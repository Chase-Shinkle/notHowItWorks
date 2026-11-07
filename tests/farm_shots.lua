-- Reviewer screenshots of the farm on the real LÖVE runtime (real push canvas,
-- real fonts, real shaders). Loaded only by `love . --farm-shots` (see the end
-- of main.lua); never packaged. Under Xvfb, from the repo root:
--
--   SHOTS_OUT=/workspace/qa/farmfeel xvfb-run -a -s '-screen 0 1024x1024x24' love . --farm-shots
--   (add --no-shader for the shader-off set, --placeholder-assets for fallbacks)
--
-- Test setup (documented in verification.md): each scene starts a fresh farm
-- with gStateMachine:change('farm', NewGameData(...)), then drives it with the
-- game's own input handlers (love.keypressed) and real frame updates; where a
-- scene needs a state that would take long to reach by play (three-digit
-- counts, a given time of day, a mature crop), the script sets that state on
-- the farm directly and says so in the log line for the shot. Every capture
-- is a real love.graphics.captureScreenshot of the presented frame (800x800
-- window), and close-ups are nearest-neighbour crops of that capture.
-- Shot names may carry a suffix (SHOTS_SUFFIX, e.g. '-shader-off').

local DT = 1 / 60
local OUT = os.getenv('SHOTS_OUT') or '/tmp/farm-shots'
local SUFFIX = os.getenv('SHOTS_SUFFIX') or ''
local ONLY = os.getenv('SHOTS_ONLY')            -- optional: comma list of scene names
os.execute('mkdir -p "' .. OUT .. '"')
io.stdout:setvbuf('line')

local checks, failures = 0, 0
local pending = {}
local function log(fmt, ...) print(string.format('[farm-shots] ' .. fmt, ...)) end
local function check(cond, fmt, ...)
    checks = checks + 1
    if cond then log('ok   ' .. fmt, ...) else failures = failures + 1; log('FAIL ' .. fmt, ...) end
    return cond
end

local function frames(n) for _ = 1, n do coroutine.yield() end end
local function wait(seconds) frames(math.floor(seconds / DT + 0.5)) end
local function press(key) love.keypressed(key, key, false); coroutine.yield() end

-- window-pixel rectangle of a virtual rectangle (push scale + offset)
local function toWindow(x, y, w, h)
    local sx, sy = push._SCALE.x, push._SCALE.y
    return math.floor(push._OFFSET.x + x * sx), math.floor(push._OFFSET.y + y * sy),
        math.ceil(w * sx), math.ceil(h * sy)
end

local function save(data, file)
    local f = io.open(file, 'wb')
    if f then f:write(data:encode('png'):getString()); f:close() end
end

local function zoom(data, crop)
    local x0, y0, w, h, s = crop[1], crop[2], crop[3], crop[4], crop[5] or 3
    local dw, dh = data:getDimensions()
    w, h = math.min(w, dw - x0), math.min(h, dh - y0)
    local z = love.image.newImageData(w * s, h * s)
    z:mapPixel(function(x, y) return data:getPixel(x0 + math.floor(x / s), y0 + math.floor(y / s)) end)
    return z
end

