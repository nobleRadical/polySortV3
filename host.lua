if itemTable == nil then itemTable = {} end -- if somehow the itemTable isn't nil here, why replace it?
peripheral.find("modem", function(name, wrap) rednet.open(name) print("opened modem " .. name) end) -- open all modems attached to computer
settings.load("disk/.settings")
settings.load(".settings.polySorter")

local host_protocol = settings.get("host_protocol") or "polySorter" -- the client will use lookup to find this computer, so this protocol should be unique.
local input_chests = settings.get("input_chests") -- the chests that are dynamically sorted. REQUIRED.
local output_chest = settings.get("output_chest") -- the chest that "request" sends items to.
local control_chests = settings.get("control_chests") or {} --the chests that are exluded from the sorting system.
                                                            --could be used for more output chests.
local push_sorting = settings.get("push_sorting") or "all" 
-- 3 possible values: nil (does not push-sort), chest (push-sorts only to chests that already have a matching item), and all (default, pushes to any available chest.)

rednet.host(host_protocol, "host")

if not input_chests then -- required setting for the program to work.
    printError("Input chest not specified.")
    local f = fs.open(".settings.polySorter", "w")
    f.write(
        [[{
    -- this protocol should be unique, 
    --  as to not be confused with 
    --  other polysorters on the server.
    host_protocol = "polySorter",
    -- REQUIRED. 
    --  Set which network-connected chests 
    --  should be marked as "input chests", 
    --  ones that are constantly emptied 
    --  into the system.
    input_chests = {
        "minecraft:barrel_0",
    },
    -- required for the "request" command to work. 
    --  which chest, by default, 
    --  will receive items that are requested.
    output_chest = "minecraft:chest_0",
    -- fully optional. 
    --  These chests will not be 
    --  incorporated into the system. 
    --  Outside of these chests, 
    --  the input chests, 
    --  and the output chest, 
    --  all others will be used as storage chests.
    control_chests = {
        "minecraft:example_chest"
    },
    -- three possible values: nil, "chest", and "all". 
    -- nil: only polymorphic sorting is allowed, 
    --  if there is not a free itemstack then 
    --  the item will not be sorted
    -- "chest": push-sorting is allowed intra-chest; 
    --  if there is space in the chest 
    --  containing an item, 
    --  it will be pushed there to a new stack.
    -- "all": push-sorting is allowed; 
    --  if there is free space anywhere in the system, 
    --  items will be pushed to the next available chest.
    push_sorting = "all",
    --name of optional monitor peripheral.
    monitor_name = "",
    -- this is an example configuration. 
    --  Edit to your liking.
}   
        ]]
    )
    f.close()
    error("example config file generated: .settings.polySorter")
end

--Display config
do
    print("Hosting polySorter on protocol " .. host_protocol)
    term.write("Input chests: ") for _, v in pairs(input_chests) do term.write(v) end print("") --newline
    print("Output chest: " .. output_chest)
    term.write("Control chests: ") for _, v in pairs(control_chests) do term.write(v) end print("") -- newline
    if push_sorting == "all" then
        print("Push sorting: ENABLED")
    elseif push_sorting == "chest" then
        print("Push sorting: ENABLED (intrachest)")
    else
        print("Push sorting: DISABLED")
    end
    os.startTimer(10)
    print("Press any key to Continue...")
    repeat
        local e = os.pullEvent()
    until e == "key" or e == "timer" --wait 10 seconds or keypress
    term.clear()
    -- monitor support
    mon = peripheral.wrap(settings.get("monitor_name") or "")
    if mon then term.redirect(mon) end
    term.clear()
    term.setCursorPos(1,5)
    term.write("Hosting protocol: " .. host_protocol)
    term.setCursorPos(1,1)
end




--utility functions
local function contains(...)
    local ret = {}
    for _,k in ipairs({...}) do ret[k] = true end
    return ret
 end

function pause() -- allows this program to pass execution back and forth while listening for events.
    os.startTimer(0.1)
    local e = os.pullEvent()
    return e
end

function getListSize(list) --come on lua.
    local size = 0
    for k, v in pairs(list) do
        size = size + 1
    end
    return size
end

function sortWrite(message, line)
    if not line then line = 0 end
    term.setCursorPos(1,1 + line)
    term.clearLine()
    if message == "" then
        term.clearLine()
    else
        term.write("[SORT] " .. message)
    end
end

function indexWrite(message, line)
    if not line then line = 0 end
    term.setCursorPos(1,2 + line)
    term.clearLine()
    if message == "" then
        term.clearLine()
    else
        term.write("[INDEX] " .. message)
    end
end

function rednetWrite(message, line)
    if not line then line = 0 end
    term.setCursorPos(1,3 + line)
    term.clearLine()
    if message == "" then
        term.clearLine()
    else
        term.write("[REDNET] " .. message)
    end
end


