local H = wesnoth.require "lua/helper.lua"
local W = H.set_wml_action_metatable {}
local LS = wesnoth.require "lua/location_set.lua"

local ai_helper = {}

----- General helper functions ------

function ai_helper.got_1_11()
   if not wesnoth.compare_versions then return false end
   return wesnoth.compare_versions(wesnoth.game_config.version, ">=", "1.11.0-svn")
end

function ai_helper.got_exactly_1_11_0_svn()
   if not wesnoth.compare_versions then return false end
   return wesnoth.compare_versions(wesnoth.game_config.version, "==", "1.11.0-svn")
end

function ai_helper.filter(input, condition)
    -- equivalent of filter() function in Formula AI

    local filtered_table = {}

    for i,v in ipairs(input) do
        if condition(v) then
            --print(i, "true")
            table.insert(filtered_table, v)
        end
    end

    return filtered_table
end

function ai_helper.choose(input, value)
    -- equivalent of choose() function in Formula AI
    -- Returns element of a table with the largest 'value' (a function)
    -- Also returns the max value and the index

    local max_value = -9e99
    local best_input = nil
    local best_key = nil

    for k,v in pairs(input) do
        if value(v) > max_value then
            max_value = value(v)
            best_input = v
            best_key = k
        end
        --print(k, value(v), max_value)
    end

    return best_input, max_value, best_key
end

function ai_helper.clear_labels()
    -- Clear all labels on a map
    local w,h,b = wesnoth.get_map_size()
    for x = 1,w do
        for y = 1,h do
          W.label {x=x, y=y, text = "" } 
        end
    end
end

function ai_helper.put_labels(map, factor)
    -- Take map (location set) and put label containing 'value' onto the map 
    -- factor: multiply by 'factor' if set
    -- print 'nan' if element exists but is not a number

    factor = factor or 1

    ai_helper.clear_labels()
    map:iter(function(x, y, data)
          local out = tonumber(data) or 'nan'
          if (out ~= 'nan') then out = out * factor end 
          W.label {x = x, y = y, text = out }
    end)
end

function ai_helper.random(min, max)
    -- Use this function as Lua's 'math.random' is not replay or MP safe

    if not max then min, max = 1, min end
    wesnoth.fire("set_variable", { name = "LUA_random", rand = string.format("%d..%d", min, max) })
    local res = wesnoth.get_variable "LUA_random"
    wesnoth.set_variable "LUA_random"
    return res
end

function ai_helper.distance_map(units, map)
    -- Get the distance map for all units in 'units' (as a location set)
    -- DM = sum ( distance_from_unit )
    -- This is done for all elements of 'map' (a locations set), or for the entire map if 'map' is not given

    local DM = LS.create()

    if map then
        map:iter(function(x, y, data)
            local dist = 0
            for i,u in ipairs(units) do
                dist = dist + H.distance_between(u.x, u.y, x, y)
            end
            DM:insert(x, y, dist)
        end)
    else
        local w,h,b = wesnoth.get_map_size()
        for x = 1,w do
            for y = 1,h do
                local dist = 0
                for i,u in ipairs(units) do
                    dist = dist + H.distance_between(u.x, u.y, x, y)
                end
                DM:insert(x, y, dist)
            end
        end
    end
    --ai_helper.put_labels(DM)
    --W.message {speaker="narrator", message="Distance map" }

    return DM
end

function ai_helper.inverse_distance_map(units, map)
    -- Get the inverse distance map for all units in 'units' (as a location set)
    -- IDM = sum ( 1 / (distance_from_unit+1) )
    -- This is done for all elements of 'map' (a locations set), or for the entire map if 'map' is not given

    local IDM = LS.create()
    if map then
        map:iter(function(x, y, data)
            local dist = 0
            for i,u in ipairs(units) do
                dist = dist + 1. / (H.distance_between(u.x, u.y, x, y) + 1)
            end
            IDM:insert(x, y, dist)
        end)
    else
        local w,h,b = wesnoth.get_map_size()
        for x = 1,w do
            for y = 1,h do
                local dist = 0
                for i,u in ipairs(units) do
                    dist = dist + 1. / (H.distance_between(u.x, u.y, x, y) + 1)
                end
                IDM:insert(x, y, dist)
            end
        end
    end
    --ai_helper.put_labels(IDM)
    --W.message {speaker="narrator", message="Inverse distance map" }

    return IDM
