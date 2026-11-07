-- Tests for title-hotbar-ending-ui section 2 (title screen):
--   love tests/love_runner tests/ui_title.lua
package.path = './?.lua;./?/init.lua;' .. package.path
local realPrint = print
local mock = dofile('tests/mock_love.lua')
mock.install()
arg = {}
local titles, quits = {}, 0
local realLoad
dofile('main.lua')
love.window.setTitle = function(t) titles[#titles + 1] = t end
love.event = {quit = function() quits = quits + 1 end}
love.load()
print = realPrint

local fails = 0
local function check(cond, msg) if not cond then fails = fails + 1; print('FAIL ' .. msg) end end

-- 2.3 window title
check(titles[#titles] == 'Back to Farming', 'window title is Back to Farming (' .. tostring(titles[#titles]) .. ')')
check(io.open('conf.lua'):read('*a'):find("t.window.title = 'Back to Farming'", 1, true), 'conf.lua window title')

-- 2.2 callbacks with the mocked state machine
local changes = {}
local function fresh()
    changes = {}; quits = 0
    gStateMachine = {change = function(_, name, param) changes[#changes + 1] = {name, param} end}
    local s = StartState()
    s:enter()
    love.keyboard.keysPressed, love.mouse.buttonsPressed = {}, {}
    return s
end
local s = fresh()
check(s.menu.index == 1 and s.menu.items[1].label == 'Play Game' and s.menu.items[2].label == 'Exit Game', 'Play highlighted first, Exit second')
mock.press('return'); s:update(1 / 60)
check(#changes == 1 and changes[1][1] == 'farm' and type(changes[1][2]) == 'table' and changes[1][2].seeds, 'Enter starts farm with new game data')
s = fresh(); mock.press('down'); mock.press('return'); s:update(1 / 60)
check(quits == 1 and #changes == 0, 'Down + Enter quits')
s = fresh(); mock.press('space'); s:update(1 / 60)
check(changes[1] and changes[1][1] == 'farm', 'Space plays')
local r = s.menu.rects
s = fresh(); r = s.menu.rects
mock.mouseAt(r[2].x + 5, r[2].y + 5); s:update(1 / 60)
check(s.menu.index == 2, 'hover highlights Exit')
mock.click(1); s:update(1 / 60)
check(quits == 1, 'click on Exit quits')
s = fresh(); mock.mouseAt(r[1].x + 5, r[1].y + 5); mock.click(1); s:update(1 / 60)
check(changes[1] and changes[1][1] == 'farm', 'click on Play starts farm')
s = fresh(); mock.mouseAt(2, 2); mock.click(1); s:update(1 / 60)
check(#changes == 0 and quits == 0, 'click outside buttons does nothing')
-- buttons stay on the 320x320 canvas
for i, b in ipairs(s.menu.rects) do
    check(b.x >= 0 and b.y >= 0 and b.x + b.w <= VIRTUAL_WIDTH and b.y + b.h <= VIRTUAL_HEIGHT, 'button ' .. i .. ' on canvas')
end

-- 2.1 render runs, scene is animated
mock.reset()
check(pcall(function() s:render() end), 'render runs')
local d1 = mock.count('draw')
check(d1 > 50, 'scene draws many sprites (' .. d1 .. ')')
local function firstCloud() local e = mock.callsNamed('ellipse'); return e[#e].args[2] end
mock.reset(); s:update(0); s:render(); local x1 = firstCloud() or 0
s.time = s.time + 3
mock.reset(); s:render(); local x2 = firstCloud() or 0
check(x1 ~= x2, 'clouds drift over time')

print(fails == 0 and 'ui_title: OK' or ('ui_title: ' .. fails .. ' FAILED'))
os.exit(fails == 0 and 0 or 1)
