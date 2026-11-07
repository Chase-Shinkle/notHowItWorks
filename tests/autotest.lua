-- Headless integration playthrough on the real LÖVE runtime (real LuaJIT,
-- real g3d shaders/meshes, real push canvas, real window depth buffer).
-- Loaded only by `love . --autotest` (see the end of main.lua). Under Xvfb:
--
--   xvfb-run -a -s '-screen 0 1024x1024x24' love . --autotest
--   xvfb-run -a -s '-screen 0 1024x1024x24' love . --autotest --placeholder-assets
--
-- Input is injected through the game's own handlers (love.keypressed,
-- love.mousepressed, love.mousemoved) plus a held-key overlay on
-- love.keyboard.isDown; the game code is never short-cut. The script only
-- reads state (positions, seeds, current state) to decide when to stop
-- holding a key and to assert results. The simulation runs at a fixed
-- 1/60 s step and every frame is drawn and presented.
--
-- Screenshots are written to $AUTOTEST_OUT (default /tmp/autotest) and every
-- one is checked to not be blank and not be LÖVE's blue error screen.
-- Exit code 0 = all checks passed; 1 = a check failed or an error was raised.

local DT = 1 / 60
local OUT = os.getenv('AUTOTEST_OUT') or '/tmp/autotest'
os.execute('mkdir -p "' .. OUT .. '"')
io.stdout:setvbuf('line')

local held = {}
local realIsDown = love.keyboard.isDown
love.keyboard.isDown = function(...)
    for i = 1, select('#', ...) do
        if held[select(i, ...)] then return true end
    end
    return realIsDown(...)
end

