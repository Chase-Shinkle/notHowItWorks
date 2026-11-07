-- Focused assertions for branching-maze-levels 5.1-5.2 (checkpoints / respawn).
-- Written, NOT run (check_all.sh runs it once). From repo root:  lua tests/maze_checkpoints.lua
package.path = './?.lua;./?/init.lua;' .. package.path
local mock = dofile('tests/mock_love.lua')
mock.install()
arg = {}
dofile('main.lua')
love.load()
local realPrint = print
print = function() end

local function check(c, msg) if not c then error(msg, 2) end end
local fails = 0
local function test(name, fn)
    local ok, err = pcall(fn)
    realPrint((ok and 'PASS ' or 'FAIL ') .. name .. (ok and '' or ('\n     ' .. tostring(err))))
    if not ok then fails = fails + 1 end
end

local function newState(seed, difficulty)
    local data = LevelGen.generate(seed, difficulty)
    local back = BackroomsState()
    gStateMachine.current = back
    back:enter(CarryOverGameData(NewGameData()), {data})
    return back, data
end

test('5.1 checkpoints exist per region on plain floor, never on a plot/crop/module', function()
    for seed = 1, 20 do
        local back, data = newState(seed, 3)
        local room, cps = back.room, back.room.checkpoints
        for _, reg in ipairs(data.meta.regions) do
            local cp = cps[reg.index + 1]
            check(cp, 'checkpoint for region ' .. reg.index)
            check(room:regionAt(cp[1], cp[2]) == reg.index, 'checkpoint inside its region')
            if reg.index > 0 then check(math.abs(cp[3] - reg.elev) < 1e-6, 'at region elevation') end
            for _, p in ipairs(data.plots) do
                check(math.abs(p.pos[1] - cp[1]) >= LEVELGEN_CELL / 2 or math.abs(p.pos[2] - cp[2]) >= LEVELGEN_CELL / 2,
                    'checkpoint not in a plot cell')
            end
            for _, c in ipairs(data.meta.cells) do
                local mx, my = LevelGen.cellCenter(c.cx, c.cy)
                if math.abs(mx - cp[1]) < 1e-6 and math.abs(my - cp[2]) < 1e-6 and reg.index > 0 then
                    check(not (c.optional or c.opt or c.shortcut or c.start or c.exit), 'checkpoint cell is not optional / start / exit')
                end
                if c.kind == 'module' then
                    check(math.abs(mx - cp[1]) > 1e-6 or math.abs(my - cp[2]) > 1e-6, 'not in a module cell')
                end
            end
        end
        check(cps[1][1] == room.spawn[1] and cps[1][2] == room.spawn[2], 'region 0 checkpoint is the spawn')
    end
end)

test('5.1 entering a new region updates the current checkpoint', function()
    local back, data = newState(7, 3)
    check(back.checkpointRegion == 0, 'starts at the spawn region')
    local r = #data.meta.regions - 1
    check(r >= 1, 'level has a later region')
    local cp = back.room.checkpoints[r + 1]
    back.player:setPosition(cp[1], cp[2], cp[3])
    back:updateCheckpoint()
    check(back.checkpointRegion == r, 'checkpoint is now region ' .. r)
end)

test('5.2 killZ respawns at the checkpoint, keeping crops, seeds and pickups', function()
    local back, data = newState(7, 3)
    local r = #data.meta.regions - 1
    local cp = back.room.checkpoints[r + 1]
    back.player:setPosition(cp[1], cp[2], cp[3])
    back:updateCheckpoint()
    back.gameData.seeds.beanstalk = 3
    local crops, pickups = #back.room.crops, #back.room.pickups
    back.player:setPosition(cp[1], cp[2], back.room.killZ - 5)
    back:update(1 / 60)
    check(math.abs(back.player.x - cp[1]) < 0.5 and math.abs(back.player.y - cp[2]) < 0.5, 'back at checkpoint, not spawn')
    check(back.player.z > back.room.killZ, 'above killZ again')
    check(back.gameData.seeds.beanstalk == 3, 'seeds kept')
    check(#back.room.crops == crops and #back.room.pickups == pickups, 'crops and pickups kept')
end)

test('5.2 reset returns to the spawn and the spawn region checkpoint', function()
    local back = newState(7, 3)
    local r = #back.room.checkpoints - 1
    local cp = back.room.checkpoints[r + 1]
    back.player:setPosition(cp[1], cp[2], cp[3])
    back:updateCheckpoint()
    back:resetRoom()
    local s = back.room.spawn
    check(math.abs(back.player.x - s[1]) < 1e-6 and math.abs(back.player.y - s[2]) < 1e-6, 'at spawn')
    check(back.checkpointRegion == 0, 'checkpoint reset to region 0')
    check(not back.visitedRegions[r] or r == 0, 'visited regions cleared')
end)

realPrint(fails == 0 and 'all passed' or (fails .. ' failed'))
os.exit(fails == 0 and 0 or 1)
