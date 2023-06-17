require("util")
require("schedule")
require("signals")

local function init()
    global.train_data = global.train_data or {}
    global.self_edit = global.self_edit or {}
    global.energy = {}

    for name, data in pairs(game.get_filtered_item_prototypes{{filter="fuel-value", comparison = ">", value=0}}) do
        global.energy[name] = data.fuel_value
    end
end

script.on_init(function()
    init()
end)

script.on_configuration_changed(function()
    init()
end)

local state_func = {
    [defines.train_state.arrive_station]   = Schedule.arriving,
    [defines.train_state.wait_station]     = Schedule.waiting,
    [defines.train_state.no_path]          = Schedule.try_next_in_group,
    [defines.train_state.destination_full] = Schedule.try_next_in_group,
}

script.on_event(defines.events.on_train_changed_state, function(event)
    local train = event.train
    if not train or not train.valid or not state_func[train.state] then return end

    local schedule = train.schedule
    if not schedule then return end
    local current = schedule.records[schedule.current]
    if not current or current.temporary then return end

    state_func[train.state](train, schedule)

    Schedule.set_schedule(train, schedule)
end)

--update train data when the schedule changes ignoring changes made by its self.
script.on_event(defines.events.on_train_schedule_changed, function(event)
    local train = event.train
    --game.print("schedule change: " .. train.id .. " self_edit: " .. tostring(global.self_edit[train.id]))
    if global.self_edit[train.id] then
        global.self_edit[train.id] = nil
        return
    end

    local schedule = train.schedule
    if not schedule then return end
    Schedule.open_schedule(schedule)
    Schedule.add_waits(schedule)
    Schedule.calc_train_data(train.id, schedule)
    Schedule.set_schedule(train, schedule)
end)

--try and transfer train data from modified trains or generate new data.
script.on_event(defines.events.on_train_created, function(event)
    --game.print(string.format("old1: %s, old2: %s, new: %s", event.old_train_id_1, event.old_train_id_2, event.train.id))
    if not Schedule.transfer_data(event) then
        local train = event.train
        Schedule.calc_train_data(train.id, train.schedule or {current=0, records={}})
    end
end)

--remove train data from trains that have been destroyed.
script.on_event({
    defines.events.script_raised_destroy,
    defines.events.on_entity_destroyed,
    defines.events.on_player_mined_entity,
    defines.events.on_robot_mined_entity,
    defines.events.on_entity_died
}, function(event)
    if not event.entity or not event.entity.train then return end
    local train = event.entity.train
    --game.print("train destroyed: " .. train.id .. " cars: " .. #train.carriages)
    if #train.carriages == 1 then
        global.train_data[train.id] = nil
    end
end)

--update train schedules on train stop name change like vanilla accounting for disabled records.
script.on_event(defines.events.on_entity_renamed, function(event)
    local entity = event.entity
    if not (entity and entity.valid and entity.type == "train-stop") then return end

    local cleaned_name = Signals.clean_station_name(entity.backer_name)
    if cleaned_name then
        game.print(entity.backer_name .. " contained incompatible symbols new name: " .. cleaned_name)
        entity.backer_name = cleaned_name
        return -- return because it creates a new on_entity_renamed event.
    end

    local old_name = event.old_name
    local old_disabled_name = Signals.disable(event.old_name)
    local new_disabled_name = Signals.disable(entity.backer_name)

    local stops = entity.force.get_train_stops{surface = entity.surface, name = old_name}
    if next(stops) then return end --there are still some with the old name, do nothing

    local trains = entity.force.get_trains(entity.surface)

    for _, train in pairs(trains) do
        local schedule = train.schedule or {records={}}
        local changed = false
        for _, record in pairs(schedule.records) do
            if record.station and record.station == old_disabled_name then
                changed = true
                record.station = new_disabled_name
            end
        end
        if changed then
            Schedule.set_schedule(train, schedule)
            Schedule.calc_train_data(train.id, schedule)
        end
    end
end)

commands.add_command("reset-train-data", nil, function (command)
    local copy = table.deepcopy(global.train_data)
    local trains = {}
    for _, f in pairs(game.forces) do
        for _, t in pairs(f.get_trains()) do
            trains[t.id] = t
        end
    end

    game.print("Building train data...")
    for _, t in pairs(trains) do
        if t.schedule then
            Schedule.calc_train_data(t.id, t.schedule)
            copy[t.id] = nil
        end
    end

    for id, _ in pairs(copy) do
        global.train_data[id] = nil
    end

    game.print("Done.")
end)