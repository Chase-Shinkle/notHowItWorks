-- Data-driven backrooms room builder.
--
-- A room is described by a plain table (see src/rooms.lua) and Room(data)
-- turns it into g3d models, colliders, plots, an exit trigger and billboards.
-- Adding or cutting a room is a data change only.
--
-- Room data fields (positions are box centres, sizes are full extents, in
-- metres, z up):
--   id, name           strings
--   spawn              {x, y, z, direction}: feet position and camera yaw
--   boxes              list of {pos = {x,y,z}, size = {sx,sy,sz},
--                        kind = 'floor'|'wall'|'ceiling'|'solid' (default 'solid'),
--                        texture = gTextures key (optional), color = {r,g,b,a} (optional),
--                        collide = false (optional, decorative only)}
--   exit               {pos = {x,y,z}, size = {sx,sy,sz}}: trigger volume; drawn as a
--                        glowing marker, never collides
--   plots              list of {id, pos = {x,y,z}, dir = '+x'|'-x'|'+y'|'-y', reach = m} (optional):
--                        fixed planting plots, drawn as soil pads; `pos` is the
--                        surface the crop grows from, `dir` (default '+x') is the
--                        way a vine grows (src/Crop.lua), `reach` (default
--                        BACKROOMS_PLANT_RANGE) the horizontal planting distance
--   allotment          {beanstalk = n, pumpkin = n, vine = n}: the room's seeds
--   billboards         list of Billboard defs (optional)
--   demoCrops          optional list of {plot = <plot id>, seed = <type>, progress = 0..1}:
--                        crops already part-grown when the room is (re)built. A
--                        demo crop is frozen and not usable until a seed of its
--                        type is planted on its plot, which finishes its growth
--                        (the tutorial room)
--   pickups            optional list of {pos = {x,y,z}, seed = <type>, tier = 'critical'|'extra'}:
--                        collectible seeds (src/LevelGen.lua); walking within
--                        BACKROOMS_PICKUP_RADIUS adds the seed (BackroomsState)
--   seedTypes          optional list of the seed types the room uses (HUD and
--                        seed selection); default: those with an allotment
--   killZ              optional, default BACKROOMS_KILL_Z
--   lights, lighting   optional look data (src/BackroomsLook.lua): ceiling
--                        fixtures and a lighting preset. Absent: fixtures on a
--                        grid under the ceiling and a preset picked from `id`.
--                        Purely visual; never read by gameplay.
--
-- Boxes are always axis-aligned: g3d.collisions ignores model rotation.

Room = Class{}

-- Default look per box kind: texture key and flat backrooms-yellow colour.
-- `color` tints a flat placeholder texture; `textured` is the (lighter) tint
-- used when the real texture loaded, since vertex colours multiply it.
ROOM_BOX_STYLES = {
    floor = {texture = 'floor', color = {0.62, 0.56, 0.32, 1}, textured = {0.85, 0.8, 0.6, 1}},
    wall = {texture = 'wall', color = {0.86, 0.8, 0.46, 1}, textured = {1, 1, 1, 1}},
    ceiling = {texture = 'ceiling', fallbackTexture = 'wall', color = {0.93, 0.9, 0.72, 1}, textured = {1, 1, 0.92, 1}},
    solid = {texture = 'wall', color = {0.78, 0.72, 0.42, 1}, textured = {0.9, 0.88, 0.8, 1}},
}
ROOM_EXIT_COLOR = {0.45, 1, 0.55, 0.9}
ROOM_BASEBOARD_HEIGHT, ROOM_BASEBOARD_DEPTH = 0.14, 0.03
ROOM_BASEBOARD_COLOR = {0.78, 0.7, 0.5, 1}

