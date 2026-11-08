-- Focused regression for the uproot standing check (all crop types).
-- Run:  love tests/love_runner tests/uproot_standing.lua
package.path = './?.lua;./?/init.lua;' .. package.path
local realPrint = print
local mock = dofile('tests/mock_love.lua')
mock.install()
-- tests/mock_love.lua has no love.math (src/Silhouette.lua needs it at load); stub locally.
love.math = love.math or {newRandomGenerator = function() return {random = function(_, a, b) return a or 0.5 end, setSeed = function() end} end,
    random = math.random, setRandomSeed = function() end}
love.image.newImageData = function() return {setPixel = function() end, mapPixel = function() end} end
local _ni = love.graphics.newImage
love.graphics.newImage = function(...) local ok, t = pcall(_ni, ...); if ok and t and t.setFilter then return t end; return {setFilter = function() end, setWrap = function() end} end
arg = {}
dofile('main.lua')
love.load()
print = function() end

local passed, failed = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then passed = passed + 1; realPrint('PASS ' .. name)
    else failed = failed + 1; realPrint('FAIL ' .. name .. '\n     ' .. tostring(err)) end
end
local function eq(a, b, m) if a ~= b then error((m or 'eq') .. ': got ' .. tostring(a) .. ', want ' .. tostring(b), 2) end end

-- Fixtures use real room data and the positions tests/run.lua uses: room 2 (pit-and-gap)
-- has the free plot 'pit' (plant from the rim at x = -4.6) and room 1 has the demo plot.
local ROOM_PIT = BACKROOMS_ROOMS[2]
local ROOM_DEMO = BACKROOMS_ROOMS[1]
local RIM = {-4.6, 0, 0}

local function setup(room, t, n)
    local back = BackroomsState()
    gStateMachine.current = back
    back:enter(CarryOverGameData(NewGameData({seeds = {[t] = n}})), {room})
    back.gameData.seeds[t] = n
    back.selectedSeed = t
    return back
end

local function atRim(back) back.player:setPosition(RIM[1], RIM[2], RIM[3]) end

local function plantPit(back, t)
    atRim(back)
    local plot = back.room:plotById('pit')
    assert(plot and not plot.crop, 'free pit plot')
    local ok, why = back:plant()
    assert(ok, 'planted: ' .. tostring(why))
    return plot
end

local function grow(back, t)
    Timer.update(CROP_DEFS[t].growTime + 0.01, back.timers)
    back.room:updateCrops({1000, 1000, 1000}, {1001, 1001, 1001})
end

-- Player box for feet (x, y, z), as PlayerController:bounds() builds it.
local function box(x, y, z)
    local r, h = BACKROOMS_PLAYER_RADIUS, BACKROOMS_PLAYER_HEIGHT
    return {x - r, y - r, z}, {x + r, y + r, z + h}
end

local function tryUproot(back, plot, x, y, z)
    local pmin, pmax = box(x, y, z)
    local ok, why = back.room:uproot(plot, pmin, pmax)
    return ok, why
end

for _, t in ipairs({'pumpkin', 'beanstalk', 'vine'}) do
    test(t .. ': standing beside (flush, skin gap, tiny overlap, any side) uproots; on top blocks', function()
        local function fresh()
            local back = setup(ROOM_PIT, t, 1)
            local plot = plantPit(back, t)
            grow(back, t)
            assert(plot.crop.grown, 'grown')
            return back, plot, plot.crop
        end
        local r, skin = BACKROOMS_PLAYER_RADIUS, BACKROOMS_SKIN
        -- beside on each of the four sides, at floor height and at crop-base height
        local back0, plot0, c0 = fresh()
        local cx, cy = (c0.min[1] + c0.max[1]) / 2, (c0.min[2] + c0.max[2]) / 2
        local sides = {
            {c0.min[1] - r, cy}, {c0.max[1] + r, cy}, {cx, c0.min[2] - r}, {cx, c0.max[2] + r},
        }
        local dirs = {{-1, 0}, {1, 0}, {0, -1}, {0, 1}}
        for gapName, gap in pairs({flush = 0, skin = skin, overlap = -0.004}) do
            for i, s in ipairs(sides) do
                for _, z in ipairs({c0.min[3], c0.min[3] - 0.5, c0.max[3] - 0.3}) do
                    local back, plot = fresh()
                    local ok, why = tryUproot(back, plot, s[1] + dirs[i][1] * gap, s[2] + dirs[i][2] * gap, z)
                    assert(ok, string.format('%s side %d z %.2f gap %s refused (%s)', t, i, z, gapName, tostring(why)))
                end
            end
        end
        -- diagonal beside a corner: the square box overlaps the crop's corner but the round
        -- footprint does not, so that is still beside, not on it
        do
            local back, plot, c = fresh()
            local d = r * 0.72
            local ok = tryUproot(back, plot, c.max[1] + d, c.max[2] + d, c.max[3])
            assert(ok, 'diagonal corner is beside')
        end
        -- on top: centre, near each edge (centre just inside the edge), feet at the top height
        local onTop = {{cx, cy}, {c0.min[1] + 0.05, cy}, {c0.max[1] - 0.05, cy}, {cx, c0.min[2] + 0.05}, {cx, c0.max[2] - 0.05},
                       {c0.max[1] + r - 0.05, cy}}   -- hanging off the edge but footprint still over it
        for i, p in ipairs(onTop) do
            for _, dz in ipairs({0, 0.01, -0.01, BACKROOMS_UPROOT_TOP_EPS * 0.9}) do
                local back, plot, c = fresh()
                local ok, why = tryUproot(back, plot, p[1], p[2], c.max[3] + dz)
                eq(ok, false, t .. ' on-top case ' .. i .. ' dz ' .. dz); eq(why, 'standing')
                assert(plot.crop == c, 'crop remains')
            end
        end
        -- clearly above or below the top (bridge/platform over or under the crop) is not standing on it
        for _, dz in ipairs({0.2, 1.0, -0.2, -0.6}) do
            local back, plot, c = fresh()
            local ok, why = tryUproot(back, plot, cx, cy, c.max[3] + dz)
            assert(ok, t .. ' footprint over crop but feet ' .. dz .. ' from top should not block (' .. tostring(why) .. ')')
        end
    end)
end

test('pumpkin: real collision push-out beside the crop leaves uproot allowed (RMB/X path)', function()
    local back = setup(ROOM_PIT, 'pumpkin', 1)
    local plot = plantPit(back, 'pumpkin')
    grow(back, 'pumpkin')
    local c = plot.crop
    local p = back.player
    p:setPosition(c.max[1] + 0.2, (c.min[2] + c.max[2]) / 2, c.min[3])   -- overlapping the side
    for _ = 1, 10 do
        p:update(1 / 60, {}, 0, back.room:solidColliders())
    end
    assert(p.x - BACKROOMS_PLAYER_RADIUS >= c.max[1] - 1e-6, 'pushed out to the side (x=' .. p.x .. ')')
    local ok, why = back:uproot()
    assert(ok, 'uproot beside pumpkin: ' .. tostring(why))
end)

realPrint(string.format('\n%d passed, %d failed', passed, failed))
os.exit(failed == 0 and 0 or 1)
