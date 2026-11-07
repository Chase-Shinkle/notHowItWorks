-- Layout dump for review (not a pass/fail test): ASCII map + top-down PNG per
-- generated level, straight from LevelGen.generate. From the repo root:
--   love tests/love_runner tests/maze_layout.lua
-- Env: MAZE_SEEDS ("1,2,3"), MAZE_DIFFS ("1,2,3"), MAZE_OUT ("/workspace/qa/maze").
-- Writes <out>/maze_d<diff>_s<seed>.png and <out>/layouts.txt. Reads only the
-- LevelGen meta interface (grid, path, chain, cells, edges, loopEdges, regions,
-- rooms) plus data.pickups / data.plots; optional fields from later sections
-- (cells with a module but no chain index = optional gates, meta.checkpoints,
-- meta.shortcuts) are drawn when present and ignored otherwise.
package.path = './?.lua;./?/init.lua;' .. package.path
local realImage = love.image          -- the mock replaces `love`; keep the real encoder
local realPrint = print
local mock = dofile('tests/mock_love.lua')
mock.install()
arg = {}
dofile('main.lua')
love.load()
print = realPrint

local function list(env, def)
    local out = {}
    for n in (os.getenv(env) or def):gmatch('%d+') do out[#out + 1] = tonumber(n) end
    return out
end
local seeds, diffs = list('MAZE_SEEDS', '1,2,3'), list('MAZE_DIFFS', '1,2,3')
local outDir = os.getenv('MAZE_OUT') or '/workspace/qa/maze'
os.execute('mkdir -p "' .. outDir .. '"')

local CELL = LEVELGEN_CELL
local function split(ek)
    local a, b, c, d = ek:match('^(-?%d+),(-?%d+)|(-?%d+),(-?%d+)$')
    return tonumber(a), tonumber(b), tonumber(c), tonumber(d)
end
local MOD_LETTER = {pit = 'P', gap = 'G', ledge = 'L'}

-- ASCII ------------------------------------------------------------------------
-- 2W+1 x 2H+1 characters, x to the right, y (cy) downward as printed. Cell chars:
-- S start, E exit, P/G/L gate (pit/gap/ledge; lowercase = optional gate),
-- * other critical-path cell, digit = region of an off-path cell.
-- Between cells: - | open, = " doorway, ~ : loop.
local function ascii(data)
    local m = data.meta
    local W, H = m.grid[1], m.grid[2]
    local g = {}
    for r = 1, 2 * H + 1 do g[r] = {} for c = 1, 2 * W + 1 do g[r][c] = ' ' end end
    local loop = {}
    for _, ek in ipairs(m.loopEdges or {}) do loop[ek] = true end
    for _, c in ipairs(m.cells) do
        local ch
        if c.start then ch = 'S' elseif c.exit then ch = 'E'
        elseif c.module then
            ch = MOD_LETTER[c.module] or '?'
            if not c.k then ch = ch:lower() end
        elseif c.onPath then ch = '*'
        else ch = tostring((c.region or 0) % 10) end
        g[2 * c.cy + 2][2 * c.cx + 2] = ch
    end
    for ek, kind in pairs(m.edges) do
        local ax, ay, bx, by = split(ek)
        local r, c = ay + by + 2, ax + bx + 2
        local horizontal = ay == by
        if loop[ek] then g[r][c] = horizontal and '~' or ':'
        elseif kind == 'door' then g[r][c] = horizontal and '=' or '"'
        else g[r][c] = horizontal and '-' or '|' end
    end
    local lines = {}
    for r = 1, 2 * H + 1 do lines[r] = (table.concat(g[r]):gsub('%s+$', '')) end
    return table.concat(lines, '\n')
end

local function describe(data, seed, diff)
    local m = data.meta
    local chain = {}
    for k, l in ipairs(m.chain) do
        chain[k] = string.format('%d:%s(%s)@%d,%d%s', k, l.module, l.seed, l.cell[1], l.cell[2],
            l.dir and (' dir ' .. l.dir[1] .. ',' .. l.dir[2] .. ' rot ' .. tostring(l.rot)) or '')
    end
    local crit, extra = 0, 0
    for _, pk in ipairs(data.pickups) do if pk.tier == 'critical' then crit = crit + 1 else extra = extra + 1 end end
    local rooms = m.rooms and #m.rooms or 0
    return string.format('== seed %d diff %d (level seed %d, attempt %s%s)\ngrid %dx%d, path %d cells (min %d), turns %d (min %d), loops %d, rooms %d, regions %d, boxes %d, pickups %d critical + %d extra, plots %d\nchain: %s',
        seed, diff, m.seed, tostring(m.attempt), m.fallback and ', FALLBACK' or '', m.grid[1], m.grid[2], m.pathLength,
        m.minPath, m.turns, m.minTurns, m.loops or 0, rooms, m.regions and #m.regions or 0, m.boxCount or #data.boxes,
        crit, extra, #(data.plots or {}), table.concat(chain, '  '))
end

-- PNG --------------------------------------------------------------------------
-- 3x5 bitmap font (upper case, digits, a few symbols), enough for the legend.
local FONT = {
    A = '010101111101101', B = '110101110101110', C = '011100100100011', D = '110101101101110', E = '111100110100111',
    F = '111100110100100', G = '011100101101011', H = '101101111101101', I = '111010010010111', J = '001001001101010',
    K = '101101110101101', L = '100100100100111', M = '101111111101101', N = '110101101101101', O = '010101101101010',
    P = '110101110100100', Q = '010101101111011', R = '110101110101101', S = '011100010001110', T = '111010010010010',
    U = '101101101101111', V = '101101101101010', W = '101101111111101', X = '101101010101101', Y = '101101010010010',
    Z = '111001010100111', ['0'] = '111101101101111', ['1'] = '010110010010111', ['2'] = '110001010100111',
    ['3'] = '110001010001110', ['4'] = '101101111001001', ['5'] = '111100110001110', ['6'] = '011100111101111',
    ['7'] = '111001010010010', ['8'] = '111101111101111', ['9'] = '111101111001110', ['-'] = '000000111000000',
    ['='] = '000111000111000', ['/'] = '001001010100100', [':'] = '000010000010000', ['.'] = '000000000000010',
    [','] = '000000000010100', ['('] = '001010010010001', [')'] = '100010010010100', ['+'] = '000010111010000',
    ['#'] = '101111101111101', ['*'] = '000101010101000', [' '] = '000000000000000',
}

local function newCanvas(w, h)
    local img = realImage.newImageData(w, h)
    local buf = {w = w, h = h, img = img}
    function buf.rect(x, y, rw, rh, c)
        for yy = math.max(0, math.floor(y)), math.min(h - 1, math.floor(y + rh) - 1) do
            for xx = math.max(0, math.floor(x)), math.min(w - 1, math.floor(x + rw) - 1) do
                img:setPixel(xx, yy, c[1], c[2], c[3], 1)
            end
        end
    end
    function buf.line(x0, y0, x1, y1, th, c, dash)
        local len = math.max(math.abs(x1 - x0), math.abs(y1 - y0), 1)
        for i = 0, len do
            if not dash or math.floor(i / dash) % 2 == 0 then
                local t = i / len
                buf.rect(x0 + (x1 - x0) * t - th / 2, y0 + (y1 - y0) * t - th / 2, th, th, c)
            end
        end
    end
    function buf.text(str, x, y, s, c)
        for i = 1, #str do
            local g = FONT[str:sub(i, i):upper()] or FONT[' ']
            for k = 0, 14 do
                if g:sub(k + 1, k + 1) == '1' then buf.rect(x + (k % 3) * s, y + math.floor(k / 3) * s, s, s, c) end
            end
            x = x + 4 * s
        end
    end
    return buf
end

local function rgb(r, g, b) return {r / 255, g / 255, b / 255} end
local COL = {
    bg = rgb(20, 22, 28), cell = rgb(46, 50, 62), room = rgb(64, 70, 86), edge = rgb(120, 126, 142),
    door = rgb(150, 156, 172), path = rgb(255, 214, 80), loop = rgb(80, 170, 255), start = rgb(60, 220, 100),
    exit = rgb(240, 70, 70), pit = rgb(255, 150, 40), gap = rgb(220, 90, 230), ledge = rgb(60, 220, 220),
    optional = rgb(150, 150, 150), crit = rgb(255, 235, 120), extra = rgb(240, 240, 240), plot = rgb(120, 255, 120),
    text = rgb(225, 228, 235), ckpt = rgb(255, 255, 255),
}
local REGION_TINT = {rgb(46, 50, 62), rgb(52, 58, 76), rgb(60, 52, 76), rgb(70, 56, 62), rgb(56, 70, 60), rgb(70, 66, 50)}

local function png(data, seed, diff, path)
    local m = data.meta
    local W, H, S, pad = m.grid[1], m.grid[2], 56, 24
    local mapW, mapH = W * S, H * S
    local legendH = 150
    local cv = newCanvas(math.max(mapW + 2 * pad, 640), mapH + 2 * pad + legendH)
    cv.rect(0, 0, cv.w, cv.h, COL.bg)
    local function cc(cx, cy) return pad + cx * S + S / 2, pad + cy * S + S / 2 end
    local byKey = {}
    for _, c in ipairs(m.cells) do byKey[c.cx .. ',' .. c.cy] = c end
    local inRoom = {}
    for _, c in ipairs(m.cells) do if c.room then inRoom[c.cx .. ',' .. c.cy] = true end end

    for _, c in ipairs(m.cells) do
        local x, y = pad + c.cx * S, pad + c.cy * S
        local tint = REGION_TINT[((c.region or 0) % #REGION_TINT) + 1]
        cv.rect(x + 3, y + 3, S - 6, S - 6, inRoom[c.cx .. ',' .. c.cy] and COL.room or tint)
    end
    -- room blocks: fill the seams between their four cells
    for _, r in ipairs(m.rooms or {}) do
        local x0, y0, x1, y1 = 1e9, 1e9, -1e9, -1e9
        for _, c in ipairs(r.cells) do
            local cx, cy = c.cx or c[1], c.cy or c[2]
            x0, y0, x1, y1 = math.min(x0, cx), math.min(y0, cy), math.max(x1, cx), math.max(y1, cy)
        end
        cv.rect(pad + x0 * S + 3, pad + y0 * S + 3, (x1 - x0 + 1) * S - 6, (y1 - y0 + 1) * S - 6, COL.room)
    end
    -- passages
    local loop = {}
    for _, ek in ipairs(m.loopEdges or {}) do loop[ek] = true end
    for ek, kind in pairs(m.edges) do
        local ax, ay, bx, by = split(ek)
        local x0, y0 = cc(ax, ay)
        local x1, y1 = cc(bx, by)
        if loop[ek] then cv.line(x0, y0, x1, y1, 4, COL.loop, 4)
        else cv.line(x0, y0, x1, y1, kind == 'door' and 2 or 3, kind == 'door' and COL.door or COL.edge) end
    end
    -- critical path
    for i = 1, #m.path - 1 do
        local x0, y0 = cc(m.path[i][1], m.path[i][2])
        local x1, y1 = cc(m.path[i + 1][1], m.path[i + 1][2])
        cv.line(x0, y0, x1, y1, 5, COL.path)
    end
    -- shortcuts / checkpoints from later sections, if present
    for _, sc in ipairs(m.shortcuts or {}) do
        if type(sc) == 'string' then
            local ax, ay, bx, by = split(sc)
            if ax then local x0, y0 = cc(ax, ay); local x1, y1 = cc(bx, by); cv.line(x0, y0, x1, y1, 4, COL.optional, 3) end
        end
    end
    -- gates, start, exit
    for _, c in ipairs(m.cells) do
        local x, y = cc(c.cx, c.cy)
        if c.module then
            local col = c.k and (COL[c.module] or COL.optional) or COL.optional
            cv.rect(x - 11, y - 11, 22, 22, col)
            if c.dir then cv.line(x, y, x + c.dir[1] * 22, y + c.dir[2] * 22, 3, COL.bg) end   -- travel direction (map y down)
            cv.text(c.k and tostring(c.k) or 'O', x - 2, y - 3, 2, COL.bg)
        end
        if c.start then cv.rect(x - 8, y - 8, 16, 16, COL.start) end
        if c.exit then cv.rect(x - 8, y - 8, 16, 16, COL.exit) end
        if c.branch or (not c.onPath and c.deadEnd) then cv.rect(x - 3, y - 3, 6, 6, COL.edge) end
    end
    for _, cp in ipairs(m.checkpoints or {}) do
        local cx, cy = cp.cx or (cp.cell and cp.cell[1]), cp.cy or (cp.cell and cp.cell[2])
        if cx then local x, y = cc(cx, cy); cv.rect(x - 14, y + 8, 6, 6, COL.ckpt) end
    end
    -- plots and pickups (world x -> map x, world y -> map y; cell cy spans y = cy*6 +- 3)
    local function wp(px, py) return pad + px / CELL * S, pad + (py / CELL + 0.5) * S end
    for _, pl in ipairs(data.plots or {}) do
        local x, y = wp(pl.pos[1], pl.pos[2]); cv.rect(x - 3, y - 3, 6, 6, COL.plot)
    end
    for _, pk in ipairs(data.pickups or {}) do
        local x, y = wp(pk.pos[1], pk.pos[2])
        local col = pk.tier == 'critical' and COL.crit or COL.extra
        cv.rect(x - 2, y - 2, 5, 5, col)
    end

    -- legend
    local ly = mapH + 2 * pad
    cv.text(string.format('SEED %d DIFF %d  GRID %dX%d  PATH %d  TURNS %d  LOOPS %d', seed, diff, W, H, m.pathLength, m.turns, m.loops or 0), pad, ly - 14, 2, COL.text)
    local items = {
        {COL.start, 'START'}, {COL.exit, 'EXIT'}, {COL.pit, 'PIT GATE'}, {COL.gap, 'GAP GATE'}, {COL.ledge, 'LEDGE GATE'},
        {COL.optional, 'OPTIONAL GATE (O)'}, {COL.path, 'CRITICAL PATH'}, {COL.edge, 'OPEN EDGE (BRANCH TREE)'},
        {COL.door, 'DOORWAY'}, {COL.loop, 'LOOP (DASHED)'}, {COL.room, 'LARGE ROOM'}, {COL.crit, 'CRITICAL SEED'},
        {COL.extra, 'EXTRA SEED'}, {COL.plot, 'PLOT'},
    }
    local x, y = pad, ly + 8
    for i, it in ipairs(items) do
        cv.rect(x, y, 12, 12, it[1])
        cv.text(it[2], x + 16, y + 1, 2, COL.text)
        x = x + 16 + #it[2] * 8 + 14
        if x > cv.w - 160 then x = pad; y = y + 20 end
    end
    cv.text('GATE NUMBER = CHAIN INDEX. LINE = TRAVEL DIR. SHADE = REGION. Y DOWN', pad, y + 24, 2, COL.text)
    local f = io.open(path, 'wb')
    f:write(cv.img:encode('png'):getString())
    f:close()
end

local txt, n = {}, 0
for _, d in ipairs(diffs) do
    for _, seed in ipairs(seeds) do
        local data = LevelGen.generate(seed, d)
        txt[#txt + 1] = describe(data, seed, d) .. '\n' .. ascii(data) .. '\n'
        png(data, seed, d, string.format('%s/maze_d%d_s%d.png', outDir, d, seed))
        n = n + 1
    end
end
txt[#txt + 1] = 'ASCII legend: S start, E exit, P/G/L pit/gap/ledge gate (lowercase = optional gate), * other critical-path cell, digit = region of an off-path cell; - | open passage, = " doorway, ~ : loop. x right, y down.\n'
local f = assert(io.open(outDir .. '/layouts.txt', 'w'))
f:write(table.concat(txt, '\n'))
f:close()
realPrint(string.format('maze_layout: %d levels written to %s', n, outDir))
os.exit(0)
