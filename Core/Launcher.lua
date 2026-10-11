local _, addon = ...

-- The minimap icon's behavior: what its tooltip says and what its clicks
-- do. It knows nothing about the icon libraries; the client adapter shows
-- the icon and calls back here.
local Launcher = {
    -- A stock gold-coin icon present on both supported clients.
    ICON = "Interface\\Icons\\INV_Misc_Coin_01",
    NOT_IN_GUILD_TEXT = "Not in a guild",
    GUILD_UNAVAILABLE_TEXT = "Guild settings unavailable",
}
addon.Launcher = Launcher

local Controller = {}
Controller.__index = Controller

local GOLD = "|cffd4af37"
local GREY = "|cffaaaaaa"
local WHITE = "|cffffffff"

-- `actions` maps a mouse button name ("LeftButton", "RightButton") to the
-- function that button runs.
function Launcher.Create(client, state, formatter, actions)
    return setmetatable({
        actions = actions or {},
        client = client,
        formatter = formatter or addon.MoneyFormatter,
        state = state,
        visibilityListeners = {},
    }, Controller)
end

-- This character's balance in coins, or nil before state is ready.
function Controller:Balance()
    local character = self.state:GetCurrentCharacter()
    return character and self.formatter.Format(character.outstandingCopper)
end

function Controller:BalanceText()
    local balance = self:Balance()
    if balance == nil then
        return "Balance unavailable"
    end
    return "Balance owed: " .. WHITE .. balance .. "|r"
end

function Controller:GuildText()
    local settings = self.state:GetTitheSettings()
    if settings == nil or type(settings.guild) ~= "table" or type(settings.guild.name) ~= "string" then
        if self.state:IsInGuild() then
            return Launcher.GUILD_UNAVAILABLE_TEXT
        end
        return Launcher.NOT_IN_GUILD_TEXT
    end
    return "Tithing " .. WHITE .. settings.percentage .. "%|r to " ..
        WHITE .. settings.guild.name .. "|r"
end

-- The display-bar text, e.g. "Tithe: 1g 20s" (with coin icons).
function Controller:Text()
    return "Tithe: " .. (self:Balance() or "-")
end

-- Shows the current balance in display bars.
function Controller:RefreshText()
    if not self:IsAvailable() then
        return false
    end
    return self.client:SetMinimapLauncherText(addon.Identity.addonName, self:Text())
end

-- The tooltip shown while hovering the icon, one string per line.
function Controller:TooltipLines()
    return {
        GOLD .. addon.Identity.displayName .. "|r",
        self:BalanceText(),
        self:GuildText(),
        " ",
        GREY .. "Left-click:|r open settings",
        GREY .. "Right-click:|r open donation history",
    }
end

-- Runs the action for a click with `button`; other buttons do nothing.
function Controller:Click(button)
    local action = self.actions[button]
    if type(action) ~= "function" then
        return false
    end
    action()
    return true
end

-- Shows the icon once saved state is ready. Returns false, quietly, when
-- the client cannot show one (for example, the icon libraries are missing).
function Controller:Start()
    if self.started then
        return true
    end
    if type(self.client.RegisterMinimapLauncher) ~= "function" then
        return false
    end

    local iconState = self.state:GetMinimapState()
    if type(iconState) ~= "table" then
        return false
    end

    self.started = self.client:RegisterMinimapLauncher({
        name = addon.Identity.addonName,
        label = addon.Identity.displayName,
        icon = Launcher.ICON,
        iconState = iconState,
        text = self:Text(),
        onClick = function(button)
            self:Click(button)
        end,
        tooltipLines = function()
            return self:TooltipLines()
        end,
    })
    -- The tooltip is built each time it opens, so only the display-bar text
    -- has to follow the balance: income, deposits, and /agt clear.
    if self.started and type(self.state.OnFinancialChange) == "function" then
        self.state:OnFinancialChange(function()
            self:RefreshText()
        end)
    end
    return self.started
end

-- Whether the client is showing the icon (the libraries loaded).
function Controller:IsAvailable()
    return self.started == true
end

-- Whether the icon is set to show; it shows by default.
function Controller:IsShown()
    local iconState = self.state:GetMinimapState()
    return type(iconState) ~= "table" or iconState.hide ~= true
end

-- Saves whether the icon shows on every character and applies it now.
-- Returns false, changing nothing, when there is no icon to show or hide.
function Controller:SetShown(shown)
    if not self:IsAvailable() or not self.state:SetMinimapIconShown(shown) then
        return false
    end
    self.client:SetMinimapIconShown(addon.Identity.addonName, shown)
    local index
    for index = 1, #self.visibilityListeners do
        pcall(self.visibilityListeners[index])
    end
    return true
end

-- Calls listener() after the icon is shown or hidden, however it happened.
function Controller:OnVisibilityChange(listener)
    if type(listener) == "function" then
        table.insert(self.visibilityListeners, listener)
    end
end

function Controller:RegisterCommands(router)
    return router:Register("minimap", "show or hide the minimap icon", function()
        local shown = not self:IsShown()
        if not self:SetShown(shown) then
            self.client:Print(addon.Identity.chatPrefix ..
                " The minimap icon is unavailable on this client.")
        elseif shown then
            self.client:Print(addon.Identity.chatPrefix .. " Minimap icon shown.")
        else
            self.client:Print(addon.Identity.chatPrefix .. " Minimap icon hidden. Use " ..
                addon.Identity.slashCommand .. " minimap to show it again.")
        end
    end)
end
