-- Full reachability sweep: for every backrooms room, every assignment of
-- {nothing, beanstalk, pumpkin, vine} to its plots (fully grown) is searched
-- with tests/reach.lua, and only the intended solutions may reach the exit.
-- Slower than tests/run.lua (which checks the key cases). From the repo root:
--   lua tests/reachability.lua        (or luajit)
package.path = './?.lua;./?/init.lua;' .. package.path

local realPrint = print
local mock = dofile('tests/mock_love.lua')
mock.install()
arg = {}
dofile('main.lua')
love.load()
print = realPrint
local Reach = dofile('tests/reach.lua')

-- The only plot assignments that should solve each room.
local SOLUTIONS = {
    tutorial = {'demo=beanstalk'},
    ['pit-and-gap'] = {'edge=vine pit=pumpkin'},
    ['pit-ledge-gap'] = {'foot=beanstalk lip=vine pit=pumpkin'},
}

local failures, searched = 0, 0
for i, data in ipairs(BACKROOMS_ROOMS) do
    local expected = {}
    for _, d in ipairs(SOLUTIONS[data.id] or {}) do expected[d] = true end
    for _, crops in ipairs(Reach.assignments(data)) do
        local name = Reach.describe(crops)
        local ok, reached, info = pcall(Reach.search, Reach.roomWith(data, crops))
        searched = searched + 1
        if not ok then
            failures = failures + 1
            realPrint(string.format('ERROR room %d %s: %s', i, name, tostring(reached)))
        else
            local want = expected[name] == true
            local status = (reached == want) and 'ok  ' or 'FAIL'
            if reached ~= want then failures = failures + 1 end
            realPrint(string.format('%s room %d %-40s reached=%-5s cells=%d maxX=%.2f maxZ=%.2f', status, i, name,
                tostring(reached), info.cells, info.maxX, info.maxZ))
        end
    end
end
realPrint(string.format('\n%d assignments searched, %d unexpected', searched, failures))
os.exit(failures == 0 and 0 or 1)
