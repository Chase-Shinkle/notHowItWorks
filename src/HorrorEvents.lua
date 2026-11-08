-- Tiny mutual-exclusion registry for backrooms horror events (light flash, distant sound, silhouette).
-- Each event registers an "am I active?" predicate; a new event may only start when no OTHER is active.
HorrorEvents = {preds = {}}

function HorrorEvents.register(name, fn) HorrorEvents.preds[name] = fn end
function HorrorEvents.unregister(name) HorrorEvents.preds[name] = nil end

function HorrorEvents.otherActive(name)
    for n, fn in pairs(HorrorEvents.preds) do
        if n ~= name then
            local ok, a = pcall(fn)
            if ok and a then return true end
        end
    end
    return false
end
