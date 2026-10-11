local _, addon = ...

-- Tithe settings shared by every character on the account in one guild: the
-- percentage and the income-source flags. Records live in the account-wide
-- `guilds` table; callers only ever receive copies.
local GuildSettings = {}
addon.GuildSettings = GuildSettings

local Settings = {}
Settings.__index = Settings

local function copyTable(source)
    local result = {}
    local key, value
    for key, value in pairs(source) do
        if type(value) == "table" then
            result[key] = copyTable(value)
        else
            result[key] = value
        end
    end
    return result
end

local function isPercentage(value)
    return type(value) == "number"
        and value >= 0
        and value <= 100
        and value == math.floor(value)
end

function GuildSettings.Create(persistence)
    return setmetatable({ persistence = persistence }, Settings)
end

local function snapshot(guildKey, record)
    return {
        guildKey = guildKey,
        percentage = record.percentage,
        sources = copyTable(record.sources),
    }
end

-- A copy of the settings for `identity`'s guild, or nil when the identity is
-- unusable or the guild's record is quarantined. A guild with no record yet
-- is created from `seed` ({ percentage, sources }, either optional), with the
-- defaults for anything the seed lacks.
function Settings:Get(identity, seed)
    local guildKey = addon.Persistence.GuildKey(identity)
    if guildKey == nil then
        return nil
    end

    local record = self.persistence:GetGuild(guildKey)
    if record ~= nil then
        return snapshot(guildKey, record)
    end

    record = self.persistence:CreateGuild(guildKey, identity, seed)
    if record == nil then
        return nil
    end
    return snapshot(guildKey, record)
end

function Settings:SetPercentage(guildKey, percentage)
    local record = self.persistence:GetGuild(guildKey)
    if record == nil or not isPercentage(percentage) then
        return false
    end
    record.percentage = percentage
    return true
end

function Settings:SetSourceEnabled(guildKey, source, enabled)
    local record = self.persistence:GetGuild(guildKey)
    if record == nil
        or not addon.Persistence.IsSource(source)
        or type(enabled) ~= "boolean"
    then
        return false
    end
    record.sources[source] = enabled
    return true
end
