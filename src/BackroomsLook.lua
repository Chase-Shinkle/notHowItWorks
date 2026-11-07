-- The backrooms' look pipeline: shaders/backrooms.glsl lights room geometry
-- per pixel (ambient + nearest fixtures with falloff + fog), flicker is a pure
-- function of time, and contact-shadow blobs ground objects. Purely visual:
-- gameplay code never reads anything here.
--
-- Safe fallback (design decision 8): reading the source and compiling the
-- shader are wrapped in pcall. On failure, or with `--no-shader`, enabled
-- stays false, the reason is logged once and Room draws the plain textured
-- boxes exactly as before (no fixtures, no shadows). Section 3 adds the
-- post-process rung of the ladder (canvases); this file has no canvas yet.
--
-- Room data it understands (validated in Room.validate):
--   lights    list of {pos = {x,y,z}, color = {r,g,b}, intensity, radius,
--               mode = 'steady'|'flicker'|'buzz'|'dead', phase}
--   lighting  a preset name (BACKROOMS_LIGHT_PRESETS) or a table of
--               overrides {preset = name, ambient, fogColor, fogDensity, ...}
-- Rooms without `lights` get ceiling fixtures placed on a grid
-- (BackroomsLook.autoLights); rooms without `lighting` get a preset picked
-- from their id.

BackroomsLook = {
    path = 'shaders/backrooms.glsl',
    forceOff = false,       -- --no-shader
    quality = 'high',       -- 'high' | 'medium' | 'low' (--quality=low): low drops flicker
    sourceOverride = nil,   -- test hook: GLSL used instead of the file
    timeOverride = nil,     -- screenshot/perf harness: fixed clock (s)
    tried = false,
    enabled = false,
    reason = nil,
    shader = nil,
    shadowImage = nil,
}

local function fail(reason)
    BackroomsLook.enabled, BackroomsLook.shader, BackroomsLook.shadowImage = false, nil, nil
    BackroomsLook.reason = reason
    print('[backrooms-look] disabled, drawing the plain backrooms render: ' .. tostring(reason))
    return false
end

-- Soft radial alpha disc for contact shadows (black, alpha falls to 0 at the rim).
local function newShadowImage()
    local size = 32
    local ok, data = pcall(love.image.newImageData, size, size)
    if not ok or not data then return nil end
    data:mapPixel(function(x, y)
        local dx, dy = (x + 0.5) / size * 2 - 1, (y + 0.5) / size * 2 - 1
        local r = math.sqrt(dx * dx + dy * dy)
        local a = math.max(0, 1 - r)
        a = a * a * (3 - 2 * a)
        return 0, 0, 0, a * BACKROOMS_SHADOW_ALPHA
    end)
    local okImg, img = pcall(love.graphics.newImage, data)
    if not okImg or not img then return nil end
    img:setFilter('linear', 'linear')
    return img
end

-- Compiles the shader once; returns whether the look is available. Safe to
-- call every frame.
function BackroomsLook.init()
    if BackroomsLook.tried then return BackroomsLook.enabled end
    BackroomsLook.tried = true
    if BackroomsLook.forceOff then return fail('turned off (--no-shader)') end

    local source = BackroomsLook.sourceOverride
    if not source then
        local ok, text = pcall(function() return love.filesystem.read(BackroomsLook.path) end)
        if not ok or type(text) ~= 'string' then
            return fail('cannot read ' .. BackroomsLook.path .. ': ' .. tostring(text))
        end
        source = text
    end
    -- g3d's vertex shader first, then the pixel code (as Billboard's alpha shader does)
    local ok, shader = pcall(love.graphics.newShader, g3d.shaderpath, source)
    if not ok or not shader then return fail('compile failed: ' .. tostring(shader)) end

    BackroomsLook.shader = shader
    BackroomsLook.shadowImage = newShadowImage()   -- nil is fine: no blobs
    BackroomsLook.enabled = true
    print('[backrooms-look] enabled (quality ' .. BackroomsLook.quality .. ')')
    return true
end

-- Forget the compiled shader so the next init() tries again (tests).
function BackroomsLook.reset()
    BackroomsLook.tried, BackroomsLook.enabled, BackroomsLook.reason = false, false, nil
    BackroomsLook.shader, BackroomsLook.shadowImage = nil, nil
end

function BackroomsLook.setQuality(q)
    for _, known in ipairs(BACKROOMS_LOOK_QUALITIES) do
        if known == q then BackroomsLook.quality = q; return true end
    end
    return false
end

function BackroomsLook.now()
    if BackroomsLook.timeOverride then return BackroomsLook.timeOverride end
    return love.timer and love.timer.getTime and love.timer.getTime() or 0
end

