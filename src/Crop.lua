-- Backrooms crops: the structures that seeds grow into on a room's plots.
--
-- Each seed type has a growth definition in CROP_DEFS: the full size of the
-- structure, the axes it grows along, how long it takes, and what it does once
-- grown:
--   beanstalk  tall and thin, grows up (z). Grown, it is a climbable volume:
--              walking into it while standing lets the player climb
--              (PlayerController). It is not solid.
--   pumpkin    wide and low, grows outwards and up (x, y, z). Grown, it is a
--              solid block whose top can be walked on.
--   vine       long, thin and flat, grows along the plot's direction (one
--              horizontal axis). Grown, it is a solid span whose top is level
--              with the plot, so it bridges gaps.
--
-- Growth is a knife Timer tween of `progress` (0..1) in the caller's Timer
-- group. The draw model is scaled by progress along the growth axes (model
-- scale is only used for drawing). A crop does nothing until it is fully
-- grown: while growing it is not solid and cannot be climbed.
--
-- g3d note: g3d.collisions scales vertex normals by scale_x only, so a model
-- with non-uniform scale gives wrong collision normals. Crop colliders never
-- carry a scale: their vertices are built at the full grown size and the
-- collision transform is a translation only. The scaled model is never passed
-- to g3d.collisions.

CROP_DEFS = {
    beanstalk = {
        size = {0.8, 0.8, 3.0},      -- climb volume (x, y, z)
        growAxes = {false, false, true},
        growTime = 2.5,
        climbable = true,
        solid = false,
        color = {0.3, 0.72, 0.25, 1},
    },
    pumpkin = {
        size = {2.6, 2.6, 1.0},
        growAxes = {true, true, true},
        growTime = 2,
        solid = true,
        color = {0.95, 0.55, 0.15, 1},
    },
    vine = {
        length = 6.0,                -- along the plot direction
        width = 1.2,
        thickness = 0.3,             -- top is level with the plot surface
        back = 0.6,                  -- starts this far behind the plot centre
        growAxes = 'direction',
        growTime = 2.5,
        solid = true,
        color = {0.2, 0.55, 0.22, 1},
    },
}

-- Smallest drawn scale while growing (a zero scale is degenerate).
CROP_MIN_SCALE = 0.05

-- Plot directions for vines: unit vectors in the floor plane.
CROP_DIRECTIONS = {
    ['+x'] = {1, 0}, ['-x'] = {-1, 0}, ['+y'] = {0, 1}, ['-y'] = {0, -1},
}

Crop = Class{}

