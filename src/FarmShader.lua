-- The farm's look pipeline (shaders/farm.glsl + shaders/farm_blur.glsl):
-- tilt-shift depth of field around the farmer, restrained bloom, golden sun
-- glow and shafts, glimmer, saturation/vignette grade and the day-cycle
-- tint. FarmState draws the scene into FarmShader.canvas (320x320) and calls
-- FarmShader.present(uniforms), which draws it through the pipeline into
-- push's canvas. The HUD and all text are drawn after it, never through it.
--
-- Design departure (see design.md, decision 7): the design called for one
-- pass. The look review asked for readable depth of field and soft bloom,
-- which one pass over a nearest canvas cannot give, so this is a small
-- multi-pass chain over downsampled canvases:
--   scene 320 -> blur H 160 -> blur V 160 (nearTex, soft)
--             -> blur H 80  -> blur V 80  (farTex, softer)
--   (far and bloom each get a second H/V round for a wide, smooth falloff;
--    the composite also upsamples them with a 4-tap bilinear kernel)
--   nearTex   -> thresholded blur H 80 -> blur V 80 x2 (bloomTex)
--   composite: scene + nearTex/farTex/bloomTex through farm.glsl.
-- Six 160/80 px passes plus one 320 px composite per frame.
--
-- Safe fallback: reading the sources, compiling both shaders and creating
-- every canvas are each wrapped in pcall. On any failure (or with the
-- --no-shader launch flag) FarmShader.enabled stays false, the reason is
-- logged once, and the farm draws straight through with a translucent tint
-- overlay instead. The backrooms never uses this pass.

FarmShader = {
    path = 'shaders/farm.glsl',
    blurPath = 'shaders/farm_blur.glsl',
    forceOff = false,       -- --no-shader
    sourceOverride = nil,   -- test hook: composite GLSL used instead of the file
    tried = false,
    enabled = false,
    reason = nil,
    shader = nil,           -- composite
    blur = nil,             -- separable blur step
    canvas = nil,           -- the sharp scene (320x320)
    buffers = nil,          -- {halfA, halfB, quarterA, quarterB, bloomA, bloomB}
}

local function fail(reason)
    FarmShader.enabled = false
    FarmShader.shader, FarmShader.blur, FarmShader.canvas, FarmShader.buffers = nil, nil, nil, nil
    FarmShader.reason = reason
    print('[farm-shader] disabled, drawing without the post-process pass: ' .. tostring(reason))
    return false
end

local function readSource(path)
    local ok, text = pcall(function() return love.filesystem.read(path) end)
    if not ok or type(text) ~= 'string' then return nil, 'cannot read ' .. path .. ': ' .. tostring(text) end
    return text
end

local function newCanvas(w, h, filter)
    local ok, canvas = pcall(love.graphics.newCanvas, w, h)
    if not ok or not canvas then return nil, 'canvas creation failed: ' .. tostring(canvas) end
    canvas:setFilter(filter, filter == 'nearest' and 'nearest' or 'linear')
    return canvas
end

-- Compiles both shaders and creates the canvases once; returns whether the
-- pipeline is available. Safe to call every frame.
function FarmShader.init()
    if FarmShader.tried then return FarmShader.enabled end
    FarmShader.tried = true
    if FarmShader.forceOff then return fail('turned off (--no-shader)') end

    local source, err = FarmShader.sourceOverride, nil
    if not source then
        source, err = readSource(FarmShader.path)
        if not source then return fail(err) end
    end
    local blurSource
    blurSource, err = readSource(FarmShader.blurPath)
    if not blurSource then return fail(err) end
    local ok, shader = pcall(love.graphics.newShader, source)
    if not ok or not shader then return fail('compile failed: ' .. tostring(shader)) end
    local okb, blur = pcall(love.graphics.newShader, blurSource)
    if not okb or not blur then return fail('blur compile failed: ' .. tostring(blur)) end

    -- the scene: sampled 1:1 by the composite (exact texels), linear when
    -- minified into the half-size blur
    local canvas
    canvas, err = newCanvas(VIRTUAL_WIDTH, VIRTUAL_HEIGHT, 'linear')
    if not canvas then return fail(err) end
    canvas:setFilter('linear', 'nearest')
    local buffers = {}
    local sizes = {2, 2, 4, 4, 4, 4}
    for i, d in ipairs(sizes) do
        buffers[i], err = newCanvas(math.ceil(VIRTUAL_WIDTH / d), math.ceil(VIRTUAL_HEIGHT / d), 'linear')
        if not buffers[i] then return fail(err) end
    end

    FarmShader.shader, FarmShader.blur, FarmShader.canvas, FarmShader.buffers = shader, blur, canvas, buffers
    FarmShader.enabled = true
    print('[farm-shader] post-process pipeline enabled')
    return true
end

-- One blur step: draws `src` (scaled to fit) into `dst` through the blur
-- shader along `axis` ('h' or 'v'), with an optional bright-pass threshold.
local function blurStep(src, dst, axis, threshold)
    local sw, sh = src:getDimensions()
    local dw, dh = dst:getDimensions()
    love.graphics.setCanvas(dst)
    love.graphics.clear(0, 0, 0, 1)
    local blur = FarmShader.blur
    -- step in source uv: about one destination texel
    local step = axis == 'h' and {1 / dw, 0} or {0, 1 / dh}
    if blur:hasUniform('dir') then blur:send('dir', step) end
    if blur:hasUniform('threshold') then blur:send('threshold', threshold or 0) end
    love.graphics.setShader(blur)
    love.graphics.draw(src, 0, 0, 0, dw / sw, dh / sh)
