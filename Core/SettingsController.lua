local _, addon = ...

local SettingsController = {}
addon.SettingsController = SettingsController

local Controller = {}
Controller.__index = Controller

local SOURCE_SETTINGS = {
    {
        key = "loot",
        variableSuffix = "Source_Loot",
        label = "Loot income",
        tooltip = "Include coin looted from creatures and containers.",
        defaultValue = true,
    },
    {
        key = "quests",
        variableSuffix = "Source_Quests",
        label = "Quest income",
        tooltip = "Include money received from quest rewards.",
        defaultValue = true,
    },
    {
        key = "vendorSales",
        variableSuffix = "Source_VendorSales",
        label = "Vendor sales",
        tooltip = "Include money received from selling items to vendors.",
        defaultValue = true,
    },
    {
        key = "auctions",
        variableSuffix = "Source_Auctions",
        label = "Auction income",
        tooltip = "Include proceeds from auction-house sales.",
        defaultValue = false,
    },
    {
        key = "mailbox",
        variableSuffix = "Source_Mailbox",
        label = "Mailbox income",
        tooltip = "Include non-auction money received through the mailbox.",
        defaultValue = false,
    },
    {
        key = "playerTrades",
        variableSuffix = "Source_PlayerTrades",
        label = "Player trades",
        tooltip = "Include money received through direct player trades.",
        defaultValue = true,
    },
    {
        key = "miscellaneous",
        variableSuffix = "Source_Miscellaneous",
        label = "Miscellaneous/system income",
        tooltip = "Include otherwise unclassified money gains.",
        defaultValue = true,
    },
}

local CHAT_FEEDBACK_SETTING = {
    variableSuffix = "ChatFeedback",
    label = "Print tithe updates",
    tooltip = "Print a message in your chat window each time income adds to your tithe. Only you see it.",
    defaultValue = true,
}

local AUTO_DEPOSIT_SETTING = {
    variableSuffix = "AutoDeposit",
    label = "Deposit tithe automatically",
    tooltip = "Deposit your tithe as soon as you open the guild bank. " ..
        "The Pay Tithe button on the guild bank is always available too.",
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

local function buildSourceCheckboxes(state)
    local checkboxes = {}
    local index

    for index = 1, #SOURCE_SETTINGS do
        local definition = SOURCE_SETTINGS[index]
        local source = definition.key
        table.insert(checkboxes, {
            variable = addon.Identity.settingsPrefix .. "_" .. definition.variableSuffix,
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

    return checkboxes
end

local function buildChatFeedbackCheckbox(state)
    return {
        variable = addon.Identity.settingsPrefix .. "_" ..
            CHAT_FEEDBACK_SETTING.variableSuffix,
        label = CHAT_FEEDBACK_SETTING.label,
        tooltip = CHAT_FEEDBACK_SETTING.tooltip,
        defaultValue = CHAT_FEEDBACK_SETTING.defaultValue,
        getValue = function()
            return currentChatFeedback(state)
        end,
        setValue = function(value)
            return state:SetChatFeedback(value)
        end,
    }
end

local function buildAutoDepositCheckbox(state)
    return {
        variable = addon.Identity.settingsPrefix .. "_" ..
            AUTO_DEPOSIT_SETTING.variableSuffix,
        label = AUTO_DEPOSIT_SETTING.label,
        tooltip = AUTO_DEPOSIT_SETTING.tooltip,
        defaultValue = AUTO_DEPOSIT_SETTING.defaultValue,
        getValue = function()
            local character = currentCharacter(state)
            return character and character.autoDeposit
        end,
        setValue = function(value)
            return state:SetAutoDeposit(value)
        end,
    }
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
        categoryName = addon.Identity.displayName,
        balanceText = balanceText,
        percentage = {
            variable = addon.Identity.settingsPrefix .. "_Percentage",
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
        checkboxSections = {
            {
                heading = "Income Sources",
                checkboxes = buildSourceCheckboxes(self.state),
            },
            {
                heading = "Feedback",
                checkboxes = { buildChatFeedbackCheckbox(self.state) },
            },
            {
                heading = "Guild Bank",
                checkboxes = { buildAutoDepositCheckbox(self.state) },
            },
        },
    })

    if category == nil then
        return false
    end

    self.category = category
    return true
end

function Controller:Open()
    if self.category ~= nil then
        local balanceText = currentBalance(self.state, self.formatter)
        if balanceText ~= nil
            and type(self.client.RefreshSettingsBalance) == "function"
        then
            self.client:RefreshSettingsBalance(self.category, balanceText)
        end
    end

    if self.category ~= nil and self.client:OpenSettingsCategory(self.category) then
        return true
    end

    self.client:Print(addon.Identity.displayName ..
        ": settings are unavailable on this client. Use " ..
        addon.Identity.slashCommand .. " help.")
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
