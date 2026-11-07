-- Backrooms dressing: furniture, tools and abandoned-object groupings placed in
-- generated levels (openspec backrooms-visual-atmosphere, section 5).
--
-- Dressing.apply(data, seed) appends non-solid billboards to data.billboards.
-- It only reads the finished layout and uses its own RNG stream, so the layout
-- (boxes, plots, pickups, exit, spawn) is identical with or without dressing.
-- Props hug the walls of non-module cells and avoid every exclusion zone.
Dressing = {}

local CELL, DOOR = LEVELGEN_CELL, LEVELGEN_DOOR

-- name -> {texture, height, tags (room types it suits), solid = false}.
-- Textures reuse the loaded farm props; tags are room types: filler, hall,
-- dead, nook, loop.
-- Heights are deliberately small (decor, not furniture) and none uses the
-- seed-bag look: no sacks/crate, so nothing is mistaken for a collectible.
PROP_CATALOGUE = {
    bucket = {texture = 'bucket',      height = 0.35, tags = {'filler', 'hall', 'loop'}},
    well   = {texture = 'well',        height = 1.0,  tags = {'hall'}},
    fence  = {texture = 'fence',       height = 0.55, tags = {'hall', 'loop', 'dead'}},
    shovel = {texture = 'tool-shovel', height = 0.6,  tags = {'dead', 'nook', 'filler', 'loop'}},
    can    = {texture = 'tool-can',    height = 0.35, tags = {'filler', 'hall', 'loop'}},
    sickle = {texture = 'tool-sickle', height = 0.4,  tags = {'dead', 'nook'}},
}
-- Storytelling groupings.
PROP_GROUPS = {   -- each: list of {prop, dx, dy} offsets
    {name = 'abandoned-camp', props = {{'bucket', 0, 0}, {'sickle', -0.5, 0.4}}},
    {name = 'lone-tool',      props = {{'shovel', 0, 0}}},
    {name = 'spilled-store',  props = {{'bucket', 0, 0}, {'can', 0.2, 0.7}}},
}

-- Room type of a meta cell.
function Dressing.roomType(c)
    if c.nook then return 'nook' end
    if c.loop then return 'loop' end
    if c.kind == 'filler' then return 'filler' end
    if c.deadEnd then return 'dead' end
    return 'hall'
end

