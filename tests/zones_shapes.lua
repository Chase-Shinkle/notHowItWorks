-- Room shapes (openspec backrooms-zones-variety-audio 4.1-4.3). Standalone, like tests/maze_branches.lua:
--   love tests/love_runner tests/zones_shapes.lua   (or luajit tests/zones_shapes.lua)
-- Env: SHAPE_SEEDS (100 seeds per difficulty), SHAPE_PHYS (max pillared rooms walked physically, default 12).
package.path = './?.lua;./?/init.lua;' .. package.path
local realPrint = print
local mock = dofile('tests/mock_love.lua')
mock.install()
arg = {}
dofile('main.lua')
love.load()
print = realPrint
local Reach = dofile('tests/reach.lua')

local N = tonumber(os.getenv('SHAPE_SEEDS')) or 100
local PHYS = tonumber(os.getenv('SHAPE_PHYS')) or 12
local fails = 0
local function bad(msg) fails = fails + 1; print('FAIL ' .. msg) end
local function key(cx, cy) return cx .. ',' .. cy end
local CELL = LEVELGEN_CELL

local seen, levels, physDone = {}, 0, 0
local distinctHist, maxDistinct, pillaredRooms = {}, {}, 0
local SIDES = {{1, 0}, {-1, 0}, {0, 1}, {0, -1}}

