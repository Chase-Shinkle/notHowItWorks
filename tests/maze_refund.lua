-- Focused assertions for branching-maze-levels section 4 (uproot refund).
-- Standalone:  lua tests/maze_refund.lua   (unrun; check_all.sh runs it once)
package.path = './?.lua;./?/init.lua;' .. package.path
local realPrint = print
local mock = dofile('tests/mock_love.lua')
mock.install()
arg = {}
dofile('main.lua')
love.load()
print = function() end

local passed, failed = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then passed = passed + 1; realPrint('PASS ' .. name)
    else failed = failed + 1; realPrint('FAIL ' .. name .. '\n     ' .. tostring(err)) end
end
local function eq(a, b, m) if a ~= b then error((m or 'eq') .. ': got ' .. tostring(a) .. ', want ' .. tostring(b), 2) end end

-- Fixtures use real room data and the positions tests/run.lua uses: room 2 (pit-and-gap)
-- has the free plot 'pit' (plant from the rim at x = -4.6) and room 1 has the demo plot.
local ROOM_PIT = BACKROOMS_ROOMS[2]
local ROOM_DEMO = BACKROOMS_ROOMS[1]
local RIM = {-4.6, 0, 0}

local function setup(room, t, n)
    local back = BackroomsState()
    gStateMachine.current = back
    back:enter(CarryOverGameData(NewGameData({seeds = {[t] = n}})), {room})
    back.gameData.seeds[t] = n
    back.selectedSeed = t
    return back
end

local function atRim(back) back.player:setPosition(RIM[1], RIM[2], RIM[3]) end

local function plantPit(back, t)
    atRim(back)
    local plot = back.room:plotById('pit')
    assert(plot and not plot.crop, 'free pit plot')
    local ok, why = back:plant()
    assert(ok, 'planted: ' .. tostring(why))
    return plot
end

local function grow(back)
    Timer.update(CROP_DEFS.pumpkin.growTime + 0.01, back.timers)
    back.room:updateCrops({1000, 1000, 1000}, {1001, 1001, 1001})
end

test('uproot refunds one seed of the crop type for a growing crop and cancels growth', function()
    local back = setup(ROOM_PIT, 'pumpkin', 2)
    local plot = plantPit(back, 'pumpkin')
    eq(back.gameData.seeds.pumpkin, 1, 'planting spent a seed')
    local crop = plot.crop
    assert(crop.timer, 'still growing')
    atRim(back)
    local ok, result = back:uproot()
    assert(ok, 'uprooted')
    eq(result.type, 'pumpkin')
    eq(back.gameData.seeds.pumpkin, 2, 'exactly one seed refunded')
    eq(plot.crop, nil, 'plot is free'); eq(#back.room.crops, 0)
    eq(crop.timer, nil, 'pending growth cancelled')
    assert(back.message.text:find('Seed returned', 1, true), 'message mentions the refund')
end)

test('uproot refunds one seed for a grown crop', function()
    local back = setup(ROOM_PIT, 'pumpkin', 1)
    local plot = plantPit(back, 'pumpkin')
    grow(back)
    assert(plot.crop.grown, 'fully grown')
    atRim(back)
    local ok = back:uproot()
    assert(ok, 'uprooted')
    eq(back.gameData.seeds.pumpkin, 1, 'seed returned')
    eq(plot.crop, nil)
end)

test('uproot refuses the demo crop and refunds nothing', function()
    local back = setup(ROOM_DEMO, 'beanstalk', 0)
    local demo = back.room:plotById('demo')
    assert(demo and demo.crop and demo.crop.demo, 'room 1 has the demo crop')
    back.player:setPosition(0, 0, 0)
    local before = FormatSeeds(back.gameData.seeds)
    local ok, reason = back:uproot()
    eq(ok, false); eq(reason, 'demo')
    eq(FormatSeeds(back.gameData.seeds), before)
    assert(demo.crop, 'demo crop remains')
end)

test('uproot refuses while standing on the crop and refunds nothing', function()
    local back = setup(ROOM_PIT, 'pumpkin', 1)
    local plot = plantPit(back, 'pumpkin')
    grow(back)
    local c = plot.crop
    eq(c.active, true)
    back.player:setPosition(-2.7, 0, c.max[3])
    local ok, reason = back:uproot()
    eq(ok, false); eq(reason, 'standing')
    eq(back.gameData.seeds.pumpkin, 0, 'no refund')
    assert(plot.crop == c, 'crop remains')
end)

test('repeated plant and uproot returns the stock to the same value', function()
    local back = setup(ROOM_PIT, 'pumpkin', 2)
    for _ = 1, 20 do
        local plot = plantPit(back, 'pumpkin')
        eq(back.gameData.seeds.pumpkin, 1)
        atRim(back)
        assert(back:uproot(), 'uprooted')
        eq(back.gameData.seeds.pumpkin, 2, 'stock restored')
        eq(plot.crop, nil)
    end
    -- nothing planted: uproot refunds nothing
    local ok = back:uproot()
    eq(ok, false); eq(back.gameData.seeds.pumpkin, 2, 'no free refund')
end)

test('HUD text mentions the uproot refund', function()
    local fh = assert(io.open('src/states/game/BackroomsState.lua', 'r')); local src = fh:read('*a'); fh:close()
    assert(src:find('X: uproot (refund)', 1, true))
end)

realPrint(string.format('\n%d passed, %d failed', passed, failed))
os.exit(failed == 0 and 0 or 1)
