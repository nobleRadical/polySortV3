local completion = require "cc.completion"
if itemTable == nil then itemTable = {} end -- if somehow the itemTable isn't nil here, why replace it?
peripheral.find("modem", rednet.open)
host_protocol = settings.get("host_protocol") or "polySorter"
hostComputer = rednet.lookup(host_protocol, "host")
assert(hostComputer, "Host computer not found. Try changing the host_protocol setting if the host is set up.")

local x, y = term.getCursorPos()
local fill_the_screen = y - 2

local function contains(...)
    local ret = {}
    for _,k in ipairs({...}) do ret[k] = true end
    return ret
end

function updateItemTable()
    rednet.send(hostComputer, {type="getTable"}, host_protocol)
    local id, message = rednet.receive()
    if message.code then
        itemTable = message.result
    end
end


function cli() -- displays the user interface cli, allowing commands such as `list`, `request`, `index`, and `help`.
    term.setTextColor(colors.yellow)
    print("polySort v3")
    print("Starting interactive CLI. type 'help' for help.")
    term.setTextColor(colors.white)
    commands = {"query", "list", "ls", "request", "move", "update", "help", "exit"}
    commandHistory = {}
    quickReference = {} --needs to be accessible by runfunction
    updateItemTable()
    while true do
        term.blit("> ", "30", "ff") -- blue prompt
        local input = read(nil, commandHistory, 
        function(text) 
            if string.find(text, "help %w") then
                return completion.choice(text, {"help query", "help list", "help ls", "help request", "help move", "help update", "help help", "help exit"})
            elseif text ~= "" then 
                return completion.choice(text, commands) 
            end 
        end)
        table.insert(commandHistory, input)
        local spaced_args_dirty = {}
        local command_args = {}
        --split input into command and args
        --get space-delimited args (and some fragmented quote-delimited args)
        for substring in string.gmatch(input, "%S+") do
            table.insert(spaced_args_dirty, substring)
        end
        --remove quote-delimited args from space-delimited args; add to command_args
        for index, arg in pairs(spaced_args_dirty) do
            if not string.find(arg, "\"") then
                table.insert(command_args, arg)
            end
        end
        --get quote-delimited args
        for substring in string.gmatch(input, "%b\"\"") do
            substring = string.gsub(substring, "\"", "") --remove quotes
            table.insert(command_args, substring)
        end

        --quickreference substitution
        for index, command_arg in ipairs(command_args) do
            local _, _, num = string.find(command_arg, "%%(%d+)")
            num = tonumber(num)
            if num then
                command_args[index] = quickReference[num]
            end
        end

        updateItemTable()
        --do command
        local code, result = pcall(runfunction, command_args)
        if not code then
            printError(result)
        end
        if result == "EXIT" then
            break
        end
    end

end

function show_results(results, verbose)
    local list = ""
    for index, namehash in ipairs(results) do
        local data = itemTable[namehash]
        list = list .."%"..tostring(index).."  "..data.displayName.."  "..tostring(data.totalCount)..((verbose == true and "  "..string.gsub(namehash,"(|%w?%w?%w?).*","%1")) or "")
        if data.enchantments then
            for _, ench in ipairs(data.enchantments) do
                list = list .."  ".. ench.displayName
            end
        end
        list = list .. "\n" --print a colored line here instead; handle key events
    end
    textutils.pagedPrint(list, fill_the_screen/2)
end