-- Captures this frame as <name><suffix>.png; `crop` = {vx, vy, vw, vh, scale}
-- in virtual px also saves <name><suffix>-zoom.png. `note` documents setup.
local function shot(name, note, crop)
    pending[#pending + 1] = {name = name, note = note, crop = crop}
    coroutine.yield(); coroutine.yield()
end

local function onCapture(p, data)
    local file = OUT .. '/' .. p.name .. SUFFIX .. '.png'
    save(data, file)
    -- not blank / not the error screen
    local w, h = data:getDimensions()
    local colors, n, errBlue, total = {}, 0, 0, 0
    for y = 0, h - 1, 4 do
        for x = 0, w - 1, 4 do
            local r, g, b = data:getPixel(x, y)
            total = total + 1
            if math.abs(r - 89 / 255) < 0.02 and math.abs(g - 157 / 255) < 0.02 and math.abs(b - 220 / 255) < 0.02 then
                errBlue = errBlue + 1
            end
            local k = math.floor(r * 15) * 256 + math.floor(g * 15) * 16 + math.floor(b * 15)
            if not colors[k] then colors[k] = true; n = n + 1 end
        end
    end
    check(n >= 8 and errBlue / total < 0.3, 'shot %s%s: %d colours -> %s (%s)', p.name, SUFFIX, n, file, p.note)
    if p.crop then
        local x, y, cw, ch = toWindow(p.crop[1], p.crop[2], p.crop[3], p.crop[4])
        save(zoom(data, {x, y, cw, ch, p.crop[5]}), OUT .. '/' .. p.name .. SUFFIX .. '-zoom.png')
    end
end

local function newFarm(overrides)
    gStateMachine:change('farm', NewGameData(overrides))
    local farm = gStateMachine.current
    love.mouse.setPosition(0, 799)               -- keep the hover off the field
    return farm
end

local function face(farm, col, row, facing)
    farm.player.col, farm.player.row, farm.player.facing = col, row, facing
    farm.player.drawX, farm.player.drawY = FarmTileToPixel(col, row)
end

-- Scenes ------------------------------------------------------------------------
local SCENES = {}
local function scene(name, fn) SCENES[#SCENES + 1] = {name = name, fn = fn} end

scene('villager', function()
    local farm = newFarm({crops = {pumpkin = 2}})
    face(farm, FARM_VILLAGER.col - 1, FARM_VILLAGER.row, 'right')
    wait(0.3)
    shot('villager-next-to-hero', 'farmer placed beside the villager (tile left of it), facing it',
        {(FARM_VILLAGER.col - 2) * FARM_TILE - 8, (FARM_VILLAGER.row - 2) * FARM_TILE + 8, 96, 64, 3})
    press('e')
    wait(0.1)
    shot('villager-sale-bounce', 'one real sale (E) then 0.1 s: villager mid-hop, sell burst, coin sparkles',
        {(FARM_VILLAGER.col - 2) * FARM_TILE - 8, 0, 112, 112, 3})
end)

scene('tools', function()
    local farm = newFarm()
    -- the farmer starts below plot (3,5): play till -> plant -> water by E
    local crop = {(FARM_PLAYER_START.col - 1) * FARM_TILE - 16, (FARM_PLAYER_START.row - 2) * FARM_TILE, 64, 64, 4}
    wait(0.3)
    shot('tool-1-shovel', 'fresh farm, facing the untilled plot', crop)
    press('e'); wait(0.6)
    shot('tool-2-seedbag', 'after one E (tilled)', crop)
    press('e'); wait(0.6)
    shot('tool-3-watering-can', 'after a second E (planted, unwatered)', crop)
    press('e')
    Farm.advance(farm:facingTarget().plot, 100)   -- setup: skip the 12 s wait
    wait(0.8)
    shot('tool-4-sickle', 'after a third E (watered); growth advanced to mature directly (setup)', crop)
end)

scene('hud', function()
    local farm = newFarm({seeds = {beanstalk = 999, pumpkin = 0, vine = 120}, crops = {beanstalk = 999, pumpkin = 105, vine = 0},
        coins = 999})
    farm.day = 999                                -- setup: worst-case day width
    farm:selectSeed('pumpkin')                    -- selected and empty: dimmed but outlined
    wait(0.3)
    shot('hud-three-digit-counts', 'counts, coins and day set to three digits directly (setup); pumpkin selected with 0 seeds; empty produce dimmed',
        {0, 0, VIRTUAL_WIDTH, FARM_TILE, 3})
    -- real-runtime layout check with the real font
    local L = farm:hudLayout()
    local font = gFonts['small']
    local boxes = {}
    local function add(n, x, y, w, h) boxes[#boxes + 1] = {n = n, x = x, y = y, w = w, h = h} end
    for i, r in ipairs(L.seeds) do
        add('seed icon ' .. i, r.icon.x, r.icon.y, r.icon.size, r.icon.size)
        add('seed key ' .. i, r.key.x, r.key.y, font:getWidth(tostring(i)), font:getHeight())
        add('seed count ' .. i, r.count.x, r.count.y, font:getWidth('x999'), font:getHeight())
    end
    add('divider', L.divider.x, L.divider.y, 1, L.divider.h)
    for i, r in ipairs(L.produce) do
        add('produce icon ' .. i, r.icon.x, r.icon.y, r.icon.size, r.icon.size)
        add('produce count ' .. i, r.count.x, r.count.y, font:getWidth('999'), font:getHeight())
    end
    add('coin icon', L.coinIcon.x, L.coinIcon.y, L.coinIcon.w, L.coinIcon.h)
    add('coin amount', L.coinText.x, L.coinText.y, font:getWidth('999'), font:getHeight())
    add('day', L.day.right - font:getWidth('Day 999'), L.day.y, font:getWidth('Day 999'), font:getHeight())
    local bad = {}
    for i, a in ipairs(boxes) do
        if a.x < 0 or a.x + a.w > VIRTUAL_WIDTH or a.y < 0 or a.y + a.h > FARM_TILE - 4 then bad[#bad + 1] = a.n .. ' outside the bar' end
        for j = i + 1, #boxes do
            local b = boxes[j]
            if a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h then bad[#bad + 1] = a.n .. '/' .. b.n end
        end
    end
    check(#bad == 0, 'real-font HUD layout with three-digit counts: %d elements, overlaps: %s', #boxes,
        #bad == 0 and 'none' or table.concat(bad, ', '))
end)

scene('farm-start', function()
    newFarm()
    wait(0.5)
    shot('farm-start-daylight', 'fresh farm (new game data), 0.5 s after entering, no input', nil)
end)

scene('soil', function()
    local farm = newFarm()
    -- setup: three plots of the top row put directly into the untilled,
    -- tilled-with-crop (dry) and watered-with-crop states
    local a, b, c = farm:plotAt(2, 4), farm:plotAt(3, 4), farm:plotAt(4, 4)
    b.tilled = true; Farm.plant(b, farm.gameData, 'pumpkin')
    c.tilled = true; Farm.plant(c, farm.gameData, 'pumpkin'); Farm.water(c)
    local d = farm:plotAt(2, 5); d.tilled = true
    face(farm, 6, 6, 'down')
    wait(0.5)
    shot('soil-three-looks', 'setup: row 4 = untilled | tilled+unwatered crop | watered crop; (2,5) tilled empty',
        {FARM_TILE * 0, FARM_TILE * 3 - 8, FARM_TILE * 6, FARM_TILE * 2 + 16, 3})
end)

scene('characters-data', function()
    -- the loaded villager image really differs from the hero's pixels
    local function imageData(path) return love.image.newImageData(path) end
    local ok1, v = pcall(imageData, 'graphics/characters/villager.png')
    local ok2, h = pcall(imageData, 'graphics/Farming - Crops Pack 017/Sprites/Hero  white - 001 copy.png')
    if Assets.forcePlaceholders then
        check(Assets.isPlaceholder(gTextures['villager']), 'placeholder mode: villager is a fallback')
        return
    end
    local differ = 0
    if ok1 and ok2 then
        for y = 0, math.min(v:getHeight(), h:getHeight()) - 1 do
            for x = 0, math.min(v:getWidth(), h:getWidth()) - 1 do
                local a = {v:getPixel(x, y)}; local b = {h:getPixel(x, y)}
                if a[1] ~= b[1] or a[2] ~= b[2] or a[3] ~= b[3] or a[4] ~= b[4] then differ = differ + 1 end
            end
        end
    end
    check(ok1 and ok2 and differ > 30 and not Assets.isPlaceholder(gTextures['villager']),
        'villager.png loaded as gTextures.villager and differs from the hero in %d pixels', differ)
    coroutine.yield()
end)

-- Main loop ---------------------------------------------------------------------

local function script()
    wait(0.3)
    press('return')
    for _, sc in ipairs(SCENES) do
        if not ONLY or (',' .. ONLY .. ','):find(',' .. sc.name .. ',', 1, true) then
            log('scene %s', sc.name)
            sc.fn()
        end
    end
end

function love.run()
    if love.load then love.load(love.arg.parseGameArguments(arg), arg) end
    if love.timer then love.timer.step() end
    log('LÖVE %d.%d; renderer: %s; out %s', select(1, love.getVersion()), select(2, love.getVersion()),
        table.concat({love.graphics.getRendererInfo()}, ' / '), OUT)
    local co = coroutine.create(script)
    return function()
        love.event.pump()
        love.timer.step()
        for name in love.event.poll() do if name == 'quit' then return 1 end end
        local ok, err = coroutine.resume(co)
        if not ok then log('ERROR in script: %s', debug.traceback(co, tostring(err))); return 1 end
        love.update(DT)
        love.graphics.origin()
        love.graphics.clear(love.graphics.getBackgroundColor())
        love.draw()
        for _, p in ipairs(pending) do
            love.graphics.captureScreenshot(function(data) onCapture(p, data) end)
        end
        pending = {}
        love.graphics.present()
        if coroutine.status(co) == 'dead' then
            log('%d checks, %d failed', checks, failures)
            return failures == 0 and 0 or 1
        end
    end
end

function love.errorhandler(msg)
    print('[farm-shots] ERROR: ' .. debug.traceback(tostring(msg), 2))
    os.exit(1)
end
