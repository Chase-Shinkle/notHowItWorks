-- Physical solvability sweep for generated levels, on the real PlayerController,
-- Room and LevelGen (headless, mocked LÖVE API). From the repo root:
--   love tests/love_runner tests/levels_sweep.lua
-- Env: SWEEP_FROM (1) SWEEP_TO (70) seeds per difficulty, SWEEP_DIFFS ("1,2,3"),
--      SWEEP_NEG (1: also run the empty/wrong-type negatives), SWEEP_VERBOSE.
-- Per (seed, difficulty), using Reach.search (sampled BFS over movement):
--   spawn settles grounded and clear; no crops -> exit unreachable;
--   for each obstacle k with crops 1..k-1 grown: every critical pickup k and a
--   planting spot for plot k are reachable (so the allotment is collectable and
--   plantable in order); all chain crops -> exit and every pickup reachable;
--   negatives (SWEEP_NEG): omitting any one chain crop, or planting any other
--   type there, leaves the exit unreachable; the minimal critical allotment
--   (one seed per chain link) is exactly the chain's multiset.
-- This navigates with physics; it does not teleport. Prints a summary line.
package.path = './?.lua;./?/init.lua;' .. package.path
local realPrint = print
local mock = dofile('tests/mock_love.lua')
mock.install()
arg = {}
dofile('main.lua')
love.load()
print = realPrint
local Reach = dofile('tests/reach.lua')

local from, to = tonumber(os.getenv('SWEEP_FROM')) or 1, tonumber(os.getenv('SWEEP_TO')) or 70
local diffs = {}
for d in (os.getenv('SWEEP_DIFFS') or '1,2,3'):gmatch('%d+') do diffs[#diffs + 1] = tonumber(d) end
local neg = os.getenv('SWEEP_NEG') ~= '0'
local verbose = os.getenv('SWEEP_VERBOSE')

local fails, levels, searches, t0 = 0, 0, 0, os.clock()
local obstacleKinds, perDiff = {}, {}
local function bad(seed, d, msg)
    fails = fails + 1
    realPrint(string.format('FAIL seed=%d diff=%d: %s', seed, d, msg))
end
local function search(room, goal)
    searches = searches + 1
    return Reach.search(room, {goal = goal, noStrafe = true})
end

for _, d in ipairs(diffs) do
    for seed = from, to do
        local data = LevelGen.generate(seed, d)
        levels = levels + 1
        perDiff[d] = (perDiff[d] or 0) + 1
        local chain = data.meta.chain
        local failsBefore = fails
        for _, l in ipairs(chain) do obstacleKinds[l.module] = (obstacleKinds[l.module] or 0) + 1 end

        -- spawn
        local room0 = Reach.roomWith(data, {})
        local p = PlayerController(data.spawn[1], data.spawn[2], data.spawn[3])
        local cols = room0:solidColliders()
        for _ = 1, 20 do p:update(1 / 20, {}, 0, cols, room0:climbVolumes()) end
        if not p.grounded or math.abs(p.z - data.spawn[3]) > 0.05 then bad(seed, d, 'spawn does not settle grounded at spawn height') end

        -- allotment = chain multiset
        local need, have = {}, {}
        for _, l in ipairs(chain) do need[l.seed] = (need[l.seed] or 0) + 1 end
        for _, pk in ipairs(data.pickups) do
            if pk.tier == 'critical' then have[pk.seed] = (have[pk.seed] or 0) + 1 end
        end
        for t, n in pairs(need) do if have[t] ~= n then bad(seed, d, 'critical allotment of ' .. t .. ' is ' .. tostring(have[t]) .. ', chain needs ' .. n) end end
        for t, n in pairs(have) do if need[t] ~= n then bad(seed, d, 'extra critical ' .. t) end end

        -- no crops: locked
        if search(room0) then bad(seed, d, 'exit reachable with no crops') end

        -- in-order collection and planting with prefix crops
        local crops = {}
        for k, link in ipairs(chain) do
            local room = Reach.roomWith(data, crops)
            local plot = room:plotById(link.plot)
            local hit, planted = {}, false
            local want = 0
            for _, pk in ipairs(data.pickups) do if pk.tier == 'critical' and pk.obstacle == k then want = want + 1 end end
            local ok = search(room, function(pl)
                for i, pk in ipairs(data.pickups) do
                    if pk.tier == 'critical' and pk.obstacle == k and not hit[i] then
                        local dx, dy = pk.pos[1] - pl.x, pk.pos[2] - pl.y
                        if dx * dx + dy * dy <= BACKROOMS_PICKUP_RADIUS ^ 2 and math.abs(pk.pos[3] - pl.z) <= BACKROOMS_PLANT_HEIGHT then
                            hit[i] = true
                        end
                    end
                end
                if not planted and room:nearestPlot(pl.x, pl.y, pl.z) == plot then planted = true end
                local n = 0
                for _ in pairs(hit) do n = n + 1 end
                return planted and n == want
            end)
            if not ok then bad(seed, d, string.format('obstacle %d (%s): critical pickups / plot %s not all reachable with crops 1..%d (picked %s, plantable %s)', k, link.module, link.plot, k - 1, tostring(next(hit) ~= nil), tostring(planted))) end
            crops[link.plot] = link.seed
        end

        -- all crops: exit and every pickup reachable
        local full = Reach.roomWith(data, crops)
        if not search(full) then bad(seed, d, 'exit unreachable with the intended crops') end
        local got = {}
        local allOk = search(full, function(pl)
            for i, pk in ipairs(data.pickups) do
                local dx, dy = pk.pos[1] - pl.x, pk.pos[2] - pl.y
                if dx * dx + dy * dy <= BACKROOMS_PICKUP_RADIUS ^ 2 and math.abs(pk.pos[3] - pl.z) <= BACKROOMS_PLANT_HEIGHT then got[i] = true end
            end
            for i = 1, #data.pickups do if not got[i] then return false end end
            return true
        end)
        if not allOk then bad(seed, d, 'some pickup (incl. extras) unreachable with all crops') end

        if neg then
            for _, link in ipairs(chain) do
                local c = {}
                for k2, v in pairs(crops) do if k2 ~= link.plot then c[k2] = v end end
                if search(Reach.roomWith(data, c)) then bad(seed, d, 'exit reachable with ' .. link.plot .. ' empty') end
                for _, t in ipairs(SEED_TYPES) do
                    if t ~= link.seed then
                        c[link.plot] = t
                        if search(Reach.roomWith(data, c)) then bad(seed, d, 'exit reachable with ' .. t .. ' (wrong type) on ' .. link.plot) end
                    end
                end
            end
        end
        if verbose or fails > failsBefore then
            realPrint(string.format('%s seed=%d diff=%d obstacles=%d', fails > failsBefore and 'FAIL' or 'ok  ', seed, d, #chain))
        end
    end
end

local kinds = {}
for k, v in pairs(obstacleKinds) do kinds[#kinds + 1] = k .. '=' .. v end
table.sort(kinds)
local pd = {}
for d, n in pairs(perDiff) do pd[#pd + 1] = 'd' .. d .. '=' .. n end
table.sort(pd)
realPrint(string.format('levels_sweep seeds %d..%d diffs %s: %d levels (%s), %d searches, obstacles {%s}, %d failures, %.1f s cpu',
    from, to, table.concat(diffs, ','), levels, table.concat(pd, ' '), searches, table.concat(kinds, ' '), fails, os.clock() - t0))
os.exit(fails == 0 and 0 or 1)
