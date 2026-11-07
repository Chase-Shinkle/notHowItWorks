-- Tests for title-hotbar-ending-ui section 1 (fonts, UI.Menu, button draw):
--   love tests/love_runner tests/ui_found.lua   (or luajit tests/ui_found.lua)
package.path = './?.lua;./?/init.lua;' .. package.path
local realPrint = print
local mock = dofile('tests/mock_love.lua')
mock.install()
arg = {}
dofile('main.lua')
love.load()
print = realPrint

local fails = 0
local function check(cond, msg) if not cond then fails = fails + 1; print('FAIL ' .. msg) end end

-- 1.2 fonts
check(gFonts['title-32'] and gFonts['title-48'], 'title fonts registered')
local f1 = UI.font(24)
check(f1 and f1:getHeight() > 0, 'UI.font returns a usable font')
check(UI.font(24) == f1, 'UI.font caches by size')
check(UI.font(25) ~= f1, 'different size, different font')
check(UI.font(1):getHeight() == UI.font(UI_FONT_MIN_SIZE):getHeight(), 'size clamps to minimum')
check(UI.scaledSize(0.1, 600) == 60, 'scaledSize is a fraction of window height')
UI.fontPath = 'fonts/does-not-exist.ttf'; UI.clearFontCache()
local ok, fb = pcall(UI.font, 24)
check(ok and fb and fb:getHeight() > 0 and fb:getWidth('Play') > 0, 'missing font file falls back to a usable font')
UI.fontPath = nil; UI.clearFontCache()
check(pcall(UI.font, 24), 'nil font path falls back without error')
UI.fontPath = UI_FONT_FILE; UI.clearFontCache()

-- 1.3 Menu
local log = {}
local function menu(mapper)
    log = {}
    local m = UI.Menu.new({
        {label = 'Play Game', onActivate = function() log[#log + 1] = 'play' end},
        {label = 'Exit Game', onActivate = function() log[#log + 1] = 'exit' end},
        {label = 'Third', onActivate = function() log[#log + 1] = 'third' end},
    }, {mapper = mapper})
    m:layout(100, 50, 80, 20, 10)   -- buttons at y 50-70, 80-100, 110-130; x 60-140
    return m
end
local m = menu()
check(m.index == 1, 'first button highlighted by default')
check(m:hit(100, 60) == 1 and m:hit(100, 90) == 2 and m:hit(60, 110) == 3 and m:hit(140, 130) == 3, 'hit-testing inside (edges inclusive)')
check(m:hit(100, 75) == nil and m:hit(59, 60) == nil and m:hit(100, 49) == nil and m:hit(141, 60) == nil, 'hit-testing outside and in gaps is nil')
m:keypressed('down'); check(m.index == 2, 'down moves')
m:keypressed('s'); check(m.index == 3, 's moves down')
m:keypressed('down'); check(m.index == 1, 'down wraps to first')
m:keypressed('up'); check(m.index == 3, 'up wraps to last')
m:keypressed('w'); check(m.index == 2, 'w moves up')
check(m:keypressed('x') == false and m.index == 2, 'other keys unhandled')
m = menu()
m:keypressed('return'); check(log[1] == 'play' and #log == 1, 'enter activates highlighted')
m:keypressed('down'); m:keypressed('space'); check(log[2] == 'exit', 'space activates after navigating')
m:keypressed('kpenter'); check(log[3] == 'exit', 'keypad enter activates')
m = menu()
check(m:mousemoved(100, 90) == 2 and m.index == 2, 'hover highlights')
check(m:mousemoved(5, 5) == nil and m.index == 2, 'hover off buttons keeps highlight')
check(m:mousepressed(5, 5, 1) == false and #log == 0 and m.index == 2, 'click outside is a no-op')
check(m:mousepressed(100, 120, 2) == false and #log == 0, 'right click does nothing')
check(m:mousepressed(100, 120, 1) == true and log[1] == 'third' and m.index == 3, 'left click activates hit button')
m = menu(function(x, y) return x / 2, y / 2 end)   -- raw window pixels at 2x
check(m:mousepressed(200, 180, 1) and log[1] == 'exit', 'coordinate mapper is applied')
check(m:mousepressed(100, 90, 1) == false, 'unmapped coords miss with a mapper')
check(pcall(function() UI.Menu.new({}):keypressed('down') end), 'empty menu ignores keys')

-- 1.4 draw
mock.reset()
m = menu()
local ok2, err = pcall(function() m:draw(UI.font(20), 0.5) end)
check(ok2, 'Menu:draw runs: ' .. tostring(err))
check(mock.count('rectangle') >= 6, 'draws fill and frame per button')
check(UI.fitScale(UI.font(20), 'x', 100) == 1, 'short label is not scaled')
local long = string.rep('W', 40)
check(UI.fitScale(UI.font(20), long, 80) * UI.font(20):getWidth(long) <= 80.001, 'long label scales to fit')

print(fails == 0 and 'ui_found: OK' or ('ui_found: ' .. fails .. ' FAILED'))
os.exit(fails == 0 and 0 or 1)