--find Inventories, list of wraps
local Inventories = { peripheral.find("inventory",  
    function(name, wrap) --this function excludes the input and output chests from the table
        if contains(table.unpack(input_chests))[name] or 
        name == output_chest or 
        contains(table.unpack(control_chests))[name] or 
        name == "back" or name == "front" or name == "left" or name == "right" or name == "top" or name == "bottom" 
        then
            return false    
        else
            return true
        end
    end
        ) }
--convert Inventories to a list of names
for k, v in pairs(Inventories) do
    Inventories[k] = peripheral.getName(v)
end


function sort(once) --Infinite loop, sorting items from all connected input chests.
    local cycles = 0
    repeat
        for _, fromChest in pairs(input_chests) do
            local fc = peripheral.wrap(fromChest)
            assert(fc, "Chest(s) removed. Restart program.")
            if getListSize(fc.list()) == 0 then sortWrite("Status: Input chest(s) empty. " .. tostring(cycles) .. " cycles completed.") end
            for fromSlot, fromItem in pairs(fc.list()) do
                sortWrite("Status: Poly-Sorting " .. fromItem.name .. " from chest " .. fromChest .. ". " .. tostring(cycles) .. " cycles completed.")
                pause()
                local tableSpot = itemTable[fromItem.name .. "|" .. (fromItem.nbt or "")] or false
                if not tableSpot then
                    --create item entry
                    itemTable[fromItem.name .. "|" .. (fromItem.nbt or "")] = fc.getItemDetail(fromSlot)
                    tableSpot = itemTable[fromItem.name .. "|" .. (fromItem.nbt or "")]
                    tableSpot.totalCount = tableSpot.count
                    tableSpot.count = nil
                    tableSpot.instances = {}
                end
                for index, instance in pairs(tableSpot.instances) do
                    if fromItem.count <= 0 then break end
                    local spaceInSlot = tableSpot.maxCount - instance.count
                    if spaceInSlot > 0 then
                        local itemsTransferred = fc.pushItems(instance.chest, fromSlot, spaceInSlot, instance.slot)
                        fromItem.count = fromItem.count - itemsTransferred
                        instance.count = instance.count + itemsTransferred
                        tableSpot.totalCount = tableSpot.totalCount + itemsTransferred
                    end
                end
                sortWrite("", 2)
                if fromItem.count > 0 then
                    --find an empty spot by looping over all of the storage chests, prioritizing the chests that already have the item first.
                    if push_sorting then
                        sortWrite("Status: Push-Sorting " .. fromItem.name .. " from chest " .. fromChest .. ". " .. tostring(cycles) .. " cycles completed.")
                        local chests_to_loop = {} --this table will have the chests with the item in it first.
                        for _, instance in pairs(tableSpot.instances) do --add the chests with the item in them.
                            table.insert(chests_to_loop, instance.chest)
                        end
                        if push_sorting == "all" then --add all chests.
                            for _, chest in pairs(Inventories) do
                                table.insert(chests_to_loop, chest)
                            end
                        end
                        for _, chest in pairs(chests_to_loop) do
                            if fromItem.count <= 0 then break end
                            local c = peripheral.wrap(chest)
                            local itemList = c.list()
                            for slot=1,c.size() do --loop over all of the slots, including empty ones.
                                if fromItem.count <= 0 then break end
                                if not itemList[slot] then
                                    local itemsTransferred = fc.pushItems(chest, fromSlot, nil, slot)
                                    fromItem.count = fromItem.count - itemsTransferred
                                    tableSpot.totalCount = tableSpot.totalCount + itemsTransferred
                                    table.insert(tableSpot.instances, {slot=slot, chest=chest, count=itemsTransferred})
                                end
                            end
                        end
                    end
                end
                if fromItem.count > 0 then
                    --if we fail (and there is no space), then we error (NO_SPACE)
                    rednet.broadcast("NO_SPACE", host_protocol)
                    sortWrite("Status: No space. Restart system after adding chests.")
                else
                    cycles = cycles + 1
                    sortWrite("Status: Sort complete. " .. tostring(cycles) .. " cycles completed.")
                end
            end
        end
    until once
end


