-- The farm's post-process pass (shaders/farm.glsl): sun tint and light
-- shafts, bloom, glimmer and the day-cycle tint, in one pass over a 320x320
-- canvas owned by the farm. FarmState draws the scene into FarmShader.canvas
-- and then draws that canvas through FarmShader.shader into push's canvas.
--
-- Safe fallback: reading the source, compiling the shader and creating the
-- canvas are each wrapped in pcall. On any failure (or with the --no-shader
-- launch flag) FarmShader.enabled stays false, the reason is logged once, and
-- the farm draws straight through with a translucent tint overlay instead.
-- The backrooms never uses this pass.

FarmShader = {
    path = 'shaders/farm.glsl',
    forceOff = false,       -- --no-shader
    sourceOverride = nil,   -- test hook: GLSL used instead of the file
    tried = false,
    enabled = false,
    reason = nil,
    shader = nil,
    canvas = nil,
}

local function fail(reason)
    FarmShader.enabled = false
    FarmShader.shader, FarmShader.canvas = nil, nil
    FarmShader.reason = reason
    print('[farm-shader] disabled, drawing without the post-process pass: ' .. tostring(reason))
    return false
end

-- Compiles the shader and creates the canvas once; returns whether the pass
-- is available. Safe to call every frame.
function FarmShader.init()
    if FarmShader.tried then return FarmShader.enabled end
    FarmShader.tried = true
    if FarmShader.forceOff then return fail('turned off (--no-shader)') end

    local source = FarmShader.sourceOverride
    if not source then
        local ok, text = pcall(function() return love.filesystem.read(FarmShader.path) end)
        if not ok or type(text) ~= 'string' then return fail('cannot read ' .. FarmShader.path .. ': ' .. tostring(text)) end
        source = text
    end
    local ok, shader = pcall(love.graphics.newShader, source)
    if not ok or not shader then return fail('compile failed: ' .. tostring(shader)) end
    local okc, canvas = pcall(love.graphics.newCanvas, VIRTUAL_WIDTH, VIRTUAL_HEIGHT)
    if not okc or not canvas then return fail('canvas creation failed: ' .. tostring(canvas)) end
    canvas:setFilter('nearest', 'nearest')

    FarmShader.shader, FarmShader.canvas = shader, canvas
    FarmShader.enabled = true
    print('[farm-shader] post-process pass enabled')
    return true
end

-- Forget the compiled pass so the next init() tries again (tests, settings).
function FarmShader.reset()
    FarmShader.tried, FarmShader.enabled, FarmShader.reason = false, false, nil
    FarmShader.shader, FarmShader.canvas = nil, nil
end

-- Perceived brightness of a tint, mapped to 0 (night) .. 1 (day).
local function daylightOf(tint)
    local l = 0.299 * tint[1] + 0.587 * tint[2] + 0.114 * tint[3]
    return math.max(0, math.min(1, (l - 0.68) / 0.3))
end

-- The uniform values for a frame. `opts.time` (s), `opts.tint` {r, g, b};
-- `opts.plain` zeroes the tint and every lighting effect (used during the
-- break, so corruption and the fade stay crisp and fully visible).
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
        shaftStrength = plain and 0 or FARM_FX_SHAFT,
        shaftSpeed = FARM_FX_SHAFT_SPEED,
        bloomStrength = plain and 0 or FARM_FX_BLOOM,
        bloomThreshold = FARM_FX_BLOOM_THRESHOLD,
        glimmerStrength = plain and 0 or FARM_FX_GLIMMER,
        glimmerThreshold = FARM_FX_GLIMMER_THRESHOLD,
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
