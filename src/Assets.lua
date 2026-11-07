-- Asset loading with placeholder fallbacks, so the game runs while the asset
-- folders are empty or half-filled. Missing or unreadable files become:
--   images -> a flat-color square image
--   sounds -> a silent source stub that accepts the usual Source calls
--   fonts  -> LÖVE's built-in font at the requested size
-- Launch with `love . --placeholder-assets` to force every fallback, which
-- simulates empty asset folders without deleting anything.

Assets = {
    forcePlaceholders = false,
    missing = {},             -- paths that fell back to a placeholder
    placeholderSize = 16,
}

local function noop() end

local function recordMissing(kind, path, reason)
    Assets.missing[#Assets.missing + 1] = {kind = kind, path = tostring(path), reason = reason}
    print(string.format('[assets] placeholder %s for %s (%s)', kind, tostring(path), reason))
end

local function available(kind, path)
    if Assets.forcePlaceholders then
        recordMissing(kind, path, 'placeholders forced')
        return false
    end
    if type(path) ~= 'string' or love.filesystem.getInfo(path, 'file') == nil then
        recordMissing(kind, path, 'file not found')
        return false
    end
    return true
end

function Assets.newPlaceholderImage(color, width, height)
    color = color or {1, 0, 1, 1}
    width = width or Assets.placeholderSize
    height = height or width

    local data = love.image.newImageData(width, height)
    local r, g, b, a = color[1], color[2], color[3], color[4] or 1
    data:mapPixel(function() return r, g, b, a end)

    local image = love.graphics.newImage(data)
    image:setFilter('nearest', 'nearest')
    return image
end

function Assets.newSilentSound()
    local stub = {isPlaceholder = true}
    function stub.play() return true end
    function stub.isPlaying() return false end
    function stub.getVolume() return 0 end
    function stub.isLooping() return false end
    function stub.clone() return Assets.newSilentSound() end
    -- every other Source method (stop, setVolume, setLooping, ...) is a no-op
    return setmetatable(stub, {__index = function() return noop end})
end

-- Returns image, isPlaceholder. `fallbackSize` (optional) sizes the square
-- placeholder, e.g. so placeholder growth stages still get bigger.
function Assets.loadImage(path, fallbackColor, fallbackSize)
    if available('image', path) then
        local ok, image = pcall(love.graphics.newImage, path)
        if ok then return image, false end
        recordMissing('image', path, tostring(image))
    end
    return Assets.newPlaceholderImage(fallbackColor, fallbackSize), true
end

-- Returns source, isPlaceholder.
function Assets.loadSound(path, sourceType)
    if love.audio and available('sound', path) then
        local ok, source = pcall(love.audio.newSource, path, sourceType or 'static')
        if ok then return source, false end
        recordMissing('sound', path, tostring(source))
    elseif not love.audio then
        recordMissing('sound', path, 'audio module disabled')
    end
    return Assets.newSilentSound(), true
end

-- Returns font, isPlaceholder.
function Assets.loadFont(path, size)
    if path and available('font', path) then
        local ok, font = pcall(love.graphics.newFont, path, size)
        if ok then return font, false end
        recordMissing('font', path, tostring(font))
    end
    return love.graphics.newFont(size), path ~= nil
end

-- Fills `target` from a manifest of {key = {path, fallback, extra}} entries
-- using `loader(path, fallback, extra)`; returns target.
function Assets.loadAll(target, manifest, loader)
    for key, entry in pairs(manifest) do
        target[key] = loader(entry[1], entry[2], entry[3])
    end
    return target
end
