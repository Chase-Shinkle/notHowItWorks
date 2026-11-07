-- Seeded, always-solvable backrooms level generator.
--
-- LevelGen.generate(seed, difficulty) returns room data in the format Room()
-- validates (src/Room.lua) plus `pickups`, `seedTypes` and a `meta` table used
-- by tests. The solution is built first: a chain of obstacle modules (pit,
-- ledge, gap; hand-measured, never invented) along a spine of 6 m cells, with
-- filler cells between them. Solving obstacle k opens region k. Side cells
-- (dead ends, halls, secret nooks, loops) hang off filler cells of one region.
--
-- Grid: cell (cx, cy) covers x [cx*6, cx*6+6], y [cy*6-3, cy*6+3]. The spine
-- is cy = 0, cx = 0.. and the spawn is in cell (0, 0), facing +x.
--
-- Modules are one cell long (local x 0..6) and declare their geometry in
-- LevelGen.MODULES, copied from the old Rooms 2 and 3 (src/rooms.lua).
LevelGen = {}

local CELL, T, DOOR = LEVELGEN_CELL, LEVELGEN_WALL, LEVELGEN_DOOR
local VOID_Z = LEVELGEN_VOID_Z
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
    pit = {seed = 'pumpkin', rise = 0, minCeiling = 2.5, pitX0 = 1.4, pitX1 = 4.0, depth = 1.0,
        plot = {2.7, 0, -1.0}, dir = '+x', reach = BACKROOMS_PIT_PLANT_RANGE},
    -- 4 m gap at local x 2..6, vine planted 0.8 m before the edge
    gap = {seed = 'vine', rise = 0, minCeiling = 2.5, gapX0 = 2, gapX1 = 6,
        plot = {1.2, 0, 0}, dir = '+x'},
    -- 2.6 m ledge face at local x 3, beanstalk planted 0.8 m before it
    ledge = {seed = 'beanstalk', rise = 2.6, minCeiling = 3.2, faceX = 3,
        plot = {2.2, 0, 0}, dir = '+y'},
}

