
local check_signals = {
    skip     = "%[virtual%-signal=skip%-signal]",
    fuel     = "%[virtual%-signal=refuel%-signal]",
    depot    = "%[virtual%-signal=depot%-signal]",
    load     = "%[virtual%-signal=load%-signal]",
    unload   = "%[virtual%-signal=unload%-signal]",
    priority = "%[virtual%-signal=priority%-signal]",
    optional = "%[virtual%-signal=optional%-signal]",
}

Signals = {}

---@param station string
---@return table
function Signals.contains(station)
    local found = {}

    for name, pat in pairs(check_signals) do
        if station:find(pat) then found[name] = true end
    end

    return found
end

---@param name string
---@param signal string
---@return unknown
local function remove(name, signal)
    return name:gsub(check_signals[signal], "")
end

---@param name string
---@param signal string
---@return unknown
local function contains(name, signal)
    return name:find(check_signals[signal])
end

---@param name string
---@return unknown
function Signals.contains_skip(name)
    return name:find(check_signals.skip)
end

---@param station string
---@return string
function Signals.enable(station)
    return station:gsub(check_signals.skip, "")
end

---@param station string
---@return string
function Signals.disable(station)
    return check_signals.skip:gsub("%%", "") .. station
end

---@param station string
---@return string?
function Signals.clean_station_name(station)
    local change = false
    local new = station

    local contains = Signals.contains(station)

    if contains.skip then
        change = true
        new = Signals.enable(new)
    end

    if contains.fuel or contains.depot then
        if contains.load then
            change = true
            new = remove(new, "load")
        end
        if contains.unload then
            change = true
            new = remove(new, "unload")
        end
        if contains.priority then
            change = true
            new = remove(new, "priority")
        end
        if contains.optional then
            change = true
            new = remove(new, "optional")
        end
    end

    contains = Signals.contains(new) -- do this again in case they were removed.
    if contains.load and contains.unload then
        change = true
        if contains(new, "load") < contains(new, "unload") then
            new = remove(new, "unload")
        else
            new = remove(new, "load")
        end
    end

    if change then return new end
end