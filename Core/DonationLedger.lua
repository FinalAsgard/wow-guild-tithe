local _, addon = ...

-- The account-wide, append-only record of completed donations. It is fed
-- only by confirmed guild-bank payments, keeps exact copper, and derives
-- every total from its entries, so history and totals can never drift apart.
local DonationLedger = {}
addon.DonationLedger = DonationLedger

local Ledger = {}
Ledger.__index = Ledger

local function copyTable(source)
    if type(source) ~= "table" then
        return source
    end
    local result = {}
    local key, value
    for key, value in pairs(source) do
        result[key] = copyTable(value)
    end
    return result
end

local function normalized(value)
    return (string.lower(value):gsub("%s+", ""))
end

-- Guilds group by the client's stable id when there is one, otherwise by
-- realm-qualified name; a display name alone never merges two guilds.
function DonationLedger.GuildKey(guild)
    if guild.id ~= nil then
        return "id:" .. guild.id
    end
    return "name:" .. string.lower(guild.name) .. "-" .. normalized(guild.realm)
end

-- Newest first; equal times fall back to the operation id so the order
-- never depends on when entries were appended.
local function newerFirst(first, second)
    if first.timestamp ~= second.timestamp then
        return first.timestamp > second.timestamp
    end
    return first.operationId > second.operationId
end

-- `records` returns the live saved donation list (nil while unavailable).
function DonationLedger.Create(records)
    return setmetatable({
        listeners = {},
        records = records,
    }, Ledger)
end

function Ledger:List()
    local list = self.records()
    if type(list) ~= "table" then
        return nil
    end
    -- Rebuild derived views whenever the saved list itself is replaced.
    if self.list ~= list then
        self.list = list
        self.byId = nil
        self.sorted = nil
    end
    return list
end

function Ledger:Index()
    local list = self:List()
    if list == nil then
        return nil
    end
    if self.byId == nil then
        self.byId = {}
        local index
        for index = 1, #list do
            self.byId[list[index].operationId] = list[index]
        end
    end
    return self.byId
end

-- Records a completed donation once. Returns true and the stored entry
-- (also for an id already recorded), or nil and a reason when the donation
-- is invalid or the ledger is unavailable; nothing is written in that case.
function Ledger:Append(donation)
    local index = self:Index()
    if index == nil then
        return nil, "the donation ledger is unavailable"
    end
    if type(donation) ~= "table" then
        return nil, "the donation is invalid"
    end
    local existing = index[donation.operationId]
    if existing ~= nil then
        return true, copyTable(existing), true
    end

    local entry = {
        operationId = donation.operationId,
        timestamp = donation.timestamp,
        amount = donation.amount,
        method = donation.method,
        character = copyTable(donation.character),
        guild = copyTable(donation.guild),
    }
    if not addon.Persistence.IsDonation(entry) then
        return nil, "the donation is invalid"
    end

    table.insert(self.list, entry)
    index[entry.operationId] = entry
    self.sorted = nil

    local copy = copyTable(entry)
    local listenerIndex
    for listenerIndex = 1, #self.listeners do
        -- A failing listener must not undo or repeat a recorded donation.
        pcall(self.listeners[listenerIndex], copyTable(copy))
    end
    return true, copy, false
end

-- Calls listener(entry) after each newly recorded donation.
function Ledger:OnAppend(listener)
    if type(listener) == "function" then
        table.insert(self.listeners, listener)
    end
end

-- True once the saved ledger is loaded and readable.
function Ledger:IsAvailable()
    return self:List() ~= nil
end

function Ledger:Count()
    local list = self:List()
    return list ~= nil and #list or 0
end

-- Up to `limit` entries, newest first, starting after `offset` entries.
-- Returns copies, so callers can never change the saved ledger.
function Ledger:Entries(offset, limit)
    local list = self:List()
    if list == nil then
        return {}
    end
    if self.sorted == nil then
        self.sorted = {}
        local index
        for index = 1, #list do
            self.sorted[index] = list[index]
        end
        table.sort(self.sorted, newerFirst)
    end

    offset = math.max(0, math.floor(tonumber(offset) or 0))
    local last = #self.sorted
    if limit ~= nil then
        last = math.min(last, offset + math.max(0, math.floor(limit)))
    end
    local result = {}
    local index
    for index = offset + 1, last do
        table.insert(result, copyTable(self.sorted[index]))
    end
    return result
end

-- The overall lifetime total and one total per guild (largest first, then
-- by name), each with the guild's most recent display snapshot.
function Ledger:Totals()
    local totals = { overall = 0, guilds = {} }
    local list = self:List()
    if list == nil then
        return totals
    end

    local byGuild = {}
    local index
    for index = 1, #list do
        local entry = list[index]
        local key = DonationLedger.GuildKey(entry.guild)
        local guild = byGuild[key]
        if guild == nil then
            guild = { key = key, amount = 0, latest = -1 }
            byGuild[key] = guild
            table.insert(totals.guilds, guild)
        end
        guild.amount = guild.amount + entry.amount
        if entry.timestamp >= guild.latest then
            guild.latest = entry.timestamp
            guild.id = entry.guild.id
            guild.name = entry.guild.name
            guild.realm = entry.guild.realm
        end
        totals.overall = totals.overall + entry.amount
    end

    table.sort(totals.guilds, function(first, second)
        if first.amount ~= second.amount then
            return first.amount > second.amount
        end
        return first.key < second.key
    end)
    for index = 1, #totals.guilds do
        totals.guilds[index].latest = nil
    end
    return totals
end