-- Text drawn in the last frame (love.graphics.print / printf), to check that
-- no debug text reaches the screen unless --debug is given.
local frameTexts, lastFrameTexts = {}, {}
for _, fname in ipairs({'print', 'printf'}) do
    local real = love.graphics[fname]
    love.graphics[fname] = function(text, ...)
        if type(text) == 'string' then frameTexts[#frameTexts + 1] = text end
        return real(text, ...)
    end
end
local function debugTextOnScreen()
    for _, t in ipairs(lastFrameTexts) do
        if t:find('debug', 1, true) or t:find('fps', 1, true) or t == DEBUG_ADVANCE_KEY then return t end
    end
    return nil
end
local debugFlag = false
for _, a in ipairs(arg or {}) do if a == '--debug' then debugFlag = true end end

local checks, failures = 0, 0
local frame = 0
local pendingShots = {}

local function log(fmt, ...) print(string.format('[autotest] ' .. fmt, ...)) end

local function check(cond, fmt, ...)
    checks = checks + 1
    local msg = string.format(fmt, ...)
    if cond then log('ok   %s', msg)
    else failures = failures + 1; log('FAIL %s', msg) end
    return cond
end

-- Coroutine helpers (the script yields once per frame) -------------------------

local function frames(n) for _ = 1, n do coroutine.yield() end end
local function wait(seconds) frames(math.floor(seconds / DT + 0.5)) end
local function press(key)
    love.keypressed(key, key, false)
    coroutine.yield()
end
local function click(button)
    local x, y = love.graphics.getWidth() / 2, love.graphics.getHeight() / 2
    love.mousepressed(x, y, button or 1, false, 1)
    coroutine.yield()
end
-- Hold `key` until cond() or `seconds` pass; returns cond().
local function holdUntil(key, cond, seconds)
    held[key] = true
    local n = 0
    while not cond() and n < seconds / DT do coroutine.yield(); n = n + 1 end
    held[key] = nil
    coroutine.yield()
    return cond()
end
local function state() return gStateMachine.current end
local function is(cls) return state() and state().update == cls.update end
local function seeds() return FormatSeeds(state().gameData.seeds) end

-- Screenshot checks: LÖVE's error screen fills with (89, 157, 220).
local function analyse(name, data)
    local w, h = data:getDimensions()
    local total, dark, errBlue = 0, 0, 0
    local colors = {}
    local ncolors = 0
    for y = 0, h - 1, 2 do
        for x = 0, w - 1, 2 do
            local r, g, b = data:getPixel(x, y)
            total = total + 1
            if r + g + b < 0.06 then dark = dark + 1 end
            if math.abs(r - 89 / 255) < 0.02 and math.abs(g - 157 / 255) < 0.02 and math.abs(b - 220 / 255) < 0.02 then
                errBlue = errBlue + 1
            end
            local key = math.floor(r * 15) * 256 + math.floor(g * 15) * 16 + math.floor(b * 15)
            if not colors[key] then colors[key] = true; ncolors = ncolors + 1 end
        end
    end
    local file = OUT .. '/' .. name .. '.png'
    local f = io.open(file, 'wb')
    if f then f:write(data:encode('png'):getString()); f:close() end
    check(errBlue / total < 0.3, 'screenshot %s: not the error screen (%.0f%% error blue)', name, 100 * errBlue / total)
    -- text-only screens (start, ending) are ~99% black, so "not blank" means
    -- several colours and at least 0.2% lit pixels
    check(ncolors >= 3 and dark / total < 0.998, 'screenshot %s: not blank (%d colours, %.2f%% lit) -> %s',
        name, ncolors, 100 * (1 - dark / total), file)
end

-- Saves a nearest-scaled close-up of the screenshot region {x, y, w, h}
-- (window pixels) as <name>-zoom.png, to inspect sprite and text edges.
local function saveZoom(name, data, crop)
    local x0, y0, w, h, s = crop[1], crop[2], crop[3], crop[4], crop[5] or 4
    local dw, dh = data:getDimensions()
    w, h = math.min(w, dw - x0), math.min(h, dh - y0)
    local zoom = love.image.newImageData(w * s, h * s)
    zoom:mapPixel(function(x, y)
        return data:getPixel(x0 + math.floor(x / s), y0 + math.floor(y / s))
    end)
    local f = io.open(OUT .. '/' .. name .. '-zoom.png', 'wb')
    if f then f:write(zoom:encode('png'):getString()); f:close() end
    log('close-up %s-zoom.png (%d,%d %dx%d x%d)', name, x0, y0, w, h, s)
end

-- `crop` (optional) {x, y, w, h, scale}: also save a close-up (saveZoom).
local function shot(name, crop)
    pendingShots[#pendingShots + 1] = {name = name, crop = crop}
    coroutine.yield()     -- captured at the end of this frame's draw
    coroutine.yield()     -- callback has run after present
end

-- The playthrough -----------------------------------------------------------------

local function script()
    wait(0.5)
    check(state().update == StartState.update, 'boots into the start state')

    -- asset integration (task 6.1): with real assets every texture used by
    -- the game is the supplied art; sounds that are missing are reported as
    -- silent placeholders instead of failing
    local missingImages, missingSounds = {}, 0
    for _, m in ipairs(Assets.missing) do
        if m.kind == 'image' then missingImages[#missingImages + 1] = m.path end
        if m.kind == 'sound' then missingSounds = missingSounds + 1 end
    end
    if Assets.forcePlaceholders then
        check(#missingImages > 0 and Assets.isPlaceholder(gTextures['wall']), 'placeholder mode: textures are flat fallbacks')
    else
        check(#missingImages == 0, 'every texture loaded from real art (missing: %s)', table.concat(missingImages, ', '))
        for _, key in ipairs({'wall', 'floor', 'ceiling', 'grass', 'hero', 'villager', 'plot', 'well'}) do
            check(gTextures[key] and not Assets.isPlaceholder(gTextures[key]), 'real texture: %s', key)
        end
    end
    -- pixel-art filtering (polish M1), on the real runtime: sprites, tiles,
    -- billboards and fonts are nearest; real backrooms surfaces are linear
    -- (placeholders for them stay nearest)
    local function filterOf(obj) local a, b = obj:getFilter(); return a .. '/' .. b end
    for _, key in ipairs({'hero', 'crop-beanstalk-3', 'crop-pumpkin-5', 'plot', 'well', 'bucket',
            'villager', 'grass', 'soil', 'seedbag-vine', 'produce-pumpkin'}) do
        check(filterOf(gTextures[key]) == 'nearest/nearest', 'filter %s: %s', key, filterOf(gTextures[key]))
    end
    for _, key in ipairs({'default', 'small'}) do
        check(filterOf(gFonts[key]) == 'nearest/nearest', 'filter font %s: %s', key, filterOf(gFonts[key]))
    end
    for _, key in ipairs(SMOOTH_SURFACE_TEXTURES) do
        local want = Assets.isPlaceholder(gTextures[key]) and 'nearest/nearest' or 'linear/linear'
        check(filterOf(gTextures[key]) == want, 'filter surface %s: %s (want %s, mipmaps %d)', key,
            filterOf(gTextures[key]), want, gTextures[key]:getMipmapCount())
    end

    local silent, totalSounds = 0, 0
    for _, s in pairs(gSounds) do
        totalSounds = totalSounds + 1
        if Assets.isPlaceholder(s) then silent = silent + 1 end
    end
    log('sounds: %d of %d are silent placeholders', silent, totalSounds)
    check(silent == missingSounds, 'every missing sound is a silent placeholder (%d)', silent)
    -- release config (polish M2): debug mode only with --debug
    check(DEBUG_MODE == debugFlag, 'debug mode %s (--debug %s)', tostring(DEBUG_MODE), tostring(debugFlag))
    if not debugFlag then
        press('f1'); press('f1')
        check(is(StartState), 'release: F1 does nothing at the start screen')
    end
    shot('01-start')
    press('return')
    check(is(FarmState), 'Enter -> farm')
    local farm = state()
    wait(0.3)
    shot('02-farm', {0, 0, 400, 250, 3})        -- HUD text, seed bags, hero, plots
    if not debugFlag then
        press('f1')
        check(state() == farm, 'release: F1 does nothing on the farm')
        check(debugTextOnScreen() == nil, 'release: no debug text on the farm HUD (%s)', tostring(debugTextOnScreen()))
    else
        check(debugTextOnScreen() ~= nil, 'debug: F1 marker on the farm HUD')
    end

    -- till, plant and water the plot above the start tile (3,5), wait, harvest
    local seedsBefore = Farm.totalSeeds(farm.gameData)
    local firstPlot = farm:plotAt(3, 5)
    check(farm:hintText() == '[E] till the soil (shovel)', 'farm: first hint is till (%s)', farm:hintText())
    press('e')
    check(firstPlot.tilled and Farm.totalSeeds(farm.gameData) == seedsBefore, 'farm: first use tills, no seed used')
    press('e')
    check(Farm.totalSeeds(farm.gameData) == seedsBefore - 1, 'farm: planting used one seed (%d -> %d)',
        seedsBefore, Farm.totalSeeds(farm.gameData))
    press('e')
    check(firstPlot.watered, 'farm: third use waters the crop')
    wait(Farm.growthTime(true) + 0.5)
    shot('03-farm-grown')
    press('e')
    check(Farm.totalCrops(farm.gameData) == 1, 'farm: harvest adds one crop')
    -- the harvested crop flies to its HUD slot; the count is already right
    check(#farm.juice.flyers == 1, 'farm: harvest launches one flying crop to the HUD (%d)', #farm.juice.flyers)
    wait(FX_FLY_TIME + 0.1)
    check(#farm.juice.flyers == 0, 'farm: the flying crop landed in its slot')
    -- the look pipeline runs on the real runtime unless turned off
    local noShader = false
    for _, a in ipairs(arg or {}) do if a == '--no-shader' then noShader = true end end
    check(FarmShader.enabled == not noShader, 'farm: look pipeline %s (%s)',
        FarmShader.enabled and 'enabled' or 'off', tostring(FarmShader.reason))

    -- walk to the tile below the villager (8,5) and face up
    for _ = 1, 5 do press('right'); wait(0.05) end
    press('up')
    check(farm.player.col == 8 and farm.player.row == 5, 'farm: walked to (8,5), at (%d,%d)', farm.player.col, farm.player.row)
    press('up')        -- villager tile is not walkable: turns to face it
    press('e')
    check(farm.gameData.coins > 0 and farm.gameData.hasSold, 'farm: sold a crop for %d coins', farm.gameData.coins)
    wait(0.3)
    shot('04-farm-sold')

    -- seed stall (polish M4): buy by mouse, a keyboard denial, plant the bought seed
    local coins, beans = farm.gameData.coins, farm.gameData.seeds.beanstalk
    local idleBefore = farm.idleTimer
    press('down')                                -- (8,6), facing the stall at (8,7)
    check(farm:facingTarget() and farm:facingTarget().kind == 'shop', 'farm: facing the seed stall')
    check(farm:hintText() == '[E] buy beanstalk seed (2c)', 'farm: stall hint shows type and price (%s)', farm:hintText())
    local sx, sy = FarmTileToPixel(FARM_SHOP.col, FARM_SHOP.row)
    -- push:toReal ignores the scale (marked TODO in lib/push.lua); invert toGame
    local rx = push._OFFSET.x + (sx + FARM_TILE / 2) * push._GWIDTH / push._WWIDTH
    local ry = push._OFFSET.y + (sy + FARM_TILE / 2) * push._GHEIGHT / push._WHEIGHT
    love.mouse.setPosition(rx, ry)
    coroutine.yield()
    check(farm.hover and farm.hover.col == FARM_SHOP.col and farm.hover.row == FARM_SHOP.row,
        'farm: mouse hovers the stall')
    love.mousepressed(rx, ry, 1, false, 1); coroutine.yield()
    check(farm.gameData.coins == coins - SEED_PRICES.beanstalk and farm.gameData.seeds.beanstalk == beans + 1,
        'farm: click bought a beanstalk seed (coins %d -> %d)', coins, farm.gameData.coins)
    wait(0.2)
    shot('04b-farm-stall', {450, 375, 300, 180, 3})
    press('e')
    check(farm.gameData.coins == coins - SEED_PRICES.beanstalk and farm.gameData.seeds.beanstalk == beans + 1,
        'farm: E with %d coin(s) is refused', farm.gameData.coins)
    check(farm.idleTimer >= idleBefore, 'farm: buying left the idle break timer running (%.2f s)', farm.idleTimer)
    love.mouse.setPosition(5, 5)
    -- walk along the path to below plot (4,5) and plant the bought seed
    -- (the fence flanks the plots, so it is reached from below)
    for _ = 1, 4 do press('left'); wait(0.05) end
    press('up')                                  -- plot (4,5) blocks: turns to face it
    local seedsNow = farm.gameData.seeds.beanstalk
    press('e')                                   -- till
    press('e')                                   -- plant
    check(farm.gameData.seeds.beanstalk == seedsNow - 1 and farm:plotAt(4, 5).state == PLOT_GROWING,
        'farm: planted the bought beanstalk seed on (4,5)')
    -- back to the villager
    for _ = 1, 4 do press('right'); wait(0.05) end
    press('up'); wait(0.05)
    press('up')
    check(farm.player.col == 8 and farm.player.row == 5 and farm:facingTarget().kind == 'villager',
        'farm: back facing the villager at (%d,%d)', farm.player.col, farm.player.row)

    -- over-sell -> break
    -- day counter: day 1 so far; the clock is moved (setup) to 1 s before
    -- the next dawn, and one real second of play turns it to day 2
    check(farm:dayNumber() == 1, 'farm: still day %d after the first loop', farm:dayNumber())
    farm.dayTime = FARM_DAY_LENGTH - 1
    wait(1.2)
    check(farm:dayNumber() == 2, 'farm: the day counter goes up at dawn (day %d)', farm:dayNumber())
    local farmSeeds = FormatSeeds(farm.gameData.seeds)
    press('e')
    check(farm.breaking == true, 'farm: over-sell starts the break')
    wait(0.8)
    shot('05-break-glitch')
    press('e'); press('f1')                      -- ignored while breaking
    check(is(FarmState), 'break ignores input')
    wait(FARM_BREAK_GLITCH_TIME + FARM_BREAK_FALL_TIME)
    check(is(BackroomsState), 'break ends in the backrooms')
    local back = state()
    check(back.gameData.coins == nil or back.gameData.coins == 0, 'no coins carried (%s)', tostring(back.gameData.coins))
    log('farm seeds at break: %s; backrooms room 1 seeds: %s', farmSeeds, seeds())
    check(back.roomIndex == 1 and (back.gameData.seeds.beanstalk or 0) >= 1, 'room 1 with at least one beanstalk')
    wait(0.3)
    check(Billboard.getAlphaShader() ~= nil, 'billboard alpha-discard shader compiled (no fallback)')
    shot('06-room1-arrival', {0, 0, 400, 70, 3}) -- Room 1 HUD text and seed list
    -- Room 1 HUD (polish M4): only beanstalk is listed, even with farm pumpkins
    -- and vines carried over, and no coins
    local hudText = table.concat(lastFrameTexts, ' | ')
    check(hudText:find('beanstalk x', 1, true) ~= nil and not hudText:find('pumpkin', 1, true)
        and not hudText:find('vine', 1, true) and not hudText:find('corn', 1, true) and not hudText:find('%dc%f[%W]'),
        'room 1 HUD lists beanstalk only and no coins (seeds held: %s; HUD: %s)', seeds(), hudText)
    if not debugFlag then
        press('f1')
        check(state() == back and back.roomIndex == 1, 'release: F1 does not skip room 1')
        check(debugTextOnScreen() == nil, 'release: no debug text on the backrooms HUD (%s)', tostring(debugTextOnScreen()))
    else
        check(debugTextOnScreen() ~= nil, 'debug: debug line on the backrooms HUD (%s)', tostring(debugTextOnScreen()))
    end

    -- mouse look: turn right then back
    local d0 = g3d.camera.getDirectionPitch()
    love.mousemoved(400, 400, 150, 0); coroutine.yield()
    local d1 = g3d.camera.getDirectionPitch()
    check(math.abs((d0 - d1) - 0.5) < 1e-6, 'mouse look turns (%.3f -> %.3f)', d0, d1)
    shot('07-room1-look-right')
    love.mousemoved(400, 400, -150, 0); coroutine.yield()
    check(math.abs(g3d.camera.getDirectionPitch() - d0) < 1e-6, 'mouse look returns')

    -- Esc frees the mouse; a click recaptures (and does not plant)
    press('escape')
    check(back.mouseCaptured == false, 'Esc frees the mouse')
    local before = seeds()
    click(1)
    check(back.mouseCaptured == true and seeds() == before, 'click recaptures without planting')

    -- Room 1: walk to the ledge face (through the unfinished demo beanstalk)
    local p = back.player
    holdUntil('w', function() return p.x > 1.65 end, 3)
    wait(0.2)
    log('room 1 at ledge face x=%.2f z=%.2f, target plot %s', p.x, p.z, tostring(back:targetPlot() and back:targetPlot().id))
    check(back:targetPlot() and back:targetPlot().id == 'demo', 'room 1: demo plot in range at the ledge face')
    -- climbing an unfinished demo does nothing
    holdUntil('w', function() return p.z > 0.2 end, 1)
    check(p.z < 0.05, 'room 1: half-grown demo is not climbable (z=%.2f)', p.z)
    -- room 1 uses only beanstalk: the keys for the carried pumpkin/vine seeds
    -- do nothing (polish M4), so they cannot even be tried on the demo plot
    press('2'); press('3'); press('q')
    check(back.selectedSeed == 'beanstalk', 'room 1: pumpkin/vine keys and Q leave beanstalk selected (%s)',
        back.selectedSeed)
    press('1'); press('e')
    check(back.room:plotById('demo').crop.timer ~= nil, 'room 1: beanstalk seed resumes the demo growth')
    wait(0.6)
    shot('08-room1-growing')
    wait(CROP_DEFS.beanstalk.growTime)
    check(back.room:plotById('demo').crop.grown, 'room 1: demo fully grown')
    local reached = holdUntil('w', function() return back.roomIndex == 2 end, 8)
    check(reached, 'room 1: climb the beanstalk and walk to the exit -> room 2')
    check(seeds() == FormatSeeds({pumpkin = 2, vine = 2}), 'room 2 allotment: %s', seeds())
    wait(0.3)
    shot('09-room2-arrival', {290, 380, 120, 80, 5}) -- billboard sprite edges
    hudText = table.concat(lastFrameTexts, ' | ')
    check(hudText:find('pumpkin x', 1, true) and hudText:find('corn x', 1, true) and not hudText:find('beanstalk', 1, true)
        and not hudText:find('vine', 1, true), 'room 2 HUD lists pumpkin and vine (as corn) only (%s)', hudText)

    -- Room 2: wrong type in the pit, then reset, then the right solution
    p = back.player
    local function pitTargeted() local t = back:targetPlot(); return t ~= nil and t.id == 'pit' end
    holdUntil('w', pitTargeted, 3)
    check(pitTargeted() and p.x < -5.5 and math.abs(p.z) < 0.05,
        'room 2: pit plot in range from well back on the floor (x=%.2f, %.2f m from the rim)', p.x, -4 - p.x)
    shot('09b-room2-pit-prompt', {200, 400, 400, 120, 2})
    press('3'); press('e')
    check(back.gameData.seeds.vine == 1, 'room 2: wrong seed (vine) planted in the pit')
    wait(CROP_DEFS.vine.growTime + 0.3)
    holdUntil('w', function() return p.x > -1.4 or p.z < -0.3 end, 3)
    wait(0.5)
    check(p.x < -4, 'room 2: a vine in the pit does not get you across (fell and respawned, x=%.2f)', p.x)
    press('r')
    check(seeds() == FormatSeeds({pumpkin = 2, vine = 2}) and #back.room.crops == 0, 'room 2: R restores seeds and clears crops')
    holdUntil('w', pitTargeted, 3)
    check(p.x < -5.5, 'room 2: after the reset, planting the pumpkin from x=%.2f', p.x)
    press('2'); press('e')
    wait(CROP_DEFS.pumpkin.growTime + 0.3)
    shot('10-room2-pumpkin')
    holdUntil('w', function() return p.x > 0.8 end, 4)
    check(math.abs(p.z) < 0.05, 'room 2: walked over the pumpkin at floor level (z=%.2f)', p.z)
    check(back:targetPlot() and back:targetPlot().id == 'edge', 'room 2: edge plot in range')
    press('3'); press('e')
    wait(CROP_DEFS.vine.growTime + 0.3)
    shot('11-room2-vine')
    reached = holdUntil('w', function() return back.roomIndex == 3 end, 6)
    check(reached, 'room 2: cross the vine to the exit -> room 3')
    check(seeds() == FormatSeeds({beanstalk = 2, pumpkin = 2, vine = 2}), 'room 3 allotment: %s', seeds())
    wait(0.3)
    shot('12-room3-arrival', {0, 0, 450, 70, 3})
    hudText = table.concat(lastFrameTexts, ' | ')
    check(hudText:find('beanstalk x', 1, true) and hudText:find('pumpkin x', 1, true) and hudText:find('corn x', 1, true),
        'room 3 HUD lists all three types (%s)', hudText)

    -- Room 3: pumpkin, beanstalk, vine
    p = back.player
    holdUntil('w', function() return p.x > -7.6 end, 3)     -- ~1.6 m back from the rim at x = -6
    press('2'); press('e')
    check(back.room:plotById('pit').crop ~= nil, 'room 3: pumpkin planted in the pit from x=%.2f (%.2f m from the rim)',
        p.x, -6 - p.x)
    wait(CROP_DEFS.pumpkin.growTime + 0.3)
    holdUntil('w', function() return p.x > -1.35 end, 4)
    wait(0.2)
    check(back:targetPlot() and back:targetPlot().id == 'foot', 'room 3: foot plot in range at the ledge (x=%.2f)', p.x)
    press('1'); press('e')
    wait(CROP_DEFS.beanstalk.growTime + 0.3)
    shot('13-room3-beanstalk')
    holdUntil('w', function() return p.x > 0.8 and p.z > 2.5 end, 6)
    check(p.z > 2.5 and p.z < 2.7, 'room 3: climbed onto the ledge (x=%.2f z=%.2f)', p.x, p.z)
    check(back:targetPlot() and back:targetPlot().id == 'lip', 'room 3: lip plot in range on the ledge')
    press('3'); press('e')
    wait(CROP_DEFS.vine.growTime + 0.3)
    shot('14-room3-vine')
    reached = holdUntil('w', function() return is(EndingState) end, 6)
    check(reached, 'room 3: cross the vine to the exit -> ending')
    wait(0.8)
    shot('15-ending')
    press('return')
    check(state().update == StartState.update, 'ending: Enter returns to start')
    wait(0.2)

    -- window resize keeps both render paths working
    love.window.setMode(640, 480, {resizable = true, depth = 24, vsync = 0})
    love.resize(640, 480)
    wait(0.1)
    shot('16-start-resized')
    -- the F1 skip is a debug feature: this check opts in explicitly
    DEBUG_MODE = true
    press('f1'); press('f1')
    check(is(BackroomsState), 'F1 x2: start -> farm -> backrooms after resize')
    wait(0.3)
    shot('17-room1-resized')
end

-- Fixed-step main loop ------------------------------------------------------------

function love.run()
    if love.load then love.load(love.arg.parseGameArguments(arg), arg) end
    if love.timer then love.timer.step() end
    local major, minor = love.getVersion()
    log('LÖVE %d.%d, %s; renderer: %s', major, minor, (jit and jit.version or _VERSION),
        table.concat({love.graphics.getRendererInfo()}, ' / '))
    local co = coroutine.create(script)
    return function()
        love.event.pump()
        love.timer.step()
        for name in love.event.poll() do
            if name == 'quit' then return 1 end
        end
        frame = frame + 1
        local ok, err = coroutine.resume(co)
        if not ok then
            log('ERROR in script: %s', debug.traceback(co, tostring(err)))
            return 1
        end
        love.update(DT)
        love.graphics.origin()
        love.graphics.clear(love.graphics.getBackgroundColor())
        frameTexts = {}
        love.draw()
        lastFrameTexts = frameTexts
        for _, pending in ipairs(pendingShots) do
            love.graphics.captureScreenshot(function(data)
                analyse(pending.name, data)
                if pending.crop then saveZoom(pending.name, data, pending.crop) end
            end)
        end
        pendingShots = {}
        love.graphics.present()
        if coroutine.status(co) == 'dead' then
            log('%d checks, %d failed, %d frames (%.1f s simulated)', checks, failures, frame, frame * DT)
            return failures == 0 and 0 or 1
        end
    end
end

-- Any uncaught error (the normal LÖVE blue error screen) fails the run.
function love.errorhandler(msg)
    print('[autotest] ERROR: ' .. debug.traceback(tostring(msg), 2))
    os.exit(1)
end
