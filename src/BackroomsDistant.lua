-- Rare, quiet, invisible distant sounds for the Backrooms (far footsteps, door
-- thud/pop). Owned by BackroomsAudio; no gameplay/collision effect. Every API
-- call is pcall-guarded so a missing love.audio/sound is a silent no-op.
BackroomsDistant = {}
BackroomsDistant.__index = BackroomsDistant

BackroomsDistant.MIN_GAP, BackroomsDistant.MAX_GAP = 60, 120  -- s between events
BackroomsDistant.VOLUME = 0.12

local function synthDoor(kind)
    local ok, src = pcall(function()
        local rate, dur = 22050, kind == 'pop' and 0.25 or 0.45
        local n = math.floor(rate * dur)
        local sd = love.sound.newSoundData(n, rate, 16, 1)
        local lp, phase = 0, 0
        for i = 0, n - 1 do
            local t = i / n
            local env = math.min(1, t * 60) * (1 - t) ^ (kind == 'pop' and 4 or 2.5)
            lp = lp + 0.08 * ((math.random() * 2 - 1) - lp)
            phase = phase + 2 * math.pi * (kind == 'pop' and 180 or 60) / rate
            sd:setSample(i, (lp * 2.5 + math.sin(phase) * 0.5) * env * 0.7)
        end
        return love.audio.newSource(sd)
    end)
    return ok and src or nil
end

function BackroomsDistant.new(footsteps)
    local self = setmetatable({}, BackroomsDistant)
    self.footBases = footsteps or {}
    self.live = {}
    self.active = true
    self.timer = self:nextGap()
    if HorrorEvents then HorrorEvents.register('distant', function() return self:isActive() end) end
    -- 2-3 door variants: heavy thud, pop, second thud
    self.doors = {}
    for _, k in ipairs({'thud', 'pop', 'thud'}) do
        local s = synthDoor(k)
        if s then self.doors[#self.doors + 1] = s end
    end
    return self
end

-- True while a fired sound is still pending or playing (blocks silhouette / light events).
function BackroomsDistant:isActive()
    if not self.active then return false end
    if self.pending and #self.pending > 0 then return true end
    for _, s in ipairs(self.live) do if s:isPlaying() then return true end end
    for _, s in ipairs(self.doors) do if s:isPlaying() then return true end end
    return false
end

function BackroomsDistant:nextGap()
    return BackroomsDistant.MIN_GAP + math.random() * (BackroomsDistant.MAX_GAP - BackroomsDistant.MIN_GAP)
end

-- Places a source off to a random side, a few metres behind the listener.
local function place(src)
    pcall(function()
        local a = math.random() * 2 * math.pi
        local d = 12 + math.random() * 8
        src:setRelative(true)
        src:setPosition(math.cos(a) * d, 0, math.sin(a) * d)
        src:setAttenuationDistances(1, 40)
    end)
end

function BackroomsDistant:track(src)
    self.live[#self.live + 1] = src
    if #self.live > 12 then table.remove(self.live, 1) end
end

function BackroomsDistant:fire()
    if math.random() < 0.5 and #self.footBases > 0 then
        -- far footsteps: 3-6 low-pitched rug clones, stepping along
        local base = self.footBases[math.random(#self.footBases)]
        local n = math.random(3, 6)
        for i = 1, n do
            local ok, src = pcall(function() return base:clone() end)
            if ok and src then
                pcall(function()
                    src:setPitch(0.55 + math.random() * 0.1)
                    src:setVolume(BackroomsDistant.VOLUME * 0.8)
                end)
                place(src)
                self.pending = self.pending or {}
                self.pending[#self.pending + 1] = {src = src, at = (i - 1) * (0.55 + math.random() * 0.15)}
                self:track(src)
            end
        end
    elseif #self.doors > 0 then
        local src = self.doors[math.random(#self.doors)]
        pcall(function() src:stop(); src:setVolume(BackroomsDistant.VOLUME) end)
        place(src)
        pcall(function() src:play() end)
    end
end

function BackroomsDistant:update(dt, muted)
    if not self.active then return end
    if self.pending then
        for i = #self.pending, 1, -1 do
            local p = self.pending[i]
            p.at = p.at - dt
            if p.at <= 0 then
                if not muted then pcall(function() p.src:play() end) end
                table.remove(self.pending, i)
            end
        end
    end
    if muted then return end
    self.timer = self.timer - dt
    if self.timer <= 0 then
        if HorrorEvents and HorrorEvents.otherActive('distant') then self.timer = 3; return end   -- retry soon
        self.timer = self:nextGap()
        self:fire()
    end
end

function BackroomsDistant:stop()
    self.active = false
    if HorrorEvents then HorrorEvents.unregister('distant') end
    self.pending = nil
    for _, s in ipairs(self.live) do pcall(function() s:stop() end) end
    for _, s in ipairs(self.doors) do pcall(function() s:stop() end) end
    self.live = {}
end
