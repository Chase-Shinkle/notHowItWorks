-- Section 3 (branch plots) assertions for the branching maze. Standalone;
-- check_all.sh runs it once (not wired into tests/run.lua):  luajit tests/maze_branches.lua
-- (or lua / love tests/love_runner tests/maze_branches.lua). Env: BRANCH_SEEDS (150).
package.path = './?.lua;./?/init.lua;' .. package.path
local realPrint = print
local mock = dofile('tests/mock_love.lua')
mock.install()
arg = {}
dofile('main.lua')
love.load()
print = realPrint

local N = tonumber(os.getenv('BRANCH_SEEDS')) or 150
local fails = 0
local function bad(msg) fails = fails + 1; print('FAIL ' .. msg) end
local function key(cx, cy) return cx .. ',' .. cy end

local stats = {alcoves = 0, decoys = 0, rewards = 0, shortcuts = 0, levels = 0, minExtra = math.huge}
for d = 1, #LEVELGEN_DIFFICULTY do
    for seed = 1, N do
        local data = LevelGen.generate(seed, d)   -- runs LevelGen.check (incl. checkBranches)
        local m, tag = data.meta, 'seed ' .. seed .. ' diff ' .. d
        stats.levels = stats.levels + 1
        -- 3.2: at least two more plots than critical obstacles
        if #data.plots < m.obstacles + 2 then bad(tag .. ': plots ' .. #data.plots .. ' < obstacles+2') end
        stats.minExtra = math.min(stats.minExtra, #data.plots - m.obstacles)
        -- section 6 row: at least `branches` optional modules (shortcuts count)
        if #m.optional < LEVELGEN_DIFFICULTY[d].branches then
            bad(tag .. ': optional ' .. #m.optional .. ' < row branches ' .. LEVELGEN_DIFFICULTY[d].branches)
        end
        -- later levels have a shortcut
        if m.obstacles >= 3 and #m.shortcuts < 1 then bad(tag .. ': no shortcut') end
        local ids = {}
        for _, p in ipairs(data.plots) do
            if ids[p.id] then bad(tag .. ': duplicate plot ' .. p.id) end
            ids[p.id] = true
        end
        local byKey = {}
        for _, c in ipairs(m.cells) do byKey[key(c.cx, c.cy)] = c end
        -- 3.1: every optional module has a plot and a seed type the level offers
        local offered = {}
        for _, t in ipairs(data.seedTypes) do offered[t] = true end
        for _, o in ipairs(m.optional) do
            if not ids[o.plot] then bad(tag .. ': optional plot missing ' .. o.plot) end
            if not offered[o.seed] then bad(tag .. ': seed type not offered ' .. o.seed) end
            if o.shortcut then stats.shortcuts = stats.shortcuts + 1
            elseif o.reward == 'empty' then stats.decoys = stats.decoys + 1
            else stats.rewards = stats.rewards + 1 end
            if not o.shortcut and o.kind == 'alcove' then stats.alcoves = stats.alcoves + 1 end
            -- the module's own supply seed lies outside every optional area
            local sc = byKey[key(o.supply[1], o.supply[2])]
            if sc.opt or sc.optional then bad(tag .. ': supply seed inside optional space') end
        end
        -- 3.3: critical seeds sit outside optional areas, in regions before their obstacle
        for _, p in ipairs(data.pickups) do
            local cx, cy = LevelGen.cellOf(p.pos[1], p.pos[2])
            local c = byKey[key(cx, cy)]
            if p.tier == 'critical' then
                if c.opt or c.optional then bad(tag .. ': critical seed in optional space') end
                if c.region >= p.obstacle then bad(tag .. ': critical seed not before obstacle ' .. p.obstacle) end
            end
        end
        -- critical-only run: only chain seeds, every obstacle in order, exit reached
        -- (checkBranches/check proved: exit + critical seeds reachable with optionals blocked,
        -- prefix sufficiency per obstacle). Re-assert through the public checker:
        local ok, why = LevelGen.checkBranches(data)
        if not ok then bad(tag .. ': ' .. tostring(why)) end
        -- mutation: dropping an area's module link-block must be caught (area reachable early)
        for _, o in ipairs(m.optional) do
            if not o.shortcut then
                local mk = key(o.cell[1], o.cell[2])
                local saved = byKey[mk].optional
                byKey[mk].optional = nil     -- module no longer blocks
                if LevelGen.checkBranches(data) then bad(tag .. ': unblocked optional module not detected') end
                byKey[mk].optional = saved
                break
            end
        end
    end
end
assert(stats.alcoves + stats.decoys + stats.rewards > 0, 'no optional areas generated at all')
assert(stats.decoys > 0 and stats.rewards > 0, 'need both decoys and extra-seed areas')
assert(stats.shortcuts > 0, 'need shortcuts')
print(string.format('maze_branches: %d levels, decoys=%d rewards=%d alcoves=%d shortcuts=%d minExtraPlots=%d fails=%d',
    stats.levels, stats.decoys, stats.rewards, stats.alcoves, stats.shortcuts, stats.minExtra, fails))
os.exit(fails == 0 and 0 or 1)
