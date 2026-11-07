-- Farm game-feel effects: particle bursts, pop and squash tweens, floating
-- popups, flying pickups and the coin ticker. Everything is in virtual
-- (320x320) pixels and advanced by fx:update(dt) -- never by knife Timers, so
-- nothing here is cleared or driven by the farm's Timer groups.
--
-- Particles use their own small random generator, so bursts never disturb the
-- global math.random sequence (the break's corruption uses it). The number of
-- live particles is capped at FX_MAX_PARTICLES, so spamming a key cannot
-- degrade the frame rate.

Fx = {}
Fx.__index = Fx

function Fx.new(seed)
    return setmetatable({
        particles = {},
        popups = {},      -- floating text {text, x, y, life, maxLife, color}
        pops = {},        -- key -> {t, dur, amp}
        squashes = {},    -- key -> {t, dur}
        flyers = {},      -- flying pickups
        seed = seed or 12345,
    }, Fx)
end

-- Park-Miller style generator in [0, 1).
function Fx:random(a, b)
    self.seed = (self.seed * 16807) % 2147483647
    local r = self.seed / 2147483647
    if a then return a + (b - a) * r end
    return r
end

-- Bursts -----------------------------------------------------------------------

-- Emits the burst `kind` (FX_BURSTS) centred on (x, y). Returns the number
-- of particles actually created (fewer once the cap is reached).
function Fx:burst(kind, x, y)
    local def = FX_BURSTS[kind]
    if not def then return 0 end
    local made = 0
    for _ = 1, def.count do
        if #self.particles >= FX_MAX_PARTICLES then break end
        local angle = def.angle and (def.angle + self:random(-def.spread, def.spread))
            or self:random(0, math.pi * 2)
        local speed = self:random(def.speed[1], def.speed[2])
        local life = self:random(def.life[1], def.life[2])
        local color = def.colors[1 + math.floor(self:random() * #def.colors)]
        self.particles[#self.particles + 1] = {
            x = x + self:random(-def.jitter, def.jitter),
            y = y + self:random(-def.jitter, def.jitter),
            vx = math.cos(angle) * speed, vy = math.sin(angle) * speed,
            gravity = def.gravity, life = life, maxLife = life,
            size = def.size, color = color, shape = def.shape,
        }
        made = made + 1
    end
    return made
end

-- Tweens -----------------------------------------------------------------------

-- A brief scale bounce on whatever is drawn under `key`.
function Fx:pop(key, amp, dur)
    self.pops[key] = {t = 0, dur = dur or FX_POP_TIME, amp = amp or FX_POP_SCALE}
end

-- Current pop scale for `key` (1 when idle).
function Fx:popScale(key)
    local p = self.pops[key]
    if not p then return 1 end
    local k = p.t / p.dur
    return 1 + p.amp * math.sin(math.pi * k) * (1 - k * 0.5)
end

-- A squash-and-stretch on `key`: starts 1.25x wide / 0.75x tall and eases
-- back to 1 with a small wobble.
function Fx:squash(key, dur)
    self.squashes[key] = {t = 0, dur = dur or FX_SQUASH_TIME}
end

-- Current squash scales (sx, sy) for `key`; (1, 1) when idle.
function Fx:squashScale(key)
    local s = self.squashes[key]
    if not s then return 1, 1 end
    local k = s.t / s.dur
    local w = math.cos(k * math.pi * 2.5) * (1 - k) * FX_SQUASH_AMOUNT
    return 1 + w, 1 - w
end

-- Popups and flyers --------------------------------------------------------------

function Fx:popup(text, x, y, color)
    local p = {text = text, x = x, y = y, life = FX_POPUP_LIFE, maxLife = FX_POPUP_LIFE,
        color = color or {1, 1, 1, 1}}
    self.popups[#self.popups + 1] = p
    return p
end

-- An `image` that flies in an arc from (x0, y0) to (x1, y1) over `dur`
-- seconds (drawn `size` px), calling onLand() on arrival.
function Fx:fly(image, x0, y0, x1, y1, onLand, dur, size)
    local f = {image = image, x0 = x0, y0 = y0, x1 = x1, y1 = y1, t = 0,
        dur = dur or FX_FLY_TIME, size = size or 14, onLand = onLand}
    self.flyers[#self.flyers + 1] = f
    return f
end

-- Position and scale of a flyer right now.
function Fx.flyerPosition(f)
    local k = math.min(1, f.t / f.dur)
    local e = k * k * (3 - 2 * k)                -- smoothstep
    local x = f.x0 + (f.x1 - f.x0) * e
    local y = f.y0 + (f.y1 - f.y0) * e - math.sin(math.pi * k) * FX_FLY_ARC
    -- pops up on the plot first, then shrinks into the slot
    local scale = 1 + 0.5 * math.sin(math.pi * math.min(1, k * 3)) - 0.3 * k
    return x, y, scale
end

-- Update -------------------------------------------------------------------------

function Fx:update(dt)
    for i = #self.particles, 1, -1 do
        local p = self.particles[i]
        p.life = p.life - dt
        if p.life <= 0 then
            table.remove(self.particles, i)
        else
            p.vy = p.vy + p.gravity * dt
            p.x = p.x + p.vx * dt
            p.y = p.y + p.vy * dt
        end
    end
    for i = #self.popups, 1, -1 do
        local p = self.popups[i]
        p.life = p.life - dt
        p.y = p.y - dt * 16
        if p.life <= 0 then table.remove(self.popups, i) end
    end
    for _, map in ipairs({self.pops, self.squashes}) do
        for key, t in pairs(map) do
            t.t = t.t + dt
            if t.t >= t.dur then map[key] = nil end
        end
    end
    for i = #self.flyers, 1, -1 do
        local f = self.flyers[i]
        f.t = f.t + dt
        if f.t >= f.dur then
            table.remove(self.flyers, i)
            if f.onLand then f.onLand() end
        end
    end
end

-- Number of live effects of every kind.
function Fx:count()
    local n = #self.particles + #self.popups + #self.flyers
    for _ in pairs(self.pops) do n = n + 1 end
    for _ in pairs(self.squashes) do n = n + 1 end
    return n
end

-- Drops particles and flyers (the break keeps only its own effects).
function Fx:clearActions()
    self.particles = {}
    self.flyers = {}
end

-- Coin ticker: moves `display` toward `target`, faster for larger gaps, so a
-- gain or a spend settles within about a second. Returns the new value.
function Fx.tickToward(display, target, dt)
    local gap = target - display
    if math.abs(gap) < 0.01 then return target end
    local step = math.max(math.abs(gap) * FX_TICKER_RATE, FX_TICKER_MIN_SPEED) * dt
    if step >= math.abs(gap) then return target end
    return display + (gap > 0 and step or -step)
end

-- Draw ---------------------------------------------------------------------------

function Fx:drawParticles()
    for _, p in ipairs(self.particles) do
        local c = p.color
        local a = math.min(1, p.life / p.maxLife * 2)
        love.graphics.setColor(c[1], c[2], c[3], (c[4] or 1) * a)
        local s = p.size
        if p.shape == 'spark' and p.life / p.maxLife > 0.5 then
            -- a small plus sign while young
            love.graphics.rectangle('fill', math.floor(p.x) - 1, math.floor(p.y), 3, 1)
            love.graphics.rectangle('fill', math.floor(p.x), math.floor(p.y) - 1, 1, 3)
        else
            love.graphics.rectangle('fill', math.floor(p.x), math.floor(p.y), s, s)
        end
    end
end

function Fx:drawPopups(font)
    love.graphics.setFont(font)
    for _, p in ipairs(self.popups) do
        local c = p.color
        local age = p.maxLife - p.life
        local k = math.min(1, age / FX_POP_TIME)
        local scale = 1 + FX_POP_SCALE * math.sin(math.pi * k)
        love.graphics.setColor(c[1], c[2], c[3], math.min(1, p.life * 2))
        love.graphics.printf(p.text, math.floor(p.x), math.floor(p.y), 80, 'center', 0, scale, scale, 40, 0)
    end
end

function Fx:drawFlyers()
    for _, f in ipairs(self.flyers) do
        local x, y, scale = Fx.flyerPosition(f)
        local w, h = f.image:getDimensions()
        local s = f.size / math.max(w, h) * scale
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(f.image, math.floor(x), math.floor(y), 0, s, s, w / 2, h / 2)
    end
end
