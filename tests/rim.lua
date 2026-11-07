-- Pit-rim measurement for the Room 2 and Room 3 pit plots (polish M3). From
-- the repo root:
--   love tests/love_runner tests/rim.lua
--
-- For each room with a 'pit' plot, positions along y = 0 on the spawn-side
-- floor are sampled every 1 cm. At each one the real PlayerController is
-- placed and left idle for 1 s against the real room colliders. It counts
-- as standing if its feet stay at floor level, so the capsule's rounded base
-- sliding off the rim counts as falling. A position is plantable when it is
-- standing and Room:nearestPlot picks the pit plot there. The script prints
-- the rim (last standing x), the plantable span and the pit targeting at
-- 1.0 m and 2.0 m back from the rim. It exits 1 if a span is under
-- PIT_MIN_SPAN metres.
package.path = './?.lua;./?/init.lua;' .. package.path

local realPrint = print
local mock = dofile('tests/mock_love.lua')
mock.install()
arg = {}
dofile('main.lua')
love.load()
print = realPrint

local PIT_MIN_SPAN = 2.5
local STEP = 0.01

local function stands(room, x, y)
    local p = PlayerController(x, y, 0)
    for _ = 1, 60 do
        p:update(1 / 60, {forward = 0, strafe = 0}, 0, room:solidColliders(), room:climbVolumes())
    end
    return p.z > -0.02
end

local failures = 0
for index, data in ipairs(BACKROOMS_ROOMS) do
    local room = Room(data)
    local pit = room:plotById('pit')
    if pit then
        local x0 = data.spawn[1]
        -- walk the spawn-side floor toward the pit until the player falls
        local rim = nil
        local x = x0
        while x < pit.pos[1] do
            if stands(room, x, 0) then rim = x else break end
            x = x + STEP
        end
        assert(rim, 'room ' .. index .. ': spawn is not standing')
        -- leftmost standing position back toward the wall
        local back = x0
        while stands(room, back - STEP, 0) and back - STEP > x0 - 20 do back = back - STEP end

        local first, last = nil, nil
        x = back
        while x <= rim + 1e-9 do
            local plot = room:nearestPlot(x, 0, 0)
            if plot and plot.id == 'pit' then
                first = first or x
                last = x
            end
            x = x + STEP
        end
        local span = first and (last - first) or 0
        local function at(d)
            local plot = room:nearestPlot(rim - d, 0, 0)
            return plot and plot.id or 'none'
        end
        local reach = pit.reach or BACKROOMS_PLANT_RANGE
        realPrint(string.format(
            'room %d (%s): pit plot x=%.2f z=%.2f reach %.2f | floor stands from x=%.2f to rim x=%.2f | ' ..
            'pit plantable x=[%s, %s] span %.2f m | 1.0 m back: %s | 2.0 m back: %s',
            index, data.id, pit.pos[1], pit.pos[3], reach, back, rim,
            first and string.format('%.2f', first) or '-', last and string.format('%.2f', last) or '-',
            span, at(1.0), at(2.0)))
        if span < PIT_MIN_SPAN - 1e-6 then
            realPrint(string.format('FAIL room %d: plantable span %.2f m < %.1f m', index, span, PIT_MIN_SPAN))
            failures = failures + 1
        end
    end
end
realPrint(failures == 0 and 'rim: ok' or ('rim: ' .. failures .. ' failed'))
os.exit(failures == 0 and 0 or 1)
