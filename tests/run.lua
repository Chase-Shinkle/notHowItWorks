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
    -- the pre-sequence puzzle rooms stay the default for the older tests; the
    -- sequence tests (section 4 of procedural-backrooms-levels) clear it
    BackroomsState.roomsOverride = BACKROOMS_ROOMS
    BACKROOMS_RUN_SEED = nil
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

-- pixel-art filtering (polish M1) -------------------------------------------
-- Every sprite, tile, billboard texture and font must be nearest; only the
-- large backrooms surfaces may be linear. Fails if main.lua sets the default
-- filter after src/Dependencies has already loaded the assets.
local function filterOf(obj)
    local min, mag = obj:getFilter()
    return min .. '/' .. mag
end

test('filtering: sprites, tiles, billboards and fonts load nearest; surfaces are linear', function()
    loadGame()
    local surfaces = {}
    for _, key in ipairs(SMOOTH_SURFACE_TEXTURES) do surfaces[key] = true end
    for _, key in ipairs(PROCEDURAL_SURFACE_TEXTURES) do
        eq(filterOf(gTextures[key]), 'linear/linear', 'procedural ' .. key)
        surfaces[key] = nil
        gTextures[key] = nil
    end
    local n = 0
    for key, image in pairs(gTextures) do
        if not surfaces[key] then
            eq(filterOf(image), 'nearest/nearest', 'texture ' .. key)
            n = n + 1
        end
    end
    assert(n > 20, 'checked every pixel-art texture (' .. n .. ')')
    for _, key in ipairs({'hero', 'crop-pumpkin-3', 'plot', 'well', 'bucket'}) do
        eq(filterOf(gTextures[key]), 'nearest/nearest', key)
    end
    eq(filterOf(gFonts['default']), 'nearest/nearest', 'default font')
    eq(filterOf(gFonts['small']), 'nearest/nearest', 'small font')
    for key in pairs(surfaces) do
        eq(filterOf(gTextures[key]), 'linear/linear', 'surface ' .. key)
        eq(gTextures[key].mipmaps, true, 'surface ' .. key .. ' mipmapped')
        eq(gTextures[key]:getMipmapFilter(), 'linear', 'surface ' .. key .. ' mipmap filter')
    end
end)

test('filtering: forced placeholder images are nearest too (surfaces included)', function()
    loadGame({'--placeholder-assets'})
    for key, image in pairs(gTextures) do
        assert(Assets.isPlaceholder(image) or key == 'white', key .. ' is a placeholder')
        eq(filterOf(image), 'nearest/nearest', 'placeholder ' .. key)
    end
    eq(filterOf(gFonts['default']), 'nearest/nearest', 'default font')
end)

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
    loadGame({'--debug'})
    mock.press('f1'); step()          -- start -> farm
    mock.press('f1'); step()          -- farm -> backrooms
    mock.reset()
    love.draw()
    eq(mock.count('push.apply'), 0, 'push bypassed')
    local room = gStateMachine.current.room
    eq(#room.exitFrame, 5, 'exit frame is four corner posts and a lintel (black door, all orientations)')
    eq(mock.count('model.draw'), #room.models + #room.plots + #room.crops + 1 + #room.exitFrame + #room.billboards,
        'room boxes, plots, crops, exit marker, exit frame and billboards drawn')
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
    loadGame({'--debug'})
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
    loadGame({'--debug'})
    DEBUG_MODE = false
    mock.press('f1'); step()
    assert(gStateMachine.current.usesPush == nil, 'still at start')
    mock.press('return'); step()
    eq(gStateMachine.current.usesPush, true, 'enter still starts the farm')
end)

