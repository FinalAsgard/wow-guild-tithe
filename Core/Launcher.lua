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
    }, Controller)
end

function Controller:BalanceText()
    local character = self.state:GetCurrentCharacter()
    local balance = character and self.formatter.Format(character.outstandingCopper)
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
        onClick = function(button)
            self:Click(button)
        end,
        tooltipLines = function()
            return self:TooltipLines()
        end,
    })
    return self.started
end
