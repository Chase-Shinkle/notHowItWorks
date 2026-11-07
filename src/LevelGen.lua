-- Seeded, always-solvable backrooms level generator (branching maze).
--
-- LevelGen.generate(seed, difficulty) returns room data in the format Room()
-- validates (src/Room.lua) plus `pickups`, `seedTypes` and a `meta` table (see
-- the meta list below). Hand-measured obstacle modules (pit, ledge, gap) sit on
-- straight passages of the maze's critical path; solving obstacle k opens
-- region k. Loops and rooms stay inside one region.
--
-- Modules are one cell long (local u 0..6 along travel) and declare their
-- geometry in LevelGen.MODULES (footprint = cells along travel; only 1 so far).
LevelGen = {}

local CELL, T, DOOR = LEVELGEN_CELL, LEVELGEN_WALL, LEVELGEN_DOOR
local VOID_Z = LEVELGEN_VOID_Z
-- section 3 tunables (defaults here to keep constants.lua conflict-free)
LEVELGEN_OPT_TYPES = LEVELGEN_OPT_TYPES or {'pit', 'gap'}   -- optional modules never rise
LEVELGEN_OPT_MAX_AREA = LEVELGEN_OPT_MAX_AREA or 8          -- most cells behind one optional module
LEVELGEN_SHORTCUT_MIN = LEVELGEN_SHORTCUT_MIN or 4          -- shortcut must skip at least this many tree steps (route z..y of >= 4 becomes 2); 6 left ~3% of candidates valid
local MODULUS = 2147483647

-- RNG -------------------------------------------------------------------------
-- Park-Miller; products stay below 2^53, so it is exact in LuaJIT and Lua 5.x
-- and independent of love.math.

local function scramble(s)
    s = math.floor(math.abs(s)) % (MODULUS - 1) + 1
    for _ = 1, 5 do s = s * 16807 % MODULUS end
    return s
end

