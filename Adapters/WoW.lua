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

local function callFunction(callback, ...)
    if type(callback) ~= "function" then
        return false
    end

    return pcall(callback, ...)
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

function Client:GetCurrentCharacterIdentity()
    local ok, name, unitRealm = callFunction(self.environment.UnitName, "player")
    if not ok or type(name) ~= "string" or name == "" then
        return nil
    end

    local realm = unitRealm
    if type(realm) ~= "string" or realm == "" then
        local realmOk, currentRealm = callFunction(self.environment.GetRealmName)
        if realmOk then
            realm = currentRealm
        end
    end

    if type(realm) ~= "string" or realm == "" then
        return nil
    end

    local stableId
    local guidOk, guid = callFunction(self.environment.UnitGUID, "player")
    if guidOk and type(guid) == "string" and guid ~= "" then
        stableId = guid
    end

    return {
        name = name,
        realm = realm,
        stableId = stableId,
    }
end

function Client:GetAccountDatabase()
    return self.environment.GuildTitheDB
end

function Client:SetAccountDatabase(database)
    self.environment.GuildTitheDB = database
    return true
end
