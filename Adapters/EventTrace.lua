local _, addon = ...

-- Development-only recorder of raw client events around income activity.
-- Traces are captured on real Forever and Retail clients and turned into test
-- fixtures, so this module deliberately knows client event and API names.
local EventTrace = {
    MAX_ENTRIES = 2000,
    MAX_STRING_LENGTH = 255,
}
addon.EventTrace = EventTrace

local EVENTS = {
    "PLAYER_MONEY",
    "CHAT_MSG_MONEY",
    "LOOT_OPENED",
    "LOOT_SLOT_CLEARED",
    "LOOT_CLOSED",
    "QUEST_COMPLETE",
    "QUEST_TURNED_IN",
    "QUEST_FINISHED",
    "MERCHANT_SHOW",
    "MERCHANT_UPDATE",
    "MERCHANT_CLOSED",
    "MAIL_SHOW",
    "MAIL_INBOX_UPDATE",
    "MAIL_SUCCESS",
    "CLOSE_INBOX_ITEM",
    "MAIL_CLOSED",
    "TRADE_SHOW",
    "TRADE_MONEY_CHANGED",
    "TRADE_ACCEPT_UPDATE",
    "TRADE_REQUEST_CANCEL",
    "TRADE_CLOSED",
    "GUILDBANKFRAME_OPENED",
    "GUILDBANK_UPDATE_MONEY",
    "GUILDBANK_UPDATE_WITHDRAWMONEY",
    "GUILDBANKFRAME_CLOSED",
    "PLAYER_GUILD_UPDATE",
    "PLAYER_INTERACTION_MANAGER_FRAME_SHOW",
    "PLAYER_INTERACTION_MANAGER_FRAME_HIDE",
    "UI_INFO_MESSAGE",
    "UI_ERROR_MESSAGE",
    "ADDON_ACTION_BLOCKED",
    "ADDON_ACTION_FORBIDDEN",
}

-- Mail collection is a function call, not an event, so it is hooked.
local MAIL_CALLS = { "TakeInboxMoney", "AutoLootMailItem" }

-- Guild-bank money calls, whether made by this add-on or the game's window.
local BANK_CALLS = { "DepositGuildBankMoney", "WithdrawGuildBankMoney" }

local Trace = {}
Trace.__index = Trace

function EventTrace.Create(client, environment)
    return setmetatable({
        active = false,
        client = client,
        environment = environment or _G,
        hooked = false,
    }, Trace)
end

local function sanitize(value)
    local valueType = type(value)
    if valueType == "number" or valueType == "boolean" then
        return value
    end
    if valueType == "string" then
        return string.sub(value, 1, EventTrace.MAX_STRING_LENGTH)
    end
    if value == nil then
        return "<nil>"
    end
    return "<" .. valueType .. ">"
end

local function pack(...)
    local values = {}
    local count = select("#", ...)
    local index
    for index = 1, count do
        values[index] = sanitize((select(index, ...)))
    end
    return values
end

function Trace:Database()
    local name = addon.Identity.traceDatabaseName
    local database = self.environment[name]
    if type(database) ~= "table" or type(database.entries) ~= "table" then
        database = { entries = {} }
        self.environment[name] = database
    end
    return database
end

function Trace:Now()
    local clock = self.environment.GetTimePreciseSec or self.environment.GetTime
    if type(clock) ~= "function" then
        return nil
    end
    local ok, now = pcall(clock)
    return ok and now or nil
end

function Trace:Record(kind, name, args, extra)
    if not self.active then
        return
    end

    local entries = self:Database().entries
    local entry = {
        args = args,
        combat = false,
        kind = kind,
        money = self.client:GetCarriedMoney(),
        name = name,
        t = self:Now(),
    }
    local inCombat = self.environment.InCombatLockdown
    if type(inCombat) == "function" then
        local ok, result = pcall(inCombat)
        entry.combat = ok and result == true
    end
    if extra ~= nil then
        entry.extra = extra
    end

    table.insert(entries, entry)
    local database = self:Database()
    while #entries > EventTrace.MAX_ENTRIES do
        -- Keep the carried money from just before the first retained entry,
        -- so a replay of a trimmed trace starts from the right balance.
        database.baselineMoney = table.remove(entries, 1).money
    end