end

-- Runs the chain on FarmShader.canvas and draws the composite into the
-- canvas that was active when called (push's), with `values` as uniforms.
function FarmShader.present(values)
    local target = love.graphics.getCanvas()
    local b = FarmShader.buffers
    local scene = FarmShader.canvas
    love.graphics.push('all')
    love.graphics.origin()
    love.graphics.setBlendMode('replace', 'premultiplied')
    love.graphics.setColor(1, 1, 1, 1)
    blurStep(scene, b[2], 'h')            -- 320 -> 160
    blurStep(b[2], b[1], 'v')             -- nearTex
    blurStep(b[1], b[4], 'h')             -- 160 -> 80
    blurStep(b[4], b[3], 'v')
    blurStep(b[3], b[4], 'h')             -- second Gaussian round: wider, no blocks
    blurStep(b[4], b[3], 'v')             -- farTex
    blurStep(b[1], b[6], 'h', values.bloomThreshold)
    blurStep(b[6], b[5], 'v')
    blurStep(b[5], b[6], 'h')
    blurStep(b[6], b[5], 'v')             -- bloomTex
    love.graphics.pop()

    love.graphics.setCanvas(target)
    FarmShader.send(values)
    FarmShader.send({nearTex = b[1], farTex = b[3], bloomTex = b[5]})
    love.graphics.setShader(FarmShader.shader)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(scene, 0, 0)
    love.graphics.setShader()
end

-- Forget the compiled pass so the next init() tries again (tests, settings).
function FarmShader.reset()
    FarmShader.tried, FarmShader.enabled, FarmShader.reason = false, false, nil
    FarmShader.shader, FarmShader.blur, FarmShader.canvas, FarmShader.buffers = nil, nil, nil, nil
end

-- Perceived brightness of a tint, mapped to 0 (night) .. 1 (day).
local function daylightOf(tint)
    local l = 0.299 * tint[1] + 0.587 * tint[2] + 0.114 * tint[3]
    return math.max(0, math.min(1, (l - 0.68) / 0.3))
end

-- The uniform values for a frame. `opts.time` (s), `opts.tint` {r, g, b},
-- `opts.focusY` (uv y of the farmer); `opts.plain` zeroes the tint and every
-- lighting, depth and grading effect (used during the break, so corruption
-- and the fade stay crisp and fully visible).
function FarmShader.uniforms(opts)
    local tint = opts.tint or {1, 1, 1}
    local plain = opts.plain
    return {
        time = opts.time or 0,
        texel = {1 / VIRTUAL_WIDTH, 1 / VIRTUAL_HEIGHT},
        dayTint = plain and {1, 1, 1} or {tint[1], tint[2], tint[3]},
        daylight = plain and 0 or daylightOf(tint),
        sunColor = FARM_FX_SUN_COLOR,
        sunStrength = plain and 0 or FARM_FX_SUN,
        sunGlow = plain and 0 or FARM_FX_SUN_GLOW,
        sunPos = FARM_FX_SUN_POS,
        shaftStrength = plain and 0 or FARM_FX_SHAFT,
        shaftSpeed = FARM_FX_SHAFT_SPEED,
        bloomStrength = plain and 0 or FARM_FX_BLOOM,
        bloomThreshold = FARM_FX_BLOOM_THRESHOLD,
        glimmerStrength = plain and 0 or FARM_FX_GLIMMER,
        glimmerThreshold = FARM_FX_GLIMMER_THRESHOLD,
        tiltStrength = plain and 0 or FARM_FX_TILT,
        focusY = opts.focusY or 0.5,
        focusHalf = FARM_FX_FOCUS_HALF,
        focusRamp = FARM_FX_FOCUS_RAMP,
        saturation = plain and 0 or FARM_FX_SATURATION,
        vignette = plain and 0 or FARM_FX_VIGNETTE,
    }
end

-- Sends `values` to the shader, skipping uniforms the compiler removed.
function FarmShader.send(values)
    local shader = FarmShader.shader
    if not shader then return end
    for name, v in pairs(values) do
        if shader:hasUniform(name) then shader:send(name, v) end
    end
end

-- Day-cycle tint at `phase` (0..1), interpolated between FARM_DAY_TINTS.
function FarmDayTint(phase)
    phase = phase % 1
    local keys = FARM_DAY_TINTS
    for i = 1, #keys - 1 do
        local a, b = keys[i], keys[i + 1]
        if phase >= a[1] and phase <= b[1] then
            local k = (b[1] > a[1]) and (phase - a[1]) / (b[1] - a[1]) or 0
            return {a[2][1] + (b[2][1] - a[2][1]) * k, a[2][2] + (b[2][2] - a[2][2]) * k,
                a[2][3] + (b[2][3] - a[2][3]) * k}
        end
    end
    local last = keys[#keys][2]
    return {last[1], last[2], last[3]}
end