-- Names of catalogue props allowed in a room type, sorted (deterministic).
function Dressing.propsFor(roomType)
    local out = {}
    for name, p in pairs(PROP_CATALOGUE) do
        for _, t in ipairs(p.tags) do if t == roomType then out[#out + 1] = name; break end end
    end
    table.sort(out)
    return out
end

local function dist2(ax, ay, bx, by) return (ax - bx) ^ 2 + (ay - by) ^ 2 end

-- Exclusion zones as circles {x, y, r}: pickups, exit, spawn, existing
-- billboards (nook sacks), and every doorway. Module cells are skipped whole.
function Dressing.zones(data)
    local z = {}
    for _, p in ipairs(data.pickups or {}) do z[#z + 1] = {p.pos[1], p.pos[2], 1.3} end
    for _, p in ipairs(data.plots or {}) do z[#z + 1] = {p.pos[1], p.pos[2], 3} end
    if data.exit then z[#z + 1] = {data.exit.pos[1], data.exit.pos[2], 1.8} end
    if data.spawn then z[#z + 1] = {data.spawn[1], data.spawn[2], 2.2} end
    for _, b in ipairs(data.billboards or {}) do z[#z + 1] = {b.pos[1], b.pos[2], 1.2} end
    for _, p in ipairs(data.meta and data.meta.pillars or {}) do z[#z + 1] = {p.x, p.y, 1.0} end
    return z
end

local function blocked(zones, x, y, pad)
    for _, zz in ipairs(zones) do
        if dist2(x, y, zz[1], zz[2]) < (zz[3] + pad) ^ 2 then return true end
    end
    return false
end

function Dressing.apply(data, seed)
    local meta = data.meta
    local rng = LevelGen.rng(seed * 31 + 977)   -- own stream, not the layout's
    local zones = Dressing.zones(data)
    local byKey = {}
    for _, c in ipairs(meta.cells) do byKey[c.cx .. ',' .. c.cy] = c end
    -- doorway centres (both sides of each door edge)
    local doors = {}
    for e, t in pairs(meta.edges) do
        if t == 'door' then
            local ax, ay, bx, by = e:match('^(-?%d+),(-?%d+)|(-?%d+),(-?%d+)$')
            ax, ay, bx, by = tonumber(ax), tonumber(ay), tonumber(bx), tonumber(by)
            if ax == bx then   -- vertical neighbours: door on a y wall
                doors[#doors + 1] = {ax * CELL + CELL / 2, math.max(ay, by) * CELL - CELL / 2}
            else
                doors[#doors + 1] = {math.max(ax, bx) * CELL, ay * CELL}
            end
        end
    end
    local doorR = DOOR / 2 + 1.0
    local count, groups = 0, 0
    local placed = {}
    local function free(x, y, c)
        if blocked(zones, x, y, 0) then return false end
        for _, d in ipairs(doors) do
            if dist2(x, y, d[1], d[2]) < doorR ^ 2 then return false end
        end
        for _, p in ipairs(placed) do
            if dist2(x, y, p[1], p[2]) < 0.8 ^ 2 then return false end
        end
        local X0, Y0 = c.cx * CELL, c.cy * CELL - CELL / 2
        return x > X0 + 0.5 and x < X0 + CELL - 0.5 and y > Y0 + 0.5 and y < Y0 + CELL - 0.5
    end
    local function put(name, x, y, c)
        local p = PROP_CATALOGUE[name]
        data.billboards[#data.billboards + 1] = {texture = p.texture, height = p.height,
            pos = {x, y, c.elev}, prop = name, dressing = true}
        placed[#placed + 1] = {x, y}
        count = count + 1
    end
    local grouped = 0
    for _, c in ipairs(meta.cells) do
        if c.kind ~= 'module' then
            local rt = Dressing.roomType(c)
            local names = Dressing.propsFor(rt)
            local X0, Y0 = c.cx * CELL, c.cy * CELL - CELL / 2
            -- candidate spots hugging the cell's walls (inset 0.8 m)
            local spots = {}
            for t = 0.8, CELL - 0.79, 1.5 do
                spots[#spots + 1] = {X0 + t, Y0 + 0.8}
                spots[#spots + 1] = {X0 + t, Y0 + CELL - 0.8}
                spots[#spots + 1] = {X0 + 0.8, Y0 + t}
                spots[#spots + 1] = {X0 + CELL - 0.8, Y0 + t}
            end
            rng:shuffle(spots)
            local want = (rt == 'hall' and rng:chance(0.5)) and 1 or 0
            local made = 0
            -- one storytelling grouping per ~2 cells, never in fillers beside spawn
            if rng:chance(rt == 'filler' and 0.15 or 0.5) then
                local g = rng:pick(PROP_GROUPS)
                for _, s in ipairs(spots) do
                    local ok = true
                    for _, gp in ipairs(g.props) do
                        if not free(s[1] + gp[2], s[2] + gp[3], c) then ok = false; break end
                    end
                    if ok then
                        for _, gp in ipairs(g.props) do put(gp[1], s[1] + gp[2], s[2] + gp[3], c) end
                        groups = groups + 1
                        grouped = grouped + 1
                        break
                    end
                end
            end
            for _, s in ipairs(spots) do
                if made >= want then break end
                if free(s[1], s[2], c) then
                    put(rng:pick(names), s[1], s[2], c)
                    made = made + 1
                end
            end
        end
    end
    meta.dressing = {props = count, groups = groups}
    return data
end
