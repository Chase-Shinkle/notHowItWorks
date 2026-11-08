-- Backrooms hum + rug footsteps. Created in BackroomsState:enter and shut down
-- in exit, so nothing plays in the start screen, farm, fall transition or
-- ending. Sources come from gSounds (loaded through the safe Assets loader, so
-- a missing file is a silent stub).
--   audio = BackroomsAudio.new()           starts the hum (fades in)
--   audio:update(dt, player)               fades the hum, counts ground distance
--   audio:reset()                          forget the last position (teleports)
--   audio:stop() / audio:dispose()         hard stop everything
BackroomsAudio = {}
BackroomsAudio.__index = BackroomsAudio

function BackroomsAudio.new(rng)
    local self = setmetatable({}, BackroomsAudio)
    self.rng = rng or function(a, b) return math.random(a, b) end
    self.rand = math.random
    self.hum = gSounds['backrooms-hum']
    self.footsteps = {}
    for i = 1, #BACKROOMS_FOOTSTEP_FILES do self.footsteps[i] = gSounds['footstep-' .. i] end
    self.active = true
    self.fade = 0                 -- 0..1 hum fade-in level
    self.walked = 0               -- ground distance since the last step
    self.lastIndex = nil
    self.lastX, self.lastY = nil, nil
    self.steps = 0
    self.live = {}                -- recent step clones, stopped on dispose
    self.duck = 1                 -- hum duck multiplier (fall fade)
    self.duckTarget = 1
    self.muted = false            -- no footsteps while falling
    if self.hum then
        self.hum:setLooping(true)
        self.hum:setVolume(0)
        self.hum:play()
    end
    return self
end

function BackroomsAudio:reset()
    self.lastX, self.lastY = nil, nil
end

-- Cycles the footsteps 1..n in order (no randomness).
function BackroomsAudio:pickIndex()
    local n = #self.footsteps
    if n <= 1 then return 1 end
    self.lastIndex = (self.lastIndex or 0) % n + 1
    return self.lastIndex
end

function BackroomsAudio:playStep()
    local i = self:pickIndex()
    local base = self.footsteps[i]
    if not base then return end
    local src = base.clone and base:clone() or base
    local pv, vv = BACKROOMS_FOOTSTEP_PITCH_VARIATION, BACKROOMS_FOOTSTEP_VOLUME_VARIATION
    src:setPitch(1 + (self.rand() * 2 - 1) * pv)
    src:setVolume(BACKROOMS_FOOTSTEP_VOLUME * (1 + (self.rand() * 2 - 1) * vv))
    src:play()
    self.live[#self.live + 1] = src
    if #self.live > 8 then table.remove(self.live, 1) end   -- older steps have long finished
    self.steps = self.steps + 1
    return i
end

-- player: needs x, y, grounded, climbing.
function BackroomsAudio:update(dt, player)
    if not self.active then return end
    if self.fade < 1 then
        self.fade = math.min(1, self.fade + dt / math.max(BACKROOMS_HUM_FADE, 1e-6))
    end
    if self.duck ~= self.duckTarget then
        local step = dt / 0.3
        if self.duck < self.duckTarget then self.duck = math.min(self.duckTarget, self.duck + step)
        else self.duck = math.max(self.duckTarget, self.duck - step) end
    end
    if self.hum then self.hum:setVolume(BACKROOMS_HUM_VOLUME * self.fade * self.duck) end
    if self.muted then
        self.lastX, self.lastY = player and player.x, player and player.y
        self.walked = 0
        return
    end
    if not player then return end
    local x, y = player.x, player.y
    local lx, ly = self.lastX, self.lastY
    self.lastX, self.lastY = x, y
    if not lx then return end
    if player.climbing then
        self.walked, self.airTime = 0, 0
        return
    end
    -- PlayerController clears `grounded` every frame and only re-sets it when a
    -- floor contact is resolved, so it drops for single frames while walking
    -- (collider seams, tiny gravity drop). Those flickers neither play steps
    -- nor wipe the banked distance; only sustained air time resets it.
    if not player.grounded then
        self.airTime = (self.airTime or 0) + dt
        if self.airTime > BACKROOMS_FOOTSTEP_AIR_GRACE then
            self.walked = 0
        else
            -- flicker frame: the stride keeps banking (no step played until grounded again)
            local fd = math.sqrt((x - lx) ^ 2 + (y - ly) ^ 2)
            if fd <= BACKROOMS_FOOTSTEP_STRIDE then self.walked = self.walked + fd end
        end
        return
    end
    self.airTime = 0
    local d = math.sqrt((x - lx) ^ 2 + (y - ly) ^ 2)
    if d > BACKROOMS_FOOTSTEP_STRIDE then return end   -- teleport (respawn/new room), not walking
    self.walked = self.walked + d
    while self.walked >= BACKROOMS_FOOTSTEP_STRIDE do
        self.walked = self.walked - BACKROOMS_FOOTSTEP_STRIDE
        self:playStep()
    end
end

-- Fall transition: duck the hum and silence footsteps, or restore both.
function BackroomsAudio:setFalling(falling)
    self.muted = falling and true or false
    self.duckTarget = falling and 0.2 or 1
    if not falling then self:reset() end
end

-- Short descending wind rush synthesized in memory (no asset needed). Returns
-- the Source, or nil if audio is unavailable.
function BackroomsAudio.synthFall()
    local ok, src = pcall(function()
        local rate, dur = 22050, 1.1
        local n = math.floor(rate * dur)
        local sd = love.sound.newSoundData(n, rate, 16, 1)
        local lp, phase = 0, 0
        for i = 0, n - 1 do
            local t = i / n
            local env = math.min(1, t * 12) * (1 - t) ^ 0.7
            local k = 0.35 - 0.28 * t                    -- low-pass closes: rush darkens
            lp = lp + k * ((math.random() * 2 - 1) - lp)
            local f = 520 * (1 - t) ^ 1.5 + 70           -- descending tone
            phase = phase + 2 * math.pi * f / rate
            sd:setSample(i, (lp * 2.2 + math.sin(phase) * 0.12) * env * 0.6)
        end
        return love.audio.newSource(sd)
    end)
    return ok and src or nil
end

function BackroomsAudio:playFall()
    if not self.active then return end
    self.fallSrc = self.fallSrc or BackroomsAudio.synthFall()
    if self.fallSrc then
        self.fallSrc:stop()
        self.fallSrc:setVolume(0.7)
        self.fallSrc:play()
    end
end

function BackroomsAudio:stop()
    self.active = false
    if self.hum then self.hum:stop() end
    for _, s in ipairs(self.footsteps) do s:stop() end
    for _, s in ipairs(self.live) do s:stop() end
    self.live = {}
    if self.fallSrc then self.fallSrc:stop() end
end

BackroomsAudio.dispose = BackroomsAudio.stop