end

function Trace:MailDetails(index)
    local details = {}
    local invoice = self.environment.GetInboxInvoiceInfo
    if type(invoice) == "function" then
        details.invoice = pack(pcall(invoice, index))
    end
    local header = self.environment.GetInboxHeaderInfo
    if type(header) == "function" then
        details.header = pack(pcall(header, index))
    end
    return details
end

function Trace:HookMailCalls()
    local hook = self.environment.hooksecurefunc
    if self.hooked or type(hook) ~= "function" then
        return
    end
    self.hooked = true

    local function callerStack()
        local stack = self.environment.debugstack
        if type(stack) ~= "function" then
            return nil
        end
        local ok, text = pcall(stack, 3, 4, 0)
        return ok and sanitize(text) or nil
    end

    local bankIndex
    for bankIndex = 1, #BANK_CALLS do
        local callName = BANK_CALLS[bankIndex]
        if type(self.environment[callName]) == "function" then
            pcall(hook, callName, function(copper)
                if self.active then
                    -- The caller's stack tells this add-on's calls apart.
                    self:Record("call", callName, pack(copper), { stack = callerStack() })
                end
            end)
        end
    end

    -- This add-on's own chat lines show what it decided at each step.
    local chat = self.environment.DEFAULT_CHAT_FRAME
    if type(chat) == "table" and type(chat.AddMessage) == "function" then
        pcall(hook, chat, "AddMessage", function(_, message)
            if self.active and type(message) == "string"
                and string.find(message, addon.Identity.displayName, 1, true) == 1
            then
                self:Record("chat", "message", pack(message))
            end
        end)
    end

    local index
    for index = 1, #MAIL_CALLS do
        local callName = MAIL_CALLS[index]
        if type(self.environment[callName]) == "function" then
            -- Secure hooks cannot be removed; Record ignores calls while idle.
            pcall(hook, callName, function(mailIndex)
                if self.active then
                    self:Record("call", callName, pack(mailIndex), self:MailDetails(mailIndex))
                end
            end)
        end
    end
end

function Trace:Start()
    if self.active then
        return true
    end

    local frame = self.frame or self.client:CreateEventFrame()
    if frame == nil then
        return false, "event frames are unavailable"
    end
    self.frame = frame
    if not self.client:SetEventHandler(frame, function(_, eventName, ...)
        self:Record("event", eventName, pack(...))
    end) then
        return false, "event handlers are unavailable"
    end

    local registered, skipped = {}, {}
    local index
    for index = 1, #EVENTS do
        if self.client:RegisterEvent(frame, EVENTS[index]) then
            table.insert(registered, EVENTS[index])
        else
            table.insert(skipped, EVENTS[index])
        end
    end
    self:HookMailCalls()

    local database = self:Database()
    local buildInfo = self.environment.GetBuildInfo
    database.header = {
        build = type(buildInfo) == "function" and pack(pcall(buildInfo)) or nil,
        client = self.client:GetClientProfile().label,
        registered = registered,
        skipped = skipped,
        startedAt = self:Now(),
    }
    self.active = true
    self:Record("marker", "trace started", {})
    return true
end

function Trace:Stop()
    if not self.active then
        return false
    end

    self:Record("marker", "trace stopped", {})
    self.active = false
    local unregister = self.frame and self.frame.UnregisterAllEvents
    if type(unregister) == "function" then
        pcall(unregister, self.frame)
    end
    return true
end

function Trace:Clear()
    self.environment[addon.Identity.traceDatabaseName] = { entries = {} }
end

function Trace:Status()
    return self.active, #self:Database().entries
end
