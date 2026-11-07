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
require 'src/Farm'
require 'src/PlayerController'
require 'src/Billboard'
require 'src/Crop'
require 'src/Room'
require 'src/rooms'

require 'src/states/game/BaseState'
require 'src/states/game/StartState'
require 'src/states/game/FarmState'
require 'src/states/game/BackroomsState'
require 'src/states/game/EndingState'

-- Launch flags:
--   `love . --placeholder-assets` forces every asset to its fallback, which is
--   equivalent to launching with empty asset folders.
--   `love . --debug` turns on DEBUG_MODE (F1 skip, debug HUD text); it is off
--   otherwise, including in the packaged release.
for _, a in ipairs(arg or {}) do
    if a == '--placeholder-assets' then Assets.forcePlaceholders = true end
    if a == '--debug' then DEBUG_MODE = true end
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

-- Textures: {path, flat fallback color}. Everything loads with the nearest
-- default filter set at the top of main.lua (crisp pixel art).
local TEXTURE_MANIFEST = {
    ['grass'] = {FARM_PACK .. 'Ground/Tiles - Grass - 01.png', {0.35, 0.65, 0.3, 1}},
    ['soil'] = {FARM_PACK .. 'Ground/Tiles - Soil - 01.png', {0.45, 0.3, 0.2, 1}},
    ['hero'] = {FARM_PACK .. 'Sprites/Hero  white - 001 copy.png', {0.9, 0.9, 0.9, 1}},
    -- backrooms surfaces: extracted unchanged from the user-supplied
    -- models/Backrooms.glb by tools/extract_glb_textures.py
    ['wall'] = {'graphics/backrooms/wall.jpg', {1, 1, 1, 1}},
    ['floor'] = {'graphics/backrooms/floor.png', {1, 1, 1, 1}},
    ['ceiling'] = {'graphics/backrooms/ceiling.jpg', {1, 1, 1, 1}},
    -- old farm props, used as backrooms billboards
    ['well'] = {FARM_PACK .. 'Buldings & Stractures/WELLS/Prop -Well 01 -01.png', {0.55, 0.5, 0.45, 1}, 14},
    ['bucket'] = {FARM_PACK .. 'Tools/Tools - ITEMS/Items - Bucket.png', {0.6, 0.45, 0.3, 1}, 10},
    ['sacks'] = {FARM_PACK .. 'Tools/Tools - ITEMS/Props - Icons - Sacks.png', {0.75, 0.65, 0.45, 1}, 10},
    ['plot'] = {FARM_PACK .. 'Ground/Props - Soil Preparation.png', {0.36, 0.22, 0.13, 1}},
    ['villager'] = {FARM_PACK .. 'Sprites/Hero  white - 001 copy 2.png', {0.7, 0.5, 0.85, 1}, 13},
}
Assets.loadAll(gTextures, TEXTURE_MANIFEST, function(path, color, size) return Assets.loadImage(path, color, size) end)

-- The large tiling backrooms surfaces are photographic, not pixel art: they
-- stay smooth (linear + mipmaps) so they do not shimmer at a distance.
-- Placeholders for them keep the nearest default.
SMOOTH_SURFACE_TEXTURES = {'wall', 'floor', 'ceiling'}
for _, key in ipairs(SMOOTH_SURFACE_TEXTURES) do
    gTextures[key] = Assets.smoothImage(gTextures[key], TEXTURE_MANIFEST[key][1])
end

-- Crop art per seed type. The pack has no beanstalk/vine crops yet, so green
-- pepper and zucchini stand in; swap the folder/pattern when real art lands.
-- Pack numbering: 01 seed bag, 03 seeds, 04-06 growing, 07 mature, 08 produce.
-- Keys: 'seedbag-<type>', 'crop-<type>-<stage 1..FARM_GROWTH_STAGES>',
-- 'produce-<type>'. Placeholders grow in size and colour with the stage.
local CROP_ART = {
    beanstalk = {FARM_PACK .. 'CROPS/Crops - GREEN BELL PEPPER/Crops PEPPER GREEN %02d.png', {0.4, 0.75, 0.3, 1}},
    pumpkin = {FARM_PACK .. 'CROPS/Crops - PUMPKIN/Crops - PUMPKIN - %02d.png', {0.95, 0.55, 0.15, 1}},
    vine = {FARM_PACK .. 'CROPS/Crops - ZUCCHINI/Crops - ZUCCHINI %02d.png', {0.2, 0.55, 0.25, 1}},
}
local STAGE_FRAMES = {3, 4, 5, 6, 7}
local STAGE_SIZES = {4, 6, 9, 12, 14}
local cropManifest = {}
for seedType, art in pairs(CROP_ART) do
    local pattern, color = art[1], art[2]
    cropManifest['seedbag-' .. seedType] = {string.format(pattern, 1), color, 10}
    cropManifest['produce-' .. seedType] = {string.format(pattern, 8), color, 10}
    for stage = 1, FARM_GROWTH_STAGES do
        local g = 0.35 + 0.1 * stage
        local stageColor = stage == FARM_GROWTH_STAGES and color or {0.25, g, 0.2, 1}
        cropManifest['crop-' .. seedType .. '-' .. stage] =
            {string.format(pattern, STAGE_FRAMES[stage]), stageColor, STAGE_SIZES[stage]}
    end
end
Assets.loadAll(gTextures, cropManifest, function(path, color, size) return Assets.loadImage(path, color, size) end)

-- Plain white texture for vertex-coloured 3D crops (src/Crop.lua).
gTextures['white'] = Assets.newPlaceholderImage({1, 1, 1, 1}, 4)

-- 3D models: g3d only reads .obj; build procedural boxes in code for now.
-- Example: gModels['crate'] = g3d.newModel('models/crate.obj', gTextures['crate'], {0,0,0})

-- Sounds: {path, source type}
Assets.loadAll(gSounds, {
    ['farm-music'] = {'sounds/farm_music.ogg', 'stream'},
    ['backrooms-hum'] = {'sounds/backrooms_hum.ogg', 'stream'},
    ['plant'] = {'sounds/plant.wav', 'static'},
    ['harvest'] = {'sounds/harvest.wav', 'static'},
    ['sell'] = {'sounds/sell.wav', 'static'},
    ['deny'] = {'sounds/deny.wav', 'static'},
    ['glitch'] = {'sounds/glitch.wav', 'static'},
}, function(path, sourceType) return Assets.loadSound(path, sourceType) end)