local function signature(m)
    local out = {}
    for _, r in ipairs(m.rooms) do
        local cs = {}
        for _, c in ipairs(r.cells) do cs[#cs + 1] = c[1] .. ',' .. c[2] end
        out[#out + 1] = r.shape .. ':' .. table.concat(cs, ';')
    end
    for _, c in ipairs(m.cells) do if c.shape == 'closet' then out[#out + 1] = 'closet:' .. key(c.cx, c.cy) end end
    return table.concat(out, '|')
end

for d = 1, #LEVELGEN_DIFFICULTY do
    maxDistinct[d] = 0
    for seed = 1, N do
        local data = LevelGen.generate(seed, d)
        local m, tag = data.meta, 'seed ' .. seed .. ' diff ' .. d
        levels = levels + 1
        local byKey = {}
        for _, c in ipairs(m.cells) do byKey[key(c.cx, c.cy)] = c end

        -- reproducible from the seed
        if signature(LevelGen.generate(seed, d).meta) ~= signature(m) then bad(tag .. ': shapes differ between two generations') end

        -- doorway centres (door edges) for exclusion / reach checks
        local doors = {}
        for e, t in pairs(m.edges) do
            if t == 'door' then
                local ax, ay, bx, by = e:match('^(-?%d+),(-?%d+)|(-?%d+),(-?%d+)$')
                ax, ay, bx, by = tonumber(ax), tonumber(ay), tonumber(bx), tonumber(by)
                if ax == bx then doors[#doors + 1] = {ax * CELL + CELL / 2, math.max(ay, by) * CELL - CELL / 2, e}
                else doors[#doors + 1] = {math.max(ax, bx) * CELL, ay * CELL, e} end
            end
        end

        local kinds, nKinds = {}, 0
        for shape, n in pairs(m.shapeCounts) do if n > 0 and not kinds[shape] then kinds[shape] = true; nKinds = nKinds + 1; seen[shape] = (seen[shape] or 0) + 1 end end
        distinctHist[d] = distinctHist[d] or {}
        distinctHist[d][nKinds] = (distinctHist[d][nKinds] or 0) + 1
        maxDistinct[d] = math.max(maxDistinct[d], nKinds)
        if (m.shapeCounts.hall or 0) < 1 then bad(tag .. ': no hallway cells') end

        for _, r in ipairs(m.rooms) do
            local inRoom = {}
            local first = byKey[key(r.cells[1][1], r.cells[1][2])]
            for _, rc in ipairs(r.cells) do
                local c = byKey[key(rc[1], rc[2])]
                inRoom[c] = true
                if c.room ~= r.id then bad(tag .. ': room ' .. r.id .. ' cell not tagged') end
                if c.shape ~= r.shape then bad(tag .. ': cell shape ' .. tostring(c.shape) .. ' ~= ' .. r.shape) end
                if c.kind == 'module' or c.start or c.exit or c.optional then bad(tag .. ': room contains module/start/exit cell') end
                if c.region ~= first.region or c.elev ~= first.elev then bad(tag .. ': room spans regions/elevations') end
                if c.zone ~= first.zone then bad(tag .. ': room ' .. r.id .. ' straddles zones') end
                if r.shape ~= 'room2x2' and (c.opt or 0) ~= 0 then bad(tag .. ': stamped shape inside an optional area') end
            end
            -- connected through open interior edges
            local reached, stack, nReached = {[first] = true}, {first}, 1
            while #stack > 0 do
                local c = table.remove(stack)
                for _, s in ipairs(SIDES) do
                    local nb = byKey[key(c.cx + s[1], c.cy + s[2])]
                    if nb and inRoom[nb] and not reached[nb] and m.edges[LevelGen.edgeKey(c, nb)] == 'open' then
                        reached[nb] = true; nReached = nReached + 1; stack[#stack + 1] = nb
                    end
                end
            end
            if nReached ~= #r.cells then bad(tag .. ': room ' .. r.id .. ' (' .. r.shape .. ') interior not fully open') end
            -- doors connect: some passage leaves the room
            local exitsRoom = false
            for e, t in pairs(m.edges) do
                local a, b = e:match('^(.-)|(.*)$')
                if inRoom[byKey[a]] ~= inRoom[byKey[b]] then exitsRoom = true end
            end
            if not exitsRoom and #m.cells > #r.cells then bad(tag .. ': room ' .. r.id .. ' has no passage out') end
            -- ceilings: every shape keeps headroom; the atrium is clearly higher than its surroundings
            local need = BACKROOMS_PLAYER_HEIGHT + 0.5
            for c in pairs(inRoom) do
                if c.ceil - c.elev < need then bad(tag .. ': low ceiling in ' .. r.shape) end
                if r.shape == 'atrium' and c.ceil - c.elev < LEVELGEN_CEILING + LEVELGEN_CEILING_VARIANTS[1] + ROOM_ATRIUM_CEILING_BONUS then
                    bad(tag .. ': atrium ceiling not raised')
                end
            end
            if r.shape == 'atrium' and #r.cells ~= 5 then bad(tag .. ': atrium is not a plus') end
            if r.shape == 'pillared' and #r.cells ~= 9 then bad(tag .. ': pillared hall is not 3x3') end
            if r.shape == 'roomL' and #r.cells ~= 3 then bad(tag .. ': L room has ' .. #r.cells .. ' cells') end
            if r.shape == 'room2x3' and #r.cells ~= 6 then bad(tag .. ': 2x3 size') end
        end

        -- closets: off-path dead ends, narrowed, lower ceiling
        for _, c in ipairs(m.cells) do
            if c.shape == 'closet' then
                if c.degree ~= 1 or c.onPath or c.kind ~= 'branch' or c.room or not c.inset then bad(tag .. ': bad closet at ' .. key(c.cx, c.cy)) end
                if c.ceil - c.elev < BACKROOMS_PLAYER_HEIGHT + 0.5 then bad(tag .. ': closet ceiling too low') end
            end
        end

        -- pillars
        local pillars = m.pillars
        local solidBoxes = {}
        for _, b in ipairs(data.boxes) do if b.kind == 'solid' and not b.obstacle and b.collide ~= false then solidBoxes[#solidBoxes + 1] = b end end
        for i, p in ipairs(pillars) do
            local r = m.rooms[p.room]
            if r.shape ~= 'pillared' then bad(tag .. ': pillar outside a pillared hall') end
            -- the four cells meeting at the pillar are all the hall: it stands at an interior intersection
            for _, o in ipairs({{-0.5, -0.5}, {0.5, -0.5}, {-0.5, 0.5}, {0.5, 0.5}}) do
                local cx, cy = LevelGen.cellOf(p.x + o[1], p.y + o[2])
                local c = byKey[key(cx, cy)]
                if not c or c.room ~= p.room then bad(tag .. ': pillar not interior to its hall') end
            end
            -- clearance to the hall walls: distance from the pillar edge to the nearest hall boundary
            local minX, maxX, minY, maxY = math.huge, -math.huge, math.huge, -math.huge
            for _, rc in ipairs(r.cells) do
                minX, maxX = math.min(minX, rc[1] * CELL), math.max(maxX, rc[1] * CELL + CELL)
                minY, maxY = math.min(minY, rc[2] * CELL - CELL / 2), math.max(maxY, rc[2] * CELL + CELL / 2)
            end
            local edge = math.min(p.x - p.size / 2 - minX, maxX - p.x - p.size / 2, p.y - p.size / 2 - minY, maxY - p.y - p.size / 2)
            if edge < ROOM_PILLAR_CLEARANCE then bad(tag .. ': pillar only ' .. edge .. ' m from a hall wall') end
            for j = i + 1, #pillars do
                local q = pillars[j]
                local gap = math.max(math.abs(p.x - q.x), math.abs(p.y - q.y)) - p.size
                if gap < ROOM_PILLAR_CLEARANCE then bad(tag .. ': pillars ' .. gap .. ' m apart') end
            end
            -- exclusion: pickups, plots, exit, spawn, doorways, with the player radius to spare
            local pad = p.size / 2 + BACKROOMS_PLAYER_RADIUS
            local function clear(x, y, what, extra)
                if math.abs(x - p.x) < pad + (extra or 0) and math.abs(y - p.y) < pad + (extra or 0) then bad(tag .. ': pillar blocks ' .. what) end
            end
            for _, pk in ipairs(data.pickups) do clear(pk.pos[1], pk.pos[2], 'a pickup', 0.3) end
            for _, pl in ipairs(data.plots) do clear(pl.pos[1], pl.pos[2], 'a plot', 1) end
            clear(data.exit.pos[1], data.exit.pos[2], 'the exit', 1)
            clear(data.spawn[1], data.spawn[2], 'the spawn', 1)
            for _, dr in ipairs(doors) do clear(dr[1], dr[2], 'a doorway', LEVELGEN_DOOR / 2) end
            -- it is a real solid box in the level
            local found = false
            for _, b in ipairs(solidBoxes) do
                if math.abs(b.pos[1] - p.x) < 1e-6 and math.abs(b.pos[2] - p.y) < 1e-6 and math.abs(b.size[1] - p.size) < 1e-6 then found = true end
            end
            if not found then bad(tag .. ': pillar has no solid box') end
        end
        -- no wall or solid box (other than pillars) intrudes into a hall's interior
        for _, r in ipairs(m.rooms) do
            if r.shape == 'pillared' then
                pillaredRooms = pillaredRooms + 1
                local c0 = byKey[key(r.cells[1][1], r.cells[1][2])]
                local x0, y0 = c0.cx * CELL, c0.cy * CELL - CELL / 2
                for _, b in ipairs(data.boxes) do
                    if (b.kind == 'wall' or b.kind == 'solid') and b.collide ~= false then
                        local isPillar = false
                        for _, p in ipairs(pillars) do
                            if p.room == r.id and math.abs(b.pos[1] - p.x) < 1e-6 and math.abs(b.pos[2] - p.y) < 1e-6 then isPillar = true end
                        end
                        local inside = b.pos[1] - b.size[1] / 2 > x0 + 0.3 and b.pos[1] + b.size[1] / 2 < x0 + 3 * CELL - 0.3
                            and b.pos[2] - b.size[2] / 2 > y0 + 0.3 and b.pos[2] + b.size[2] / 2 < y0 + 3 * CELL - 0.3
                        if inside and not isPillar then bad(tag .. ': stray wall/solid inside pillared hall') end
                    end
                end
                -- physics: the player can walk from the hall's middle cell to every doorway of the hall
                if physDone < PHYS then
                    physDone = physDone + 1
                    local inRoom = {}
                    for _, rc in ipairs(r.cells) do inRoom[key(rc[1], rc[2])] = true end
                    local mid = byKey[key(c0.cx + 1, c0.cy + 1)]
                    local sx, sy = LevelGen.cellCenter(mid.cx, mid.cy)
                    local room = Reach.roomWith(data, {})
                    for _, dr in ipairs(doors) do
                        local a, b = dr[3]:match('^(.-)|(.*)$')
                        if inRoom[a] ~= inRoom[b] then
                            local ok = Reach.search(room, {start = {sx, sy, c0.elev}, noStrafe = true,
                                goal = function(pl) return math.abs(pl.x - dr[1]) < 0.9 and math.abs(pl.y - dr[2]) < 0.9 end})
                            if not ok then bad(tag .. ': cannot walk from hall centre to doorway ' .. dr[3]) end
                        end
                    end
                end
            end
        end
    end
end

for _, s in ipairs(ROOM_SHAPE_NAMES) do
    if (ROOM_SHAPE_WEIGHTS[s] or 0) > 0 and not seen[s] then bad('shape never generated in ' .. levels .. ' levels: ' .. s) end
end
for d = 1, #LEVELGEN_DIFFICULTY do
    if maxDistinct[d] < 3 then bad('difficulty ' .. d .. ': no level with >= 3 distinct room shapes') end
end
local parts = {}
for _, s in ipairs(ROOM_SHAPE_NAMES) do parts[#parts + 1] = s .. '=' .. (seen[s] or 0) end
print(string.format('zones_shapes: %d levels, levels containing each shape: %s; pillared halls %d; %d physical hall walks; %d failures',
    levels, table.concat(parts, ' '), pillaredRooms, physDone, fails))
for d = 1, #LEVELGEN_DIFFICULTY do
    local h = {}
    for n, c in pairs(distinctHist[d] or {}) do h[#h + 1] = n .. ' shapes: ' .. c end
    table.sort(h)
    print('  diff ' .. d .. ' distinct shapes per level -> ' .. table.concat(h, ', '))
end
os.exit(fails == 0 and 0 or 1)
