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
        or type(options.checkboxes) ~= "table"
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

    local index
    for index = 1, #options.checkboxes do
        if not validBinding(options.checkboxes[index]) then
            return nil
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

        local balanceInitializer = createSectionHeader("Current balance: " ..
            options.balanceText .. " (income tracking not active)")
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

        for index = 1, #options.checkboxes do
            local checkbox = options.checkboxes[index]
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

    data.name = "Current balance: " .. balanceText ..
        " (income tracking not active)"
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
