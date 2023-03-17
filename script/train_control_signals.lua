--[[
  Train data is generated when a trains schedule is edited so the station names don't have to be parsed each time it is needed.

global.train_data[train.id]{ --Each train has extra data attached to it indexed by its id.
  .self_edit        --true if it has edited the train schedule its self so it can ignore the event.
  .edited           --true if the train data has been recently modified.
  .currently_at     --The last station the train has stopped at.
  .groups[index]{   --List of all groups in the schedule and the indexes of where they start and end.
    .start
    .stop
  }
  .fuel_stations[]  --List of all indexes of fuel stations in the schedule
  .records[index]{  --Data attached to individual records in the trains schedule.
    .group          --The index of the group the the record is in or nil.
    .is_fuel        --
    .is_depot       --
    .is_priority    --
    .is_optional    --
  }
}
]]--

local util = require("util")

local fuel_signal = "%[virtual%-signal=refuel%-signal]"

local depot_signal = "%[virtual%-signal=depot%-signal]"

local skip_signal = "%[virtual%-signal=skip%-signal]"

local load_signal = "%[virtual%-signal=load%-signal]"
local unload_signal = "%[virtual%-signal=unload%-signal]"

local priority_signal = "%[virtual%-signal=priority%-signal]"
local optional_signal = "%[virtual%-signal=optional%-signal]"

--list of all signals that are checked for when a station name is changed.
local all_signals = {
  fuel_signal     = fuel_signal,
  depot_signal    = depot_signal,
  load_signal     = load_signal,
  unload_signal   = unload_signal,
  priority_signal = priority_signal,
  optional_signal = optional_signal,
}

local last_group = function(schedule)
  if schedule.data.currently_at then
    return schedule.data.records[schedule.data.currently_at].group
  end
  return nil
end

local group_start = function(schedule, index)
  local group = schedule.data.records[index].group

  if group then
    return schedule.data.groups[group].start
  end
  return index
end

local group_end = function(schedule, index)
  local group = schedule.data.records[index].group

  if group then
    return schedule.data.groups[group].stop
  end
  return index
end

local prev_station = function(schedule, index)
  local temp = group_start(schedule, index) - 1

  if temp == 0 then
    return #schedule.records
  end
  return temp
end

local next_station = function(schedule, index)
  --game.print("next_station")
  local temp = group_end(schedule, index) + 1

  if temp > #schedule.records then
    return 1
  end
  return temp
end

local enable_station = function(station)
  return station:gsub(skip_signal, "")
end

local enable_index = function(schedule, index)
  schedule.records[index].station = enable_station(schedule.records[index].station)
end

local disable_station = function(station)
  return skip_signal:gsub("%%", "") .. station
end

local disable_index = function(schedule, index)
  schedule.records[index].station = disable_station(schedule.records[index].station)
end

print_train_data = function(id)
  game.print("train id #" .. id .. " : " .. serpent.dump(global.train_data[id]))
end

print_train_data_cmd = function(command)
  if command.parameter then
    local id = tonumber(command.parameter)
    if id then
      if global.train_data[id] then
        print_train_data(id)
      else
        game.print("No train data with that id.")
      end
    end
  else
    for k, _ in pairs(global.train_data) do
      print_train_data(k)
    end
  end
end

get_trains = function()
  local trains = {}

  for _, f in pairs(game.forces) do
    for _, t in pairs(f.get_trains()) do
      trains[t.id] = t
    end
  end

  return trains
end

check_for_train_errors = function()
  game.print("Scanning for errors.")
  local errors = false
  local trains = get_trains()

  for k, v in pairs(global.train_data) do
    if trains[k] == nil then
      game.print("Id: " .. k .. " in train data doesn't match a real train.")
      errors = true
      global.train_data[k] = nil
    end
  end

  for k, v in pairs(trains) do
    if global.train_data[k] == nil and v.schedule ~= nil then
      game.print("train Id: " .. k .. " doesn't  have train data.")
      errors = true
      calc_train_data(v)
    end
  end

  if errors == false then
    game.print("No errors found.")
  end

end

reset_train_data = function()
  global.train_data = {}

  game.print("Building train schedule data...")
  for _, t in pairs(get_trains()) do
    calc_train_data(t)
  end
  game.print("Done.")
end

