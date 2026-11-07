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

-- Filters follow LÖVE: new images and fonts take the current default filter
-- (linear until setDefaultFilter is called); setFilter changes one object.
local function filterMethods(obj)
    obj.filter = {M.defaultFilter[1], M.defaultFilter[2]}
    obj.setFilter = function(self, min, mag) self.filter = {min, mag or min} end
    obj.getFilter = function(self) return self.filter[1], self.filter[2] end
    obj.setMipmapFilter = function(self, mode) self.mipmapFilter = mode end
    obj.getMipmapFilter = function(self) return self.mipmapFilter end
    return obj
end

local function newImageObject(w, h, source, settings)
    return filterMethods({
        source = source, w = w, h = h, mipmaps = settings and settings.mipmaps or false,
        setWrap = function() end,
        getDimensions = function(self) return self.w, self.h end,
        getWidth = function(self) return self.w end,
        getHeight = function(self) return self.h end,
    })
end

function M.install()
    M.calls, M.printed, M.pressed, M.held = {}, {}, {}, {}
    M.soundPlays = {}
    M.mouseX, M.mouseY = 0, 0
    M.relativeMode = false
    M.defaultFilter = {'linear', 'linear'}

    local graphics = {
        getDimensions = function() return 800, 800 end,
        getWidth = function() return 800 end,
        getHeight = function() return 800 end,
        getCanvas = function() return nil end,
        newImage = function(src, settings)
            if type(src) == 'string' then
                if not fileExists(src) then error('Could not open file ' .. src) end
                return newImageObject(32, 32, src, settings)
            end
            return newImageObject(src.w, src.h, src, settings)
        end,
        newFont = function(a, b)
            local size = type(a) == 'number' and a or b or 12
            return filterMethods({
                size = size,
                getHeight = function() return size end,
                getWidth = function(_, text) return #tostring(text) * math.ceil(size / 2) end,
            })
        end,
        setDefaultFilter = function(min, mag)
            M.defaultFilter = {min, mag or min}
            record('setDefaultFilter', min, mag)
        end,
        getDefaultFilter = function() return M.defaultFilter[1], M.defaultFilter[2] end,
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
                -- a Source-like object that records plays
                local src = {path = path, kind = kind, plays = 0, volume = 1, looping = false}
                function src:play() self.plays = self.plays + 1; M.soundPlays[#M.soundPlays + 1] = self.path; return true end
                function src:stop() end
                function src:setVolume(v) self.volume = v end
                function src:getVolume() return self.volume end
                function src:setLooping(on) self.looping = on end
                function src:isLooping() return self.looping end
                function src:isPlaying() return false end
                function src:clone() return love.audio.newSource(self.path, self.kind) end
                return src
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
            setRelativeMode = function(on) M.relativeMode = on; record('setRelativeMode', on) end,
            getRelativeMode = function() return M.relativeMode or false end,
        },
        timer = {getFPS = function() return 60 end},
        window = setmetatable({}, {__index = function() return function() end end}),
    }

    _G.print = function(...)
        local parts = {}
        for i = 1, select('#', ...) do parts[#parts + 1] = tostring(select(i, ...)) end
        M.printed[#M.printed + 1] = table.concat(parts, '\t')
    end

    -- g3d's init.lua and model.lua need a GL context (shader, meshes), so the
    -- g3d table and newModel are recording stubs. The pure-Lua parts (camera,
    -- matrices, vectors, collisions) are the real g3d files, freshly loaded for
    -- every test so camera state does not leak between tests.
    for k in pairs(package.loaded) do
        if k:match('^g3d%.') then package.loaded[k] = nil end
    end
    local g3d = {path = 'g3d'}
    package.loaded['g3d'] = g3d
    g3d.vectors = require('g3d.vectors')
    g3d.collisions = require('g3d.collisions')
    g3d.camera = require('g3d.camera')
    local realResize = g3d.camera.resize
    g3d.camera.resize = function(w, h) record('camera.resize', w, h); return realResize(w, h) end
    local realLookAt = g3d.camera.lookAt
    g3d.camera.lookAt = function(...) record('camera.lookAt', ...); return realLookAt(...) end
    g3d.newModel = function(verts, texture, translation, rotation, scale)
        record('g3d.newModel', #verts)
        if type(scale) == 'number' then scale = {scale, scale, scale} end
        local m = {
            verts = verts, texture = texture,
            translation = translation or {0, 0, 0},
            rotation = rotation or {0, 0, 0},
            scale = scale or {1, 1, 1},
        }
        function m:setRotation(x, y, z) self.rotation = {x, y, z} end
        function m:setTranslation(x, y, z) self.translation = {x, y, z} end
        function m:setScale(x, y, z) self.scale = {x, y or x, z or x} end
        function m:draw(shader) record('model.draw', self, shader) end
        return m
    end

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

-- Calls named `name`, in order.
function M.callsNamed(name)
    local out = {}
    for _, c in ipairs(M.calls) do if c.name == name then out[#out + 1] = c end end
    return out
end

return M