function runfunction(command)
    if not command[1] then return 0 end
    command[1] = string.lower(command[1])
    if contains("query", "list", "ls", "q")[command[1]] then
        --query based on filters <name> <display name> <enchantments>
        --save results as numbered variables for request or move. (%1, %2, %n)
        local verbose = false
        if string.lower(command[2] or "") == "--verbose" or string.lower(command[2] or "") == "-v" then
            verbose = true
            table.remove(command, 2)
        end
        local results = {}
        for namehash, data in pairs(itemTable) do
            if command[2] == nil then
                table.insert(results, namehash)
            else
            --check for display name, lore, enchantments
                for i=2, #command do
                    local search_filter = string.lower(command[i])
                    if string.find(namehash, search_filter) then
                        table.insert(results, namehash)
                    elseif string.find(string.lower(data.displayName), search_filter) then
                        table.insert(results, namehash)
                    else
                        for _, ench in ipairs(data.enchantments or {}) do
                            if string.find(string.lower(ench.displayName), search_filter) then
                                table.insert(results, namehash)
                                break
                            end
                        end
                    end
                end
            end
        end
        show_results(results, verbose)
        if quickReference then
            quickReference = {}--clear quickReference
            for _, result in ipairs(results) do table.insert(quickReference, result) end --copy results to quickReference
        end
    elseif contains("request", "r")[command[1]] then
        --item <name> (or %1) <count> gets sent to the output_chest.
        local message = {
            type="move",
            chest="OUTPUT_CHEST",
            count=nil,
            name=nil
        }
        local itemName = command[2]
        if not itemName then
            printError("Usage: request <name> <count>")
            return 1
        end
        --correction from item_name to minecraft:item_name
        if not (string.find(itemName, ":")) then --if no colon
            itemName = "minecraft:" .. itemName
        end

        for key, value in pairs(itemTable) do
            if string.find(key, "^"..itemName) then --key starts with itemName 
                message.name = key
            end
        end
        if message.name == nil then
            printError("No item with that name found.")
            return
        end
        local itemCount = tonumber(command[3])
        if itemCount == nil then
            print("No item count supplied, defaulting to 1 stack.")
            itemCount = itemTable[message.name].maxCount
        end
        message.count = itemCount
        rednet.send(hostComputer, message, host_protocol)
        print("Waiting for response...")
        getresponse(10)
    elseif contains("move", "m")[command[1]] then
        --item <chest> <name> (or %1) <count> gets sent to a chest.
        local message = {
            type="move",
            chest=command[2],
            count=nil,
            name=nil
        }
        if message.chest == nil then
            printError("Usage: <chest> <name> <count>")
            return
        end
        local itemName = command[3]
        --correction from item_name to minecraft:item_name
        if not (string.find(itemName, ":")) then --if no colon
            itemName = "minecraft:" .. itemName
        end

        for key, value in pairs(itemTable) do
            if string.find(key, "^"..itemName) then --key starts with itemName 
                message.name = key
            end
        end
        if message.name == nil then
            printError("No item with that name found.")
            return
        end
        local itemCount = tonumber(command[4])
        if itemCount == nil then
            print("No item count supplied, defaulting to 1 stack.")
            itemCount = itemTable[message.name].maxCount
        end
        message.count = itemCount
        rednet.send(hostComputer, message, host_protocol)
        print("Waiting for response...")
        getresponse(10)
    elseif command[1] == "update" then
        print("Updating item table.")
        updateItemTable()
    elseif command[1] == "exit" then
        term.setTextColor(colors.yellow)
        print("Bye")
        term.setTextColor(colors.white)
        return "EXIT"
    elseif command[1] == "help" then
        term.setTextColor(colors.green)
        if command[2] == nil then
            textutils.pagedPrint(
[[Commands are query, request, move, update, and help (this one).
arguments are delimited with spaces or quotes.
Usages below.
->request <name> <count> 
    Sends items to the output chest. 
->move <chest> <name> <count>
    sends items to a chest.
->query <search filter> 
    Searches for items.
->list
->ls
    Aliases for query.
->update
    Debugging command.
->help [command]
    displays help text.
->exit
    exits the program.]],
            fill_the_screen)
            term.setTextColor(colors.white)
        elseif command[2] == "request" then
            term.setTextColor(colors.yellow)
            print("request <name> <count>")
            term.setTextColor(colors.green)
            print(
[[Sends <count> of <item> to the output chest. 
Defaults to 1 stack of the item.
Can use %# format instead of item name. 
For example, typing %1 instead of the item name
will use the first item from the last query.]]
            )
            term.setTextColor(colors.white)
        elseif command[2] == "move" then
            term.setTextColor(colors.yellow)
            print("move <chest> <name> <count>")
            term.setTextColor(colors.green)
            print(
[[Sends <count> of <item> to <chest>. 
Defaults to 1 stack of the item.
Can use %# format instead of item name. 
For example, typing %1 instead of the item name
will use the first item from the last query.]]
            )
            term.setTextColor(colors.white)
        elseif command[2] == "query" or command[2] == "list" or command[2] == "ls" then
            term.setTextColor(colors.yellow)
            print("query [-v|--verbose] <search filters> ...")
            term.setTextColor(colors.green)
            print(
[[Searches the system for items with
the name, display name or enchantment(s)
listed in the search filters.
Specifically, it returns items whose
properties contain ANY of the
search filters.
Saves the returned list into a
"quick reference" index that
can be accessed later.]]
            )
            term.setTextColor(colors.white)
            print("Press space to continue")
            repeat
                local _, key = os.pullEvent("key")
            until key == keys.space
            term.setTextColor(colors.green)
            print(
[[Displays search results in a list
including display name, count,
and enchantment. use optional
-v|--verbose to also display
internal name and first 3
digits of nbt hash.]]
            )
            term.setTextColor(colors.white)
        elseif command[2] == "update" then
            term.setTextColor(colors.yellow)
            print("update")
            term.setTextColor(colors.green)
            print(
[[Debugging command.
updates the item table.
End users shouldn't have to run this.]]
            )
            term.setTextColor(colors.white)
        elseif command[2] == "help" then
            term.setTextColor(colors.yellow)
            print("help [command]")
            term.setTextColor(colors.green)
            print(
[[Displays general help text, or
help text relevant to a particular command.]]
            )
            term.setTextColor(colors.white)
        else
            term.setTextColor(colors.yellow)
            print("No help text for that command.")
            term.setTextColor(colors.white)
        end
    else
        printError("Invalid command. type 'help' for help.")
    end
end

--wait for a response, then print.
function getresponse(timeout)
    repeat
        local id, message, protocol = rednet.receive(host_protocol, timeout)
        if id == hostComputer then
            if message.code then
                print(message.result .. " Items transferred.")
            else
                printError("Error: " .. message.reason)
            end
        end
        if id == nil then
            printError("Response timed out.")
        end
    until (id == hostComputer) or (id == nil)
end

if arg[1] == nil then
    cli()
else
    updateItemTable()
    runfunction(arg)
end

