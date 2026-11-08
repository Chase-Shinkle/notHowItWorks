-- Occasional horror light outage: every 20-60 s (randomized) a fixture near the
-- camera stutters, goes dark for 1-2 s, then restores with a brief re-flicker.
-- Driven from BackroomsLook.begin (backrooms rooms only), so it needs no state
-- hooks. It only scales one fixture's intensity: zone ambient/fog (the
-- readability floor), collision and room solvability are untouched.
-- A tiny synthesized crackle/pop plays at the start and the restore; if
-- love.sound/audio is unavailable it is silently skipped.
HorrorOutage = {}

local MIN_GAP, MAX_GAP = 20, 60
local STUTTER, MIN_OUT, MAX_OUT, RESTORE = 0.5, 1.0, 2.0, 0.35
local NEARBY = 4

local function fresh() return {room = nil, nextAt = nil, light = nil, startAt = nil, outAt = nil, endAt = nil, restoreAt = nil, sources = {}} end
local S = fresh()

local function rnd(a, b) return a + (b - a) * love.math.random() end

local function makeCrackle(seconds, density)
    if not (love and love.sound and love.sound.newSoundData) then return nil end
    local ok, sd = pcall(function()
        local rate = 22050
        local n = math.floor(rate * seconds)
        local d = love.sound.newSoundData(n, rate, 16, 1)
        for i = 0, n - 1 do
            local env = math.exp(-i / (rate * seconds * 0.25))
            local v = 0
            if love.math.random() < density then v = (love.math.random() * 2 - 1) * 0.9 end
            d:setSample(i, v * env * 0.35)
        end
        return d
    end)
    return ok and sd or nil
end

local function pop(kind)
    if not (love and love.audio and love.audio.newSource) then return end
    local ok = pcall(function()
        local sd = makeCrackle(kind == 'start' and 0.35 or 0.2, kind == 'start' and 0.06 or 0.03)
        if not sd then return end
        local src = love.audio.newSource(sd, 'static')
        src:setVolume(0.5)
        src:play()
        S.sources[#S.sources + 1] = src
    end)
    return ok
end

local function prune()
    for i = #S.sources, 1, -1 do
        if not S.sources[i]:isPlaying() then table.remove(S.sources, i) end
    end
end

-- Stop all outage audio and forget the schedule (room change / leaving backrooms).
function HorrorOutage.reset()
    for _, s in ipairs(S.sources) do pcall(function() s:stop() end) end
    S = fresh()
end

-- Advance the state machine. `lights` is the room's light list, `picked` the
-- indices of the nearest lights to the camera.
function HorrorOutage.update(room, lights, picked, t)
    if S.room ~= room then
        HorrorOutage.reset()
        S.room = room
        S.nextAt = t + rnd(MIN_GAP, MAX_GAP)
    end
    prune()
    if S.light then
        if t >= S.endAt + RESTORE then S.light, S.nextAt = nil, t + rnd(MIN_GAP, MAX_GAP)
        elseif not S.restored and t >= S.endAt then S.restored = true; pop('restore') end
    elseif t >= S.nextAt and picked and #picked > 0 then
        local n = math.min(NEARBY, #picked)
        S.light = lights[picked[love.math.random(1, n)]]
        S.startAt = t
        S.outAt = t + STUTTER
        S.endAt = S.outAt + rnd(MIN_OUT, MAX_OUT)
        S.restored = false
        pop('start')
    elseif t >= S.nextAt then
        S.nextAt = t + 5
    end
end

-- Brightness multiplier for `light` at time t (1 when unaffected).
function HorrorOutage.factor(light, t)
    if light ~= S.light or not S.light then return 1 end
    if t < S.startAt then return 1 end
    if t < S.outAt then       -- stutter before dying
        local slot = math.floor((t - S.startAt) * 18)
        return (BackroomsLook.hash01(slot * 7 + 3) < 0.5) and 0.1 or 0.8
    elseif t < S.endAt then return 0
    elseif t < S.endAt + RESTORE then   -- restore with a re-flicker
        local slot = math.floor((t - S.endAt) * 20)
        return (slot % 2 == 0) and 0.9 or 0.3
    end
    return 1
end

function HorrorOutage.active() return S.light ~= nil end
