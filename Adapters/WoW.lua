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
    return setmetatable({
        databaseName = addon.Identity.databaseName,
        environment = environment or _G,
    }, Client)
end

function Client:GetClientProfile()
    if self.clientProfile == nil then
        self.clientProfile = addon.ClientProfile.Detect(
            self.environment,
            addon.Identity.addonName
        )
    end

    return self.clientProfile
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

function Client:IsLoggedIn()
    local ok, loggedIn = callFunction(self.environment.IsLoggedIn)
    return ok and loggedIn ~= nil and loggedIn ~= false
end

local function withoutLeadingSlash(command)
    return string.gsub(command, "^/", "")
end

function Client:RegisterSlashCommand(command, alias, key, handler)
    if type(command) ~= "string"
        or type(alias) ~= "string"
        or type(key) ~= "string"
        or type(handler) ~= "function"
    then
        return false
    end

    local registerNewSlashCommand = self.environment.RegisterNewSlashCommand
    if type(registerNewSlashCommand) == "function" then
        local ok = pcall(
            registerNewSlashCommand,
            handler,
            withoutLeadingSlash(command),
            withoutLeadingSlash(alias)
        )
        if ok then
            return true
        end
    end

    local slashCommands = self.environment.SlashCmdList
    if type(slashCommands) ~= "table" then
        return false
    end

    self.environment["SLASH_" .. key .. "1"] = command
    self.environment["SLASH_" .. key .. "2"] = alias
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

    -- Both clients report a placeholder name until the player is ready.
    local placeholder = self.environment.UNKNOWNOBJECT
    if name == (type(placeholder) == "string" and placeholder or "Unknown") then
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

-- Carried money in copper, or nil when the client cannot report it.
function Client:GetCarriedMoney()
    local ok, copper = callFunction(self.environment.GetMoney)
    if not ok or type(copper) ~= "number" or copper < 0 or copper ~= math.floor(copper) then
        return nil
    end

    return copper
end

-- true/false for guild membership, or nil when the client cannot report it.
function Client:IsInGuild()
    local ok, inGuild = callFunction(self.environment.IsInGuild)
    if not ok then
        return nil
    end

    return inGuild ~= nil and inGuild ~= false
end

-- Calls onChange() whenever the client reports that carried money changed.
-- Client event names stay here so Core modules only see the normalized call.
function Client:ObserveMoneyChanges(onChange)
    if type(onChange) ~= "function" or type(self.environment.GetMoney) ~= "function" then
        return false
    end

    local frame = self:CreateEventFrame()
    if frame == nil
        or not self:SetEventHandler(frame, function()
            onChange()
        end)
        or not self:RegisterEvent(frame, "PLAYER_MONEY")
    then
        return false
    end

    self.moneyFrame = frame
    return true
end

-- Seconds from the client's monotonic clock, or nil when unavailable.
function Client:Now()
    local ok, now = callFunction(self.environment.GetTime)
    if not ok or type(now) ~= "number" then
        return nil
    end

    return now
end

-- Runs callback once after `seconds`. Returns false when the client has no
-- timer, so callers can act immediately instead.
function Client:After(seconds, callback)
    local timers = self.environment.C_Timer
    if type(timers) ~= "table" or type(timers.After) ~= "function" or type(callback) ~= "function" then
        return false
    end

    local ok = pcall(timers.After, seconds, callback)
    return ok
end

-- Client events that describe where the next money change came from, mapped
-- to normalized source context. "open"/"close" bracket an interaction;
-- "note" is a single corroborating message.
local CONTEXT_EVENTS = {
    CHAT_MSG_MONEY = { source = "loot", action = "note" },
    LOOT_CLOSED = { source = "loot", action = "close" },
    LOOT_OPENED = { source = "loot", action = "open" },
}

-- Calls onContext(source, action) for each recognized context event.
-- Payloads are not trusted: only the event name is used.
function Client:ObserveIncomeContext(onContext)
    if type(onContext) ~= "function" then
        return false
    end

    local frame = self:CreateEventFrame()
    if frame == nil
        or not self:SetEventHandler(frame, function(_, eventName)
            local context = CONTEXT_EVENTS[eventName]
            if context ~= nil then
                onContext(context.source, context.action)
            end
        end)
    then
        return false
    end

    local registered = false
    local eventName
    for eventName in pairs(CONTEXT_EVENTS) do
        -- An event this client lacks is skipped; the others still work.
        registered = self:RegisterEvent(frame, eventName) or registered
    end

    self.contextFrame = frame
    return registered
end

function Client:GetAccountDatabase()
    return self.environment[self.databaseName]
end

function Client:SetAccountDatabase(database)
    self.environment[self.databaseName] = database
    return true
end

local function validBinding(options)
    return type(options) == "table"
        and type(options.getValue) == "function"
        and type(options.setValue) == "function"
end