check_for_deadlocks = function()
  game.print("Checking for deadlocks...")
  for _, train in pairs(get_trains()) do
    if care_about[train.state] then
      --game.print("scanning train: " .. train.id)
      local schedule = train.schedule

      if schedule and global.train_data[train.id] and global.train_data[train.id].currently_at then
        schedule.data = global.train_data[train.id]
        local current = next_station(schedule, schedule.data.currently_at)
  
        -- find the next station that isn't a depot
        --game.print("current: " .. current .. " data: " .. serpent.dump(schedule.data.records[current]))
        while schedule.data.records[current].is_depot do
          current = next_station(schedule, current)
          --game.print("current: " .. current .. " data: " .. serpent.dump(schedule.data.records[current]))
        end
  
        -- if next station is a group check if it is deadlocked
        local group = schedule.data.records[current].group
        if group then
          --game.print("group: " .. group)
          local deadlocked = true
  
          -- if the group contains any temporary or non skipped stations then it is not deadlocked.
          for i = schedule.data.groups[group].start, schedule.data.groups[group].stop do
            --game.print("index: " .. i)
            if schedule.records[i].temporary or (not schedule.records[i].station:find(skip_signal)) then
              deadlocked = false
              break
            end
          end
  
          -- if deadlocked try to unlock it.
          if deadlocked then
            game.print("Deadlock detected on train: " .. train.id)
  
            if schedule.data.records[schedule.data.currently_at].is_priority then
              enable_group(schedule, group)
            else
              enable_except_optional(schedule, group)
            end
  
            schedule.current = schedule.data.currently_at
  
            schedule.data.self_edit = true
            train.schedule = schedule
          end
        end
      end
    end
  end
  game.print("Done.")
end

local train_needs_refueling = function(train)
  local locomotives = train.locomotives
  for k, movers in pairs (locomotives) do
    for k, locomotive in pairs (movers) do
      local fuel_inventory = locomotive.get_fuel_inventory()
      if not fuel_inventory then return false end
      if #fuel_inventory == 0 then return false end
      fuel_inventory.sort_and_merge()
      if #fuel_inventory > 1 then
        if not fuel_inventory[2].valid_for_read then
          return true
        end
      else
        --Locomotive with only 1 fuel stack... idk, lets just guess
        local stack = fuel_inventory[1]
        if not stack.valid_for_read then
          --Nothing in the stack, needs refueling.
          return true
        end
        if stack.count < math.ceil(stack.prototype.stack_size / 4) then
          return true
        end
      end
    end
  end
  return false
end

local check_for_depot = function(schedule)
  -- Only checks if it can go to a depot if it can't go anywhere else.
  -- Only checks if the station right after the group it is currently stationed at is a depot.

  if not schedule.data.currently_at then return false end
  local next = next_station(schedule, schedule.data.currently_at)

  if schedule.data.records[next].is_depot then
    --game.print("depot found")
    enable_index(schedule, next)
    return true
  end

  return false
end

-- reenables the stations in the group that the train has just left unless they are optional.
enable_except_optional = function(schedule, group)
  if not group then return end

  for i = schedule.data.groups[group].start, schedule.data.groups[group].stop do

    if not schedule.data.records[i].is_optional then
      --game.print("enabling")
      enable_index(schedule, i)
    end
  end
end

enable_group = function(schedule, group)
  if not group then return end

  for i = schedule.data.groups[group].start, schedule.data.groups[group].stop do
    enable_index(schedule, i)
  end
end

--finds the index of the next non optional station in a group or nil if none are found.
local next_non_optional = function(schedule, group)
  local next = schedule.current + 1

  while next <= schedule.data.groups[group].stop do
    if not schedule.data.records[next].is_optional then
      --game.print("found next: " .. next)
      return next
    end

    next = next + 1
  end

  --game.print("found none.")
  return
end

--the train has reached the last available station in the group so it checks for a depot and resets to the start of the group.
local reset_group = function(schedule, group)
  if schedule.data.records[schedule.data.currently_at].is_priority then
    enable_group(schedule, group)
  else
    enable_except_optional(schedule, group)
  end
  
  check_for_depot(schedule)
end

-- tries to move to the next station in group or tries to open a depot if needed.
local try_next_in_group = function(schedule, train)
  local group = schedule.data.records[schedule.current].group

  --if the next station cant be reached and is not a part of a group then just check for a depot.
  if not group then
    if check_for_depot(schedule) == false then return end

  --the current station is at the end of the group and can't be reached so reset the group.
  elseif schedule.current == schedule.data.groups[group].stop then
    reset_group(schedule, group)

  --the next station cant be reached but there are more stations in the group so check if the next station in the group is open.
  else
    --if the train is currently not at a priority station then it has to jump over optional stations in the group.
    if not schedule.data.records[schedule.data.currently_at].is_priority then
      --group doesn't have any more non optional stations
      --game.print("non priority")
      if not next_non_optional(schedule, group) then
        --game.print("no more found resetting")
        reset_group(schedule, group)
      else
        --disable the current destination so it can check the next one.
        disable_index(schedule, schedule.current)
      end
    else
      --disable the current destination so it can check the next one.
      disable_index(schedule, schedule.current)
    end
  end

  --reset the schedule to where the train currently is so new train events can be generated.
  schedule.current = schedule.data.currently_at