-- release config (polish M2) ---------------------------------------------------
local function debugTexts()
    local found = {}
    for _, c in ipairs(mock.calls) do
        local t = (c.name == 'print' or c.name == 'printf') and c.args[1]
        if type(t) == 'string' and (t:find('debug', 1, true) or t:find('fps', 1, true) or t == DEBUG_ADVANCE_KEY) then
            found[#found + 1] = t
        end
    end
    return found
end

test('release: debug mode is off by default; F1 changes no state and no debug text is drawn', function()
    loadGame({'.'})
    eq(DEBUG_MODE, false, 'default off')
    mock.press('f1'); step()
    assert(isState(gStateMachine.current, StartState), 'F1 ignored at start')
    mock.press('return'); step()
    local farm = gStateMachine.current
    mock.press('f1'); step()
    eq(gStateMachine.current, farm, 'F1 ignored on the farm')
    mock.reset(); love.draw()
    eq(#debugTexts(), 0, 'no farm debug text: ' .. table.concat(debugTexts(), ' | '))
    gStateMachine:change('backrooms', CarryOverGameData(farm.gameData))
    local back = gStateMachine.current
    mock.press('f1'); step()
    eq(gStateMachine.current, back, 'F1 ignored in the backrooms')
    eq(back.roomIndex, 1, 'F1 does not skip the room')
    mock.reset(); love.draw()
    eq(#debugTexts(), 0, 'no backrooms debug text: ' .. table.concat(debugTexts(), ' | '))
    back:advance(); back:advance(); back:advance()
    assert(isState(gStateMachine.current, EndingState), 'ending')
    mock.press('f1'); step()
    assert(isState(gStateMachine.current, EndingState), 'F1 ignored on the ending')
end)

test('release: --debug opts in to F1 skip and the debug HUD text', function()
    loadGame({'.', '--debug'})
    eq(DEBUG_MODE, true, '--debug turns it on')
    mock.press('f1'); step()
    local farm = gStateMachine.current
    eq(farm.usesPush, true, 'F1: start -> farm')
    mock.reset(); love.draw()
    assert(#debugTexts() > 0, 'farm F1 marker drawn')
    mock.press('f1'); step()
    eq(gStateMachine.current.usesPush, false, 'F1: farm -> backrooms')
    mock.reset(); love.draw()
    assert(find(debugTexts(), 'debug skip'), 'backrooms debug line drawn')
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
    loadGame({'--debug'})
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
    loadGame({'.', '--placeholder-assets', '--debug'})
    eq(Assets.forcePlaceholders, true)
    for _, key in ipairs({'grass', 'soil', 'hero', 'wall', 'floor'}) do
        assert(gTextures[key], 'texture ' .. key)
    end
    assert(gSounds['plant'].isPlaceholder, 'sound placeholder')
    mock.press('f1'); step(); love.draw()
    mock.press('f1'); step(); love.draw()
    eq(gStateMachine.current.usesPush, false, 'reached backrooms')
end)

-- 6.1 asset integration ---------------------------------------------------------
test('supplied art is used: backrooms textures load and rooms switch to the light tint', function()
    loadGame()
    for _, key in ipairs({'wall', 'floor', 'ceiling', 'well', 'bucket', 'sacks'}) do
        assert(gTextures[key], 'texture ' .. key)
        eq(Assets.isPlaceholder(gTextures[key]), false, 'real texture ' .. key)
    end
    local _, isPh = Assets.loadImage('graphics/nope.png')
    eq(isPh, true)
    -- placeholders are flagged on the object too
    local img = Assets.loadImage('graphics/nope.png')
    eq(Assets.isPlaceholder(img), true)
    eq(Assets.isPlaceholder(Assets.loadSound('sounds/nope.wav')), true)
    -- a real wall texture is tinted white, not multiplied by the flat yellow
    local room = Room({id = 't', spawn = {0, 0, 0}, boxes = {{kind = 'wall', pos = {0, 0, 0}, size = {1, 1, 1}}},
        exit = {pos = {5, 0, 1}, size = {1, 1, 1}}, allotment = {}})
    assert(room.models[1], 'wall model')
    local v = room.colliders[1].verts[1]
    eq(v[9] >= 0.84 and v[10] >= 0.84 and v[11] >= 0.84, true, 'light tint on real texture')
end)

test('forced placeholders keep the flat room colours', function()
    loadGame({'.', '--placeholder-assets'})
    eq(Assets.isPlaceholder(gTextures['wall']), true)
    local room = Room({id = 't', spawn = {0, 0, 0}, boxes = {{kind = 'wall', pos = {0, 0, 0}, size = {1, 1, 1}}},
        exit = {pos = {5, 0, 1}, size = {1, 1, 1}}, allotment = {}})
    local v = room.colliders[1].verts[1]
    eq(v[11] < 0.5, true, 'flat yellow tint (blue channel low) on placeholder')
end)

test('every loaded sound is hooked into the game code', function()
    loadGame()
    local code = ''
    for _, f in ipairs({'src/states/game/FarmState.lua', 'src/states/game/BackroomsState.lua',
                        'src/states/game/StartState.lua', 'src/states/game/EndingState.lua'}) do
        local fh = assert(io.open(f, 'r')); code = code .. fh:read('*a'); fh:close()
    end
    -- footstep-N keys are wired dynamically: BackroomsAudio builds gSounds['footstep-' .. i] for
    -- 1..#BACKROOMS_FOOTSTEP_FILES, and BackroomsState creates and updates it.
    local fa = assert(io.open('src/BackroomsAudio.lua', 'r')); local audioCode = fa:read('*a'); fa:close()
    assert(audioCode:find("gSounds%['footstep%-' %.%. i%]", 1, false), 'BackroomsAudio loads footstep-i dynamically')
    assert(audioCode:find('for i = 1, #BACKROOMS_FOOTSTEP_FILES', 1, true), 'all footstep files are loaded')
    assert(code:find('BackroomsAudio.new()', 1, true) and code:find('self.audio:update(', 1, true),
        'BackroomsState creates and updates BackroomsAudio')
    for key in pairs(gSounds) do
      if not key:match('^footstep%-%d+$') then
        assert(code:find("gSounds%['" .. key:gsub('%-', '%%-') .. "'%]"), 'sound ' .. key .. ' is never used')
      else
        assert(tonumber(key:match('%d+')) <= #BACKROOMS_FOOTSTEP_FILES, key .. ' is outside the dynamic footstep range')
      end
    end
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
    -- farmer starts facing an empty, untilled plot: the first E press tills it
    local target = farm:facingTarget()
    eq(target and target.kind, 'plot'); eq(target.plot.state, PLOT_EMPTY)
    eq(target.plot.tilled, false); eq(farm:plotAction(target.plot), 'till')
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

test('farm: the first use tills, the next plants one seed of the selected type', function()
    local farm = toFarm()
    local d = farm.gameData
    eq(farm.selectedSeed, 'beanstalk')
    press('2'); eq(farm.selectedSeed, 'pumpkin')
    local plot = farm:facingTarget().plot
    eq(farm:hintText(), '[E] till the soil (shovel)')
    press('e')
    eq(plot.tilled, true); eq(plot.state, PLOT_EMPTY, 'tilling plants nothing')
    eq(Farm.totalSeeds(d), Farm.totalSeeds(NewGameData()), 'no seed consumed by tilling')
    eq(farm.popups[#farm.popups].text, 'tilled', 'tilling feedback')
    eq(farm:hintText(), '[E] plant pumpkin (seed bag)')
    press('e')
    eq(plot.state, PLOT_GROWING); eq(plot.seedType, 'pumpkin'); eq(plot.stage, 1)
    eq(plot.watered, false, 'a new crop starts unwatered')
    eq(d.seeds.pumpkin, STARTING_SEEDS.pumpkin - 1)
    eq(d.seeds.beanstalk, STARTING_SEEDS.beanstalk, 'other seeds untouched')
    -- interacting again with a growing plot waters it and plants nothing more
    eq(farm:hintText(), '[E] water pumpkin (watering can)')
    press('space')
    eq(plot.watered, true)
    eq(d.seeds.pumpkin, STARTING_SEEDS.pumpkin - 1)
    eq(farm:hintText(), 'pumpkin growing...')
    -- an already-watered crop is unchanged by another use
    eq(farm:interact(farm:facingTarget()), 'growing')
    eq(plot.watered, true); eq(d.seeds.pumpkin, STARTING_SEEDS.pumpkin - 1)
end)

test('farm: planting with no seeds does nothing', function()
    loadGame()
    gStateMachine:change('farm', NewGameData({seeds = {}}))
    local farm = gStateMachine.current
    eq(Farm.totalSeeds(farm.gameData), 0)
    eq(farm:hintText(), '[E] till the soil (shovel)', 'tilling needs no seeds')
    press('e')
    eq(farm:facingTarget().plot.tilled, true)
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
    press('e')                                          -- till
    eq(farm:hintText(), '[E] plant corn (seed bag)', 'vine reads as corn')
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

-- till, plant and (unless `dry`) water the plot the farmer faces
local function tillPlantWater(dry)
    press('e'); press('e')
    if not dry then press('e') end
end

test('farm: crops grow through visible stages and mature (watered)', function()
    local farm = toFarm()
    tillPlantWater()
    local plot = farm:facingTarget().plot
    eq(plot.watered, true)
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
    eq(#farm.timers, 0, 'growth uses no Timer')
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
    tillPlantWater()
    local plot = farm:facingTarget().plot
    local total = FARM_STAGE_TIME * (FARM_GROWTH_STAGES - 1)
    run(total - 0.1)
    eq(plot.state, PLOT_GROWING, 'not yet mature')
    run(0.2)
    eq(plot.state, PLOT_MATURE)
end)

test('farm: immature crops cannot be harvested', function()
    local farm = toFarm()
    tillPlantWater()
    run(FARM_STAGE_TIME + 0.05)
    press('e')
    local plot = farm:facingTarget().plot
    eq(plot.state, PLOT_GROWING); eq(plot.stage, 2)
    eq(Farm.totalCrops(farm.gameData), 0, 'inventory unchanged')
end)

test('farm: harvesting a mature crop adds it to the inventory and clears the plot', function()
    local farm = toFarm()
    tillPlantWater()
    run(FARM_STAGE_TIME * FARM_GROWTH_STAGES)
    local plot = farm:facingTarget().plot
    eq(farm:hintText(), '[E] harvest beanstalk (sickle)')
    press('e')
    eq(plot.state, PLOT_EMPTY); eq(plot.seedType, nil); eq(plot.stage, 0)
    eq(plot.tilled, true, 'stays tilled'); eq(plot.watered, false, 'the water is used up')
    eq(farm.gameData.crops.beanstalk, 1)
    eq(farm.gameData.seeds.beanstalk, STARTING_SEEDS.beanstalk - 1, 'harvest gives a crop, not a seed')
    -- the plot is replanted on the next use, without tilling again, unwatered
    eq(farm:hintText(), '[E] plant beanstalk (seed bag)')
    press('e'); eq(plot.state, PLOT_GROWING); eq(plot.watered, false)
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
    mock.mouseAt(px + 10, py + 10); mock.click(1); step()          -- till
    local plot = farm:plotAt(FARM_PLOTS.col, FARM_PLOTS.row)
    eq(plot.tilled, true)
    mock.click(1); step()                                          -- plant
    mock.click(1); step()                                          -- water
    eq(plot.watered, true)
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
    act('e'); act('e'); act('e')                                   -- till, plant, water
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

test('farm: first cycle without watering still finishes well under 3 minutes', function()
    local farm = toFarm()
    local frames = 0
    local function act(key) mock.press(key); step(); frames = frames + 1 + run(0.25) end
    act('e'); act('e')                                             -- till, plant (no water)
    local plot = farm:facingTarget().plot
    frames = frames + run(Farm.growthTime(true) + 0.1)
    eq(plot.state, PLOT_GROWING, 'unwatered: not mature after the watered time')
    frames = frames + run(Farm.growthTime(false) - Farm.growthTime(true))
    act('e')
    eq(Farm.totalCrops(farm.gameData), 1, 'harvested')
    for _ = 1, FARM_VILLAGER.col - 1 - FARM_PLAYER_START.col do act('right') end
    for _ = 1, FARM_PLAYER_START.row - FARM_VILLAGER.row do act('up') end
    act('right'); act('e')
    eq(farm.gameData.hasSold, true)
    local seconds = frames / 60
    assert(seconds < 180 and seconds < 40, 'unwatered cycle took ' .. seconds .. ' s')
end)

test('farm: growth is not on any Timer group (state or global) and stops on exit', function()
    local farm = toFarm({'--debug'})
    tillPlantWater()
    eq(#farm.timers, 0, 'no growth timer on the state group')
    eq(#Timer.defaultGroup, 0, 'growth not on the global group')
    local plot = farm:facingTarget().plot
    mock.press('f1'); step()
    local progress = plot.progress
    run(5)
    eq(plot.progress, progress, 'nothing advances the farm once it is left')
end)

test('farm: renders HUD and field with every asset as a placeholder', function()
    local farm = toFarm({'.', '--placeholder-assets'})
    tillPlantWater()
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
    local farm = toFarm({'--debug'})
    press('e'); press('e')                              -- till, then spend one beanstalk seed
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
    local ok, why = Farm.harvest(plot, d); eq(ok, false); eq(why, 'empty')
    ok, why = Farm.plant(plot, d, 'pumpkin'); eq(ok, false); eq(why, 'untilled')
    eq(d.seeds.pumpkin, 1, 'untilled plot takes no seed')
    ok, why = Farm.water(plot); eq(ok, false); eq(why, 'not-growing')
    ok = Farm.till(plot); eq(ok, true); eq(plot.tilled, true)
    ok, why = Farm.till(plot); eq(ok, false); eq(why, 'tilled')
    ok, why = Farm.plant(plot, d, 'pumpkin'); eq(ok, true); eq(why, 'pumpkin')
    ok, why = Farm.plant(plot, d, 'pumpkin'); eq(ok, false); eq(why, 'occupied')
    ok, why = Farm.till(plot); eq(ok, false); eq(why, 'occupied')
    ok, why = Farm.harvest(plot, d); eq(ok, false); eq(why, 'immature')
    eq(Farm.advance(plot, FARM_STAGE_TIME * FARM_GROWTH_STAGES * 2), FARM_GROWTH_STAGES, 'one big step')
    eq(plot.state, PLOT_MATURE)
    ok, why = Farm.water(plot); eq(ok, false); eq(why, 'not-growing', 'mature crops need no water')
    ok, why = Farm.harvest(plot, d); eq(ok, true); eq(why, 'pumpkin')
    eq(plot.tilled, true)
    ok, why = Farm.plant(plot, d, 'pumpkin'); eq(ok, false); eq(why, 'no-seeds')
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
    local farm = farmAtVillager({hasSold = true, seeds = {beanstalk = 2}}, {'--debug'})   -- F1 live too
    -- a mature crop the player could otherwise harvest by click
    local plot = farm:plotAt(FARM_PLOTS.col, FARM_PLOTS.row)
    plot.state, plot.seedType, plot.stage = PLOT_MATURE, 'beanstalk', FARM_GROWTH_STAGES
    local growing = farm:plotAt(FARM_PLOTS.col + 1, FARM_PLOTS.row)
    growing.tilled = true
    Farm.plant(growing, farm.gameData, 'beanstalk')
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
    Farm.till(plot)
    Farm.plant(plot, farm.gameData, 'vine')
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

-- seed stall (polish M4, farm) ----------------------------------------------------
test('shop: every seed price is below its crop sale value', function()
    loadGame()
    for _, t in ipairs(SEED_TYPES) do
        assert(SEED_PRICES[t] and SEED_PRICES[t] > 0, 'price for ' .. t)
        assert(SEED_PRICES[t] < CROP_VALUES[t], t .. ' price ' .. SEED_PRICES[t] .. ' < sale value ' .. CROP_VALUES[t])
    end
end)

test('shop: Farm.buySeed succeeds, refuses without enough coins, and only touches coins and that seed', function()
    loadGame()
    local data = NewGameData({coins = 5, crops = {pumpkin = 2}, hasSold = true})
    local ok, seedType, price = Farm.buySeed(data, 'pumpkin')
    eq(ok, true); eq(seedType, 'pumpkin'); eq(price, SEED_PRICES.pumpkin)
    eq(data.coins, 5 - SEED_PRICES.pumpkin)
    eq(FormatSeeds(data.seeds), 'beanstalk=2 pumpkin=3 vine=2', 'one pumpkin seed added')
    eq(data.crops.pumpkin, 2, 'crops unchanged'); eq(data.hasSold, true, 'hasSold unchanged')
    eq(data.hasBroken, false, 'break flag unchanged')
    -- 1 coin left: not enough for anything but... nothing (cheapest is 2)
    local before = FormatSeeds(data.seeds)
    local ok2, reason, price2 = Farm.buySeed(data, 'vine')
    eq(ok2, false); eq(reason, 'no-coins'); eq(price2, SEED_PRICES.vine)
    eq(data.coins, 1, 'coins unchanged'); eq(FormatSeeds(data.seeds), before, 'seeds unchanged')
    -- before any sale, too
    local fresh = NewGameData()
    eq(select(2, Farm.buySeed(fresh, 'beanstalk')), 'no-coins')
    eq(fresh.hasSold, false); eq(fresh.coins, 0)
    eq(select(2, Farm.buySeed(fresh, 'carrot')), 'unknown-seed')
end)

test('shop: plant -> harvest -> sell -> rebuy the same seed leaves more coins than before', function()
    loadGame()
    for _, t in ipairs(SEED_TYPES) do
        local data = NewGameData({seeds = {[t] = 1}})
        local plot = Farm.newPlot(1, 1)
        Farm.till(plot)
        assert(Farm.plant(plot, data, t))
        Farm.advance(plot, Farm.growthTime(false))
        assert(Farm.harvest(plot, data), t .. ' harvested')
        assert(Farm.sell(data, t))
        assert(Farm.buySeed(data, t))
        eq(data.seeds[t], 1, t .. ' seed back')
        assert(data.coins > 0, t .. ': more coins than before the plant (' .. data.coins .. ')')
    end
end)

test('shop: the stall is its own tile on the field, clear of plots, villager, start and HUD, and walkable around', function()
    local farm = toFarm()
    assert(FARM_SHOP.row >= FARM_FIELD_TOP and FARM_SHOP.row <= FARM_FIELD_BOTTOM, 'inside the field rows (not the HUD bars)')
    assert(FARM_SHOP.col >= 1 and FARM_SHOP.col <= FARM_COLS)
    eq(farm:plotAt(FARM_SHOP.col, FARM_SHOP.row), nil, 'not a plot')
    eq(farm:isVillagerAt(FARM_SHOP.col, FARM_SHOP.row), false, 'not the villager')
    assert(not (FARM_SHOP.col == FARM_PLAYER_START.col and FARM_SHOP.row == FARM_PLAYER_START.row), 'not the start tile')
    eq(farm:targetAt(FARM_SHOP.col, FARM_SHOP.row).kind, 'shop')
    eq(farm:isWalkable(FARM_SHOP.col, FARM_SHOP.row), false, 'the stall blocks movement')
    for _, d in ipairs({{-1, 0}, {1, 0}, {0, -1}, {0, 1}}) do
        local c, r = FARM_SHOP.col + d[1], FARM_SHOP.row + d[2]
        eq(farm:isWalkable(c, r), true, string.format('neighbour (%d,%d) walkable', c, r))
    end
    -- the starting hint is the till prompt for the plot above the start
    eq(farm:hintText(), '[E] till the soil (shovel)')
    mock.reset(); love.draw()
    local priced = false
    for _, c in ipairs(mock.calls) do
        if c.name == 'printf' and c.args[1] == SEED_PRICES.beanstalk .. 'c' then priced = true end
    end
    assert(priced, 'stall price drawn')
end)

test('shop: buying by keyboard (face + E) with feedback, and a denial without coins', function()
    local farm = toFarm()
    farm.player.col, farm.player.row, farm.player.facing = FARM_SHOP.col - 1, FARM_SHOP.row, 'right'
    eq(farm:facingTarget().kind, 'shop')
    eq(farm:hintText(), 'beanstalk seed costs 2c (have 0c)', 'hint: type and price, not affordable')
    press('e')
    eq(farm.gameData.coins, 0); eq(farm.gameData.seeds.beanstalk, STARTING_SEEDS.beanstalk, 'nothing bought')
    eq(farm.popups[#farm.popups].text, 'need 2c', 'denial message')
    farm.gameData.coins = 10
    press('2')
    eq(farm:hintText(), '[E] buy pumpkin seed (4c)', 'hint follows the selected seed')
    press('e')
    eq(farm.gameData.coins, 10 - SEED_PRICES.pumpkin)
    eq(farm.gameData.seeds.pumpkin, STARTING_SEEDS.pumpkin + 1)
    eq(farm.popups[#farm.popups].text, '+1 pumpkin -4c', 'purchase feedback')
    eq(farm:interact(farm:facingTarget()), 'buy')
    eq(farm:interact(farm:facingTarget()), 'no-coins', '2 coins left < 4')
    eq(farm.gameData.coins, 2)
end)

test('shop: buying by mouse (hover shows the hint, click buys), and then planting the bought seed', function()
    local farm = toFarm()
    farm.gameData.coins = 3
    for _, t in ipairs(SEED_TYPES) do farm.gameData.seeds[t] = 0 end
    local sx, sy = FarmTileToPixel(FARM_SHOP.col, FARM_SHOP.row)
    mock.mouseAt(sx + 10, sy + 10); step()
    eq(farm.hover.col, FARM_SHOP.col); eq(farm.hover.row, FARM_SHOP.row)
    eq(farm:hintText(), '[E] buy beanstalk seed (2c)', 'hover shows the stall hint')
    mock.reset(); love.draw()
    local found = false
    for _, c in ipairs(mock.calls) do
        if c.name == 'rectangle' and c.args[1] == 'line' and c.args[2] == sx + 3.5 and c.args[3] == sy + 3.5 then found = true end
    end
    assert(found, 'hover highlight on the stall')
    mock.click(1); step()
    eq(farm.gameData.coins, 1); eq(farm.gameData.seeds.beanstalk, 1, 'bought by click')
    mock.click(1); step()
    eq(farm.gameData.coins, 1, 'second click refused'); eq(farm.gameData.seeds.beanstalk, 1)
    -- the bought seed plants like any other (the farmer starts facing a plot)
    mock.mouseAt(-50, -50); step()
    press('e'); press('e')                        -- till, plant
    eq(farm.gameData.seeds.beanstalk, 0)
    eq(farm:plotAt(FARM_PLAYER_START.col, FARM_PLAYER_START.row - 1).seedType, 'beanstalk')
end)

test('shop: buying after the first sale does not touch the idle break timer; over-sell still breaks', function()
    local farm = farmAtVillager({crops = {beanstalk = 1}})
    press('e')                                    -- first sale: 3 coins
    eq(farm.gameData.hasSold, true)
    run(10)
    local idle, nag = farm.idleTimer, farm.nagTimer
    -- turn to the stall and buy
    farm.player.col, farm.player.row, farm.player.facing = FARM_SHOP.col - 1, FARM_SHOP.row, 'right'
    eq(farm:interact(farm:facingTarget()), 'buy')
    eq(farm.idleTimer, idle, 'idle timer untouched by buying'); eq(farm.nagTimer, nag, 'nag timer untouched')
    eq(farm.breaking, false, 'buying never starts the break')
    run(FARM_IDLE_BREAK_TIME - 10 - 1)
    eq(farm.breaking, false)
    run(1.5)
    eq(farm.breaking, true, 'idle break fires on the original schedule from the last sale')
    eq(farm.breakReason, 'idle')
    eq(farm:interact({kind = 'shop', col = FARM_SHOP.col, row = FARM_SHOP.row}), nil, 'stall disabled during the break')

    local farm2 = farmAtVillager({crops = {beanstalk = 1}})
    press('e')                                    -- sale
    farm2.player.col, farm2.player.row, farm2.player.facing = FARM_SHOP.col - 1, FARM_SHOP.row, 'right'
    eq(farm2:interact(farm2:facingTarget()), 'buy')
    farm2.player.col, farm2.player.row, farm2.player.facing = FARM_VILLAGER.col - 1, FARM_VILLAGER.row, 'right'
    press('e')                                    -- zero crops after a sale: over-sell
    eq(farm2.breaking, true); eq(farm2.breakReason, 'oversell')
end)

test('shop: carry-over after buying is still seeds only, with the Room 1 top-up', function()
    local farm = farmAtVillager({crops = {pumpkin = 1}, seeds = {beanstalk = 0, pumpkin = 0, vine = 0}})
    press('e')                                    -- 5 coins
    farm.player.col, farm.player.row, farm.player.facing = FARM_SHOP.col - 1, FARM_SHOP.row, 'right'
    farm:selectSeed('vine')
    eq(farm:interact(farm:facingTarget()), 'buy')         -- 2 coins left
    eq(farm.gameData.coins, 2)
    farm:startBreak('oversell')
    run(FARM_BREAK_GLITCH_TIME + FARM_BREAK_FALL_TIME + 0.2)
    local back = gStateMachine.current
    eq(back.usesPush, false, 'in the backrooms')
    eq(FormatSeeds(back.gameData.seeds), 'beanstalk=1 pumpkin=0 vine=1', 'bought vine kept; beanstalk topped up')
    eq(back.gameData.coins, 0, 'coins dropped'); eq(Farm.totalCrops(back.gameData), 0, 'crops dropped')
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
    loadGame({'--debug'})
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
        plots = {{id = 'a', pos = {0, -1.5, 0}}, {id = 'b', pos = {0, 1.5, 0}}, {id = 'high', pos = {4, 0, 2.6}}},
    })
    eq(room:nearestPlot(0, -1.5, 0).id, 'a')
    eq(room:nearestPlot(0.5, 1.1, 0).id, 'b')
    eq(room:nearestPlot(0, -0.1, 0).id, 'a', 'nearest of two in range')
    eq(room:nearestPlot(0, 0.1, 0).id, 'b', 'nearest of two in range')
    eq(room:nearestPlot(-(BACKROOMS_PLANT_RANGE - 0.01), -1.5, 0).id, 'a', 'just inside the range')
    eq(room:nearestPlot(-(BACKROOMS_PLANT_RANGE + 0.01), -1.5, 0), nil, 'just outside the range')
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
    eq(Hotbar.last.selected, 'pumpkin', 'hotbar marks the selected type')
    eq(table.concat(Hotbar.last.counts, ','), '0,2,2', 'hotbar shows every type with its count')
    assert(texts:find('E / click: plant pumpkin', 1, true), 'planting prompt near a plot')
    press('e')
    eq(FormatSeeds(back.gameData.seeds), 'beanstalk=0 pumpkin=1 vine=2', 'one pumpkin consumed')
    local crop = back.room:plotById('pit').crop
    assert(crop and crop.type == 'pumpkin' and not crop.grown, 'pumpkin growing on the pit plot')
    eq(#back.timers, 1, 'growth runs on the state timer group')
    mock.reset(); love.draw()
    eq(table.concat(Hotbar.last.counts, ','), '0,1,2', 'HUD count updated')
    assert(find(mock.printed, '[backrooms] planted pumpkin on plot pit'), 'planting logged')
    -- growth is driven once per frame (the state group is not also the default group)
    run(CROP_DEFS.pumpkin.growTime * 0.75)
    eq(crop.grown, false, 'not grown early')
    run(CROP_DEFS.pumpkin.growTime * 0.25 + 0.1)
    eq(crop.grown, true); eq(crop.active, true)
end)

-- pit reach (polish M3) --------------------------------------------------------
test('pit reach: per-plot reach is used, defaults to the global range, and the nearest plot still wins', function()
    loadGame()
    local room = Room({
        id = 'reach', spawn = {0, 0, 0}, allotment = {},
        boxes = Room.shellBoxes(20, 10, 6),
        exit = {pos = {0, 0, -50}, size = {1, 1, 1}},
        plots = {{id = 'far', pos = {-3, 0, -1}, reach = 3.8}, {id = 'near', pos = {1, 0, 0}},
            {id = 'high', pos = {-3, 0, 2.6}, reach = 3.8}},
    })
    eq(room:plotById('near').reach, BACKROOMS_PLANT_RANGE, 'default reach')
    eq(room:plotById('far').reach, 3.8)
    eq(room:nearestPlot(-6.7, 0, 0).id, 'far', 'inside the long reach')
    eq(room:nearestPlot(-6.9, 0, 0), nil, 'outside the long reach')
    eq(room:nearestPlot(2.7, 0, 0).id, 'near', 'default reach unchanged')
    eq(room:nearestPlot(2.9, 0, 0), nil, 'default reach unchanged (outside)')
    eq(room:nearestPlot(0.1, 0, 0).id, 'near', 'both in reach: the nearer plot wins')
    eq(room:nearestPlot(-0.9, 0, 0).id, 'far', 'both in reach: the nearer plot wins')
    eq(room:nearestPlot(-3, 0, 0).id, 'far', 'the high plot (3.6 m above) is out of height reach')
    local ok, err = Room.validate({id = 'bad', spawn = {0, 0, 0}, allotment = {}, boxes = Room.shellBoxes(4, 4, 3),
        exit = {pos = {0, 0, -50}, size = {1, 1, 1}}, plots = {{pos = {0, 0, 0}, reach = -1}}})
    eq(ok, false); assert(err:find('reach'), err)
end)

test('pit reach: a pumpkin is planted from the spawn-side floor 1.0 m and 2.0 m back from the rim (rooms 2 and 3)', function()
    -- geometric pit rims on the spawn side (src/rooms.lua): room 2 x = -4, room 3 x = -6
    for _, case in ipairs({{room = 2, rim = -4}, {room = 3, rim = -6}}) do
        for _, back in ipairs({1.0, 2.0}) do
            local r = toRoom(case.room)
            local x = case.rim - back
            r.player:setPosition(x, 0, 0); run(0.3)
            local where = string.format('room %d, %.1f m back (x=%.2f)', case.room, back, x)
            near(r.player.z, 0, 0.01, where .. ': standing on the floor')
            local plot = r:targetPlot()
            eq(plot and plot.id, 'pit', where .. ': pit is the target')
            press('2')
            mock.reset(); love.draw()
            assert(table.concat(printedTexts(), '\n'):find('E / click: plant pumpkin', 1, true), where .. ': prompt shown')
            local before = r.gameData.seeds.pumpkin
            press('e')
            eq(r.gameData.seeds.pumpkin, before - 1, where .. ': one pumpkin used')
            local crop = r.room:plotById('pit').crop
            assert(crop and crop.type == 'pumpkin', where .. ': pumpkin growing in the pit')
            run(CROP_DEFS.pumpkin.growTime + 0.2)
            assert(crop.grown and crop.active, where .. ': pumpkin grown and solid')
            near(r.player.z, 0, 0.01, where .. ': never fell')
        end
    end
end)

test('pit reach: walking from the room 2 spawn, the plant prompt appears well before the rim', function()
    local r = toRoom(2)
    local p = r.player
    holdUntil('w', function() local t = r:targetPlot(); return t and t.id == 'pit' end, 3)
    assert(r:targetPlot() and r:targetPlot().id == 'pit', 'pit targeted while walking')
    assert(p.x < -5.9, string.format('pit targeted at least 1.9 m back from the rim (x=%.2f)', p.x))
    near(p.z, 0, 0.01, 'on the floor')
end)

test('pit reach: room 3 neighbours still resolve (foot at the ledge, lip on the ledge, pit from the start floor)', function()
    local r = toRoom(3)
    local function at(x, z)
        r.player:setPosition(x, 0, z); run(0.2)
        local t = r:targetPlot()
        return t and t.id or 'none'
    end
    eq(at(-8, 0), 'pit', 'from the spawn')
    eq(at(-1.35, 0), 'foot', 'at the ledge face')
    eq(at(-2.6, 0), 'foot', 'middle of floor B')
    eq(at(1.0, 2.6), 'lip', 'on the ledge')
    eq(at(-0.5, 2.6), 'lip', 'ledge back edge: lip, not the pit 3.6 m below')
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

-- backrooms HUD (polish M4, backrooms) ---------------------------------------------
local function hudSeedLabels(back)
    -- the hotbar always shows every type; usable ones are full brightness
    mock.reset(); love.draw()
    local labels = {}
    for i, t in ipairs(SEED_TYPES) do
        if Hotbar.last.usable[i] then
            labels[#labels + 1] = (t == Hotbar.last.selected and '[' or ' ') .. i .. ' ' .. t .. ' x' .. Hotbar.last.counts[i] .. (t == Hotbar.last.selected and ']' or '')
        end
    end
    return table.concat(labels, '|')
end

local function hudHasCoins()
    for _, c in ipairs(mock.calls) do
        local t = (c.name == 'print' or c.name == 'printf') and c.args[1]
        if type(t) == 'string' and (t:find('coin', 1, true) or t:find('%d+c$') or t:find('%d+c ')) then return t end
    end
    return nil
end

test('hud: visible seed types follow the room allotment (room 1 beanstalk; room 2 pumpkin, vine; room 3 all)', function()
    local back = toBackrooms({beanstalk = 3, pumpkin = 5, vine = 4})
    eq(table.concat(back:visibleSeedTypes(), ','), 'beanstalk')
    eq(hudSeedLabels(back), '[1 beanstalk x3]', 'room 1 HUD: beanstalk only, despite carried pumpkins and vines')
    eq(hudHasCoins(), nil, 'no coins in the backrooms HUD')
    eq(FormatSeeds(back.gameData.seeds), 'beanstalk=3 pumpkin=5 vine=4', 'hidden counts still tracked')
    back:advance()
    eq(table.concat(back:visibleSeedTypes(), ','), 'pumpkin,vine')
    eq(hudSeedLabels(back), '[2 pumpkin x2]| 3 vine x2', 'room 2 HUD: pumpkin and vine (shown as corn), no beanstalk')
    eq(hudHasCoins(), nil)
    back:advance()
    eq(table.concat(back:visibleSeedTypes(), ','), 'beanstalk,pumpkin,vine')
    eq(hudSeedLabels(back), ' 1 beanstalk x2|[2 pumpkin x2]| 3 vine x2', 'room 3 HUD: all three')
    eq(hudHasCoins(), nil)
end)

test('hud: keys for hidden types do nothing; Q / Tab visit visible types only', function()
    local back = toBackrooms({beanstalk = 3, pumpkin = 5, vine = 4})
    eq(back.selectedSeed, 'beanstalk')
    press('2'); eq(back.selectedSeed, 'beanstalk', 'room 1: pumpkin key does nothing')
    press('3'); eq(back.selectedSeed, 'beanstalk', 'room 1: vine key does nothing')
    press('q'); eq(back.selectedSeed, 'beanstalk', 'room 1: Q stays on the only visible type')
    press('tab'); eq(back.selectedSeed, 'beanstalk', 'room 1: Tab too')
    back:advance()
    eq(back.selectedSeed, 'pumpkin', 'room 2 starts on a visible type')
    press('1'); eq(back.selectedSeed, 'pumpkin', 'room 2: beanstalk key does nothing')
    local seen = {}
    for _ = 1, 4 do press('q'); seen[#seen + 1] = back.selectedSeed end
    eq(table.concat(seen, ','), 'vine,pumpkin,vine,pumpkin', 'room 2: Q cycles pumpkin <-> vine')
    press('tab'); eq(back.selectedSeed, 'vine')
    back:advance()
    seen = {}
    for _ = 1, 3 do press('tab'); seen[#seen + 1] = back.selectedSeed end
    eq(table.concat(seen, ','), 'beanstalk,pumpkin,vine', 'room 3: Tab visits all three')
    press('1'); eq(back.selectedSeed, 'beanstalk')
end)

test('hud: resets and carry-over are unchanged by hiding (room 1 extras kept, reset restores them)', function()
    local back = toBackrooms({beanstalk = 0, pumpkin = 3, vine = 2})
    eq(FormatSeeds(back.gameData.seeds), 'beanstalk=1 pumpkin=3 vine=2', 'room 1 top-up; extras kept but hidden')
    back.player:setPosition(0.4, 0, 0); run(0.2)
    press('e')
    eq(FormatSeeds(back.gameData.seeds), 'beanstalk=0 pumpkin=3 vine=2')
    press('r')
    eq(FormatSeeds(back.gameData.seeds), 'beanstalk=1 pumpkin=3 vine=2', 'room 1 reset restores the recorded seeds')
    eq(hudSeedLabels(back), '[1 beanstalk x1]')
    back:advance()
    eq(FormatSeeds(back.gameData.seeds), 'beanstalk=0 pumpkin=2 vine=2', 'room 2: fixed allotment')
    back.player:setPosition(-5, 0, 0); run(0.2); press('e')
    press('r')
    eq(FormatSeeds(back.gameData.seeds), 'beanstalk=0 pumpkin=2 vine=2', 'room 2 reset restores its allotment')
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
    eq(back.selectedSeed, 'vine', 'beanstalk is hidden in room 2: its key does nothing')
    back.gameData.seeds.vine = 0
    press('2'); press('3')
    eq(back.selectedSeed, 'vine', 'a visible type can be selected even with none held')
    back.player:setPosition(0.8, 0, 0); run(0.2)
    eq(back:targetPlot().id, 'edge')
    press('e')
    eq(back.gameData.seeds.vine, 0); eq(back.room:plotById('edge').crop, nil, 'no vine seeds: nothing planted')
    eq(back.message.text, 'No corn seeds left')
end)

test('planting: 1-3 select, Q / Tab cycle through held types, a click plants', function()
    local back = toRoom(3)
    eq(FormatSeeds(back.gameData.seeds), 'beanstalk=2 pumpkin=2 vine=2')
    -- room 2 auto-selected pumpkin (no beanstalks there); a held selection is kept
    eq(back.selectedSeed, 'pumpkin', 'selection carried from room 2')
    press('1'); eq(back.selectedSeed, 'beanstalk')
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

-- farm game feel: display names and plot care (section 1) ------------------------
test('names: vine reads as corn in every farm hint, popup, villager line and shop hint', function()
    loadGame()
    gStateMachine:change('farm', NewGameData({seeds = {vine = 2}, coins = 20}))
    local farm = gStateMachine.current
    local seen = {}
    local function note() seen[#seen + 1] = farm:hintText()
        for _, p in ipairs(farm.popups) do seen[#seen + 1] = p.text end
        if farm.villagerLine then seen[#seen + 1] = farm.villagerLine.text end
    end
    farm:selectSeed('vine')
    note(); press('e'); note(); press('e'); note(); press('e'); note()   -- till, plant, water
    run(Farm.growthTime(true) + 0.1); note()
    press('e'); note()                                                    -- harvest
    farm.player.col, farm.player.row, farm.player.facing = FARM_VILLAGER.col - 1, FARM_VILLAGER.row, 'right'
    note(); farm.gameData.crops.vine = 2; note(); press('e'); note()      -- sell (one left: 'Thanks! A corn!')
    farm.player.col, farm.player.row, farm.player.facing = FARM_SHOP.col - 1, FARM_SHOP.row, 'right'
    note(); press('e'); note()                                            -- buy
    farm.gameData.coins = 0; note()
    -- HUD and stall draws
    mock.reset(); love.draw()
    for _, c in ipairs(mock.calls) do
        if (c.name == 'print' or c.name == 'printf') and type(c.args[1]) == 'string' then seen[#seen + 1] = c.args[1] end
    end
    local all = table.concat(seen, ' | ')
    assert(not all:find('vine', 1, true), 'no player-visible "vine": ' .. all)
    assert(all:find('plant corn', 1, true) and all:find('harvest corn', 1, true) and all:find('sell corn', 1, true)
        and all:find('buy corn seed', 1, true) and all:find('Thanks! A corn!', 1, true)
        and all:find('+1 corn', 1, true) and all:find('-1 corn', 1, true), 'corn named everywhere: ' .. all)
    -- internal keys are untouched
    eq(farm.selectedSeed, 'vine'); eq(farm.gameData.seeds.vine ~= nil, true)
    eq(SeedName('vine'), 'corn'); eq(SeedName('pumpkin'), 'pumpkin'); eq(SeedName('beanstalk'), 'beanstalk')
    eq(table.concat(SEED_TYPES, ','), 'beanstalk,pumpkin,vine', 'keys unchanged')
    eq(BACKROOMS_ROOMS[2].allotment.vine, 2, 'allotments keyed by vine')
    eq(FormatSeeds(CarryOverGameData(farm.gameData).seeds):find('vine=', 1, true) ~= nil, true, 'carry-over keyed by vine')
end)

test('names: backrooms prompts and messages say corn, never vine', function()
    local back = toRoom(2)
    back.player:setPosition(0.8, 0, 0); run(0.2)
    press('3')
    mock.reset(); love.draw()
    local texts = table.concat(printedTexts(), '\n')
    assert(texts:find('E / click: plant corn', 1, true), 'prompt: ' .. texts)
    press('e')
    eq(back.message.text, 'Planted a corn')
    mock.reset(); love.draw()
    texts = table.concat(printedTexts(), '\n')
    assert(not texts:find('vine', 1, true), 'no "vine" on the backrooms HUD: ' .. texts)
end)

test('plot care: watered crops mature in 12 s, unwatered in 24 s, never blocked', function()
    loadGame()
    eq(Farm.growthTime(true), 12); eq(Farm.growthTime(false), 24)
    for _, watered in ipairs({true, false}) do
        local d = NewGameData()
        local plot = Farm.newPlot(1, 1)
        Farm.till(plot); Farm.plant(plot, d, 'beanstalk')
        if watered then Farm.water(plot) end
        local t, stages = 0, {}
        while plot.state ~= PLOT_MATURE and t < 60 do
            local s = Farm.advance(plot, 1 / 60); t = t + 1 / 60
            if s then stages[#stages + 1] = s end
        end
        local want = watered and 12 or 24
        assert(math.abs(t - want) < 0.05, (watered and 'watered' or 'unwatered') .. ' matured at ' .. t)
        eq(table.concat(stages, ','), '2,3,4,5', 'each stage reported once')
        eq(Farm.advance(plot, 10), nil, 'mature plots no longer advance')
    end
end)

test('plot care: watering mid-growth keeps progress and grows the rest at full rate', function()
    loadGame()
    local d = NewGameData()
    local plot = Farm.newPlot(1, 1)
    Farm.till(plot); Farm.plant(plot, d, 'pumpkin')
    for _ = 1, 8 * 60 do Farm.advance(plot, 1 / 60) end          -- 8 s unwatered = 4 s of growth
    assert(math.abs(plot.progress - 4) < 1e-6, 'progress ' .. plot.progress); eq(plot.stage, 2)
    Farm.water(plot)
    eq(plot.stage, 2, 'watering keeps the stage'); assert(math.abs(plot.progress - 4) < 1e-6, 'and the progress')
    local t = 0
    while plot.state ~= PLOT_MATURE do Farm.advance(plot, 1 / 60); t = t + 1 / 60 end
    assert(math.abs(t - 8) < 0.05, 'remaining 8 s at full rate, took ' .. t)
    -- water is lost on harvest; the replanted crop starts unwatered on tilled soil
    Farm.harvest(plot, d)
    eq(plot.tilled, true); eq(plot.watered, false)
    Farm.plant(plot, d, 'pumpkin')
    eq(plot.watered, false); eq(Farm.growthRate(plot), FARM_UNWATERED_RATE)
end)

test('plot care: the hint, the action and the result agree for every plot state', function()
    local farm = toFarm()
    local plot = farm:facingTarget().plot
    local cases = {
        {'till', '[E] till the soil (shovel)', function() end},
        {'plant', '[E] plant beanstalk (seed bag)', function() plot.tilled = true end},
        {'water', '[E] water beanstalk (watering can)', function() Farm.plant(plot, farm.gameData, 'beanstalk') end},
        {'growing', 'beanstalk growing...', function() Farm.water(plot) end},
        {'harvest', '[E] harvest beanstalk (sickle)', function() Farm.advance(plot, 100) end},
    }
    for _, c in ipairs(cases) do
        c[3]()
        eq(farm:plotAction(plot), c[1], 'plotAction')
        eq(farm:hintText(), c[2], c[1] .. ' hint')
    end
    -- every action performed through interact matches what plotAction said
    local farm2 = toFarm()
    local p2 = farm2:facingTarget().plot
    for _, want in ipairs({'till', 'plant', 'water', 'growing'}) do
        eq(farm2:plotAction(p2), want); eq(farm2:interact(farm2:facingTarget()), want)
    end
    Farm.advance(p2, 100)
    eq(farm2:plotAction(p2), 'harvest'); eq(farm2:interact(farm2:facingTarget()), 'harvest')
    eq(farm2:plotAction(p2), 'plant', 'harvested plot is still tilled')
    -- no seeds on a tilled plot
    for _, t in ipairs(SEED_TYPES) do farm2.gameData.seeds[t] = 0 end
    eq(farm2:plotAction(p2), 'no-seeds'); eq(farm2:hintText(), 'no seeds left')
    eq(farm2:interact(farm2:facingTarget()), 'no-seeds')
end)

test('plot care: tilling and watering after a sale keep the idle countdown; the break freezes growth', function()
    local farm = farmAtVillager({crops = {beanstalk = 1}})
    press('e'); eq(farm.gameData.hasSold, true)
    run(10)
    local idle, nag = farm.idleTimer, farm.nagTimer
    local a = farm:plotAt(FARM_PLOTS.col, FARM_PLOTS.row)
    local b = farm:plotAt(FARM_PLOTS.col + 1, FARM_PLOTS.row)
    eq(farm:interact({kind = 'plot', plot = a, col = a.col, row = a.row}), 'till')
    eq(farm:interact({kind = 'plot', plot = a, col = a.col, row = a.row}), 'plant')
    eq(farm:interact({kind = 'plot', plot = a, col = a.col, row = a.row}), 'water')
    eq(farm:interact({kind = 'plot', plot = b, col = b.col, row = b.row}), 'till')
    eq(farm.idleTimer, idle, 'idle countdown untouched'); eq(farm.nagTimer, nag)
    eq(farm.breaking, false, 'care never starts the break')
    run(FARM_IDLE_BREAK_TIME - 10 - 0.5)
    eq(farm.breaking, false)
    run(1)
    eq(farm.breaking, true, 'idle break on the schedule from the last sale'); eq(farm.breakReason, 'idle')
    local progress, stage = a.progress, a.stage
    run(1)
    eq(a.progress, progress, 'growth frozen during the break'); eq(a.stage, stage)
    eq(farm:interact({kind = 'plot', plot = b, col = b.col, row = b.row}), nil, 'no care during the break')
    eq(b.state, PLOT_EMPTY)
end)

-- farm game feel: effects and sound (section 2) -----------------------------------
test('fx: bursts clean up after their lifetime and the particle cap holds', function()
    loadGame()
    local fx = Fx.new()
    for kind in pairs(FX_BURSTS) do assert(fx:burst(kind, 100, 100) > 0, kind .. ' emits') end
    fx:pop('a'); fx:squash('b'); fx:popup('hi', 10, 10)
    local landed = false
    fx:fly(gTextures['produce-pumpkin'], 0, 0, 50, 10, function() landed = true end)
    assert(fx:count() > 10, 'effects live')
    for _ = 1, 60 * 3 do fx:update(1 / 60) end
    eq(fx:count(), 0, 'nothing left after 3 s'); eq(landed, true, 'flyer landed and called back')
    -- spam: the cap is never exceeded
    for _ = 1, 200 do fx:burst('harvest', 50, 50) end
    eq(#fx.particles, FX_MAX_PARTICLES, 'capped at FX_MAX_PARTICLES')
    eq(fx:burst('harvest', 50, 50), 0, 'no new particles at the cap')
    -- bursts do not consume the global random sequence
    math.randomseed(42); local a = math.random()
    math.randomseed(42); fx:burst('till', 1, 1); local b = math.random()
    eq(a, b, 'global RNG untouched')
end)

test('fx: the coin ticker converges for gains and spending within about a second', function()
    loadGame()
    for _, case in ipairs({{0, 5}, {5, 1}, {0, 120}, {120, 116}}) do
        local v, t = case[1], 0
        local monotonic = true
        while v ~= case[2] and t < 3 do
            local nv = Fx.tickToward(v, case[2], 1 / 60)
            if (case[2] > case[1] and nv < v) or (case[2] < case[1] and nv > v) then monotonic = false end
            v = nv; t = t + 1 / 60
        end
        eq(v, case[2], 'reached ' .. case[2]); eq(monotonic, true, 'moves one way')
        assert(t <= 1.05, case[1] .. ' -> ' .. case[2] .. ' took ' .. t .. ' s')
        assert(t > 0.1, 'ticks rather than jumping (' .. t .. ' s)')
    end
end)

test('fx: squash and pop tweens start, then rest at scale 1', function()
    loadGame()
    local fx = Fx.new()
    fx:squash('k')
    local sx, sy = fx:squashScale('k')
    assert(math.abs(sx - 1.25) < 1e-9 and math.abs(sy - 0.75) < 1e-9, 'starts 1.25 x 0.75')
    fx:pop('p'); fx:update(FX_POP_TIME / 2)
    assert(fx:popScale('p') > 1.1, 'pop grows')
    for _ = 1, 60 do fx:update(1 / 60) end
    sx, sy = fx:squashScale('k')
    eq(sx, 1); eq(sy, 1); eq(fx:popScale('p'), 1)
end)

test('fx: every farm action emits an effect; the break emits none', function()
    local farm = toFarm()
    farm.gameData.coins = 20
    local function particles() return #farm.juice.particles end
    local plot = farm:facingTarget().plot
    local key = plot.col .. ',' .. plot.row
    for _, want in ipairs({'till', 'plant', 'water'}) do
        local n = particles()
        eq(farm:interact(farm:facingTarget()), want)
        assert(particles() > n, want .. ' emitted a burst')
        assert(farm.juice.pops[key], want .. ' pops the plot')
    end
    Farm.advance(plot, 100)
    local n = particles()
    eq(farm:interact(farm:facingTarget()), 'harvest'); assert(particles() > n, 'harvest burst')
    eq(#farm.juice.flyers, 1, 'harvested crop flies')
    farm.player.col, farm.player.row, farm.player.facing = FARM_VILLAGER.col - 1, FARM_VILLAGER.row, 'right'
    n = particles()
    eq(farm:interact(farm:facingTarget()), 'sell'); assert(particles() > n, 'sell burst')
    farm.player.col, farm.player.row, farm.player.facing = FARM_SHOP.col - 1, FARM_SHOP.row, 'right'
    n = particles()
    eq(farm:interact(farm:facingTarget()), 'buy'); assert(particles() > n, 'buy burst')
    -- the break: action effects are dropped and nothing new is emitted
    farm:startBreak('oversell')
    eq(#farm.juice.particles, 0); eq(#farm.juice.flyers, 0)
    eq(farm:emit('harvest', 3, 5), false, 'emit refused while breaking')
    local p2 = farm:plotAt(FARM_PLOTS.col + 1, FARM_PLOTS.row)
    eq(farm:interact({kind = 'plot', plot = p2, col = p2.col, row = p2.row}), nil)
    run(0.5)
    eq(#farm.juice.particles, 0, 'no particles during the break')
end)

test('fx: no effects remain a few seconds after input stops', function()
    local farm = toFarm()
    press('e')                               -- till (nothing growing afterwards)
    for _ = 1, 30 do farm:emit('harvest', 3, 5) end
    run(3)
    eq(farm.juice:count(), 0)
    eq(farm.displayCoins, farm.gameData.coins)
end)

test('fx: a harvest counts on the same frame, flies to its slot and pulses it on landing', function()
    local farm = toFarm()
    tillPlantWater()
    run(Farm.growthTime(true) + 0.1)
    press('e')
    eq(farm.gameData.crops.beanstalk, 1, 'counted immediately')
    local f = farm.juice.flyers[1]
    assert(f and f.image == gTextures['produce-beanstalk'], 'produce icon flying')
    local tx, ty = farm:produceSlotCenter('beanstalk')
    eq(f.x1, tx); eq(f.y1, ty)
    assert(ty < FARM_TILE, 'target is in the top bar')
    eq(farm.juice.pops['slot-beanstalk'], nil, 'no pulse before landing')
    run(FX_FLY_TIME + 0.02)
    eq(#farm.juice.flyers, 0); assert(farm.juice.pops['slot-beanstalk'], 'slot pulses on landing')
end)

test('fx: selling ticks the shown coins up with sparkles; buying ticks them down', function()
    local farm = farmAtVillager({crops = {pumpkin = 1}})
    press('e')
    eq(farm.gameData.coins, CROP_VALUES.pumpkin, 'real coins updated at once')
    assert(farm.displayCoins < CROP_VALUES.pumpkin, 'shown coins still ticking')
    local cx, cy = farm:coinIconCenter()
    local near = 0
    for _, p in ipairs(farm.juice.particles) do
        if math.abs(p.x - cx) < 8 and math.abs(p.y - cy) < 8 then near = near + 1 end
    end
    assert(near >= 3, 'coin sparkles at the coin icon')
    local t = 0
    while farm.displayCoins ~= farm.gameData.coins and t < 2 do step(); t = t + 1 / 60 end
    eq(farm.displayCoins, CROP_VALUES.pumpkin); assert(t <= 1.1, 'took ' .. t)
    farm.player.col, farm.player.row, farm.player.facing = FARM_SHOP.col - 1, FARM_SHOP.row, 'right'
    farm:selectSeed('pumpkin')
    press('e')
    eq(farm.gameData.coins, CROP_VALUES.pumpkin - SEED_PRICES.pumpkin)
    local seenBetween = false
    t = 0
    while farm.displayCoins ~= farm.gameData.coins and t < 2 do
        step(); t = t + 1 / 60
        if farm.displayCoins < CROP_VALUES.pumpkin and farm.displayCoins > farm.gameData.coins then seenBetween = true end
    end
    eq(farm.displayCoins, farm.gameData.coins); eq(seenBetween, true, 'counted down')
end)

test('fx: a stage change starts a squash on that crop which returns to scale 1', function()
    local farm = toFarm()
    tillPlantWater()
    local plot = farm:facingTarget().plot
    local key = 'crop-' .. plot.col .. ',' .. plot.row
    eq(farm.juice.squashes[key], nil)
    run(FARM_STAGE_TIME + 0.02)
    eq(plot.stage, 2)
    local sx, sy = farm.juice:squashScale(key)
    assert(sx > 1.1 and sy < 0.9, 'squashing just after the stage change')
    run(FX_SQUASH_TIME + 0.05)
    sx, sy = farm.juice:squashScale(key)
    eq(sx, 1); eq(sy, 1)
    -- maturity: a sparkle burst
    run(FARM_STAGE_TIME * 3 - FX_SQUASH_TIME - 0.1)
    local n = #farm.juice.particles
    run(0.1)
    eq(plot.state, PLOT_MATURE); assert(#farm.juice.particles > n, 'maturity sparkle')
end)

test('sound: generated effects ship in sounds/, load for real and play on their actions', function()
    for _, f in ipairs({'till', 'plant', 'water', 'harvest', 'sell', 'buy', 'coin', 'deny', 'glitch'}) do
        local fh = io.open('sounds/' .. f .. '.wav', 'rb'); assert(fh, f .. '.wav exists'); fh:close()
    end
    local farm = toFarm()
    for _, key in ipairs({'till', 'water', 'coin', 'buy', 'plant', 'harvest', 'sell', 'deny', 'glitch'}) do
        assert(not Assets.isPlaceholder(gSounds[key]), key .. ' loaded from file')
        eq(gSounds[key].volume, FARM_SFX_VOLUME, key .. ' volume')
    end
    for _, m in ipairs(Assets.missing) do
        assert(not (m.kind == 'sound' and m.path:match('%.wav$')), 'no placeholder for ' .. m.path)
    end
    local function lastPlay() return mock.soundPlays[#mock.soundPlays] end
    press('e'); eq(lastPlay(), 'sounds/till.wav')
    press('e'); eq(lastPlay(), 'sounds/plant.wav')
    press('e'); eq(lastPlay(), 'sounds/water.wav')
    farm.player.col, farm.player.row, farm.player.facing = FARM_SHOP.col - 1, FARM_SHOP.row, 'right'
    press('e'); eq(lastPlay(), 'sounds/deny.wav', 'quiet denial at the stall without coins')
    farm.gameData.coins = 10
    mock.soundPlays = {}
    press('e'); eq(mock.soundPlays[1], 'sounds/buy.wav')
    mock.soundPlays = {}
    run(1)
    local ticks = 0
    for _, p in ipairs(mock.soundPlays) do if p == 'sounds/coin.wav' then ticks = ticks + 1 end end
    assert(ticks >= 1, 'coin ticks while the counter moves (' .. ticks .. ')')
end)

test('sound: a missing sound file still runs the actions silently', function()
    local farm = toFarm({'.', '--placeholder-assets'})
    for _, key in ipairs({'till', 'water', 'coin', 'buy'}) do assert(gSounds[key].isPlaceholder, key .. ' stub') end
    tillPlantWater()
    eq(farm:facingTarget().plot.watered, true, 'actions work without sound')
end)

-- farm game feel: characters and HUD (section 3) -----------------------------------
-- The colour set right before `texture` was drawn in the last love.draw().
-- (`last`: the last draw of it instead of the first, e.g. the HUD's.)
local function colorBeforeDraw(texture, last)
    local color, found
    for _, c in ipairs(mock.calls) do
        if c.name == 'setColor' then color = c.args end
        if c.name == 'draw' and c.args[1] == texture then
            found = type(color[1]) == 'table' and color[1] or color
            if not last then return found end
        end
    end
    return found
end

test('characters: the villager has its own sprite file, drawn untinted; the farmer is the hero', function()
    local farm = toFarm()
    eq(gTextures['villager'].source, 'graphics/characters/villager.png')
    assert(gTextures['villager'].source ~= gTextures['hero'].source, 'different files')
    local a = assert(io.open(gTextures['villager'].source, 'rb')):read('*a')
    local b = assert(io.open(gTextures['hero'].source, 'rb')):read('*a')
    assert(a ~= b, 'villager pixels differ from the hero')
    mock.reset(); love.draw()
    local c = colorBeforeDraw(gTextures['villager'])
    eq(c[1], 1); eq(c[2], 1); eq(c[3], 1, 'no draw-time tint')
    assert(colorBeforeDraw(gTextures['hero']), 'farmer drawn with the hero sprite')
end)

test('characters: the tool beside the farmer follows the faced plot (shovel, seed bag, can, sickle, none)', function()
    local farm = toFarm()
    local plot = farm:facingTarget().plot
    local function drawnTool()
        mock.reset(); love.draw()
        for _, key in ipairs({'tool-shovel', 'tool-can', 'tool-sickle', 'seedbag-beanstalk', 'seedbag-pumpkin'}) do
            -- the HUD also draws seed bags: count draws of each texture
            local n = 0
            for _, c in ipairs(mock.calls) do if c.name == 'draw' and c.args[1] == gTextures[key] then n = n + 1 end end
            local hud = key:match('^seedbag') and 2 or 0     -- HUD slot + stall counter (selected only)
            if key:match('^seedbag') and key ~= 'seedbag-' .. farm.selectedSeed then hud = 1 end
            if n > hud then return key end
        end
        return nil
    end
    eq(farm:toolIcon(), 'tool-shovel'); eq(drawnTool(), 'tool-shovel')
    press('e')
    eq(farm:toolIcon(), 'seedbag-beanstalk'); eq(drawnTool(), 'seedbag-beanstalk')
    press('2')
    eq(farm:toolIcon(), 'seedbag-pumpkin', 'the selected seed bag')
    press('e')
    eq(farm:toolIcon(), 'tool-can'); eq(drawnTool(), 'tool-can')
    press('e')
    eq(farm:toolIcon(), nil, 'watered and growing: nothing to use'); eq(drawnTool(), nil)
    Farm.advance(plot, 100)
    eq(farm:toolIcon(), 'tool-sickle'); eq(drawnTool(), 'tool-sickle')
    press('down')
    eq(farm:facingTarget(), nil); eq(farm:toolIcon(), nil, 'facing grass'); eq(drawnTool(), nil)
    farm.player.col, farm.player.row, farm.player.facing = FARM_VILLAGER.col - 1, FARM_VILLAGER.row, 'right'
    eq(farm:toolIcon(), nil, 'facing the villager')
end)

test('characters: the villager bounces briefly on a sale and keeps talking', function()
    local farm = farmAtVillager({crops = {pumpkin = 2}})
    eq(farm:villagerHop(), 0)
    press('e')
    run(FX_POP_TIME / 2)
    assert(farm:villagerHop() < -2, 'hopping up (' .. farm:villagerHop() .. ')')
    eq(farm.villagerLine.text, 'Thanks! A pumpkin!')
    run(FX_POP_TIME)
    eq(farm:villagerHop(), 0, 'back on the ground')
end)

test('hud: seeds | divider | produce, coin icon and day; nothing overlaps with three-digit counts', function()
    local farm = toFarm()
    for _, t in ipairs(SEED_TYPES) do farm.gameData.seeds[t] = 999; farm.gameData.crops[t] = 999 end
    farm.gameData.coins = 999; farm.displayCoins = 999; farm.dayTime = 998.5 * FARM_DAY_LENGTH
    local L = farm:hudLayout()
    local font = gFonts['small']
    -- worst case text width: the mock font or LÖVE 11.5's 8 px font (5 px per digit/char, measured)
    local function tw(text) return math.max(font:getWidth(text), 5 * #text) end
    local boxes = {}
    local function add(name, x, y, w, h) boxes[#boxes + 1] = {name = name, x = x, y = y, w = w, h = h} end
    for i, r in ipairs(L.seeds) do
        add('seed icon ' .. i, r.icon.x, r.icon.y, r.icon.size, r.icon.size)
        add('seed key ' .. i, r.key.x, r.key.y, tw(tostring(i)), 9)
        add('seed count ' .. i, r.count.x, r.count.y, tw('x999'), 9)
        assert(r.count.x + tw('x999') <= r.x + r.w, 'seed count ' .. i .. ' inside its slot')
    end
    add('divider', L.divider.x, L.divider.y, L.divider.w, L.divider.h)
    for i, r in ipairs(L.produce) do
        add('produce icon ' .. i, r.icon.x, r.icon.y, r.icon.size, r.icon.size)
        add('produce count ' .. i, r.count.x, r.count.y, tw('999'), 9)
    end
    add('coin icon', L.coinIcon.x, L.coinIcon.y, L.coinIcon.w, L.coinIcon.h)
    add('coin amount', L.coinText.x, L.coinText.y, tw('999'), 9)
    add('day', L.day.right - tw('Day 999'), L.day.y, tw('Day 999'), 9)
    for i, a in ipairs(boxes) do
        assert(a.x >= 0 and a.x + a.w <= VIRTUAL_WIDTH, a.name .. ' inside the screen width')
        assert(a.y >= 0 and a.y + a.h <= FARM_TILE - 4, a.name .. ' inside the top bar (clear of the hint bar)')
        for j = i + 1, #boxes do
            local b = boxes[j]
            local overlap = a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
            assert(not overlap, a.name .. ' overlaps ' .. b.name)
        end
    end
    -- the divider sits between the last seed slot and the first produce slot
    assert(L.divider.x >= L.seeds[3].x + L.seeds[3].w and L.divider.x + 1 <= L.produce[1].x, 'divider between groups')
    -- drawn: coin icon (circles), amount without a 'c' suffix, day number
    mock.reset(); love.draw()
    local texts = {}
    for _, c in ipairs(mock.calls) do if c.name == 'print' then texts[#texts + 1] = c.args[1] end end
    local all = table.concat(texts, '|')
    assert(all:find('|999|', 1, true) and not all:find('999c', 1, true), 'coin amount without a c suffix: ' .. all)
    assert(all:find('Day 999', 1, true), 'day number drawn')
    assert(mock.count('circle') >= 2, 'coin icon drawn')
end)

test('hud: a new farm shows day 1; empty slots dim and the selected slot stays highlighted', function()
    local farm = toFarm()
    mock.reset(); love.draw()
    local found = false
    for _, c in ipairs(mock.calls) do if c.name == 'print' and c.args[1] == 'Day 1' then found = true end end
    assert(found, 'Day 1 on a new farm')
    local bag = gTextures['seedbag-pumpkin']
    eq(colorBeforeDraw(bag, true)[4], 1, 'pumpkin seeds held: full brightness')
    farm.gameData.seeds.pumpkin = 0
    farm:selectSeed('pumpkin')
    mock.reset(); love.draw()
    eq(colorBeforeDraw(bag, true)[4], FARM_HUD.emptyAlpha, 'empty: dimmed')
    local r = farm:hudLayout().seeds[2]
    local outlined = false
    for _, c in ipairs(mock.calls) do
        if c.name == 'rectangle' and c.args[1] == 'line' and c.args[2] == r.x + 0.5 and c.args[3] == r.y + 0.5 then outlined = true end
    end
    assert(outlined, 'selected empty slot still outlined')
    farm.gameData.seeds.pumpkin = 1
    mock.reset(); love.draw()
    eq(colorBeforeDraw(bag, true)[4], 1, 'back to full brightness at 1')
    -- produce slots too
    local produce = gTextures['produce-vine']
    eq(colorBeforeDraw(produce)[4], FARM_HUD.emptyAlpha)
    farm.gameData.crops.vine = 1
    mock.reset(); love.draw()
    eq(colorBeforeDraw(produce)[4], 1)
end)

-- farm game feel: world dressing (section 4) ----------------------------------------
local function decorTiles(kind)
    if kind == 'barn' then return FARM_DECOR.barn.blocks end
    return FARM_DECOR[kind]
end

test('decor: solid dressing blocks movement (the farmer only turns); path tiles do not', function()
    local farm = toFarm()
    for _, kind in ipairs({'fence', 'well', 'bushes', 'pond', 'barn'}) do
        for _, t in ipairs(decorTiles(kind)) do
            eq(farm:isWalkable(t[1], t[2]), false, kind .. ' (' .. t[1] .. ',' .. t[2] .. ') blocks')
            -- approach from a walkable neighbour and press toward it
            for dir, d in pairs({left = {1, 0}, right = {-1, 0}, up = {0, 1}, down = {0, -1}}) do
                local c, r = t[1] + d[1], t[2] + d[2]
                if farm:isWalkable(c, r) then
                    farm.player.col, farm.player.row = c, r
                    eq(farm:tryMove(dir), false, kind .. ' entered from ' .. dir)
                    eq(farm.player.col, c); eq(farm.player.row, r); eq(farm.player.facing, dir, 'turned to face it')
                end
            end
        end
    end
    for _, t in ipairs(FARM_DECOR.path) do
        eq(farm:isWalkable(t[1], t[2]), true, 'path (' .. t[1] .. ',' .. t[2] .. ') walkable')
    end
    -- walk along the path: start (3,6) -> right x4 -> (7,6) -> up x2 -> (7,4)
    farm.player.col, farm.player.row = FARM_PLAYER_START.col, FARM_PLAYER_START.row
    for _ = 1, 4 do press('right') end
    eq(farm.player.col, 7); eq(farm.player.row, 6, 'walked onto the path')
    press('up'); press('up')
    eq(farm.player.row, 4, 'up the path'); press('right'); eq(farm:facingTarget().kind, 'villager')
end)

test('decor: nothing sits on the HUD rows, start tile, plots, villager or stall; the barn tops out behind the HUD', function()
    local farm = toFarm()
    local reserved = {[FARM_PLAYER_START.col .. ',' .. FARM_PLAYER_START.row] = 'start',
        [FARM_VILLAGER.col .. ',' .. FARM_VILLAGER.row] = 'villager', [FARM_SHOP.col .. ',' .. FARM_SHOP.row] = 'stall'}
    for _, p in ipairs(farm.plots) do reserved[p.col .. ',' .. p.row] = 'plot' end
    for _, kind in ipairs({'fence', 'path', 'well', 'bushes', 'pond', 'barn'}) do
        for _, t in ipairs(decorTiles(kind)) do
            local k = t[1] .. ',' .. t[2]
            eq(reserved[k], nil, kind .. ' on ' .. tostring(reserved[k]) .. ' at ' .. k)
            assert(t[2] >= FARM_FIELD_TOP and t[2] <= FARM_FIELD_BOTTOM, kind .. ' inside the field rows')
        end
    end
    for _, g in ipairs(farm.groundDecor) do
        assert(not reserved[g.col .. ',' .. g.row] and not farm:isBlockedDecor(g.col, g.row), 'ground variation on free grass')
    end
    -- the fence flanks the plot block left and right only
    for _, t in ipairs(FARM_DECOR.fence) do
        assert((t[1] == FARM_PLOTS.col - 1 or t[1] == FARM_PLOTS.col + FARM_PLOTS.cols)
            and t[2] >= FARM_PLOTS.row and t[2] < FARM_PLOTS.row + FARM_PLOTS.rows, 'fence beside the plots')
    end
    -- the barn is drawn bottom-aligned on its row; its top is under the HUD bar
    mock.reset(); love.draw()
    for _, c in ipairs(mock.calls) do
        if c.name == 'draw' and c.args[1] == gTextures['barn'] then
            local y = c.args[3]
            eq(y + 96, FARM_DECOR.barn.row * FARM_TILE, 'barn bottom on row ' .. FARM_DECOR.barn.row)
            assert(y < FARM_TILE, 'roof behind the HUD bar')
        end
    end
end)

test('decor: from the start, every plot, the villager and the stall have a reachable walkable neighbour', function()
    local farm = toFarm()
    local seen, queue = {}, {{FARM_PLAYER_START.col, FARM_PLAYER_START.row}}
    seen[FARM_PLAYER_START.col .. ',' .. FARM_PLAYER_START.row] = true
    while #queue > 0 do
        local c = table.remove(queue, 1)
        for _, d in ipairs({{1, 0}, {-1, 0}, {0, 1}, {0, -1}}) do
            local nc, nr = c[1] + d[1], c[2] + d[2]
            if not seen[nc .. ',' .. nr] and farm:isWalkable(nc, nr) then
                seen[nc .. ',' .. nr] = true; queue[#queue + 1] = {nc, nr}
            end
        end
    end
    local function reachable(col, row)
        for _, d in ipairs({{1, 0}, {-1, 0}, {0, 1}, {0, -1}}) do
            if seen[(col + d[1]) .. ',' .. (row + d[2])] then return true end
        end
        return false
    end
    for _, p in ipairs(farm.plots) do assert(reachable(p.col, p.row), 'plot ' .. p.col .. ',' .. p.row) end
    assert(reachable(FARM_VILLAGER.col, FARM_VILLAGER.row), 'villager')
    assert(reachable(FARM_SHOP.col, FARM_SHOP.row), 'stall')
    local n = 0; for _ in pairs(seen) do n = n + 1 end
    assert(n > 40, 'most of the field is open (' .. n .. ' tiles)')
end)

test('decor: ground variation is identical on two entries and leaves the global RNG alone', function()
    local farm = toFarm()
    local function sig(f)
        local parts = {}
        for _, g in ipairs(f.groundDecor) do parts[#parts + 1] = table.concat({g.kind, g.col, g.row, g.x, g.y}, ':') end
        return table.concat(parts, ' ')
    end
    local a = sig(farm)
    assert(#farm.groundDecor >= 10, 'some tufts and stones (' .. #farm.groundDecor .. ')')
    math.randomseed(7); local r1 = math.random()
    math.randomseed(7)
    gStateMachine:change('farm', NewGameData())
    local r2 = math.random()
    eq(r1, r2, 'entering the farm does not consume the global RNG')
    eq(sig(gStateMachine.current), a, 'same layout on the second entry')
end)

test('decor: three soil looks (untilled, tilled, watered) are drawn differently', function()
    local farm = toFarm()
    local plot = farm:facingTarget().plot
    local x, y = FarmTileToPixel(plot.col, plot.row)
    local function look()
        mock.reset(); farm:renderSoil(plot, x, y)
        local parts = {}
        for _, c in ipairs(mock.calls) do
            local a = c.args
            if c.name == 'setColor' then parts[#parts + 1] = 'c' .. table.concat({a[1], a[2], a[3]}, ',')
            elseif c.name == 'draw' then
                for k, v in pairs(gTextures) do if v == a[1] then parts[#parts + 1] = k end end
            end
        end
        return table.concat(parts, ' ')
    end
    local untilled = look()
    press('e'); local tilled = look()
    press('e'); press('e'); local watered = look()
    assert(untilled ~= tilled and tilled ~= watered and untilled ~= watered, 'three different looks')
    assert(not untilled:find('plot', 1, true) and tilled:find('plot', 1, true), 'furrows only once tilled')
    assert(watered:find('c0.7,0.82,1', 1, true), 'wet sheen when watered')
end)

test('decor: ambient sway and shimmer move with time but tile positions never change; frozen in the break', function()
    local farm = farmAtVillager({crops = {beanstalk = 1}})
    local plot = farm:plotAt(FARM_PLOTS.col, FARM_PLOTS.row)
    plot.tilled = true; Farm.plant(plot, farm.gameData, 'beanstalk')
    local function frame()
        mock.reset(); love.draw()
        local soil, skews = {}, {}
        for _, c in ipairs(mock.calls) do
            if c.name == 'draw' and c.args[1] == gTextures['soil'] then soil[#soil + 1] = c.args[2] .. ',' .. c.args[3] end
            if c.name == 'draw' and c.args[9] then skews[#skews + 1] = c.args[9] end
        end
        return table.concat(soil, ' '), table.concat(skews, ',')
    end
    local positions = {}
    for _, p in ipairs(farm.plots) do positions[#positions + 1] = p.col .. ',' .. p.row end
    local soil1, sway1 = frame()
    run(0.7)
    local soil2, sway2 = frame()
    eq(soil2, soil1, 'soil tiles drawn at the same positions')
    assert(sway1 ~= sway2, 'something sways over time')
    local after = {}
    for _, p in ipairs(farm.plots) do after[#after + 1] = p.col .. ',' .. p.row end
    eq(table.concat(after, ' '), table.concat(positions, ' '), 'plot tiles unchanged')
    eq(farm.player.col, FARM_VILLAGER.col - 1); eq(FARM_VILLAGER.col, 8)
    -- the break freezes ambient time
    press('e'); press('e')                     -- sale, then over-sell
    eq(farm.breaking, true)
    local t = farm.time
    run(1)
    eq(farm.time, t, 'ambient time frozen during the break')
end)

-- farm game feel: day cycle and shader pass (section 5) --------------------------------
-- A stand-in compiled pass, so the shader path can be checked headless.
local function fakePass()
    local sent = {}
    local shader = {sent = sent}
    function shader:hasUniform() return true end
    function shader:send(name, v) sent[name] = v end
    local function fakeCanvas(w, h)
        return {setFilter = function() end, getDimensions = function() return w, h end}
    end
    local canvas = fakeCanvas(VIRTUAL_WIDTH, VIRTUAL_HEIGHT)
    local blur = {sent = {}}
    function blur:hasUniform() return true end
    function blur:send(name, v) self.sent[name] = v end
    local buffers = {}
    for i, d in ipairs({2, 2, 4, 4, 4, 4}) do buffers[i] = fakeCanvas(VIRTUAL_WIDTH / d, VIRTUAL_HEIGHT / d) end
    FarmShader.reset()
    FarmShader.tried, FarmShader.enabled, FarmShader.shader, FarmShader.canvas = true, true, shader, canvas
    FarmShader.blur, FarmShader.buffers = blur, buffers
    return shader, canvas, blur
end

test('day: a new farm is day 1 in full daylight; the counter goes up at each dawn', function()
    local farm = toFarm()
    eq(farm:dayNumber(), 1)
    local t = farm:dayTint()
    eq(t[1] + t[2] + t[3], 3, 'not tinted at the start')
    run(FARM_DAY_LENGTH * (1 - FARM_DAY_START_PHASE) - 0.2)
    eq(farm:dayNumber(), 1, 'still day 1 just before dawn')
    assert(farm:dayPhase() > 0.99, 'end of the night')
    run(0.4)
    eq(farm:dayNumber(), 2, 'new dawn, new day'); assert(farm:dayPhase() < 0.01, 'cycle restarted')
    run(FARM_DAY_LENGTH)
    eq(farm:dayNumber(), 3)
end)

test('day: the tint runs dawn warm -> day neutral -> dusk orange -> night cool and darker, night stays readable', function()
    loadGame()
    local function luma(c) return 0.299 * c[1] + 0.587 * c[2] + 0.114 * c[3] end
    local dawn, day, dusk, night = FarmDayTint(0.02), FarmDayTint(0.4), FarmDayTint(0.66), FarmDayTint(0.84)
    assert(dawn[1] > dawn[3], 'dawn warm'); eq(day[1] + day[2] + day[3], 3, 'day neutral')
    assert(dusk[1] > dusk[2] and dusk[2] > dusk[3], 'dusk orange')
    assert(night[3] > night[1] and luma(night) < luma(day), 'night cool and darker')
    local darkest = 1
    for i = 0, 100 do darkest = math.min(darkest, luma(FarmDayTint(i / 100))) end
    assert(darkest >= 0.65, 'darkest point keeps ~0.7 brightness (' .. darkest .. ')')
    -- continuous across the wrap
    local a, b = FarmDayTint(0.9999), FarmDayTint(0)
    assert(math.abs(a[1] - b[1]) + math.abs(a[2] - b[2]) + math.abs(a[3] - b[3]) < 0.01, 'no jump at dawn')
end)

test('day: growth takes the same time across a day boundary; the clock pauses in the break', function()
    local farm = farmAtVillager({crops = {beanstalk = 1}})
    local plot = farm:plotAt(FARM_PLOTS.col, FARM_PLOTS.row)
    farm.dayTime = FARM_DAY_LENGTH - 5                  -- 5 s before the next dawn
    plot.tilled = true; Farm.plant(plot, farm.gameData, 'beanstalk'); Farm.water(plot)
    local t = 0
    while plot.state ~= PLOT_MATURE and t < 30 do step(); t = t + 1 / 60 end
    eq(farm:dayNumber(), 2, 'crossed into day 2 while growing')
    assert(math.abs(t - Farm.growthTime(true)) < 0.05, 'matured in ' .. t .. ' s across the boundary')
    press('e'); press('e')                              -- sell, over-sell
    eq(farm.breaking, true)
    local clock = farm.dayTime
    run(1.5)
    eq(farm.dayTime, clock, 'time of day frozen during the break')
end)

test('shader: headless (no GL) falls back once with a logged reason; the tint overlay keeps the cycle visible', function()
    local farm = toFarm()
    run(0.2); love.draw(); love.draw()
    eq(FarmShader.enabled, false)
    local logged = 0
    for _, line in ipairs(mock.printed) do if line:find('[farm-shader] disabled', 1, true) then logged = logged + 1 end end
    eq(logged, 1, 'reason logged once')
    -- at night the fallback multiplies the view by the night tint, before the HUD
    farm.dayTime = 0.84 * FARM_DAY_LENGTH
    mock.reset(); love.draw()
    local night = farm:dayTint()
    local overlayAt, hudAt
    for i, c in ipairs(mock.calls) do
        if c.name == 'setBlendMode' and c.args[1] == 'multiply' then overlayAt = overlayAt or i end
        if c.name == 'print' and c.args[1] == 'Day 1' then hudAt = i end
    end
    assert(overlayAt and hudAt and overlayAt < hudAt, 'tint overlay before the HUD text')
    local col = mock.calls[overlayAt + 1]
    eq(col.name, 'setColor'); eq(col.args[1], night[1]); eq(col.args[3], night[3])
end)

test('shader: --no-shader forces the same fallback path and the farm stays playable', function()
    local f2 = toFarm({'--no-shader'})
    love.draw()
    eq(FarmShader.forceOff, true); eq(FarmShader.enabled, false)
    assert(FarmShader.reason:find('no-shader', 1, true), FarmShader.reason)
    tillPlantWater()
    eq(f2:facingTarget().plot.watered, true, 'playable without the pass')
end)

test('shader: the scene goes into the farm canvas and through the pass; text and HUD are drawn after it', function()
    local farm = toFarm()
    local shader, canvas = fakePass()
    mock.reset(); love.draw()
    local setCanvasTo, shaderOn, shaderOff, drawCanvas, hud
    for i, c in ipairs(mock.calls) do
        if c.name == 'setCanvas' and c.args[1] == canvas then setCanvasTo = setCanvasTo or i end
        if c.name == 'setShader' and c.args[1] == shader then shaderOn = i end
        if c.name == 'setShader' and c.args[1] == nil and shaderOn then shaderOff = shaderOff or i end
        if c.name == 'draw' and c.args[1] == canvas then drawCanvas = i end
        if c.name == 'print' and c.args[1] == 'Day 1' then hud = i end
    end
    assert(setCanvasTo and shaderOn and drawCanvas and shaderOff and hud, 'pass ran')
    assert(setCanvasTo < shaderOn and shaderOn < drawCanvas and drawCanvas < shaderOff and shaderOff < hud,
        'scene -> canvas -> shader -> HUD after the pass')
    for _, c in ipairs(mock.calls) do
        assert(not (c.name == 'setBlendMode' and c.args[1] == 'multiply'), 'no fallback overlay while the pass is on')
    end
    -- every piece of text (price, bubble, HUD, hint) is drawn after the composite
    for i = 1, shaderOff do
        local c = mock.calls[i]
        assert(c.name ~= 'print' and c.name ~= 'printf', 'text drawn inside the pass: ' .. tostring(c.args[1]))
    end
    -- the top bar is opaque, so no world pixel (the barn roof) shows behind it
    local opaqueBar = false
    for i = shaderOff, #mock.calls - 1 do
        local c, n = mock.calls[i], mock.calls[i + 1]
        if c.name == 'setColor' and c.args[4] == 1 and n.name == 'rectangle' and n.args[1] == 'fill'
            and n.args[2] == 0 and n.args[3] == 0 and n.args[4] == VIRTUAL_WIDTH then opaqueBar = true end
    end
    assert(opaqueBar, 'opaque HUD bar drawn after the pass')
    -- the downsampled chain ran: ten blur steps into the buffers, bloom thresholded
    local blurDraws = 0
    for _, c in ipairs(mock.calls) do
        if c.name == 'setCanvas' then for _, b in ipairs(FarmShader.buffers) do if c.args[1] == b then blurDraws = blurDraws + 1 end end end
    end
    eq(blurDraws, 10, 'ten blur steps')
    eq(shader.sent.focusY, nil, 'tilt-shift is fixed to the screen: no focus-position uniform')
    assert(shader.sent.focusHalf and shader.sent.focusRamp, 'fixed tilt-shift zone uniforms sent')
    -- uniforms come from the constants and the day tint
    local u = shader.sent
    eq(u.bloomStrength, FARM_FX_BLOOM); eq(u.sunStrength, FARM_FX_SUN); eq(u.shaftStrength, FARM_FX_SHAFT)
    eq(u.glimmerStrength, FARM_FX_GLIMMER); eq(u.bloomThreshold, FARM_FX_BLOOM_THRESHOLD)
    eq(u.dayTint[1], 1); assert(u.daylight > 0.9, 'daylight at the start')
    farm.dayTime = 0.84 * FARM_DAY_LENGTH
    love.draw()
    eq(u.dayTint[3], farm:dayTint()[3]); assert(u.daylight < 0.1, 'night: no sun')
end)

test('shader: every look constant is a uniform; zeroing one changes only that uniform', function()
    loadGame()
    local fh = assert(io.open('shaders/farm.glsl', 'r')); local src = fh:read('*a'); fh:close()
    local base = FarmShader.uniforms({time = 3, tint = {1, 1, 1}})
    for name in pairs(base) do
        assert(src:find('uniform %w+ ' .. name .. ';'), 'shader declares ' .. name)
    end
    for _, c in ipairs({{'FARM_FX_BLOOM', 'bloomStrength'}, {'FARM_FX_SUN', 'sunStrength'},
            {'FARM_FX_SHAFT', 'shaftStrength'}, {'FARM_FX_GLIMMER', 'glimmerStrength'}}) do
        local saved = _G[c[1]]
        _G[c[1]] = 0
        local u = FarmShader.uniforms({time = 3, tint = {1, 1, 1}})
        _G[c[1]] = saved
        for name, v in pairs(base) do
            if name == c[2] then eq(u[name], 0, c[1] .. ' -> ' .. name)
            else
                local function ser(x) return type(x) == 'table' and table.concat(x, ',') or tostring(x) end
                eq(ser(u[name]), ser(v), c[1] .. ' leaves ' .. name)
            end
        end
    end
end)

test('shader: during the break the pass is plain and corruption and the fade are drawn on top of it', function()
    local farm = farmAtVillager({hasSold = true})
    local shader, canvas = fakePass()
    press('e')
    eq(farm.breaking, true)
    farm.dayTime = 0.84 * FARM_DAY_LENGTH                -- even at night: no tint in the break
    run(FARM_BREAK_GLITCH_TIME + FARM_BREAK_FALL_TIME * 0.5)
    mock.reset(); love.draw()
    local u = shader.sent
    eq(u.dayTint[1] + u.dayTint[2] + u.dayTint[3], 3, 'tint zeroed')
    eq(u.bloomStrength, 0); eq(u.sunStrength, 0); eq(u.shaftStrength, 0); eq(u.glimmerStrength, 0)
    local shaderOff, lastFill, fadeAlpha
    for i, c in ipairs(mock.calls) do
        if c.name == 'setShader' and c.args[1] == nil then shaderOff = i end
        if c.name == 'rectangle' and c.args[1] == 'fill' then lastFill = i end
        if c.name == 'setColor' and c.args[1] == 0 and c.args[2] == 0 and c.args[3] == 0 then fadeAlpha = c.args[4] end
    end
    assert(shaderOff and lastFill > shaderOff, 'corruption and fade after the pass')
    assert(fadeAlpha and fadeAlpha > 0, 'fade drawn')
    local fillsAfter = 0
    for i = shaderOff, #mock.calls do
        local c = mock.calls[i]
        if c.name == 'rectangle' and c.args[1] == 'fill' then fillsAfter = fillsAfter + 1 end
    end
    assert(fillsAfter > 5, 'corruption blocks drawn outside the pass (' .. fillsAfter .. ')')
    for i = 1, shaderOff do
        local c = mock.calls[i]
        assert(c.name ~= 'print' and c.name ~= 'printf', 'break: text drawn inside the pass: ' .. tostring(c.args[1]))
    end
    eq(u.tiltStrength, 0); eq(u.saturation, 0); eq(u.vignette, 0); eq(u.sunGlow, 0)
    run(BREAK_TIME)
    eq(gStateMachine.current.usesPush, false, 'reached the backrooms')
end)

test('shader: the backrooms never uses the farm pass', function()
    local fh = assert(io.open('src/states/game/BackroomsState.lua', 'r')); local src = fh:read('*a'); fh:close()
    assert(not src:find('FarmShader', 1, true), 'BackroomsState does not reference FarmShader')
    local back = toBackrooms({beanstalk = 1})
    local shader = fakePass()
    mock.reset(); love.draw()
    for _, c in ipairs(mock.calls) do
        assert(not (c.name == 'setShader' and c.args[1] == shader), 'farm shader set in the backrooms')
    end
    eq(next(shader.sent), nil, 'no uniforms sent')
end)

-- procedural levels (openspec procedural-backrooms-levels, sections 1-2) ------
test('levelgen 1.1: equal seeds give equal sequences, different seeds differ', function()
    local a, b, c = LevelGen.rng(42), LevelGen.rng(42), LevelGen.rng(43)
    local same, diff = true, false
    for _ = 1, 50 do
        local x, y, z = a:next(), b:next(), c:next()
        if x ~= y then same = false end
        if x ~= z then diff = true end
        assert(x >= 0 and x < 1, 'in [0, 1)')
    end
    assert(same, 'equal seeds equal'); assert(diff, 'different seeds differ')
    eq(LevelGen.levelSeed(7, 2), LevelGen.levelSeed(7, 2), 'levelSeed deterministic')
    local seen = {}
    for i = 1, 20 do seen[LevelGen.levelSeed(7, i)] = true end
    local count = 0
    for _ in pairs(seen) do count = count + 1 end
    eq(count, 20, 'level seeds of one run are distinct')
    assert(LevelGen.levelSeed(7, 1) ~= LevelGen.levelSeed(8, 1), 'run seed matters')
end)

test('levelgen 1.2: module dimensions match the crop sizes', function()
    loadGame()
    local M = LevelGen.MODULES
    local pumpkin = CROP_DEFS.pumpkin.size
    eq(M.pit.pitX1 - M.pit.pitX0, pumpkin[1], 'pit width = pumpkin width')
    eq(M.pit.depth, pumpkin[3], 'pit depth = pumpkin height')
    eq(M.pit.plot[3], -M.pit.depth, 'pit plot at the pit bottom')
    eq((M.pit.pitX0 + M.pit.pitX1) / 2, M.pit.plot[1], 'pit plot centred')
    local beanstalk = CROP_DEFS.beanstalk.size[3]
    assert(M.ledge.rise <= beanstalk, 'beanstalk reaches the ledge top')
    assert(beanstalk <= M.ledge.minCeiling, 'ledge ceiling clears the beanstalk')
    assert(math.abs((M.ledge.faceX - M.ledge.plot[1]) - 0.8) < 1e-9, 'ledge plot 0.8 m before the face')
    -- the vine, planted on the gap plot, spans the gap and lands on the floor
    local mn, mx = Crop.fullBounds('vine', {pos = M.gap.plot, dir = M.gap.dir})
    assert(mn[1] <= M.gap.gapX0 and mx[1] >= M.gap.gapX1, 'vine spans the gap')
    assert(mx[1] <= 6 + 1.4, 'vine lands within the next cell floor')
end)

local function gen(seed, d, opts) return LevelGen.generate(seed, d, opts) end

test('levelgen 1.3: layouts are valid, connected, non-overlapping and deterministic', function()
    loadGame()
    for d = 1, #LEVELGEN_DIFFICULTY do
        for seed = 1, 40 do
            local data = gen(seed, d)
            assert(Room.validate(data))
            Room(data)
            eq(data.meta.obstacles, LEVELGEN_DIFFICULTY[d].obstacles, 'chain length')
            local ok, msg = LevelGen.check(data)
            assert(ok, 'seed ' .. seed .. ': ' .. tostring(msg))
        end
    end
    local a, b = gen(5, 2), gen(5, 2)
    eq(#a.boxes, #b.boxes, 'same boxes'); eq(#a.pickups, #b.pickups, 'same pickups')
    for i, bx in ipairs(a.boxes) do eq(bx.pos[1], b.boxes[i].pos[1]); eq(bx.size[2], b.boxes[i].size[2]) end
    for i, p in ipairs(a.pickups) do eq(p.pos[1], b.pickups[i].pos[1]); eq(p.seed, b.pickups[i].seed) end
    eq(a.exit.pos[1], b.exit.pos[1], 'same exit')
    local differing = 0
    for s = 1, 20 do if #gen(s, 2).boxes ~= #gen(s + 100, 2).boxes or gen(s, 2).exit.pos[1] ~= gen(s + 100, 2).exit.pos[1] then differing = differing + 1 end end
    assert(differing >= 12, 'most seed pairs differ: ' .. differing)
    -- a hand-made overlap is caught
    local bad = gen(5, 2)
    table.insert(bad.meta.cells, bad.meta.cells[1])
    assert(not LevelGen.check(bad), 'overlap rejected')
end)

test('maze 1-2: turning branching maze, rooms, straight modules, loops stay in a region (written, not yet run)', function()
    loadGame()
    local junctions, rooms = 0, 0
    for seed = 1, 60 do
        local d = 1 + seed % #LEVELGEN_DIFFICULTY
        local data = gen(seed, d)
        local m = data.meta
        assert(LevelGen.check(data))
        assert(m.turns >= 3 and m.pathLength >= m.minPath and m.loops >= 1, 'seed ' .. seed)
        assert(#data.boxes <= LEVELGEN_BOX_BUDGET, 'box budget')
        for _, c in ipairs(m.cells) do
            if c.degree >= 3 then junctions = junctions + 1 end
            if c.room then rooms = rooms + 1 end
        end
        eq(#m.regions, m.obstacles + 1, 'regions R_0..R_n')
    end
    assert(junctions > 0 and rooms > 0, 'junctions and 2x2 rooms occur')
end)

test('levelgen 1.4: elevation and headroom track the chain (ledge then gap)', function()
    loadGame()
    local found = 0
    for seed = 1, 300 do
        local data = gen(seed, 3)
        local cells = data.meta.cells
        for i, c in ipairs(cells) do
            if c.kind == 'module' and c.module == 'ledge' then
                eq(c.elevOut, c.elev + LevelGen.MODULES.ledge.rise, 'ledge raises the floor')
                assert(c.ceil - c.elevOut >= BACKROOMS_PLAYER_HEIGHT + 0.5, 'headroom above the ledge')
                for _, o in ipairs(cells) do
                    if o.kind == 'module' and o.k == c.k + 1 and o.module == 'gap' then
                        eq(o.elev, c.elevOut, 'gap sits at ledge height')
                        local plot
                        for _, p in ipairs(data.plots) do if p.id == 'p' .. o.k then plot = p end end
                        eq(plot.pos[3], c.elevOut, 'gap plot at ledge height')
                        found = found + 1
                    end
                end
            end
        end
    end
    assert(found > 0, 'a ledge-then-gap chain occurred')
end)

test('levelgen 2.1: critical seeds satisfy the prefix rule over 500 seeds', function()
    loadGame()
    for seed = 1, 500 do
        local data = gen(seed, 1 + seed % #LEVELGEN_DIFFICULTY)
        local ok, msg = LevelGen.check(data)
        assert(ok, 'seed ' .. seed .. ': ' .. tostring(msg))
        local crit, extra = 0, 0
        for _, p in ipairs(data.pickups) do
            if p.tier == 'critical' then crit = crit + 1 else extra = extra + 1 end
        end
        eq(crit, data.meta.obstacles, 'one critical seed per obstacle')
        assert(extra >= 1, 'at least one extra')
        eq(next(data.allotment), nil, 'generated levels start with no seeds')
        -- seedTypes lists exactly the chain's types
        local used = {}
        for _, l in ipairs(data.meta.chain) do used[l.seed] = true end
        for _, t in ipairs(data.seedTypes) do assert(used[t], 'seedTypes only chain types') end
    end
end)

test('levelgen 2.2: a bad candidate is rejected and replaced by a derived seed', function()
    loadGame()
    -- a seed whose unmutated first candidate is accepted (layout acceptance can
    -- reject candidates too, so which seeds pass first time depends on the layout rules)
    local seed
    for s = 9, 60 do
        if gen(s, 2).meta.attempt == 0 then seed = s break end
    end
    assert(seed, 'some seed passes first time')
    local data = gen(seed, 2, {mutate = function(cand, attempt)
        if attempt == 0 then
            for i, p in ipairs(cand.pickups) do
                if p.tier == 'critical' then table.remove(cand.pickups, i) break end
            end
        end
    end})
    assert(data.meta.attempt >= 1, 'a later candidate used (derived seeds may also be rejected by layout rules)')
    assert(data.meta.seed ~= seed, 'derived seed used')
    eq(data.meta.requestedSeed, seed)
    assert(LevelGen.check(data))
    eq(gen(seed, 2).meta.attempt, 0, 'unmutated seed passes first time')
end)

test('levelgen 2.3: Room validates and builds pickups and seedTypes', function()
    loadGame()
    local data = gen(3, 2)
    local room = Room(data)
    eq(#room.pickups, #data.pickups, 'pickups built')
    eq(#room.seedTypes, #data.seedTypes, 'seedTypes kept')
    local function with(change)
        local d = gen(3, 2)
        change(d)
        return Room.validate(d)
    end
    assert(not with(function(d) d.pickups[1].seed = 'rock' end), 'unknown pickup seed')
    assert(not with(function(d) d.pickups[1].tier = 'bonus' end), 'unknown tier')
    assert(not with(function(d) d.pickups[1].pos = {1, 2} end), 'bad pos')
    assert(not with(function(d) d.seedTypes = {'rock'} end), 'unknown seedType')
    assert(not with(function(d) d.seedTypes = 5 end), 'seedTypes not a list')
    assert(not pcall(Room, (function() local d = gen(3, 2); d.pickups[1].tier = 'x'; return d end)()), 'Room rejects')
end)

test('levelgen 2.4: walking onto a pickup adds one seed and removes it', function()
    local back = toBackrooms()
    local data = gen(3, 2)
    back.rooms = {data}
    back:loadRoom(1)
    local n = #back.room.pickups
    local p = back.room.pickups[1]
    local seed = p.seed
    back.gameData.seeds = {beanstalk = 0, pumpkin = 0, vine = 0}   -- (stock policy is section 4)
    back.player:setPosition(p.pos[1], p.pos[2], p.pos[3])
    back:collectPickups()
    eq(back.gameData.seeds[seed], 1, 'seed added')
    eq(#back.room.pickups, n - 1, 'pickup removed')
    assert(back.message and back.message.text:find(SeedName(seed), 1, true), 'message names the seed')
    back:collectPickups()
    eq(back.gameData.seeds[seed], 1, 'not collected twice')
    mock.reset(); love.draw()
end)

test('levelgen 2.5: visibleSeedTypes uses seedTypes when present', function()
    local back = toBackrooms()
    local data = gen(3, 1)
    data.seedTypes = {'pumpkin', 'vine'}
    back.rooms = {data}
    back:loadRoom(1)
    local v = back:visibleSeedTypes()
    eq(#v, 2, 'two types'); eq(v[1], 'pumpkin'); eq(v[2], 'vine')
    back.rooms = {BACKROOMS_ROOMS[2]}
    back:loadRoom(1)
    eq(#back:visibleSeedTypes(), 2, 'allotment fallback unchanged')
end)

-- 3. uproot ----------------------------------------------------------------------
test('uproot 3.1: freeing a plot lets it take a new seed; uprooting refunds one seed (grown or growing)', function()
    local back = toBackrooms()
    back.rooms = {BACKROOMS_ROOMS[2]}
    back:loadRoom(1)
    back.gameData.seeds = {beanstalk = 0, pumpkin = 2, vine = 1}
    back.player:setPosition(-4.6, 0, 0)       -- on the floor at the pit rim, plot 'pit' in reach
    back.selectedSeed = 'pumpkin'
    local ok, crop = back:plant()
    assert(ok, 'planted wrong crop: ' .. tostring(crop))
    eq(back.gameData.seeds.pumpkin, 1)
    local plot = back.room:plotById('pit')
    eq(back:uproot() and true, true, 'uprooted while growing')
    eq(plot.crop, nil, 'plot free'); eq(#back.room.crops, 0)
    eq(back.gameData.seeds.pumpkin, 2, 'growing crop: one seed refunded')
    assert(back.message.text:find('Uprooted', 1, true), 'message')
    -- the cancelled growth never completes
    Timer.update(10, back.timers)
    eq(crop.grown, false); eq(crop.removed, true)
    -- a grown crop: uproot removes the collider too, plot accepts a new seed
    local ok2, crop2 = back:plant(); assert(ok2)
    Timer.update(CROP_DEFS.pumpkin.growTime + 0.01, back.timers)
    back.player:setPosition(-4.6, 0, 0)
    back.room:updateCrops({1000, 1000, 1000}, {1001, 1001, 1001})
    eq(crop2.active, true)
    local solids = #back.room:solidColliders()
    local ok3 = back:uproot()
    eq(ok3, true, 'uprooted when grown')
    eq(back.gameData.seeds.pumpkin, 2, 'grown crop: one seed refunded (planted 1, back to 2)')
    eq(#back.room:solidColliders(), solids - 1, 'structure no longer collides')
    back.gameData.seeds.vine = 1
    back.selectedSeed = 'vine'
    local ok4 = back:plant()
    eq(ok4, true, 'plot accepts a new seed')
    eq(back.gameData.seeds.vine, 0)
    eq(back.gameData.seeds.pumpkin, 2, 'both pumpkins were refunded; the vine was a different type')
    -- the X key drives it
    press('x')
    eq(plot.crop, nil, 'X uproots')
    local out = back:uproot()
    eq(out, false, 'nothing left to uproot')
end)

test('uproot 3.1b: every crop type, growing or grown, targets from a normal standing spot beside its collider; standing still refuses', function()
    local back = toBackrooms()
    local room = back.room
    for _, seed in ipairs({'beanstalk', 'pumpkin', 'vine'}) do
        for _, grown in ipairs({false, true}) do
            local plot = {id = 't', pos = {0, 0, 0}, dir = '+x', reach = BACKROOMS_PLANT_RANGE}
            local crop = Crop(seed, plot)
            plot.crop = crop
            room.plots = {plot}
            if grown then crop.active = true end
            -- just outside the full footprint (player radius ~0.3), on the plot's floor, midway along its long side
            local sx = (crop.min[1] + crop.max[1]) / 2
            local x, y = sx, crop.max[2] + 0.4
            if seed == 'vine' then x = crop.max[1] - 0.2 end   -- far end of the vine, > reach from the centre
            local label = seed .. (grown and ' grown' or ' growing')
            assert(room:nearestCropPlot(x, y, 0) == plot, label .. ' targeted from beside it')
            local pmin, pmax = {x - 0.3, y - 0.3, 0}, {x + 0.3, y + 0.3, 1.8}
            local ok = room:uproot(plot, pmin, pmax)
            eq(ok, true, label .. ' uprooted')
            -- safety refusal unchanged: standing on the crop
            local plot2 = {id = 't2', pos = {0, 0, 0}, dir = '+x', reach = BACKROOMS_PLANT_RANGE}
            plot2.crop = Crop(seed, plot2)
            local c = plot2.crop
            local ok2, why = room:uproot(plot2, {c.min[1], c.min[2], c.max[3] - 0.05}, {c.min[1] + 0.6, c.min[2] + 0.6, c.max[3] + 1.8})
            eq(ok2, false, label .. ' refused on/in crop'); eq(why, 'standing')
        end
    end
    -- too far from the footprint is still out of reach
    local plot = {id = 't', pos = {0, 0, 0}, dir = '+x', reach = BACKROOMS_PLANT_RANGE}
    plot.crop = Crop('pumpkin', plot); room.plots = {plot}
    eq(room:nearestCropPlot(plot.crop.max[1] + BACKROOMS_PLANT_RANGE + 0.5, 0, 0), nil)
end)

test('uproot 3.2: refused for the demo crop and while standing on or in the crop', function()
    local back = toBackrooms()
    local demo = back.room:plotById('demo')
    assert(demo.crop and demo.crop.demo, 'tutorial demo crop')
    back.player:setPosition(0, 0, 0)
    local before = #back.room.crops
    local ok, reason = back:uproot()
    eq(ok, false); eq(reason, 'demo')
    eq(#back.room.crops, before); assert(demo.crop, 'demo crop kept')
    assert(back.message.text:find('lesson', 1, true), 'on-screen message')
    -- standing on a grown pumpkin
    back.rooms = {BACKROOMS_ROOMS[2]}
    back:loadRoom(1)
    back.gameData.seeds = {beanstalk = 0, pumpkin = 1, vine = 0}
    back.selectedSeed = 'pumpkin'
    back.player:setPosition(-4.6, 0, 0)
    assert(back:plant())
    Timer.update(CROP_DEFS.pumpkin.growTime + 0.01, back.timers)
    back.room:updateCrops({1000, 1000, 1000}, {1001, 1001, 1001})
    local crop = back.room:plotById('pit').crop
    eq(crop.active, true)
    back.player:setPosition(-2.7, 0, crop.max[3])      -- on top (pumpkin top at z = 0)
    local ok2, reason2 = back:uproot()
    eq(ok2, false); eq(reason2, 'standing')
    assert(back.room:plotById('pit').crop == crop, 'not removed')
    assert(back.message.text:find('Step off', 1, true), 'message says why')
    back.player:setPosition(-2.7, 0, crop.min[3] + 0.3)   -- inside it
    eq(back:uproot(), false)
    back.player:setPosition(-4.6, 0, 0)
    eq(back:uproot(), true, 'removable once clear (at the rim)')
end)

-- 4. level sequence, stock policy, reset ----------------------------------------------
-- Enters the real sequence (no room override) with run seed `runSeed`.
local function toSequence(runSeed, seeds)
    local back = toBackrooms(seeds)          -- loads the game; then re-enter without the override
    BackroomsState.roomsOverride = nil
    BACKROOMS_RUN_SEED = runSeed
    gStateMachine:change('backrooms', CarryOverGameData(NewGameData(seeds and {seeds = seeds} or nil)))
    return gStateMachine.current
end

test('sequence 4.1: tutorial, then generated levels with rising difficulty, per-level seeds, then the ending', function()
    local back = toSequence(777)
    eq(back:levelCount(), 1 + BACKROOMS_GENERATED_LEVELS)
    eq(back.runSeed, 777)
    assert(find(mock.printed, 'run seed 777'), 'run seed logged')
    eq(back.roomIndex, 1); eq(back.room.id, 'tutorial')
    assert(back.room:plotById('demo').crop.demo, 'tutorial keeps its half-grown demo crop')
    local obstacles, ids = {}, {}
    for i = 2, back:levelCount() do
        back:advance()
        eq(back.roomIndex, i)
        assert(back.room.data.generated, 'level ' .. i .. ' is generated')
        -- the requested seed is always run seed + index; a rejected candidate is replaced by a derived seed
        eq(back.room.data.meta.requestedSeed, LevelGen.levelSeed(777, i), 'level seed from run seed + index')
        if back.room.data.meta.attempt == 0 then eq(back.room.data.meta.seed, LevelGen.levelSeed(777, i)) end
        eq(back.levelSeeds[i], LevelGen.levelSeed(777, i))
        obstacles[#obstacles + 1] = back.room.data.meta.obstacles
        ids[#ids + 1] = back.room.id
    end
    for i = 2, #obstacles do assert(obstacles[i] >= obstacles[i - 1], 'non-decreasing obstacles') end
    assert(obstacles[#obstacles] > obstacles[1], 'last has more obstacles than the first')
    local changes = countChanges()
    back:advance()
    eq(#changes, 1); eq(changes[1], 'ending')

    -- the same run seed gives the same levels; another run seed does not
    local again = toSequence(777)
    again:advance()
    eq(again.room.id, ids[1]); eq(#again.room.data.boxes, #back.levels[2].boxes)
    for i, p in ipairs(back.levels[2].pickups) do
        eq(again.room.data.pickups[i].seed, p.seed); near(again.room.data.pickups[i].pos[1], p.pos[1], 1e-12)
    end
    local other = toSequence(778)
    other:advance()
    assert(other.room.id ~= ids[1], 'different run seed, different level')
    -- the debug skip walks the same sequence and the default run seed is random but logged
    BACKROOMS_RUN_SEED = nil
    gStateMachine:change('backrooms', CarryOverGameData(NewGameData()))
    assert(gStateMachine.current.runSeed >= 1, 'random run seed')
end)

test('sequence 4.2: starting stocks: tutorial topped up, generated levels start empty, nothing carries', function()
    local back = toSequence(5, {beanstalk = 0, pumpkin = 3, vine = 0})
    eq(FormatSeeds(back.gameData.seeds), 'beanstalk=1 pumpkin=3 vine=0', 'tutorial: carry-over and top-up unchanged')
    back.gameData.seeds.pumpkin = 9           -- leftovers
    back:advance()
    eq(FormatSeeds(back.gameData.seeds), 'beanstalk=0 pumpkin=0 vine=0', 'level 2 starts empty')
    eq(FormatSeeds(back.roomStartSeeds), 'beanstalk=0 pumpkin=0 vine=0')
    back.gameData.seeds.vine = 4
    back:advance()
    eq(FormatSeeds(back.gameData.seeds), 'beanstalk=0 pumpkin=0 vine=0', 'nothing carried to level 3')
    eq(FormatSeeds(RoomStartingSeeds(back.room.data, 1, {beanstalk = 5, pumpkin = 5, vine = 5})), 'beanstalk=0 pumpkin=0 vine=0',
        'even as a first room')
    -- the HUD still lists the level's seed types
    assert(#back:visibleSeedTypes() >= 1)
end)

test('sequence 4.3: reset rebuilds the same level: layout equal, pickups back, crops gone, stock restored', function()
    local back = toSequence(31)
    back:advance(); back:advance()           -- level 3 (three obstacles)
    local data = back.room.data
    local nBoxes, nPick, oldRoom = #back.room.colliders, #back.room.pickups, back.room
    assert(nPick >= 3, 'critical + extra pickups')
    local exit0 = {back.room.exit.pos[1], back.room.exit.pos[2], back.room.exit.pos[3]}
    -- collect everything
    local all = {}
    for i, p in ipairs(back.room.pickups) do all[i] = p end
    for _, p in ipairs(all) do
        back.player:setPosition(p.pos[1], p.pos[2], p.pos[3]); back:collectPickups()
    end
    eq(#back.room.pickups, 0, 'all collected')
    local total = 0
    for _, t in ipairs(SEED_TYPES) do total = total + back.gameData.seeds[t] end
    eq(total, nPick, 'one seed per pickup')
    -- plant something on the first plot
    local plot = back.room.plots[1]
    local t = back.room.data.meta.chain[1].seed
    back.player:setPosition(plot.pos[1] - 0.5, plot.pos[2], plot.pos[3] + (t == 'pumpkin' and 1 or 0))
    back.selectedSeed = t
    assert(back:plant()); assert(#back.room.crops == 1)
    back:resetRoom()
    assert(back.room ~= oldRoom, 'rebuilt')
    eq(back.levels[3], data, 'same level data (same seed)')
    eq(#back.room.colliders, nBoxes, 'same layout'); eq(#back.room.pickups, nPick, 'pickups respawned')
    eq(#back.room.crops, 0, 'crops cleared'); eq(back.room.plots[1].crop, nil)
    eq(FormatSeeds(back.gameData.seeds), 'beanstalk=0 pumpkin=0 vine=0', 'starting stock restored')
    for i = 1, 3 do near(back.room.exit.pos[i], exit0[i], 1e-12, 'exit') end
    eq(back.roomIndex, 3)
    local s = back.room.spawn
    near(back.player.x, s[1], 1e-6)
end)


-- backrooms look (backrooms-visual-atmosphere sections 1-2) ----------------------
-- A fake shader that records uniform sends, to test what the look uploads.
local function fakeShader()
    local sh = {sent = {}}
    function sh:hasUniform() return true end
    function sh:send(name, ...) self.sent[name] = {...} end
    return sh
end

local function lookRoom(extra)
    local data = {id = 'look-test', spawn = {0, 0, 0}, exit = {pos = {9, 0, 1}, size = {1, 1, 1}}, allotment = {},
        boxes = Room.joinBoxes(Room.shellBoxes(24, 4, 3, 0.2))}
    for k, v in pairs(extra or {}) do data[k] = v end
    return Room(data)
end

test('look 1.1: a forced compile failure keeps the look off, logs once, and rooms still build and draw', function()
    loadGame()
    BackroomsLook.reset()
    love.filesystem.read = function() return 'stub glsl' end
    love.graphics.newShader = function() error('0:1: syntax error (forced)') end
    local printed = {}
    print = function(...) printed[#printed + 1] = table.concat({...}, ' ') end
    for _ = 1, 3 do BackroomsLook.init() end
    local room = lookRoom()
    room:draw(0, 0)
    print = realPrint
    eq(BackroomsLook.enabled, false)
    assert(tostring(BackroomsLook.reason):find('compile failed', 1, true), BackroomsLook.reason)
    local n = 0
    for _, l in ipairs(printed) do if l:find('[backrooms-look]', 1, true) then n = n + 1 end end
    eq(n, 1, 'reason logged exactly once')
    eq(#room.fixtures, 0, 'no fixture models without the look')
    eq(BackroomsLook.begin(room, 0, 0, 1, 0), nil)
end)

test('look 1.1: --no-shader and a missing source also leave it off; quality setting validates', function()
    loadGame({'--no-shader'})
    eq(BackroomsLook.forceOff, true)
    eq(BackroomsLook.init(), false)
    assert(BackroomsLook.reason:find('--no-shader', 1, true))
    BackroomsLook.reset(); BackroomsLook.forceOff = false
    love.filesystem.read = function() return nil end
    eq(BackroomsLook.init(), false)
    assert(BackroomsLook.reason:find('cannot read', 1, true))
    eq(BackroomsLook.setQuality('low'), true); eq(BackroomsLook.quality, 'low')
    eq(BackroomsLook.setQuality('ultra'), false); eq(BackroomsLook.quality, 'low')
end)

test('look 1.1: --quality=NAME sets the quality at launch', function()
    loadGame({'--quality=medium'})
    eq(BackroomsLook.quality, 'medium')
end)

test('look 1.2: shaders/backrooms.glsl declares the uniforms the look uploads', function()
    local f = assert(io.open('shaders/backrooms.glsl'))
    local src = f:read('a'); f:close()
    for _, name in ipairs({'camPos', 'ambient', 'lightCount', 'lightPos', 'lightColor', 'lightRadius',
        'fogColor', 'fogDensity', 'litFloor', 'emissive'}) do
        assert(src:find('uniform [%w ]+ ' .. name .. '[%[;]'), 'uniform ' .. name)
    end
    assert(src:find('#define MAX_LIGHTS ' .. 8, 1, true))
    loadGame()
    eq(BACKROOMS_LOOK_MAX_LIGHTS, 8, 'matches MAX_LIGHTS')
end)

test('look 1.3: flicker is steady / varies over time / buzzes, dead is exactly zero; pure and deterministic', function()
    loadGame()
    local F = BackroomsLook.flicker
    for t = 0, 5, 0.37 do
        eq(F('dead', t, 0.3), 0); eq(F('steady', t, 0.3), 1)
    end
    for _, mode in ipairs({'flicker', 'buzz'}) do
        for _, phase in ipairs({0, 0.25, 0.6, 0.93}) do
            local lo, hi = 9, -9
            for i = 0, 300 do
                local v = F(mode, i / 60, phase)
                assert(v >= 0 and v <= 1, mode .. ' in [0, 1]')
                lo, hi = math.min(lo, v), math.max(hi, v)
                eq(v, F(mode, i / 60, phase), 'deterministic')
            end
            assert(hi - lo > 0.1, mode .. ' varies over 5 s (phase ' .. phase .. ')')
        end
    end
    BackroomsLook.setQuality('low')
    local l = {mode = 'flicker', intensity = 2, phase = 0}
    for i = 0, 300 do eq(BackroomsLook.activeIntensity(l, i / 60), 2, 'low quality: no flicker') end
    eq(BackroomsLook.activeIntensity({mode = 'dead', intensity = 2}, 1), 0, 'dead stays dead at low')
end)

test('look 2.1: Room.validate checks lights and lighting', function()
    loadGame()
    local function bad(extra, needle)
        local ok, err = pcall(lookRoom, extra)
        assert(not ok and tostring(err):find(needle, 1, true), needle .. ': ' .. tostring(err))
    end
    bad({lights = 5}, 'lights must be a list')
    bad({lights = {{}}}, 'light 1 needs pos')
    bad({lights = {{pos = {0, 0, 2}, mode = 'strobe'}}}, 'unknown mode')
    bad({lights = {{pos = {0, 0, 2}, radius = -1}}}, 'radius must be positive')
    bad({lights = {{pos = {0, 0, 2}, intensity = 0}}}, 'intensity must be positive')
    bad({lighting = 'moonlit'}, 'unknown lighting preset')
    bad({lighting = 7}, 'lighting must be')
    local room = lookRoom({lights = {{pos = {0, 0, 2.8}, mode = 'buzz'}}, lighting = {preset = 'dim', fogDensity = 0.2}})
    eq(#room.lights, 1); eq(room.lighting.name, 'dim'); eq(room.lighting.fogDensity, 0.2)
    near(room.lighting.ambient[1], BACKROOMS_LIGHT_PRESETS['dim'].ambient[1], 1e-12, 'preset kept where not overridden')
end)

test('look 2.1: nearest-N selection (nearest first, dead skipped, capped) and the per-frame upload', function()
    loadGame()
    local lights = {}
    for i = 1, 12 do lights[i] = {pos = {i * 2, 0, 3}, mode = (i == 2) and 'dead' or 'steady'} end
    local picked = BackroomsLook.nearestLights(lights, 0, 0, 1, 8)
    eq(#picked, 8)
    eq(picked[1], 1); eq(picked[2], 3, 'dead light 2 skipped'); eq(picked[8], 9)
    picked = BackroomsLook.nearestLights(lights, 25, 0, 1, 3)
    eq(picked[1], 12); eq(picked[2], 11); eq(picked[3], 10)
    eq(#BackroomsLook.nearestLights({{pos = {0, 0, 0}}}, 0, 0, 0, 8), 1)

    -- upload with a fake compiled shader
    BackroomsLook.reset()
    local sh = fakeShader()
    love.filesystem.read = function() return 'stub glsl' end
    love.graphics.newShader = function() return sh end
    local room = lookRoom({lights = lights, lighting = 'bright'})
    eq(BackroomsLook.enabled, true)
    local used = BackroomsLook.begin(room, 0, 0, 1, 0)
    eq(used, sh)
    eq(sh.sent.lightCount[1], 8)
    eq(#sh.sent.lightPos, 8)
    eq(sh.sent.lightPos[1][1], 2)
    eq(sh.sent.fogDensity[1], BACKROOMS_LIGHT_PRESETS['bright'].fogDensity)
    eq(sh.sent.litFloor[1], 0)
end)

test('look 2.2: presets are complete, ambient/gameplay floors guarantee readability, defaults reproducible', function()
    loadGame()
    for _, name in ipairs({'bright', 'dim', 'single-bulb', 'near-dark'}) do
        local p = BACKROOMS_LIGHT_PRESETS[name]
        assert(p, name)
        for _, k in ipairs({'ambient', 'fogColor', 'fogDensity', 'intensity', 'litEvery', 'flicker', 'buzz', 'gameplayFloor'}) do
            assert(p[k] ~= nil, name .. ' has ' .. k)
        end
        assert(p.gameplayFloor >= 0.5, name .. ' keeps plots/crops/pickups/exit visible')
        assert(p.ambient[1] >= 0.1 and p.ambient[2] >= 0.1, name .. ' has an ambient floor')
    end
    eq(BackroomsLook.defaultPresetName('tutorial'), 'bright')
    local seen = {}
    for i = 1, 40 do
        local a = BackroomsLook.defaultPresetName('gen-' .. i * 7919)
        eq(a, BackroomsLook.defaultPresetName('gen-' .. i * 7919), 'same id, same preset')
        seen[a] = true
    end
    local kinds = 0
    for _ in pairs(seen) do kinds = kinds + 1 end
    assert(kinds >= 3, 'generated levels differ: ' .. kinds .. ' presets over 40 ids')
    -- auto fixtures: reproducible, under the ceiling, single-bulb leaves most dead, near-dark is not all lit
    local boxes = Room.shellBoxes(24, 4, 3, 0.2)
    local single = BackroomsLook.resolveLighting('single-bulb', 'x')
    local a, b = BackroomsLook.autoLights(boxes, single, 'x'), BackroomsLook.autoLights(boxes, single, 'x')
    eq(#a, #b); assert(#a >= 3)
    local live = 0
    for i, l in ipairs(a) do
        eq(l.mode, b[i].mode); eq(l.pos[1], b[i].pos[1])
        assert(l.pos[3] < 3, 'below the ceiling')
        if l.mode ~= 'dead' then live = live + 1 end
    end
    assert(live >= 1 and live < #a, 'single-bulb: some lit, most dead')
    local bright = BackroomsLook.autoLights(boxes, BackroomsLook.resolveLighting('bright', 'x'), 'x')
    local dead = 0
    for _, l in ipairs(bright) do if l.mode == 'dead' then dead = dead + 1 end end
    eq(dead, 0, 'bright: every fixture lit')
end)

test('look 2.2/2.3: with the look on, gameplay objects get the readability floor and shadow blobs are drawn', function()
    loadGame()
    BackroomsLook.reset()
    local sh = fakeShader()
    love.filesystem.read = function() return 'stub glsl' end
    love.graphics.newShader = function() return sh end
    love.graphics.newImage = function() return {setFilter = function() end} end
    love.image.newImageData = function() return {mapPixel = function() end} end
    local room = lookRoom({lighting = 'near-dark', billboards = {{texture = 'sacks', pos = {2, 0, 0}, height = 1}},
        pickups = {{pos = {4, 0, 0}, seed = 'pumpkin', tier = 'extra'}}})
    assert(#room.fixtures >= 3, 'fixture panels built')
    local blobsBefore = #room.blobs
    eq(blobsBefore, 1, 'one blob per billboard at build')
    local floors = {}
    local setShader = sh.send
    sh.send = function(self, name, v) if name == 'litFloor' then floors[#floors + 1] = v end return setShader(self, name, v) end
    room:draw(0, 0)
    assert(#room.blobs == 2, 'pickup blob added: ' .. #room.blobs)
    local sawFloor = false
    for _, v in ipairs(floors) do if v == BACKROOMS_LIGHT_PRESETS['near-dark'].gameplayFloor then sawFloor = true end end
    assert(sawFloor, 'gameplay objects drawn with the near-dark readability floor')
    eq(floors[#floors], 0, 'floor reset after the gameplay objects')
end)

-- backrooms atmosphere (section 3) ---------------------------------------------------
local function fakePostSetup()
    BackroomsLook.reset()
    local sh = fakeShader()
    love.filesystem.read = function() return 'stub glsl' end
    love.graphics.newShader = function() return sh end
    love.graphics.newImage = function() return {setFilter = function() end} end
    love.image.newImageData = function() return {mapPixel = function() end} end
    love.graphics.newCanvas = function(w, h) return {w = w, h = h, setFilter = function() end,
        getDimensions = function(self) return self.w, self.h end} end
    return sh
end

test('atmos 3.1: fog colour and density are uploaded per room, denser/darker in worse rooms', function()
    loadGame()
    local sh = fakePostSetup()
    local seen = {}
    for _, name in ipairs({'bright', 'dim', 'single-bulb', 'near-dark'}) do
        local room = lookRoom({lighting = name})
        BackroomsLook.begin(room, 0, 0, 1, 0)
        local p = BACKROOMS_LIGHT_PRESETS[name]
        eq(sh.sent.fogDensity[1], p.fogDensity, name .. ' density')
        eq(sh.sent.fogColor[1], p.fogColor, name .. ' colour')
        local c = p.fogColor
        assert(c[1] >= c[2] and c[2] > c[3] * 1.5, name .. ' fog is yellow-brown')
        seen[#seen + 1] = p.fogDensity
    end
    for i = 2, #seen do assert(seen[i] > seen[i - 1], 'fog thickens from bright to near-dark') end
    local src = io.open('shaders/backrooms.glsl'):read('*a')
    assert(src:find('FOG_NEAR', 1, true), 'shader keeps near range clear')
end)

test('atmos 3.2: shafts under live fixtures scale with fog; low quality skips them', function()
    loadGame()
    fakePostSetup()
    eq(BackroomsLook.shaftStrength(0), 0)
    assert(BackroomsLook.shaftStrength(0.05) > BackroomsLook.shaftStrength(0.02))
    assert(BackroomsLook.shaftStrength(5) <= 0.4, 'capped')
    local room = lookRoom({lighting = 'bright'})
    BackroomsLook.init()
    local function shaftDraws()
        mock.reset()
        BackroomsLook.drawShafts(room, 0, 0)
        return mock.count('model.draw')
    end
    BackroomsLook.setQuality('high')
    local n = shaftDraws()
    assert(n >= 1 and n <= BACKROOMS_LOOK_MAX_LIGHTS, 'shafts drawn: ' .. n)
    local sawAdd = false
    for _, c in ipairs(mock.calls) do if c.name == 'setBlendMode' and c.args[1] == 'add' then sawAdd = true end end
    assert(sawAdd, 'additive blend')
    local last = mock.calls[#mock.calls]
    eq(last.name, 'setDepthMode'); eq(last.args[2], true, 'depth writes restored')
    BackroomsLook.setQuality('medium'); assert(shaftDraws() >= 1, 'medium keeps shafts')
    BackroomsLook.setQuality('low'); eq(shaftDraws(), 0, 'low skips shafts')
    eq(BackroomsLook.bloomStrength(), 0); BackroomsLook.setQuality('high'); assert(BackroomsLook.bloomStrength() > 0)
end)

test('atmos 3.3: scene goes through a depth canvas and grade; HUD is drawn outside canvas and shader', function()
    loadGame({'--debug'})
    fakePostSetup()
    mock.press('f1'); step()
    mock.press('f1'); step()
    eq(gStateMachine.current.usesPush, false)
    mock.reset()
    love.draw()
    eq(BackroomsLook.postEnabled, true)
    local canvas, shader, sceneInCanvas, drewPass, hudPrints = nil, nil, 0, false, 0
    for _, c in ipairs(mock.calls) do
        if c.name == 'setCanvas' then canvas = c.args[1]
            if canvas then eq(canvas.depth, true, 'canvas has a depth buffer') end
        elseif c.name == 'setShader' then shader = c.args[1]
        elseif c.name == 'model.draw' and canvas then sceneInCanvas = sceneInCanvas + 1
        elseif c.name == 'draw' and shader == BackroomsLook.postShader then drewPass = true
        elseif c.name == 'print' then
            hudPrints = hudPrints + 1
            eq(canvas, nil, 'HUD text not drawn into the scene canvas')
            eq(shader, nil, 'HUD text not drawn through the grade shader')
        end
    end
    assert(sceneInCanvas > 0, 'room drawn into the canvas')
    assert(drewPass, 'canvas drawn through the post shader')
    assert(hudPrints > 0, 'HUD printed')
end)

test('atmos 3.3: post failures fall back to the plain direct render, logged once, state restored', function()
    loadGame({'--debug'})
    fakePostSetup()
    love.graphics.newCanvas = function() error('no canvas (forced)') end
    mock.press('f1'); step()
    mock.press('f1'); step()
    local printed = {}
    print = function(...) printed[#printed + 1] = table.concat({...}, ' ') end
    mock.reset()
    for _ = 1, 3 do love.draw() end
    print = realPrint
    eq(BackroomsLook.postEnabled, false)
    assert(BackroomsLook.postReason:find('canvas creation failed', 1, true), BackroomsLook.postReason)
    local n = 0
    for _, l in ipairs(printed) do if l:find('post-process off', 1, true) then n = n + 1 end end
    eq(n, 1, 'logged once')
    for _, c in ipairs(mock.calls) do
        if c.name == 'setCanvas' then eq(c.args[1], nil, 'never switched to a canvas') end
    end
    assert(mock.count('model.draw') > 0, 'scene still drawn')
    -- a failing pass shader mid-frame also falls back and resets render state
    BackroomsLook.reset(); fakePostSetup()
    BackroomsLook.init(); BackroomsLook.initPost()
    local real = love.graphics.draw
    love.graphics.draw = function() error('pass failed (forced)') end
    local ok = pcall(BackroomsLook.renderScene, function() end)
    love.graphics.draw = real
    eq(BackroomsLook.postEnabled, false, 'pass failure disables post')
    local lastShader
    for _, c in ipairs(mock.calls) do if c.name == 'setShader' then lastShader = c.args[1] end end
    eq(lastShader, nil, 'shader reset to none')
    -- --no-shader: no post either
    BackroomsLook.reset(); BackroomsLook.forceOff = true
    eq(BackroomsLook.initPost(), false); BackroomsLook.forceOff = false
end)

local function levelSignature(room)
    local parts = {}
    local function r(v) return string.format('%.4f', v) end
    for _, c in ipairs(room:solidColliders()) do
        parts[#parts + 1] = 'c' .. r(c.min[1]) .. ',' .. r(c.min[2]) .. ',' .. r(c.min[3]) .. ',' .. r(c.max[1]) .. ',' .. r(c.max[2]) .. ',' .. r(c.max[3])
    end
    for _, p in ipairs(room.plots) do parts[#parts + 1] = 'p' .. p.id .. r(p.pos[1]) .. ',' .. r(p.pos[2]) .. ',' .. r(p.pos[3]) end
    for _, p in ipairs(room.pickups) do parts[#parts + 1] = 'k' .. p.seed .. (p.tier or '') .. r(p.pos[1]) .. ',' .. r(p.pos[2]) end
    parts[#parts + 1] = 'e' .. r(room.exit.min[1]) .. ',' .. r(room.exit.min[2])
    -- collision probes on a grid
    for x = -2, 30, 1.5 do for y = -6, 6, 1.5 do
        local hit = false
        for _, c in ipairs(room:solidColliders()) do
            if PlayerController.boxesOverlap({x - 0.3, y - 0.3, 0.1}, {x + 0.3, y + 0.3, 1.7}, c.min, c.max) then hit = true; break end
        end
        parts[#parts + 1] = hit and '1' or '0'
    end end
    return table.concat(parts, '|')
end

test('atmos 3.4: same level has identical geometry, plots, pickups and collisions at every quality and with the shader off', function()
    loadGame()
    local data = LevelGen.generate(4242, 2)
    local baseline
    local function build(setup)
        BackroomsLook.forceOff = false
        setup()
        local room = Room(data)
        for _ = 1, 2 do room:draw(room.spawn[1], room.spawn[2]) end
        return levelSignature(room)
    end
    local configs = {
        high = function() fakePostSetup(); BackroomsLook.setQuality('high') end,
        medium = function() fakePostSetup(); BackroomsLook.setQuality('medium') end,
        low = function() fakePostSetup(); BackroomsLook.setQuality('low') end,
        noshader = function() BackroomsLook.reset(); BackroomsLook.forceOff = true; BackroomsLook.setQuality('high') end,
        badshader = function() BackroomsLook.reset(); love.filesystem.read = function() return 'x' end
            love.graphics.newShader = function() error('bad') end end,
    }
    local order = {'high', 'medium', 'low', 'noshader', 'badshader'}
    for _, name in ipairs(order) do
        local sig = build(configs[name])
        baseline = baseline or sig
        eq(sig, baseline, name .. ' matches the high-quality level')
    end
    BackroomsLook.forceOff = false; BackroomsLook.setQuality('high')
end)

test('materials 4.1: themed boxes resolve textures through the theme; missing textures use the fallback colour', function()
    loadGame()
    local function one(theme, kind)
        local room = Room({id = 't', spawn = {0, 0, 0}, theme = theme, boxes = {{kind = kind, pos = {0, 0, 0}, size = {1, 1, 1}}},
            exit = {pos = {5, 0, 1}, size = {1, 1, 1}}, allotment = {}})
        return room.models[1], room.colliders[1].verts[1]
    end
    local m = one('level0', 'wall')
    eq(m.texture, gTextures['wall-chevron'], 'wall texture from theme')
    eq((one('level0', 'floor')).texture, gTextures['floor-carpet'], 'floor texture from theme')
    eq((one('level0', 'ceiling')).texture, gTextures['ceiling-grid'], 'ceiling texture from theme')
    eq((one('stripe', 'wall')).texture, gTextures['wall-stripe'])
    local saved = gTextures['wall-chevron']
    gTextures['wall-chevron'] = nil
    local m2, v = one('level0', 'wall')
    assert(m2.texture, 'still renders')
    local fb = MATERIAL_THEMES.level0.fallbackColor
    assert(math.abs(v[9] / v[11] - fb[1] / fb[3]) < 1e-6, 'fallback colour ratio')
    gTextures['wall-chevron'] = saved
    -- no theme: legacy look unchanged
    eq((one(nil, 'wall')).texture, gTextures['wall'])
end)

test('materials 4.2: obstacle surfaces and plots use fixed tints regardless of theme', function()
    loadGame()
    local function vert(theme)
        local room = Room({id = 't', spawn = {0, 0, 0}, plots = {{id = 'p', pos = {1, 0, 0}}}, theme = theme,
            boxes = {{kind = 'floor', obstacle = true, pos = {0, 0, 0}, size = {1, 1, 1}},
                     {kind = 'solid', obstacle = true, pos = {3, 0, 0}, size = {1, 1, 1}}},
            exit = {pos = {5, 0, 1}, size = {1, 1, 1}}, allotment = {}})
        return room.colliders[1].verts[1], room.colliders[2].verts[1], room
    end
    local f1, s1, r1 = vert('level0')
    local f2, s2 = vert('classic')
    for i = 9, 11 do eq(f1[i], f2[i], 'floor tint theme-independent'); eq(s1[i], s2[i], 'solid tint theme-independent') end
    local oc = ROOM_OBSTACLE_COLORS.floor
    assert(math.abs(f1[9] / f1[11] - oc[1] / oc[3]) < 1e-6, 'floor obstacle tint')
    assert(f1[11] ~= s1[11] or f1[9] ~= s1[9])
    assert(r1.plots[1].model, 'plot built')
end)

test('materials 4.3: themes are deterministic per seed, vary within a level, and leave layout unchanged', function()
    loadGame()
    for d = 1, #LEVELGEN_DIFFICULTY do
        for seed = 1, 40 do
            local a, b = LevelGen.generate(seed, d), LevelGen.generate(seed, d)
            local walls, floors = {}, {}
            for i, bx in ipairs(a.boxes) do
                eq(bx.theme, b.boxes[i].theme, 'same themes for same seed')
                if bx.theme and not bx.obstacle then
                    local th = MATERIAL_THEMES[bx.theme]
                    if bx.kind == 'wall' then walls[th.wall] = true elseif bx.kind == 'floor' then floors[th.floor] = true end
                end
            end
            local nw, nf = 0, 0
            for _ in pairs(walls) do nw = nw + 1 end
            for _ in pairs(floors) do nf = nf + 1 end
            assert(nw >= 2 and nf >= 2, 'seed ' .. seed .. ' d' .. d .. ' walls ' .. nw .. ' floors ' .. nf)
        end
    end
    -- theme stream is separate: layout RNG outputs are independent of it
    local before = LevelGen.rng(99):next()
    LevelGen.generate(3, 1)
    eq(LevelGen.rng(99):next(), before)
end)

-- dressing (openspec backrooms-visual-atmosphere, section 5) ------------------
local function propsOf(data)
    local out = {}
    for _, b in ipairs(data.billboards) do if b.dressing then out[#out + 1] = b end end
    return out
end

test('dressing 5.1: catalogue is tagged and a hall and a filler room draw from different props', function()
    loadGame()
    local hall, filler = Dressing.propsFor('hall'), Dressing.propsFor('filler')
    assert(#hall > 0 and #filler > 0, 'both room types have props')
    eq(table.concat(hall, ','), table.concat(Dressing.propsFor('hall'), ','), 'selection is stable')
    assert(table.concat(hall, ',') ~= table.concat(filler, ','), 'hall and filler selections differ')
    for name, p in pairs(PROP_CATALOGUE) do
        assert(p.texture and p.height and #p.tags > 0, name .. ' fully described')
        assert(not p.solid, name .. ' is a billboard')
    end
    -- placed props respect the tags of the cell they stand in
    for seed = 1, 20 do
        local d = gen(seed, 2)
        local byKey = {}
        for _, c in ipairs(d.meta.cells) do byKey[c.cx .. ',' .. c.cy] = c end
        for _, b in ipairs(propsOf(d)) do
            local c = byKey[math.floor(b.pos[1] / 6) .. ',' .. math.floor((b.pos[2] + 3) / 6)]
            assert(c and c.kind ~= 'module', 'prop in a non-module cell')
        end
    end
end)

test('dressing 5.2: over many seeds no prop touches an exclusion zone, doorway or module', function()
    loadGame()
    local total = 0
    for d = 1, #LEVELGEN_DIFFICULTY do
        for seed = 1, 60 do
            local data = gen(seed, d)
            local zones = {}
            for _, p in ipairs(data.pickups) do zones[#zones + 1] = {p.pos[1], p.pos[2], 1.3} end
            for _, p in ipairs(data.plots) do zones[#zones + 1] = {p.pos[1], p.pos[2], 3} end
            zones[#zones + 1] = {data.exit.pos[1], data.exit.pos[2], 1.8}
            zones[#zones + 1] = {data.spawn[1], data.spawn[2], 2.2}
            local cells = {}
            for _, c in ipairs(data.meta.cells) do cells[c.cx .. ',' .. c.cy] = c end
            for _, b in ipairs(propsOf(data)) do
                total = total + 1
                for _, z in ipairs(zones) do
                    assert((b.pos[1] - z[1]) ^ 2 + (b.pos[2] - z[2]) ^ 2 >= z[3] ^ 2,
                        'prop in exclusion zone seed ' .. seed)
                end
                local cx, cy = math.floor(b.pos[1] / 6), math.floor((b.pos[2] + 3) / 6)
                assert(cells[cx .. ',' .. cy].kind ~= 'module', 'prop in a module footprint')
                -- doorway: no prop within the door span plus margin
                for e, t in pairs(data.meta.edges) do
                    if t == 'door' then
                        local ax, ay, bx, by = e:match('^(-?%d+),(-?%d+)|(-?%d+),(-?%d+)$')
                        ax, ay, bx, by = tonumber(ax), tonumber(ay), tonumber(bx), tonumber(by)
                        local dx, dy
                        if ax == bx then dx, dy = ax * 6 + 3, math.max(ay, by) * 6 - 3
                        else dx, dy = math.max(ax, bx) * 6, ay * 6 end
                        assert((b.pos[1] - dx) ^ 2 + (b.pos[2] - dy) ^ 2 >= (1.2 + 1.0) ^ 2, 'prop in a doorway')
                    end
                end
            end
        end
    end
    assert(total > 200, 'props were placed: ' .. total)
end)

test('dressing 5.3: groupings exist; concealing props are nook-only and nook doorways stay clear', function()
    loadGame()
    local any = false
    for seed = 1, 20 do
        local data = gen(seed, 2)
        assert(data.meta.dressing.groups >= 1, 'grouping in seed ' .. seed)
        any = any or data.meta.dressing.groups > 0
        -- the only props near a doorway belong to nooks (the pre-existing sacks)
        local nookDoors = 0
        for _, b in ipairs(data.billboards) do
            if not b.dressing then nookDoors = nookDoors + 1 end
        end
        eq(nookDoors, data.meta.nooks, 'concealing props = secret nooks only')
        assert(LevelGen.check(data))
    end
    assert(any)
end)

test('dressing 5.4: equal seeds give equal props; adding dressing leaves the layout unchanged', function()
    loadGame()
    local function sig(data)
        local t = {}
        for _, b in ipairs(data.billboards) do
            t[#t + 1] = string.format('%s %.3f %.3f %.3f', b.texture, b.pos[1], b.pos[2], b.pos[3])
        end
        return table.concat(t, ';')
    end
    local function layout(data)
        local t = {}
        for _, b in ipairs(data.boxes) do t[#t + 1] = table.concat(b.pos, ',') .. table.concat(b.size, ',') end
        for _, p in ipairs(data.pickups) do t[#t + 1] = table.concat(p.pos, ',') .. p.seed end
        for _, p in ipairs(data.plots) do t[#t + 1] = table.concat(p.pos, ',') end
        t[#t + 1] = table.concat(data.exit.pos, ',')
        return table.concat(t, '|')
    end
    for seed = 1, 15 do
        eq(sig(gen(seed, 2)), sig(gen(seed, 2)), 'same seed, same props')
    end
    assert(sig(gen(1, 2)) ~= sig(gen(2, 2)), 'different seeds differ')
    local real = Dressing.apply
    for seed = 1, 15 do
        local with = layout(gen(seed, 3))
        Dressing.apply = function(data) return data end
        local without = layout(gen(seed, 3))
        Dressing.apply = real
        eq(with, without, 'layout identical without dressing, seed ' .. seed)
    end
end)

test('dressing review: props never use the seed-bag/sacks look, stay small and sparse, and the baseboard is render-only', function()
    loadGame()
    local n, levels = 0, 0
    for seed = 1, 30 do
        local d = gen(seed, 2)
        levels = levels + 1
        for _, b in ipairs(propsOf(d)) do
            n = n + 1
            assert(b.texture ~= 'sacks' and not tostring(b.texture):find('seedbag'), 'prop looks like a seed bag: ' .. b.prop)
            assert(b.height <= 1.0, 'prop is small')
        end
        assert(#propsOf(d) <= #d.meta.cells, 'at most ~1 prop per cell on average')
    end
    assert(n / levels >= 3, 'still dressed: ' .. n / levels .. ' props/level')
    -- baseboard adds one non-colliding model and no colliders
    local data = gen(3, 2)
    local colliders = 0
    local room = Room(data)
    for _ in ipairs(room.colliders) do colliders = colliders + 1 end
    local solidBoxes = 0
    for _, b in ipairs(data.boxes) do if b.collide ~= false then solidBoxes = solidBoxes + 1 end end
    eq(colliders, solidBoxes, 'baseboard adds no colliders')
    -- pit rims render as several void parts instead of one model, so models >= boxes + baseboard
    assert(#room.models >= #data.boxes + 1, 'one merged baseboard model on top of the boxes')
end)

realPrint(string.format('\n%d passed, %d failed', passed, failed))
os.exit(failed == 0 and 0 or 1)