-- Flicker ----------------------------------------------------------------------

-- Deterministic hash of an integer to [0, 1).
local function hash01(n)
    local x = math.sin(n * 12.9898 + 78.233) * 43758.5453
    return x - math.floor(x)
end
BackroomsLook.hash01 = hash01

-- Brightness multiplier of a fixture at time `t` (s) with a per-light `phase`.
-- A pure function of its arguments: steady = 1, dead = 0, flicker = mostly 1
-- with short dips to 0.15-0.65 in 1/7 s slots, buzz = a fast shallow ripple.
-- (Quality 'low' is applied by the caller: see activeIntensity.)
function BackroomsLook.flicker(mode, t, phase)
    phase = phase or 0
    if mode == 'dead' then return 0 end
    if mode == 'flicker' then
        local slot = math.floor(t * 7 + phase * 13)
        if hash01(slot) < 0.2 then return 0.15 + 0.5 * hash01(slot + 91) end
        return 1
    elseif mode == 'buzz' then
        return 0.84 + 0.16 * math.abs(math.sin(t * 43 + phase * 6.28))
    end
    return 1
end

-- Intensity of `light` right now, with the quality setting applied (low = no
-- flicker or buzz; dead stays dead).
function BackroomsLook.activeIntensity(light, t)
    local mode = light.mode or 'steady'
    if mode == 'dead' then return 0 end
    local base = light.intensity or 1
    if BackroomsLook.quality == 'low' then return base end
    return base * BackroomsLook.flicker(mode, t, light.phase)
end

-- Presets and lights -------------------------------------------------------------

local function hashString(s)
    local h = 0
    for i = 1, #s do h = (h * 31 + s:byte(i)) % 1000003 end
    return h
end

