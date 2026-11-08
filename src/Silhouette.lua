-- A rare, purely visual dark humanoid billboard far down a long straight hall
-- in the backrooms. It never touches collision, plots, seeds, the exit,
-- solvability or the run RNG (own generator). It only appears when the player
-- is looking down a clear, floored sightline, never behind or near them, and
-- it fades out when approached or after a few seconds.
Silhouette = {
    COOLDOWN_MIN = 180,     -- seconds between appearances (and before the first)
    COOLDOWN_MAX = 420,
    MIN_DIST = 16.5,        -- spawn distance floor (>16 m)
    MAX_DIST = 30,
    VANISH_DIST = 8,        -- fades out when the player gets this close
    LIFETIME = 5,           -- seconds visible at most
    FADE_IN = 1.2,
    FADE_OUT = 1.0,
    HEIGHT = 1.9,
    PEAK_ALPHA = 0.85,
    CHECK_EVERY = 0.5,
}

local rng = love.math.newRandomGenerator(os.time())
local S = Silhouette
S.cooldown, S.checkIn, S.active, S.board, S.image = nil, 0, nil, nil, nil
S.forced = false   -- true only for a dev-harness appearance

-- Procedural 24x64 humanoid: head, neck, shoulders, torso, arms, legs.
local function buildImage()
    local ok, data = pcall(love.image.newImageData, 24, 64)
    if not ok or not data then return nil end
    local function inside(x, y)
        local dx = x - 11.5
        if y >= 2 and y < 12 then return (dx * dx) / 20 + ((y - 7) ^ 2) / 28 <= 1 end -- head
        if y >= 12 and y < 15 then return math.abs(dx) <= 2 end                       -- neck
        if y >= 15 and y < 40 then
            local w = y < 19 and 8 or 5                                               -- shoulders / torso
            if math.abs(dx) <= w then return true end
            return math.abs(dx) <= 8 and math.abs(dx) >= 6.5 and y < 38              -- arms
        end
        if y >= 40 and y < 62 then return math.abs(dx) >= 0.8 and math.abs(dx) <= 4.5 end -- legs
        return false
    end
    data:mapPixel(function(x, y)
        if not inside(x, y) then return 0, 0, 0, 0 end
        local s = 0.02 + 0.03 * ((x * 7 + y * 3) % 5) / 5
        return s, s, s * 1.1, 1
    end)
    local img = love.graphics.newImage(data)
    img:setFilter('nearest', 'nearest')
    return img
end

local function pointBlocked(colliders, x, y, z)
    for _, c in ipairs(colliders) do
        if x >= c.min[1] and x <= c.max[1] and y >= c.min[2] and y <= c.max[2]
            and z >= c.min[3] and z <= c.max[3] then return true end
    end
    return false
end

-- Walkable floor top beneath (x, y): highest collider top below probeZ.
local function floorTop(colliders, x, y, probeZ)
    local best
    for _, c in ipairs(colliders) do
        if x >= c.min[1] and x <= c.max[1] and y >= c.min[2] and y <= c.max[2]
            and c.max[3] <= probeZ and (not best or c.max[3] > best) then best = c.max[3] end
    end
    return best
end

Silhouette.floorTop = floorTop

-- Pure query: returns x, y, z (feet) of an eligible spot straight ahead of
-- (px, py, feetZ) along yaw `dir`, or nil. The hall must be clear at body
-- height and solidly floored (level with the player) the whole way.
function Silhouette.findSpot(colliders, px, py, feetZ, dir)
    local own = floorTop(colliders, px, py, feetZ + 0.6)
    if not own or math.abs(own - feetZ) > 0.15 then return nil end
    local dx, dy = math.cos(dir), math.sin(dir)
    local heights = {feetZ + 0.3, feetZ + 1.0, feetZ + 1.7}
    local clear = 0
    local step = 0.5
    local d = step
    while d <= S.MAX_DIST + 1 do
        local x, y = px + dx * d, py + dy * d
        for _, h in ipairs(heights) do
            if pointBlocked(colliders, x, y, h) then d = nil; break end
        end
        if not d then break end
        local ft = floorTop(colliders, x, y, feetZ + 0.6)
        if not ft or math.abs(ft - feetZ) > 0.15 then break end
        clear = d
        d = d + step
    end
    -- a hall that is clear for `clear` metres; place the figure near its far end
    if clear < S.MIN_DIST + 1 then return nil end
    local dist = math.min(S.MAX_DIST, clear - 0.75)
    if dist < S.MIN_DIST then return nil end
    return px + dx * dist, py + dy * dist, feetZ
end

function Silhouette.reset()
    S.cooldown = rng:random(S.COOLDOWN_MIN, S.COOLDOWN_MAX)
    S.checkIn, S.active, S.forced = 0, nil, false
    if S.board then S.board = nil end
end

local function spawn(x, y, z)
    S.image = S.image or buildImage()
    if not S.image or not Billboard then return false end
    local ok, board = pcall(Billboard, {texture = S.image, pos = {x, y, z}, height = S.HEIGHT,
        color = {1, 1, 1, 0}})
    if not ok then return false end
    S.board = board
    S.active = {t = 0, alpha = 0, x = x, y = y}
    return true
end

-- Dev harness only: appear now, ignoring the cooldown. Reports itself as forced.
function Silhouette.debugForce(colliders, player, dir)
    local x, y, z = S.findSpot(colliders, player.x, player.y, player.z, dir)
    if not x then return false end
    S.forced = true
    return spawn(x, y, z)
end

-- paused: true while the pit-death fade runs. Reads state only; writes none.
function Silhouette.update(dt, room, player, dir, paused)
    if not S.cooldown then S.reset() end
    if S.active then
        local a = S.active
        a.t = a.t + dt
        local dist = math.sqrt((player.x - a.x) ^ 2 + (player.y - a.y) ^ 2)
        local fadingOut = a.out or paused or dist < S.VANISH_DIST or a.t > S.LIFETIME
        if fadingOut and not a.out then a.out = 0 end
        local alpha
        if a.out then
            a.out = a.out + dt
            alpha = a.alpha * math.max(0, 1 - a.out / S.FADE_OUT)
            if a.out >= S.FADE_OUT then S.active, S.board = nil, nil; S.forced = false; return end
        else
            alpha = S.PEAK_ALPHA * math.min(1, a.t / S.FADE_IN)
            a.alpha = alpha
        end
        S.board.color[4] = alpha
        return
    end
    if paused or not room then return end
    S.cooldown = S.cooldown - dt
    if S.cooldown > 0 then return end
    S.checkIn = S.checkIn - dt
    if S.checkIn > 0 then return end
    S.checkIn = S.CHECK_EVERY
    local x, y, z = S.findSpot(room:solidColliders(), player.x, player.y, player.z, dir)
    if x and spawn(x, y, z) then
        S.cooldown = rng:random(S.COOLDOWN_MIN, S.COOLDOWN_MAX)
    end
end

function Silhouette.draw(cx, cy)
    if not S.active or not S.board then return end
    S.board:faceCamera(cx, cy)
    S.board:draw()
    love.graphics.setColor(1, 1, 1, 1)
end

-- A room load drops any visible figure (keeps the cooldown).
function Silhouette.clearActive() S.active, S.board, S.forced = nil, nil, false end

function Silhouette.dispose()
    S.active, S.board, S.cooldown, S.forced = nil, nil, nil, false
end
