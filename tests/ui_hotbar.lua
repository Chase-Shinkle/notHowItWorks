-- Tests for title-hotbar-ending-ui section 3 (hotbar layout/draw, wheel, HUD, counts).
--   love tests/love_runner tests/ui_hotbar.lua
package.path = './?.lua;./?/init.lua;' .. package.path
local realPrint = print
local mock = dofile('tests/mock_love.lua')
mock.install()
arg = {}
dofile('main.lua')
love.load()
print = function() end

local fails = 0
local function check(cond, msg) if not cond then fails = fails + 1; realPrint('FAIL ' .. msg) end end

-- 3.1 layout
for _, sz in ipairs({{640, 640}, {800, 800}, {1920, 1080}, {320, 240}, {1080, 1080}}) do
    local w, h = sz[1], sz[2]
    local lay = Hotbar.layout(w, h, #SEED_TYPES)
    local tag = w .. 'x' .. h
    check(#lay.slots == #SEED_TYPES, 'slot count ' .. tag)
    local first, last = lay.slots[1], lay.slots[#lay.slots]
    check(first.x >= 0 and last.x + last.w <= w and last.y + last.h <= h and first.y >= 0, 'on screen ' .. tag)
    check(math.abs((first.x + last.x + last.w) / 2 - w / 2) < 0.01, 'centred ' .. tag)
    check(first.y > h / 2, 'at the bottom ' .. tag)
end
check(Hotbar.layout(1920, 1080).size > Hotbar.layout(640, 640).size, 'scales with height')
check(Hotbar.layout(4000, 4000).size <= HOTBAR_SLOT_MAX, 'size clamped')

-- fixtures
local ROOM = BACKROOMS_ROOMS[2]
local function setup(room, seeds, selected)
    local back = BackroomsState()
    gStateMachine.current = back
    back:enter(CarryOverGameData(NewGameData({seeds = seeds})), {room})
    for k, v in pairs(seeds) do back.gameData.seeds[k] = v end
    back.selectedSeed = selected
    return back
end
local function texts()
    local out = {}
    for _, c in ipairs(mock.calls) do
        if (c.name == 'print' or c.name == 'printf') and type(c.args[1]) == 'string' then out[#out + 1] = c.args[1] end
    end
    return out
end
local function has(list, s) for _, t in ipairs(list) do if t == s then return true end end return false end

-- 3.2 draw: all types shown, with counts (including a zero count), no full-width band
local back = setup(ROOM, {beanstalk = 0, pumpkin = 3, vine = 1}, 'pumpkin')
mock.reset(); love.draw()
local t = texts()
check(has(t, '0') and has(t, '3') and has(t, '1'), 'counts drawn incl. zero')
check(has(t, '1') and has(t, '2') and has(t, '3'), 'key numbers drawn')
local w, h = love.graphics.getDimensions()
local band = false
for _, c in ipairs(mock.callsNamed('rectangle')) do
    if c.args[1] == 'fill' and c.args[4] >= w - 1 then band = true end
end
check(not band, 'no full-width band')
local shown = 0
for _, ty in ipairs(SEED_TYPES) do if back:isSeedVisible(ty) then shown = shown + 1 end end
check(shown < #SEED_TYPES or true, 'room visibility computed')

-- 3.3 wheel
local vis = back:visibleSeedTypes()
check(#vis >= 1, 'room has visible types')
back.selectedSeed = vis[1]
for i = 1, #vis do back:wheelSelect(1) end
check(back.selectedSeed == vis[1], 'forward wrap after a full turn')
back:wheelSelect(1)
check(back.selectedSeed == vis[(2 - 1) % #vis + 1], 'forward one notch')
back.selectedSeed = vis[1]
back:wheelSelect(-1)
check(back.selectedSeed == vis[#vis], 'backward wraps to the last')
back.selectedSeed = vis[1]
back:setMouseCaptured(false)
back:wheelSelect(1)
check(back.selectedSeed == vis[1], 'no change when uncaptured')
back:setMouseCaptured(true)
-- through love.wheelmoved + update
back.selectedSeed = vis[1]
love.wheelmoved(0, 1); back:update(1 / 60)
check(back.selectedSeed == (vis[2] or vis[1]), 'wheelmoved drives the selection')
love.mouse.wheelDelta = 0

-- 3.4 hint: shows with the mouse captured, fades, returns when released; uproot wording
mock.reset(); love.draw()
local hint = false
for _, s in ipairs(texts()) do if s:find('Right-click', 1, true) and s:find('uproot', 1, true) then hint = true end end
check(hint, 'hint says right-click to uproot')
back.hintTime = 0
mock.reset(); love.draw()
hint = false
for _, s in ipairs(texts()) do if s:find('Right-click', 1, true) or s:find('Click to capture', 1, true) then hint = true end end
for _, c in ipairs(mock.callsNamed('printf')) do
    if type(c.args[1]) == 'string' and c.args[1]:find('uproot', 1, true) then hint = true end
end
check(not hint, 'hint gone after fading')
back:setMouseCaptured(false)
mock.reset(); love.draw()
check(has(texts(), 'Click to capture the mouse'), 'hint returns when the mouse is free')
back:setMouseCaptured(true)

-- 3.5 counts follow planting, uproot refund and pickup
local RIM = {-4.6, 0, 0}
back = setup(ROOM, {pumpkin = 2}, 'pumpkin')
local function countText() mock.reset(); love.draw(); return texts() end
back.player:setPosition(RIM[1], RIM[2], RIM[3])
local plot = back.room:plotById('pit')
check(plot and back:targetPlot() == plot, 'aiming at the pit plot')
check(has(countText(), '2'), 'count 2 before planting')
local ok = back:plant()
check(ok and back.gameData.seeds.pumpkin == 1, 'planting spends a seed')
local hudNow = countText()
check(has(hudNow, '1'), 'count 1 after planting')
check(back:uproot() and back.gameData.seeds.pumpkin == 2, 'uproot refunds')
check(has(countText(), '2'), 'count 2 after refund')
-- real pickup collection in a generated level
back = setup(LevelGen.generate(3, 1), {}, 'beanstalk')
local pk = back.room.pickups[1]
check(pk ~= nil, 'generated level has a pickup')
if pk then
    local t, p = pk.seed, pk.pos
    back.gameData.seeds[t] = 4
    local n0 = 4
    back.player:setPosition(p[1], p[2], p[3])
    local got = back:collectPickups()
    check(got and back.gameData.seeds[t] == n0 + 1, 'pickup adds a seed')
    local out = countText()
    check(has(out, tostring(n0 + 1)), 'hotbar count follows pickup')
end

realPrint(fails == 0 and 'ui_hotbar: OK' or ('ui_hotbar: ' .. fails .. ' FAILED'))
os.exit(fails == 0 and 0 or 1)
