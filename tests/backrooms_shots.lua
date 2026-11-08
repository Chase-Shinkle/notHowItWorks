-- Deterministic backrooms screenshot + frame-time harness on the real LÖVE
-- runtime. Loaded only by `love . --backrooms-shots` (end of main.lua);
-- development only, not packaged. Under Xvfb, from the repo root:
--
--   BR_OUT=/workspace/qa/atmos/run1 xvfb-run -a -s '-screen 0 1024x1024x24' \
--       love . --backrooms-shots --run-seed=2026            (look as configured)
--   ... love . --backrooms-shots --run-seed=2026 --no-shader  (plain renderer)
--
-- Environment:
--   BR_OUT      output dir (default /tmp/backrooms-shots)
--   BR_SUFFIX   appended to every file name (e.g. -plain)
--   BR_LEVELS   comma list of level indices (1 = tutorial; default "1,2")
--   BR_POSES    comma list of pose names (default: all)
--   BR_PRESET   lighting preset forced on every level (bright|dim|single-bulb|near-dark)
--   BR_BAD_SHADER=1  compile garbage instead of shaders/backrooms.glsl (real-runtime failure path)
--   BR_BAD_POST=1    compile garbage instead of shaders/backrooms_post.glsl (post rung falls away, look stays)
--   BR_SCENES   comma list of scene names (see SCENES) added after the POSES; BR_POSES=none
--               skips the fixed poses. Scenes aim the camera at things in the generated level
--               (module obstacle, plot + crop, pickup, exit, prop, nook, zone-transition, zone-<preset>, shape-<name>); BR_LEVELS picks the level
--               (module scenes search levels 2.. for the first one with that obstacle).
--   quality: pass --quality=high|medium|low on the command line (BackroomsLook.setQuality).
--   BR_MODE     "shots", "perf" or "both" (default both)
--   BR_WARMUP   perf warm-up frames per pose (default 90)
--   BR_FRAMES   timed frames per pose (default 300)
--
-- Determinism: the level comes from --run-seed (LevelGen), the camera poses
-- are derived from the room's spawn, the look's clock is the frame counter
-- (BackroomsLook.timeOverride) and the camera is set directly, so the same
-- seed gives the same picture. No physics runs.
--
-- Timing: vsync is turned off (love.window.updateMode) so the loop is not
-- capped to the display rate, and the loop is its own (no sleep). Each pose
-- first renders warm-up frames (shader compile, texture upload, driver
-- warm-up), then times N frames. GPU work is synchronised at the end of the
-- timed batch by a real screenshot read-back (captureScreenshot's callback
-- only fires once the GPU has produced the pixels), so ms/frame is
-- (wall time from first timed frame to read-back) / N, not just CPU
-- submission. Per-frame wall times give p50/p95/max. Under Xvfb the GL
-- renderer is software (llvmpipe): numbers are comparable between runs on
-- the same machine, not absolute GPU numbers.