-- Crop material: a small texture whose texels are drawn from the opaque pixels
-- of the type's mature crop sprite (falling back to the def colour with noise),
-- so bridges/platforms read as the crop's own skin, not a flat colour.
local materials = {}
local function cropMaterial(seedType)
    if materials[seedType] then return materials[seedType] end
    local c = CROP_DEFS[seedType].color
    local pool = {}
    local ok, data = pcall(function() return love.image.newImageData(CROP_SPRITE_PATHS[seedType]) end)
    if ok and data then
        local w, h = data:getDimensions()
        for y = 0, h - 1 do
            for x = 0, w - 1 do
                local r, g, b, a = data:getPixel(x, y)
                if a > 0.9 then pool[#pool + 1] = {r, g, b} end
            end
        end
    end
    local N = 16
    local img = love.image.newImageData(N, N)
    local rng = love.math.newRandomGenerator(#seedType * 7919)
    for y = 0, N - 1 do
        for x = 0, N - 1 do
            local r, g, b
            if #pool > 0 then
                local p = pool[rng:random(#pool)]
                r, g, b = p[1], p[2], p[3]
            else
                local k = 0.75 + 0.25 * rng:random()
                r, g, b = c[1] * k, c[2] * k, c[3] * k
            end
            -- ribs/fibres so large faces show structure
            local rib = (seedType == 'pumpkin' and x % 4 == 0) and 0.8 or (seedType ~= 'pumpkin' and y % 5 == 0) and 0.85 or 1
            img:setPixel(x, y, r * rib, g * rib, b * rib, 1)
        end
    end
    local tex = love.graphics.newImage(img)
    tex:setFilter('nearest', 'nearest')
    tex:setWrap('repeat', 'repeat')
    materials[seedType] = tex
    return tex
end

local function lerp(a, b, t) return a + (b - a) * t end

-- Box vertices for the axis-aligned box [x0, x1] x [y0, y1] x [z0, z1],
-- given relative to `origin` (so the model's translation is the origin).
local function boxVertsAt(x0, x1, y0, y1, z0, z1, color)
    local verts = NewBoxVerts(x1 - x0, y1 - y0, z1 - z0, color)
    local tu, tv = math.max(1, (x1 - x0) * 1.5), math.max(1, (z1 - z0) * 1.5)
    local cx, cy, cz = (x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2
    for _, v in ipairs(verts) do
        v[1], v[2], v[3] = v[1] + cx, v[2] + cy, v[3] + cz
        -- per-face shading, kept strong enough to survive the bright preset's light
        -- and the gameplay light floor (which otherwise wash a uniform colour flat)
        local s = v[8] > 0.5 and 0.95 or (v[8] < -0.5 and 0.45 or (math.abs(v[6]) > 0.5 and 0.62 or 0.78))
        -- tile the material by face size so it is not one stretched texel
        v[4], v[5] = v[4] * tu, v[5] * tv
        v[9], v[10], v[11] = v[9] * s, v[10] * s, v[11] * s
    end
    return verts
end

local function append(list, more)
    for _, v in ipairs(more) do list[#list + 1] = v end
    return list
end

-- World-space bounds {min}, {max} of a crop's full-grown structure on `plot`
-- ({pos = {x, y, z}, dir = '+x' ...}).
function Crop.fullBounds(seedType, plot)
    local def = CROP_DEFS[seedType]
    local px, py, pz = plot.pos[1], plot.pos[2], plot.pos[3]
    if seedType == 'vine' then
        local d = CROP_DIRECTIONS[plot.dir or '+x']
        local a = -def.back
        local b = def.length - def.back
        local hw = def.width / 2
        local zmin, zmax = pz - def.thickness, pz
        if d[1] ~= 0 then
            local x0, x1 = px + d[1] * a, px + d[1] * b
            return {math.min(x0, x1), py - hw, zmin}, {math.max(x0, x1), py + hw, zmax}
        else
            local y0, y1 = py + d[2] * a, py + d[2] * b
            return {px - hw, math.min(y0, y1), zmin}, {px + hw, math.max(y0, y1), zmax}
        end
    end
    local sx, sy, sz = def.size[1], def.size[2], def.size[3]
    return {px - sx / 2, py - sy / 2, pz}, {px + sx / 2, py + sy / 2, pz + sz}
end

-- The point the crop grows out of (its draw-model origin) and the per-axis
-- growth mask {gx, gy, gz}.
local function anchorAndAxes(seedType, plot)
    local def = CROP_DEFS[seedType]
    local px, py, pz = plot.pos[1], plot.pos[2], plot.pos[3]
    if seedType == 'vine' then
        local d = CROP_DIRECTIONS[plot.dir or '+x']
        return {px - d[1] * def.back, py - d[2] * def.back, pz}, {d[1] ~= 0, d[2] ~= 0, false}
    end
    return {px, py, pz}, def.growAxes
end

-- Visual mesh in model space (origin at the anchor). Beanstalk: a stalk with
-- leaves; pumpkin: a wide block with ribs and a stem; vine: a flat span with
-- leaves. Decorative parts stay inside the full-size bounds or are tiny.
local function buildVisualVerts(seedType, plot, anchor)
    local def = CROP_DEFS[seedType]
    local min, max = Crop.fullBounds(seedType, plot)
    local ax, ay, az = anchor[1], anchor[2], anchor[3]
    local x0, x1, y0, y1, z0, z1 = min[1] - ax, max[1] - ax, min[2] - ay, max[2] - ay, min[3] - az, max[3] - az
    local c = {1, 1, 1, 1}   -- the material texture carries the colour
    local dark = {0.7, 0.7, 0.7, 1}
    local verts = {}
    if seedType == 'beanstalk' then
        local h = z1
        append(verts, boxVertsAt(-0.15, 0.15, -0.15, 0.15, 0, h, c))
        for i = 1, 5 do
            local z = h * i / 6
            if i % 2 == 0 then
                append(verts, boxVertsAt(-0.4, 0.4, -0.12, 0.12, z, z + 0.05, dark))
            else
                append(verts, boxVertsAt(-0.12, 0.12, -0.4, 0.4, z, z + 0.05, dark))
            end
        end
    elseif seedType == 'pumpkin' then
        append(verts, boxVertsAt(x0, x1, y0, y1, z0, z1, c))
        append(verts, boxVertsAt(-0.1, 0.1, -0.1, 0.1, z1, z1 + 0.15, {0.55, 0.75, 0.3, 1}))
        append(verts, boxVertsAt(x0 - 0.01, x1 + 0.01, -0.05, 0.05, z0 + 0.05, z1 - 0.05, dark))
        append(verts, boxVertsAt(-0.05, 0.05, y0 - 0.01, y1 + 0.01, z0 + 0.05, z1 - 0.05, dark))
    else
        append(verts, boxVertsAt(x0, x1, y0, y1, z0, z1, c))
        -- leaves along the span, just above the walking surface
        local along = (x1 - x0) > (y1 - y0)
        for i = 1, 4 do
            local t = i / 5
            if along then
                local x = lerp(x0, x1, t)
                append(verts, boxVertsAt(x - 0.15, x + 0.15, y1 - 0.25, y1, z1, z1 + 0.02, dark))
            else
                local y = lerp(y0, y1, t)
                append(verts, boxVertsAt(x1 - 0.25, x1, y - 0.15, y + 0.15, z1, z1 + 0.02, dark))
            end
        end
    end
    return verts
end

-- seedType: a CROP_DEFS key. plot: a Room plot ({id, pos, dir}).
-- opts.progress: starting growth (default 0; the tutorial demo starts at 0.5).
function Crop:init(seedType, plot, opts)
    opts = opts or {}
    local def = CROP_DEFS[seedType]
    assert(def, 'unknown crop type ' .. tostring(seedType))
    self.type = seedType
    self.def = def
    self.plot = plot
    self.progress = opts.progress or 0
    self.grown = false
    self.active = false          -- grown and in effect (solid / climbable)
    self.timer = nil

    self.min, self.max = Crop.fullBounds(seedType, plot)
    self.anchor, self.axes = anchorAndAxes(seedType, plot)
    self.model = g3d.newModel(buildVisualVerts(seedType, plot, self.anchor), cropMaterial(seedType),
        {self.anchor[1], self.anchor[2], self.anchor[3]})

    if def.solid then
        -- built at the full grown size; translation only (see the g3d note)
        local cx = (self.min[1] + self.max[1]) / 2
        local cy = (self.min[2] + self.max[2]) / 2
        local cz = (self.min[3] + self.max[3]) / 2
        self.collider = {
            verts = NewBoxVerts(self.max[1] - self.min[1], self.max[2] - self.min[2], self.max[3] - self.min[3]),
            transform = {translation = {cx, cy, cz}},
            min = self.min, max = self.max, kind = 'crop', crop = self,
        }
    end
    if def.climbable then
        self.climbVolume = {min = self.min, max = self.max, crop = self}
    end
    self:applyScale()
end

-- Draw scale along each axis for the current progress.
function Crop:scale()
    local s = lerp(CROP_MIN_SCALE, 1, math.max(0, math.min(1, self.progress)))
    return self.axes[1] and s or 1, self.axes[2] and s or 1, self.axes[3] and s or 1
end

function Crop:applyScale()
    local sx, sy, sz = self:scale()
    self.model:setScale(sx, sy, sz)
end

-- Starts (or resumes) growth towards full size in Timer group `group`. The
-- tween time is the remaining fraction of the type's growTime, so the demo
-- crop (progress 0.5) finishes in half the time.
function Crop:grow(group)
    if self.timer or self.grown then return end
    local duration = math.max(0.01, self.def.growTime * (1 - self.progress))
    self.timer = Timer.tween(duration, {[self] = {progress = 1}})
        :finish(function()
            self.progress = 1
            self.grown = true
            self.timer = nil
            self:applyScale()
        end)
    if group then self.timer:group(group) end
end

-- Called every frame with the player's bounds. A grown crop takes effect only
-- once the player is clear of its full volume, so finishing growth never
-- traps the player inside a solid block.
function Crop:update(pmin, pmax)
    self:applyScale()
    if self.grown and not self.active then
        if not self.def.solid or not PlayerController.boxesOverlap(pmin, pmax, self.min, self.max, -0.01) then
            self.active = true
        end
    end
end

-- Cancels pending growth. The caller drops the crop from its room and plot;
-- a removed crop is never solid or climbable again.
function Crop:remove()
    if self.timer then self.timer:remove(); self.timer = nil end
    self.active = false
    self.removed = true
end

function Crop:draw(shader)
    self.model:draw(shader)
end