-- Material themes: a consistent wall/floor/ceiling set. Texture values are
-- gTextures keys; `tint` multiplies a loaded texture, `fallbackColor` is the
-- flat colour used when a texture is missing or a placeholder. A box takes its
-- theme from `box.theme`, else `data.theme`; no theme keeps ROOM_BOX_STYLES.
MATERIAL_THEMES = {
    level0 = {wall = 'wall-chevron', floor = 'floor-carpet', ceiling = 'ceiling-grid',
        tint = {1, 1, 1, 1}, fallbackColor = {0.84, 0.78, 0.38, 1}},
    stripe = {wall = 'wall-stripe', floor = 'floor-damp', ceiling = 'ceiling-grid',
        tint = {0.95, 0.95, 0.9, 1}, fallbackColor = {0.8, 0.74, 0.44, 1}},
    classic = {wall = 'wall', floor = 'floor', ceiling = 'ceiling',
        tint = {1, 1, 1, 1}, fallbackColor = {0.86, 0.8, 0.46, 1}},
}
MATERIAL_THEME_NAMES = {'level0', 'stripe', 'classic'}
-- Obstacle modules (pit/gap/ledge surfaces) and plots use fixed high-contrast
-- tints on a plain texture, independent of the theme (cool slate vs. yellow rooms).
ROOM_OBSTACLE_COLORS = {floor = {0.3, 0.42, 0.62, 1}, solid = {0.78, 0.36, 0.2, 1}}
ROOM_PLOT_TINT = {1.15, 0.8, 0.6, 1}
ROOM_PLOT_SIZE = 1.2
ROOM_TEXTURE_TILE = 2      -- metres per texture repeat on box faces

-- Per-face shade so flat-coloured boxes still read as 3D without lighting.
local function faceShade(nx, ny, nz)
    if nz > 0.5 then return 1 end
    if nz < -0.5 then return 0.7 end
    if math.abs(nx) > 0.5 then return 0.85 end
    return 0.92
end

-- Box vertices with per-face shading and world-size UVs (so textures tile
-- instead of stretching). Built from NewBoxVerts; that helper is unchanged.
function NewRoomBoxVerts(sx, sy, sz, color)
    local verts = NewBoxVerts(sx, sy, sz, color)
    for _, v in ipairs(verts) do
        local s = faceShade(v[6], v[7], v[8])
        v[9], v[10], v[11] = v[9] * s, v[10] * s, v[11] * s
        local a, b
        if math.abs(v[6]) > 0.5 then a, b = v[2], v[3]
        elseif math.abs(v[7]) > 0.5 then a, b = v[1], v[3]
        else a, b = v[1], v[2] end
        v[4], v[5] = a / ROOM_TEXTURE_TILE, -b / ROOM_TEXTURE_TILE
    end
    return verts
end

-- Boxes for a closed rectangular room: floor top at z = 0, ceiling at
-- z = height, walls of `thickness` just outside the [-w/2, w/2] x [-d/2, d/2]
-- interior. A convenience for room data.
function Room.shellBoxes(w, d, height, thickness)
    local t = thickness or 0.2
    return {
        {kind = 'floor', pos = {0, 0, -t / 2}, size = {w + 2 * t, d + 2 * t, t}},
        {kind = 'ceiling', pos = {0, 0, height + t / 2}, size = {w + 2 * t, d + 2 * t, t}},
        {kind = 'wall', pos = {w / 2 + t / 2, 0, height / 2}, size = {t, d + 2 * t, height}},
        {kind = 'wall', pos = {-w / 2 - t / 2, 0, height / 2}, size = {t, d + 2 * t, height}},
        {kind = 'wall', pos = {0, d / 2 + t / 2, height / 2}, size = {w, t, height}},
        {kind = 'wall', pos = {0, -d / 2 - t / 2, height / 2}, size = {w, t, height}},
    }
end

