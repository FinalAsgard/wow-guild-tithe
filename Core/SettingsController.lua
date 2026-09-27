local _, addon = ...

local SettingsController = {}
addon.SettingsController = SettingsController

local Controller = {}
Controller.__index = Controller

local function currentPercentage(state)
    local character = state:GetCurrentCharacter()
    if type(character) ~= "table" then
        return nil
    end

    return character.percentage
end

function SettingsController.Create(client, state)
    return setmetatable({
        client = client,
        state = state,
    }, Controller)
end

function Controller:Register()
    if self.category ~= nil or currentPercentage(self.state) == nil then
        return self.category ~= nil
    end

    local category = self.client:RegisterPercentageSettings({
        categoryName = "Guild Tithe",
        variable = "GuildTithe_Percentage",
        label = "Tithe percentage",
        tooltip = "Percentage of eligible income reserved for your guild tithe.",
        defaultValue = 10,
        minimum = 0,
        maximum = 100,
        step = 1,
        getValue = function()
            return currentPercentage(self.state)
        end,
        setValue = function(value)
            return self.state:SetPercentage(value)
        end,
    })

    if category == nil then
        return false
    end

    self.category = category
    return true
end

function Controller:Open()
    if self.category ~= nil and self.client:OpenSettingsCategory(self.category) then
        return true
    end

    self.client:Print("Guild Tithe: settings are unavailable on this client. Use /gt help.")
    return false
end

function Controller:RegisterCommands(router)
    local registered = router:Register("settings", "open settings", function()
        self:Open()
    end)

    if registered and type(router.SetDefault) == "function" then
        router:SetDefault("settings")
    end

    return registered
end
