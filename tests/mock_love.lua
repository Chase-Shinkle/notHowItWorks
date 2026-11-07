-- Minimal headless stand-ins for the parts of LÖVE and g3d the foundation
-- code touches. Records calls so tests can assert on render-path behaviour.
local M = {calls = {}, printed = {}, pressed = {}, held = {}, mouseX = 0, mouseY = 0}

local function record(name, ...)
    M.calls[#M.calls + 1] = {name = name, args = {...}}
end

local function fileExists(path)
    if type(path) ~= 'string' then return false end
    local f = io.open(path, 'rb')
    if f then f:close() return true end
    return false
end

local function newImageObject(w, h, source)
    return {
        source = source, w = w, h = h,
        setFilter = function() end, setWrap = function() end,
        getDimensions = function(self) return self.w, self.h end,
        getWidth = function(self) return self.w end,
        getHeight = function(self) return self.h end,
    }
end

function M.install()
    M.calls, M.printed, M.pressed, M.held = {}, {}, {}, {}
    M.mouseX, M.mouseY = 0, 0

    local graphics = {
        getDimensions = function() return 800, 800 end,
        getWidth = function() return 800 end,
        getHeight = function() return 800 end,
        getCanvas = function() return nil end,
        newImage = function(src)
            if type(src) == 'string' then
                if not fileExists(src) then error('Could not open file ' .. src) end
                return newImageObject(32, 32, src)
            end
            return newImageObject(src.w, src.h, src)
        end,
        newFont = function(a, b)
            local size = type(a) == 'number' and a or b or 12
            return {
                size = size,
                getHeight = function() return size end,
                getWidth = function(_, text) return #tostring(text) * math.ceil(size / 2) end,
            }
        end,
        setDepthMode = function(...) record('setDepthMode', ...) end,
    }
    setmetatable(graphics, {__index = function(_, name)
        return function(...) record(name, ...) end
    end})

    love = {
        getVersion = function() return 11, 5, 0, 'Mysterious Mysteries' end,
        graphics = graphics,
        filesystem = {
            getInfo = function(path, filter)
                if fileExists(path) then return {type = 'file'} end
                return nil
            end,
        },
        image = {
            newImageData = function(w, h)
                return {w = w, h = h, mapPixel = function(self, fn) self.color = {fn(0, 0, 0, 0, 0, 0)} end}
            end,
        },
        audio = {
            newSource = function(path, kind)
                if not fileExists(path) then error('Could not open file ' .. path) end
                return {path = path, kind = kind}
            end,
        },
        keyboard = {
            isDown = function(...)
                for i = 1, select('#', ...) do
                    if M.held[select(i, ...)] then return true end
                end
                return false
            end,
        },
        mouse = {
            getPosition = function() return M.mouseX, M.mouseY end,
        },
        timer = {getFPS = function() return 60 end},
        window = setmetatable({}, {__index = function() return function() end end}),
    }

    _G.print = function(...)
        local parts = {}
        for i = 1, select('#', ...) do parts[#parts + 1] = tostring(select(i, ...)) end
        M.printed[#M.printed + 1] = table.concat(parts, '\t')
    end

    -- g3d needs a GL context (shader), so substitute a recording stub
    local camera = {
        resize = function(w, h) record('camera.resize', w, h) end,
        lookAt = function(...) record('camera.lookAt', ...) end,
    }
    package.loaded['g3d'] = {
        camera = camera,
        newModel = function(verts, texture, translation)
            record('g3d.newModel', #verts)
            return {
                verts = verts, texture = texture, translation = translation,
                setRotation = function() end,
                draw = function() record('model.draw') end,
            }
        end,
    }

    -- push creates canvases/windows; record apply calls instead
    package.loaded['lib/push'] = {
        setupScreen = function() end,
        resize = function() end,
        apply = function(self, op) record('push.apply', op) end,
        -- 800x800 window, 320x320 game: uniform 2.5x scale, no letterbox
        toGame = function(self, x, y) return x / 2.5, y / 2.5 end,
    }
end

function M.press(key)
    love.keyboard.keysPressed = love.keyboard.keysPressed or {}
    love.keyboard.keysPressed[key] = true
end

-- Hold a key down (love.keyboard.isDown) until M.release(key).
function M.hold(key) M.held[key] = true end
function M.release(key) M.held[key] = nil end

-- Move the mouse to a point given in virtual (320x320) coordinates.
function M.mouseAt(gx, gy) M.mouseX, M.mouseY = gx * 2.5, gy * 2.5 end

function M.click(button)
    love.mouse.buttonsPressed = love.mouse.buttonsPressed or {}
    love.mouse.buttonsPressed[button or 1] = true
end

function M.count(name)
    local n = 0
    for _, c in ipairs(M.calls) do if c.name == name then n = n + 1 end end
    return n
end

function M.reset() M.calls = {} end

return M
