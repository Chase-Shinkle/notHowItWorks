-- Generic quad generation for spritesheets
function GenerateQuads(atlas, tilewidth, tileheight)
    local sheetWidth = atlas:getWidth() / tilewidth
    local sheetHeight = atlas:getHeight() / tileheight

    local sheetCounter = 1
    local spritesheet = {}

    for y = 0, sheetHeight - 1 do
        for x = 0, sheetWidth - 1 do
            spritesheet[sheetCounter] = love.graphics.newQuad(x*tilewidth, y*tileheight, tilewidth, tileheight, atlas:getDimensions())
            sheetCounter = sheetCounter + 1
        end
    end
    return spritesheet
end

-- Utility to slice a table
function table.slice(table, first, last, step)
    local sliced = {}

    for i = first or 1, last or #table, step or 1 do
        sliced[#sliced+1] = table[i]
    end

    return sliced
end

-- The name the player reads for a seed type (SEED_DISPLAY_NAMES in
-- src/constants.lua); unknown types fall back to their key.
function SeedName(seedType)
    return (SEED_DISPLAY_NAMES and SEED_DISPLAY_NAMES[seedType]) or tostring(seedType)
end
