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

-- Is `state` an instance of the state class `cls` (e.g. EndingState)?
local function isState(state, cls)
    return state ~= nil and state.update == cls.update and state.render == cls.render
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
    local room = gStateMachine.current.room
    eq(mock.count('model.draw'), #room.models + #room.plots + #room.crops + 1 + #room.billboards,
        'room boxes, plots, crops, exit marker and billboards drawn')
    assert(#room.crops >= 1, 'room 1 draws its demo crop')
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
test('start -> farm -> backrooms rooms -> ending -> start via debug key', function()
    loadGame()
    assert(gStateMachine.current.usesPush ~= false, 'start uses push')
    mock.press('f1'); step()
    eq(gStateMachine.current.usesPush, true, 'farm state')
    assert(gStateMachine.current.gameData, 'farm has game data')
    mock.press('f1'); step()
    local back = gStateMachine.current
    eq(back.usesPush, false, 'backrooms state')
    -- in the backrooms the debug key skips the current room
    for i = 1, #BACKROOMS_ROOMS do
        eq(gStateMachine.current, back, 'still in the backrooms')
        eq(back.roomIndex, i, 'room ' .. i)
        mock.press('f1'); step()
    end
    assert(isState(gStateMachine.current, EndingState), 'ending state')
    mock.press('f1'); step()
    assert(isState(gStateMachine.current, StartState), 'back at start')
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
    eq(d.crops.beanstalk, 0); eq(d.crops.pumpkin, 0); eq(d.crops.vine, 0)
    local o = NewGameData({seeds = {pumpkin = 5}, coins = 3, hasSold = true})
    eq(o.seeds.pumpkin, 5); eq(o.seeds.beanstalk, 0); eq(o.coins, 3); eq(o.hasSold, true)
    eq(FormatSeeds(o.seeds), 'beanstalk=0 pumpkin=5 vine=0')
    -- STARTING_SEEDS must not be aliased into game data
    d.seeds.vine = 99
    eq(STARTING_SEEDS.vine, 2)
end)

test('debug farm -> backrooms carries seeds only (via CarryOverGameData) and prints them', function()
    loadGame()
    mock.press('f1'); step()
    local farmData = gStateMachine.current.gameData
    farmData.seeds.vine = 7
    farmData.coins = 12; farmData.crops.pumpkin = 3; farmData.hasSold = true
    mock.press('f1'); step()
    local back = gStateMachine.current
    assert(back.gameData ~= farmData, 'a fresh carried-over table, not the farm table')
    eq(FormatSeeds(back.gameData.seeds), 'beanstalk=2 pumpkin=2 vine=7', 'seeds kept')
    eq(back.gameData.coins, 0, 'coins do not leak through the debug skip')
    eq(back.gameData.crops.pumpkin, 0, 'crops do not leak through the debug skip')
    eq(back.gameData.hasSold, true)
    eq(farmData.coins, 12, 'farm data untouched')
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


-- 2. farm ----------------------------------------------------------------------
local function toFarm(args)
    loadGame(args)
    mock.press('return'); step()
    local farm = gStateMachine.current
    assert(farm.plots and farm.player, 'in farm state')
    return farm
end

-- simulate `seconds` of frames at 60 fps; returns frames run
local function run(seconds)
    local frames = math.floor(seconds * 60 + 0.5)
    for _ = 1, frames do step() end
    return frames
end

local function press(key)
    mock.press(key); step()
end

local function plotAt(farm, col, row) return farm:plotAt(col, row) end

test('farm: new game has seeds, an empty plot and a villager on screen', function()
    local farm = toFarm()
    assert(Farm.totalSeeds(farm.gameData) >= 1, 'at least one seed')
    eq(#farm.plots, FARM_PLOTS.cols * FARM_PLOTS.rows, 'plot count')
    for _, plot in ipairs(farm.plots) do eq(plot.state, PLOT_EMPTY) end
    local vx, vy = FarmTileToPixel(FARM_VILLAGER.col, FARM_VILLAGER.row)
    assert(vx >= 0 and vy >= FARM_TILE and vx + FARM_TILE <= VIRTUAL_WIDTH
        and vy + FARM_TILE <= VIRTUAL_HEIGHT - FARM_TILE, 'villager inside the field')
    -- farmer starts facing an empty plot: the first E press plants
    local target = farm:facingTarget()
    eq(target and target.kind, 'plot'); eq(target.plot.state, PLOT_EMPTY)
    eq(farm.gameData.coins, 0); eq(Farm.totalCrops(farm.gameData), 0)
end)

test('farm: grid movement, blocking and bounds', function()
    local farm = toFarm()
    local p = farm.player
    press('right'); eq(p.col, FARM_PLAYER_START.col + 1); eq(p.facing, 'right')
    press('d'); eq(p.col, FARM_PLAYER_START.col + 2, 'WASD works')
    press('left'); press('left'); eq(p.col, FARM_PLAYER_START.col)
    -- up is a plot: turn but do not step onto it
    press('up'); eq(p.row, FARM_PLAYER_START.row); eq(p.facing, 'up')
    -- walk down to the bottom edge; the hint bar row is not walkable
    for _ = 1, 10 do press('s') end
    eq(p.row, FARM_FIELD_BOTTOM)
    for _ = 1, 15 do press('a') end
    eq(p.col, 1)
    -- the villager tile blocks movement
    farm.player.col, farm.player.row = FARM_VILLAGER.col - 1, FARM_VILLAGER.row
    press('right')
    eq(p.col, FARM_VILLAGER.col - 1, 'villager blocks'); eq(farm:facingTarget().kind, 'villager')
    -- the HUD row is not walkable
    farm.player.col, farm.player.row = 1, FARM_FIELD_TOP
    press('up'); eq(p.row, FARM_FIELD_TOP)
end)

test('farm: holding a direction repeats steps', function()
    local farm = toFarm()
    mock.press('right'); mock.hold('right'); step()
    eq(farm.player.col, FARM_PLAYER_START.col + 1)
    run(FARM_MOVE_REPEAT_DELAY + FARM_MOVE_REPEAT_INTERVAL * 2 + 0.05)
    assert(farm.player.col >= FARM_PLAYER_START.col + 3, 'repeat moved, col=' .. farm.player.col)
    mock.release('right')
    local col = farm.player.col
    run(0.5)
    eq(farm.player.col, col, 'stops on release')
end)

test('farm: facing target is highlighted', function()
    local farm = toFarm()
    mock.reset(); love.draw()
    local tx, ty = FarmTileToPixel(farm:facingTile())
    local found = false
    for _, c in ipairs(mock.calls) do
        if c.name == 'rectangle' and c.args[1] == 'line' and c.args[2] == tx + 1.5 and c.args[3] == ty + 1.5 then
            found = true
        end
    end
    assert(found, 'highlight rectangle on facing plot')
    -- facing nothing: no highlight
    press('down'); press('down')
    assert(farm:facingTarget() == nil, 'facing grass')
    eq(farm:hintText(), 'WASD/arrows move  E use  1-3 seed  or click')
end)

test('farm: planting consumes one seed of the selected type', function()
    local farm = toFarm()
    local d = farm.gameData
    eq(farm.selectedSeed, 'beanstalk')
    press('2'); eq(farm.selectedSeed, 'pumpkin')
    eq(farm:hintText(), '[E] plant pumpkin')
    press('e')
    local plot = farm:facingTarget().plot
    eq(plot.state, PLOT_GROWING); eq(plot.seedType, 'pumpkin'); eq(plot.stage, 1)
    eq(d.seeds.pumpkin, STARTING_SEEDS.pumpkin - 1)
    eq(d.seeds.beanstalk, STARTING_SEEDS.beanstalk, 'other seeds untouched')
    -- interacting again with a growing plot plants nothing more
    press('space')
    eq(d.seeds.pumpkin, STARTING_SEEDS.pumpkin - 1)
    eq(farm:hintText(), 'pumpkin growing...')
end)

test('farm: planting with no seeds does nothing', function()
    loadGame()
    gStateMachine:change('farm', NewGameData({seeds = {}}))
    local farm = gStateMachine.current
    eq(Farm.totalSeeds(farm.gameData), 0)
    eq(farm:hintText(), 'no seeds left')
    press('e')
    eq(farm:facingTarget().plot.state, PLOT_EMPTY)
    eq(FormatSeeds(farm.gameData.seeds), 'beanstalk=0 pumpkin=0 vine=0')
end)

test('farm: empty selected type falls back to a type that has seeds', function()
    loadGame()
    gStateMachine:change('farm', NewGameData({seeds = {vine = 1}}))
    local farm = gStateMachine.current
    farm:selectSeed('beanstalk')
    eq(farm:hintText(), '[E] plant vine')
    press('e')
    eq(farm:facingTarget().plot.seedType, 'vine'); eq(farm.gameData.seeds.vine, 0)
    eq(farm.selectedSeed, 'vine')
end)

test('farm: seed cycling with tab/q and number keys', function()
    local farm = toFarm()
    press('tab'); eq(farm.selectedSeed, 'pumpkin')
    press('q'); eq(farm.selectedSeed, 'vine')
    press('tab'); eq(farm.selectedSeed, 'beanstalk')
    press('3'); eq(farm.selectedSeed, 'vine')
    press('kp1'); eq(farm.selectedSeed, 'beanstalk')
end)

test('farm: crops grow through visible stages on the Timer and mature', function()
    local farm = toFarm()
    press('e')
    local plot = farm:facingTarget().plot
    eq(plot.stage, 1)
    run(FARM_STAGE_TIME + 0.05); eq(plot.stage, 2); eq(plot.state, PLOT_GROWING)
    run(FARM_STAGE_TIME); eq(plot.stage, 3)
    -- the drawn sprite follows the stage
    mock.reset(); love.draw()
    local stageTex = gTextures['crop-beanstalk-3']
    local drawn = false
    for _, c in ipairs(mock.calls) do if c.name == 'draw' and c.args[1] == stageTex then drawn = true end end
    assert(drawn, 'stage 3 sprite drawn')
    run(FARM_STAGE_TIME * (FARM_GROWTH_STAGES - 3))
    eq(plot.state, PLOT_MATURE); eq(plot.stage, FARM_GROWTH_STAGES)
    eq(#farm.timers, 0, 'growth timer removed once mature')
    -- stays mature
    run(FARM_STAGE_TIME * 3); eq(plot.stage, FARM_GROWTH_STAGES)
    mock.reset(); love.draw()
    local matureTex = gTextures['crop-beanstalk-' .. FARM_GROWTH_STAGES]
    drawn = false
    for _, c in ipairs(mock.calls) do if c.name == 'draw' and c.args[1] == matureTex then drawn = true end end
    assert(drawn, 'mature sprite drawn')
end)

test('farm: a crop matures after exactly its growth duration, not before', function()
    local farm = toFarm()
    press('e')
    local plot = farm:facingTarget().plot
    local total = FARM_STAGE_TIME * (FARM_GROWTH_STAGES - 1)
    run(total - 0.1)
    eq(plot.state, PLOT_GROWING, 'not yet mature')
    run(0.2)
    eq(plot.state, PLOT_MATURE)
end)

test('farm: immature crops cannot be harvested', function()
    local farm = toFarm()
    press('e')
    run(FARM_STAGE_TIME + 0.05)
    press('e')
    local plot = farm:facingTarget().plot
    eq(plot.state, PLOT_GROWING); eq(plot.stage, 2)
    eq(Farm.totalCrops(farm.gameData), 0, 'inventory unchanged')
end)

test('farm: harvesting a mature crop adds it to the inventory and clears the plot', function()
    local farm = toFarm()
    press('e')
    run(FARM_STAGE_TIME * FARM_GROWTH_STAGES)
    local plot = farm:facingTarget().plot
    eq(farm:hintText(), '[E] harvest beanstalk')
    press('e')
    eq(plot.state, PLOT_EMPTY); eq(plot.seedType, nil); eq(plot.stage, 0)
    eq(farm.gameData.crops.beanstalk, 1)
    eq(farm.gameData.seeds.beanstalk, STARTING_SEEDS.beanstalk - 1, 'harvest gives a crop, not a seed')
    -- the plot can be replanted
    press('e'); eq(plot.state, PLOT_GROWING)
end)

test('farm: selling to the villager adds coins and removes a crop', function()
    loadGame()
    gStateMachine:change('farm', NewGameData({crops = {pumpkin = 2}}))
    local farm = gStateMachine.current
    farm.player.col, farm.player.row, farm.player.facing = FARM_VILLAGER.col - 1, FARM_VILLAGER.row, 'right'
    eq(farm:hintText(), '[E] sell pumpkin (+' .. CROP_VALUES.pumpkin .. 'c)')
    press('e')
    eq(farm.gameData.crops.pumpkin, 1); eq(farm.gameData.coins, CROP_VALUES.pumpkin)
    eq(farm.gameData.hasSold, true)
    press('e')
    eq(farm.gameData.crops.pumpkin, 0); eq(farm.gameData.coins, CROP_VALUES.pumpkin * 2)
end)

test('farm: selling with no crops changes nothing and does not leave the farm', function()
    local farm = toFarm()
    farm.player.col, farm.player.row, farm.player.facing = FARM_VILLAGER.col - 1, FARM_VILLAGER.row, 'right'
    eq(farm:hintText(), 'harvest a crop to sell')
    press('e')
    eq(farm.gameData.coins, 0); eq(farm.gameData.hasSold, false)
    eq(farm.villagerLine.text, 'Got any crops?')
    assert(gStateMachine.current == farm, 'still on the farm')
end)

test('farm: mouse hover highlights and click uses plots, villager and seed slots', function()
    local farm = toFarm()
    -- hover a plot that is not the keyboard target
    local px, py = FarmTileToPixel(FARM_PLOTS.col, FARM_PLOTS.row)
    mock.mouseAt(px + 10, py + 10); step()
    eq(farm.hover.col, FARM_PLOTS.col); eq(farm.hover.row, FARM_PLOTS.row)
    mock.reset(); love.draw()
    local found = false
    for _, c in ipairs(mock.calls) do
        if c.name == 'rectangle' and c.args[1] == 'line' and c.args[2] == px + 3.5 and c.args[3] == py + 3.5 then found = true end
    end
    assert(found, 'hover highlight drawn')
    -- click the third seed slot in the top bar, then click the plot
    mock.mouseAt(4 + 2 * 46 + 10, 10); mock.click(1); step()
    eq(farm.selectedSeed, 'vine')
    mock.mouseAt(px + 10, py + 10); mock.click(1); step()
    local plot = farm:plotAt(FARM_PLOTS.col, FARM_PLOTS.row)
    eq(plot.state, PLOT_GROWING); eq(plot.seedType, 'vine')
    eq(farm.gameData.seeds.vine, STARTING_SEEDS.vine - 1)
    -- click to harvest once mature, then click the villager to sell
    run(FARM_STAGE_TIME * FARM_GROWTH_STAGES)
    mock.mouseAt(px + 10, py + 10); mock.click(1); step()
    eq(farm.gameData.crops.vine, 1)
    local vx, vy = FarmTileToPixel(FARM_VILLAGER.col, FARM_VILLAGER.row)
    mock.mouseAt(vx + 16, vy + 16); mock.click(1); step()
    eq(farm.gameData.crops.vine, 0); eq(farm.gameData.coins, CROP_VALUES.vine)
    -- clicking empty grass does nothing; off-screen mouse clears hover
    mock.mouseAt(FarmTileToPixel(9, 8)); mock.click(1); step()
    eq(farm.gameData.coins, CROP_VALUES.vine)
    mock.mouseAt(-50, -50); step()
    eq(farm.hover, nil)
end)

test('farm: first plant -> harvest -> sell cycle by keyboard finishes well under 3 minutes', function()
    local farm = toFarm()
    local frames = 0
    local function act(key)               -- press, then ~0.25 s of reaction time
        mock.press(key); step(); frames = frames + 1 + run(0.25)
    end
    act('e')                                                       -- plant
    frames = frames + run(FARM_STAGE_TIME * (FARM_GROWTH_STAGES - 1) + 0.1) -- wait
    act('e')                                                       -- harvest
    eq(Farm.totalCrops(farm.gameData), 1, 'harvested')
    -- walk from the start tile to the tile left of the villager
    for _ = 1, FARM_VILLAGER.col - 1 - FARM_PLAYER_START.col do act('right') end
    for _ = 1, FARM_PLAYER_START.row - FARM_VILLAGER.row do act('up') end
    act('right')                                                   -- face villager
    eq(farm:facingTarget().kind, 'villager')
    act('e')                                                       -- sell
    eq(farm.gameData.coins, CROP_VALUES.beanstalk); eq(farm.gameData.hasSold, true)
    local seconds = frames / 60
    assert(seconds < 180, 'cycle took ' .. seconds .. ' s')
    assert(seconds < 30, 'expected a ~20 s cycle, got ' .. seconds .. ' s')
end)

test('farm: growth timers are owned by the farm and cleared on exit', function()
    local farm = toFarm()
    press('e')
    eq(#farm.timers, 1)
    eq(#Timer.defaultGroup, 0, 'growth not on the global group')
    mock.press('f1'); step()
    eq(#farm.timers, 0, 'cleared on leaving the farm')
end)

test('farm: renders HUD and field with every asset as a placeholder', function()
    local farm = toFarm({'.', '--placeholder-assets'})
    press('e')
    run(FARM_STAGE_TIME * 2)
    mock.reset(); love.draw()
    assert(mock.count('draw') > 100, 'field tiles and sprites drawn')
    assert(mock.count('print') + mock.count('printf') > 3, 'HUD text drawn')
    for _, seedType in ipairs(SEED_TYPES) do
        for stage = 1, FARM_GROWTH_STAGES do
            assert(gTextures['crop-' .. seedType .. '-' .. stage], 'stage texture ' .. seedType .. stage)
        end
        assert(gTextures['seedbag-' .. seedType] and gTextures['produce-' .. seedType])
    end
    -- placeholder stages grow
    assert(gTextures['crop-pumpkin-1']:getWidth() < gTextures['crop-pumpkin-5']:getWidth())
end)

test('farm: crop art loads from the pack when present', function()
    loadGame()
    for _, key in ipairs({'crop-pumpkin-1', 'crop-pumpkin-5', 'crop-beanstalk-3', 'crop-vine-4',
            'produce-vine', 'seedbag-beanstalk', 'plot', 'villager'}) do
        eq(gTextures[key].source and type(gTextures[key].source), 'string', key .. ' loaded from file')
    end
end)

test('farm: seeds spent on the farm stay spent in the backrooms (debug skip)', function()
    local farm = toFarm()
    press('e')                                          -- spend one beanstalk seed
    mock.press('f1'); step()
    local back = gStateMachine.current
    eq(back.usesPush, false, 'in backrooms')
    eq(FormatSeeds(back.gameData.seeds), 'beanstalk=1 pumpkin=2 vine=2')
    assert(find(mock.printed, 'beanstalk=1 pumpkin=2 vine=2'), 'spent seed visible in backrooms')
    eq(back.gameData.coins, 0)
end)

test('Farm rules: plant/harvest/sell return values', function()
    loadGame()
    local d = NewGameData({seeds = {pumpkin = 1}})
    local plot = Farm.newPlot(1, 1)
    local group = {}
    local ok, why = Farm.harvest(plot, d); eq(ok, false); eq(why, 'empty')
    ok, why = Farm.plant(plot, d, 'pumpkin', group); eq(ok, true); eq(why, 'pumpkin')
    ok, why = Farm.plant(plot, d, 'pumpkin', group); eq(ok, false); eq(why, 'occupied')
    ok, why = Farm.harvest(plot, d); eq(ok, false); eq(why, 'immature')
    Timer.update(FARM_STAGE_TIME * FARM_GROWTH_STAGES, group)   -- one big step
    eq(plot.state, PLOT_MATURE)
    ok, why = Farm.harvest(plot, d); eq(ok, true); eq(why, 'pumpkin')
    ok, why = Farm.plant(plot, d, 'pumpkin', group); eq(ok, false); eq(why, 'no-seeds')
    local sold, t, v = Farm.sell(d); eq(sold, true); eq(t, 'pumpkin'); eq(v, CROP_VALUES.pumpkin)
    sold, t = Farm.sell(d); eq(sold, false); eq(t, 'no-crops')
    eq(d.coins, CROP_VALUES.pumpkin); eq(d.hasSold, true)
end)

-- 3. the break -----------------------------------------------------------------
local BREAK_TIME = FARM_BREAK_GLITCH_TIME + FARM_BREAK_FALL_TIME

-- A farm started from `overrides`, with the farmer facing the villager.
local function farmAtVillager(overrides, args)
    loadGame(args)
    gStateMachine:change('farm', NewGameData(overrides))
    local farm = gStateMachine.current
    farm.player.col, farm.player.row, farm.player.facing = FARM_VILLAGER.col - 1, FARM_VILLAGER.row, 'right'
    assert(farm:facingTarget().kind == 'villager', 'facing villager')
    return farm
end

-- Records every gStateMachine:change call by state name.
local function countChanges()
    local names = {}
    local original = gStateMachine.change
    gStateMachine.change = function(self, name, data)
        names[#names + 1] = name
        return original(self, name, data)
    end
    return names
end

local function countOf(list, value)
    local n = 0
    for _, v in ipairs(list) do if v == value then n = n + 1 end end
    return n
end

test('break: no break when selling with no crops before any sale', function()
    local farm = farmAtVillager({})
    for _ = 1, 5 do press('e') end
    eq(farm.breaking, false, 'no break before a sale')
    eq(farm.gameData.hasSold, false); eq(farm.gameData.hasBroken, false)
    eq(farm.villagerLine.text, 'Got any crops?')
    -- the idle fallback cannot fire before a sale either
    run(FARM_IDLE_BREAK_TIME + 5)
    eq(farm.breaking, false, 'no idle break before a sale')
    assert(gStateMachine.current == farm, 'still on the farm')
end)

test('break: villager keeps asking for crops after the last one is sold', function()
    local farm = farmAtVillager({crops = {pumpkin = 1}})
    press('e')
    eq(farm.gameData.crops.pumpkin, 0); eq(farm.gameData.hasSold, true)
    eq(farm.breaking, false, 'a normal sale does not break')
    eq(farm.villagerLine.text, 'Thanks! Got another?')
    eq(farm:hintText(), '[E] sell another?')
    -- repeated, cycling requests while out of stock
    run(FARM_VILLAGER_NAG_INTERVAL + 0.05)
    eq(farm.villagerLine.text, FARM_VILLAGER_REQUESTS[1])
    run(FARM_VILLAGER_NAG_INTERVAL)
    eq(farm.villagerLine.text, FARM_VILLAGER_REQUESTS[2])
    -- default bubble also asks for more
    farm.villagerLine = nil
    mock.reset(); love.draw()
    local asked = false
    for _, c in ipairs(mock.calls) do if c.name == 'print' and c.args[1] == 'More crops?' then asked = true end end
    assert(asked, 'bubble asks for more crops')
    eq(farm.breaking, false, 'asking alone does not break')
end)

test('break: over-sell after a sale and stock exhaustion starts the break', function()
    local farm = farmAtVillager({crops = {vine = 2}})
    press('e'); eq(farm.breaking, false, 'first sale')
    press('e'); eq(farm.breaking, false, 'second sale empties stock')
    eq(Farm.totalCrops(farm.gameData), 0)
    assert(Farm.isOverSell(farm.gameData), 'over-sell condition')
    local coins = farm.gameData.coins
    eq(farm:interact(farm:facingTarget()), 'oversell')
    eq(farm.breaking, true); eq(farm.breakReason, 'oversell'); eq(farm.gameData.hasBroken, true)
    eq(farm.gameData.coins, coins, 'over-sell pays nothing real')
    eq(Farm.totalCrops(farm.gameData), 0, 'no negative crops')
    assert(gStateMachine.current == farm, 'sequence plays on the farm first')
end)

test('break: over-sell by mouse click also starts the break', function()
    local farm = farmAtVillager({hasSold = true})
    local vx, vy = FarmTileToPixel(FARM_VILLAGER.col, FARM_VILLAGER.row)
    mock.mouseAt(vx + 16, vy + 16); mock.click(1); step()
    eq(farm.breaking, true); eq(farm.breakReason, 'oversell')
end)

test('break: input is locked while the glitch sequence plays', function()
    local farm = farmAtVillager({hasSold = true, seeds = {beanstalk = 2}})
    -- a mature crop the player could otherwise harvest by click
    local plot = farm:plotAt(FARM_PLOTS.col, FARM_PLOTS.row)
    plot.state, plot.seedType, plot.stage = PLOT_MATURE, 'beanstalk', FARM_GROWTH_STAGES
    local growing = farm:plotAt(FARM_PLOTS.col + 1, FARM_PLOTS.row)
    Farm.plant(growing, farm.gameData, 'beanstalk', farm.timers)
    press('e')
    eq(farm.breaking, true)
    local col, row, facing = farm.player.col, farm.player.row, farm.player.facing
    local seed = farm.selectedSeed
    for _, key in ipairs({'left', 'up', 'down', 'w', 'e', 'space', 'return', '2', '3', 'tab', 'q', 'f1'}) do
        press(key)
    end
    mock.hold('left'); run(0.5); mock.release('left')
    local px, py = FarmTileToPixel(plot.col, plot.row)
    mock.mouseAt(px + 10, py + 10); mock.click(1); step()
    mock.mouseAt(4 + 46 + 10, 10); mock.click(1); step()   -- seed slot 2
    eq(farm.player.col, col); eq(farm.player.row, row); eq(farm.player.facing, facing)
    eq(farm.selectedSeed, seed, 'seed selection locked')
    eq(plot.state, PLOT_MATURE, 'click did not harvest')
    eq(farm.gameData.crops.beanstalk, 0)
    eq(farm.gameData.seeds.beanstalk, 1, 'no planting')
    eq(growing.stage, 1, 'growth frozen during the break')
    eq(farm.hover, nil, 'no hover')
    eq(farm:interact(farm:facingTarget()), nil, 'interact refused')
    eq(farm:interact({kind = 'plot', plot = plot}), nil)
    assert(gStateMachine.current == farm, 'debug key ignored during the break')
end)

test('break: sequence shakes, corrupts and falls, then changes to backrooms exactly once', function()
    local farm = farmAtVillager({hasSold = true})
    local plays = 0
    gSounds['glitch'] = {play = function() plays = plays + 1 end}
    local changes = countChanges()
    press('e')
    eq(farm.breaking, true)
    eq(plays, 1, 'glitch sound on start')
    -- glitch phase: shake and corruption ramp up, no fall yet
    run(FARM_BREAK_GLITCH_TIME * 0.5)
    assert(farm.fx.shake > 0 and farm.fx.corruption > 0, 'glitch ramping')
    eq(farm.fx.fall, 0, 'not falling yet')
    mock.reset(); love.draw()
    assert(mock.count('translate') >= 2, 'shake offsets applied')
    local fillRects = 0
    for _, c in ipairs(mock.calls) do if c.name == 'rectangle' and c.args[1] == 'fill' then fillRects = fillRects + 1 end end
    assert(fillRects > 5, 'corruption blocks drawn')
    -- fall phase
    run(FARM_BREAK_GLITCH_TIME * 0.5 + FARM_BREAK_FALL_TIME * 0.5)
    eq(farm.fx.corruption, 1); eq(plays, 2, 'second glitch sound as the fall starts')
    assert(farm.fx.fall > 0 and farm.fx.fall < 1, 'falling, fall=' .. farm.fx.fall)
    mock.reset(); love.draw()
    assert(mock.count('rotate') + mock.count('draw') > 0, 'falling farmer drawn')
    -- not over until the full duration
    eq(countOf(changes, 'backrooms'), 0, 'no transition mid-sequence')
    assert(gStateMachine.current == farm)
    run(BREAK_TIME * 0.5 + 0.1)
    eq(countOf(changes, 'backrooms'), 1, 'one transition')
    eq(gStateMachine.current.usesPush, false, 'ends in the backrooms')
    eq(#farm.breakTimers, 0, 'sequence timers cleared')
    eq(#farm.timers, 0)
    -- nothing can replay it
    run(BREAK_TIME * 2)
    eq(farm:startBreak('oversell'), false, 'once per game')
    eq(countOf(changes, 'backrooms'), 1, 'still exactly one transition')
    eq(#changes, 1)
end)

test('break: a second trigger during the sequence does not restart it', function()
    local farm = farmAtVillager({hasSold = true})
    local changes = countChanges()
    press('e')
    run(BREAK_TIME * 0.5)
    local fall = farm.fx.fall
    eq(farm:startBreak('idle'), false)
    eq(farm.breakReason, 'oversell')
    farm.idleTimer = FARM_IDLE_BREAK_TIME * 2
    run(BREAK_TIME * 0.5 + 0.1)
    assert(farm.fx.fall >= fall)
    eq(countOf(changes, 'backrooms'), 1)
end)

test('break: farm re-entered with already-broken data cannot break again', function()
    loadGame()
    local changes = countChanges()
    gStateMachine:change('farm', NewGameData({hasSold = true, hasBroken = true}))
    local farm = gStateMachine.current
    farm.player.col, farm.player.row, farm.player.facing = FARM_VILLAGER.col - 1, FARM_VILLAGER.row, 'right'
    eq(farm:interact(farm:facingTarget()), 'no-crops')
    run(FARM_IDLE_BREAK_TIME + BREAK_TIME + 1)
    eq(farm.breaking, false)
    eq(countOf(changes, 'backrooms'), 0)
end)

test('carry-over: low-seed arrival is topped up to the first room minimum', function()
    local farm = farmAtVillager({seeds = {}, coins = 7, hasSold = true})
    eq(Farm.totalSeeds(farm.gameData), 0)
    press('e'); run(BREAK_TIME + 0.1)
    local back = gStateMachine.current
    eq(back.usesPush, false, 'in backrooms')
    for _, seedType in ipairs(SEED_TYPES) do
        eq(back.gameData.seeds[seedType], FIRST_ROOM_MIN_SEEDS[seedType] or 0, seedType .. ' topped up')
    end
    eq(back.gameData.seeds.beanstalk >= 1, true, 'can finish the tutorial room')
    eq(back.gameData.coins, 0, 'coins dropped')
    eq(Farm.totalCrops(back.gameData), 0, 'crops dropped')
    assert(find(mock.printed, '[backrooms] seeds received: ' .. FormatSeeds(back.gameData.seeds)), 'printed')
    eq(farm.gameData.coins, 7, 'farm data untouched')
end)

test('carry-over: high-seed arrival keeps exactly the seeds held at the break', function()
    local farm = farmAtVillager({seeds = {beanstalk = 5, pumpkin = 3, vine = 4}, coins = 20,
        crops = {pumpkin = 1}})
    -- plant one vine on the farm, sell the last crop, then over-sell
    local plot = farm:plotAt(FARM_PLOTS.col, FARM_PLOTS.row)
    Farm.plant(plot, farm.gameData, 'vine', farm.timers)
    press('e'); eq(farm.gameData.hasSold, true)
    press('e'); eq(farm.breaking, true)
    run(BREAK_TIME + 0.1)
    local back = gStateMachine.current
    eq(back.usesPush, false, 'in backrooms')
    assert(back.gameData ~= farm.gameData, 'a fresh table, not the farm data')
    eq(FormatSeeds(back.gameData.seeds), 'beanstalk=5 pumpkin=3 vine=3')
    eq(back.gameData.coins, 0); eq(Farm.totalCrops(back.gameData), 0)
    assert(find(mock.printed, '[backrooms] seeds received: beanstalk=5 pumpkin=3 vine=3'), 'printed')
end)

test('carry-over: CarryOverGameData copies seeds, tops up per type, drops coins/crops', function()
    loadGame()
    local d = NewGameData({seeds = {pumpkin = 4}, coins = 9, crops = {vine = 2}, hasSold = true})
    local c = CarryOverGameData(d)
    eq(FormatSeeds(c.seeds), 'beanstalk=1 pumpkin=4 vine=0')
    eq(c.coins, 0); eq(c.crops.vine, 0); eq(c.hasSold, true)
    c.seeds.pumpkin = 0
    eq(d.seeds.pumpkin, 4, 'seeds not aliased')
    local custom = CarryOverGameData(d, {vine = 2, pumpkin = 1})
    eq(FormatSeeds(custom.seeds), 'beanstalk=0 pumpkin=4 vine=2')
end)

test('idle: fallback break fires after the configured delay following a sale', function()
    local farm = farmAtVillager({crops = {beanstalk = 1}})
    local changes = countChanges()
    press('e'); eq(farm.gameData.hasSold, true)
    run(FARM_IDLE_BREAK_TIME - 0.5)
    eq(farm.breaking, false, 'not before the delay')
    run(1)
    eq(farm.breaking, true, 'idle fallback fired'); eq(farm.breakReason, 'idle')
    run(BREAK_TIME + 0.1)
    eq(countOf(changes, 'backrooms'), 1)
    eq(gStateMachine.current.usesPush, false, 'idle break also ends in the backrooms')
    eq(gStateMachine.current.gameData.seeds.beanstalk, STARTING_SEEDS.beanstalk)
end)

test('idle: a new sale restarts the idle delay', function()
    local farm = farmAtVillager({crops = {beanstalk = 2}})
    press('e')
    run(FARM_IDLE_BREAK_TIME - 5)
    press('e')                                -- second sale resets the timer
    run(FARM_IDLE_BREAK_TIME - 1)
    eq(farm.breaking, false, 'delay measured from the latest sale')
    run(1.5)
    eq(farm.breaking, true); eq(farm.breakReason, 'idle')
end)

test('break: sequence renders and completes with every asset as a placeholder', function()
    local farm = farmAtVillager({hasSold = true}, {'.', '--placeholder-assets'})
    assert(gSounds['glitch'].isPlaceholder, 'glitch sound is a stub')
    press('e')
    for _ = 1, 6 do run(BREAK_TIME / 6); love.draw() end
    run(0.1); love.draw()
    eq(gStateMachine.current.usesPush, false, 'reached backrooms')
end)

-- 4. backrooms world -----------------------------------------------------------
local function near(a, b, tol, msg)
    if math.abs(a - b) > (tol or 1e-6) then
        error((msg or 'expected near') .. ': got ' .. tostring(a) .. ', want ' .. tostring(b) .. ' +- ' .. tostring(tol or 1e-6), 2)
    end
end

-- Enters the backrooms with `seeds` carried over (default: a new game's).
local function toBackrooms(seeds, args)
    loadGame(args)
    gStateMachine:change('backrooms', CarryOverGameData(NewGameData(seeds and {seeds = seeds} or nil)))
    local back = gStateMachine.current
    assert(back.room and back.player, 'in backrooms state')
    return back
end

-- A closed 6 x 6 x 3 m test room (interior x, y in [-3, 3], floor top z = 0)
-- plus `extra` boxes; its exit is far below the floor, out of the way.
local function testRoom(extra)
    return Room({
        id = 'test', spawn = {0, 0, 0, 0},
        boxes = Room.joinBoxes(Room.shellBoxes(6, 6, 3), extra or {}),
        exit = {pos = {0, 0, -50}, size = {1, 1, 1}},
        allotment = {},
    })
end

-- Steps a bare controller for `seconds` at 60 fps.
local function simulate(player, room, seconds, input, direction)
    for _ = 1, math.floor(seconds * 60 + 0.5) do
        player:update(1 / 60, input or {}, direction or 0, room.colliders)
    end
end

local R = BACKROOMS_PLAYER_RADIUS

-- The section 4 fixture rooms (exits reachable on foot), kept for the
-- progression tests now that BACKROOMS_ROOMS holds the real puzzle rooms.
local function fixtureRooms()
    local H = 3
    return {
        {
            id = 'fixture-box', name = 'fixture: plain box room',
            spawn = {-3.5, 0, 0, 0},
            boxes = Room.shellBoxes(10, 10, H),
            exit = {pos = {4.6, 0, 1.1}, size = {0.6, 1.4, 2.2}},
            plots = {{id = 'a', pos = {0, -2, 0}}, {id = 'b', pos = {0, 2, 0}}},
            allotment = CopySeeds(FIRST_ROOM_MIN_SEEDS),
        },
        {
            id = 'fixture-ledge', name = 'fixture: ledge and pillar',
            spawn = {-4, 0, 1, 0},
            boxes = Room.joinBoxes(Room.shellBoxes(12, 8, H), {
                {kind = 'solid', pos = {-4.5, 0, 0.5}, size = {3, 8, 1}},
                {kind = 'solid', pos = {1, 0, H / 2}, size = {1, 1, H}},
            }),
            exit = {pos = {5.6, 0, 1.1}, size = {0.6, 1.4, 2.2}},
            plots = {{id = 'a', pos = {2.5, 2, 0}}},
            allotment = {beanstalk = 1, pumpkin = 1},
        },
    }
end

-- 4.1 first-person look and move ----------------------------------------------
test('backrooms: entering captures the mouse; Esc frees it, a click recaptures, leaving releases', function()
    local back = toBackrooms()
    eq(mock.relativeMode, true, 'relative mouse mode on entry')
    eq(back.mouseCaptured, true)
    press('escape')
    eq(back.mouseCaptured, false); eq(mock.relativeMode, false, 'freed by Esc')
    local dir = g3d.camera.getDirectionPitch()
    love.mousemoved(0, 0, 120, 40)
    eq(g3d.camera.getDirectionPitch(), dir, 'no look while the mouse is free')
    eq(mock.relativeMode, false, 'firstPersonLook not called (it would recapture)')
    mock.click(1); step()
    eq(back.mouseCaptured, true); eq(mock.relativeMode, true, 'click recaptures')
    back:loadRoom(#BACKROOMS_ROOMS); back:advance()   -- to the ending
    eq(mock.relativeMode, false, 'released on leaving the backrooms')
end)

test('backrooms: mouse movement turns the g3d camera (yaw and clamped pitch)', function()
    local back = toBackrooms()
    local dir0, pitch0 = g3d.camera.getDirectionPitch()
    near(dir0, BACKROOMS_ROOMS[1].spawn[4], 1e-9, 'spawn yaw'); near(pitch0, 0, 1e-9)
    love.mousemoved(400, 400, 30, 0)
    local dir1, pitch1 = g3d.camera.getDirectionPitch()
    near(dir1, dir0 - 30 / 300, 1e-9, 'mouse right turns right'); near(pitch1, 0, 1e-9)
    love.mousemoved(400, 400, 0, -60)
    local _, pitch2 = g3d.camera.getDirectionPitch()
    near(pitch2, 60 / 300, 1e-9, 'mouse up looks up')
    love.mousemoved(400, 400, 0, -100000)
    local _, pitch3 = g3d.camera.getDirectionPitch()
    near(pitch3, math.pi / 2, 1e-9, 'pitch clamped')
    -- the camera target follows the look direction
    local lx, ly, lz = g3d.camera.getLookVector()
    assert(lz > 0.99, 'looking straight up, lz=' .. lz)
    eq(back.mouseCaptured, true)
end)

test('backrooms: WASD/arrows walk relative to the look direction and the camera follows the eyes', function()
    local back = toBackrooms()
    local p = back.player
    run(0.5)                                         -- settle on the floor
    local x0, y0 = p.x, p.y
    mock.hold('w'); run(0.5); mock.release('w')
    near(p.x - x0, BACKROOMS_WALK_SPEED * 0.5, 0.15, 'forward along +x (spawn yaw 0)')
    near(p.y, y0, 1e-6, 'no sideways drift')
    -- camera eye follows the controller
    near(g3d.camera.position[1], p.x, 1e-9); near(g3d.camera.position[2], p.y, 1e-9)
    near(g3d.camera.position[3], p.z + BACKROOMS_EYE_HEIGHT, 1e-9)
    -- strafe right (facing +x, z up, right is -y)
    local y1 = p.y
    mock.hold('d'); run(0.25); mock.release('d')
    assert(p.y < y1 - 0.5, 'd strafes right (-y)')
    -- turn 90 degrees left with the mouse, then the up arrow walks +y
    love.mousemoved(0, 0, -(math.pi / 2) * 300, 0)
    local x2, y2 = p.x, p.y
    mock.hold('up'); run(0.25); mock.release('up')
    assert(p.y > y2 + 0.5, 'forward is now +y'); near(p.x, x2, 1e-3, 'no x drift')
    -- back + left together are normalised (not faster on diagonals)
    local x3, y3 = p.x, p.y
    mock.hold('s'); mock.hold('a'); run(0.25); mock.release('s'); mock.release('a')
    local moved = math.sqrt((p.x - x3) ^ 2 + (p.y - y3) ^ 2)
    near(moved, BACKROOMS_WALK_SPEED * 0.25, 0.1, 'diagonal speed')
end)

test('backrooms: renders at native resolution (camera aspect, HUD crosshair at screen centre)', function()
    local back = toBackrooms()
    local resized = mock.callsNamed('camera.resize')
    local last = resized[#resized]
    eq(last.args[1], 800); eq(last.args[2], 800)
    mock.reset(); love.draw()
    eq(mock.count('push.apply'), 0)
    local centred = false
    for _, c in ipairs(mock.callsNamed('line')) do
        if c.args[1] == 394 and c.args[2] == 400 and c.args[3] == 406 then centred = true end
    end
    assert(centred, 'crosshair drawn at the native window centre')
    assert(find(mock.printed, '[backrooms] entered room 1/'), 'room entry logged')
    eq(back.roomIndex, 1)
end)

-- 4.2 capsule controller and collision ------------------------------------------
test('collision: the player rests on the floor under gravity without jitter', function()
    local room = testRoom()
    local p = PlayerController(0, 0, 0)
    simulate(p, room, 2)
    near(p.z, 0, 0.01, 'on the floor'); eq(p.grounded, true); eq(p.vz, 0)
    local z = p.z
    simulate(p, room, 1)
    near(p.z, z, 0.005, 'stable while standing')
end)

test('collision: the player falls from height and lands on the floor', function()
    local room = testRoom()
    -- start at z = 1: the 1.7 m capsule must fit under the 3 m ceiling
    local p = PlayerController(0, 0, 1)
    simulate(p, room, 0.2)
    assert(p.z < 1 and p.z > 0.5, 'falling, z=' .. p.z); eq(p.grounded, false)
    simulate(p, room, 2)
    near(p.z, 0, 0.01, 'landed'); eq(p.grounded, true)
end)

test('collision: a wall stops the player at the wall', function()
    local room = testRoom()
    local p = PlayerController(0, 0, 0)
    simulate(p, room, 3, {forward = 1}, 0)            -- walk +x into the x = 3 wall
    assert(p.x <= 3 - R + 0.01, 'not through the wall, x=' .. p.x)
    assert(p.x >= 3 - R - 0.05, 'stopped at the wall, x=' .. p.x)
    near(p.y, 0, 1e-3, 'head-on: no sideways push')
    near(p.z, 0, 0.01, 'still on the floor')
end)

test('collision: walking diagonally into a wall slides along it', function()
    local room = testRoom()
    local p = PlayerController(0, -2, 0)
    simulate(p, room, 1.5, {forward = 1}, math.rad(30))
    assert(p.x <= 3 - R + 0.01, 'held at the wall, x=' .. p.x)
    -- the y part of the motion survives the contact: -2 + 4 sin30 * 1.5 = 1
    assert(p.y > 0.8, 'slid along the wall, y=' .. p.y)
end)

test('collision: no sticking in a corner and no clipping out of it', function()
    local room = testRoom()
    local p = PlayerController(0, 0, 0)
    simulate(p, room, 2, {forward = 1}, math.pi / 4)  -- into the (+x, +y) corner
    assert(p.x <= 3 - R + 0.01 and p.y <= 3 - R + 0.01, 'inside the corner')
    assert(p.x > 3 - R - 0.05 and p.y > 3 - R - 0.05, 'reached the corner')
    local x, y = p.x, p.y
    simulate(p, room, 0.5, {forward = 1}, math.pi + math.pi / 4)   -- walk straight back out
    local moved = math.sqrt((p.x - x) ^ 2 + (p.y - y) ^ 2)
    near(moved, BACKROOMS_WALK_SPEED * 0.5, 0.1, 'free to leave the corner')
    -- slide out along one wall too
    simulate(p, room, 1, {forward = 1}, math.pi / 4)
    simulate(p, room, 0.5, {forward = 1}, -math.pi / 2)            -- along the x wall, -y
    assert(p.y < 3 - R - 1, 'slides out along the wall, y=' .. p.y)
end)

test('collision: walking off a raised surface falls to the floor below', function()
    -- ledge (stand-in for a grown crop top): x in [-3, 0], top at z = 1
    local room = testRoom({{kind = 'solid', pos = {-1.5, 0, 0.5}, size = {3, 6, 1}}})
    local p = PlayerController(-1.5, 0, 1)
    simulate(p, room, 0.5)
    near(p.z, 1, 0.01, 'standing on top of the ledge'); eq(p.grounded, true)
    simulate(p, room, 1, {forward = 1}, 0)
    assert(p.x > 0.5, 'walked off the edge, x=' .. p.x)
    simulate(p, room, 1)
    near(p.z, 0, 0.01, 'fell to the floor'); eq(p.grounded, true)
    -- and the ledge side is a wall from below
    simulate(p, room, 1, {forward = 1}, math.pi)
    assert(p.x >= R - 0.01, 'blocked by the ledge side, x=' .. p.x)
    near(p.z, 0, 0.05, 'did not climb the 1 m ledge')
end)

test('collision: fast motion does not tunnel through thin walls or floors', function()
    local room = testRoom({{kind = 'wall', pos = {1, 0, 1.5}, size = {0.05, 6, 3}}})
    local p = PlayerController(0, 0, 0, {speed = 40})
    for _ = 1, 30 do p:update(1 / 20, {forward = 1}, 0, room.colliders) end   -- 2 m per frame
    assert(p.x < 1, 'stopped by a 5 cm wall, x=' .. p.x)
    local pit = Room({id = 'pit', spawn = {0, 0, 0}, allotment = {},
        boxes = {{kind = 'floor', pos = {0, 0, -0.1}, size = {6, 6, 0.2}}},
        exit = {pos = {0, 0, -50}, size = {1, 1, 1}}})
    local faller = PlayerController(-2, 0, 30)                                 -- no ceiling above
    for _ = 1, 120 do faller:update(1 / 20, {}, 0, pit.colliders) end          -- reaches terminal speed
    near(faller.vz, 0, 1e-9, 'stopped on landing')
    near(faller.z, 0, 0.01, 'landed after a long fall'); eq(faller.grounded, true)
    -- a huge dt is clamped instead of teleporting
    local q = PlayerController(-2, 0, 0)
    q:update(10, {forward = 1}, 0, room.colliders)
    assert(q.x - (-2) <= BACKROOMS_WALK_SPEED * BACKROOMS_MAX_DT + 1e-6, 'dt clamped')
end)

test('collision: the ceiling stops upward motion', function()
    local room = testRoom()
    local p = PlayerController(0, 0, 0)
    p.vz = 12
    simulate(p, room, 0.4)
    assert(p.z + BACKROOMS_PLAYER_HEIGHT <= 3 + 0.01, 'head below the ceiling')
    assert(p.vz <= 0, 'vertical speed cancelled or falling')
end)

test('collision: colliders far from the player are not tested (broadphase)', function()
    local room = testRoom()
    local real = g3d.collisions.capsuleIntersection
    local tested = 0
    g3d.collisions.capsuleIntersection = function(...) tested = tested + 1; return real(...) end
    local p = PlayerController(0, 0, 1)              -- mid-air, centre of the room
    p:update(1 / 60, {}, 0, room.colliders)
    g3d.collisions.capsuleIntersection = real
    eq(tested, 0, 'no box near the player in the air')
end)

test('backrooms: falling out of the world respawns at the room spawn', function()
    local back = toBackrooms()
    back.player:setPosition(0, 0, BACKROOMS_KILL_Z - 1)
    step()
    local s = back.room.spawn
    near(back.player.x, s[1], 1e-6); near(back.player.y, s[2], 1e-6)
    eq(back.roomIndex, 1)
end)

-- 4.3 data-driven Room builder ----------------------------------------------------
local SAMPLE_ROOM = {
    id = 'sample', name = 'Sample',
    spawn = {1, 2, 0, math.pi},
    boxes = {
        {kind = 'floor', pos = {0, 0, -0.1}, size = {8, 8, 0.2}},
        {kind = 'wall', pos = {4, 0, 1.5}, size = {0.2, 8, 3}, color = {1, 0, 0, 1}},
        {pos = {0, 0, 1}, size = {1, 1, 2}, collide = false},
    },
    plots = {{id = 'left', pos = {-2, 0, 0}}, {pos = {2, 0, 0}}},
    exit = {pos = {3, 3, 1}, size = {1, 2, 2}},
    allotment = {pumpkin = 2},
    billboards = {{texture = 'crop-pumpkin-5', pos = {0, 3, 0}, height = 1}},
    demoCrops = {{plot = 'left', seed = 'beanstalk', progress = 0.5}},
}

test('room: a sample room loads from a data table', function()
    loadGame()
    local room = Room(SAMPLE_ROOM)
    eq(room.id, 'sample'); eq(room.name, 'Sample')
    eq(room.spawn[1], 1); eq(room.spawn[4], math.pi)
    eq(#room.models, 3, 'every box is drawn')
    eq(#room.colliders, 2, 'collide = false box is not solid')
    eq(room.colliders[1].kind, 'floor')
    local c = room.colliders[2]
    near(c.min[1], 3.9); near(c.max[1], 4.1); near(c.min[3], 0); near(c.max[3], 3)
    eq(c.transform.translation[1], 4, 'collider uses the model translation')
    eq(#c.verts, 36)
    eq(c.verts[1][9], 1 * 0.85, 'custom colour, shaded per face')
    eq(#room.plots, 2); eq(room.plots[1].id, 'left'); eq(room.plots[2].id, 'plot2')
    eq(room.plots[1].pos[1], -2)
    near(room.exit.min[1], 2.5); near(room.exit.max[2], 4); near(room.exit.max[3], 2)
    eq(FormatSeeds(room.allotment), 'beanstalk=0 pumpkin=2 vine=0')
    room.allotment.pumpkin = 0
    eq(SAMPLE_ROOM.allotment.pumpkin, 2, 'allotment copied, data not aliased')
    eq(#room.billboards, 1)
    eq(room.demoCrops, SAMPLE_ROOM.demoCrops, 'demo crop data kept for section 5')
    assert(room:overlapsExit({2.8, 2.8, 0}, {3.2, 3.2, 1.7}), 'standing in the exit')
    assert(not room:overlapsExit({0, 0, 0}, {0.6, 0.6, 1.7}), 'away from the exit')
end)

test('room: textures tile with box size and faces are shaded', function()
    loadGame()
    local v = NewRoomBoxVerts(4, 2, 6, {1, 1, 1, 1})
    local maxU = 0
    for _, vert in ipairs(v) do
        if vert[8] > 0.5 then eq(vert[9], 1, 'top face full bright') end
        if vert[8] < -0.5 then eq(vert[9], 0.7, 'bottom face darker') end
        if math.abs(vert[6]) > 0.5 then eq(vert[9], 0.85, 'x faces') end
        maxU = math.max(maxU, math.abs(vert[4]))
    end
    near(maxU, 2 / ROOM_TEXTURE_TILE, 1e-9, 'u spans the face size in tiles')
end)

test('room: invalid data is rejected with a message naming the room', function()
    loadGame()
    local function broken(change)
        local d = {}
        for k, v in pairs(SAMPLE_ROOM) do d[k] = v end
        d.id = 'bad'
        change(d)
        local ok, err = pcall(Room, d)
        eq(ok, false, 'should fail')
        assert(tostring(err):find('room bad', 1, true), 'message names the room: ' .. tostring(err))
        return tostring(err)
    end
    broken(function(d) d.spawn = nil end)
    broken(function(d) d.exit = nil end)
    broken(function(d) d.boxes = {} end)
    broken(function(d) d.boxes = {{pos = {0, 0, 0}, size = {1, 0, 1}}} end)
    broken(function(d) d.boxes = {{pos = {0, 0, 0}, size = {1, 1, 1}, kind = 'lava'}} end)
    broken(function(d) d.allotment = nil end)
    assert(broken(function(d) d.allotment = {carrot = 1} end):find('carrot', 1, true))
    broken(function(d) d.allotment = {vine = -1} end)
    broken(function(d) d.allotment = {vine = 1.5} end)
    broken(function(d) d.plots = {{id = 'x'}} end)
    broken(function(d) d.billboards = {{pos = {0, 0, 0}}} end)
    eq(Room.validate(SAMPLE_ROOM), true)
end)

test('room: every BACKROOMS_ROOMS entry builds, and the player spawns standing and free', function()
    loadGame()
    assert(#BACKROOMS_ROOMS >= 2, 'at least two rooms')
    local ids = {}
    for i, data in ipairs(BACKROOMS_ROOMS) do
        assert(Room.validate(data))
        assert(not ids[data.id], 'unique id ' .. data.id); ids[data.id] = true
        local room = Room(data)
        local s = room.spawn
        local p = PlayerController(s[1], s[2], s[3])
        simulate(p, room, 1)
        eq(p.grounded, true, 'room ' .. i .. ' spawn is supported')
        near(p.x, s[1], 0.02, 'room ' .. i .. ' spawn not inside a wall'); near(p.y, s[2], 0.02)
        near(p.z, s[3], 0.02, 'room ' .. i .. ' spawn height')
        local pmin, pmax = p:bounds()
        assert(not room:overlapsExit(pmin, pmax), 'room ' .. i .. ' does not spawn in its exit')
    end
end)

-- 4.4 billboards -----------------------------------------------------------------
test('billboard: quad verts stand upright and face +x before rotation', function()
    loadGame()
    local v = NewBillboardVerts(2, 3)
    eq(#v, 6)
    for _, vert in ipairs(v) do
        eq(vert[1], 0); assert(math.abs(vert[2]) == 1); assert(vert[3] == 0 or vert[3] == 3)
        eq(vert[6], 1); eq(vert[7], 0); eq(#vert, 12)
        -- image top at the top of the quad, left at -y (the viewer's left from +x)
        eq(vert[5], vert[3] == 0 and 1 or 0); eq(vert[4], vert[2] < 0 and 0 or 1)
    end
end)

test('billboard: keeps facing the camera as the player moves around it', function()
    loadGame()
    local b = Billboard({texture = 'crop-pumpkin-5', pos = {1, 2, 0}, height = 1})
    eq(b.width, b.height, 'square texture keeps its aspect ratio')
    for i = 0, 7 do
        local a = i * math.pi / 4
        local cx, cy = 1 + 3 * math.cos(a), 2 + 3 * math.sin(a)
        b:faceCamera(cx, cy)
        local fx, fy = b:facing()
        local dx, dy = (cx - 1) / 3, (cy - 2) / 3
        near(fx * dx + fy * dy, 1, 1e-9, 'facing the camera at angle ' .. i)
        eq(b.model.rotation[3], b.yaw, 'model rotated about z only')
        eq(b.model.rotation[1], 0); eq(b.model.rotation[2], 0)
    end
    local yaw = b.yaw
    b:faceCamera(1, 2)                                    -- camera straight above: keep yaw
    eq(b.yaw, yaw)
    near(Billboard.yawToward(0, 0, 0, 5), math.pi / 2, 1e-12)
    eq(Billboard.yawToward(0, 0, 0, 0), nil)
    local wide = Billboard({texture = {getDimensions = function() return 64, 32 end}, pos = {0, 0, 0}, height = 1.5})
    eq(wide.width, 3, 'width from the image aspect ratio')
end)

test('billboard: backrooms sprites turn to the player and draw after the room, far to near', function()
    local back = toBackrooms()
    local room = back.room
    assert(#room.billboards >= 2, 'fixture room has billboards')
    for _, pos in ipairs({{-3, -3}, {3, 3}, {0, -1}}) do
        back.player:setPosition(pos[1], pos[2], 0)
        mock.reset(); love.draw()
        local order, opaqueLast, firstBoard = {}, 0, nil
        local boardOf = {}
        for _, b in ipairs(room.billboards) do boardOf[b.model] = b end
        for i, c in ipairs(mock.callsNamed('model.draw')) do
            local b = boardOf[c.args[1]]
            if b then
                order[#order + 1] = b
                firstBoard = firstBoard or i
            else
                opaqueLast = i
            end
        end
        eq(#order, #room.billboards, 'every billboard drawn')
        assert(firstBoard > opaqueLast, 'billboards after opaque geometry')
        for i, b in ipairs(order) do
            local fx, fy = b:facing()
            local dx, dy = pos[1] - b.x, pos[2] - b.y
            local len = math.sqrt(dx * dx + dy * dy)
            near((fx * dx + fy * dy) / len, 1, 1e-9, 'billboard faces the player')
            if i > 1 then
                local prev = order[i - 1]
                assert((prev.x - pos[1]) ^ 2 + (prev.y - pos[2]) ^ 2 >= len * len - 1e-9, 'far to near')
            end
        end
    end
end)

-- 4.5 exits, progression, ending -----------------------------------------------------
test('progression: walking into the exit loads the next room with its own allotment', function()
    -- section 4 fixture rooms (their exits are reachable on foot)
    loadGame()
    local rooms = fixtureRooms()
    local back = BackroomsState()
    gStateMachine.current = back
    back:enter(CarryOverGameData(NewGameData({seeds = {beanstalk = 4, pumpkin = 0, vine = 2}})), rooms)
    eq(FormatSeeds(back.gameData.seeds), 'beanstalk=4 pumpkin=0 vine=2', 'room 1 keeps the farm seeds')
    mock.hold('w')                                   -- room 1 spawn faces its exit
    local frames = 0
    while back.roomIndex == 1 and frames < 6 * 60 do step(); frames = frames + 1 end
    mock.release('w')
    eq(back.roomIndex, 2, 'reached the room 1 exit on foot')
    eq(back.room.id, rooms[2].id)
    eq(FormatSeeds(back.gameData.seeds), FormatSeeds(CopySeeds(rooms[2].allotment)),
        'room 2 seeds are exactly its allotment')
    local s = back.room.spawn
    near(back.player.x, s[1], 1e-6, 'placed at the new spawn'); near(back.player.y, s[2], 1e-6)
    eq(gStateMachine.current, back, 'same state, new room')
end)

test('progression: an exit fires once and the last exit shows the ending', function()
    local back = toBackrooms()
    local changes = countChanges()
    for i = 1, #BACKROOMS_ROOMS - 1 do
        local e = back.room.exit.pos
        back.player:setPosition(e[1], e[2], e[3] - 1)
        step()
        eq(back.roomIndex, i + 1, 'advanced exactly one room')
    end
    eq(#changes, 0, 'no state change before the last exit')
    local e = back.room.exit.pos
    back.player:setPosition(e[1], e[2], e[3] - 1)
    step()
    eq(#changes, 1); eq(changes[1], 'ending')
    assert(isState(gStateMachine.current, EndingState), 'ending shown')
    eq(gStateMachine.current.gameData, back.gameData)
    back:advance()                                   -- a stray second trigger does nothing
    eq(#changes, 1)
    mock.reset(); love.draw()
    eq(mock.count('push.apply'), 2, 'ending renders through push')
    assert(mock.count('printf') >= 2, 'ending text drawn')
end)

test('progression: a single-room list goes straight to the ending', function()
    loadGame()
    local only = {}
    for k, v in pairs(SAMPLE_ROOM) do only[k] = v end
    local back = BackroomsState()
    gStateMachine.current = back
    back:enter(CarryOverGameData(NewGameData()), {only})
    eq(#back.rooms, 1)
    back.player:setPosition(3, 3, 0)
    step()
    assert(isState(gStateMachine.current, EndingState))
end)

test('ending: Enter returns to the start screen, but not in the first half second', function()
    loadGame()
    gStateMachine:change('ending', NewGameData())
    assert(find(mock.printed, '[ending]'), 'ending logged')
    press('return')
    assert(isState(gStateMachine.current, EndingState), 'held Enter from the exit is ignored')
    run(0.6)
    press('return')
    assert(isState(gStateMachine.current, StartState), 'back to start')
end)

-- seed carry-over vs per-room allotment policy ------------------------------------------
test('seeds: Room 1 keeps the farm seeds topped up to its allotment; later rooms are fixed', function()
    loadGame()
    local room1 = {allotment = {beanstalk = 1, vine = 1}}
    eq(FormatSeeds(RoomStartingSeeds(room1, 1, {pumpkin = 5})), 'beanstalk=1 pumpkin=5 vine=1')
    eq(FormatSeeds(RoomStartingSeeds(room1, 1, {beanstalk = 3, vine = 0})), 'beanstalk=3 pumpkin=0 vine=1')
    local room2 = {allotment = {pumpkin = 2}}
    eq(FormatSeeds(RoomStartingSeeds(room2, 2, {beanstalk = 9, pumpkin = 9, vine = 9})), 'beanstalk=0 pumpkin=2 vine=0')
    eq(FormatSeeds(RoomStartingSeeds(room2, 3, {})), 'beanstalk=0 pumpkin=2 vine=0')
    local carried = {beanstalk = 2}
    local out = RoomStartingSeeds(room1, 1, carried)
    out.beanstalk = 0
    eq(carried.beanstalk, 2, 'input not aliased')
    local fixed = RoomStartingSeeds(room2, 2, {})
    fixed.pumpkin = 0
    eq(room2.allotment.pumpkin, 2, 'room data not aliased')
end)

test('seeds: FIRST_ROOM_MIN_SEEDS matches Room 1 allotment, so farm and backrooms agree', function()
    loadGame()
    eq(FormatSeeds(FIRST_ROOM_MIN_SEEDS), FormatSeeds(BACKROOMS_ROOMS[1].allotment))
    -- a zero-seed farm arrival via the debug skip is topped up too
    mock.press('return'); step()
    local farm = gStateMachine.current
    for _, t in ipairs(SEED_TYPES) do farm.gameData.seeds[t] = 0 end
    mock.press('f1'); step()
    eq(FormatSeeds(gStateMachine.current.gameData.seeds), FormatSeeds(CopySeeds(BACKROOMS_ROOMS[1].allotment)))
end)

test('seeds: resetting Room 1 restores its recorded start (topped-up farm seeds)', function()
    local back = toBackrooms({beanstalk = 0, pumpkin = 5, vine = 0})
    local start = FormatSeeds(back.gameData.seeds)
    eq(start, FormatSeeds(RoomStartingSeeds(BACKROOMS_ROOMS[1], 1, {pumpkin = 5})))
    assert(back.gameData.seeds.pumpkin == 5, 'farm pumpkins kept')
    back.gameData.seeds.pumpkin = 0; back.gameData.seeds.beanstalk = 0   -- "waste" seeds
    back.player:setPosition(2, 2, 0)
    local oldRoom = back.room
    back:resetRoom()
    eq(FormatSeeds(back.gameData.seeds), start, 'recorded start restored, not the bare allotment')
    assert(back.room ~= oldRoom, 'room rebuilt from data')
    near(back.player.x, back.room.spawn[1], 1e-6, 'player back at spawn')
    back.gameData.seeds.vine = 3
    back:resetRoom()
    eq(FormatSeeds(back.gameData.seeds), start, 'reset is repeatable')
end)

test('seeds: resetting a later room restores its fixed allotment', function()
    local back = toBackrooms({beanstalk = 7, pumpkin = 7, vine = 7})
    back:advance()
    eq(back.roomIndex, 2)
    local allot = FormatSeeds(CopySeeds(BACKROOMS_ROOMS[2].allotment))
    eq(FormatSeeds(back.gameData.seeds), allot, 'farm surplus does not carry into room 2')
    for _, t in ipairs(SEED_TYPES) do back.gameData.seeds[t] = 0 end
    back:resetRoom()
    eq(FormatSeeds(back.gameData.seeds), allot)
    eq(back.roomIndex, 2, 'reset stays in the same room')
end)

test('backrooms: every room renders with all assets as placeholders', function()
    local back = toBackrooms(nil, {'.', '--placeholder-assets'})
    for i = 1, #BACKROOMS_ROOMS do
        eq(back.roomIndex, i)
        mock.reset(); love.draw()
        assert(mock.count('model.draw') > 0, 'room ' .. i .. ' drew')
        if i < #BACKROOMS_ROOMS then back:advance() end
    end
end)

-- 5. seed puzzles ------------------------------------------------------------------
local Reach = dofile('tests/reach.lua')

-- Enters the backrooms and skips to room `index` with `seeds` carried over.
local function toRoom(index, seeds)
    local back = toBackrooms(seeds)
    while back.roomIndex < index do back:advance() end
    eq(back.roomIndex, index)
    return back
end

-- Holds `key` until cond() is true or `seconds` pass. Returns cond().
local function holdUntil(key, cond, seconds)
    mock.hold(key)
    local frames = 0
    while not cond() and frames < seconds * 60 do step(); frames = frames + 1 end
    mock.release(key)
    return cond()
end

-- Steps a bare controller with the room's current solid colliders and climb
-- volumes (crops included) for `seconds` at 60 fps.
local function simulateCrops(player, room, seconds, input, direction)
    for _ = 1, math.floor(seconds * 60 + 0.5) do
        player:update(1 / 60, input or {}, direction or 0, room:solidColliders(), room:climbVolumes())
    end
end

-- A closed room w x d x h (interior centred on the origin, floor top z = 0)
-- plus `extra` boxes, with one plot at `plotPos` (dir `dir`).
local function plotRoom(w, d, h, extra, plotPos, dir)
    return Room({
        id = 'plot-test', spawn = {0, 0, 0, 0},
        boxes = Room.joinBoxes(Room.shellBoxes(w, d, h), extra or {}),
        exit = {pos = {0, 0, -50}, size = {1, 1, 1}},
        plots = {{id = 'p', pos = plotPos or {0, 0, 0}, dir = dir}},
        allotment = {},
    })
end

-- Grows the crop on plot `id` of `room` to full size and puts it in effect
-- (no player in the way).
local function growNow(room, id, seedType)
    local plot = room:plotById(id)
    local group = {}
    local ok, crop = room:plant(plot, seedType, {[seedType] = 1}, group)
    assert(ok, 'planted ' .. seedType .. ': ' .. tostring(crop))
    Timer.update(CROP_DEFS[seedType].growTime + 0.01, group)
    room:updateCrops({1000, 1000, 1000}, {1001, 1001, 1001})
    assert(crop.grown and crop.active, seedType .. ' grown and active')
    return crop
end

local function printedTexts()
    local out = {}
    for _, c in ipairs(mock.calls) do
        if (c.name == 'print' or c.name == 'printf') and type(c.args[1]) == 'string' then out[#out + 1] = c.args[1] end
    end
    return out
end

-- Everything a reset must restore, as one comparable string (the selected
-- seed is a UI preference and is deliberately left out).
local function roomSignature(back)
    local p = back.player
    local dir = g3d.camera.getDirectionPitch()
    local parts = {back.room.id, FormatSeeds(back.gameData.seeds),
        string.format('%.4f,%.4f,%.4f,%.4f,%s,%.3f', p.x, p.y, p.z, p.vz, tostring(p.climbing), dir),
        'crops=' .. #back.room.crops, 'timers=' .. #back.timers}
    for _, plot in ipairs(back.room.plots) do
        local c = plot.crop
        parts[#parts + 1] = plot.id .. ':' .. (c and string.format('%s,%.4f,%s,%s,%s', c.type, c.progress,
            tostring(c.grown), tostring(c.active), tostring(c.timer ~= nil)) or 'empty')
    end
    return table.concat(parts, ' | ')
end

-- 5.1 seed definitions and growth ---------------------------------------------------
test('seeds: beanstalk, pumpkin and vine grow into distinct shapes', function()
    loadGame()
    local plot = {pos = {1, 2, 0.5}, dir = '+x'}
    local function dims(t)
        local min, max = Crop.fullBounds(t, plot)
        return max[1] - min[1], max[2] - min[2], max[3] - min[3], min, max
    end
    local bx, by, bz, bmin = dims('beanstalk')
    local px, py, pz, pmin = dims('pumpkin')
    local vx, vy, vz, vmin, vmax = dims('vine')
    assert(bz >= 2.6 and bz > 3 * bx and bz > 3 * by, 'beanstalk tall and thin')
    near(bmin[3], 0.5, 1e-12, 'beanstalk grows up from the plot')
    assert(px >= 2.5 and py >= 2.5 and pz <= 1.0 and px > 2 * pz, 'pumpkin wide and low')
    near(pmin[3], 0.5, 1e-12, 'pumpkin sits on the plot')
    assert(vx >= 5 and vx > 3 * vy and vz <= 0.3 + 1e-9, 'vine long, narrow, flat along +x')
    near(vmax[3], 0.5, 1e-12, 'vine top level with the plot surface')
    near(vmin[1], 1 - CROP_DEFS.vine.back, 1e-12, 'vine starts just behind the plot')
    -- tallest / widest / longest each belong to one type
    assert(bz > pz and bz > vz, 'only the beanstalk is tall')
    assert(px * py > bx * by and py > vy, 'only the pumpkin is wide in both directions')
    assert(vx > px and vx > bx, 'only the vine is long')
    -- a vine follows its plot direction
    for dir, d in pairs(CROP_DIRECTIONS) do
        local min, max = Crop.fullBounds('vine', {pos = {0, 0, 0}, dir = dir})
        local farX = d[1] ~= 0 and (d[1] > 0 and max[1] or -min[1]) or 0
        local farY = d[2] ~= 0 and (d[2] > 0 and max[2] or -min[2]) or 0
        near(farX + farY, CROP_DEFS.vine.length - CROP_DEFS.vine.back, 1e-12, 'vine grows along ' .. dir)
    end
    for _, t in ipairs(SEED_TYPES) do
        assert(CROP_DEFS[t], t .. ' has a growth definition')
        assert(CROP_DEFS[t].growTime >= 1 and CROP_DEFS[t].growTime <= 3, t .. ' grows in a few seconds')
    end
end)

test('growth: a planted crop tweens its scale along its own axes and is unusable until grown', function()
    loadGame()
    local expectAxes = {beanstalk = {false, false, true}, pumpkin = {true, true, true}, vine = {false, true, false}}
    for _, t in ipairs(SEED_TYPES) do
        local room = plotRoom(8, 8, 6, nil, {0, 0, 0}, '+y')
        local group = {}
        local seeds = {[t] = 2}
        local ok, crop = room:plant(room:plotById('p'), t, seeds, group)
        assert(ok, t .. ' planted'); eq(seeds[t], 1, t .. ' consumed one seed')
        eq(crop.progress, 0, t .. ' starts ungrown')
        local half = CROP_DEFS[t].growTime / 2
        Timer.update(half, group)
        room:updateCrops({100, 100, 100}, {101, 101, 101})
        near(crop.progress, 0.5, 1e-9, t .. ' half way')
        local s = {crop:scale()}
        for axis = 1, 3 do
            if expectAxes[t][axis] then near(s[axis], CROP_MIN_SCALE + (1 - CROP_MIN_SCALE) * 0.5, 1e-9, t .. ' axis ' .. axis .. ' grows')
            else eq(s[axis], 1, t .. ' axis ' .. axis .. ' fixed') end
        end
        eq(crop.model.scale[1], s[1]); eq(crop.model.scale[3], s[3])
        eq(crop.grown, false); eq(crop.active, false)
        eq(#room:solidColliders(), #room.colliders, t .. ' not solid while growing')
        eq(#room:climbVolumes(), 0, t .. ' not climbable while growing')
        Timer.update(half + 0.001, group)
        room:updateCrops({100, 100, 100}, {101, 101, 101})
        eq(crop.progress, 1); eq(crop.grown, true); eq(crop.active, true)
        eq(#group, 0, t .. ' tween finished and removed')
        local sx, sy, sz = crop:scale()
        eq(sx, 1); eq(sy, 1); eq(sz, 1)
        if CROP_DEFS[t].solid then
            eq(#room:solidColliders(), #room.colliders + 1, t .. ' solid when grown')
            eq(#room:climbVolumes(), 0)
        else
            eq(#room:solidColliders(), #room.colliders, t .. ' is not solid')
            eq(#room:climbVolumes(), 1, t .. ' climbable when grown')
        end
    end
end)

test('growth: crop colliders are full size with no scale, so g3d normals stay correct', function()
    loadGame()
    local room = plotRoom(8, 8, 6, nil, {0, 0, 0})
    local group = {}
    local _, crop = room:plant(room:plotById('p'), 'pumpkin', {pumpkin = 1}, group)
    Timer.update(0.5, group)                      -- mid growth: draw model is non-uniformly scaled
    local sx, _, sz = crop:scale()
    assert(sx < 1 and sz < 1, 'draw model scaled while growing')
    local c = crop.collider
    eq(c.transform.scale, nil, 'collision transform has no scale')
    assert(c.transform ~= crop.model, 'the scaled draw model is never used for collision')
    local minX, maxX, maxZ = math.huge, -math.huge, -math.huge
    for _, v in ipairs(c.verts) do
        minX = math.min(minX, v[1] + c.transform.translation[1]); maxX = math.max(maxX, v[1] + c.transform.translation[1])
        maxZ = math.max(maxZ, v[3] + c.transform.translation[3])
    end
    near(maxX - minX, CROP_DEFS.pumpkin.size[1], 1e-9, 'collider verts at full grown width')
    near(maxZ, CROP_DEFS.pumpkin.size[3], 1e-9, 'collider top at full grown height')
    -- a capsule resting on the top gets a straight-up normal from g3d
    local len, _, _, _, nx, ny, nz = g3d.collisions.capsuleIntersection(c.verts, c.transform,
        0.4, 0.2, 1.0 + 1.7 - 0.05, 0.4, 0.2, 1.0 - 0.05, R)
    assert(len and len < R, 'touching the top')
    near(nz, 1, 1e-9, 'up normal'); near(nx, 0, 1e-9); near(ny, 0, 1e-9)
end)

test('growth: a grown pumpkin waits until the player is clear before it turns solid', function()
    loadGame()
    local room = plotRoom(10, 6, 3, nil, {0, 0, 0})
    local p = PlayerController(0, 0, 0)          -- standing on the plot
    simulateCrops(p, room, 0.3)
    local group = {}
    local _, crop = room:plant(room:plotById('p'), 'pumpkin', {pumpkin = 1}, group)
    -- a pumpkin growing around the player does not push them anywhere
    for _ = 1, 60 do
        Timer.update(1 / 60, group)
        local bmin, bmax = p:bounds(); room:updateCrops(bmin, bmax)
        p:update(1 / 60, {}, 0, room:solidColliders(), room:climbVolumes())
    end
    eq(crop.active, false, 'still growing')
    Timer.update(CROP_DEFS.pumpkin.growTime, group)
    local bmin, bmax = p:bounds(); room:updateCrops(bmin, bmax)
    eq(crop.grown, true); eq(crop.active, false, 'grown but the player is inside it')
    near(p.z, 0, 0.01, 'player not shoved by a crop that grew around them')
    -- walk out (-x), then it becomes solid and blocks the way back
    for _ = 1, 60 do
        local a, b = p:bounds(); room:updateCrops(a, b)
        p:update(1 / 60, {forward = 1}, math.pi, room:solidColliders(), room:climbVolumes())
    end
    eq(crop.active, true, 'solid once the player left')
    simulateCrops(p, room, 1.5, {forward = 1}, 0)
    assert(p.x <= -CROP_DEFS.pumpkin.size[1] / 2 - R + 0.02, 'blocked by the grown pumpkin, x=' .. p.x)
    near(p.z, 0, 0.02, 'cannot step up a 1 m pumpkin')
end)

-- 5.2 plot planting, selection and HUD --------------------------------------------
test('planting: the nearest plot within range is chosen; nothing elsewhere', function()
    loadGame()
    local room = Room({
        id = 'plots', spawn = {0, 0, 0}, allotment = {},
        boxes = Room.shellBoxes(10, 10, 6),
        exit = {pos = {0, 0, -50}, size = {1, 1, 1}},
        plots = {{id = 'a', pos = {0, -2, 0}}, {id = 'b', pos = {0, 2, 0}}, {id = 'high', pos = {4, 0, 2.6}}},
    })
    eq(room:nearestPlot(0, -1.5, 0).id, 'a')
    eq(room:nearestPlot(0.5, 1.1, 0).id, 'b')
    eq(room:nearestPlot(0, 0.1, 0).id, 'a', 'nearest of two in range')
    eq(room:nearestPlot(0, -2 + BACKROOMS_PLANT_RANGE - 0.01, 0).id, 'a', 'just inside the range')
    eq(room:nearestPlot(3, -2, 0), nil, 'out of horizontal range')
    eq(room:nearestPlot(4, 0, 0), nil, 'a plot 2.6 m above is out of reach')
    eq(room:nearestPlot(4, 0, 2.6).id, 'high', 'reachable from its own level')
    eq(room:nearestPlot(-4, -4, 0), nil)
    local seeds = {beanstalk = 1, pumpkin = 1, vine = 1}
    local ok, reason = room:plant(nil, 'pumpkin', seeds, {})
    eq(ok, false); eq(reason, 'no-plot'); eq(seeds.pumpkin, 1, 'nothing consumed without a plot')
    eq(#room.crops, 0)
end)

test('planting: E plants the selected seed on the plot in range and only that count drops', function()
    local back = toRoom(2)
    eq(FormatSeeds(back.gameData.seeds), 'beanstalk=0 pumpkin=2 vine=2')
    eq(back.selectedSeed, 'pumpkin', 'first held type selected')
    back.player:setPosition(-4.4, 0, 0); run(0.2)    -- on the rim of the pit
    eq(back:targetPlot().id, 'pit')
    mock.reset(); love.draw()
    local texts = table.concat(printedTexts(), '\n')
    assert(texts:find('[2 pumpkin x2]', 1, true), 'HUD shows the selected type and its count')
    assert(texts:find(' 3 vine x2 ', 1, true), 'HUD shows the other counts')
    assert(texts:find('E / click: plant pumpkin', 1, true), 'planting prompt near a plot')
    press('e')
    eq(FormatSeeds(back.gameData.seeds), 'beanstalk=0 pumpkin=1 vine=2', 'one pumpkin consumed')
    local crop = back.room:plotById('pit').crop
    assert(crop and crop.type == 'pumpkin' and not crop.grown, 'pumpkin growing on the pit plot')
    eq(#back.timers, 1, 'growth runs on the state timer group')
    mock.reset(); love.draw()
    assert(table.concat(printedTexts(), '\n'):find('[2 pumpkin x1]', 1, true), 'HUD count updated')
    assert(find(mock.printed, '[backrooms] planted pumpkin on plot pit'), 'planting logged')
    -- growth is driven once per frame (the state group is not also the default group)
    run(CROP_DEFS.pumpkin.growTime * 0.75)
    eq(crop.grown, false, 'not grown early')
    run(CROP_DEFS.pumpkin.growTime * 0.25 + 0.1)
    eq(crop.grown, true); eq(crop.active, true)
end)

test('planting: away from plots nothing is planted and no seed is used', function()
    local back = toRoom(2)
    run(0.2)
    eq(back:targetPlot(), nil, 'spawn is not near a plot')
    press('e')
    eq(FormatSeeds(back.gameData.seeds), 'beanstalk=0 pumpkin=2 vine=2')
    eq(#back.room.crops, 0)
    eq(back.message.text, 'Seeds only take on the soil plots')
    mock.click(1); step()                           -- a click while captured also tries to plant
    eq(FormatSeeds(back.gameData.seeds), 'beanstalk=0 pumpkin=2 vine=2')
end)

test('planting: occupied plots and empty seed types refuse without using seeds', function()
    local back = toRoom(2)
    back.player:setPosition(-4.4, 0, 0); run(0.2)
    press('e')
    eq(back.gameData.seeds.pumpkin, 1)
    press('e')
    eq(back.gameData.seeds.pumpkin, 1, 'second plant on the same plot refused')
    press('3')
    eq(back.selectedSeed, 'vine')
    press('e')
    eq(back.gameData.seeds.vine, 2, 'occupied plot refuses another type')
    eq(back.message.text, 'Something is already growing here')
    press('1')
    eq(back.selectedSeed, 'beanstalk', 'a type can be selected even with none held')
    back.player:setPosition(0.8, 0, 0); run(0.2)
    eq(back:targetPlot().id, 'edge')
    press('e')
    eq(back.gameData.seeds.beanstalk, 0); eq(back.room:plotById('edge').crop, nil, 'no beanstalk seeds: nothing planted')
    eq(back.message.text, 'No beanstalk seeds left')
end)

test('planting: 1-3 select, Q / Tab cycle through held types, a click plants', function()
    local back = toRoom(3)
    eq(FormatSeeds(back.gameData.seeds), 'beanstalk=2 pumpkin=2 vine=2')
    eq(back.selectedSeed, 'beanstalk')
    press('2'); eq(back.selectedSeed, 'pumpkin')
    press('q'); eq(back.selectedSeed, 'vine')
    press('tab'); eq(back.selectedSeed, 'beanstalk', 'cycling wraps')
    back.player:setPosition(-2.4, 0, 0); run(0.2)
    eq(back:targetPlot().id, 'foot')
    mock.click(1); step()
    eq(back.gameData.seeds.beanstalk, 1, 'left click planted the selected seed')
    eq(back.room:plotById('foot').crop.type, 'beanstalk')
    -- cycling skips types the player has none of
    local two = toRoom(2)
    eq(two.selectedSeed, 'pumpkin')
    press('q'); eq(two.selectedSeed, 'vine')
    press('q'); eq(two.selectedSeed, 'pumpkin', 'beanstalk (none held) skipped')
end)

test('planting: using the last seed of a type selects the next type held', function()
    local back = toRoom(2)
    back.gameData.seeds.pumpkin = 1
    back.player:setPosition(-4.4, 0, 0); run(0.2)
    press('e')
    eq(back.gameData.seeds.pumpkin, 0)
    eq(back.selectedSeed, 'vine')
end)

-- 5.3 climbing beanstalks, standing on pumpkins and vines ---------------------------
-- 8 x 6 x 6 room with a 2.6 m ledge x in [1, 4]; beanstalk plot 0.8 m before its face
local function ledgeRoom()
    return plotRoom(8, 6, 6, {{kind = 'solid', pos = {2.5, 0, 1.3}, size = {3, 6, 2.6}}}, {0.2, 0, 0})
end

test('climbing: walking into a grown beanstalk climbs it and steps off onto the ledge', function()
    loadGame()
    local room = ledgeRoom()
    local p = PlayerController(-2.5, 0, 0)
    simulateCrops(p, room, 3, {forward = 1}, 0)
    assert(p.x < 1 - R + 0.02, 'no beanstalk: stopped by the ledge face, x=' .. p.x)
    near(p.z, 0, 0.02, 'no beanstalk: still on the floor')
    growNow(room, 'p', 'beanstalk')
    p:setPosition(-2.5, 0, 0)
    local sawClimb, maxZ = false, 0
    for _ = 1, 4 * 60 do
        p:update(1 / 60, {forward = 1}, 0, room:solidColliders(), room:climbVolumes())
        if p.climbing then sawClimb = true end
        maxZ = math.max(maxZ, p.z)
    end
    assert(sawClimb, 'climbed')
    assert(maxZ <= CROP_DEFS.beanstalk.size[3] + 1e-9, 'never above the beanstalk top, maxZ=' .. maxZ)
    assert(p.x > 1.5, 'walked onto the ledge, x=' .. p.x)
    near(p.z, 2.6, 0.02, 'standing on the ledge'); eq(p.grounded, true); eq(p.climbing, nil)
end)

test('climbing: hold on with no input, climb down with back, and the top caps the climb', function()
    loadGame()
    local room = plotRoom(8, 6, 6, nil, {0, 0, 0})
    growNow(room, 'p', 'beanstalk')
    local top = CROP_DEFS.beanstalk.size[3]
    local p = PlayerController(0, 0, 0, {speed = 0})   -- climb in place
    simulateCrops(p, room, 0.3)
    eq(p.grounded, true)
    simulateCrops(p, room, 0.4, {forward = 1})
    near(p.z, BACKROOMS_CLIMB_SPEED * 0.4, 0.06, 'climbing at the climb speed')
    assert(p.climbing, 'climbing')
    local z = p.z
    simulateCrops(p, room, 1)
    near(p.z, z, 1e-9, 'holds on with no input (no gravity while climbing)')
    simulateCrops(p, room, 3, {forward = 1})
    near(p.z, top, 1e-9, 'hangs at the top')
    simulateCrops(p, room, 3, {forward = -1})
    near(p.z, 0, 0.01, 'climbed back down'); eq(p.grounded, true)
    -- leaving the volume sideways at the top: falls (it is not a floor)
    simulateCrops(p, room, 3, {forward = 1})
    local q = PlayerController(p.x, p.y, p.z)
    q.climbing = p.climbing
    simulateCrops(q, room, 1.5, {forward = 1}, 0)
    near(q.z, 0, 0.01, 'walked off the top and fell to the floor')
end)

test('climbing: a beanstalk does not catch a falling player, and an ungrown one is not climbable', function()
    loadGame()
    local room = plotRoom(8, 6, 6, nil, {0, 0, 0})
    growNow(room, 'p', 'beanstalk')
    local p = PlayerController(0, 0, 2, {speed = 0})   -- mid-air inside the stalk
    local frames = 0
    while not p.grounded and frames < 120 do
        p:update(1 / 60, {forward = 1}, 0, room:solidColliders(), room:climbVolumes())
        eq(p.climbing, nil, 'not caught while falling (frame ' .. frames .. ')')
        frames = frames + 1
    end
    near(p.z, 0, 0.01, 'fell through the volume to the floor'); eq(p.grounded, true)
    -- standing (or strafing) at the base does not latch on; forward climbs
    simulateCrops(p, room, 0.5)
    simulateCrops(p, room, 0.5, {strafe = 1})
    near(p.z, 0, 0.01, 'standing / strafing at the base stays on the floor'); eq(p.climbing, nil)
    simulateCrops(p, room, 0.4, {forward = 1})
    assert(p.z > 0.5 and p.climbing, 'climbs after landing, z=' .. p.z)

    local growing = plotRoom(8, 6, 6, nil, {0, 0, 0})
    local group = {}
    growing:plant(growing:plotById('p'), 'beanstalk', {beanstalk = 1}, group)
    Timer.update(CROP_DEFS.beanstalk.growTime * 0.9, group)
    local g = PlayerController(0, 0, 0, {speed = 0})
    simulateCrops(g, growing, 1, {forward = 1})
    near(g.z, 0, 0.01, 'a growing beanstalk cannot be climbed')
end)

test('standing: a pumpkin grown in a pit is walked over level with the floor', function()
    loadGame()
    local room = Reach.roomWith(BACKROOMS_ROOMS[2], {pit = 'pumpkin'})
    local s = room.spawn
    local p = PlayerController(s[1], s[2], s[3])
    local minZ = math.huge
    for _ = 1, 3 * 60 do
        p:update(1 / 60, {forward = 1}, 0, room:solidColliders(), room:climbVolumes())
        if p.x > -4 and p.x < -1.4 then minZ = math.min(minZ, p.z) end
        if p.x > -0.5 then break end                 -- on B, before the gap
    end
    assert(p.x > -1, 'crossed the pit, x=' .. p.x)
    assert(minZ > -0.02 and minZ < 0.05, 'stood on the pumpkin top over the pit, minZ=' .. minZ)
    eq(p.grounded, true)
    -- without it the same walk falls into the pit
    local bare = Room(BACKROOMS_ROOMS[2])
    local q = PlayerController(s[1], s[2], s[3])
    simulateCrops(q, bare, 3, {forward = 1}, 0)
    assert(q.z < bare.killZ, 'fell into the pit without the pumpkin, z=' .. q.z)
end)

test('standing: a grown vine bridges a gap and is walked across', function()
    loadGame()
    local room = Reach.roomWith(BACKROOMS_ROOMS[2], {pit = 'pumpkin', edge = 'vine'})
    local p = PlayerController(0.8, 0, 0)
    local minZ, reached = math.huge, false
    for _ = 1, 3 * 60 do
        p:update(1 / 60, {forward = 1}, 0, room:solidColliders(), room:climbVolumes())
        if p.x > 2 and p.x < 6 then minZ = math.min(minZ, p.z) end
        local a, b = p:bounds()
        if room:overlapsExit(a, b) then reached = true break end
    end
    assert(reached, 'walked across the vine to the exit')
    assert(minZ > -0.02 and minZ < 0.05, 'stayed on the vine over the gap, minZ=' .. minZ)
    local bare = Reach.roomWith(BACKROOMS_ROOMS[2], {pit = 'pumpkin'})
    local q = PlayerController(0.8, 0, 0)
    simulateCrops(q, bare, 3, {forward = 1}, 0)
    assert(q.z < bare.killZ, 'fell into the gap without the vine')
end)

-- 5.4 tutorial room -------------------------------------------------------------------
-- Is the straight line from (ax, ay, az) to (bx, by, bz) clear of every collider?
local function lineClear(room, ax, ay, az, bx, by, bz)
    local dx, dy, dz = bx - ax, by - ay, bz - az
    local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
    dx, dy, dz = dx / dist, dy / dist, dz / dist
    for _, c in ipairs(room:solidColliders()) do
        local len = g3d.collisions.rayIntersection(c.verts, c.transform, ax, ay, az, dx, dy, dz)
        if len and len < dist - 1e-6 then return false end
    end
    return true
end

test('tutorial: room 1 starts with a frozen half-grown beanstalk and a visible, unreachable exit', function()
    local back = toBackrooms()
    local room = back.room
    eq(room.id, 'tutorial')
    eq(#room.plots, 1, 'one plot only')
    local demo = room:plotById('demo').crop
    assert(demo and demo.demo and demo.type == 'beanstalk', 'demo beanstalk on the plot')
    eq(demo.progress, 0.5)
    local _, _, sz = demo:scale()
    near(sz * CROP_DEFS.beanstalk.size[3], (CROP_MIN_SCALE + (1 - CROP_MIN_SCALE) * 0.5) * 3, 1e-9, 'drawn half height')
    -- it points at the exit: the plot is at the foot of the exit ledge
    assert(room.exit.pos[3] > CROP_DEFS.beanstalk.size[3] * 0.5 + 1.7, 'exit above the half-grown crop')
    run(10)
    eq(demo.progress, 0.5, 'demo frozen until a seed is planted'); eq(demo.active, false)
    eq(#room:climbVolumes(), 0, 'half-grown demo cannot be climbed')
    -- visible from the spawn: lines of sight to the exit marker and the demo top
    local s = room.spawn
    local ex, ey, ez = s[1], s[2], s[3] + BACKROOMS_EYE_HEIGHT
    assert(lineClear(room, ex, ey, ez, room.exit.pos[1], room.exit.pos[2], room.exit.max[3] - 0.2), 'exit marker visible')
    assert(lineClear(room, ex, ey, ez, 1.2, 0, 1.4), 'demo crop visible')
    -- unreachable: walking at it does nothing, and a search finds no way
    back.player:setPosition(s[1], s[2], s[3])
    eq(holdUntil('w', function() return back.roomIndex ~= 1 end, 5), false, 'walking forward does not reach the exit')
    local reached, info = Reach.search(Room(BACKROOMS_ROOMS[1]))
    eq(reached, false, 'no explored path reaches the exit (' .. info.cells .. ' cells)')
    eq(FormatSeeds(FIRST_ROOM_MIN_SEEDS), FormatSeeds(BACKROOMS_ROOMS[1].allotment))
    eq(FormatSeeds(FIRST_ROOM_MIN_SEEDS), 'beanstalk=1 pumpkin=0 vine=0', 'exactly one seed needed')
end)

test('tutorial: the demo plot refuses other types, so carried surplus seeds cannot help', function()
    local back = toBackrooms({beanstalk = 3, pumpkin = 5, vine = 4})
    eq(FormatSeeds(back.gameData.seeds), 'beanstalk=3 pumpkin=5 vine=4', 'farm seeds carried into room 1')
    back.player:setPosition(0.4, 0, 0); run(0.2)
    eq(back:targetPlot().id, 'demo')
    for _, t in ipairs({'pumpkin', 'vine'}) do
        back.selectedSeed = t
        press('e')
        eq(back.gameData.seeds[t], t == 'pumpkin' and 5 or 4, t .. ' refused at the demo plot')
        eq(back.message.text, 'This beanstalk needs a beanstalk seed')
    end
    eq(#back.room.crops, 1); eq(back.room:plotById('demo').crop.progress, 0.5)
    -- room 1's only plot is the demo plot, so no other seed has anywhere to go
    for _, p in ipairs({{-4, 0}, {-2, 2}, {0, -2.5}, {-5, -2.5}}) do
        eq(back.room:nearestPlot(p[1], p[2], 0), nil)
    end
end)

test('tutorial: one beanstalk seed finishes the demo and the climb reaches the exit', function()
    local back = toBackrooms({beanstalk = 0, pumpkin = 0, vine = 0})
    eq(FormatSeeds(back.gameData.seeds), 'beanstalk=1 pumpkin=0 vine=0', 'topped up to the one seed needed')
    run(0.3)
    assert(holdUntil('w', function() return back.player.x >= 0.3 end, 3), 'walked to the demo plot')
    eq(back:targetPlot().id, 'demo')
    press('e')
    eq(back.gameData.seeds.beanstalk, 0, 'the seed was used')
    local demo = back.room:plotById('demo').crop
    assert(demo.timer, 'demo growing again')
    run(0.3)
    assert(demo.progress > 0.5 and demo.progress < 1, 'grows from half, progress=' .. demo.progress)
    run(CROP_DEFS.beanstalk.growTime / 2)
    eq(demo.grown, true); eq(demo.active, true)
    eq(#back.room:climbVolumes(), 1)
    assert(holdUntil('w', function() return back.roomIndex == 2 end, 6), 'climbed and reached the exit')
    eq(back.room.id, BACKROOMS_ROOMS[2].id)
end)

-- 5.5 room reset ----------------------------------------------------------------------
test('reset: R after wasting seeds returns room 2 to its initial state', function()
    local back = toRoom(2)
    run(0.5)
    local fresh = roomSignature(back)
    -- waste: a vine in the pit, a pumpkin at the edge (half grown)
    back.player:setPosition(-4.4, 0, 0); run(0.2)
    press('3'); press('e')
    back.player:setPosition(0.8, 0, 0); run(0.2)
    press('2'); press('e')
    run(1)
    eq(FormatSeeds(back.gameData.seeds), 'beanstalk=0 pumpkin=1 vine=1')
    eq(#back.room.crops, 2); assert(#back.timers >= 1, 'something still growing')
    local oldRoom = back.room
    press('r')
    assert(back.room ~= oldRoom, 'rebuilt')
    eq(#back.room.crops, 0, 'all crops removed')
    for _, plot in ipairs(back.room.plots) do eq(plot.crop, nil, 'plot ' .. plot.id .. ' empty') end
    eq(#back.timers, 0, 'pending growth cancelled')
    eq(FormatSeeds(back.gameData.seeds), 'beanstalk=0 pumpkin=2 vine=2', 'allotment restored')
    eq(back.roomIndex, 2)
    eq(back.message.text, 'Room reset')
    run(0.5)
    eq(roomSignature(back), fresh, 'identical to entering the room')
    run(5)
    eq(#back.room.crops, 0, 'nothing grows back after the reset')
end)

test('reset: room 1 reset returns the demo crop to its half-grown start', function()
    local back = toBackrooms({beanstalk = 2, pumpkin = 1, vine = 0})
    run(0.5)
    local fresh = roomSignature(back)
    back.player:setPosition(0.4, 0, 0); run(0.2)
    press('e')
    run(CROP_DEFS.beanstalk.growTime)             -- the demo needs only half of this
    local demo = back.room:plotById('demo').crop
    eq(demo.grown, true)
    eq(back.gameData.seeds.beanstalk, 1)
    press('r')
    local again = back.room:plotById('demo').crop
    assert(again ~= demo, 'demo crop rebuilt')
    eq(again.progress, 0.5); eq(again.grown, false); eq(again.active, false); eq(again.timer, nil)
    eq(FormatSeeds(back.gameData.seeds), 'beanstalk=2 pumpkin=1 vine=0', 'recorded room 1 start restored')
    run(0.5)
    eq(roomSignature(back), fresh)
    eq(again.progress, 0.5, 'still frozen after the reset')
end)

test('reset: is deterministic whatever happened before it', function()
    local histories = {
        function() end,
        function(back)
            back.player:setPosition(-6.4, 0, 0); run(0.2); press('2'); press('e'); run(3)
            back.player:setPosition(-2.4, 0, 0); run(0.2); press('1'); press('e'); run(0.5)
        end,
        function(back)
            back.player:setPosition(-2.4, 0, 0); run(0.2); press('3'); press('e')
            mock.hold('w'); run(1.5); mock.release('w')
            love.mousemoved(0, 0, 200, -50)
        end,
    }
    local sigs = {}
    for i, history in ipairs(histories) do
        local back = toRoom(3)
        history(back)
        press('r'); run(0.5)
        sigs[i] = roomSignature(back)
        press('r'); run(0.5)
        eq(roomSignature(back), sigs[i], 'history ' .. i .. ': reset twice gives the same room')
    end
    eq(sigs[2], sigs[1]); eq(sigs[3], sigs[1])
end)

-- 5.6 / 5.7 combination rooms -----------------------------------------------------------
test('room 2: pumpkin in the pit then vine at the edge, played through the state, reaches room 3', function()
    local back = toRoom(2, {beanstalk = 9, pumpkin = 9, vine = 9})
    eq(FormatSeeds(back.gameData.seeds), 'beanstalk=0 pumpkin=2 vine=2', 'fixed allotment, no farm surplus, no beanstalks')
    run(0.3)
    assert(holdUntil('w', function() return back.player.x >= -4.4 end, 3), 'to the pit rim')
    eq(back:targetPlot().id, 'pit'); eq(back.selectedSeed, 'pumpkin')
    press('e')
    run(CROP_DEFS.pumpkin.growTime + 0.2)
    assert(back.room:plotById('pit').crop.active, 'pumpkin grown')
    assert(holdUntil('w', function() return back.player.x >= 0.8 end, 3), 'over the pumpkin to the far side')
    near(back.player.z, 0, 0.02)
    eq(back:targetPlot().id, 'edge')
    press('3'); press('e')
    run(CROP_DEFS.vine.growTime + 0.2)
    assert(holdUntil('w', function() return back.roomIndex == 3 end, 4), 'across the vine to the exit')
    eq(back.room.id, BACKROOMS_ROOMS[3].id)
end)

test('room 2: one seed type alone never reaches the exit', function()
    loadGame()
    local data = BACKROOMS_ROOMS[2]
    for _, t in ipairs(SEED_TYPES) do
        local reached, info = Reach.search(Reach.roomWith(data, {pit = t, edge = t}))
        eq(reached, false, 'only ' .. t .. ' on every plot (' .. info.cells .. ' cells)')
        for _, plot in ipairs({'pit', 'edge'}) do
            local r1 = Reach.search(Reach.roomWith(data, {[plot] = t}))
            eq(r1, false, 'only ' .. t .. ' on ' .. plot)
        end
    end
    eq((data.allotment.beanstalk or 0), 0, 'no beanstalk seeds in room 2')
    -- played through the state with pumpkins only: walking on over the gap falls and respawns
    local back = toRoom(2)
    back.player:setPosition(-4.4, 0, 0); run(0.2); press('e'); run(2.5)
    back.player:setPosition(0.8, 0, 0); run(0.2); press('e'); run(2.5)
    eq(back.gameData.seeds.pumpkin, 0, 'both pumpkins planted')
    for _, y in ipairs({-2.5, -1.5, -0.5, 0.5, 1.5, 2.5}) do
        back.player:setPosition(-0.5, y, 0); run(0.1)
        holdUntil('w', function() return back.player.x < -6 end, 4)   -- until respawned at the spawn
        eq(back.roomIndex, 2, 'pumpkins only: still in room 2 (lane y=' .. y .. ')')
    end
end)

test('room 2: the correct combination is the only one that reaches the exit', function()
    loadGame()
    local data = BACKROOMS_ROOMS[2]
    local reached = Reach.search(Reach.roomWith(data, {pit = 'pumpkin', edge = 'vine'}))
    eq(reached, true, 'pumpkin + vine solves room 2')
    eq(Reach.search(Reach.roomWith(data, {pit = 'vine', edge = 'pumpkin'})), false, 'swapped plots')
    eq(Reach.search(Reach.roomWith(data, {pit = 'pumpkin', edge = 'beanstalk'})), false, 'beanstalk is no bridge')
end)

test('room 3: pumpkin, beanstalk and vine, played through the state, reach the ending', function()
    local back = toRoom(3, {beanstalk = 9, pumpkin = 9, vine = 9})
    eq(FormatSeeds(back.gameData.seeds), 'beanstalk=2 pumpkin=2 vine=2', 'fixed allotment')
    local changes = countChanges()
    run(0.3)
    assert(holdUntil('w', function() return back.player.x >= -6.4 end, 3), 'to the pit rim')
    eq(back:targetPlot().id, 'pit')
    press('2'); press('e')
    run(CROP_DEFS.pumpkin.growTime + 0.2)
    assert(holdUntil('w', function() return back.player.x >= -2.5 end, 3), 'over the pumpkin')
    eq(back:targetPlot().id, 'foot')
    press('1'); press('e')
    run(CROP_DEFS.beanstalk.growTime + 0.2)
    assert(holdUntil('w', function() return back.player.x >= 0.6 and back.player.z > 2.5 end, 5), 'climbed onto the ledge')
    eq(back:targetPlot().id, 'lip')
    press('3'); press('e')
    run(CROP_DEFS.vine.growTime + 0.2)
    assert(holdUntil('w', function() return isState(gStateMachine.current, EndingState) end, 4), 'across the vine to the final exit')
    eq(#changes, 1); eq(changes[1], 'ending', 'room 3 is the last room: its exit shows the ending')
    eq(FormatSeeds(gStateMachine.current.gameData.seeds), 'beanstalk=1 pumpkin=1 vine=1', 'spares left')
end)

test('room 3: single types and every combination missing a type fail; all three succeed', function()
    loadGame()
    local data = BACKROOMS_ROOMS[3]
    for _, t in ipairs(SEED_TYPES) do
        local reached, info = Reach.search(Reach.roomWith(data, {pit = t, foot = t, lip = t}))
        eq(reached, false, 'only ' .. t .. ' (' .. info.cells .. ' cells)')
    end
    local missing = {
        {foot = 'beanstalk', lip = 'vine'},                       -- no pumpkin
        {pit = 'pumpkin', lip = 'vine'},                          -- no beanstalk
        {pit = 'pumpkin', foot = 'beanstalk'},                    -- no vine
        {pit = 'pumpkin', foot = 'beanstalk', lip = 'beanstalk'}, -- spare beanstalk instead of the vine
        {pit = 'pumpkin', foot = 'beanstalk', lip = 'pumpkin'},   -- spare pumpkin instead of the vine
    }
    for _, crops in ipairs(missing) do
        local reached, info = Reach.search(Reach.roomWith(data, crops))
        eq(reached, false, Reach.describe(crops) .. ' (' .. info.cells .. ' cells, maxX ' .. string.format('%.2f', info.maxX) .. ')')
    end
    local reached = Reach.search(Reach.roomWith(data, {pit = 'pumpkin', foot = 'beanstalk', lip = 'vine'}))
    eq(reached, true, 'all three solve room 3')
end)

test('rooms: every exit is out of reach on entry', function()
    loadGame()
    for i, data in ipairs(BACKROOMS_ROOMS) do
        local reached, info = Reach.search(Room(data))
        eq(reached, false, 'room ' .. i .. ' exit reachable without crops (' .. info.cells .. ' cells)')
    end
end)

realPrint(string.format('\n%d passed, %d failed', passed, failed))
os.exit(failed == 0 and 0 or 1)