function Client:RegisterSettingsCategory(options)
    local settings = self.environment.Settings
    local createSectionHeader = self.environment.CreateSettingsListSectionHeaderInitializer
    if type(options) ~= "table"
        or not validBinding(options.percentage)
        or type(options.checkboxSections) ~= "table"
        or type(options.balanceText) ~= "string"
        or type(createSectionHeader) ~= "function"
        or type(settings) ~= "table"
        or type(settings.RegisterVerticalLayoutCategory) ~= "function"
        or type(settings.RegisterProxySetting) ~= "function"
        or type(settings.CreateSliderOptions) ~= "function"
        or type(settings.CreateSlider) ~= "function"
        or type(settings.CreateCheckbox) ~= "function"
        or type(settings.RegisterAddOnCategory) ~= "function"
        or type(settings.VarType) ~= "table"
        or settings.VarType.Number == nil
        or settings.VarType.Boolean == nil
    then
        return nil
    end

    local sectionIndex, checkboxIndex
    for sectionIndex = 1, #options.checkboxSections do
        local section = options.checkboxSections[sectionIndex]
        if type(section) ~= "table"
            or type(section.heading) ~= "string"
            or section.heading == ""
            or type(section.checkboxes) ~= "table"
        then
            return nil
        end

        for checkboxIndex = 1, #section.checkboxes do
            if not validBinding(section.checkboxes[checkboxIndex]) then
                return nil
            end
        end
    end

    local ok, category, balanceInitializer = pcall(function()
        local percentage = options.percentage
        local registeredCategory, layout = settings.RegisterVerticalLayoutCategory(
            options.categoryName
        )
        if registeredCategory == nil
            or type(layout) ~= "table"
            or type(layout.AddInitializer) ~= "function"
        then
            error("settings category was not created")
        end

        local balanceInitializer = createSectionHeader("Tithe - Current balance: " ..
            options.balanceText)
        if balanceInitializer == nil then
            error("balance display was not created")
        end
        layout:AddInitializer(balanceInitializer)

        local setting = settings.RegisterProxySetting(
            registeredCategory,
            percentage.variable,
            settings.VarType.Number,
            percentage.label,
            percentage.defaultValue,
            percentage.getValue,
            percentage.setValue
        )
        if setting == nil then
            error("percentage setting was not created")
        end

        local sliderOptions = settings.CreateSliderOptions(
            percentage.minimum,
            percentage.maximum,
            percentage.step
        )
        if sliderOptions == nil then
            error("percentage slider options were not created")
        end

        local sliderMixin = self.environment.MinimalSliderWithSteppersMixin
        if type(sliderOptions.SetLabelFormatter) ~= "function"
            or type(sliderMixin) ~= "table"
            or type(sliderMixin.Label) ~= "table"
            or sliderMixin.Label.Right == nil
        then
            error("percentage slider formatter is unavailable")
        end
        sliderOptions:SetLabelFormatter(
            sliderMixin.Label.Right,
            function(value)
                return string.format("%.0f%%", value)
            end
        )

        local slider = settings.CreateSlider(
            registeredCategory,
            setting,
            sliderOptions,
            percentage.tooltip
        )
        if slider == nil then
            error("percentage slider was not created")
        end

        for sectionIndex = 1, #options.checkboxSections do
            local section = options.checkboxSections[sectionIndex]
            local sectionInitializer = createSectionHeader(section.heading)
            if sectionInitializer == nil then
                error("settings section was not created")
            end
            layout:AddInitializer(sectionInitializer)

            for checkboxIndex = 1, #section.checkboxes do
                local checkbox = section.checkboxes[checkboxIndex]
                local checkboxSetting = settings.RegisterProxySetting(
                    registeredCategory,
                    checkbox.variable,
                    settings.VarType.Boolean,
                    checkbox.label,
                    checkbox.defaultValue,
                    checkbox.getValue,
                    checkbox.setValue
                )
                if checkboxSetting == nil then
                    error("checkbox setting was not created")
                end

                local checkboxControl = settings.CreateCheckbox(
                    registeredCategory,
                    checkboxSetting,
                    checkbox.tooltip
                )
                if checkboxControl == nil then
                    error("checkbox control was not created")
                end
            end
        end

        settings.RegisterAddOnCategory(registeredCategory)
        return registeredCategory, balanceInitializer
    end)

    if not ok then
        return nil
    end

    self.balanceInitializers = self.balanceInitializers or {}
    self.balanceInitializers[category] = balanceInitializer
    return category
end

function Client:RefreshSettingsBalance(category, balanceText)
    if type(balanceText) ~= "string"
        or type(self.balanceInitializers) ~= "table"
    then
        return false
    end

    local initializer = self.balanceInitializers[category]
    if type(initializer) ~= "table"
        or type(initializer.GetData) ~= "function"
    then
        return false
    end

    local ok, data = pcall(initializer.GetData, initializer)
    if not ok or type(data) ~= "table" then
        return false
    end

    data.name = "Tithe - Current balance: " .. balanceText
    return true
end

function Client:OpenSettingsCategory(category)
    local settings = self.environment.Settings
    if type(settings) ~= "table"
        or type(settings.OpenToCategory) ~= "function"
        or type(category) ~= "table"
        or type(category.GetID) ~= "function"
    then
        return false
    end

    local idOk, categoryID = pcall(category.GetID, category)
    if not idOk or categoryID == nil then
        return false
    end

    local openOk = pcall(settings.OpenToCategory, categoryID)
    return openOk
end
