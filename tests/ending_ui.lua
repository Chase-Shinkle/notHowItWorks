-- Tests for title-hotbar-ending-ui section 4 (ending scene), wired into tests/check_all.sh:
--   love tests/love_runner tests/ending_ui.lua   (or luajit tests/ending_ui.lua)
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

local playing = {}
local function fake()
    local s = {}
    function s:play() playing[self] = true; return true end
    function s:stop() playing[self] = nil end
    function s:setVolume() end
    function s:setPitch() end
    function s:setLooping() end
    function s:clone() return fake() end
    return s
end
gSounds['backrooms-hum'] = fake()
for i = 1, 5 do gSounds['footstep-' .. i] = fake() end

local function tick(dt) love.update(dt) end
local function press(k) love.keyboard.keysPressed[k] = true end

-- 4.1 hand-off forms
gStateMachine:change('ending', {gameData = NewGameData(), runSeed = 4242})
local e = gStateMachine.current
check(e.runSeed == 4242 and e.gameData, 'table param: run seed and game data')
gStateMachine:change('ending', NewGameData())
e = gStateMachine.current
check(e.runSeed and e.gameData.seeds, 'bare gameData: random seed')
gStateMachine:change('ending')
check(gStateMachine.current.gameData, 'no param works')

local back = BackroomsState()
local got
local realChange = gStateMachine.change
gStateMachine.change = function(self, name, param) got = {name, param} end
back.finished, back.advancing, back.roomIndex, back.runSeed = false, false, 1, 777
back.gameData = NewGameData(); back.rooms = {1}
back:advance()
gStateMachine.change = realChange
check(got and got[1] == 'ending' and got[2].runSeed == 777 and got[2].gameData == back.gameData, 'advance passes gameData and runSeed')

-- 4.2 reproducible, no-shader renders
local function sig(d)
    local n = {#d.boxes, d.spawn[1], d.spawn[2]}
    for _, b in ipairs(d.boxes) do n[#n + 1] = b.pos[1] + 3 * b.pos[2] + 7 * b.size[1] end
    return table.concat(n, ',')
end
local d1, p1 = EndingState.buildHallway(31)
local d2, p2 = EndingState.buildHallway(31)
check(sig(d1) == sig(d2) and #p1 == #p2, 'same seed, same hallway')
check(sig(EndingState.buildHallway(32)) ~= sig(d1), 'different seed differs')
BackroomsLook.enabled = false
gStateMachine:change('ending', {gameData = NewGameData(), runSeed = 5})
local ok, err = pcall(function() love.draw() end)
check(ok, 'renders with the look disabled: ' .. tostring(err))

-- 4.3 camera stays in open cells; sweep; input does not move it
for seed = 1, 60 do
    local data, pts = EndingState.buildHallway(seed)
    check(#pts >= 2, 'seed ' .. seed .. ': path has waypoints')
    local room = Room(data)
    local inside = true
    for t = 0, 120, 0.5 do
        local x, y, z = EndingState.cameraAt(pts, t)
        if data.id == 'ending-hall' then
            inside = inside and x > 0 and x < 30 and math.abs(y) < 1.9
        else
            local c = room:cellAt(x, y)
            inside = inside and c and c.region == 0 and c.kind ~= 'module'
        end
        inside = inside and math.abs(z - BACKROOMS_EYE_HEIGHT) < 0.1
    end
    check(inside, 'seed ' .. seed .. ': camera stays inside open cells')
end
local x0, y0 = EndingState.cameraAt(p1, 0)
local x5 = EndingState.cameraAt(p1, 5)
local xe1, ye1 = EndingState.cameraAt(p1, 500)
local xe2, ye2 = EndingState.cameraAt(p1, 501)
check(math.abs(xe1 - xe2) < 0.2 and math.abs(ye1 - ye2) < 0.2, 'holds at the end (sway only)')
-- authored fallback (no generated candidate): valid room, camera inside it
local tries = ENDING_LEVEL_TRIES; ENDING_LEVEL_TRIES = 0
local fd, fp = EndingState.buildHallway(1)
ENDING_LEVEL_TRIES = tries
check(fd.id == 'ending-hall' and pcall(Room, fd), 'authored fallback builds a Room')
local fin = true
for t = 0, 120, 0.5 do local x, y = EndingState.cameraAt(fp, t); fin = fin and x > 0 and x < 30 and math.abs(y) < 1.9 end
check(fin, 'fallback camera inside the hall')

gStateMachine:change('ending', {gameData = NewGameData(), runSeed = 9})
e = gStateMachine.current
tick(0.1)
local ax, ay = e.camX, e.camY
local dist0 = math.sqrt((ax - e.path[1][1]) ^ 2 + (ay - e.path[1][2]) ^ 2)
mock.mouseX, mock.mouseY = 3, 3
press('w'); press('up'); tick(0.1)
local expX, expY = EndingState.cameraAt(e.path, e.time)
check(e.camX == expX and e.camY == expY, 'input does not move the camera off its path')
for _ = 1, 50 do tick(0.1) end
check(math.sqrt((e.camX - e.path[1][1]) ^ 2 + (e.camY - e.path[1][2]) ^ 2) > dist0 + 1, 'camera drifts along the hallway')

-- 4.4 audio
check(next(playing) ~= nil and e.audio, 'hum plays in the ending')
check(love.mouse.getRelativeMode() == false, 'mouse freed')
gStateMachine:change('start')
check(next(playing) == nil and e.audio == nil, 'audio disposed leaving to the title')

-- 4.5 reveal and input
local quit = 0
love.event = love.event or {}
local realQuit = love.event.quit
love.event.quit = function() quit = quit + 1 end
gStateMachine:change('ending', {gameData = NewGameData(), runSeed = 9})
e = gStateMachine.current
press('return'); tick(0.1)
check(gStateMachine.current == e, 'held/early key activates nothing')
tick(ENDING_BUTTONS_AT + ENDING_FADE)
press('return'); tick(0.016)
check(getmetatable(gStateMachine.current) ~= getmetatable(e), 'Enter on Back to Title leaves the ending')
check(gStateMachine.current.update == StartState.update, 'goes to the title')

gStateMachine:change('ending', {gameData = NewGameData(), runSeed = 9})
e = gStateMachine.current
tick(ENDING_BUTTONS_AT + ENDING_FADE + 0.1)
press('down'); tick(0.016)
press('return'); tick(0.016)
check(quit == 1, 'Exit Game quits')

gStateMachine:change('ending', {gameData = NewGameData(), runSeed = 9})
e = gStateMachine.current
tick(ENDING_BUTTONS_AT + ENDING_FADE + 0.1)
local r = e.menu.rects[2]
mock.mouseX, mock.mouseY = r.x + 2, r.y + 2
love.mouse.buttonsPressed[1] = true; tick(0.016)
check(quit == 2, 'mouse click on Exit Game quits')
love.event.quit = realQuit

if fails == 0 then print('ending_ui: all ok') else print('ending_ui: ' .. fails .. ' failure(s)'); os.exit(1) end
