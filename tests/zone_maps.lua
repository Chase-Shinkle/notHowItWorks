-- Top-down zone map renderer for visual review (backrooms-zones-variety-audio 5.1).
-- Loaded by `love . --zone-maps`; development only. Generates the real levels of
-- a run seed and draws each as a PNG: cells coloured by zone, walls/doors from
-- meta.edges, room/shape boundaries, path, start/exit, props, legend.
--   ZM_OUT=/workspace/qa/zones ZM_LEVELS=2,3 xvfb-run -a love . --zone-maps --run-seed=2026
-- Shape metadata is read tolerantly: a cell's `shape` (string or {name=..., id=...}),
-- `shapeId`, else `room` (multi-cell room id). Cells sharing a group id are outlined
-- as one shape; the shape name is drawn at its centroid.
local OUT = os.getenv('ZM_OUT') or '/workspace/qa/zones'
os.execute('mkdir -p "' .. OUT .. '"')
local LEVELS = {}
for n in (os.getenv('ZM_LEVELS') or '2,3'):gmatch('[^,]+') do LEVELS[#LEVELS + 1] = tonumber(n) end
local PALETTE = {{0.9, 0.35, 0.3}, {0.3, 0.6, 0.9}, {0.4, 0.8, 0.4}, {0.9, 0.75, 0.25},
    {0.7, 0.4, 0.85}, {0.3, 0.8, 0.8}, {0.9, 0.55, 0.7}, {0.6, 0.6, 0.6}}
local PX = 40   -- pixels per cell

local function shapeOf(c)
    local s = c.shape
    if type(s) == 'table' then return s.id or s.name, s.name end
    if s then return c.shapeId or s, s end
    if c.room then return 'r' .. tostring(c.room), 'room' end
    return nil
end

local function render(meta, data, name)
    local minx, maxx, miny, maxy = 1e9, -1e9, 1e9, -1e9
    for _, c in ipairs(meta.cells) do
        minx, maxx = math.min(minx, c.cx), math.max(maxx, c.cx)
        miny, maxy = math.min(miny, c.cy), math.max(maxy, c.cy)
    end
    local W, H = math.max(440, (maxx - minx + 1) * PX + 20), (maxy - miny + 1) * PX + 20 + 18 * (#meta.zones + 3)
    local cv = love.graphics.newCanvas(W, H)
    love.graphics.setCanvas(cv)
    love.graphics.clear(0.08, 0.08, 0.08, 1)
    local zoneIdx = {}
    for i, z in ipairs(meta.zones) do zoneIdx[z.id] = i end
    local function px(c) return 10 + (c.cx - minx) * PX, 10 + (c.cy - miny) * PX end
    local byKey, groups = {}, {}
    for _, c in ipairs(meta.cells) do
        byKey[c.cx .. ',' .. c.cy] = c
        local col = PALETTE[((zoneIdx[c.zone] or 1) - 1) % #PALETTE + 1]
        local x, y = px(c)
        love.graphics.setColor(col[1], col[2], col[3], c.module and 0.45 or 0.85)
        love.graphics.rectangle('fill', x, y, PX, PX)
        local gid, gname = shapeOf(c)
        if gid then
            local g = groups[gid] or {name = gname, sx = 0, sy = 0, n = 0}
            groups[gid] = g; g.sx, g.sy, g.n = g.sx + x + PX / 2, g.sy + y + PX / 2, g.n + 1
        end
        if c.start then love.graphics.setColor(1, 1, 1); love.graphics.print('S', x + 4, y + 2) end
        if c.exit then love.graphics.setColor(0, 0, 0); love.graphics.print('E', x + 4, y + 2) end
        if c.module then love.graphics.setColor(0, 0, 0); love.graphics.print(c.module:sub(1, 3), x + 4, y + 22) end
    end
    -- walls where there is no edge; thick shape outline where group ids differ; zone border in white
    local function edge(a, b) return meta.edges[LevelGen.edgeKey(a, b)] end
    for _, c in ipairs(meta.cells) do
        local x, y = px(c)
        local gid = shapeOf(c)
        for _, d in ipairs({{1, 0}, {0, 1}, {-1, 0}, {0, -1}}) do
            local nb = byKey[(c.cx + d[1]) .. ',' .. (c.cy + d[2])]
            local x1 = x + (d[1] == 1 and PX or 0)
            local y1 = y + (d[2] == 1 and PX or 0)
            local x2 = d[1] ~= 0 and x1 or x1 + PX
            local y2 = d[2] ~= 0 and y1 or y1 + PX
            if not nb or not edge(c, nb) then
                love.graphics.setColor(0, 0, 0); love.graphics.setLineWidth(3)
                love.graphics.line(x1, y1, x2, y2)
            else
                local ngid = shapeOf(nb)
                if nb.zone ~= c.zone then
                    love.graphics.setColor(1, 1, 1); love.graphics.setLineWidth(3); love.graphics.line(x1, y1, x2, y2)
                elseif gid ~= ngid then
                    love.graphics.setColor(1, 0.9, 0); love.graphics.setLineWidth(2); love.graphics.line(x1, y1, x2, y2)
                end
                if edge(c, nb) == 'door' then
                    love.graphics.setColor(0.2, 0.2, 0.2); love.graphics.setLineWidth(1)
                    love.graphics.circle('line', (x1 + x2) / 2, (y1 + y2) / 2, 4)
                end
            end
        end
    end
    -- path
    love.graphics.setColor(1, 1, 1, 0.8); love.graphics.setLineWidth(2)
    for i = 2, #meta.path do
        local a, b = meta.path[i - 1], meta.path[i]
        love.graphics.line(10 + (a[1] - minx + 0.5) * PX, 10 + (a[2] - miny + 0.5) * PX,
            10 + (b[1] - minx + 0.5) * PX, 10 + (b[2] - miny + 0.5) * PX)
    end
    -- props (dots in the zone-contrast colour)
    local CELL = LEVELGEN_CELL
    love.graphics.setColor(0, 0, 0)
    for _, b in ipairs(data.billboards or {}) do
        if b.dressing then
            love.graphics.circle('fill', 10 + (b.pos[1] / CELL - minx) * PX, 10 + ((b.pos[2] + CELL / 2) / CELL - miny) * PX, 2)
        end
    end
    for gid, g in pairs(groups) do
        love.graphics.setColor(0, 0, 0); love.graphics.print(tostring(g.name):sub(1, 6), g.sx / g.n - 12, g.sy / g.n - 6)
    end
    -- legend
    local ly = 10 + (maxy - miny + 1) * PX + 6
    for i, z in ipairs(meta.zones) do
        local col = PALETTE[(i - 1) % #PALETTE + 1]
        love.graphics.setColor(col); love.graphics.rectangle('fill', 10, ly, 14, 14)
        love.graphics.setColor(1, 1, 1)
        love.graphics.print(string.format('%s  %s / %s  %d cells  adj %s', z.id, z.theme, z.lighting, z.cellCount,
            table.concat(z.adjacent, ',')), 30, ly)
        ly = ly + 18
    end
    love.graphics.setColor(1, 1, 1)
    love.graphics.print('white=zone border  yellow=shape border  black=wall  circle=door  line=path  dot=prop', 10, ly)
    love.graphics.setCanvas()
    local img = cv:newImageData()
    local f = io.open(OUT .. '/' .. name .. '.png', 'wb')
    f:write(img:encode('png'):getString()); f:close()
    print('[zone-maps] wrote ' .. name .. ' zones=' .. #meta.zones .. ' cells=' .. #meta.cells)
end

function love.run()
    if love.load then love.load(love.arg.parseGameArguments(arg), arg) end
    return function()
        love.event.pump()
        for _ in love.event.poll() do end
        local runSeed = BACKROOMS_RUN_SEED or 2026
        for _, lv in ipairs(LEVELS) do
            local ok, err = pcall(function()
                local seed = LevelGen.levelSeed(runSeed, lv)
                local d = LevelGen.generate(seed, lv - 1, {name = 'Level ' .. lv})
                render(d.meta, d, string.format('seed%d-L%d', runSeed, lv))
            end)
            if not ok then print('[zone-maps] ERROR ' .. tostring(err)) end
        end
        return 0
    end
end