function LevelGen.rng(seed)
    local s = scramble(seed)
    local r = {}
    function r:next()
        s = s * 16807 % MODULUS
        return s / MODULUS
    end
    function r:int(a, b) return a + math.floor(self:next() * (b - a + 1)) end
    function r:chance(p) return self:next() < p end
    function r:pick(list) return list[self:int(1, #list)] end
    function r:shuffle(list)
        for i = #list, 2, -1 do
            local j = self:int(1, i)
            list[i], list[j] = list[j], list[i]
        end
        return list
    end
    return r
end

-- Seed of level `index` of run `runSeed`; also the retry seed for a candidate.
function LevelGen.levelSeed(runSeed, index)
    local s = scramble(math.floor(runSeed) * 7919 + math.floor(index) * 104729 + 12345)
    return s
end

local function deriveSeed(seed, attempt) return LevelGen.levelSeed(seed, 7000 + attempt) end

-- Obstacle modules ------------------------------------------------------------
-- seed: crop that solves it. rise: floor elevation change across the module.
-- plot: local {x, y, z offset from the floor}. minCeiling: headroom needed
-- above the entry floor (the crop at full size).
LevelGen.MODULES = {
    -- 2.6 m wide, 1.0 m deep pit at local x 1.4..4.0; a pumpkin fills it
    pit = {footprint = 1, seed = 'pumpkin', rise = 0, minCeiling = 2.5, pitX0 = 1.4, pitX1 = 4.0, depth = 1.0,
        plot = {2.7, 0, -1.0}, dir = '+x', reach = BACKROOMS_PIT_PLANT_RANGE},
    -- 4 m gap at local x 2..6, vine planted 0.8 m before the edge
    gap = {footprint = 1, seed = 'vine', rise = 0, minCeiling = 2.5, gapX0 = 2, gapX1 = 6,
        plot = {1.2, 0, 0}, dir = '+x'},
    -- 2.6 m ledge face at local x 3, beanstalk planted 0.8 m before it
    ledge = {footprint = 1, seed = 'beanstalk', rise = 2.6, minCeiling = 3.2, faceX = 3,
        plot = {2.2, 0, 0}, dir = '+y'},
}

local function resolveDifficulty(difficulty)
    if type(difficulty) == 'table' then return difficulty end
    local d = math.max(1, math.min(#LEVELGEN_DIFFICULTY, math.floor(difficulty or 1)))
    return LEVELGEN_DIFFICULTY[d]
end

-- Build ------------------------------------------------------------------------
--
-- Layout: a W x H grid of 6 m cells. Cell (cx, cy) covers x [cx*6, cx*6+6],
-- y [cy*6-3, cy*6+3]. A seeded recursive-backtracker carve gives a spanning
-- tree; the longest tree path is the critical path (start = spawn cell, exit
-- cell = the other end). Obstacle modules sit on straight degree-2 cells of
-- that path, rotated so their local +x is the direction of travel. Cells get
-- a region (number of modules crossed to reach them) and an elevation (sum of
-- the ledge rises crossed). 2x2 rooms and loops are added afterwards and only
-- ever join cells of the same region, so nothing bypasses a module.
--
-- meta (stable interface for the later sections):
--   seed, obstacles, minPath, minTurns, pathLength, turns, loops, fallback,
--   grid = {w, h}, start = {cx, cy}, exitCell = {cx, cy},
--   path   = list of {cx, cy}, start..exit,
--   chain  = list (k = 1..n) of {module, seed (crop), plot ('p'..k), cell = {cx, cy},
--            dir = {dx, dy} travel direction, rot = 0..3 (0 = +x, 1 = +y, 2 = -x, 3 = -y)},
--   cells  = list of {cx, cy, kind ('filler' = path, 'module', 'branch' = off path),
--            region, elev, elevOut (modules), ceil, k + module + dir + rot (modules),
--            onPath, pathIndex, start, exit, degree, room (id), inset, deadEnd, nook, loop},
--   edges  = {['cx,cy|cx,cy'] = 'open' | 'door'} (key sorted as strings),
--   regions = list (index 0..n at [r + 1]) of {index, elev, entry = {cx, cy}, cells = count},
--   rooms  = list of {id, cells = {{cx, cy} x4}},
--   loopEdges = list of edge keys, boxCount, nooks.

local function key(cx, cy) return cx .. ',' .. cy end
local function edgeKey(a, b)
    local ka, kb = key(a.cx, a.cy), key(b.cx, b.cy)
    if ka > kb then ka, kb = kb, ka end
    return ka .. '|' .. kb
end
LevelGen.key, LevelGen.edgeKey = key, edgeKey

local SIDES = {{1, 0}, {-1, 0}, {0, 1}, {0, -1}}
local DIR_NAME = {['1,0'] = '+x', ['0,1'] = '+y', ['-1,0'] = '-x', ['0,-1'] = '-y'}
local DIR_ROT = {['1,0'] = 0, ['0,1'] = 1, ['-1,0'] = 2, ['0,-1'] = 3}
local DIR_ANGLE = {['1,0'] = 0, ['0,1'] = math.pi / 2, ['-1,0'] = math.pi, ['0,-1'] = -math.pi / 2}

local function cellOf(x, y) return math.floor(x / CELL), math.floor((y + CELL / 2) / CELL) end
function LevelGen.cellCenter(cx, cy) return cx * CELL + CELL / 2, cy * CELL end
LevelGen.cellOf = cellOf

-- Module frame for travel direction d = {dx, dy}: local u (0..CELL, along d) and
-- v (-CELL/2..CELL/2, along p = left of d) map to world x, y of cell (cx, cy).
function LevelGen.frame(cx, cy, d)
    local mx, my = LevelGen.cellCenter(cx, cy)
    local p = {-d[2] + 0, d[1] + 0}
    local f = {d = d, p = p}
    function f.point(u, v)
        return mx + (u - CELL / 2) * d[1] + v * p[1], my + (u - CELL / 2) * d[2] + v * p[2]
    end
    -- local plot direction name ('+x' along travel, '+y' to the left) -> world name
    function f.dirName(localName)
        local l = CROP_DIRECTIONS[localName]
        local wx, wy = l[1] * d[1] + l[2] * p[1], l[1] * d[2] + l[2] * p[2]
        return DIR_NAME[(wx + 0) .. ',' .. (wy + 0)]   -- + 0 turns -0 into 0
    end
    return f
end

local function gridOf(spec)
    local g = spec.grid or LEVELGEN_GRID
    if type(g) == 'number' then return g, g end
    return g[1], g[2]
end

-- Tree helpers ------------------------------------------------------------------

local function newGrid(W, H)
    local cells, list = {}, {}
    for cy = 0, H - 1 do
        for cx = 0, W - 1 do
            local c = {cx = cx, cy = cy}
            cells[key(cx, cy)] = c
            list[#list + 1] = c
        end
    end
    return cells, list
end

local function carveTree(rng, cells, list, W, H)
    local conn, visited = {}, {}
    local start = list[rng:int(1, #list)]
    visited[key(start.cx, start.cy)] = true
    local stack = {start}
    local mix = LEVELGEN_CARVE_MIX or 0
    while #stack > 0 do
        -- growing tree: mostly extend the newest cell (long corridors), sometimes
        -- branch from a random active cell (side branches, a shorter longest path)
        local ci = (mix > 0 and #stack > 1 and rng:chance(mix)) and rng:int(1, #stack) or #stack
        local c = stack[ci]
        local opts = {}
        for _, d in ipairs(SIDES) do
            local n = cells[key(c.cx + d[1], c.cy + d[2])]
            if n and not visited[key(n.cx, n.cy)] then opts[#opts + 1] = n end
        end
        if #opts == 0 then
            table.remove(stack, ci)
        else
            local n = rng:pick(opts)
            visited[key(n.cx, n.cy)] = true
            conn[edgeKey(c, n)] = 'door'
            stack[#stack + 1] = n
        end
    end
    return conn
end

-- Known-good tree: a serpentine over rows 0..H-2 with a stub below each cell of
-- the last snake row (junctions, dead ends, many turns). Needs H >= 4.
local function fallbackTree(cells, W, H)
    local conn = {}
    local function link(ax, ay, bx, by) conn[edgeKey(cells[key(ax, ay)], cells[key(bx, by)])] = 'door' end
    for r = 0, H - 2 do
        for c = 0, W - 2 do link(c, r, c + 1, r) end
        if r < H - 2 then
            local col = (r % 2 == 0) and W - 1 or 0
            link(col, r, col, r + 1)
        end
    end
    for c = 0, W - 1 do link(c, H - 1, c, H - 2) end
    return conn
end

local function treeNeighbors(cells, conn, c)
    local out = {}
    for _, d in ipairs(SIDES) do
        local n = cells[key(c.cx + d[1], c.cy + d[2])]
        if n and conn[edgeKey(c, n)] then out[#out + 1] = n end
    end
    return out
end

-- BFS over conn; returns the farthest cell (first found in grid order) and the parent map.
local function farthest(cells, list, conn, from)
    local dist, parent = {[key(from.cx, from.cy)] = 0}, {}
    local queue, head, last = {from}, 1, from
    while head <= #queue do
        local c = queue[head]; head = head + 1
        if dist[key(c.cx, c.cy)] > dist[key(last.cx, last.cy)] then last = c end
        for _, n in ipairs(treeNeighbors(cells, conn, c)) do
            local nk = key(n.cx, n.cy)
            if not dist[nk] then
                dist[nk] = dist[key(c.cx, c.cy)] + 1
                parent[nk] = c
                queue[#queue + 1] = n
            end
        end
    end
    return last, parent
end

local function longestPath(cells, list, conn, rng)
    local a = farthest(cells, list, conn, list[1])
    local b, parent = farthest(cells, list, conn, a)
    local path, c = {}, b
    while c do
        table.insert(path, 1, c)
        c = parent[key(c.cx, c.cy)]
    end
    if rng:chance(0.5) then   -- path runs a..b or b..a
        local rev = {}
        for i = #path, 1, -1 do rev[#rev + 1] = path[i] end
        path = rev
    end
    return path
end

local function step(a, b) return {b.cx - a.cx, b.cy - a.cy} end

local function countTurns(path)
    local t = 0
    for i = 2, #path - 1 do
        local s1, s2 = step(path[i - 1], path[i]), step(path[i], path[i + 1])
        if s1[1] ~= s2[1] or s1[2] ~= s2[2] then t = t + 1 end
    end
    return t
end

-- Module indices on the path: straight degree-2 cells, one per equal path segment,
-- never the first two or last cell and never adjacent. Returns a list or nil.
local function chooseModuleSlots(cells, conn, path, n, rng)
    local L = #path
    local lo, hi = 3, L - 1
    local span = hi - lo + 1
    if span < n then return nil end
    local slots, prev = {}, 0
    for k = 1, n do
        local s0 = math.max(lo + math.floor((k - 1) * span / n), prev + 2)
        local s1 = lo + math.floor(k * span / n) - 1
        local opts = {}
        for i = s0, s1 do
            local s1v, s2v = step(path[i - 1], path[i]), step(path[i], path[i + 1])
            if s1v[1] == s2v[1] and s1v[2] == s2v[2] and #treeNeighbors(cells, conn, path[i]) == 2 then
                opts[#opts + 1] = i
            end
        end
        if #opts == 0 then return nil end
        prev = rng:pick(opts)
        slots[k] = prev
    end
    return slots
end

-- Build ------------------------------------------------------------------------

-- One candidate level from `seed` (no full self-check). Returns data, or nil and
-- a reason when no acceptable layout was found (generate() then derives a seed).
function LevelGen.build(seed, difficulty)
    local spec = resolveDifficulty(difficulty)
    local n = spec.obstacles
    local W, H = gridOf(spec)
    local minPath, minTurns = spec.minPath or LEVELGEN_MIN_PATH, spec.minTurns or LEVELGEN_MIN_TURNS

    -- 1. carve: bounded retries, then the fallback template
    local cells, list, conn, path, slots
    local fallback = false
    local rng = LevelGen.rng(seed)
    local function accept(tree, p)
        if #p < minPath or countTurns(p) < minTurns then return nil end
        -- the critical path must not swallow the grid: side branches need room
        if #p > (spec.maxPathFrac or LEVELGEN_MAX_PATH_FRAC) * W * H then return nil end
        local junction = false
        for _, c in ipairs(list) do if #treeNeighbors(cells, tree, c) >= 3 then junction = true end end
        if not junction then return nil end
        return chooseModuleSlots(cells, tree, p, n, rng)
    end
    for t = 0, LEVELGEN_CARVE_TRIES - 1 do
        cells, list = newGrid(W, H)
        local crng = LevelGen.rng(LevelGen.levelSeed(seed, 9000 + t))
        local tree = carveTree(crng, cells, list, W, H)
        local p = longestPath(cells, list, tree, crng)
        local s = accept(tree, p)
        if s then conn, path, slots = tree, p, s; break end
    end
    if not conn and H >= 4 then
        fallback = true
        cells, list = newGrid(W, H)
        local tree = fallbackTree(cells, W, H)
        local p = longestPath(cells, list, tree, LevelGen.rng(seed))
        local s = accept(tree, p)
        if s then conn, path, slots = tree, p, s end
    end
    if not conn then return nil, 'no acceptable maze for seed ' .. tostring(seed) end
    if fallback then print('[levelgen] fallback maze for seed ' .. tostring(seed)) end
    local L = #path

    -- 2. critical path, modules (chain) and the regions / elevations they cut
    local chain = {}
    for k = 1, n do chain[k] = {module = rng:pick(spec.types)} end
    if n >= #spec.types then
        local order = {}
        for k = 1, n do order[k] = k end
        rng:shuffle(order)
        for i, t in ipairs(spec.types) do chain[order[i]].module = t end
    end
    local slotOf = {}
    for k = 1, n do slotOf[slots[k]] = k end
    local region, elev = 0, 0
    local regionInfo = {{index = 0, elev = 0, entry = {path[1].cx, path[1].cy}}}
    for i, c in ipairs(path) do
        c.onPath, c.pathIndex = true, i
        c.region, c.elev = region, elev
        local k = slotOf[i]
        if k then
            local def = LevelGen.MODULES[chain[k].module]
            local d = step(path[i - 1], c)
            c.kind, c.k, c.module = 'module', k, chain[k].module
            c.dir, c.rot = d, DIR_ROT[d[1] .. ',' .. d[2]]
            c.elevOut = elev + def.rise
            chain[k].seed, chain[k].plot = def.seed, 'p' .. k
            chain[k].cell, chain[k].dir, chain[k].rot = {c.cx, c.cy}, d, c.rot
            region, elev = region + 1, elev + def.rise
            local nxt = path[i + 1]
            regionInfo[region + 1] = {index = region, elev = elev, entry = {nxt.cx, nxt.cy}}
        else
            c.kind = 'filler'
        end
    end
    path[1].start, path[L].exit = true, true
    -- off-path cells inherit region / elevation from the path cell they hang off
    local queue, head = {}, 1
    for _, c in ipairs(path) do queue[#queue + 1] = c end
    while head <= #queue do
        local c = queue[head]; head = head + 1
        for _, nb in ipairs(treeNeighbors(cells, conn, c)) do
            if not nb.region then
                nb.region, nb.elev, nb.kind, nb.parent = c.region, c.elev, 'branch', c
                queue[#queue + 1] = nb
            end
        end
    end

    -- 2b. optional plots (section 3): own rng stream, so nothing else shifts.
    -- An alcove module sits on a straight off-path cell whose subtree (the
    -- area) hangs behind it; area cells carry opt = index and are walled off
    -- from everything else (rooms and loops require equal opt).
    local orng = LevelGen.rng(seed * 13 + 4421)
    local optional, shortcutList = {}, {}
    local wantShortcuts = spec.shortcuts or (n >= 3 and 1 or 0)
    local function subtree(c)
        local out, stack = {}, {}
        for _, nb in ipairs(treeNeighbors(cells, conn, c)) do if nb ~= c.parent then stack[#stack + 1] = nb end end
        while #stack > 0 do
            local x = table.remove(stack)
            out[#out + 1] = x
            for _, nb in ipairs(treeNeighbors(cells, conn, x)) do if nb ~= x.parent then stack[#stack + 1] = nb end end
        end
        return out
    end
    local function makeOptional(c, d, shortcut)
        local mod = orng:pick(LEVELGEN_OPT_TYPES)
        local def = LevelGen.MODULES[mod]
        local o = {plot = 'p' .. (n + #optional + 1), module = mod, seed = def.seed, cell = {c.cx, c.cy},
            dir = d, rot = DIR_ROT[d[1] .. ',' .. d[2]], region = c.region, shortcut = shortcut or false}
        c.kind, c.module, c.dir, c.rot, c.elevOut = 'module', mod, d, o.rot, c.elev
        c.optional, c.plotId, c.shortcut, c.deadEnd = true, o.plot, shortcut or nil, nil
        optional[#optional + 1] = o
        return o
    end
    do
        local cand = {}
        for _, c in ipairs(list) do
            if c.kind == 'branch' and c.parent and #treeNeighbors(cells, conn, c) == 2 then
                local child
                for _, nb in ipairs(treeNeighbors(cells, conn, c)) do if nb ~= c.parent then child = nb end end
                local s1, s2 = step(c.parent, c), step(c, child)
                if s1[1] == s2[1] and s1[2] == s2[2] then cand[#cand + 1] = c end
            end
        end
        orng:shuffle(cand)
        local want, taken = spec.optional or spec.branches or math.max(2, n), {}   -- branches: LEVELGEN_DIFFICULTY row (section 6)
        local rewardFlip = orng:int(0, 1)
        for _, c in ipairs(cand) do
            if #optional >= want then break end
            local area = (not taken[c]) and subtree(c) or {}
            local ok = #area >= 1 and #area <= LEVELGEN_OPT_MAX_AREA
            for _, a in ipairs(area) do if taken[a] then ok = false end end
            if ok then
                local o = makeOptional(c, step(c.parent, c))
                taken[c] = true
                local branching = false
                o.area = {}
                for _, a in ipairs(area) do
                    taken[a], a.opt = true, #optional
                    o.area[#o.area + 1] = {a.cx, a.cy}
                    if #treeNeighbors(cells, conn, a) > 2 then branching = true end
                end
                o.parent = {c.parent.cx, c.parent.cy}
                o.kind = branching and 'alcove' or 'deadend'
                o.reward = ((#optional + rewardFlip) % 2 == 1) and 'seed' or 'empty'
            end
        end
        if #optional < 2 - wantShortcuts then return nil, 'too few optional plots' end
    end
    local vrng = LevelGen.rng(seed * 17 + 301)   -- ceiling variety: own stream
    for _, c in ipairs(list) do
        local var = (c.kind == 'module') and 0 or vrng:pick(LEVELGEN_CEILING_VARIANTS)
        c.ceil = c.elev + LEVELGEN_CEILING + var
        c.degree = #treeNeighbors(cells, conn, c)
        if c.kind == 'branch' and c.degree == 1 then c.deadEnd = true end
    end
    for _, c in ipairs(list) do
        regionInfo[c.region + 1].cells = (regionInfo[c.region + 1].cells or 0) + 1
    end

    -- module edges are fully open
    for _, c in ipairs(path) do
        if c.kind == 'module' then
            conn[edgeKey(path[c.pathIndex - 1], c)] = 'open'
            conn[edgeKey(c, path[c.pathIndex + 1])] = 'open'
        end
    end

    for _, c in ipairs(list) do
        if c.optional then
            for _, nb in ipairs(treeNeighbors(cells, conn, c)) do conn[edgeKey(c, nb)] = 'open' end
        end
    end

    -- 3. rooms: connected 2x2 blocks of one region, no module / start / exit cell
    local rooms, inRoom = {}, {}
    local blocks = {}
    for cy = 0, H - 2 do
        for cx = 0, W - 2 do
            local b = {cells[key(cx, cy)], cells[key(cx + 1, cy)], cells[key(cx, cy + 1)], cells[key(cx + 1, cy + 1)]}
            local ok = true
            for _, c in ipairs(b) do
                if c.kind == 'module' or c.start or c.exit or c.region ~= b[1].region or (c.opt or 0) ~= (b[1].opt or 0) then ok = false end
            end
            if ok then blocks[#blocks + 1] = b end
        end
    end
    rng:shuffle(blocks)
    for _, b in ipairs(blocks) do
        if #rooms >= LEVELGEN_MAX_ROOMS then break end
        local free = true
        for _, c in ipairs(b) do if inRoom[c] then free = false end end
        if free and rng:chance(LEVELGEN_ROOM_CHANCE) then
            local id = #rooms + 1
            local r = {id = id, cells = {}}
            for _, c in ipairs(b) do
                inRoom[c], c.room = true, id
                r.cells[#r.cells + 1] = {c.cx, c.cy}
            end
            conn[edgeKey(b[1], b[2])], conn[edgeKey(b[3], b[4])] = 'open', 'open'
            conn[edgeKey(b[1], b[3])], conn[edgeKey(b[2], b[4])] = 'open', 'open'
            local top = math.max(b[1].ceil, b[2].ceil, b[3].ceil, b[4].ceil)
            for _, c in ipairs(b) do c.ceil = top end
            rooms[id] = r
        end
    end

    -- 4. loops: only between unconnected neighbours of the same region and elevation
    local loopEdges = {}
    local cands = {}
    for _, c in ipairs(list) do
        for _, d in ipairs({{1, 0}, {0, 1}}) do
            local nb = cells[key(c.cx + d[1], c.cy + d[2])]
            if nb and not conn[edgeKey(c, nb)] and c.kind ~= 'module' and nb.kind ~= 'module'
                and not c.start and not c.exit and not nb.start and not nb.exit
                and c.region == nb.region and c.elev == nb.elev and (c.opt or 0) == (nb.opt or 0) then
                cands[#cands + 1] = {c, nb}
            end
        end
    end
    rng:shuffle(cands)
    for _, p in ipairs(cands) do
        if rng:chance(LEVELGEN_LOOP_CHANCE) or (#loopEdges == 0 and p == cands[#cands]) then
            conn[edgeKey(p[1], p[2])] = 'door'
            loopEdges[#loopEdges + 1] = edgeKey(p[1], p[2])
            p[1].loop, p[2].loop = true, true
        end
    end
    if #loopEdges == 0 then return nil, 'no loop candidate' end

    -- 4b. shortcuts: a free leaf M (parent Z) joins the far cell Y straight
    -- across it, so M becomes a straight module on a new loop inside one
    -- region. Solving it shortens Z..Y; nothing needs it.
    do
        local function dist(a, b)
            local d, q, h = {[a] = 0}, {a}, 1
            while h <= #q do
                local c = q[h]; h = h + 1
                if c == b then return d[c] end
                for _, nb in ipairs(treeNeighbors(cells, conn, c)) do
                    if not d[nb] then d[nb] = d[c] + 1; q[#q + 1] = nb end
                end
            end
        end
        local cand = {}
        for _, c in ipairs(list) do
            if c.kind == 'branch' and c.parent and c.deadEnd and not c.loop and not c.opt and not c.room
                and c.parent.kind ~= 'module' then cand[#cand + 1] = c end
        end
        orng:shuffle(cand)
        local made = 0
        for _, c in ipairs(cand) do
            if made >= wantShortcuts then break end
            local z = c.parent
            local d = step(z, c)
            local y = cells[key(c.cx + d[1], c.cy + d[2])]
            if y and y.kind ~= 'module' and not y.start and not y.exit and not y.opt and y.region == c.region
                and y.elev == c.elev and #treeNeighbors(cells, conn, c) == 1 then
                local td = dist(z, y)
                if td and td >= LEVELGEN_SHORTCUT_MIN then
                    local o = makeOptional(c, d, true)
                    o.from, o.to, o.treeDist = {z.cx, z.cy}, {y.cx, y.cy}, td
                    conn[edgeKey(z, c)], conn[edgeKey(c, y)] = 'open', 'open'
                    c.ceil = c.elev + LEVELGEN_CEILING
                    shortcutList[#shortcutList + 1] = o
                    made = made + 1
                end
            end
        end
        if made < wantShortcuts then return nil, 'no shortcut site' end
    end
    for _, c in ipairs(list) do
        local deg = 0
        for _, d in ipairs(SIDES) do
            local nb = cells[key(c.cx + d[1], c.cy + d[2])]
            if nb and conn[edgeKey(c, nb)] then deg = deg + 1 end
        end
        c.degree = deg
        if c.loop then c.deadEnd = nil end
    end

    -- nooks: some off-path leaves hide behind a prop; corridor width variety
    local nooks = {}
    for _, c in ipairs(list) do
        if c.deadEnd and not c.loop and rng:chance(0.35) then c.nook = true end
        if c.kind ~= 'module' and not c.room and not c.start and not c.exit and c.degree == 2
            and rng:chance(LEVELGEN_NARROW_CHANCE) then
            local open = {}
            for _, d in ipairs(SIDES) do
                local nb = cells[key(c.cx + d[1], c.cy + d[2])]
                if nb and conn[edgeKey(c, nb)] then open[#open + 1] = d end
            end
            if open[1][1] + open[2][1] == 0 and open[1][2] + open[2][2] == 0 then
                c.inset, c.insetAxis = LEVELGEN_NARROW_INSET, open[1][1] ~= 0 and 'x' or 'y'
            end
        end
    end

    -- 5. boxes ----------------------------------------------------------------
    local themeRng = LevelGen.rng(seed * 31 + 977)   -- own stream, never the layout rng
    local themes = {}
    for _, c in ipairs(list) do themes[c] = themeRng:pick(MATERIAL_THEME_NAMES) end
    do
        local allSame = true
        for _, c in ipairs(list) do if themes[c] ~= themes[list[1]] then allSame = false end end
        if allSame then
            local others = {}
            for _, nme in ipairs(MATERIAL_THEME_NAMES) do if nme ~= themes[list[1]] then others[#others + 1] = nme end end
            themes[list[#list]] = others[themeRng:int(1, #others)]
        end
    end
    local boxes, plots, billboards = {}, {}, {}
    local function addBox(kind, x0, x1, y0, y1, z0, z1, theme, obstacle)
        boxes[#boxes + 1] = {kind = kind, pos = {(x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2},
            size = {x1 - x0, y1 - y0, z1 - z0}, theme = theme, obstacle = obstacle or nil}
    end
    -- plain floors and ceilings are merged into runs of same-height, same-theme cells
    local slabs = {}
    local function slab(kind, c, z0, z1)
        slabs[#slabs + 1] = {kind = kind, x0 = c.cx * CELL, x1 = c.cx * CELL + CELL,
            y0 = c.cy * CELL - CELL / 2, y1 = c.cy * CELL + CELL / 2, z0 = z0, z1 = z1, theme = themes[c]}
    end
    local function mergeSlabs(list2, a0, a1, b0, b1)
        local function gk(s) return s.kind .. '|' .. s.theme .. '|' .. s.z0 .. '|' .. s.z1 .. '|' .. s[b0] .. '|' .. s[b1] end
        table.sort(list2, function(p, q)
            local kp, kq = gk(p), gk(q)
            if kp ~= kq then return kp < kq end
            return p[a0] < q[a0]
        end)
        local out = {}
        for _, s in ipairs(list2) do
            local last = out[#out]
            if last and gk(last) == gk(s) and last[a1] == s[a0] then last[a1] = s[a1]
            else out[#out + 1] = {kind = s.kind, x0 = s.x0, x1 = s.x1, y0 = s.y0, y1 = s.y1, z0 = s.z0, z1 = s.z1, theme = s.theme} end
        end
        return out
    end

    for _, c in ipairs(list) do
        local X0, Y0 = c.cx * CELL, c.cy * CELL - CELL / 2
        local X1, Y1 = X0 + CELL, Y0 + CELL
        slab('ceiling', c, c.ceil, c.ceil + T)
        if c.kind ~= 'module' then
            slab('floor', c, c.elev - T, c.elev)
        else
            local def = LevelGen.MODULES[c.module]
            local f = LevelGen.frame(c.cx, c.cy, c.dir)
            local th, e = themes[c], c.elev
            local function mbox(kind, u0, u1, v0, v1, z0, z1)
                local xa, ya = f.point(u0, v0)
                local xb, yb = f.point(u1, v1)
                addBox(kind, math.min(xa, xb), math.max(xa, xb), math.min(ya, yb), math.max(ya, yb), z0, z1, th, true)
            end
            local h = CELL / 2
            mbox('floor', 0, CELL, -h, h, VOID_Z - T, VOID_Z)
            local px, py = f.point(def.plot[1], def.plot[2])
            local pz = e + def.plot[3]
            plots[#plots + 1] = {id = c.plotId or ('p' .. c.k), pos = {px, py, pz}, dir = f.dirName(def.dir), reach = def.reach}
            if c.module == 'pit' then
                mbox('floor', 0, def.pitX0, -h, h, e - T, e)
                mbox('floor', def.pitX1, CELL, -h, h, e - T, e)
                boxes[#boxes + 1] = {kind = 'solid', pos = {px, py, (VOID_Z + pz) / 2}, size = {1.2, 1.2, pz - VOID_Z},
                    color = {0.36, 0.25, 0.16, 1}, collide = false}
            elseif c.module == 'gap' then
                mbox('floor', 0, def.gapX0, -h, h, e - T, e)
            else
                mbox('floor', 0, def.faceX, -h, h, e - T, e)
                mbox('solid', def.faceX, CELL, -h, h, VOID_Z, e + def.rise)
            end
        end
    end
    -- flush merged slabs (x runs, then y runs)
    do
        local merged = mergeSlabs(mergeSlabs(slabs, 'x0', 'x1', 'y0', 'y1'), 'y0', 'y1', 'x0', 'x1')
        for _, s in ipairs(merged) do
            addBox(s.kind, s.x0, s.x1, s.y0, s.y1, s.z0, s.z1, s.theme)
        end
    end

    for _, c in ipairs(list) do
        local X0, Y0 = c.cx * CELL, c.cy * CELL - CELL / 2
        local X1, Y1 = X0 + CELL, Y0 + CELL
        local th = themes[c]
        local obst = nil
        for _, d in ipairs(SIDES) do
            local nb = cells[key(c.cx + d[1], c.cy + d[2])]
            local mode
            if not nb then mode = 'full'
            elseif d[1] > 0 or d[2] > 0 then
                local t = conn[edgeKey(c, nb)]
                mode = t == 'door' and 'door' or (t == nil and 'full' or nil)
            end
            if mode then
                local top = math.max(c.ceil, nb and nb.ceil or c.ceil)
                local vertical = d[1] ~= 0
                local line = vertical and (d[1] > 0 and X1 or X0) or (d[2] > 0 and Y1 or Y0)
                local a, b = vertical and Y0 or X0 - T / 2, vertical and Y1 or X1 + T / 2
                local mid = vertical and c.cy * CELL or X0 + CELL / 2
                local spans = {{a, b}}
                if mode == 'door' then spans = {{a, mid - DOOR / 2}, {mid + DOOR / 2, b}} end
                for _, sp in ipairs(spans) do
                    if vertical then addBox('wall', line - T / 2, line + T / 2, sp[1], sp[2], VOID_Z, top, th)
                    else addBox('wall', sp[1], sp[2], line - T / 2, line + T / 2, VOID_Z, top, th) end
                end
            end
        end
        if c.inset then   -- narrowed straight corridor: slabs along both side walls
            local i = c.inset
            if c.insetAxis == 'x' then
                addBox('wall', X0, X1, Y0 + T / 2, Y0 + T / 2 + i, c.elev, c.ceil, th)
                addBox('wall', X0, X1, Y1 - T / 2 - i, Y1 - T / 2, c.elev, c.ceil, th)
            else
                addBox('wall', X0 + T / 2, X0 + T / 2 + i, Y0, Y1, c.elev, c.ceil, th)
                addBox('wall', X1 - T / 2 - i, X1 - T / 2, Y0, Y1, c.elev, c.ceil, th)
            end
        end
    end

    -- nook props: half-cover the doorway on the parent side
    local nookCount = 0
    for _, c in ipairs(list) do
        if c.nook then
            for _, d in ipairs(SIDES) do
                local par = cells[key(c.cx + d[1], c.cy + d[2])]
                if par and conn[edgeKey(c, par)] then
                    local mx, my = LevelGen.cellCenter(par.cx, par.cy)
                    local px, py = mx, my
                    -- doorway lies on the shared face; shift the prop beside it, inside the parent cell
                    local dx, dy = c.cx - par.cx, c.cy - par.cy
                    billboards[#billboards + 1] = {texture = 'sacks', height = 1.1,
                        pos = {px + dx * (CELL / 2 - 0.7) - dy * 0.7, py + dy * (CELL / 2 - 0.7) + dx * 0.7, par.elev}}
                    nookCount = nookCount + 1
                    break
                end
            end
        end
    end

    -- 6. spawn and exit
    local first = step(path[1], path[2])
    local sx, sy = LevelGen.cellCenter(path[1].cx, path[1].cy)
    local lastStep = step(path[L - 1], path[L])
    local ex, ey = LevelGen.cellCenter(path[L].cx, path[L].cy)
    local exit = {
        pos = {ex + lastStep[1] * (CELL / 2 - 0.3), ey + lastStep[2] * (CELL / 2 - 0.3), path[L].elev + 1.1},
        size = lastStep[1] ~= 0 and {0.6, 1.4, 2.2} or {1.4, 0.6, 2.2},
    }

    -- 7. seeds (prefix rule: critical seed k lies in a region < k; extras off the path)
    local seedTypes, used = {}, {}
    for _, link in ipairs(chain) do used[link.seed] = true end
    for _, o in ipairs(optional) do used[o.seed] = true end
    for _, t in ipairs(SEED_TYPES) do if used[t] then seedTypes[#seedTypes + 1] = t end end
    local pickups = {}
    local function place(c, seedType, tier, k, r)
        r = r or rng
        local mx, my = LevelGen.cellCenter(c.cx, c.cy)
        pickups[#pickups + 1] = {pos = {mx + (r:next() - 0.5) * 3.4, my + (r:next() - 0.5) * 3.4, c.elev},
            seed = seedType, tier = tier, obstacle = k}
    end
    for k = 1, n do
        local branchCells, pathCells = {}, {}
        for _, c in ipairs(list) do
            if c.region < k and c.kind == 'branch' and not c.opt then branchCells[#branchCells + 1] = c
            elseif c.region < k and c.kind == 'filler' and not c.start then pathCells[#pathCells + 1] = c end
        end
        local pool = (#branchCells > 0 and rng:chance(0.7)) and branchCells or pathCells
        place(rng:pick(pool), chain[k].seed, 'critical', k)
    end
    local sideCells = {}
    for _, c in ipairs(list) do if c.kind == 'branch' and not c.opt then sideCells[#sideCells + 1] = c end end
    if #sideCells == 0 then return nil, 'no side cells' end
    for _ = 1, rng:int(1, n) do
        place(rng:pick(sideCells), rng:pick(seedTypes), 'extra')
    end
    -- section 3 seeds, own stream: one seed of each optional module's crop in
    -- a non-optional dead end / branch no later than its region, plus the
    -- reward seed inside alcoves and dead ends marked 'seed'
    for _, o in ipairs(optional) do
        local ends, any = {}, {}
        for _, c in ipairs(sideCells) do
            if c.region <= o.region then
                any[#any + 1] = c
                if c.deadEnd then ends[#ends + 1] = c end
            end
        end
        local pool = #ends > 0 and ends or (#any > 0 and any or sideCells)
        local sc = orng:pick(pool)
        place(sc, o.seed, 'extra', nil, orng)
        o.supply = {sc.cx, sc.cy}
        if not o.shortcut and o.reward == 'seed' then
            local a = orng:pick(o.area)
            place(cells[key(a[1], a[2])], orng:pick(seedTypes), 'extra', nil, orng)
        end
    end

    -- 8. assemble
    local metaCells = {}
    for i, c in ipairs(list) do
        metaCells[i] = {cx = c.cx, cy = c.cy, kind = c.kind, region = c.region, elev = c.elev, elevOut = c.elevOut,
            ceil = c.ceil, k = c.k, module = c.module, dir = c.dir, rot = c.rot, onPath = c.onPath or false,
            pathIndex = c.pathIndex, start = c.start, exit = c.exit, degree = c.degree, room = c.room,
            inset = c.inset, deadEnd = c.deadEnd, nook = c.nook, loop = c.loop,
            optional = c.optional, shortcut = c.shortcut, opt = c.opt, plotId = c.plotId}
    end
    local metaPath = {}
    for i, c in ipairs(path) do metaPath[i] = {c.cx, c.cy} end
    local edges = {}
    for k2, v in pairs(conn) do edges[k2] = v end
    local data = {
        id = 'gen-' .. seed,
        name = 'Generated level',
        spawn = {sx, sy, 0, DIR_ANGLE[first[1] .. ',' .. first[2]]},
        killZ = LEVELGEN_KILL_Z,
        boxes = boxes,
        exit = exit,
        plots = plots,
        allotment = {},
        generated = true,       -- starts with no seeds (RoomStartingSeeds)
        billboards = billboards,
        pickups = pickups,
        seedTypes = seedTypes,
        meta = {seed = seed, obstacles = n, chain = chain, cells = metaCells, edges = edges, nooks = nookCount,
            grid = {W, H}, start = {path[1].cx, path[1].cy}, exitCell = {path[L].cx, path[L].cy},
            path = metaPath, pathLength = L, turns = countTurns(path), minPath = minPath, minTurns = minTurns,
            regions = regionInfo, rooms = rooms, loopEdges = loopEdges, loops = #loopEdges,
            fallback = fallback, boxCount = #boxes,
            optional = optional, shortcuts = shortcutList, shortcutsWanted = wantShortcuts, plotCount = #plots},
    }
    return Dressing.apply(data, seed)
end

-- Self-check ---------------------------------------------------------------------

-- Cells reachable from the start cell over doorways and open edges while the
-- modules with k >= blockFrom are not crossed (their cell is not entered).
local function reachable(meta, blockFrom, blockOptional)
    local byKey, adj = {}, {}
    for _, c in ipairs(meta.cells) do byKey[key(c.cx, c.cy)] = c end
    for e in pairs(meta.edges) do
        local a, b = e:match('^(.-)|(.*)$')
        adj[a] = adj[a] or {}; adj[b] = adj[b] or {}
        table.insert(adj[a], b); table.insert(adj[b], a)
    end
    local s = key(meta.start[1], meta.start[2])
    local seen, stack = {[s] = true}, {s}
    while #stack > 0 do
        local k = table.remove(stack)
        for _, nk in ipairs(adj[k] or {}) do
            local c = byKey[nk]
            local blocked = c.kind == 'module'
                and ((c.optional and blockOptional) or (not c.optional and c.k >= blockFrom))
            if not seen[nk] and not blocked then
                seen[nk] = true
                stack[#stack + 1] = nk
            end
        end
    end
    return seen, byKey
end

-- Section 3 invariants (meta.optional / meta.shortcuts); true or false, reason.
-- Cells reachable with every optional module blocked are the "critical-only"
-- world: it must hold the exit and every critical seed and none of the areas.
function LevelGen.checkBranches(data)
    local meta = data.meta
    if #data.plots < meta.obstacles + 2 then return false, 'fewer than two extra plots' end
    if #meta.shortcuts < meta.shortcutsWanted then return false, 'missing shortcut' end
    local crit, byKey = reachable(meta, math.huge, true)
    if not crit[key(meta.exitCell[1], meta.exitCell[2])] then return false, 'exit needs an optional plot' end
    for _, p in ipairs(data.pickups) do
        if p.tier == 'critical' then
            local cx, cy = cellOf(p.pos[1], p.pos[2])
            if not crit[key(cx, cy)] then return false, 'critical seed needs an optional plot' end
        end
    end
    local seen = {}
    for _, o in ipairs(meta.optional) do
        if seen[o.plot] then return false, 'duplicate plot id ' .. o.plot end
        seen[o.plot] = true
        local mk = key(o.cell[1], o.cell[2])
        if not byKey[mk].optional then return false, 'optional cell not marked ' .. mk end
        if o.shortcut then
            local from, to = key(o.from[1], o.from[2]), key(o.to[1], o.to[2])
            if not (crit[from] and crit[to]) then return false, 'shortcut ends not reachable' end
            local function dist(blockOpt)
                local d, q, h = {[from] = 0}, {from}, 1
                local adj = {}
                for e in pairs(meta.edges) do
                    local a, b = e:match('^(.-)|(.*)$')
                    adj[a] = adj[a] or {}; adj[b] = adj[b] or {}
                    table.insert(adj[a], b); table.insert(adj[b], a)
                end
                while h <= #q do
                    local k = q[h]; h = h + 1
                    for _, nk in ipairs(adj[k] or {}) do
                        if not d[nk] and not (blockOpt and byKey[nk].optional) then d[nk] = d[k] + 1; q[#q + 1] = nk end
                    end
                end
                return d[to]
            end
            local walled, open = dist(true), dist(false)
            if not walled or not open or open >= walled then return false, 'shortcut ' .. o.plot .. ' does not shorten' end
        else
            if crit[mk] then return false, 'optional module reachable ' .. mk end
            local inArea = {}
            for _, a in ipairs(o.area) do inArea[key(a[1], a[2])] = true end
            for _, a in ipairs(o.area) do
                local ak = key(a[1], a[2])
                if crit[ak] then return false, 'optional area reachable early ' .. ak end
                if ak == key(meta.exitCell[1], meta.exitCell[2]) or byKey[ak].onPath then
                    return false, 'optional area holds a critical cell ' .. ak
                end
            end
            -- only the module links the area to the rest
            for e in pairs(meta.edges) do
                local a, b = e:match('^(.-)|(.*)$')
                if inArea[a] ~= inArea[b] and a ~= mk and b ~= mk then return false, 'area leaks at ' .. e end
            end
            -- solving it opens the area
            local opened = reachable(meta, math.huge, false)
            for ak in pairs(inArea) do if not opened[ak] then return false, 'area not opened ' .. ak end end
            local extras = 0
            for _, p in ipairs(data.pickups) do
                local cx, cy = cellOf(p.pos[1], p.pos[2])
                if inArea[key(cx, cy)] then
                    extras = extras + 1
                    if p.tier ~= 'extra' then return false, 'critical seed inside an optional area' end
                end
            end
            if o.reward == 'empty' and extras > 0 then return false, 'decoy holds a seed' end
            if o.reward == 'seed' and extras == 0 then return false, 'reward area is empty' end
        end
    end
    return true
end

-- Returns true, or false and a reason. Checks structure and seed sufficiency;
-- tests/reach.lua is the independent physical check (section 7).
function LevelGen.check(data)
    local ok, err = Room.validate(data)
    if not ok then return false, err end
    local meta = data.meta
    if #data.boxes > LEVELGEN_BOX_BUDGET then return false, 'box budget exceeded: ' .. #data.boxes end
    local seenKeys = {}
    for _, c in ipairs(meta.cells) do
        local k = key(c.cx, c.cy)
        if seenKeys[k] then return false, 'overlapping cells at ' .. k end
        seenKeys[k] = true
    end
    local all, byKey = reachable(meta, math.huge)
    for k in pairs(seenKeys) do
        if not all[k] then return false, 'disconnected cell ' .. k end
    end
    local exitKey = key(meta.exitCell[1], meta.exitCell[2])
    if not all[exitKey] then return false, 'exit not connected' end
    if reachable(meta, 1)[exitKey] then return false, 'exit reachable without solving the chain' end
    if meta.pathLength < meta.minPath then return false, 'critical path too short' end
    if meta.turns < meta.minTurns then return false, 'too few turns on the critical path' end
    if meta.loops < 1 then return false, 'no loop' end
    local junction = false
    local degreeOf = {}
    for e in pairs(meta.edges) do
        local a, b = e:match('^(.-)|(.*)$')
        degreeOf[a], degreeOf[b] = (degreeOf[a] or 0) + 1, (degreeOf[b] or 0) + 1
    end
    for _, d in pairs(degreeOf) do if d >= 3 then junction = true end end
    if not junction then return false, 'no junction' end
    -- edges: loops stay inside a region; elevation changes only across a ledge module
    for e in pairs(meta.edges) do
        local a, b = e:match('^(.-)|(.*)$')
        local ca, cb = byKey[a], byKey[b]
        if ca.kind ~= 'module' and cb.kind ~= 'module' and ca.region ~= cb.region then
            return false, 'passage joins regions ' .. e
        end
        if ca.elev ~= cb.elev then
            local okElev = (ca.kind == 'module' and ca.module == 'ledge' and cb.elev == ca.elevOut)
                or (cb.kind == 'module' and cb.module == 'ledge' and ca.elev == cb.elevOut)
            if not okElev then return false, 'elevation changes off a ledge at ' .. e end
        end
    end
    for _, c in ipairs(meta.cells) do
        if c.kind == 'module' then
            local def = LevelGen.MODULES[c.module]
            if c.ceil - c.elev < def.minCeiling then return false, 'ceiling too low at module ' .. tostring(c.k or c.plotId) end
            if c.ceil - c.elevOut < BACKROOMS_PLAYER_HEIGHT + 0.5 then return false, 'no headroom after module ' .. tostring(c.k or c.plotId) end
            -- straight: exactly two passages, on opposite faces
            local open = {}
            for _, d in ipairs(SIDES) do
                local nb = byKey[key(c.cx + d[1], c.cy + d[2])]
                if nb and meta.edges[edgeKey(c, nb)] then open[#open + 1] = d end
            end
            if #open ~= 2 or open[1][1] + open[2][1] ~= 0 or open[1][2] + open[2][2] ~= 0 then
                return false, 'module ' .. tostring(c.k or c.plotId) .. ' is not on a straight passage'
            end
        end
    end
    local bok, bmsg = LevelGen.checkBranches(data)
    if not bok then return false, bmsg end
    -- prefix sufficiency: seeds collectable before obstacle k cover obstacles 1..k
    for k = 1, meta.obstacles do
        local before = reachable(meta, k, true)
        local have, need = {}, {}
        for _, p in ipairs(data.pickups) do
            if p.tier == 'critical' then
                local cx, cy = cellOf(p.pos[1], p.pos[2])
                if before[key(cx, cy)] then have[p.seed] = (have[p.seed] or 0) + 1 end
            end
        end
        for i = 1, k do need[meta.chain[i].seed] = (need[meta.chain[i].seed] or 0) + 1 end
        for t, cnt in pairs(need) do
            if (have[t] or 0) < cnt then return false, 'not enough ' .. t .. ' seeds before obstacle ' .. k end
        end
    end
    local sideOk = false
    for _, c in ipairs(meta.cells) do if c.deadEnd or c.nook then sideOk = true end end
    if not sideOk then return false, 'no dead end or nook' end
    return true
end

-- A checked level for `seed`; a failing candidate is replaced by one from a
-- derived seed. opts.mutate(candidate, attempt) lets tests corrupt candidates.
function LevelGen.generate(seed, difficulty, opts)
    local lastErr
    for attempt = 0, LEVELGEN_MAX_ATTEMPTS do
        local s = attempt == 0 and seed or deriveSeed(seed, attempt)
        local cand, why = LevelGen.build(s, difficulty)
        if cand then
            if opts and opts.mutate then opts.mutate(cand, attempt) end
            local ok, msg = LevelGen.check(cand)
            if ok then
                cand.meta.attempt, cand.meta.requestedSeed = attempt, seed
                if opts and opts.name then cand.name = opts.name end
                return cand
            end
            lastErr = msg
        else
            lastErr = why
        end
    end
    error('level generation failed for seed ' .. tostring(seed) .. ': ' .. tostring(lastErr))
end
