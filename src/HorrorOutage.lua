-- Backrooms area light flash: a discrete event every 75-150 s (randomized). When a lit fixture is near the camera,
-- ALL lit fixtures of the camera's zone (zone-less: those within 20 m) flash together (irregular on/off) for 2-4 s, then return to
-- normal. No per-fixture timers; skipped/delayed (retry 5 s) when no light is near or another horror event
-- (distant sound / silhouette, see HorrorEvents) is active. A synced crackle plays on each off/on transition.
-- Driven from BackroomsLook.begin; only scales fixture intensity (ambient/fog floor, collision untouched).
HorrorOutage = {}

local MIN_GAP, MAX_GAP = 75, 150          -- cooldown between area flashes
local MIN_DUR, MAX_DUR = 2, 4               -- flash length
local AREA_R = 20                           -- zone-less fallback only: lights within this many metres flash together
local NEAR_REQUIRED = 12                    -- need a lit fixture this close, else skip/delay

local function fresh() return {room = nil, nextAt = nil, set = nil, segs = nil, endAt = nil, seg = 0, sources = {}} end
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

-- Advance the state machine. `lights` is the room's light list, `picked` the indices of the nearest lights
-- to the camera (cx, cy). One discrete event: every lit light in the camera's zone/area flashes together.
function HorrorOutage.update(room, lights, picked, t, cx, cy)
    if S.room ~= room then
        HorrorOutage.reset()
        S.room = room
        S.nextAt = t + rnd(MIN_GAP, MAX_GAP)
    end
    prune()
    if S.set then
        local seg = S.seg
        while S.segs[seg + 1] and t >= S.segs[seg + 1].from do seg = seg + 1 end
        if seg ~= S.seg then
            S.seg = seg
            if S.segs[seg] and not S.segs[seg].on then pop('start') else pop('restore') end
        end
        if t >= S.endAt then S.set, S.segs = nil, nil; S.nextAt = t + rnd(MIN_GAP, MAX_GAP) end
    elseif t >= S.nextAt then
        local first = picked and picked[1] and lights[picked[1]]
        local near = first and cx and ((first.pos[1] - cx) ^ 2 + (first.pos[2] - cy) ^ 2) <= NEAR_REQUIRED ^ 2
        if near and not (HorrorEvents and HorrorEvents.otherActive('lights')) then
            local set, n = {}, 0
            for _, l in ipairs(lights) do
                if (l.mode or 'steady') ~= 'dead' and l.zone == first.zone
                    and (first.zone ~= nil or ((l.pos[1] - cx) ^ 2 + (l.pos[2] - cy) ^ 2) <= AREA_R ^ 2) then
                    set[l] = true; n = n + 1
                end
            end
            local dur = rnd(MIN_DUR, MAX_DUR)
            local segs, at, on = {}, 0, false      -- irregular on/off pattern, starts with an off
            while at < dur do
                segs[#segs + 1] = {from = t + at, on = on, level = rnd(0.05, 0.10)}
                at = at + (on and rnd(0.05, 0.4) or rnd(0.2, 0.6))
                on = not on
            end
            S.set, S.segs, S.endAt, S.seg = set, segs, t + dur, 0
        else
            S.nextAt = t + 5
        end
    end
end

-- Brightness multiplier for `light` at time t (1 when unaffected).
function HorrorOutage.factor(light, t)
    if not S.set or not S.set[light] then return 1 end
    local seg = S.segs[math.max(1, S.seg)]
    if t < S.segs[1].from or t >= S.endAt then return 1 end
    return seg.on and 1 or 0
end

-- Whole-scene brightness (ambient, fog, sprites/crops included) for the camera's zone: 1 normally, 0.05-0.10
-- (near black, hard cut) during an OFF phase of an active flash.
function HorrorOutage.sceneDim(t)
    if not S.set or t < S.segs[1].from or t >= S.endAt then return 1 end
    local seg = S.segs[math.max(1, S.seg)]
    return seg.on and 1 or seg.level
end

function HorrorOutage.active() return S.set ~= nil end

if HorrorEvents then HorrorEvents.register('lights', HorrorOutage.active) end
