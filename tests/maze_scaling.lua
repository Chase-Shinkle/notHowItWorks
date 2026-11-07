-- Maze section 6.1/6.2: difficulty rows scale up and never shrink. Pure data
-- checks (no generation). Run from the repo root: lua tests/maze_scaling.lua
package.path = './?.lua;./?/init.lua;' .. package.path
dofile('src/constants.lua')
local function dims(g) if type(g) == 'number' then return g, g end return g[1], g[2] end
local rows = LEVELGEN_DIFFICULTY
assert(#rows == BACKROOMS_GENERATED_LEVELS)
local first, last = rows[1], rows[#rows]
for i, r in ipairs(rows) do
    assert(r.obstacles == i + 1, 'row ' .. i .. ' obstacles 2/3/4')
    local w, h = dims(r.grid)
    assert(w >= 6 and h >= 6 and w <= 9 and h <= 9, 'grid 6x6..9x9')
    assert(r.minPath >= 14 and r.minTurns >= 3 and r.branches >= 1)
    if i > 1 then
        local pw, ph = dims(rows[i - 1].grid)
        assert(w * h >= pw * ph and r.minPath >= rows[i - 1].minPath
            and r.branches >= rows[i - 1].branches and r.minTurns >= rows[i - 1].minTurns, 'row ' .. i .. ' shrinks')
    end
end
local fw, fh = dims(first.grid); local lw, lh = dims(last.grid)
assert(lw * lh > fw * fh and last.minPath > first.minPath, 'last exceeds first')
-- level-length spec: critical path >= 14 cells AND pure walking time >= 30 s
-- (centre-to-centre distance of a minPath-cell path, at the walking speed)
for i, r in ipairs(rows) do
    assert(r.minPath >= 14, 'row ' .. i .. ' path at least 14 cells')
    local secs = (r.minPath - 1) * LEVELGEN_CELL / BACKROOMS_WALK_SPEED
    assert(secs >= 30, string.format('row %d walking time %.1f s < 30 s', i, secs))
end
print('maze_scaling ok')
