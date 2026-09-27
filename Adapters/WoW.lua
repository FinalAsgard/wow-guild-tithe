local _, addon = ...

local Compatibility = {}
addon.Compatibility = Compatibility

local Client = {}
Client.__index = Client

local function callMethod(object, methodName, ...)
    if object == nil then
        return false
    end

    local method = object[methodName]
    if type(method) ~= "function" then
        return false
    end

    local ok = pcall(method, object, ...)
    return ok
end

function Compatibility.Create(environment)
    return setmetatable({ environment = environment or _G }, Client)
end

function Client:CreateEventFrame()
    local createFrame = self.environment.CreateFrame
    if type(createFrame) ~= "function" then
        return nil
    end

    local ok, frame = pcall(createFrame, "Frame")
    if not ok then
        return nil
    end

    return frame
end

function Client:RegisterEvent(frame, eventName)
    return callMethod(frame, "RegisterEvent", eventName)
end

function Client:SetEventHandler(frame, handler)
    return callMethod(frame, "SetScript", "OnEvent", handler)
end

function Client:RegisterSlashCommand(command, key, handler)
    local slashCommands = self.environment.SlashCmdList
    if type(slashCommands) ~= "table" then
        return false
    end

    self.environment["SLASH_" .. key .. "1"] = command
    slashCommands[key] = handler
    return true
end

function Client:Print(message)
    local chatFrame = self.environment.DEFAULT_CHAT_FRAME
    if callMethod(chatFrame, "AddMessage", message) then
        return true
    end

    local printMessage = self.environment.print
    if type(printMessage) == "function" then
        local ok = pcall(printMessage, message)
        return ok
    end

    return false
end
