Class = require 'lib/class'
push = require 'lib/push'
Timer = require 'lib/knife.timer'
g3d = require 'g3d'

require 'src/StateMachine'
require 'src/Util'
require 'src/constants'
require 'src/Entity'
require 'src/Assets'
require 'src/Geometry'
require 'src/GameData'

require 'src/states/game/BaseState'
require 'src/states/game/StartState'
require 'src/states/game/FarmState'
require 'src/states/game/BackroomsState'

-- `love . --placeholder-assets` forces every asset to its fallback, which is
-- equivalent to launching with empty asset folders.
for _, a in ipairs(arg or {}) do
    if a == '--placeholder-assets' then Assets.forcePlaceholders = true end
end

local FARM_PACK = 'graphics/Farming - Crops Pack 017/'

-- Global asset tables. Every entry is {path, fallback}; a missing or broken
-- file falls back to a flat-color image / silent sound / built-in font.
gFonts = {}
gTextures = {}
gFrames = {}
gSounds = {}
gModels = {}

-- Fonts: {path or nil, size}
Assets.loadAll(gFonts, {
    ['default'] = {nil, 16},
    ['small'] = {nil, 8},
}, function(path, size) return Assets.loadFont(path, size) end)

-- Textures: {path, flat fallback color}
Assets.loadAll(gTextures, {
    ['grass'] = {FARM_PACK .. 'Ground/Tiles - Grass - 01.png', {0.35, 0.65, 0.3, 1}},
    ['soil'] = {FARM_PACK .. 'Ground/Tiles - Soil - 01.png', {0.45, 0.3, 0.2, 1}},
    ['hero'] = {FARM_PACK .. 'Sprites/Hero  white - 001 copy.png', {0.9, 0.9, 0.9, 1}},
    ['wall'] = {'graphics/backrooms/wall.png', {1, 1, 1, 1}},
    ['floor'] = {'graphics/backrooms/floor.png', {1, 1, 1, 1}},
}, function(path, color) return Assets.loadImage(path, color) end)

-- 3D models: g3d only reads .obj; build procedural boxes in code for now.
-- Example: gModels['crate'] = g3d.newModel('models/crate.obj', gTextures['crate'], {0,0,0})

-- Sounds: {path, source type}
Assets.loadAll(gSounds, {
    ['farm-music'] = {'sounds/farm_music.ogg', 'stream'},
    ['backrooms-hum'] = {'sounds/backrooms_hum.ogg', 'stream'},
    ['plant'] = {'sounds/plant.wav', 'static'},
    ['glitch'] = {'sounds/glitch.wav', 'static'},
}, function(path, sourceType) return Assets.loadSound(path, sourceType) end)
