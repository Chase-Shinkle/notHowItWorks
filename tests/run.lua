-- Headless test runner. From the repo root:  lua tests/run.lua  (or luajit)
-- Uses mocked LÖVE/g3d (tests/mock_love.lua); no window or GPU required.
package.path = './?.lua;./?/init.lua;' .. package.path

local realPrint = print
local mock = dofile('tests/mock_love.lua')

local passed, failed = 0, 0
local function test(name, fn)
    mock.install()
    for k in pairs(package.loaded) do
        if k:match('^src/') or k == 'main' then package.loaded[k] = nil end
    end
    arg = {}
    local ok, err = pcall(fn)
    print = realPrint
    if ok then passed = passed + 1; print('PASS ' .. name)
    else failed = failed + 1; print('FAIL ' .. name .. '\n     ' .. tostring(err)) end
end

local function eq(a, b, msg)
    if a ~= b then error((msg or 'expected equal') .. ': got ' .. tostring(a) .. ', want ' .. tostring(b), 2) end
end

local function loadGame(args)
    arg = args or {}
    dofile('main.lua')
    love.load()
end

local function step()
    love.update(1 / 60)
end

local function find(list, pattern)
    for _, line in ipairs(list) do if line:find(pattern, 1, true) then return line end end
end

-- 1.1 render path ------------------------------------------------------------
test('push states render through push with depth disabled', function()
    loadGame()
    mock.reset()
    love.draw()
    eq(mock.count('push.apply'), 2, 'push start/end')
    eq(mock.count('model.draw'), 0, 'no 3D in start state')
    local depth = mock.calls[1]
    eq(depth.name, 'setDepthMode'); eq(#depth.args, 0, 'depth disabled for push path')
end)

test('backrooms opts out of push and draws g3d with depth then HUD without', function()
    loadGame()
    mock.press('f1'); step()          -- start -> farm
    mock.press('f1'); step()          -- farm -> backrooms
    mock.reset()
    love.draw()
    eq(mock.count('push.apply'), 0, 'push bypassed')
    eq(mock.count('model.draw'), 3, 'cube, cross cube, floor drawn')
    local first = mock.calls[1]
    eq(first.name, 'setDepthMode'); eq(first.args[1], 'lequal'); eq(first.args[2], true)
    -- the depth reset must come after every model draw (HUD drawn last)
    local lastDraw, lastDepthOff = 0, 0
    for i, c in ipairs(mock.calls) do
        if c.name == 'model.draw' then lastDraw = i end
        if c.name == 'setDepthMode' and #c.args == 0 then lastDepthOff = i end
    end
    assert(lastDepthOff > lastDraw, 'HUD depth disable after 3D')
    assert(mock.count('print') > 0, 'HUD text printed')
end)

-- 1.2 states and debug transitions -------------------------------------------
test('start -> farm -> backrooms -> start via debug key', function()
    loadGame()
    assert(gStateMachine.current.usesPush ~= false, 'start uses push')
    mock.press('f1'); step()
    eq(gStateMachine.current.usesPush, true, 'farm state')
    assert(gStateMachine.current.gameData, 'farm has game data')
    mock.press('f1'); step()
    eq(gStateMachine.current.usesPush, false, 'backrooms state')
    mock.press('f1'); step()
    assert(gStateMachine.current.usesPush == nil, 'back at start')
end)

test('debug key is ignored when DEBUG_MODE is off', function()
    loadGame()
    DEBUG_MODE = false
    mock.press('f1'); step()
    assert(gStateMachine.current.usesPush == nil, 'still at start')
    mock.press('return'); step()
    eq(gStateMachine.current.usesPush, true, 'enter still starts the farm')
end)

-- 1.3 shared game data --------------------------------------------------------
test('new game data has seeds, coins, crops, hasSold', function()
    loadGame()
    local d = NewGameData()
    eq(d.seeds.beanstalk, 2); eq(d.seeds.pumpkin, 2); eq(d.seeds.vine, 2)
    eq(d.coins, 0); eq(type(d.crops), 'table'); eq(d.hasSold, false)
    local o = NewGameData({seeds = {pumpkin = 5}, coins = 3, hasSold = true})
    eq(o.seeds.pumpkin, 5); eq(o.seeds.beanstalk, 0); eq(o.coins, 3); eq(o.hasSold, true)
    eq(FormatSeeds(o.seeds), 'beanstalk=0 pumpkin=5 vine=0')
    -- STARTING_SEEDS must not be aliased into game data
    d.seeds.vine = 99
    eq(STARTING_SEEDS.vine, 2)
end)

test('the same game-data table flows farm -> backrooms and seeds are printed', function()
    loadGame()
    mock.press('f1'); step()
    local farmData = gStateMachine.current.gameData
    farmData.seeds.vine = 7
    mock.press('f1'); step()
    assert(gStateMachine.current.gameData == farmData, 'same table passed through change')
    assert(find(mock.printed, '[backrooms] seeds received: beanstalk=2 pumpkin=2 vine=7'), 'seeds printed')
end)

-- 1.4 placeholder fallbacks ---------------------------------------------------
test('missing files fall back to flat-color images and silent sounds', function()
    loadGame()
    local img, isPh = Assets.loadImage('graphics/does-not-exist.png', {0.1, 0.2, 0.3, 1})
    eq(isPh, true); eq(img:getWidth(), 16)
    eq(img.source.color[1], 0.1); eq(img.source.color[3], 0.3)
    local snd, sndPh = Assets.loadSound('sounds/nope.wav')
    eq(sndPh, true)
    snd:play(); snd:stop(); snd:setLooping(true); snd:setVolume(0.5)
    eq(snd:isPlaying(), false)
    assert(snd:clone().isPlaceholder, 'clone is a stub')
    local _, fontPh = Assets.loadFont('fonts/nope.ttf', 12)
    eq(fontPh, true)
end)

test('existing files load for real', function()
    loadGame()
    local _, isPh = Assets.loadImage('graphics/Farming - Crops Pack 017/Ground/Tiles - Grass - 01.png')
    eq(isPh, false)
end)

test('game launches with every asset forced to placeholders', function()
    loadGame({'.', '--placeholder-assets'})
    eq(Assets.forcePlaceholders, true)
    for _, key in ipairs({'grass', 'soil', 'hero', 'wall', 'floor'}) do
        assert(gTextures[key], 'texture ' .. key)
    end
    assert(gSounds['plant'].isPlaceholder, 'sound placeholder')
    mock.press('f1'); step(); love.draw()
    mock.press('f1'); step(); love.draw()
    eq(gStateMachine.current.usesPush, false, 'reached backrooms')
end)

-- geometry ---------------------------------------------------------------------
test('box verts have 36 vertices with outward-facing winding', function()
    loadGame()
    local v = NewBoxVerts(2, 4, 6)
    eq(#v, 36)
    for i = 1, 36, 3 do
        local a, b, c = v[i], v[i + 1], v[i + 2]
        local ux, uy, uz = b[1] - a[1], b[2] - a[2], b[3] - a[3]
        local wx, wy, wz = c[1] - a[1], c[2] - a[2], c[3] - a[3]
        local nx, ny, nz = uy * wz - uz * wy, uz * wx - ux * wz, ux * wy - uy * wx
        assert(nx * a[6] + ny * a[7] + nz * a[8] > 0, 'triangle ' .. i .. ' winding matches normal')
        eq(#a, 12, 'g3d vertex layout')
        assert(math.abs(a[1]) == 1 and math.abs(a[2]) == 2 and math.abs(a[3]) == 3, 'corner on box')
    end
end)

realPrint(string.format('\n%d passed, %d failed', passed, failed))
os.exit(failed == 0 and 0 or 1)