-- Preset name for a room with no `lighting`.
function BackroomsLook.defaultPresetName(roomId)
    local fixed = BACKROOMS_LIGHTING_BY_ROOM_ID[roomId]
    if fixed then return fixed end
    local pool = BACKROOMS_LIGHTING_DEFAULT_POOL
    return pool[hashString(tostring(roomId)) % #pool + 1]
end

-- The preset table for room data `lighting` (a name, an override table, or
-- nil) and the room id. Returns a fresh table {name, ambient, ...}.
function BackroomsLook.resolveLighting(lighting, roomId)
    local name, overrides
    if type(lighting) == 'string' then name = lighting
    elseif type(lighting) == 'table' then name, overrides = lighting.preset, lighting end
    name = name or BackroomsLook.defaultPresetName(roomId)
    local preset = BACKROOMS_LIGHT_PRESETS[name] or BACKROOMS_LIGHT_PRESETS['dim']
    local out = {name = name}
    for k, v in pairs(preset) do out[k] = v end
    for k, v in pairs(overrides or {}) do
        if k ~= 'preset' then out[k] = v end
    end
    return out
end

local function rangeOk(v) return type(v) == 'number' and v > 0 end

-- Checks the `lights` and `lighting` fields of room data; true, or false and a message.
function BackroomsLook.validate(data)
    if data.lights ~= nil then
        if type(data.lights) ~= 'table' then return false, 'lights must be a list' end
        for i, l in ipairs(data.lights) do
            local p = l.pos
            if type(p) ~= 'table' or type(p[1]) ~= 'number' or type(p[2]) ~= 'number' or type(p[3]) ~= 'number' then
                return false, 'light ' .. i .. ' needs pos'
            end
            if l.intensity ~= nil and not rangeOk(l.intensity) then return false, 'light ' .. i .. ' intensity must be positive' end
            if l.radius ~= nil and not rangeOk(l.radius) then return false, 'light ' .. i .. ' radius must be positive' end
            if l.mode ~= nil and l.mode ~= 'steady' and l.mode ~= 'flicker' and l.mode ~= 'buzz' and l.mode ~= 'dead' then
                return false, 'light ' .. i .. ' unknown mode ' .. tostring(l.mode)
            end
            if l.color ~= nil and (type(l.color) ~= 'table' or type(l.color[1]) ~= 'number'
                or type(l.color[2]) ~= 'number' or type(l.color[3]) ~= 'number') then
                return false, 'light ' .. i .. ' color must be {r, g, b}'
            end
        end
    end
    local lt = data.lighting
    if lt ~= nil then
        local name = type(lt) == 'string' and lt or (type(lt) == 'table' and lt.preset)
        if type(lt) ~= 'string' and type(lt) ~= 'table' then return false, 'lighting must be a preset name or a table' end
        if name ~= nil and not BACKROOMS_LIGHT_PRESETS[name] then return false, 'unknown lighting preset ' .. tostring(name) end
    end
    return true
end

-- Ceiling fixtures for a room with no `lights`: on a grid under every ceiling
-- box, spaced about BACKROOMS_LIGHT_SPACING, skipping boxes with no free
-- height beneath. Which are lit, flickering, buzzing or dead comes from the
-- preset and a hash of the room id and the fixture's index, so it is
-- reproducible and independent of layout RNG. Returns a list of light tables
-- (see the data format above; `panelZ` is the ceiling underside it hangs from).
function BackroomsLook.autoLights(boxes, preset, roomId)
    local lights = {}
    local seed = hashString(tostring(roomId))
    for _, b in ipairs(boxes) do
        if b.kind == 'ceiling' and b.collide ~= false then
            local nx = math.max(1, math.floor(b.size[1] / BACKROOMS_LIGHT_SPACING + 0.5))
            local ny = math.max(1, math.floor(b.size[2] / BACKROOMS_LIGHT_SPACING + 0.5))
            local zUnder = b.pos[3] - b.size[3] / 2
            for i = 1, nx do
                for j = 1, ny do
                    local x = b.pos[1] - b.size[1] / 2 + (i - 0.5) * b.size[1] / nx
                    local y = b.pos[2] - b.size[2] / 2 + (j - 0.5) * b.size[2] / ny
                    local n = #lights + 1
                    local r = hash01(seed + n * 7.31)
                    local mode = 'steady'
                    if (n - 1) % preset.litEvery ~= 0 then mode = 'dead'
                    elseif r < preset.flicker then mode = 'flicker'
                    elseif r < preset.flicker + preset.buzz then mode = 'buzz' end
                    lights[n] = {pos = {x, y, zUnder - 0.12}, color = BACKROOMS_LIGHT_COLOR,
                        intensity = preset.intensity, radius = BACKROOMS_LIGHT_RADIUS, mode = mode,
                        phase = hash01(seed + n * 3.17), panelZ = zUnder}
                end
            end
        end
    end
    return lights
end

-- The nearest `n` live (not dead) lights to (x, y, z), nearest first, as
-- indices into `lights`. Pure; the per-frame upload uses it.
function BackroomsLook.nearestLights(lights, x, y, z, n)
    local picked = {}
    for i, l in ipairs(lights) do
        if (l.mode or 'steady') ~= 'dead' then
            local dx, dy, dz = l.pos[1] - x, l.pos[2] - y, l.pos[3] - z
            picked[#picked + 1] = {i = i, d = dx * dx + dy * dy + dz * dz}
        end
    end
    table.sort(picked, function(a, b) if a.d ~= b.d then return a.d < b.d end return a.i < b.i end)
    local out = {}
    for k = 1, math.min(n or BACKROOMS_LOOK_MAX_LIGHTS, #picked) do out[k] = picked[k].i end
    return out
end

-- Uploads the per-frame uniforms for `room` seen from (cx, cy, cz) at time t.
-- Returns the shader, or nil when the look is off.
function BackroomsLook.begin(room, cx, cy, cz, t)
    if not BackroomsLook.enabled then return nil end
    local shader = BackroomsLook.shader
    local lighting = room.lighting
    local pos, color, radius = {}, {}, {}
    local picked = BackroomsLook.nearestLights(room.lights, cx, cy, cz, BACKROOMS_LOOK_MAX_LIGHTS)
    for k = 1, BACKROOMS_LOOK_MAX_LIGHTS do
        local l = room.lights[picked[k]]
        if l then
            local c = l.color or BACKROOMS_LIGHT_COLOR
            local s = BackroomsLook.activeIntensity(l, t)
            pos[k], color[k], radius[k] = l.pos, {c[1] * s, c[2] * s, c[3] * s}, l.radius or BACKROOMS_LIGHT_RADIUS
        else
            pos[k], color[k], radius[k] = {0, 0, 0}, {0, 0, 0}, 1
        end
    end
    local values = {
        camPos = {cx, cy, cz}, ambient = lighting.ambient, lightCount = #picked,
        lightPos = pos, lightColor = color, lightRadius = radius,
        fogColor = lighting.fogColor, fogDensity = lighting.fogDensity,
        litFloor = 0, emissive = 0,
    }
    BackroomsLook.lastUniforms = values
    for name, v in pairs(values) do
        if shader:hasUniform(name) then
            if name == 'lightPos' or name == 'lightColor' or name == 'lightRadius' then
                shader:send(name, unpack(v))     -- array uniforms: one argument per element
            else shader:send(name, v) end
        end
    end
    return shader
end

-- Sets one uniform (e.g. litFloor or emissive) between draws, if present.
function BackroomsLook.set(name, value)
    local shader = BackroomsLook.shader
    if shader and shader:hasUniform(name) then shader:send(name, value) end
end
