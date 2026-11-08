Class = require 'lib/class'
push = require 'lib/push'
Timer = require 'lib/knife.timer'
g3d = require 'g3d'

require 'src/StateMachine'
require 'src/Util'
require 'src/constants'
require 'src/Entity'
require 'src/Assets'
require 'src/UI'
require 'src/Hotbar'
require 'src/Geometry'
require 'src/GameData'
require 'src/Farm'
require 'src/Fx'
require 'src/FarmShader'
require 'src/BackroomsLook'
require 'src/BackroomsAudio'
require 'src/PlayerController'
require 'src/Billboard'
require 'src/Crop'
require 'src/PitShaft'
require 'src/Room'
require 'src/rooms'
require 'src/Dressing'
require 'src/LevelGen'

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
--   `love . --run-seed=N` fixes the run seed of the generated backrooms levels.
--   `love . --no-shader` draws the farm without its post-process pass and the
--   backrooms without lighting/fog (the same paths as a shader that fails to
--   compile). `love . --quality=low` drops backrooms light flicker.
for _, a in ipairs(arg or {}) do
    if a == '--placeholder-assets' then Assets.forcePlaceholders = true end
    if a == '--debug' then DEBUG_MODE = true end
    local runSeed = a:match('^%-%-run%-seed=(%d+)$')
    if runSeed then BACKROOMS_RUN_SEED = tonumber(runSeed) end
    if a == '--no-shader' then FarmShader.forceOff = true; BackroomsLook.forceOff = true end
    local quality = a:match('^%-%-quality=(%a+)$')
    if quality then BackroomsLook.setQuality(quality) end
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
    -- display font (title, buttons, ending headline); falls back to built-in
    ['title-32'] = {UI_FONT_FILE, 32},
    ['title-48'] = {UI_FONT_FILE, 48},
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
    -- the farm villager: its own sprite (brown hair, straw hat, apron), made
    -- from the hero by tools/make_villager.py; no draw-time tint
    ['villager'] = {'graphics/characters/villager.png', {0.7, 0.5, 0.85, 1}, 13},
    -- farm dressing (src/constants.lua FARM_DECOR)
    ['barn'] = {FARM_PACK .. 'Buldings & Stractures/Props - Stractures - Barn 01.png', {0.7, 0.35, 0.3, 1}, 96},
    ['fence'] = {FARM_PACK .. 'Fences/Wooden Fence - 01/Tiles - Wooden Fence - 01 -01.png', {0.6, 0.4, 0.25, 1}, 6},
    ['bush-1'] = {FARM_PACK .. 'CROPS/Crops - RAPSBERRY/Crops RASPBERRY 07.png', {0.25, 0.5, 0.25, 1}, 14},
    ['bush-2'] = {FARM_PACK .. 'CROPS/Crops - BLACKBERRY/Crops  BLACKBERRY07.png', {0.2, 0.45, 0.3, 1}, 14},
    ['path'] = {FARM_PACK .. 'Ground/Tile - Stone Soil - 01.png', {0.7, 0.6, 0.45, 1}},
    ['grass-plant'] = {FARM_PACK .. 'Ground/Tile -Plant - 01.png', {0.3, 0.6, 0.3, 1}},
    -- tools shown beside the farmer (the seed bag is the crop's own bag)
    ['tool-shovel'] = {FARM_PACK .. 'Tools/Tools  - Icons - WO (With Outline)/Icon -  Shovel WO 01.png', {0.6, 0.6, 0.65, 1}, 8},
    ['tool-can'] = {FARM_PACK .. 'Tools/Tools  - Icons - WO (With Outline)/Icons - Water Can WO.png', {0.4, 0.6, 0.9, 1}, 8},
    ['tool-sickle'] = {FARM_PACK .. 'Tools/Tools  - Icons - WO (With Outline)/Icons -Sickle WO 01.png', {0.75, 0.75, 0.8, 1}, 8},
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
CROP_SPRITE_PATHS = {}   -- mature sprite per seed type; Crop.lua samples its pixels for the 3D material
for seedType, art in pairs(CROP_ART) do
    CROP_SPRITE_PATHS[seedType] = string.format(art[1], 7)
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

-- Procedural backrooms material textures (MATERIAL_THEMES in src/Room.lua).
-- Generated in code, no files; with --placeholder-assets they become flat
-- placeholders so themes fall back to their flat colours.
local function hash(x, y)
    local n = (x * 374761393 + y * 668265263) % 4294967296
    n = (n * 1274126177) % 4294967296
    return (n % 1000) / 1000
end
local function proceduralTexture(size, shade)
    if Assets.forcePlaceholders then
        local img = Assets.newPlaceholderImage({1, 1, 1, 1}, 4)
        Assets.placeholders[img] = true
        return img
    end
    local data = love.image.newImageData(size, size)
    data:mapPixel(function(x, y)
        local r, g, b = shade(x, y, size)
        return r, g, b, 1
    end)
    local img = love.graphics.newImage(data)
    img:setFilter('linear', 'linear')
    return img
end
PROCEDURAL_SURFACE_TEXTURES = {'wall-chevron', 'wall-stripe', 'floor-carpet', 'floor-damp', 'ceiling-grid'}
local function mix(c, k) return c[1] * k, c[2] * k, c[3] * k end
-- sickly yellow wallpaper with chevron pairs
gTextures['wall-chevron'] = proceduralTexture(64, function(x, y, s)
    local band = (x + math.abs((y % 32) - 16)) % 16
    local k = (band < 3 and 0.78 or 1) * (0.94 + 0.06 * hash(x, y))
    return mix({0.84, 0.78, 0.38}, k)
end)
-- yellow wallpaper with vertical stripes
gTextures['wall-stripe'] = proceduralTexture(64, function(x, y, s)
    local k = ((x % 16) < 4 and 0.8 or 1) * (0.94 + 0.06 * hash(x, y))
    return mix({0.88, 0.82, 0.5}, k)
end)
-- damp mustard carpet
gTextures['floor-carpet'] = proceduralTexture(64, function(x, y, s)
    local damp = hash(math.floor(x / 8), math.floor(y / 8)) < 0.2 and 0.82 or 1
    return mix({0.66, 0.56, 0.24}, damp * (0.82 + 0.18 * hash(x, y)))
end)
-- darker stained carpet
gTextures['floor-damp'] = proceduralTexture(64, function(x, y, s)
    local damp = hash(math.floor(x / 16), math.floor(y / 16)) < 0.4 and 0.7 or 0.9
    return mix({0.5, 0.44, 0.22}, damp * (0.85 + 0.15 * hash(x, y)))
end)
-- acoustic ceiling tiles with grid lines
gTextures['ceiling-grid'] = proceduralTexture(64, function(x, y, s)
    local line = (x % 32 < 2) or (y % 32 < 2)
    return mix(line and {0.55, 0.52, 0.42} or {0.9, 0.88, 0.76}, 0.9 + 0.1 * hash(x, y))
end)

-- Plain white texture for vertex-coloured 3D crops (src/Crop.lua).
gTextures['white'] = Assets.newPlaceholderImage({1, 1, 1, 1}, 4)

-- 3D models: g3d only reads .obj; build procedural boxes in code for now.
-- Example: gModels['crate'] = g3d.newModel('models/crate.obj', gTextures['crate'], {0,0,0})

-- Sounds: {path, source type}
Assets.loadAll(gSounds, {
    ['farm-music'] = {'sounds/farm_music.ogg', 'stream'},
    ['backrooms-hum'] = {BACKROOMS_HUM_FILE, 'stream'},   -- 43 MB mp3: streamed, never static
    ['footstep-1'] = {BACKROOMS_FOOTSTEP_FILES[1], 'static'},
    ['footstep-2'] = {BACKROOMS_FOOTSTEP_FILES[2], 'static'},
    ['footstep-3'] = {BACKROOMS_FOOTSTEP_FILES[3], 'static'},
    ['footstep-4'] = {BACKROOMS_FOOTSTEP_FILES[4], 'static'},
    ['footstep-5'] = {BACKROOMS_FOOTSTEP_FILES[5], 'static'},
    ['till'] = {'sounds/till.wav', 'static'},
    ['plant'] = {'sounds/plant.wav', 'static'},
    ['water'] = {'sounds/water.wav', 'static'},
    ['harvest'] = {'sounds/harvest.wav', 'static'},
    ['sell'] = {'sounds/sell.wav', 'static'},
    ['buy'] = {'sounds/buy.wav', 'static'},
    ['coin'] = {'sounds/coin.wav', 'static'},
    ['deny'] = {'sounds/deny.wav', 'static'},
    ['glitch'] = {'sounds/glitch.wav', 'static'},
}, function(path, sourceType) return Assets.loadSound(path, sourceType) end)

-- The short effects in sounds/ are generated by tools/gen_sounds.py (soft by
-- design); play them a little under full volume. Replace any of them by
-- dropping a real file at the same path.
for _, key in ipairs({'till', 'plant', 'water', 'harvest', 'sell', 'buy', 'coin', 'deny', 'glitch'}) do
    gSounds[key]:setVolume(FARM_SFX_VOLUME)
end
