Class = require 'lib/class'
push = require 'lib/push'
Timer = require 'lib/knife.timer'
g3d = require 'g3d'

require 'src/StateMachine'
require 'src/Util'
require 'src/constants'
require 'src/Entity'

require 'src/states/game/BaseState'
require 'src/states/game/StartState'

-- Global asset tables
gFonts = {}
gTextures = {}
gFrames = {}
gSounds = {}

-- Load your fonts here
gFonts['default'] = love.graphics.newFont(16)

-- Load your textures here
-- Example: gTextures['player'] = love.graphics.newImage('graphics/player.png')

-- Load your 3D models here
-- Example: gModels['crate'] = g3d.newModel('models/crate.obj', gTextures['crate'], {0,0,0})
gModels = {}

-- Load your sounds here
-- Example: gSounds['jump'] = love.audio.newSource('sounds/jump.wav', 'static')
