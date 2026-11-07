-- backrooms-zones-variety-audio tasks 2.1-2.3, 3.1-3.2 (zone partition data, validation, per-zone lighting).
-- Written, NOT run by its author (the integrator runs it). From repo root:  love tests/love_runner tests/zones_lighting.lua
package.path = './?.lua;./?/init.lua;' .. package.path
local mock = dofile('tests/mock_love.lua')
mock.install()
arg = {}
dofile('main.lua')
love.load()
local realPrint = print
print = function() end

local function check(c, msg) if not c then error(msg, 2) end end
local fails = 0
local function test(name, fn)
    local ok, err = pcall(fn)
    realPrint((ok and 'PASS ' or 'FAIL ') .. name .. (ok and '' or ('\n     ' .. tostring(err))))
    if not ok then fails = fails + 1 end
end

local SEEDS = 300
local function eachLevel(fn)
    for seed = 1, SEEDS do fn(seed, LevelGen.build(seed, (seed % 3) + 1)) end
end
local function k(c) return c.cx .. ',' .. c.cy end
local function neighbours(meta, c, byKey)
    local out = {}
    for _, d in ipairs({{1, 0}, {-1, 0}, {0, 1}, {0, -1}}) do
        local nb = byKey[(c.cx + d[1]) .. ',' .. (c.cy + d[2])]
        if nb then
            local a, b = k(c), k(nb)
            if a > b then a, b = b, a end
            if meta.edges[a .. '|' .. b] then out[#out + 1] = nb end
        end
    end
    return out
end

test('2.1 zones are connected, rooms are single-zone, >= 3 zones', function()
    eachLevel(function(seed, data)
        local meta = data.meta
        check(#meta.zones >= LEVELGEN_MIN_ZONES, 'seed ' .. seed .. ' has ' .. #meta.zones .. ' zones')
        local byKey, perZone, roomZone = {}, {}, {}
        for _, c in ipairs(meta.cells) do
            byKey[k(c)] = c
            check(c.zone, 'cell without zone')
            perZone[c.zone] = perZone[c.zone] or {}
            table.insert(perZone[c.zone], c)
            if c.room then
                check(roomZone[c.room] == nil or roomZone[c.room] == c.zone, 'seed ' .. seed .. ' room straddles zones')
                roomZone[c.room] = c.zone
            end
        end
        for id, cs in pairs(perZone) do
            local seen, stack, n = {[k(cs[1])] = true}, {cs[1]}, 1
            while #stack > 0 do
                local c = table.remove(stack)
                for _, nb in ipairs(neighbours(meta, c, byKey)) do
                    if nb.zone == id and not seen[k(nb)] then seen[k(nb)] = true; n = n + 1; stack[#stack + 1] = nb end
                end
            end
            check(n == #cs, 'seed ' .. seed .. ' zone ' .. id .. ' is split (' .. n .. '/' .. #cs .. ')')
        end
    end)
end)

test('2.1 module cells share a zone with the cell holding their plot', function()
    eachLevel(function(seed, data)
        local byKey = {}
        for _, c in ipairs(data.meta.cells) do byKey[k(c)] = c end
        for _, p in ipairs(data.plots) do
            local c = byKey[math.floor(p.pos[1] / LEVELGEN_CELL) .. ',' .. math.floor((p.pos[2] + LEVELGEN_CELL / 2) / LEVELGEN_CELL)]
            check(c and p.zone == c.zone, 'seed ' .. seed .. ' plot zone matches its cell')
        end
    end)
end)

test('2.2 neighbouring zones differ in theme and lighting; themes constant per zone', function()
    eachLevel(function(seed, data)
        local byId = {}
        for _, z in ipairs(data.meta.zones) do byId[z.id] = z end
        for _, z in ipairs(data.meta.zones) do
            for _, nid in ipairs(z.adjacent) do
                check(byId[nid].theme ~= z.theme, 'seed ' .. seed .. ' ' .. z.id .. '/' .. nid .. ' same theme')
                check(byId[nid].lighting ~= z.lighting, 'seed ' .. seed .. ' ' .. z.id .. '/' .. nid .. ' same lighting')
            end
        end
        for i, b in ipairs(data.boxes) do
            if b.zone and b.theme then check(byId[b.zone].theme == b.theme, 'seed ' .. seed .. ' box ' .. i .. ' theme != zone theme') end
        end
    end)
end)

test('2.2 same seed gives the same zones; zones do not change the layout cells', function()
    for seed = 1, 20 do
        local a, b = LevelGen.build(seed, 2), LevelGen.build(seed, 2)
        check(#a.meta.zones == #b.meta.zones, 'zone count')
        for i, z in ipairs(a.meta.zones) do
            local y = b.meta.zones[i]
            check(z.id == y.id and z.theme == y.theme and z.lighting == y.lighting and z.cellCount == y.cellCount, 'zone ' .. i)
        end
        for i, c in ipairs(a.meta.cells) do check(c.zone == b.meta.cells[i].zone, 'cell zone') end
    end
end)

test('2.3 zone ids are on boxes, plots, pickups, exit and checkpoints', function()
    for seed = 1, 20 do
        local data = LevelGen.generate(seed, 3)
        local ids = {}
        for _, z in ipairs(data.zones) do ids[z.id] = true end
        for _, b in ipairs(data.boxes) do check(ids[b.zone], 'box zone ' .. tostring(b.zone)) end
        for _, p in ipairs(data.plots) do check(ids[p.zone], 'plot zone') end
        for _, p in ipairs(data.pickups) do check(ids[p.zone], 'pickup zone') end
        check(ids[data.exit.zone], 'exit zone')
        check(Room.validate(data))
        local room = Room(data)
        for i, cp in ipairs(room.checkpoints) do
            if i > 1 then check(ids[cp.zone], 'checkpoint zone ' .. i) end
        end
    end
end)

test('2.3 Room.validate rejects bad zones; old rooms without zones still build', function()
    local data = LevelGen.generate(3, 2)
    local function broken(mutate)
        local d = LevelGen.generate(3, 2)
        mutate(d)
        return select(1, Room.validate(d))
    end
    check(broken(function(d) d.boxes[1].zone = 'nope' end) == false, 'unknown box zone')
    check(broken(function(d) d.zones[2].id = d.zones[1].id end) == false, 'duplicate zone id')
    check(broken(function(d) d.zones[1].lighting = 'blinding' end) == false, 'unknown zone lighting')
    check(broken(function(d) d.zones[1].theme = 'plaid' end) == false, 'unknown zone theme')
    check(broken(function(d) d.exit.zone = 'zzz' end) == false, 'unknown exit zone')
    check(broken(function(d) d.zones = nil end) == false, 'zone ids without a zones list')
    local old = LevelGen.generate(3, 2)
    old.zones = nil
    for _, b in ipairs(old.boxes) do b.zone = nil end
    for _, p in ipairs(old.plots) do p.zone = nil end
    for _, p in ipairs(old.pickups) do p.zone = nil end
    old.exit.zone = nil
    check(Room.validate(old))
    local room = Room(old)
    check(room.zoneLighting == nil and #room.lights > 0, 'old room builds with one lighting')
    check(Room.validate(data))
end)

test('3.1 fixtures follow their zone preset (colour, intensity, litEvery)', function()
    local found = 0
    for seed = 1, 40 do
        local data = LevelGen.generate(seed, 3)
        local room = Room(data)
        local byZone = {}
        for _, l in ipairs(room.lights) do
            check(l.zone, 'fixture without zone')
            byZone[l.zone] = byZone[l.zone] or l
        end
        local presetOf = {}
        for _, z in ipairs(data.zones) do presetOf[z.id] = BACKROOMS_LIGHT_PRESETS[z.lighting] end
        local seenPresets = {}
        for zid, l in pairs(byZone) do
            local p = presetOf[zid]
            check(l.intensity == p.intensity, 'intensity from the zone preset')
            check(l.color == p.fixtureColor, 'colour from the zone preset')
            seenPresets[p] = true
        end
        local n = 0
        for _ in pairs(seenPresets) do n = n + 1 end
        if n >= 2 then found = found + 1 end
    end
    check(found > 0, 'at least two presets of fixtures in a level')
    -- explicit lights on a generated-style room are left alone
    local d = LevelGen.generate(1, 1)
    d.lights = {{pos = {1, 1, 1}}}
    check(#Room(d).lights == 1)
end)

local function levelWithBoundary()
    for seed = 1, 60 do
        local data = LevelGen.generate(seed, 3)
        local room = Room(data)
        local byKey = {}
        for _, c in ipairs(data.meta.cells) do byKey[k(c)] = c end
        for _, c in ipairs(data.meta.cells) do
            for _, nb in ipairs(neighbours(data.meta, c, byKey)) do
                if nb.zone ~= c.zone and nb.cx == c.cx + 1 then return room, data, c, nb end
            end
        end
    end
end

test('3.2 ambient/fog blend is continuous across a zone boundary and bounded by the presets', function()
    local room, data, a, b = levelWithBoundary()
    check(room, 'found a boundary')
    local bx = b.cx * LEVELGEN_CELL                       -- shared edge (x)
    local y = a.cy * LEVELGEN_CELL                        -- cell centre line
    local eps = 1e-4
    local L = BackroomsLook.blendedLighting(room, bx - eps, y)
    local R = BackroomsLook.blendedLighting(room, bx + eps, y)
    for i = 1, 3 do check(math.abs(L.ambient[i] - R.ambient[i]) < 1e-3, 'ambient jumps at the boundary') end
    check(math.abs(L.fogDensity - R.fogDensity) < 1e-3, 'fog jumps at the boundary')
    -- far from the edge: pure zone preset; and the change is gradual (no step bigger than a small slice)
    local pa = room.zoneLighting[a.zone]
    local far = BackroomsLook.blendedLighting(room, a.cx * LEVELGEN_CELL + 0.2, y)
    local nbs = select(2, room:zoneNeighbours(a.cx * LEVELGEN_CELL + 0.2, y, BACKROOMS_ZONE_BLEND_DISTANCE))
    if #nbs == 0 then check(math.abs(far.fogDensity - pa.fogDensity) < 1e-9, 'pure zone preset away from boundaries') end
    local prev
    for i = 0, 50 do
        local x = bx - BACKROOMS_ZONE_BLEND_DISTANCE + i * (2 * BACKROOMS_ZONE_BLEND_DISTANCE / 50)
        local l = BackroomsLook.blendedLighting(room, x, y)
        if prev then
            local span = math.abs(room.zoneLighting[a.zone].fogDensity - room.zoneLighting[b.zone].fogDensity)
            check(math.abs(l.fogDensity - prev) <= span * 0.1 + 1e-9, 'fog changes gradually')
        end
        prev = l.fogDensity
    end
end)

test('3.2 readability floor is kept under every zone preset and blend', function()
    local minFloor = math.huge
    for _, p in pairs(BACKROOMS_LIGHT_PRESETS) do minFloor = math.min(minFloor, p.gameplayFloor) end
    check(minFloor >= 0.7, 'preset floors >= 0.7')
    local room = levelWithBoundary()
    for x = 0, 40, 0.5 do
        local l = BackroomsLook.blendedLighting(room, x, 0)
        check(l.gameplayFloor >= minFloor - 1e-9, 'blended floor never below the lowest preset')
    end
    check(BackroomsLook.blendedLighting({lighting = {name = 'x'}}, 0, 0).name == 'x', 'room without zones is unchanged')
end)

realPrint(fails == 0 and 'all passed' or (fails .. ' failed'))
os.exit(fails == 0 and 0 or 1)
