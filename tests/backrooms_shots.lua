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

local function save(data, file)
    local f = io.open(file, 'wb')
    if f then f:write(data:encode('png'):getString()); f:close() end
end

local function look() return rawget(_G, 'BackroomsLook') end

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
end

local results, failures = {}, 0
local job, jobIndex, phase, frame, clock = nil, 0, 'start', 0, 0
local samples, tStart, lastT, syncDone, syncTime, shotDone = {}, 0, 0, false, 0, false
local state

local function setPose(j)
    local room = state.room
    local s = room.spawn
    state.player:setPosition(s[1] + j.pose.dx, s[2], s[3])
    local ex, ey, ez = state.player:eyePosition()
    g3d.camera.lookInDirection(ex, ey, ez, (s[4] or 0) + j.pose.yaw, j.pose.pitch)
end

local function startJob()
    jobIndex = jobIndex + 1
    job = jobs[jobIndex]
    if not job then return false end
    state:loadRoom(job.level)
    if PRESET then state.room:setLighting(PRESET) end
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
    local info = {love.graphics.getRendererInfo()}
    local lk = look()
    log('LÖVE %d.%d; renderer: %s; vsync=%s; look=%s; out %s', select(1, love.getVersion()), select(2, love.getVersion()),
        table.concat(info, ' / '), tostring(love.window.getVSync()),
        lk and (lk.enabled and 'on' or ('off (' .. tostring(lk.reason) .. ')')) or 'absent', OUT)
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
                        f:write(string.format('renderer: %s\nvsync: %s\nlook: %s\nwarmup=%d frames=%d\n',
                            table.concat(info, ' / '), tostring(love.window.getVSync()),
                            lk and (lk.enabled and 'on' or 'off') or 'absent', WARMUP, FRAMES))
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