end

local disable_rest_of_next_group = function(schedule)
  local group = schedule.data.records[schedule.current].group
  --game.print("disabling group")

  if not group then return end

  for i = schedule.current + 1, schedule.data.groups[group].stop do
    if not schedule.records[i].station:find(skip_signal) then
      disable_index(schedule, i)
    end
  end

end

local disable_if_depot = function(schedule)
  --game.print("disabling if depot")
  if not schedule.data.currently_at then return end
  --game.print("is depot and disabling")

  if schedule.data.records[schedule.data.currently_at].is_depot then
    disable_index(schedule, schedule.data.currently_at)
  end
end

local fuel_stations = function(train, schedule)
  --If the station the train is currently pulling into is a fuel station don't check.
  --This prevents the train getting stuck if got sent to a fuel station while being full.
  if schedule.data.records[schedule.current].is_fuel then return end

  needs_refuel = train_needs_refueling(train)

  for k, index in pairs (schedule.data.fuel_stations) do
    if needs_refuel then
      enable_index(schedule, index)
    else
      --check if the station has already been disable to prevent the station from collecting multiple skip signals.
      if not schedule.records[index].station:find(skip_signal) then
        disable_index(schedule, index)
      end
    end
  end
end

local check_priority = function(schedule)
  -- if the station it left was optional disable it.
  if schedule.data.records[schedule.data.currently_at].is_optional then
    disable_index(schedule, schedule.data.currently_at)
  end

  -- if the station it is pulling into is high priority enable upcoming optional stations
  if schedule.data.records[schedule.current].is_priority then
    local next = next_station(schedule, schedule.current)

    -- find the next station that isn't a depot
    while schedule.data.records[next].is_depot do
      next = next_station(schedule, next)
    end

    enable_group(schedule, schedule.data.records[next].group)
  end
end

care_about = {
  [defines.train_state.arrive_station]   = true,
  [defines.train_state.wait_station]     = true,
  [defines.train_state.no_path]          = true,
  [defines.train_state.destination_full] = true,
}

--functions to run when each state occurs.
local run = {
  ------------------------------------------------------------------------------------------------------------------------
  [defines.train_state.arrive_station]   = function(train, schedule)
    disable_if_depot(schedule)
    enable_except_optional(schedule, last_group(schedule))
    check_priority(schedule)
    disable_rest_of_next_group(schedule)
    fuel_stations(train, schedule)
  end,

  ------------------------------------------------------------------------------------------------------------------------
  [defines.train_state.wait_station]     = function(train, schedule)
    schedule.data.currently_at = schedule.current
    if schedule.data.edited then
      disable_rest_of_next_group(schedule)

      --check if the train is currently at a priority station and if it is not disable all of the optional stations.
      if not schedule.data.records[schedule.current].is_priority then
        for i, _ in pairs(schedule.records) do
          if (i ~= schedule.current) and (schedule.data.records[i].is_optional) then
            disable_index(schedule, i)
          end
        end
      end

      schedule.data.edited = nil
    end
  end,

  ------------------------------------------------------------------------------------------------------------------------
  [defines.train_state.no_path]          = function(train, schedule)
    try_next_in_group(schedule, train)
  end,

  ------------------------------------------------------------------------------------------------------------------------
  [defines.train_state.destination_full] = function(train, schedule)
    try_next_in_group(schedule, train)
  end,
}

local on_train_changed_state = function(event)

  local train = event.train
  if not (train and train.valid)   then return end
  if not (care_about[train.state]) then return end

  local schedule = train.schedule
  if not schedule then return end

  -- if the train is currently working on a temporary order wait until it has been removed.
  if schedule.records[schedule.current].temporary then return end

  schedule.data = global.train_data[train.id]

  if schedule.data == nil then
    game.print("An error has been detected in train schedule data.")
    check_for_train_errors()
    game.print("Done!")
  end

  run[train.state](train, schedule)
  --[[
  if train.state == defines.train_state.arrive_station then
    disable_if_depot(schedule)
    enable_except_optional(schedule, last_group(schedule))
    disable_rest_of_next_group(schedule)
    fuel_stations(train, schedule)
  elseif train.state == defines.train_state.wait_station then
    schedule.data.currently_at = schedule.current
  else
    try_next_in_group(schedule, train)
  end
  ]]--

  schedule.data.self_edit = true
  train.schedule = schedule