--Infinite Loop. indexes the inventories, adding each slot's status to the itemTable. 
--[[
    data_structure = {
        internal_name|nbt_hash = {
            instances = {
                {chest=n, slot=n, count=n}, 
                {chest=n, slot=n, count=n}
            }, 
            name = ...,
            totalCount = ...,
            displayName = ...,
            lore = ...,
            nbt = ...,
            maxCount = ...,
            etc. (item details)
            
        }
    }

--]]
function index(once)
    local cycles = 0
    repeat
        indexWrite("Status: Indexing... " .. tostring(cycles) .. " cycles completed.")
        for _, chest in pairs(Inventories) do
            local c = peripheral.wrap(chest)
            assert(c, "Chest(s) removed. Restart program.")
            for slot, item in pairs(c.list()) do
                pause()
                local tableSpot = itemTable[item.name .. "|" .. (item.nbt or "")]
                if tableSpot then
                    local foundInstance = false
                    local totalCount = 0
                    for _, instance in pairs(tableSpot.instances) do
                        if slot == instance.slot and chest == instance.chest then
                            instance.count = item.count
                            foundInstance = true
                        end
                        totalCount = totalCount + instance.count
                    end
                    
                    if not foundInstance then
                        table.insert(tableSpot.instances, {slot=slot, chest=chest, count=item.count})
                        totalCount = totalCount + item.count
                    end
                    tableSpot.totalCount = totalCount
                else
                    --create item entry
                    tableSpot = c.getItemDetail(slot)
                    tableSpot.totalCount = tableSpot.count
                    tableSpot.count = nil
                    tableSpot.instances = {
                        {slot=slot, chest=chest, count=item.count}
                    }
                    itemTable[item.name .. "|" .. (item.nbt or "")] = tableSpot
                end
            end
            --cleanup of improperly removed items.
            for namehash, data in pairs(itemTable) do
                for index, instance in pairs(data.instances) do
                    local itemData = peripheral.call(instance.chest, "list")[instance.slot]
                    if not itemData then
                        table.remove(data.instances, index)
                    elseif not (itemData.name == data.name and itemData.nbt == data.nbt) then
                        table.remove(data.instances, index)
                    end
                end
                if getListSize(data.instances) == 0 then ---remove items with no instances
                    itemTable[namehash] = nil
                end
            end
        end
    cycles = cycles + 1
    indexWrite("Status: Index complete. " .. tostring(cycles) .. " cycles completed.")
    until once
end

--returns itemsMoved (number)
--moves [limit] number of [name] item to [toChest] or the output_chest.
function move(name, toChest, limit)
    if limit == (0/0) or tonumber(limit) ~= limit or limit == (1/0) then
        return {code=false, reason="Malformed request"}
    end
    if toChest == "OUTPUT_CHEST" then
        if output_chest then
            toChest = output_chest
        else
            return {code=false, reason="No output chest"}
        end
    end
    local tc = peripheral.wrap(toChest)
    if tc then
        local itemsLeft = limit --counter variable for how many items still need to be moved (or nil)
        if type(itemTable[name]) ~= "table" then return {code=false, reason="No item with name " .. name} end
        for index, instance in pairs(itemTable[name].instances) do
            local items_moved = peripheral.call(instance.chest, "pushItems", toChest, instance.slot, itemsLeft)
            itemsLeft = itemsLeft - items_moved
            instance.count = instance.count - items_moved
            itemTable[name].totalCount = itemTable[name].totalCount - items_moved
            if instance.count == 0 then table.remove(itemTable[name].instances, index) end
            if itemsLeft <= 0 then break end
        end
        if (limit - itemsLeft) == 0 then
            if #tc.list() >= tc.size() then --chest is full
                return {code=false, reason="Destination chest is full"}
            end
            return {code=false, reason="Unknown error"}
        end
        return {code=true, result=(limit - itemsLeft)} --total items moved
    else
        return {code=false, reason="No chest with name " .. toChest}
    end
end

--listens for a rednet signal getTable, then sends the current itemTable as a serialized message.
--Listens for a rednet signal move, then moves the requested item into the specified output chest.
--[[data_structure = {
    type="getTable or move"
    chest="chest name or OUTPUT_CHEST"
    name="item_name|nbt_hash"
    count=#
}
]]--
function rednet_handler() -- Infinite Loop.  
    rednetWrite("Waiting for requests...", 0)
    while true do
        local id, message = rednet.receive(host_protocol)
        rednetWrite("Received " .. tostring(message.type or "malformed") .. " request.", 0)
        rednetWrite("", 1)
        if message.type == "getTable" then
            rednetWrite("Sending Item Table...", 1)
            rednet.send(id, {code=true, result=itemTable}, host_protocol)
            rednetWrite("Sending Item Table... Sent.", 1)
        elseif message.type == "move" then
            rednetWrite("Moving " .. tostring(message.count) .." ".. tostring(string.gsub(message.name, "|.*", "")) .. " to " .. tostring(message.chest) .. "...", 1) 
            local result = move(message.name, message.chest, message.count)
            rednet.send(id, result, host_protocol) --send back the total items moved
            if result.code then
                rednetWrite("Moved " .. result.result .." ".. tostring(string.gsub(message.name, "|.*", "")) .. " to " .. tostring(message.chest), 1)
            else
                rednetWrite("Could not move " .. tostring(string.gsub(message.name, "|.*", "")) .. " to " .. tostring(message.chest) .. ". Reason: " .. result.reason, 1)
            end
        end
    end
end
parallel.waitForAll(sort, index, rednet_handler)