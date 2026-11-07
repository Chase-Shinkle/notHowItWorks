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
    eq(d.crops.beanstalk, 0); eq(d.crops.pumpkin, 0); eq(d.crops.vine, 0)
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

test('farm: shared game data survives farm -> backrooms', function()
    local farm = toFarm()
    press('e')                                          -- spend one beanstalk seed
    local data = farm.gameData
    mock.press('f1'); step()
    assert(gStateMachine.current.gameData == data, 'same table')
    assert(find(mock.printed, 'beanstalk=1 pumpkin=2 vine=2'), 'spent seed visible in backrooms')
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

realPrint(string.format('\n%d passed, %d failed', passed, failed))
os.exit(failed == 0 and 0 or 1)