local function resolveDifficulty(difficulty)
    if type(difficulty) == 'table' then return difficulty end
    local d = math.max(1, math.min(#LEVELGEN_DIFFICULTY, math.floor(difficulty or 1)))
    return LEVELGEN_DIFFICULTY[d]
end

-- Build ------------------------------------------------------------------------

local function key(cx, cy) return cx .. ',' .. cy end
local function edgeKey(a, b)
    local ka, kb = key(a.cx, a.cy), key(b.cx, b.cy)
    if ka > kb then ka, kb = kb, ka end
    return ka .. '|' .. kb
end

local SIDES = {{1, 0}, {-1, 0}, {0, 1}, {0, -1}}

local function cellOf(x, y) return math.floor(x / CELL), math.floor((y + CELL / 2) / CELL) end

-- One candidate level from `seed` (no self-check).
function LevelGen.build(seed, difficulty)
    local rng = LevelGen.rng(seed)
    local spec = resolveDifficulty(difficulty)
    local n = spec.obstacles

    -- 1. the solution chain; every allowed type appears when n allows it
    local chain = {}
    for k = 1, n do chain[k] = {module = rng:pick(spec.types)} end
    if n >= #spec.types then
        local slots = {}
        for k = 1, n do slots[k] = k end
        rng:shuffle(slots)
        for i, t in ipairs(spec.types) do chain[slots[i]].module = t end
    end

    -- 2. the spine
    local list, cells, conn = {}, {}, {}
    local function addCell(c)
        c.ceil = c.elev + LEVELGEN_CEILING
        list[#list + 1] = c
        cells[key(c.cx, c.cy)] = c
        return c
    end
    local spine, elev, cx = {}, 0, 0
    local function filler(region, count)
        for _ = 1, count do
            spine[#spine + 1] = addCell({cx = cx, cy = 0, kind = 'filler', region = region, elev = elev})
            cx = cx + 1
        end
    end
    filler(0, rng:int(1, 2))
    for k = 1, n do
        local def = LevelGen.MODULES[chain[k].module]
        spine[#spine + 1] = addCell({cx = cx, cy = 0, kind = 'module', region = k - 1, elev = elev,
            elevOut = elev + def.rise, k = k, module = chain[k].module})
        chain[k].plot = 'p' .. k
        chain[k].seed = def.seed
        chain[k].cell = cx
        cx = cx + 1
        elev = elev + def.rise
        filler(k, rng:int(1, 3))
    end
    for i = 2, #spine do conn[edgeKey(spine[i - 1], spine[i])] = 'open' end

    -- 3. side cells
    local function addSide(parent, cy, extra)
        local c = {cx = parent.cx, cy = cy, kind = 'branch', region = parent.region, elev = parent.elev}
        for k, v in pairs(extra or {}) do c[k] = v end
        return addCell(c)
    end
    local nooks = {}
    local function free(cxx, cy) return cells[key(cxx, cy)] == nil end
    local byRegion = {}
    for _, c in ipairs(spine) do
        if c.kind == 'filler' then
            byRegion[c.region] = byRegion[c.region] or {}
            table.insert(byRegion[c.region], c)
        end
    end
    -- loops: two adjacent filler cells joined through a side hall
    for r = 0, n do
        local fs = byRegion[r] or {}
        if #fs >= 2 and rng:chance(LEVELGEN_LOOP_CHANCE) then
            local i = rng:int(1, #fs - 1)
            local s = rng:chance(0.5) and 1 or -1
            if free(fs[i].cx, s) and free(fs[i + 1].cx, s) then
                local b1, b2 = addSide(fs[i], s, {loop = true}), addSide(fs[i + 1], s, {loop = true})
                conn[edgeKey(fs[i], b1)], conn[edgeKey(b1, b2)], conn[edgeKey(b2, fs[i + 1])] = 'door', 'door', 'door'
            end
        end
    end
    local function addBranch(parent, s)
        local kind = rng:pick({'dead', 'hall', 'nook'})
        local b = addSide(parent, s)
        conn[edgeKey(parent, b)] = 'door'
        if kind == 'hall' and free(parent.cx, 2 * s) then
            local b2 = addSide(parent, 2 * s, {deadEnd = true})
            conn[edgeKey(b, b2)] = 'door'
        elseif kind == 'nook' then
            b.nook, b.deadEnd = true, true
            nooks[#nooks + 1] = {cell = b, side = s}
        else
            b.deadEnd = true
        end
    end
    for r = 0, n do
        for _, c in ipairs(byRegion[r] or {}) do
            for _, s in ipairs({1, -1}) do
                if free(c.cx, s) and rng:chance(LEVELGEN_BRANCH_CHANCE) then addBranch(c, s) end
            end
        end
    end
    local hasDead = false
    for _, c in ipairs(list) do if c.deadEnd then hasDead = true end end
    if not hasDead then
        local options = {}
        for _, c in ipairs(spine) do
            if c.kind == 'filler' then
                for _, s in ipairs({1, -1}) do if free(c.cx, s) then options[#options + 1] = {c, s} end end
            end
        end
        local o = rng:pick(options)
        addBranch(o[1], o[2])
    end

    -- 4. boxes
    local boxes, plots, billboards = {}, {}, {}
    local function box(kind, x0, x1, y0, y1, z0, z1)
        boxes[#boxes + 1] = {kind = kind, pos = {(x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2},
            size = {x1 - x0, y1 - y0, z1 - z0}}
    end
    local function floorBox(x0, x1, y0, y1, top) box('floor', x0, x1, y0, y1, top - T, top) end

    for _, c in ipairs(list) do
        local X0, Y0 = c.cx * CELL, c.cy * CELL - CELL / 2
        local X1, Y1 = X0 + CELL, Y0 + CELL
        box('ceiling', X0, X1, Y0, Y1, c.ceil, c.ceil + T)
        if c.kind ~= 'module' then
            floorBox(X0, X1, Y0, Y1, c.elev)
        else
            local def = LevelGen.MODULES[c.module]
            local e = c.elev
            floorBox(X0, X1, Y0, Y1, VOID_Z)
            local px, py, pz = X0 + def.plot[1], Y0 + CELL / 2 + def.plot[2], e + def.plot[3]
            plots[#plots + 1] = {id = 'p' .. c.k, pos = {px, py, pz}, dir = def.dir, reach = def.reach}
            if c.module == 'pit' then
                floorBox(X0, X0 + def.pitX0, Y0, Y1, e)
                floorBox(X0 + def.pitX1, X1, Y0, Y1, e)
                boxes[#boxes + 1] = {kind = 'solid', pos = {px, py, (VOID_Z + pz) / 2}, size = {1.2, 1.2, pz - VOID_Z},
                    color = {0.36, 0.25, 0.16, 1}, collide = false}
            elseif c.module == 'gap' then
                floorBox(X0, X0 + def.gapX0, Y0, Y1, e)
            else
                floorBox(X0, X0 + def.faceX, Y0, Y1, e)
                box('solid', X0 + def.faceX, X1, Y0, Y1, VOID_Z, e + def.rise)
            end
        end
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
                -- boundary line and span along it
                local vertical = d[1] ~= 0
                local line = vertical and (d[1] > 0 and X1 or X0) or (d[2] > 0 and Y1 or Y0)
                local a, b = vertical and Y0 or X0 - T / 2, vertical and Y1 or X1 + T / 2
                local mid = vertical and c.cy * CELL or X0 + CELL / 2
                local spans = {{a, b}}
                if mode == 'door' then spans = {{a, mid - DOOR / 2}, {mid + DOOR / 2, b}} end
                for _, sp in ipairs(spans) do
                    if vertical then box('wall', line - T / 2, line + T / 2, sp[1], sp[2], VOID_Z, top)
                    else box('wall', sp[1], sp[2], line - T / 2, line + T / 2, VOID_Z, top) end
                end
            end
        end
    end

    -- secret nooks: a prop half-covers the doorway on the spine side
    for _, nk in ipairs(nooks) do
        local parent = cells[key(nk.cell.cx, 0)]
        billboards[#billboards + 1] = {texture = 'sacks', height = 1.1,
            pos = {parent.cx * CELL + CELL / 2 + 0.7, nk.side * (CELL / 2 - 0.7), parent.elev}}
    end

    -- 5. exit in the last spine cell
    local last = spine[#spine]
    local exit = {pos = {(last.cx + 1) * CELL - 0.3, 0, last.elev + 1.1}, size = {0.6, 1.4, 2.2}}

    -- 6. seeds
    local seedTypes, used = {}, {}
    for _, link in ipairs(chain) do used[link.seed] = true end
    for _, t in ipairs(SEED_TYPES) do if used[t] then seedTypes[#seedTypes + 1] = t end end
    local pickups = {}
    local function place(c, seedType, tier, k)
        local x = c.cx * CELL + CELL / 2 + (rng:next() - 0.5) * 3.4
        local y = c.cy * CELL + (rng:next() - 0.5) * 3.4
        pickups[#pickups + 1] = {pos = {x, y, c.elev}, seed = seedType, tier = tier, obstacle = k}
    end
    for k = 1, n do
        local branchCells, spineCells = {}, {}
        for _, c in ipairs(list) do
            if c.region < k and c.kind == 'branch' then branchCells[#branchCells + 1] = c
            elseif c.region < k and c.kind == 'filler' then spineCells[#spineCells + 1] = c end
        end
        local pool = (#branchCells > 0 and rng:chance(0.7)) and branchCells or spineCells
        place(rng:pick(pool), chain[k].seed, 'critical', k)
    end
    local sideCells = {}
    for _, c in ipairs(list) do if c.kind == 'branch' then sideCells[#sideCells + 1] = c end end
    for _ = 1, rng:int(1, n) do
        place(rng:pick(sideCells), rng:pick(seedTypes), 'extra')
    end

    -- 7. assemble
    local metaCells = {}
    for i, c in ipairs(list) do
        metaCells[i] = {cx = c.cx, cy = c.cy, kind = c.kind, region = c.region, elev = c.elev, elevOut = c.elevOut,
            ceil = c.ceil, k = c.k, module = c.module, deadEnd = c.deadEnd, nook = c.nook, loop = c.loop}
    end
    local edges = {}
    for k2, v in pairs(conn) do edges[k2] = v end
    return {
        id = 'gen-' .. seed,
        name = 'Generated level',
        spawn = {CELL / 4, 0, 0, 0},
        killZ = LEVELGEN_KILL_Z,
        boxes = boxes,
        exit = exit,
        plots = plots,
        allotment = {},
        billboards = billboards,
        pickups = pickups,
        seedTypes = seedTypes,
        meta = {seed = seed, obstacles = n, chain = chain, cells = metaCells, edges = edges, nooks = #nooks,
            exitCell = {last.cx, 0}},
    }
end

-- Self-check ---------------------------------------------------------------------

-- Cells reachable from the spawn cell over doorways and open spine edges while
-- the modules with k >= blockFrom are not crossed (their cell is not entered).
local function reachable(meta, blockFrom)
    local byKey, adj = {}, {}
    for _, c in ipairs(meta.cells) do byKey[key(c.cx, c.cy)] = c end
    for e in pairs(meta.edges) do
        local a, b = e:match('^(.-)|(.*)$')
        adj[a] = adj[a] or {}; adj[b] = adj[b] or {}
        table.insert(adj[a], b); table.insert(adj[b], a)
    end
    local seen, stack = {['0,0'] = true}, {'0,0'}
    while #stack > 0 do
        local k = table.remove(stack)
        for _, nk in ipairs(adj[k] or {}) do
            local c = byKey[nk]
            if not seen[nk] and not (c.kind == 'module' and c.k >= blockFrom) then
                seen[nk] = true
                stack[#stack + 1] = nk
            end
        end
    end
    return seen, byKey
end

-- Returns true, or false and a reason. Checks structure and seed sufficiency;
-- tests/reach.lua is the independent physical check (section 5).
function LevelGen.check(data)
    local ok, err = Room.validate(data)
    if not ok then return false, err end
    local meta = data.meta
    local seenKeys = {}
    for _, c in ipairs(meta.cells) do
        local k = key(c.cx, c.cy)
        if seenKeys[k] then return false, 'overlapping cells at ' .. k end
        seenKeys[k] = true
    end
    local all = reachable(meta, math.huge)
    for k in pairs(seenKeys) do
        if not all[k] then return false, 'disconnected cell ' .. k end
    end
    local exitKey = key(meta.exitCell[1], meta.exitCell[2])
    if not all[exitKey] then return false, 'exit not connected' end
    if reachable(meta, 1)[exitKey] then return false, 'exit reachable without solving the chain' end
    for _, c in ipairs(meta.cells) do
        if c.kind == 'module' then
            local def = LevelGen.MODULES[c.module]
            if c.ceil - c.elev < def.minCeiling then return false, 'ceiling too low at module ' .. c.k end
            if c.ceil - c.elevOut < BACKROOMS_PLAYER_HEIGHT + 0.5 then return false, 'no headroom after module ' .. c.k end
        end
    end
    -- prefix sufficiency: seeds collectable before obstacle k cover obstacles 1..k
    for k = 1, meta.obstacles do
        local before = reachable(meta, k)
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
        local cand = LevelGen.build(s, difficulty)
        if opts and opts.mutate then opts.mutate(cand, attempt) end
        local ok, msg = LevelGen.check(cand)
        if ok then
            cand.meta.attempt, cand.meta.requestedSeed = attempt, seed
            if opts and opts.name then cand.name = opts.name end
            return cand
        end
        lastErr = msg
    end
    error('level generation failed for seed ' .. tostring(seed) .. ': ' .. tostring(lastErr))
end
