---@class record
---@field group integer --The index of the group the the record is in or nil.
---@field is_fuel boolean
---@field is_depot boolean
---@field is_priority boolean
---@field is_optional boolean
---@field is_disabled boolean

---@class train_data
---@field edited boolean
---@field primed station           --the index of station that marks the schedule is ready.
---@field currently_at station     --The last station the train has stopped at.
---@field groups {start: station, stop: station}[] --List of all groups in the schedule and the indexes of where they start and end.
---@field fuel_stations station[] --List of all indexes of fuel stations in the schedule
---@field records record[] --Data attached to individual records in the trains schedule.

require("signals")

Schedule = {}

---@param schedule TrainSchedule
---@return boolean
function Schedule.has_temp_records(schedule)
    for _, record in pairs(schedule.records) do
        if record.temporary then return true end
    end
end

---@param schedule TrainSchedule
function Schedule.open_schedule(schedule)
    for _, record in pairs(schedule.records) do
        if record.station then
            record.station = Signals.enable(record.station)
        end
    end
end

---@param train LuaTrain
---@param schedule TrainSchedule
function Schedule.set_schedule(train, schedule)
    global.self_edit[train.id] = true
    train.schedule = schedule
end

---@param id TrainID
---@param schedule TrainSchedule
function Schedule.calc_train_data(id, schedule)
    local old_data = global.train_data[id]
    local data = {
        currently_at = (old_data and old_data.currently_at) or schedule.current,
        fuel_stations = {},
        groups = {},
        records = {},
    }

    local temps = 0
    local groups = 0
    local last_group
    for i, record in pairs(schedule.records) do
        index = i - temps
        if record.temporary then
            temps = temps + 1
        else
            local signals = Signals.contains(record.station)

            data.records[index] = {
                is_fuel = signals.fuel,
                is_depot = signals.depot,
                is_priority = signals.priority,
                is_optional = signals.optional,
                is_disabled = signals.skip,
            }

            if signals.fuel then table.insert(data.fuel_stations, index) end

            local group = (signals.load and 0) or (signals.unload and 1)
            if group then
                if group ~= last_group then
                    groups = groups + 1
                    data.groups[groups] = {
                        start = index,
                        stop = index,
                    }
                    data.records[index].group = groups
                else
                    data.groups[groups].stop = index
                    data.records[index].group = groups
                end
            end
            last_group = group
        end
    end

    global.train_data[id] = data
end

---@param loco LuaEntity Locomotive
---@return boolean
local function loco_needs_fuel(loco)
    local burner = loco.burner
    if not burner or #burner.inventory == 0 then return false end

    local fuel = burner.remaining_burning_fuel
    for name, num in pairs(burner.inventory.get_contents()) do
        fuel = fuel + global.energy[name] * num
    end

    local p = loco.prototype
    local seconds = settings.global['min-fuel'].value * 60 * (p.max_energy_usage / p.burner_prototype.effectivity)
    return fuel < seconds
end

---@param train LuaTrain
---@return boolean
local function train_needs_refueling(train)
    for _, movers in pairs (train.locomotives) do
        for _, loco in pairs (movers) do
            if loco_needs_fuel(loco) then return true end
        end
    end
    return false
end

-- ---@param schedule any
-- ---@param data train_data
-- ---@param index any
-- ---@return integer
-- local function next_station(schedule, data, index)
--     local temp = index + 1
--     if temp > #schedule.records then return 1 end
--     return temp
-- end

---@param schedule LuaSchedule
---@param data train_data
---@param index station
---@return station
local function next_group(schedule, data, index)
    local group = data.records[index].group
    local current = (group and data.groups[group].stop) or index
    local temp = current + 1

    if temp > #schedule.records then return 1 end
    return temp
end

---@param schedule LuaSchedule
---@param data train_data
---@param index station
local function enable_at(schedule, data, index)
    if not data.records[index].is_disabled then return end
    data.records[index].is_disabled = false
    schedule.records[index].station = Signals.enable(schedule.records[index].station)
end

---@param schedule LuaSchedule
---@param data train_data
---@param index station
local function disable_at(schedule, data, index)
    if data.records[index].is_disabled then return end
    data.records[index].is_disabled = true
    schedule.records[index].station = Signals.disable(schedule.records[index].station)
end

---@param train LuaTrain
---@param schedule LuaSchedule
---@param data train_data
local function fuel_stations(train, schedule, data)
    if train_needs_refueling(train) then
        for _, index in pairs(data.fuel_stations) do
            enable_at(schedule, data, index)
        end
    else
        for _, index in pairs(data.fuel_stations) do
            disable_at(schedule, data, index)
        end
    end