end

local check_rename_signal = function(entity, old_name)
  --game.print("checking for signals")

  local new_name = entity.backer_name

  -- look for signals that can be skipped in station name
  local found_signals = false
  for k, signal in pairs(all_signals) do
    if old_name:find(signal) then
      found_signals = true
      break
    end
  end

  -- if there are none leave
  if found_signals == false then return end

  --game.print("signals found")

  --old name had a control signal, lets emulate the base game thing where it fixes the schedules

  local stops = entity.force.get_train_stops({surface = entity.surface, name = old_name})
  if next(stops) then
    --there are still some with the old name, do nothing
    return
  end

  local old_disabled_name = disable_station(old_name)
  local new_disabled_name = disable_station(new_name)

  --game.print("station old name: " .. old_name)
  --game.print("station new name: " .. new_name)

  local trains = entity.force.get_trains(entity.surface)

  for k, train in pairs(trains) do
    --game.print("checking train: " .. train.id)
    local schedule = train.schedule
    if schedule then
      local changed = false
      for k, record in pairs(schedule.records) do
        if record.station then
          --game.print("record name: " .. record.station)
          if record.station == old_disabled_name then
            changed = true
            record.station = new_disabled_name
          elseif record.station == new_name then
            changed = true
          end
        end
      end
      if changed then
        --game.print("changes in train")
        global.train_data[train.id].self_edit = true
        train.schedule = schedule
        calc_train_data(train)
      end
    end
  end
end

local on_entity_renamed = function(event)
  local entity = event.entity
  if not (entity and entity.valid and entity.type == "train-stop") then
    return
  end
  --game.print("station renamed")

  if entity.backer_name:find(skip_signal) then
    --naughty...
    entity.backer_name = enable_station(skip_signal)
    return
  end

  check_rename_signal(entity, event.old_name)

end

--finds all stations that are in a single group
--So i is the index of the schedule and r is the index of the schedule ignoring the temps.
full_group = function(temp_data, train_data, group)
  table.insert(train_data.groups, {start = temp_data.r, stop = temp_data.r})
  local group_num = #train_data.groups

  train_data.records[temp_data.r].group = group_num
  temp_data.i = temp_data.i + 1
  temp_data.r = temp_data.r + 1

  while(temp_data.i <= temp_data.len) do
    if temp_data.records[temp_data.i].temporary then
      temp_data.i = temp_data.i + 1
    else
      local signals = find_signals(temp_data.records[temp_data.i].station)
      signals_into_train_data(signals, train_data, temp_data.r)

      if signals.group == group then
        train_data.records[temp_data.r].group = group_num
        train_data.groups[group_num].stop = temp_data.r

        temp_data.i = temp_data.i + 1
        temp_data.r = temp_data.r + 1
      else
        break
      end
    end
  end
end


--adds a configurable wait time to trains to prevent trains from checking for a new path every tick.
add_wait_times = function(schedule)
    
  if settings.global["wait-at-stops"].value == 0 then return end
  wait_time = settings.global["wait-at-stops"].value * 60

  --game.print("adding wait times: " .. wait_time)

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

    local new_wait = nil

    --makes sure that the time wait condition is at the end of the list.
    if has_wait then
      new_wait = table.remove(record.wait_conditions, has_wait)
    else
      new_wait = {type = "time", compare_type = "and", ticks = wait_time}
    end

    table.insert(record.wait_conditions, new_wait)
  end
end

find_signals = function(station)
  local signals = {}

  if station:find(fuel_signal)     then signals.fuel     = true end
  if station:find(depot_signal)    then signals.depot    = true end
  if station:find(priority_signal) then signals.priority = true end
  if station:find(optional_signal) then signals.optional = true end

  if station:find(load_signal) then
    signals.group = load_signal
  elseif station:find(unload_signal) then
    signals.group = unload_signal
  end
  
  return signals
end

signals_into_train_data = function(signals, train_data, index)
  train_data.records[index] = {}

  if signals.fuel then
    table.insert(train_data.fuel_stations, index)
    train_data.records[index].is_fuel = true
  end
  
    train_data.records[index].is_depot    = signals.depot
    train_data.records[index].is_priority = signals.priority
    train_data.records[index].is_optional = signals.optional
