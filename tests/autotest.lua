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

local function shot(name)
    pendingShots[#pendingShots + 1] = name
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
    local silent, totalSounds = 0, 0
    for _, s in pairs(gSounds) do
        totalSounds = totalSounds + 1
        if Assets.isPlaceholder(s) then silent = silent + 1 end
    end
    log('sounds: %d of %d are silent placeholders', silent, totalSounds)
    check(silent == missingSounds, 'every missing sound is a silent placeholder (%d)', silent)
    shot('01-start')
    press('return')
    check(is(FarmState), 'Enter -> farm')
    local farm = state()
    wait(0.3)
    shot('02-farm')

    -- plant on the plot above the start tile (3,5), wait, harvest
    local seedsBefore = Farm.totalSeeds(farm.gameData)
    press('e')
    check(Farm.totalSeeds(farm.gameData) == seedsBefore - 1, 'farm: planting used one seed (%d -> %d)',
        seedsBefore, Farm.totalSeeds(farm.gameData))
    wait(FARM_STAGE_TIME * (FARM_GROWTH_STAGES - 1) + 0.5)
    shot('03-farm-grown')
    press('e')
    check(Farm.totalCrops(farm.gameData) == 1, 'farm: harvest adds one crop')

    -- walk to the tile below the villager (8,5) and face up
    for _ = 1, 5 do press('right'); wait(0.05) end
    press('up')
    check(farm.player.col == 8 and farm.player.row == 5, 'farm: walked to (8,5), at (%d,%d)', farm.player.col, farm.player.row)
    press('up')        -- villager tile is not walkable: turns to face it
    press('e')
    check(farm.gameData.coins > 0 and farm.gameData.hasSold, 'farm: sold a crop for %d coins', farm.gameData.coins)
    wait(0.3)
    shot('04-farm-sold')

    -- over-sell -> break
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
    shot('06-room1-arrival')

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
    if (back.gameData.seeds.pumpkin or 0) > 0 then
        local pk = back.gameData.seeds.pumpkin
        press('2'); press('e')
        check(back.gameData.seeds.pumpkin == pk, 'room 1: demo plot refuses a pumpkin (msg: %s)',
            back.message and back.message.text or '')
    end
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
    shot('09-room2-arrival')

    -- Room 2: wrong type in the pit, then reset, then the right solution
    p = back.player
    holdUntil('w', function() return p.x > -4.5 end, 3)
    check(back:targetPlot() and back:targetPlot().id == 'pit', 'room 2: pit plot in range from the rim (x=%.2f)', p.x)
    press('3'); press('e')
    check(back.gameData.seeds.vine == 1, 'room 2: wrong seed (vine) planted in the pit')
    wait(CROP_DEFS.vine.growTime + 0.3)
    holdUntil('w', function() return p.x > -1.4 or p.z < -0.3 end, 3)
    wait(0.5)
    check(p.x < -4, 'room 2: a vine in the pit does not get you across (fell and respawned, x=%.2f)', p.x)
    press('r')
    check(seeds() == FormatSeeds({pumpkin = 2, vine = 2}) and #back.room.crops == 0, 'room 2: R restores seeds and clears crops')
    holdUntil('w', function() return p.x > -4.5 end, 3)
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
    shot('12-room3-arrival')

    -- Room 3: pumpkin, beanstalk, vine
    p = back.player
    holdUntil('w', function() return p.x > -6.4 end, 3)
    press('2'); press('e')
    check(back.room:plotById('pit').crop ~= nil, 'room 3: pumpkin planted in the pit')
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
        love.draw()
        for _, name in ipairs(pendingShots) do
            love.graphics.captureScreenshot(function(data) analyse(name, data) end)
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
