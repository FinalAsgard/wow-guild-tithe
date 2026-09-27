local _, addon = ...

local SettingsController = {}
addon.SettingsController = SettingsController

local Controller = {}
Controller.__index = Controller

local SOURCE_SETTINGS = {
    {
        key = "loot",
        variable = "GuildTithe_Source_Loot",
        label = "Loot income",
        tooltip = "Include coin looted from creatures and containers.",
        defaultValue = true,
    },
    {
        key = "quests",
        variable = "GuildTithe_Source_Quests",
        label = "Quest income",
        tooltip = "Include money received from quest rewards.",
        defaultValue = true,
    },
    {
        key = "vendorSales",
        variable = "GuildTithe_Source_VendorSales",
        label = "Vendor sales",
        tooltip = "Include money received from selling items to vendors.",
        defaultValue = true,
    },
    {
        key = "auctions",
        variable = "GuildTithe_Source_Auctions",
        label = "Auction income",
        tooltip = "Include proceeds from auction-house sales.",
        defaultValue = false,
    },
    {
        key = "mailbox",
        variable = "GuildTithe_Source_Mailbox",
        label = "Mailbox income",
        tooltip = "Include non-auction money received through the mailbox.",
        defaultValue = false,
    },
    {
        key = "playerTrades",
        variable = "GuildTithe_Source_PlayerTrades",
        label = "Player trades",
        tooltip = "Include money received through direct player trades.",
        defaultValue = true,
    },
    {
        key = "miscellaneous",
        variable = "GuildTithe_Source_Miscellaneous",
        label = "Miscellaneous/system income",
        tooltip = "Include otherwise unclassified money gains.",
        defaultValue = true,
    },
}

local CHAT_FEEDBACK_SETTING = {
    variable = "GuildTithe_ChatFeedback",
    label = "Routine chat feedback",
    tooltip = "Show routine Guild Tithe activity messages in chat.",
    defaultValue = true,
}

local function currentCharacter(state)
    local character = state:GetCurrentCharacter()
    if type(character) ~= "table" then
        return nil
    end

    return character
end

local function currentPercentage(state)
    local character = currentCharacter(state)
    if character == nil then
        return nil
    end

    return character.percentage
end

local function currentSource(state, source)
    local character = currentCharacter(state)
    if character == nil or type(character.sources) ~= "table" then
        return nil
    end

    return character.sources[source]
end

local function currentChatFeedback(state)
    local character = currentCharacter(state)
    if character == nil then
        return nil
    end

    return character.chatFeedback
end

local function currentBalance(state, formatter)
    local character = currentCharacter(state)
    if character == nil
        or formatter == nil
        or type(formatter.Format) ~= "function"
    then
        return nil
    end

    return formatter.Format(character.outstandingCopper)
end

local function buildCheckboxes(state)
    local checkboxes = {}
    local index

    for index = 1, #SOURCE_SETTINGS do
        local definition = SOURCE_SETTINGS[index]
        local source = definition.key
        table.insert(checkboxes, {
            variable = definition.variable,
            label = definition.label,
            tooltip = definition.tooltip,
            defaultValue = definition.defaultValue,
            getValue = function()
                return currentSource(state, source)
            end,
            setValue = function(value)
                return state:SetSourceEnabled(source, value)
            end,
        })
    end

    table.insert(checkboxes, {
        variable = CHAT_FEEDBACK_SETTING.variable,
        label = CHAT_FEEDBACK_SETTING.label,
        tooltip = CHAT_FEEDBACK_SETTING.tooltip,
        defaultValue = CHAT_FEEDBACK_SETTING.defaultValue,
        getValue = function()
            return currentChatFeedback(state)
        end,
        setValue = function(value)
            return state:SetChatFeedback(value)
        end,
    })

    return checkboxes
end

function SettingsController.Create(client, state, formatter)
    return setmetatable({
        client = client,
        formatter = formatter or addon.MoneyFormatter,
        state = state,
    }, Controller)
end

function Controller:Register()
    local balanceText = currentBalance(self.state, self.formatter)
    if self.category ~= nil
        or currentPercentage(self.state) == nil
        or balanceText == nil
    then
        return self.category ~= nil
    end

    local category = self.client:RegisterSettingsCategory({
        categoryName = "Guild Tithe",
        balanceText = balanceText,
        percentage = {
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
        },
        checkboxes = buildCheckboxes(self.state),
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