end

function ai_helper.generalized_distance(x1, y1, x2, y2)
    -- determines "distance of (x1,y1) from (x2,y2) even if
    -- x2 and y2 are not necessarily both given (or not numbers)

    -- Return 0 if neither is given
    if (not x2) and (not y2) then return 0 end

    -- If only one of the parameters is set
    if (not x2) then return math.abs(y1 - y2) end
    if (not y2) then return math.abs(x1 - x2) end

    -- Otherwise, return standard distance
    return H.distance_between(x1, y1, x2, y2)
end

function ai_helper.xyoff(x, y, ori, hex)
    -- Finds hexes at a certain offset from x,y
    -- ori: direction/orientation: north (0), ne (1), se (2), s (3), sw (4), nw (5)
    -- hex: string for the hex to be queried.  Possible values:
    --   's': self, 'u': up, 'lu': left up, 'ld': left down, 'ru': right up, 'rd': right down
    --   This is all relative "looking" in the direction of 'ori'
    -- returns x,y for the queried hex

    -- Unlike Lua default, we count 'ori' from 0 (north) to 5 (nw), so that modulo operator can be used
    ori = ori % 6

    if (hex == 's') then return x, y end

    -- This is all done with ifs, to keep it as fast as possible
    if (ori == 0)  then -- "north"
        if (hex == 'u') then return x, y-1 end
        if (hex == 'd') then return x, y+1 end
        local dy = 0
        if (x % 2) == 1 then dy=1 end
        if (hex == 'lu') then return x-1, y-dy end
        if (hex == 'ld') then return x-1, y+1-dy end
        if (hex == 'ru') then return x+1, y-dy end
        if (hex == 'rd') then return x+1, y+1-dy end
    end

    if (ori == 1)  then -- "north-east"
        local dy = 0
        if (x % 2) == 1 then dy=1 end
        if (hex == 'u') then return x+1, y-dy end
        if (hex == 'd') then return x-1, y+1-dy end
        if (hex == 'lu') then return x, y-1 end
        if (hex == 'ld') then return x-1, y-dy end
        if (hex == 'ru') then return x+1, y+1-dy end
        if (hex == 'rd') then return x, y+1 end
    end

    if (ori == 2)  then -- "south-east"
        local dy = 0
        if (x % 2) == 1 then dy=1 end
        if (hex == 'u') then return x+1, y+1-dy end
        if (hex == 'd') then return x-1, y-dy end
        if (hex == 'lu') then return x+1, y-dy end
        if (hex == 'ld') then return x, y-1 end
        if (hex == 'ru') then return x, y+1 end
        if (hex == 'rd') then return x-1, y+1-dy end
    end

    if (ori == 3)  then -- "south"
        if (hex == 'u') then return x, y+1 end
        if (hex == 'd') then return x, y-1 end
        local dy = 0
        if (x % 2) == 1 then dy=1 end
        if (hex == 'lu') then return x+1, y+1-dy end
        if (hex == 'ld') then return x+1, y-dy end
        if (hex == 'ru') then return x-1, y+1-dy end
        if (hex == 'rd') then return x-1, y-dy end
    end

    if (ori == 4)  then -- "south-west"
        local dy = 0
        if (x % 2) == 1 then dy=1 end
        if (hex == 'u') then return x-1, y+1-dy end
        if (hex == 'd') then return x+1, y-dy end
        if (hex == 'lu') then return x, y+1 end
        if (hex == 'ld') then return x+1, y+1-dy end
        if (hex == 'ru') then return x-1, y-dy end
        if (hex == 'rd') then return x, y-1 end
    end

    if (ori == 5)  then -- "north-west"
        local dy = 0
        if (x % 2) == 1 then dy=1 end
        if (hex == 'u') then return x-1, y-dy end
        if (hex == 'd') then return x+1, y+1-dy end
        if (hex == 'lu') then return x-1, y+1-dy end
        if (hex == 'ld') then return x, y+1 end
        if (hex == 'ru') then return x, y-1 end
        if (hex == 'rd') then return x+1, y-dy end
    end

    return
