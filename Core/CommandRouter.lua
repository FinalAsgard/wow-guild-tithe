local _, addon = ...

local CommandRouter = {}
addon.CommandRouter = CommandRouter

local Router = {}
Router.__index = Router

local function normalizeInput(input)
    if type(input) ~= "string" then
        return "", ""
    end

    local command, arguments = input:match("^%s*(%S*)%s*(.-)%s*$")
    return string.lower(command or ""), arguments or ""
end

function CommandRouter.Create(output)
    return setmetatable({
        commands = {},
        commandOrder = {},
        output = type(output) == "function" and output or function() end,
    }, Router)
end

function Router:Register(command, description, handler)
    if type(command) ~= "string" or command == "" or type(handler) ~= "function" then
        return false
    end

    command = string.lower(command)
    if self.commands[command] == nil then
        table.insert(self.commandOrder, command)
    end

    self.commands[command] = {
        description = description or "",
        handler = handler,
    }
    return true
end

function Router:PrintHelp()
    local entries = {}
    local index

    for index = 1, #self.commandOrder do
        local command = self.commandOrder[index]
        local description = self.commands[command].description
        table.insert(entries, "/gt " .. command .. " - " .. description)
    end

    self.output("Guild Tithe: " .. table.concat(entries, "; "))
end

function Router:Execute(input)
    local command, arguments = normalizeInput(input)
    if command == "" then
        command = "help"
    end

    local route = self.commands[command]
    if route == nil then
        self.output("Guild Tithe: unknown command '" .. command .. "'. Use /gt help.")
        return false
    end

    route.handler(arguments)
    return true
end
