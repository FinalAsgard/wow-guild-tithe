local _, addon = ...

-- Tithe settings shared by every character on the account in one guild: the
-- percentage and the income-source flags (simple mode), and advanced mode
-- with its per-source percentages. Records live in the account-wide
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
        advancedMode = record.advancedMode == true,
        guildKey = guildKey,
        percentage = record.percentage,
        sourcePercentages = type(record.sourcePercentages) == "table"
            and copyTable(record.sourcePercentages) or nil,
        sources = copyTable(record.sources),
    }
end

-- The percentage `source` tithes at under `settings` (a snapshot), or nil
-- when it is off. Simple mode tithes enabled sources at the one percentage;
-- advanced mode tithes each source at its own percentage, and 0% is off.
function GuildSettings.RateFor(settings, source)
    if type(settings) ~= "table" then
        return nil
    end

    if settings.advancedMode == true then
        local percentages = settings.sourcePercentages
        local percentage = type(percentages) == "table" and percentages[source] or nil
        if isPercentage(percentage) and percentage > 0 then
            return percentage
        end
        return nil
    end

    if type(settings.sources) == "table"
        and settings.sources[source] == true
        and isPercentage(settings.percentage)
    then
        return settings.percentage
    end
    return nil
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

-- Turns advanced mode on or off. The first time it is turned on, each
-- source starts at the percentage it tithes at in simple mode; after that
-- the per-source percentages are kept however often the mode changes.
function Settings:SetAdvancedMode(guildKey, enabled)
    local record = self.persistence:GetGuild(guildKey)
    if record == nil or type(enabled) ~= "boolean" then
        return false
    end
    if enabled and type(record.sourcePercentages) ~= "table" then
        record.sourcePercentages = addon.Persistence.SeedSourcePercentages(record)
    end
    record.advancedMode = enabled
    return true
end

-- Sets one source's advanced-mode percentage; 0 turns the source off.
function Settings:SetSourcePercentage(guildKey, source, percentage)
    local record = self.persistence:GetGuild(guildKey)
    if record == nil
        or not addon.Persistence.IsSource(source)
        or not isPercentage(percentage)
    then
        return false
    end
    if type(record.sourcePercentages) ~= "table" then
        record.sourcePercentages = addon.Persistence.SeedSourcePercentages(record)
    end
    record.sourcePercentages[source] = percentage
    return true
end
