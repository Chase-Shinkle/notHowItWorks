-- Focused assertions for branching-maze-levels section 4 (uproot refund).
-- Standalone:  lua tests/maze_refund.lua   (NOT yet run; run once at integration)
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

-- A BackroomsState on the first built-in room, holding `n` seeds of `t`.
local function setup(t, n)
    local back = BackroomsState()
    gStateMachine.current = back
    back:enter(CarryOverGameData(NewGameData({seeds = {[t] = n}})), {BACKROOMS_ROOMS[1]})
    back.gameData.seeds[t] = n
    back.selectedSeed = t
    return back
end

local function standBeside(back, plot)
    back.player:setPosition(plot.pos[1] - 0.5, plot.pos[2], plot.pos[3])
end

local function plantOne(back, t)
    local plot
    for _, p in ipairs(back.room.plots) do if not p.crop and not p.demo then plot = p; break end end
    assert(plot, 'a free plot')
    standBeside(back, plot)
    local ok = back:plant()
    assert(ok, 'planted')
    return plot
end

test('uproot refunds one seed of the crop type for a growing crop and cancels growth', function()
    local back = setup('beanstalk', 2)
    local plot = plantOne(back, 'beanstalk')
    eq(back.gameData.seeds.beanstalk, 1, 'planting spent a seed')
    local crop = plot.crop
    assert(crop.timer, 'still growing')
    standBeside(back, plot)
    local ok, result = back:uproot()
    assert(ok, 'uprooted')
    eq(result.type, 'beanstalk')
    eq(back.gameData.seeds.beanstalk, 2, 'exactly one seed refunded')
    eq(plot.crop, nil, 'plot is free'); eq(#back.room.crops, 0)
    eq(crop.timer, nil, 'pending growth cancelled')
    assert(back.message.text:find('Seed returned', 1, true), 'message mentions the refund')
end)

test('uproot refunds one seed for a grown crop', function()
    local back = setup('beanstalk', 1)
    local plot = plantOne(back, 'beanstalk')
    back.timers:update(600)
    assert(plot.crop.grown, 'fully grown')
    standBeside(back, plot)
    -- stand clear of the grown volume
    back.player:setPosition(plot.pos[1] - 3, plot.pos[2], plot.pos[3])
    local target = back.room:nearestCropPlot(back.player.x, back.player.y, back.player.z)
    if target ~= plot then back.player:setPosition(plot.pos[1] - 0.5, plot.pos[2], plot.pos[3]) end
    local ok = back:uproot()
    assert(ok, 'uprooted')
    eq(back.gameData.seeds.beanstalk, 1, 'seed returned')
    eq(plot.crop, nil)
end)

test('uproot refuses the demo crop and refunds nothing', function()
    local back = setup('beanstalk', 0)
    local demo
    for _, p in ipairs(back.room.plots) do if p.crop and p.crop.demo then demo = p end end
    if not demo then return end -- first room has no demo crop: nothing to assert
    standBeside(back, demo)
    local before = FormatSeeds(back.gameData.seeds)
    local ok, reason = back:uproot()
    eq(ok, false); eq(reason, 'demo')
    eq(FormatSeeds(back.gameData.seeds), before)
    assert(demo.crop, 'demo crop remains')
end)

test('uproot refuses while standing on the crop and refunds nothing', function()
    local back = setup('beanstalk', 1)
    local plot = plantOne(back, 'beanstalk')
    back.timers:update(600)
    local c = plot.crop
    back.player:setPosition(plot.pos[1], plot.pos[2], c.max[3])
    local ok, reason = back:uproot()
    eq(ok, false); eq(reason, 'standing')
    eq(back.gameData.seeds.beanstalk, 0, 'no refund')
    assert(plot.crop == c, 'crop remains')
end)

test('repeated plant and uproot returns the stock to the same value', function()
    local back = setup('beanstalk', 2)
    for _ = 1, 20 do
        local plot = plantOne(back, 'beanstalk')
        eq(back.gameData.seeds.beanstalk, 1)
        standBeside(back, plot)
        assert(back:uproot(), 'uprooted')
        eq(back.gameData.seeds.beanstalk, 2, 'stock restored')
    end
    -- nothing planted: uproot refunds nothing
    local ok = back:uproot()
    eq(ok, false); eq(back.gameData.seeds.beanstalk, 2, 'no free refund')
end)

test('HUD text mentions the uproot refund', function()
    local fh = assert(io.open('src/states/game/BackroomsState.lua', 'r')); local src = fh:read('*a'); fh:close()
    assert(src:find('X: uproot (refund)', 1, true))
end)

realPrint(string.format('\n%d passed, %d failed', passed, failed))
os.exit(failed == 0 and 0 or 1)
