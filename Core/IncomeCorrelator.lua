local _, addon = ...

-- Holds short-lived source context and decides which source explains a money
-- gain. Pure logic: times come from the caller, so sequences are replayable.
local IncomeCorrelator = {
    -- How close (seconds) a single corroborating message must be to a gain.
    NOTE_WINDOW = 1.0,
    -- How long (seconds) an interaction still explains gains after it closes.
    CLOSE_GRACE = 1.0,
    -- An interaction whose close event never arrives stops counting after
    -- this many seconds, so it cannot claim unrelated later gains.
    MAX_OPEN = 120,
    -- Upper bound on remembered notes, oldest dropped first.
    MAX_NOTES = 32,
    -- Most specific source first. Sources not listed never classify.
    -- Corroborating notes are checked before open interactions, because a
    -- note names one gain while an interaction (e.g. an open vendor) is broad.
    -- Exclusions (known non-income, such as money returned to the sender)
    -- sit above the sources they could be confused with.
    PRECEDENCE = {
        "quests",
        "returnedMail",
        "refund",
        "guildBankWithdrawal",
        "auctions",
        "mailbox",
        "loot",
        "playerTrades",
        "vendorSales",
    },
    -- Context that identifies a known non-income transfer, with its reason.
    EXCLUSIONS = {
        guildBankWithdrawal = "money withdrawn from the guild bank is not income",
        refund = "an item refund returns money you already spent",
        returnedMail = "mail returned to sender is your own money coming back",
    },
}
addon.IncomeCorrelator = IncomeCorrelator

local Correlator = {}
Correlator.__index = Correlator

function IncomeCorrelator.Create()
    return setmetatable({
        notes = {},
        sessions = {},
    }, Correlator)
end

local function isTime(value)
    return type(value) == "number" and value == value
end

-- Discards all pending context, e.g. at session start or reload.
function Correlator:Reset()
    self.notes = {}
    self.sessions = {}
end

-- `amount` (optional, notes only) is the exact copper the note describes; a
-- note with an amount only explains a gain of exactly that size.
function Correlator:Record(source, action, now, amount)
    if type(source) ~= "string" or not isTime(now) then
        return false
    end

    if action == "note" then
        if amount ~= nil and (type(amount) ~= "number" or amount < 0) then
            amount = nil
        end
        table.insert(self.notes, { amount = amount, at = now, source = source })
        while #self.notes > IncomeCorrelator.MAX_NOTES do
            table.remove(self.notes, 1)
        end
    elseif action == "open" then
        self.sessions[source] = { openedAt = now }
    elseif action == "close" then
        local session = self.sessions[source]
        if session ~= nil and session.closedAt == nil then
            session.closedAt = now
        end
    else
        return false
    end

    return true
end

-- Drops context that can no longer explain a gain observed at or after `now`.
function Correlator:Prune(now)
    if not isTime(now) then
        return
    end

    local kept = {}
    local index
    for index = 1, #self.notes do
        local note = self.notes[index]
        if note.at + IncomeCorrelator.NOTE_WINDOW >= now then
            table.insert(kept, note)
        end
    end
    self.notes = kept

    local source, session
    for source, session in pairs(self.sessions) do
        local expiresAt = session.closedAt ~= nil
            and session.closedAt + IncomeCorrelator.CLOSE_GRACE
            or session.openedAt + IncomeCorrelator.MAX_OPEN
        if expiresAt < now then
            self.sessions[source] = nil
        end
    end
end

local function sessionExplains(session, observedAt)
    if session == nil or session.openedAt > observedAt then
        return false
    end
    if session.closedAt == nil then
        return observedAt <= session.openedAt + IncomeCorrelator.MAX_OPEN
    end
    return observedAt <= session.closedAt + IncomeCorrelator.CLOSE_GRACE
end

-- Returns the index of the first note for `source` that explains the gain.
local function explainingNote(notes, source, observedAt, finalizedAt, copper)
    local index
    for index = 1, #notes do
        local note = notes[index]
        if note.source == source
            and note.at >= observedAt - IncomeCorrelator.NOTE_WINDOW
            and note.at <= finalizedAt
            and (note.amount == nil or note.amount == copper)
        then
            return index
        end
    end
    return nil
end

local function result(source, reason)
    local exclusion = IncomeCorrelator.EXCLUSIONS[source]
    if exclusion ~= nil then
        return source, exclusion, true
    end
    return source, reason, false
end

-- Returns source, reason, excluded for a gain of `copper` observed at
-- `observedAt` and finalized at `finalizedAt`. Notes that arrive after the
-- money change but before finalization still count, so reordered events
-- classify the same way. A note naming an exact amount is used up by the
-- gain it explains, so one mail or reward cannot explain two gains.
function Correlator:Classify(observedAt, finalizedAt, copper)
    if not isTime(observedAt) or not isTime(finalizedAt) then
        return "miscellaneous", "no clock to correlate source context", false
    end

    local index
    for index = 1, #IncomeCorrelator.PRECEDENCE do
        local source = IncomeCorrelator.PRECEDENCE[index]
        local noteIndex = explainingNote(self.notes, source, observedAt, finalizedAt, copper)
        if noteIndex ~= nil then
            if self.notes[noteIndex].amount ~= nil then
                table.remove(self.notes, noteIndex)
            end
            return result(source, source .. " message corroborated the gain")
        end
    end
    for index = 1, #IncomeCorrelator.PRECEDENCE do
        local source = IncomeCorrelator.PRECEDENCE[index]
        if sessionExplains(self.sessions[source], observedAt) then
            return result(source, source .. " interaction was open")
        end
    end

    return "miscellaneous", "no specific source context", false
end