local OUT = os.getenv('BR_OUT') or '/tmp/backrooms-shots'
local SUFFIX = os.getenv('BR_SUFFIX') or ''
local MODE = os.getenv('BR_MODE') or 'both'
local WARMUP = tonumber(os.getenv('BR_WARMUP')) or 90
local FRAMES = tonumber(os.getenv('BR_FRAMES')) or 300
local PRESET = os.getenv('BR_PRESET')
local function list(env, default)
    local out = {}
    for item in (os.getenv(env) or default):gmatch('[^,]+') do out[#out + 1] = item end
    return out
end
local LEVELS = list('BR_LEVELS', '1,2')
local ONLY_POSES = os.getenv('BR_POSES') and list('BR_POSES', '') or nil
local SCENE_NAMES = os.getenv('BR_SCENES') and list('BR_SCENES', '') or {}
os.execute('mkdir -p "' .. OUT .. '"')
io.stdout:setvbuf('line')
local function log(fmt, ...) print(string.format('[backrooms-shots] ' .. fmt, ...)) end

-- Camera poses relative to the room spawn (feet x, y, z, yaw). Generated
-- levels run along +x from the spawn.
local POSES = {
    {name = 'spawn-hall', dx = 0, yaw = 0, pitch = 0},
    {name = 'mid-hall', dx = 8, yaw = 0, pitch = 0},
    {name = 'look-back', dx = 8, yaw = math.pi, pitch = 0},
    {name = 'ceiling', dx = 8, yaw = 0, pitch = 0.45},
}

-- Scenes: pose.fn(room, state) -> feet x, y, z, yaw, pitch (nil: scene absent in this level).
-- Everything is derived from the room data, so a seed gives the same picture.
local CELL = LEVELGEN_CELL or 6
-- stand ~dist from (x, y, z) on the side of its cell's centre line, looking at it
local function aimAt(x, y, z, dist)
    local cx, cy = math.floor(x / CELL), math.floor((y + CELL / 2) / CELL)
    local mx, my = cx * CELL + CELL / 2, cy * CELL
    local dx, dy = x - mx, y - my
    local d = math.sqrt(dx * dx + dy * dy)
    if d < 0.3 then dx, dy, d = 1, 0, 1 end
    local ux, uy = dx / d, dy / d
    local sx, sy = x - ux * dist, y - uy * dist
    return sx, sy, z, math.atan2(uy, ux), -0.12
end
local function moduleScene(name)
    return function(room)
        for _, c in ipairs(room.data.meta and room.data.meta.cells or {}) do
            if c.module == name then
                -- modules are rotated: stand `back` metres before the cell centre along the
                -- travel direction, looking along it
                local mx, my = c.cx * CELL + CELL / 2, c.cy * CELL
                local back = (name == 'ledge' and 4.5 or 0.4) + CELL / 2
                local dx, dy = c.dir[1], c.dir[2]
                return mx - dx * back, my - dy * back, c.elev, math.atan2(dy, dx), -0.18
            end
        end
    end
end
local function plotScene(room, state)
    local plot = room.plots[1]
    if not plot then return end
    if not plot.crop then
        local seed = room.data.meta and room.data.meta.chain and room.data.meta.chain[1].seed or 'pumpkin'
        local crop = Crop(seed, plot, {progress = 0.6})
        crop.demo = true
        plot.crop = crop
        room.crops[#room.crops + 1] = crop
    end
    local p = plot.pos
    return p[1] - 2.6, p[2], p[3], 0, -0.1
end
-- pit with its pumpkin fully grown (the bridge), seen from the near rim, a little above it
-- and looking down across: the surfaces round a grown pit plot (surfaces QA)
local function pitBridgeScene(room)
    for _, c in ipairs(room.data.meta and room.data.meta.cells or {}) do
        if c.module == 'pit' then
            local plot
            for _, p in ipairs(room.plots) do
                local px, py = p.pos[1], p.pos[2]
                if math.floor(px / CELL) == c.cx and math.floor((py + CELL / 2) / CELL) == c.cy then plot = p end
            end
            if plot and not plot.crop then
                local crop = Crop('pumpkin', plot, {progress = 1})
                crop.grown, crop.active, crop.demo = true, true, true
                plot.crop = crop
                room.crops[#room.crops + 1] = crop
            end
            local mx, my = c.cx * CELL + CELL / 2, c.cy * CELL
            local dx, dy = c.dir[1], c.dir[2]
            return mx - dx * (CELL / 2 + 0.4), my - dy * (CELL / 2 + 0.4), c.elev, math.atan2(dy, dx), -0.3
        end
    end
end
-- stand 1.5 cells before path cell `c` (on the path, towards the start), looking at it
local function pathScene(pred)
    return function(room)
        local meta = room.data.meta
        if not meta then return end
        for i = 2, #meta.path - 1 do
            local a, c, b = meta.path[i - 1], meta.path[i], meta.path[i + 1]
            local cell
            for _, x in ipairs(meta.cells) do if x.cx == c[1] and x.cy == c[2] then cell = x end end
            if cell and cell.kind ~= 'module' and pred(a, c, b, cell) then
                local dx, dy = c[1] - a[1], c[2] - a[2]
                local mx, my = c[1] * CELL + CELL / 2, c[2] * CELL
                return mx - dx * (CELL * 1.2), my - dy * (CELL * 1.2), cell.elev or 0, math.atan2(dy, dx), -0.05
            end
        end
    end
end
-- stand 2 m before a path junction's centre and look half-way between the path
-- and the side opening, so the branch mouth is in frame (not just a corridor)
local function junctionScene(room)
    local meta = room.data.meta
    if not meta then return end
    for i = 2, #meta.path - 1 do
        local a, c, b = meta.path[i - 1], meta.path[i], meta.path[i + 1]
        local cell
        for _, x in ipairs(meta.cells) do if x.cx == c[1] and x.cy == c[2] then cell = x end end
        if cell and cell.kind ~= 'module' and (cell.degree or 0) >= 3 then
            for _, d in ipairs({{1, 0}, {-1, 0}, {0, 1}, {0, -1}}) do
                local n = {c[1] + d[1], c[2] + d[2]}
                local isPath = (n[1] == a[1] and n[2] == a[2]) or (n[1] == b[1] and n[2] == b[2])
                if not isPath and meta.edges[LevelGen.edgeKey({cx = c[1], cy = c[2]}, {cx = n[1], cy = n[2]})] then
                    local fx, fy = c[1] - a[1], c[2] - a[2]          -- incoming travel direction
                    local mx, my = c[1] * CELL + CELL / 2, c[2] * CELL
                    local lx, ly = fx * 1.0 + d[1] * 1.3, fy * 1.0 + d[2] * 1.3
                    return mx - fx * 2.0, my - fy * 2.0, cell.elev or 0, math.atan2(ly, lx), -0.05
                end
            end
        end
    end
end
local SCENES = {
    ['junction'] = junctionScene,
    ['turn'] = pathScene(function(a, c, b) return (c[1] - a[1]) ~= (b[1] - c[1]) or (c[2] - a[2]) ~= (b[2] - c[2]) end),
    ['plot-crop'] = plotScene,
    ['pickup'] = function(room)
        local p = room.pickups[1]
        if p then return aimAt(p.pos[1], p.pos[2], p.pos[3], 2.2) end
    end,
    ['exit'] = function(room)
        -- approach along the real last step of the critical path, looking at the void
        local e = room.exit.pos
        local meta, dx, dy = room.data.meta, 1, 0
        if meta and #meta.path >= 2 then
            local p, q = meta.path[#meta.path - 1], meta.path[#meta.path]
            dx, dy = q[1] - p[1], q[2] - p[2]
        end
        return e[1] - dx * 4.5, e[2] - dy * 4.5, e[3] - 1.1, math.atan2(dy, dx), -0.05
    end,
    ['pit-bridge'] = pitBridgeScene,
    ['pit'] = moduleScene('pit'), ['ledge'] = moduleScene('ledge'), ['gap'] = moduleScene('gap'),
    ['prop'] = function(room)
        for _, b in ipairs(room.data.billboards or {}) do
            if b.dressing then return aimAt(b.pos[1], b.pos[2], b.pos[3], 2.6) end
        end
    end,
    ['nook'] = function(room)
        for _, b in ipairs(room.data.billboards or {}) do
            if not b.dressing and b.texture == 'sacks' then return aimAt(b.pos[1], b.pos[2], b.pos[3], 2.2) end
        end
    end,
}

-- Zone / shape scenes (backrooms-zones-variety-audio 5.1), all from meta.zones / meta.cells[].zone / .shape.
--   zone-transition   stand 2 cells before a connected zone border on the critical path (else any), looking across
--   zone-<preset>     inside the first zone whose lighting is <preset> (bright|dim|single-bulb|near-dark)
--   shape-<name>      at the edge of the first cell of shape <name> (cell.shape string or {name=}), facing its centre;
--                     absent (spawn view) until the shapes group emits cell.shape
-- All are searched across levels like the module scenes (first level of the run that has one).
local function cellShape(c) local s = c.shape; return type(s) == 'table' and s.name or s end
local function cellAt(meta, cx, cy)
    for _, c in ipairs(meta.cells) do if c.cx == cx and c.cy == cy then return c end end
end
local function zoneTransitionScene(room)
    local meta = room.data.meta
    if not (meta and meta.zones) then return end
    local function try(a, b)   -- a -> b adjacent, connected, different zone
        if a.zone ~= b.zone and a.kind ~= 'module' and b.kind ~= 'module'
            and meta.edges[LevelGen.edgeKey(a, b)] then
            local dx, dy = b.cx - a.cx, b.cy - a.cy
            local mx, my = a.cx * CELL + CELL / 2, a.cy * CELL
            return mx - dx * CELL * 0.8, my - dy * CELL * 0.8, a.elev or 0, math.atan2(dy, dx), -0.05
        end
    end
    for i = 1, #meta.path - 1 do   -- critical path first
        local a, b = cellAt(meta, meta.path[i][1], meta.path[i][2]), cellAt(meta, meta.path[i + 1][1], meta.path[i + 1][2])
        local x, y, z, yaw, p = try(a, b)
        if x then return x, y, z, yaw, p end
    end
    for _, a in ipairs(meta.cells) do
        for _, d in ipairs({{1, 0}, {0, 1}, {-1, 0}, {0, -1}}) do
            local b = cellAt(meta, a.cx + d[1], a.cy + d[2])
            if b then
                local x, y, z, yaw, p = try(a, b)
                if x then return x, y, z, yaw, p end
            end
        end
    end
end
local function zoneLightingScene(preset)
    return function(room)
        local meta = room.data.meta
        if not (meta and meta.zones) then return end
        for _, z in ipairs(meta.zones) do
            if z.lighting == preset then
                for _, c in ipairs(meta.cells) do   -- a plain cell of that zone, viewed along a corridor/room
                    if c.zone == z.id and c.kind ~= 'module' and not c.start then
                        local mx, my = c.cx * CELL + CELL / 2, c.cy * CELL
                        return mx - CELL * 0.4, my, c.elev or 0, 0, -0.05
                    end
                end
            end
        end
    end
end
local function shapeScene(name)
    return function(room)
        local meta = room.data.meta
        if not meta then return end
        local first
        for _, c in ipairs(meta.cells) do
            if cellShape(c) == name then first = first or c end
        end
        if not first then return end
        local sx, sy, n = 0, 0, 0   -- centroid of the shape's cells; stand on the far side of the first cell
        for _, c in ipairs(meta.cells) do
            if cellShape(c) == name and (c.shapeId == nil or c.shapeId == first.shapeId) then
                sx, sy, n = sx + c.cx * CELL + CELL / 2, sy + c.cy * CELL, n + 1
            end
        end
        local fx, fy = first.cx * CELL + CELL / 2, first.cy * CELL
        local cx, cy = sx / n, sy / n
        local dx, dy = cx - fx, cy - fy
        if math.abs(dx) + math.abs(dy) < 0.5 then dx, dy = 1, 0 end
        local d = math.sqrt(dx * dx + dy * dy)
        dx, dy = dx / d, dy / d
        return fx - dx * (CELL / 2 - 0.8), fy - dy * (CELL / 2 - 0.8), first.elev or 0, math.atan2(dy, dx), -0.1
    end
end
SCENES['zone-transition'] = zoneTransitionScene
for _, p in ipairs({'bright', 'dim', 'single-bulb', 'near-dark'}) do SCENES['zone-' .. p] = zoneLightingScene(p) end
for _, nme in ipairs(ROOM_SHAPE_NAMES or {}) do SCENES['shape-' .. nme] = shapeScene(nme) end
local MODULE_SCENES = {pit = true, ['pit-bridge'] = true, ledge = true, gap = true, ['zone-transition'] = true}
for name in pairs(SCENES) do if name:match('^zone%-') or name:match('^shape%-') then MODULE_SCENES[name] = true end end

local function save(data, file)
    local f = io.open(file, 'wb')
    if f then f:write(data:encode('png'):getString()); f:close() end
end

local function look() return rawget(_G, 'BackroomsLook') end

-- one-line state of the fallback ladder: look shader / post pass / quality
local function ladder()
    local lk = look()
    if not lk then return 'look absent' end
    return string.format('quality=%s look=%s%s post=%s%s', lk.quality, lk.enabled and 'on' or 'OFF',
        lk.enabled and '' or ' (' .. tostring(lk.reason) .. ')', lk.postEnabled and 'on' or 'OFF',
        lk.postEnabled and '' or ' (' .. tostring(lk.postReason or (lk.enabled and 'not tried' or 'look off')) .. ')')
end
local function loadavg() local f = io.open('/proc/loadavg'); local l = f and f:read('*l') or '?'; if f then f:close() end return l end

local jobs = {}
for _, lv in ipairs(LEVELS) do
    for _, pose in ipairs(POSES) do
        if not ONLY_POSES then jobs[#jobs + 1] = {level = tonumber(lv), pose = pose}
        else
            for _, n in ipairs(ONLY_POSES) do
                if n == pose.name then jobs[#jobs + 1] = {level = tonumber(lv), pose = pose} end
            end
        end
    end
    for _, name in ipairs(SCENE_NAMES) do
        if MODULE_SCENES[name] then
            -- one job per scene: the first level >= 2 (from this one) that has the obstacle / zone feature
            if not jobs[name] then jobs[name] = true; jobs[#jobs + 1] = {level = tonumber(lv), scene = name, search = true,
                pose = {name = name, fn = SCENES[name]}} end
        else
            jobs[#jobs + 1] = {level = tonumber(lv), scene = name, pose = {name = name, fn = SCENES[name]}}
        end
    end
end

local startLoad = loadavg()
local results, failures = {}, 0
local job, jobIndex, phase, frame, clock = nil, 0, 'start', 0, 0
local samples, tStart, lastT, syncDone, syncTime, shotDone = {}, 0, 0, false, 0, false
local state

local function setPose(j)
    local room = state.room
    local s = room.spawn
    if j.pose.fn then
        local x, y, z, yaw, pitch = j.pose.fn(room, state)
        if not x then x, y, z, yaw, pitch = s[1], s[2], s[3], s[4] or 0, 0 end
        state.player:setPosition(x, y, z)
        local ex, ey, ez = state.player:eyePosition()
        g3d.camera.lookInDirection(ex, ey, ez, yaw, pitch)
        return
    end
    state.player:setPosition(s[1] + j.pose.dx, s[2], s[3])
    local ex, ey, ez = state.player:eyePosition()
    g3d.camera.lookInDirection(ex, ey, ez, (s[4] or 0) + j.pose.yaw, j.pose.pitch)
end

local function startJob()
    jobIndex = jobIndex + 1
    job = jobs[jobIndex]
    if not job then return false end
    state:loadRoom(job.level)
    if job.search then
        -- obstacle scenes: walk up the levels until one has the module
        while not job.pose.fn(state.room) and job.level < state:levelCount() do
            job.level = job.level + 1
            state:loadRoom(job.level)
        end
        if not job.pose.fn(state.room) then log('scene %s: no such obstacle in any level of this seed', job.scene) end
    end
    if PRESET then state.room:setLighting(PRESET) end
    if job.scene then
        local x = job.pose.fn(state.room)
        log('scene %s: level %d (%s)%s', job.scene, job.level, tostring(state.room.id),
            x and '' or ' ABSENT in this level (spawn view used)')
    end
    setPose(job)
    phase, frame, samples, syncDone, shotDone = 'warmup', 0, {}, false, false
    return true
end

local function percentile(sorted, p)
    return sorted[math.max(1, math.min(#sorted, math.ceil(p * #sorted)))]
end

local function finishPerf()
    local total = syncTime - tStart
    table.sort(samples)
    local r = {
        level = job.level, pose = job.pose.name, frames = FRAMES, total_ms = total * 1000,
        ms_per_frame = total * 1000 / FRAMES,
        p50_ms = percentile(samples, 0.5) * 1000, p95_ms = percentile(samples, 0.95) * 1000,
        max_ms = samples[#samples] * 1000,
    }
    results[#results + 1] = r
    log('perf level %d %-10s %.3f ms/frame (p50 %.3f p95 %.3f max %.3f, %d frames)', r.level, r.pose,
        r.ms_per_frame, r.p50_ms, r.p95_ms, r.max_ms, FRAMES)
end

function love.run()
    if love.load then love.load(love.arg.parseGameArguments(arg), arg) end
    if love.timer then love.timer.step() end
    love.window.updateMode(800, 800, {vsync = 0})
    if os.getenv('BR_BAD_SHADER') and look() then look().sourceOverride = 'this is not glsl' end
    if os.getenv('BR_BAD_POST') and look() then look().postSourceOverride = 'this is not glsl' end
    local info = {love.graphics.getRendererInfo()}
    local lk = look()
    log('LÖVE %d.%d; renderer: %s; vsync=%s; look=%s; out %s', select(1, love.getVersion()), select(2, love.getVersion()),
        table.concat(info, ' / '), tostring(love.window.getVSync()),
        lk and (lk.enabled and 'on' or ('off (' .. tostring(lk.reason) .. ')')) or 'absent', OUT)
    log('loadavg at start: %s', startLoad)
    gStateMachine:change('backrooms')
    state = gStateMachine.current
    local started = false
    return function()
        love.event.pump()
        for name in love.event.poll() do if name == 'quit' then return 1 end end
        if not started then
            started = true
            if not startJob() then return 0 end
        end
        local lk = look()
        if lk then lk.timeOverride = clock / 60 end
        clock = clock + 1
        setPose(job)
        love.graphics.origin()
        love.graphics.clear(love.graphics.getBackgroundColor())
        local t0 = love.timer.getTime()
        love.draw()
        local wantShot = (MODE ~= 'perf') and phase == 'warmup' and frame == WARMUP - 1
        if wantShot then
            log('shot L%d %s: %s', job.level, job.pose.name, ladder())
            local file = string.format('%s/L%d-%s%s.png', OUT, job.level, job.pose.name, SUFFIX)
            love.graphics.captureScreenshot(function(data) save(data, file); shotDone = true end)
        end
        local wantSync = phase == 'timed' and frame == FRAMES
        if wantSync then
            love.graphics.captureScreenshot(function() syncTime = love.timer.getTime(); syncDone = true end)
        end
        love.graphics.present()
        local t1 = love.timer.getTime()
        frame = frame + 1
        if phase == 'warmup' then
            if frame >= WARMUP and (MODE ~= 'perf' and not shotDone and wantShot) then
                -- wait one more frame for the capture callback
            end
            if frame >= WARMUP and (MODE == 'perf' or shotDone or frame > WARMUP + 2) then
                if MODE == 'shots' then
                    if not startJob() then return 0 end
                else
                    phase, frame, tStart = 'timed', 0, love.timer.getTime()
                end
            end
        elseif phase == 'timed' then
            if frame <= FRAMES then samples[#samples + 1] = t1 - t0 end
            if syncDone then
                finishPerf()
                if not startJob() then
                    local file = OUT .. '/perf' .. SUFFIX .. '.txt'
                    local f = io.open(file, 'w')
                    if f then
                        local sw = table.concat(info, ' '):lower():match('llvmpipe') or table.concat(info, ' '):lower():match('softpipe')
                        f:write(string.format('renderer: %s%s\nvsync: %s\nladder: %s\nwarmup=%d frames=%d\nloadavg at end: %s (at start: %s)\n',
                            table.concat(info, ' / '), sw and '  [SOFTWARE RENDERER: compare runs on this machine only, not GPU numbers]' or '',
                            tostring(love.window.getVSync()), ladder(), WARMUP, FRAMES, loadavg(), startLoad))
                        for _, r in ipairs(results) do
                            f:write(string.format('level %d %-10s %.3f ms/frame p50 %.3f p95 %.3f max %.3f\n',
                                r.level, r.pose, r.ms_per_frame, r.p50_ms, r.p95_ms, r.max_ms))
                        end
                        f:close()
                    end
                    log('done, %d jobs', #jobs)
                    return 0
                end
            end
        end
    end
end

function love.errorhandler(msg)
    print('[backrooms-shots] ERROR: ' .. debug.traceback(tostring(msg), 2))
    os.exit(1)
end
