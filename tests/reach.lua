-- Reachability search over the real PlayerController and Room code, used by
-- tests/run.lua and tests/reachability.lua (needs the game loaded, i.e. after
-- dofile('main.lua'); love.load()).
--
-- It is a breadth-first search over controller states: from the spawn, every
-- action (idle, or one of `yaws` directions held as forward / strafe / back
-- input) is simulated for `duration` seconds at `dt` steps; resulting states
-- are de-duplicated on a grid (`cell` metres, plus climbing / grounded
-- flags). Falling below the room's killZ ends that branch (the game would
-- respawn the player at the spawn, which is already explored). The search
-- stops as soon as any state touches the exit.
--
-- This is coarse: it explores the movement the controller allows, sampled,
-- not every possible input sequence. A `false` result means "no sampled path
-- reached the exit", which, together with the hand geometry reasoning in
-- design.md, is the evidence that a seed combination does not solve a room.
local Reach = {}

-- Builds `data` (a BACKROOMS_ROOMS entry) with `crops` = {plotId = seedType}
-- already fully grown and in effect. Returns the Room.
function Reach.roomWith(data, crops)
    local room = Room(data)
    for plotId, seedType in pairs(crops or {}) do
        local plot = room:plotById(plotId)
        assert(plot, 'no plot ' .. tostring(plotId))
        local crop = plot.crop
        if not crop or crop.type ~= seedType then
            crop = Crop(seedType, plot)
            -- replace any demo crop of another type
            for i, c in ipairs(room.crops) do
                if c == plot.crop then table.remove(room.crops, i) break end
            end
            plot.crop = crop
            room.crops[#room.crops + 1] = crop
        end
        crop.progress, crop.grown, crop.active = 1, true, true
        crop:applyScale()
    end
    return room
end

local function snapshot(p)
    return {p.x, p.y, p.z, p.vz, p.grounded, p.climbing}
end

local function restore(s)
    local p = PlayerController(s[1], s[2], s[3])
    p.vz, p.grounded, p.climbing = s[4], s[5], s[6]
    return p
end

-- Returns reached (bool), info {cells, frames, at = {x, y, z} | nil,
-- maxX, maxZ}. opts: cell (0.4), duration (0.25), dt (1/20), yaws (8),
-- noStrafe (skip strafe actions: with 8+ yaws they repeat forward moves; used by the
-- level sweep for speed), cap (60000 cells), start {x, y, z} (default the room spawn), goal (optional
-- function(player, pmin, pmax) -> bool replacing the exit test; it is called
-- after every simulated frame and may keep state to need several targets).
function Reach.search(room, opts)
    opts = opts or {}
    local cell = opts.cell or 0.4
    local duration = opts.duration or 0.25
    local dt = opts.dt or 1 / 20
    local yaws = opts.yaws or 8
    local cap = opts.cap or 60000
    local frames = math.floor(duration / dt + 0.5)
    local colliders, climbables = room:solidColliders(), room:climbVolumes()
    local s = opts.start or room.spawn

    local actions = {{forward = 0, strafe = 0, dir = 0}}
    for k = 0, yaws - 1 do
        local d = 2 * math.pi * k / yaws
        actions[#actions + 1] = {forward = 1, strafe = 0, dir = d}
        if not opts.noStrafe then actions[#actions + 1] = {forward = 0, strafe = 1, dir = d} end
        actions[#actions + 1] = {forward = -1, strafe = 0, dir = d}
    end

    local function key(p)
        return string.format('%d,%d,%d,%s,%s', math.floor(p.x / cell + 0.5), math.floor(p.y / cell + 0.5),
            math.floor(p.z / cell + 0.5), tostring(p.climbing ~= nil), tostring(p.grounded))
    end

    local goal = opts.goal or function(_, pmin, pmax) return room:overlapsExit(pmin, pmax) end
    local p0 = PlayerController(s[1], s[2], s[3])
    for _ = 1, 20 do p0:update(dt, {}, 0, colliders, climbables) end
    do
        local pmin, pmax = p0:bounds()
        if goal(p0, pmin, pmax) then
            return true, {cells = 1, frames = 0, at = {p0.x, p0.y, p0.z}, maxX = p0.x, maxZ = p0.z}
        end
    end
    local seen, count = {[key(p0)] = true}, 1
    local frontier = {snapshot(p0)}
    local info = {cells = 1, frames = 0, maxX = p0.x, maxZ = p0.z}

    while #frontier > 0 do
        local nextFrontier = {}
        for _, st in ipairs(frontier) do
            -- only boxes within reach of this state matter for one action (<= 0.25 s of
            -- movement); culling them is exact and makes the sweep several times faster
            local near = {}
            for _, c in ipairs(colliders) do
                if c.max[1] >= st[1] - 3 and c.min[1] <= st[1] + 3 and c.max[2] >= st[2] - 3 and c.min[2] <= st[2] + 3
                    and c.max[3] >= st[3] - 3 and c.min[3] <= st[3] + 4 then near[#near + 1] = c end
            end
            for _, a in ipairs(actions) do
                local p = restore(st)
                local alive = true
                for _ = 1, frames do
                    p:update(dt, a, a.dir, near, climbables)
                    info.frames = info.frames + 1
                    if p.z < room.killZ then alive = false break end
                    local pmin, pmax = p:bounds()
                    if goal(p, pmin, pmax) then
                        info.cells, info.at = count, {p.x, p.y, p.z}
                        return true, info
                    end
                end
                if alive then
                    local k = key(p)
                    if not seen[k] then
                        seen[k] = true
                        count = count + 1
                        nextFrontier[#nextFrontier + 1] = snapshot(p)
                        if p.x > info.maxX then info.maxX = p.x end
                        if p.z > info.maxZ then info.maxZ = p.z end
                        if count > cap then
                            info.cells = count
                            error('reachability search exceeded ' .. cap .. ' cells')
                        end
                    end
                end
            end
        end
        frontier = nextFrontier
    end
    info.cells = count
    return false, info
end

-- Every assignment of {nil, beanstalk, pumpkin, vine} to the room's plots,
-- as a list of {plotId = seedType} tables (demo crops stay as data says
-- unless overridden; an unassigned demo plot keeps its frozen demo crop).
function Reach.assignments(data)
    local ids = {}
    for i, p in ipairs(data.plots or {}) do ids[#ids + 1] = p.id or ('plot' .. i) end
    local out = {{}}
    for _, id in ipairs(ids) do
        local grown = {}
        for _, a in ipairs(out) do
            grown[#grown + 1] = a
            for _, t in ipairs(SEED_TYPES) do
                local b = {}
                for k, v in pairs(a) do b[k] = v end
                b[id] = t
                grown[#grown + 1] = b
            end
        end
        out = grown
    end
    return out
end

function Reach.describe(crops)
    local parts = {}
    for k, v in pairs(crops) do parts[#parts + 1] = k .. '=' .. v end
    table.sort(parts)
    return #parts > 0 and table.concat(parts, ' ') or '(no crops)'
end

return Reach