-- Concatenate box lists (for data: Room.joinBoxes(Room.shellBoxes(...), {...})).
function Room.joinBoxes(...)
    local out = {}
    for i = 1, select('#', ...) do
        for _, b in ipairs(select(i, ...) or {}) do out[#out + 1] = b end
    end
    return out
end

local function isVec3(v)
    return type(v) == 'table' and type(v[1]) == 'number' and type(v[2]) == 'number' and type(v[3]) == 'number'
end

-- Checks a room data table; returns true or false, message.
function Room.validate(data)
    local id = tostring(type(data) == 'table' and data.id or '?')
    local function fail(msg) return false, 'room ' .. id .. ': ' .. msg end
    if type(data) ~= 'table' then return fail('data must be a table') end
    if type(data.spawn) ~= 'table' or not isVec3(data.spawn) then return fail('spawn {x, y, z, direction} required') end
    if type(data.boxes) ~= 'table' or #data.boxes == 0 then return fail('at least one box required') end
    for i, b in ipairs(data.boxes) do
        if not isVec3(b.pos) or not isVec3(b.size) then return fail('box ' .. i .. ' needs pos and size') end
        for k = 1, 3 do
            if b.size[k] <= 0 then return fail('box ' .. i .. ' size must be positive') end
        end
        if b.kind and not ROOM_BOX_STYLES[b.kind] then return fail('box ' .. i .. ' unknown kind ' .. tostring(b.kind)) end
        if b.theme and not MATERIAL_THEMES[b.theme] then return fail('box ' .. i .. ' unknown theme ' .. tostring(b.theme)) end
    end
    if type(data.exit) ~= 'table' or not isVec3(data.exit.pos) or not isVec3(data.exit.size) then
        return fail('exit {pos, size} required')
    end
    if type(data.allotment) ~= 'table' then return fail('allotment required') end
    for seedType, n in pairs(data.allotment) do
        local known = false
        for _, t in ipairs(SEED_TYPES) do if t == seedType then known = true end end
        if not known then return fail('unknown seed type ' .. tostring(seedType)) end
        if type(n) ~= 'number' or n < 0 or n % 1 ~= 0 then return fail('allotment ' .. seedType .. ' must be a whole number >= 0') end
    end
    local plotIds = {}
    for i, p in ipairs(data.plots or {}) do
        if not isVec3(p.pos) then return fail('plot ' .. i .. ' needs pos') end
        if p.reach ~= nil and (type(p.reach) ~= 'number' or p.reach <= 0) then
            return fail('plot ' .. i .. ' reach must be a positive number')
        end
        if p.dir ~= nil and not CROP_DIRECTIONS[p.dir] then
            return fail('plot ' .. i .. ' unknown dir ' .. tostring(p.dir))
        end
        local pid = p.id or ('plot' .. i)
        if plotIds[pid] then return fail('duplicate plot id ' .. tostring(pid)) end
        plotIds[pid] = true
    end
    local demoPlots = {}
    for i, d in ipairs(data.demoCrops or {}) do
        if not plotIds[d.plot] then return fail('demo crop ' .. i .. ' unknown plot ' .. tostring(d.plot)) end
        if demoPlots[d.plot] then return fail('demo crop ' .. i .. ' plot ' .. tostring(d.plot) .. ' used twice') end
        demoPlots[d.plot] = true
        if not CROP_DEFS[d.seed] then return fail('demo crop ' .. i .. ' unknown seed ' .. tostring(d.seed)) end
        if type(d.progress) ~= 'number' or d.progress < 0 or d.progress >= 1 then
            return fail('demo crop ' .. i .. ' progress must be in [0, 1)')
        end
    end
    for i, b in ipairs(data.billboards or {}) do
        if not isVec3(b.pos) or not b.texture then return fail('billboard ' .. i .. ' needs pos and texture') end
    end
    local function knownSeed(t)
        for _, s in ipairs(SEED_TYPES) do if s == t then return true end end
        return false
    end
    if data.seedTypes ~= nil then
        if type(data.seedTypes) ~= 'table' then return fail('seedTypes must be a list') end
        for i, t in ipairs(data.seedTypes) do
            if not knownSeed(t) then return fail('seedTypes ' .. i .. ' unknown seed type ' .. tostring(t)) end
        end
    end
    for i, p in ipairs(data.pickups or {}) do
        if not isVec3(p.pos) then return fail('pickup ' .. i .. ' needs pos') end
        if not knownSeed(p.seed) then return fail('pickup ' .. i .. ' unknown seed ' .. tostring(p.seed)) end
        if p.tier ~= 'critical' and p.tier ~= 'extra' then
            return fail('pickup ' .. i .. ' tier must be critical or extra')
        end
    end
    return BackroomsLook.validate(data)
end

local function bounds(pos, size)
    return {pos[1] - size[1] / 2, pos[2] - size[2] / 2, pos[3] - size[3] / 2},
           {pos[1] + size[1] / 2, pos[2] + size[2] / 2, pos[3] + size[3] / 2}
end

local function texture(key, fallbackKey)
    local tex = gTextures[key or fallbackKey] or gTextures[fallbackKey]
    if tex and tex.setWrap then tex:setWrap('repeat', 'repeat') end
    return tex
end

function Room:init(data)
    local ok, err = Room.validate(data)
    if not ok then error(err, 2) end

    self.data = data
    self.id = data.id
    self.name = data.name or data.id
    self.spawn = {data.spawn[1], data.spawn[2], data.spawn[3], data.spawn[4] or 0}
    self.killZ = data.killZ or BACKROOMS_KILL_Z
    self.allotment = CopySeeds(data.allotment)
    self.seedTypes = data.seedTypes
    -- collectible seeds, rebuilt with the room (so reset respawns them)
    self.pickups = {}
    for _, p in ipairs(data.pickups or {}) do
        self.pickups[#self.pickups + 1] = {
            pos = {p.pos[1], p.pos[2], p.pos[3]}, seed = p.seed, tier = p.tier,
            billboard = Billboard({texture = 'seedbag-' .. p.seed, pos = p.pos, height = BACKROOMS_PICKUP_HEIGHT}),
        }
    end

    -- solid geometry
    self.models = {}       -- {model, color} drawn opaque
    self.colliders = {}
    for _, b in ipairs(data.boxes) do
        local kind = b.kind or 'solid'
        local style = ROOM_BOX_STYLES[kind]
        local theme = MATERIAL_THEMES[b.theme or data.theme or '']
        local tex, color
        if b.obstacle and ROOM_OBSTACLE_COLORS[kind] then
            tex, color = gTextures['white'] or texture(nil, style.texture), ROOM_OBSTACLE_COLORS[kind]
        elseif theme and not b.texture and not b.color then
            -- solid blocks use the wall texture
            local key = theme[kind == 'solid' and 'wall' or kind]
            tex = gTextures[key]
            if tex and not Assets.isPlaceholder(tex) then
                texture(key)
                local shade = style.textured
                color = {theme.tint[1] * shade[1], theme.tint[2] * shade[2], theme.tint[3] * shade[3], 1}
            else
                tex, color = texture(nil, style.texture), theme.fallbackColor
            end
        else
            tex = texture(b.texture, style.texture)
            if not tex and style.fallbackTexture then tex = texture(nil, style.fallbackTexture) end
            color = b.color
                or ((style.textured and tex and not Assets.isPlaceholder(tex)) and style.textured or style.color)
        end
        local verts = NewRoomBoxVerts(b.size[1], b.size[2], b.size[3], color)
        local model = g3d.newModel(verts, tex, {b.pos[1], b.pos[2], b.pos[3]})
        self.models[#self.models + 1] = model
        if b.collide ~= false then
            local min, max = bounds(b.pos, b.size)
            self.colliders[#self.colliders + 1] = {
                verts = verts, transform = model, min = min, max = max, kind = b.kind or 'solid',
            }
        end
    end

    -- generated levels: one merged, render-only beige baseboard along both
    -- faces of every wall (no collider, no data change)
    if data.meta then
        local trim = {}
        for _, b in ipairs(data.boxes) do
            if b.kind == 'wall' and not b.obstacle and b.size[3] > 1 then
                local alongX = b.size[1] >= b.size[2]
                local th = alongX and b.size[2] or b.size[1]
                local z = b.pos[3] - b.size[3] / 2 + ROOM_BASEBOARD_HEIGHT / 2
                for side = -1, 1, 2 do
                    local ox = alongX and 0 or side * (th / 2 + ROOM_BASEBOARD_DEPTH / 2)
                    local oy = alongX and side * (th / 2 + ROOM_BASEBOARD_DEPTH / 2) or 0
                    local sx = alongX and b.size[1] or ROOM_BASEBOARD_DEPTH
                    local sy = alongX and ROOM_BASEBOARD_DEPTH or b.size[2]
                    for _, v in ipairs(NewRoomBoxVerts(sx, sy, ROOM_BASEBOARD_HEIGHT, ROOM_BASEBOARD_COLOR)) do
                        v[1], v[2], v[3] = v[1] + b.pos[1] + ox, v[2] + b.pos[2] + oy, v[3] + z
                        trim[#trim + 1] = v
                    end
                end
            end
        end
        if #trim > 0 then
            self.models[#self.models + 1] = g3d.newModel(trim, gTextures['white'] or texture(nil, 'floor'), {0, 0, 0})
        end
    end

    -- exit trigger and its marker
    local e = data.exit
    local emin, emax = bounds(e.pos, e.size)
    self.exit = {pos = {e.pos[1], e.pos[2], e.pos[3]}, size = {e.size[1], e.size[2], e.size[3]}, min = emin, max = emax}
    self.exitModel = g3d.newModel(NewRoomBoxVerts(e.size[1], e.size[2], e.size[3], ROOM_EXIT_COLOR),
        gTextures['white'] or texture(nil, 'floor'), {e.pos[1], e.pos[2], e.pos[3]})

    -- fixed plots: flat soil pads just above the surface they sit on
    self.plots = {}
    for i, p in ipairs(data.plots or {}) do
        local size = p.size or ROOM_PLOT_SIZE
        local model = g3d.newModel(NewBoxVerts(size, size, 0.02, ROOM_PLOT_TINT), gTextures['plot'],
            {p.pos[1], p.pos[2], p.pos[3] + 0.011})
        self.plots[#self.plots + 1] = {
            id = p.id or ('plot' .. i), pos = {p.pos[1], p.pos[2], p.pos[3]}, dir = p.dir or '+x',
            reach = p.reach or BACKROOMS_PLANT_RANGE,
            model = model, crop = nil,
        }
    end

    self.billboards = {}
    for _, def in ipairs(data.billboards or {}) do
        self.billboards[#self.billboards + 1] = Billboard(def)
    end

    -- crops: demo crops are rebuilt from data every time the room is built,
    -- so a reset returns them to their starting state
    self.demoCrops = data.demoCrops
    self.crops = {}
    for _, d in ipairs(data.demoCrops or {}) do
        local plot = self:plotById(d.plot)
        local crop = Crop(d.seed, plot, {progress = d.progress})
        crop.demo = true
        plot.crop = crop
        self.crops[#self.crops + 1] = crop
    end

    self:setLighting(data.lighting)
end

-- Look data (visual only): resolves the lighting preset, the fixture list
-- (the room's `lights`, or ceiling fixtures placed by BackroomsLook.autoLights)
-- and, when the look shader is on, the fixture panel and contact-shadow models.
-- `lighting` is a preset name, an override table or nil (the room's default).
function Room:setLighting(lighting)
    BackroomsLook.init()
    self.lighting = BackroomsLook.resolveLighting(lighting, self.id)
    self.lights = self.data.lights or BackroomsLook.autoLights(self.data.boxes, self.lighting, self.id)
    self.fixtures, self.blobs = {}, {}
    if not BackroomsLook.enabled then return end
    local white = gTextures['white'] or texture(nil, 'floor')
    for _, l in ipairs(self.lights) do
        local mode = l.mode or 'steady'
        local color = mode == 'dead' and {0.32, 0.31, 0.27, 1} or {1, 0.97, 0.82, 1}
        local z = (l.panelZ or l.pos[3] + 0.12) - 0.02
        self.fixtures[#self.fixtures + 1] = {
            light = l,
            model = g3d.newModel(NewBoxVerts(BACKROOMS_FIXTURE_SIZE[1], BACKROOMS_FIXTURE_SIZE[2], 0.04, color),
                white, {l.pos[1], l.pos[2], z}),
        }
    end
    -- contact shadows under floor-standing billboards (pickups and crops are
    -- handled each frame in drawShadows)
    for _, b in ipairs(self.billboards) do
        self:addBlob(b, b.x, b.y, b.z + 0.012, math.max(0.5, b.width * 1.1))
    end
end

-- One shadow blob (a thin textured quad) keyed by `key`; no-op without the image.
function Room:addBlob(key, x, y, z, size)
    local img = BackroomsLook.shadowImage
    if not img then return nil end
    local blob = {key = key, size = size,
        model = g3d.newModel(NewBoxVerts(size, size, 0.002, {1, 1, 1, 1}), img, {x, y, z})}
    self.blobs[#self.blobs + 1] = blob
    return blob
end

-- Soft shadows on the floor under billboards, pickups and crops: drawn after
-- the opaque geometry, depth-tested but not depth-writing, before the sprites.
function Room:drawShadows()
    if not BackroomsLook.shadowImage then return end
    local have = {}
    for _, b in ipairs(self.blobs) do have[b.key] = true end
    for _, p in ipairs(self.pickups) do
        if not have[p] then self:addBlob(p, p.pos[1], p.pos[2], p.pos[3] + 0.015, 0.55); have[p] = true end
    end
    for _, c in ipairs(self.crops) do
        if not have[c] and c.plot then
            self:addBlob(c, c.plot.pos[1], c.plot.pos[2], c.plot.pos[3] + 0.03, 1.1); have[c] = true
        end
    end
    love.graphics.setDepthMode('lequal', false)
    love.graphics.setColor(1, 1, 1, 1)
    local live = {}
    for _, b in ipairs(self.blobs) do
        local key = b.key
        local alive = true
        if key.pos and key.seed then alive = false; for _, p in ipairs(self.pickups) do if p == key then alive = true end end
        elseif key.plot and key.type then alive = key.plot.crop == key end
        if alive then b.model:draw() end
    end
    love.graphics.setDepthMode('lequal', true)
end

-- Removes and returns the first pickup within `radius` (horizontally, and
-- BACKROOMS_PLANT_HEIGHT vertically) of the feet position, or nil.
function Room:collectPickup(x, y, z, radius)
    radius = radius or BACKROOMS_PICKUP_RADIUS
    for i, p in ipairs(self.pickups) do
        local dx, dy = p.pos[1] - x, p.pos[2] - y
        if dx * dx + dy * dy <= radius * radius and math.abs(p.pos[3] - z) <= BACKROOMS_PLANT_HEIGHT then
            table.remove(self.pickups, i)
            return p
        end
    end
    return nil
end

function Room:plotById(id)
    for _, plot in ipairs(self.plots) do
        if plot.id == id then return plot end
    end
    return nil
end

-- The plot the player at feet position (x, y, z) can plant on: the nearest
-- plot within its own `reach` (default BACKROOMS_PLANT_RANGE) horizontally
-- and BACKROOMS_PLANT_HEIGHT vertically, or nil. When several are in reach
-- the nearest wins, whatever their reaches. Fixed plots only: there is no
-- planting anywhere else.
function Room:nearestPlot(x, y, z)
    local best, bestD
    for _, plot in ipairs(self.plots) do
        local dx, dy = plot.pos[1] - x, plot.pos[2] - y
        local d = math.sqrt(dx * dx + dy * dy)
        if d <= plot.reach and math.abs(plot.pos[3] - z) <= BACKROOMS_PLANT_HEIGHT
            and (not bestD or d < bestD) then
            best, bestD = plot, d
        end
    end
    return best
end

-- Can `seedType` be planted on `plot` with `seeds`? Returns true, or false and
-- a reason: 'no-plot' | 'no-seeds' | 'occupied' | 'growing' | 'wrong-seed'.
-- A plot holding a frozen demo crop takes one seed of the demo's type, which
-- finishes the demo (the tutorial); any other plot must be empty.
function Room:canPlant(plot, seedType, seeds)
    if not plot then return false, 'no-plot' end
    if not CROP_DEFS[seedType] then return false, 'no-seeds' end
    local crop = plot.crop
    if crop then
        if not crop.demo then return false, 'occupied' end
        if crop.timer or crop.grown then return false, 'growing' end
        if crop.type ~= seedType then return false, 'wrong-seed' end
    end
    if ((seeds or {})[seedType] or 0) < 1 then return false, 'no-seeds' end
    return true
end

-- Plants one `seedType` seed (taken from `seeds`) on `plot`, growing in Timer
-- group `group`. Returns ok, crop or false, reason (see canPlant); nothing is
-- consumed on failure.
function Room:plant(plot, seedType, seeds, group)
    local ok, reason = self:canPlant(plot, seedType, seeds)
    if not ok then return false, reason end
    seeds[seedType] = seeds[seedType] - 1
    local crop = plot.crop
    if not crop then
        crop = Crop(seedType, plot)
        plot.crop = crop
        self.crops[#self.crops + 1] = crop
    end
    crop:grow(group)
    return true, crop
end

-- The nearest plot in reach (as nearestPlot) that holds a crop, or nil.
function Room:nearestCropPlot(x, y, z)
    local best, bestD
    for _, plot in ipairs(self.plots) do
        if plot.crop then
            local dx, dy = plot.pos[1] - x, plot.pos[2] - y
            local d = math.sqrt(dx * dx + dy * dy)
            if d <= plot.reach and math.abs(plot.pos[3] - z) <= BACKROOMS_PLANT_HEIGHT
                and (not bestD or d < bestD) then
                best, bestD = plot, d
            end
        end
    end
    return best
end

-- Is the player box (pmin, pmax) on top of, inside or touching `crop`'s full
-- volume? A little slack above (standing on it) and around (climbing).
function Room.playerOnCrop(crop, pmin, pmax)
    local lo = {crop.min[1] - BACKROOMS_UPROOT_MARGIN, crop.min[2] - BACKROOMS_UPROOT_MARGIN, crop.min[3] - BACKROOMS_UPROOT_MARGIN}
    local hi = {crop.max[1] + BACKROOMS_UPROOT_MARGIN, crop.max[2] + BACKROOMS_UPROOT_MARGIN, crop.max[3] + BACKROOMS_UPROOT_MARGIN}
    return PlayerController.boxesOverlap(pmin, pmax, lo, hi)
end

-- Removes the crop on `plot`, freeing it and cancelling any pending growth. The
-- player box (pmin, pmax) must be clear of it. Returns true, or false and a
-- reason: 'no-plot' | 'empty' | 'demo' | 'standing'. Nothing changes on failure.
-- On success the second value is the removed crop (crop.type is the seed to
-- refund; the caller does the refunding).
function Room:uproot(plot, pmin, pmax)
    if not plot then return false, 'no-plot' end
    local crop = plot.crop
    if not crop then return false, 'empty' end
    if crop.demo then return false, 'demo' end
    if pmin and Room.playerOnCrop(crop, pmin, pmax) then return false, 'standing' end
    crop:remove()
    plot.crop = nil
    for i, c in ipairs(self.crops) do
        if c == crop then table.remove(self.crops, i); break end
    end
    return true, crop
end

-- Per-frame crop bookkeeping with the player's bounds (see Crop:update).
function Room:updateCrops(pmin, pmax)
    for _, crop in ipairs(self.crops) do crop:update(pmin, pmax) end
end

-- Solid colliders this frame: the room boxes plus every active solid crop.
function Room:solidColliders()
    local list = {}
    for i, c in ipairs(self.colliders) do list[i] = c end
    for _, crop in ipairs(self.crops) do
        if crop.active and crop.collider then list[#list + 1] = crop.collider end
    end
    return list
end

-- Climbable volumes this frame: every active beanstalk.
function Room:climbVolumes()
    local list = {}
    for _, crop in ipairs(self.crops) do
        if crop.active and crop.climbVolume then list[#list + 1] = crop.climbVolume end
    end
    return list
end

-- Is a box (min, max) touching the exit trigger?
function Room:overlapsExit(min, max)
    return PlayerController.boxesOverlap(min, max, self.exit.min, self.exit.max)
end

-- Opaque geometry first, then (look on) fixture panels, plots, crops and the
-- exit marker, shadow blobs, then billboards sorted far to near (camera at cx,
-- cy). With the look shader on, room surfaces are lit and fogged; plots,
-- crops, pickups and the exit get BackroomsLook's `gameplayFloor` minimum
-- light so they stay readable in every preset. With it off this is the plain
-- unlit render.
function Room:draw(cx, cy)
    love.graphics.setColor(1, 1, 1, 1)
    local cam = g3d.camera and g3d.camera.position
    local t = BackroomsLook.now()
    local look = BackroomsLook.begin(self, cx, cy, cam and cam[3] or 0, t)
    for _, model in ipairs(self.models) do model:draw(look) end
    if look then
        for _, f in ipairs(self.fixtures) do
            local mode = f.light.mode or 'steady'
            BackroomsLook.set('emissive', mode == 'dead' and 0 or math.min(1, BackroomsLook.activeIntensity(
                {mode = mode, intensity = 1, phase = f.light.phase}, t)))
            f.model:draw(look)
        end
        BackroomsLook.set('emissive', 0)
        BackroomsLook.set('litFloor', self.lighting.gameplayFloor)
    end
    for _, plot in ipairs(self.plots) do plot.model:draw(look) end
    for _, crop in ipairs(self.crops) do crop:draw(look) end
    self.exitModel:draw(look)
    if look then self:drawShadows(); BackroomsLook.drawShafts(self, cx, cy) end
    Billboard.drawAll(self.billboards, cx, cy, look)
    -- pickups bob gently; the billboard is lifted, not the pickup position
    local clock = love.timer and love.timer.getTime and love.timer.getTime() or 0
    local pickupBoards = {}
    for i, p in ipairs(self.pickups) do
        local b = p.billboard
        b.model:setTranslation(p.pos[1], p.pos[2], p.pos[3] + 0.35 + 0.1 * math.sin(clock * 3 + i))
        pickupBoards[i] = b
    end
    Billboard.drawAll(pickupBoards, cx, cy, look)
    if look then BackroomsLook.set('litFloor', 0) end
    love.graphics.setColor(1, 1, 1, 1)
end
