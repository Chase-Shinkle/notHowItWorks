-- Focused assertions for backrooms-zones-variety-audio 3.3 (dressing by zone theme).
-- Standalone:  lua tests/zones_dressing.lua   (not yet run; check_all.sh integration is final integration's job)
package.path = './?.lua;./?/init.lua;' .. package.path
local realPrint = print
local mock = dofile('tests/mock_love.lua')
mock.install()
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

local SEEDS = {2026, 7, 1234}
local function level(seed) return LevelGen.build(seed, 2) end

test('every room type x theme has at least one themed prop', function()
    for _, rt in ipairs({'filler', 'hall', 'dead', 'nook', 'loop'}) do
        for _, th in ipairs(MATERIAL_THEME_NAMES) do
            local names = Dressing.propsFor(rt, th)
            assert(#names > 0, rt .. '/' .. th)
            for _, n in ipairs(names) do
                local ok = false
                for _, t in ipairs(PROP_CATALOGUE[n].themes) do ok = ok or t == th end
                assert(ok, n .. ' not themed ' .. th .. ' (fallback should be unneeded)')
            end
        end
    end
end)

test('props follow their zone theme', function()
    for _, seed in ipairs(SEEDS) do
        local d = level(seed)
        local theme = {}
        for _, z in ipairs(d.meta.zones) do theme[z.id] = z.theme end
        local n = 0
        for _, b in ipairs(d.billboards) do
            if b.dressing then
                n = n + 1
                assert(b.zone and theme[b.zone], 'prop has a zone')
                local ok = false
                for _, t in ipairs(PROP_CATALOGUE[b.prop].themes) do ok = ok or t == theme[b.zone] end
                assert(ok, b.prop .. ' in a ' .. theme[b.zone] .. ' zone')
            end
        end
        assert(n > 0, 'seed ' .. seed .. ' has props')
    end
end)

test('dressing is deterministic and leaves the layout alone', function()
    for _, seed in ipairs(SEEDS) do
        local a, b = level(seed), level(seed)
        assert(#a.billboards == #b.billboards)
        for i, p in ipairs(a.billboards) do
            assert(p.pos[1] == b.billboards[i].pos[1] and p.prop == b.billboards[i].prop)
        end
        assert(#a.boxes == a.meta.boxCount)
    end
end)

test('exclusion zones and doorways still hold', function()
    for _, seed in ipairs(SEEDS) do
        local d = level(seed)
        local ex = {}
        for _, p in ipairs(d.pickups or {}) do ex[#ex + 1] = {p.pos, 1.3} end
        if d.exit then ex[#ex + 1] = {d.exit.pos, 1.8} end
        ex[#ex + 1] = {d.spawn, 2.2}
        for _, b in ipairs(d.billboards) do
            if b.dressing then
                for _, e in ipairs(ex) do
                    local dx, dy = b.pos[1] - e[1][1], b.pos[2] - e[1][2]
                    assert(dx * dx + dy * dy >= e[2] ^ 2, 'prop inside an exclusion zone')
                end
            end
        end
    end
end)

realPrint(string.format('%d passed, %d failed', passed, failed))
os.exit(failed == 0 and 0 or 1)