end

---@param schedule LuaSchedule
---@param data train_data
---@return boolean
local function check_for_depot(schedule, data)
    local next = next_group(schedule, data, data.currently_at)

    if data.records[next].is_depot then
        enable_at(schedule, next)
        return true
    end
end

---@param schedule LuaSchedule
---@param data train_data
---@param group group
---@param priority priority
local function enable_group(schedule, data, group, priority)
    for i = data.groups[group].start, data.groups[group].stop do
        if priority or not data.records[i].is_optional then
            enable_at(schedule, data, i)
        end
    end
end

---@param schedule LuaSchedule
---@param data train_data
local function disable_rest_of_group(schedule, data)
    local group = data.records[schedule.current].group
    if not group then return end

    for i = schedule.current + 1, data.groups[group].stop do
        --game.print("disabling: " .. i .. " group: " .. group)
        disable_at(schedule, data, i)
    end
end

---@param schedule LuaSchedule
---@param data train_data
local function prime_next_group(schedule, data)
    if data.currently_at == data.primed then return end

    disable_rest_of_group(schedule, data)
    data.primed = data.currently_at

    local search = next_group(schedule, data, data.currently_at)
    if data.records[search].is_depot then
        disable_at(schedule, data, search)
        search = next_group(schedule, data, search)
    end

    if data.records[data.currently_at].is_priority then return end

    local group = data.records[search].group
    if not group then return end

    for i = search, data.groups[group].stop do
        if data.records[i].is_optional then
            disable_at(schedule, data, i)
        end
    end
end

---@param train LuaTrain
---@param schedule LuaSchedule
function Schedule.arriving(train, schedule)
    local data = global.train_data[train.id]

    local group = data.records[data.currently_at].group
    if group then
        enable_group(schedule, data, group, true)
    end
    
    data.currently_at = schedule.current

    prime_next_group(schedule, data)
    fuel_stations(train, schedule, data)
end

---@param train LuaTrain
---@param schedule LuaSchedule
function Schedule.waiting(train, schedule)
    local data = global.train_data[train.id]
    data.currently_at = schedule.current
    prime_next_group(schedule, data)
end

---@param train LuaTrain
---@param schedule LuaSchedule
function Schedule.try_next_in_group(train, schedule)
    local data = global.train_data[train.id]
    local group = data.records[schedule.current].group
    local current = schedule.current

    if not group then
        check_for_depot(schedule, data)
    else
        disable_at(schedule, data, current)
        local stop = data.groups[group].stop
        repeat
            current = current + 1
        until(current > stop or not data.records[current].is_disabled)

        if current > stop then
            check_for_depot(schedule, data)
            enable_group(schedule, data, group, data.records[data.currently_at].is_priority)
        end
    end

    schedule.current = data.currently_at
end

---@param schedule LuaSchedule
function Schedule.add_waits(schedule)
    if settings.global["wait-at-stops"].value == 0 then return end
    local wait_time = settings.global["wait-at-stops"].value * 60

    for _, record in pairs(schedule.records) do
        local has_wait = nil
    
        if record.wait_conditions then
            for i = #record.wait_conditions, 1, -1 do
                local condition = record.wait_conditions[i]
                if (condition.type == "time") and (condition.compare_type == "and") and (condition.ticks >= wait_time) then
                    has_wait = i
                    break
                end
            end
        else
            record.wait_conditions = {}
        end
    
        --make sure that the time wait condition is at the end of the list.
        local new_wait
        if has_wait then
            new_wait = table.remove(record.wait_conditions, has_wait)
        else
            new_wait = {type = "time", compare_type = "and", ticks = wait_time}
        end
    
        table.insert(record.wait_conditions, new_wait)
    end
end

---@param event EventData on_train_created
---@return boolean
function Schedule.transfer_data(event)
    -- game.print(string.format("old1: %s, old2: %s, new: %s", event.old_train_id_1, event.old_train_id_2, event.train.id))
    local old_1 = event.old_train_id_1
    local old_2 = event.old_train_id_2

    if (old_1 and old_2) and (old_2 > old_1) then
        old_2, old_1 = old_1, old_2
    end

    local transfer
    if old_2 then
        transfer = global.train_data[old_2]
        global.train_data[old_2] = nil
    end
    if old_1 then
        transfer = global.train_data[old_1]
        global.train_data[old_1] = nil
    end
    
    global.train_data[event.train.id] = event.train.schedule and transfer

    return transfer == nil
end