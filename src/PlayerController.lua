-- First-person capsule controller for the backrooms.
--
-- The player is a vertical capsule: (x, y, z) is the bottom of the capsule
-- (the feet), it is `height` tall and `radius` wide. Each update moves the
-- capsule by its walk velocity and gravity in small sub-steps and, after every
-- sub-step, pushes it out of any collider it overlaps using
-- g3d.collisions.capsuleIntersection (used as-is). Pushing out along the
-- contact normal removes only the part of the motion that goes into a surface,
-- so the player slides along walls; repeating the push-out a few times lets
-- corners (two walls, wall + floor) settle instead of sticking.
--
-- Colliders are tables {verts = <g3d vertex list>, transform = <table with
-- translation (and optional scale)>, min = {x,y,z}, max = {x,y,z}}, as built by
-- Room. g3d's collision functions ignore model rotation, so colliders must be
-- axis-aligned (Room only builds axis-aligned boxes).
--
-- Climbing (beanstalks): `climbables` is a list of volumes {min, max}. The
-- player starts climbing by pressing forward inside one while standing on
-- something (a falling player is not caught, and standing or strafing at the
-- base does not latch on), and keeps climbing while still inside it.
-- While climbing there is no gravity: forward input moves up at
-- BACKROOMS_CLIMB_SPEED, back input moves down, and otherwise the player
-- holds on. The feet never rise above the volume's top, so the player hangs
-- there and leaves by walking off sideways, e.g. onto a ledge.
PlayerController = Class{}

-- math.atan2 is LuaJIT/5.1; Lua 5.3+ only has the two-argument math.atan
local atan2 = math.atan2 or math.atan

function PlayerController:init(x, y, z, opts)
    opts = opts or {}
    self.radius = opts.radius or BACKROOMS_PLAYER_RADIUS
    self.height = opts.height or BACKROOMS_PLAYER_HEIGHT
    self.eyeHeight = opts.eyeHeight or BACKROOMS_EYE_HEIGHT
    self.speed = opts.speed or BACKROOMS_WALK_SPEED
    self.gravity = opts.gravity or BACKROOMS_GRAVITY
    self:setPosition(x or 0, y or 0, z or 0)
end

function PlayerController:setPosition(x, y, z)
    self.x, self.y, self.z = x, y, z
    self.vz = 0
    self.grounded = false
    self.climbing = nil
end

function PlayerController:eyePosition()
    return self.x, self.y, self.z + self.eyeHeight
end

-- tip (top) and base (bottom) points of the capsule, as g3d expects
function PlayerController:capsule()
    return self.x, self.y, self.z + self.height, self.x, self.y, self.z
end

function PlayerController:bounds()
    local r = self.radius
    return {self.x - r, self.y - r, self.z}, {self.x + r, self.y + r, self.z + self.height}
end

local function boxesOverlap(amin, amax, bmin, bmax, margin)
    margin = margin or 0
    for i = 1, 3 do
        if amax[i] < bmin[i] - margin or amin[i] > bmax[i] + margin then return false end
    end
    return true
end
PlayerController.boxesOverlap = boxesOverlap

-- Horizontal walk velocity for `input` = {forward = -1..1, strafe = -1..1}
-- (strafe +1 = right) relative to a camera yaw `direction` (g3d convention:
-- forward is (cos d, sin d)). Diagonals are normalised.
function PlayerController:walkVelocity(input, direction)
    local f, s = input.forward or 0, input.strafe or 0
    if f == 0 and s == 0 then return 0, 0 end
    -- same trigonometry as g3d.camera.firstPersonMovement (moveY +1 = left)
    local angle = atan2(-s, f)
    return math.cos(direction + angle) * self.speed, math.sin(direction + angle) * self.speed
end

-- Push the capsule out of every overlapping collider. Returns the number of
-- contacts resolved. Sets self.grounded on supporting contacts and cancels
-- vertical velocity into floors and ceilings.
function PlayerController:resolve(colliders)
    local contacts = 0
    local r = self.radius
    for _ = 1, BACKROOMS_RESOLVE_ITERATIONS do
        local pushed = false
        for _, c in ipairs(colliders) do
            local pmin, pmax = self:bounds()
            if boxesOverlap(pmin, pmax, c.min, c.max, 0.01) then
                local tx, ty, tz, bx, by, bz = self:capsule()
                local len, _, _, _, nx, ny, nz =
                    g3d.collisions.capsuleIntersection(c.verts, c.transform, tx, ty, tz, bx, by, bz, r)
                if len and len < r and nx then
                    local depth = r - len + BACKROOMS_SKIN
                    self.x = self.x + nx * depth
                    self.y = self.y + ny * depth
                    self.z = self.z + nz * depth
                    if nz > BACKROOMS_GROUND_NORMAL then
                        self.grounded = true
                        if self.vz < 0 then self.vz = 0 end
                    elseif nz < -BACKROOMS_GROUND_NORMAL and self.vz > 0 then
                        self.vz = 0
                    end
                    contacts = contacts + 1
                    pushed = true
                end
            end
        end
        if not pushed then break end
    end
    return contacts
end

-- The climbable volume the capsule is inside, or nil. Inside means the
-- capsule's bounding box overlaps the volume horizontally and the feet are
-- between its bottom and top.
function PlayerController:climbableAt(climbables)
    local pmin, pmax = self:bounds()
    for _, v in ipairs(climbables or {}) do
        if pmax[1] > v.min[1] and pmin[1] < v.max[1] and pmax[2] > v.min[2] and pmin[2] < v.max[2]
            and self.z >= v.min[3] - BACKROOMS_CLIMB_MARGIN and self.z <= v.max[3] + BACKROOMS_CLIMB_MARGIN then
            return v
        end
    end
    return nil
end

-- Advance the controller by dt. `input` is {forward, strafe}; `direction` is
-- the camera yaw from g3d.camera.getDirectionPitch(); `colliders` as above;
-- `climbables` (optional) as described at the top.
function PlayerController:update(dt, input, direction, colliders, climbables)
    dt = math.min(dt, BACKROOMS_MAX_DT)
    input = input or {}
    local vx, vy = self:walkVelocity(input, direction or 0)

    -- climbing: continues while inside; starts only from standing + forward
    local volume = self:climbableAt(climbables)
    if volume and not (self.climbing or (self.grounded and (input.forward or 0) > 0)) then volume = nil end
    self.climbing = volume
    if volume then
        local f = input.forward or 0
        self.vz = (f > 0 and BACKROOMS_CLIMB_SPEED) or (f < 0 and -BACKROOMS_CLIMB_SPEED) or 0
    else
        self.vz = math.max(self.vz - self.gravity * dt, -BACKROOMS_TERMINAL_SPEED)
    end

    local longest = math.max(math.abs(vx), math.abs(vy), math.abs(self.vz)) * dt
    local steps = math.max(1, math.ceil(longest / BACKROOMS_MAX_STEP))
    local h = dt / steps

    self.grounded = false
    for _ = 1, steps do
        -- vz is re-read each sub-step: landing zeroes it mid-frame
        self.x = self.x + vx * h
        self.y = self.y + vy * h
        self.z = self.z + self.vz * h
        if volume and self.z > volume.max[3] then
            self.z = volume.max[3]              -- hang at the top
            if self.vz > 0 then self.vz = 0 end
        end
        self:resolve(colliders or {})
    end
end