end

--will find all of the stations that are grouped together.
calc_train_data = function(train)
  if not train.schedule then return end
  local schedule = train.schedule

  --set up data in table for easer passing to functions.
  local temp_data = {
    i = 1,
    r = 1,
    len = #schedule.records,
    records = schedule.records,
  }

  local old_data = global.train_data[train.id]
  local old_currently_at = nil

  if old_data then
    old_currently_at = old_data.currently_at
  end

  local train_data = {
    edited        = true,
    currently_at  = old_currently_at or schedule.current,
    fuel_stations = {},
    groups        = {},
    records       = {}
  }

  --The extra train data should act like the temporary stops don't exist.
  --So i is the index of the schedule and r is the index of the schedule ignoring the temps.
  while(temp_data.i <= temp_data.len) do
    if temp_data.records[temp_data.i].temporary then
      temp_data.i = temp_data.i + 1
    else
      local signals = find_signals(temp_data.records[temp_data.i].station)
      signals_into_train_data(signals, train_data, temp_data.r)

      if signals.group then
        full_group(temp_data, train_data, signals.group)
      else
        temp_data.i = temp_data.i + 1
        temp_data.r = temp_data.r + 1
      end
    end
  end

  if settings.global["wait-at-stops"].value then
    add_wait_times(schedule)

    global.train_data[train.id].self_edit = true
    train.schedule = schedule
  end

  global.train_data[train.id] = train_data
  
  --print_train_data(train.id)
end

local has_temp_records = function(schedule)
  for _, record in pairs(schedule.records) do
    if record.temporary then
      return true
    end
  end

  return false
end

--when a human edits the schedule re-enables all stations to prevent the train getting stuck.
local clean_schedule = function(train)
  if not train.schedule then return end
  local schedule = train.schedule

  if has_temp_records(schedule) then return end

  for _, record in pairs(schedule.records) do
    if record.station then
      record.station = enable_station(record.station)
    end
  end

  global.train_data[train.id].self_edit = true
  train.schedule = schedule
end

local on_train_schedule_changed = function(event)
  if not event.train then return end
  if global.train_data[event.train.id] ~= nil then
    if global.train_data[event.train.id].self_edit then
      global.train_data[event.train.id].self_edit = nil
      return
    end
  else
    global.train_data[event.train.id] = {}
  end

  clean_schedule(event.train)
  calc_train_data(event.train)
  on_train_changed_state(event)
end

--creates the extra train data table if it does't exist
local init_vars = function()
  if global.train_data == nil then
    global.train_data = {}
  end
end

--removes the extra train data from the old train id and then regenerates it for the new id.
local update_train_data = function(event)
  local old_1 = event.old_train_id_1
  local old_2 = event.old_train_id_2

  if old_1 then
    global.train_data[old_1] = nil
  end

  if old_2 then
    global.train_data[old_2] = nil
  end

  calc_train_data(event.train)
end

--when ever a train car is removed clears its extra data.
local remove_train_data = function(event)
  if not event.entity       then return end
  if not event.entity.train then return end

  global.train_data[event.entity.train.id] = nil
end

local lib = {}

lib.events =
{
  [defines.events.on_train_changed_state]    = on_train_changed_state,
  [defines.events.on_entity_renamed]         = on_entity_renamed,
  [defines.events.on_train_schedule_changed] = on_train_schedule_changed,
  [defines.events.on_train_created]          = update_train_data,

  [defines.events.script_raised_destroy]     = remove_train_data,
  [defines.events.on_entity_destroyed]       = remove_train_data,
  [defines.events.on_player_mined_entity]    = remove_train_data,
  [defines.events.on_robot_mined_entity]     = remove_train_data,
  [defines.events.on_entity_died]            = remove_train_data,
}

lib.on_init = function() 
  init_vars()
end

lib.on_configuration_changed = function()
  init_vars()
  --reset_train_data()
end

lib.add_commands = function()
  commands.add_command("scan-for-train-errors", "Compares saved train data to existing trains to find errors", check_for_train_errors)
  commands.add_command("print-train-data", "Prints the data of the train id given or all train data when no id is given.", print_train_data_cmd)
  commands.add_command("reset-train-data", "Completely reconstructs train data.", reset_train_data)
  commands.add_command("check-for-deadlocks", "Scans all trains schedules for deadlocks and tries to fix them.", check_for_deadlocks)
end

return lib