end

--------- Location set related helper functions ----------

function ai_helper.get_LS_xy(index)
    -- Get the x,y coordinates from a location set index
    -- For some reason, there doesn't seem to be a LS function for this

    local tmp_set = LS.create()
    tmp_set.values[index] = 1
    local xy = tmp_set:to_pairs()[1]

    return xy[1], xy[2]
end

function ai_helper.LS_of_triples(table)
    -- Create a location set from a table of 3-element tables
    -- Elements 1 and 2 are x,y coordinates, #3 is value to be inserted

    local set = LS.create()
    for k,t in pairs(table) do
        set:insert(t[1], t[2], t[3])
    end
    return set
end

function ai_helper.to_triples(set)
    local res = {}
    set:iter(function(x, y, v) table.insert(res, { x, y, v }) end)
    return res
end

function ai_helper.LS_random_hex(set)
    -- Select a random hex out of the 
    -- This seems "inelegant", but I can't come up with another way without creating an extra array
    -- Return -1, -1 is set is empty

    local r = ai_helper.random(set:size())
    local i, xr, yr = 1, -1, -1
    set:iter( function(x, y, v)
        if (i == r) then xr, yr = x, y end
        i = i + 1
    end)

    return xr, yr
end

--------- Move related helper functions ----------

function ai_helper.get_dst_src_units(units, cfg)
    -- Get the dst_src LS for 'units'

    local max_moves = false
    if cfg then
        if (cfg['moves'] == 'max') then max_moves = true end
    end

    local dstsrc = LS.create()
    for i,u in ipairs(units) do
        -- If {moves = 'max} is set
        local tmp = u.moves
        if max_moves then
            u.moves = u.max_moves
        end
        local reach = wesnoth.find_reach(u)
        if max_moves then
            u.moves = tmp
        end
        for j,r in ipairs(reach) do
            local tmp = dstsrc:get(r[1], r[2]) or {}
            table.insert(tmp, {x = u.x, y = u.y})
            dstsrc:insert(r[1], r[2], tmp)
        end
    end
    return dstsrc
end

function ai_helper.get_dst_src(units)
    -- Produces the same output as ai.get_dst_src()   (available in 1.11.0)
    -- If units is given, use them, otherwise do it for all units on side
    
    local my_units = {}
    if units then
        my_units = units
    else
        my_units = wesnoth.get_units { side = wesnoth.current.side }
    end

    return ai_helper.get_dst_src_units(my_units)
end

function ai_helper.get_enemy_dst_src()
    -- Produces the same output as ai.get_enemy_dst_src()   (available in 1.11.0)

    local enemies = wesnoth.get_units {
        { "filter_side", {{"enemy_of", {side = wesnoth.current.side} }} }
    }

    return ai_helper.get_dst_src_units(enemies, {moves = 'max'})
end

function ai_helper.my_moves()
    -- Produces a table with each (numerical) field of form:
    --   [1] = { dst = { x = 7, y = 16 },
    --           src = { x = 6, y = 16 } }

    local dstsrc = ai.get_dstsrc()

    local my_moves = {}
    for key,value in pairs(dstsrc) do 
        --print("src: ",value[1].x,value[1].y,"    -- dst: ",key.x,key.y)
        table.insert( my_moves, 
            {   src = { x = value[1].x , y = value[1].y }, 
                dst = { x = key.x , y = key.y }
            }
        )
    end

    return my_moves
end

function ai_helper.enemy_moves()
    -- Produces a table with each (numerical) field of form:
    --   [1] = { dst = { x = 7, y = 16 },
    --           src = { x = 6, y = 16 } }

    local dstsrc = ai.get_enemy_dstsrc()

    local enemy_moves = {}
    for key,value in pairs(dstsrc) do 
        --print("src: ",value[1].x,value[1].y,"    -- dst: ",key.x,key.y)
        table.insert( enemy_moves, 
            {   src = { x = value[1].x , y = value[1].y }, 
                dst = { x = key.x , y = key.y }
            }
        )
    end

    return enemy_moves
end

function ai_helper.next_hop(unit, x, y, cfg)
    -- Finds the next "hop" of 'unit' on its way to (x,y)
    -- Returns coordinates of the endpoint of the hop, and movement cost to get there
    -- only unoccupied hexes are considered
    -- cfg: extra options for wesnoth.find_path()
    local path, cost = wesnoth.find_path(unit, x, y, cfg)

    -- If unit cannot get there:
    if cost >= 42424242 then return nil, cost end

    -- If none of the hexes is unoccupied, use current position as default
    local next_hop, nh_cost = {unit.x, unit.y}, 0

    -- Go through loop to find reachable, unoccupied hex along the path
    for index, path_loc in ipairs(path) do
        local sub_path, sub_cost = wesnoth.find_path( unit, path_loc[1], path_loc[2], cfg)

        if sub_cost <= unit.moves then
            local unit_in_way = wesnoth.get_units{ x = path_loc[1], y = path_loc[2] }[1]
            if not unit_in_way then
                next_hop, nh_cost = path_loc, sub_cost
            end
        else
            break
        end
    end

    return next_hop, nh_cost
end

function ai_helper.get_reachable_unocc(unit, cfg)
    -- Get all reachable hexes for unit that are unoccupied (incl. by allied units)
    -- Returned array is a location set, with value = 1 for each reachable hex
    -- cfg: parameters to wesnoth.find_reach, such as {additional_turns = 1}
    -- additional, {moves = 'max'} can be set inside cfg, which sets unit MP to max_moves before calculation

    local old_moves = unit.moves
    if cfg then
        if (cfg.moves == 'max') then
            unit.moves = unit.max_moves
        end
    end

    local reach = LS.create()
    local initial_reach = wesnoth.find_reach(unit, cfg)

    for i,loc in ipairs(initial_reach) do
        local unit_in_way = wesnoth.get_unit(loc[1], loc[2])
        if not unit_in_way then
            reach:insert(loc[1], loc[2], 1)
        end
    end

    -- Also need to include the hex the unit is on itself
    reach:insert(unit.x, unit.y, 1)

    -- Reset unit moves (can be done whether it was changed or not)
    unit.moves = old_moves

    return reach
end


---------- Attack related helper functions --------------

function ai_helper.simulate_combat_loc(attacker, dst, defender, weapon)
    -- Get simulate_combat results for unit 'attacker' attacking unit at 'defender'
    -- when on terrain as that at 'dst', which is of form {x,y}
    -- If 'weapon' is set (to number of attack), use that weapon (starting at 1), otherwise use best weapon

    local attacker_dst = wesnoth.copy_unit(attacker)
    attacker_dst.x, attacker_dst.y = dst[1], dst[2]

    if weapon then
        return wesnoth.simulate_combat( attacker_dst, weapon, defender)
    else
        return wesnoth.simulate_combat( attacker_dst, defender)
    end
end

function ai_helper.get_attacks_unit(unit, moves)
    -- Get all attacks a unit can do
    -- moves: if set, use this for 'moves' key, otherwise use "current"
    -- Returns {} if no attacks can be done, otherwise table with fields
    --   x, y: attack position
    --   attacker_id: id of attacking unit
    --   defender_id: id of defending unit
    --   att_stats, def_stats: as returned by wesnoth.simulate_combat
    -- This is somewhat slow, but will hopefully replaced soon by built-in AI function

    -- Need to find reachable hexes that are
    -- 1. next to an enemy unit
    -- 2. not occupied by an allied unit (except for unit itself)
    W.store_reachable_locations { 
        { "filter", { id = unit.id } },
        { "filter_location", {
            { "filter_adjacent_location", { 
                { "filter", 
                    { { "filter_side",
                        { { "enemy_of", { side = unit.side } } }
                    } }
                } 
            } },
            { "not", { 
                { "filter", { { "not", { id = unit.id } } } }
            } }
        } },
        moves = moves or "current",
        variable = "tmp_locs"
    }
    local attack_loc = H.get_variable_array("tmp_locs")
    W.clear_variable { name = "tmp_locs" }
    --print("reachable attack locs:",unit.id,#attack_loc)

    -- Variable to store attacks
    local attacks = {}
    -- Current position of unit
    local x1, y1 = unit.x, unit.y

    -- Go through all attack locations
    for i,p in pairs(attack_loc) do

        -- Put unit at this position
        wesnoth.put_unit(p.x, p.y, unit)
        --print(i,' attack pos:',p.x,p.y)

        -- As there might be several attackable units from a position, need to find all those
        local targets = wesnoth.get_units {
            { "filter_side",
                { { "enemy_of", { side = unit.side } } }
            },
            { "filter_location", 
                { { "filter_adjacent_location", { x = p.x, y = p.y } } }
            }
        }
        --print('  number targets: ',#targets)

        for j,t in pairs(targets) do
            local att_stats, def_stats = wesnoth.simulate_combat(unit, t)

            table.insert(attacks, {
                x = p.x, y = p.y,
                attacker_id = unit.id,
                defender_id = t.id,
                att_stats = att_stats,
                def_stats = def_stats
            } )
        end
    end

    -- Put unit back to its location
    wesnoth.put_unit(x1, y1, unit)

    return attacks
end

function ai_helper.get_attacks(units, moves)
    -- Wrapper function for ai_helper.get_attacks_unit
    -- Returns the same sort of table, but for the attacks of several units
    -- This is somewhat slow, but will hopefully replaced soon by built-in AI function

    local attacks = {}
    for k,u in pairs(units) do
        local attacks_unit = ai_helper.get_attacks_unit(u, moves)

        if attacks_unit[1] then
            for i,a in ipairs(attacks_unit) do
                table.insert(attacks, a)
            end
        end
    end

    return attacks
end

function ai_helper.get_reachable_attack_map(unit, cfg)
    -- Get all hexes that a unit can attack
    -- Return value is a location set, where the value is 1 for each hex that can be attacked
    -- cfg: parameters to wesnoth.find_reach, such as {additional_turns = 1}
    -- additional, {moves = 'max'} can be set inside cfg, which sets unit MP to max_moves before calculation

    local old_moves = unit.moves
    if cfg then
        if (cfg.moves == 'max') then
            unit.moves = unit.max_moves
        end
    end

    local reach = LS.create()
    local initial_reach = wesnoth.find_reach(unit, cfg)

    for i,loc in ipairs(initial_reach) do
        reach:insert(loc[1], loc[2], 1)
        for x, y in H.adjacent_tiles(loc[1], loc[2]) do
            reach:insert(x, y, 1)
        end
    end

    -- Reset unit moves (can be done whether it was changed or not)
    unit.moves = old_moves

    return reach
end

function ai_helper.attack_map(units, cfg)
    -- Attack map: number of units which can attack each hex
    -- Return value is a location set, where the value is the 
    --   number of units that can attack a hex
    -- cfg: parameters to wesnoth.find_reach, such as {additional_turns = 1}
    -- additional, {moves = 'max'} can be set inside cfg, which sets unit MP to max_moves before calculation

    local AM = LS.create()  -- attack map

    for i,u in ipairs(units) do
        local reach = ai_helper.get_reachable_attack_map(u, cfg)
        AM:union_merge(reach, function(x, y, v1, v2) 
            return (v1 or 0) + v2
        end)
    end
    --ai_helper.put_labels(AM)
    --W.message {speaker="narrator", message="Attack map" }

    return AM
end

return ai_helper
