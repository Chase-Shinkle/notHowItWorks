-- Section 1 (audio) assertions for backrooms-zones-variety-audio (wired into tests/check_all.sh):
--   love tests/love_runner tests/zones_audio.lua   (or luajit tests/zones_audio.lua)
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

-- fake sources recording what plays
local playing = {}
local function fake(name)
    local s = {name = name, plays = 0, vol = 1, pitch = 1}
    function s:play() self.plays = self.plays + 1; playing[self] = true; return true end
    function s:stop() playing[self] = nil end
    function s:setVolume(v) self.vol = v end
    function s:setPitch(p) self.pitch = p end
    function s:setLooping(l) self.looping = l end
    function s:clone() local c = fake(name); c.isClone = true; s.clones = s.clones or {}; s.clones[#s.clones + 1] = c; return c end
    return s
end
local function installFakes()
    playing = {}
    gSounds['backrooms-hum'] = fake('hum')
    for i = 1, 5 do gSounds['footstep-' .. i] = fake('step' .. i) end
end
local function stepCount()
    local n, seq = 0, {}
    for i = 1, 5 do
        for _, c in ipairs(gSounds['footstep-' .. i].clones or {}) do n = n + 1 end
    end
    return n
end
local function walk(audio, player, meters, dx)
    for _ = 1, math.floor(meters / dx) do player.x = player.x + dx; audio:update(1 / 60, player) end
end

-- 1.1 registration: hum is a stream of the mp3; footsteps are static; missing files give stubs
check(BACKROOMS_HUM_FILE:match('%.mp3$'), 'hum file is the mp3')
local lines = io.open('src/Dependencies.lua'):read('*a')
check(lines:find("BACKROOMS_HUM_FILE, 'stream'", 1, true), 'hum registered as stream')
check(lines:find("footstep%-5'%] = {BACKROOMS_FOOTSTEP_FILES%[5%], 'static'}"), 'footsteps registered static')
local stub, isStub = Assets.loadSound('sounds/does-not-exist.wav', 'static')
check(isStub and stub:clone() and stub:play() and stub.setPitch, 'missing sound yields a usable silent stub')
check(gSounds['backrooms-hum'] and gSounds['footstep-1'] and gSounds['footstep-5'], 'sounds registered in gSounds')

-- 1.2 cadence, no repeats, variation, no steps off the ground
installFakes()
local a = BackroomsAudio.new()
check(playing[gSounds['backrooms-hum']] and gSounds['backrooms-hum'].looping, 'hum starts looping on new')
local p = {x = 0, y = 0, grounded = true}
a:update(1 / 60, p)                       -- first sample only sets the origin
walk(a, p, BACKROOMS_FOOTSTEP_STRIDE * 10 + 0.01, 0.05)
check(a.steps == 10, 'ten strides give ten steps, got ' .. a.steps)

installFakes(); a = BackroomsAudio.new()
p = {x = 0, y = 0, grounded = true}
a:update(0, p)
for _ = 1, 120 do a:update(1 / 60, p) end
check(a.steps == 0, 'standing still plays no footsteps')

local seq, last, repeats = {}, nil, 0
installFakes(); a = BackroomsAudio.new()
local orig = a.playStep
a.playStep = function(self) local i = orig(self); if i == last then repeats = repeats + 1 end; last = i; seq[#seq + 1] = i; return i end
p = {x = 0, y = 0, grounded = true}
a:update(0, p)
walk(a, p, BACKROOMS_FOOTSTEP_STRIDE * 200, 0.1)
check(#seq >= 190, 'many steps played')
check(repeats == 0, 'no footstep index twice in a row')
local seen = {}
for _, i in ipairs(seq) do seen[i] = true end
check(#seq > 0 and seen[1] and seen[5], 'all five sounds are used')
local minP, maxP, minV, maxV = 9, 0, 9, 0
for i = 1, 5 do
    for _, c in ipairs(gSounds['footstep-' .. i].clones or {}) do
        minP, maxP = math.min(minP, c.pitch), math.max(maxP, c.pitch)
        minV, maxV = math.min(minV, c.vol), math.max(maxV, c.vol)
        check(math.abs(c.pitch - 1) <= BACKROOMS_FOOTSTEP_PITCH_VARIATION + 1e-9, 'pitch within variation')
        check(math.abs(c.vol / BACKROOMS_FOOTSTEP_VOLUME - 1) <= BACKROOMS_FOOTSTEP_VOLUME_VARIATION + 1e-9, 'volume within variation')
    end
end
check(maxP > minP and maxV > minV, 'pitch and volume vary')

for _, mode in ipairs({'airborne', 'falling', 'climbing'}) do
    installFakes(); a = BackroomsAudio.new()
    p = {x = 0, y = 0, grounded = (mode == 'climbing'), climbing = (mode == 'climbing') or nil}
    a:update(0, p)
    walk(a, p, 20, 0.1)
    check(a.steps == 0 and stepCount() == 0, 'no footsteps while ' .. mode)
end

installFakes(); a = BackroomsAudio.new()
p = {x = 0, y = 0, grounded = true}
a:update(0, p)
p.x = 50; a:update(0, p)                  -- teleport (respawn / next room)
check(a.steps == 0, 'a teleport is not walking')

-- hum fade
installFakes(); a = BackroomsAudio.new()
local hum = gSounds['backrooms-hum']
check(hum.vol == 0, 'hum fades in from silence')
a:update(BACKROOMS_HUM_FADE / 2, nil)
check(math.abs(hum.vol - BACKROOMS_HUM_VOLUME / 2) < 1e-9, 'hum half faded')
a:update(BACKROOMS_HUM_FADE, nil)
check(math.abs(hum.vol - BACKROOMS_HUM_VOLUME) < 1e-9, 'hum reaches its volume')

-- stop/dispose: nothing playing, later updates do nothing
a:dispose()
check(next(playing) == nil, 'dispose leaves nothing playing')
a:update(1, {x = 0, y = 0, grounded = true}); a:update(1, {x = 1, y = 0, grounded = true})
check(next(playing) == nil, 'updates after dispose play nothing')

-- 1.3 lifecycle: state enter/exit, ending, farm/start
installFakes()
check(next(playing) == nil, 'nothing playing before the backrooms')
gStateMachine:change('start'); gStateMachine:change('farm', NewGameData())
check(next(playing) == nil, 'start and farm play no backrooms audio')
gStateMachine:change('backrooms', CarryOverGameData(NewGameData()))
check(playing[gSounds['backrooms-hum']], 'hum plays in the backrooms (tutorial room included)')
local state = gStateMachine.current
check(state.audio, 'backrooms state owns an audio object')
gStateMachine:change('farm', NewGameData())
check(next(playing) == nil and state.audio == nil, 'leaving the backrooms stops the hum and drops audio')
gStateMachine:change('backrooms', CarryOverGameData(NewGameData()))
state = gStateMachine.current
state.finished = false; state.advancing = false
state.roomIndex = state:levelCount()
state:advance()                           -- last exit -> ending
check(gStateMachine.current ~= state and next(playing) == nil, 'ending run leaves nothing playing')
gStateMachine:change('start')
check(next(playing) == nil, 'back at the start screen: silence')

-- 1.3b the real fall: the farm break (glitch + fall) is silent; the hum starts only when the backrooms state is entered
installFakes()
gStateMachine:change('start'); gStateMachine:change('farm', NewGameData())
local farm = gStateMachine.current
farm:startBreak('idle')
for _ = 1, 30 do farm:updateBreak(1 / 60) end
check(gStateMachine.current == farm and next(playing) == nil, 'fall transition (farm break in progress) is silent')
farm.breakDone = true
farm:updateBreak(1 / 60)
check(gStateMachine.current ~= farm and playing[gSounds['backrooms-hum']], 'hum starts when the fall lands in the backrooms')
gStateMachine:change('start')
check(next(playing) == nil, 'silent again at start')

print(fails == 0 and 'zones_audio: OK' or ('zones_audio: ' .. fails .. ' FAILED'))
os.exit(fails == 0 and 0 or 1)
