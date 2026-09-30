local _, addon = ...

local IncomeFeedback = {
    -- Seconds of quiet after the last accrual before a grouped message prints.
    COALESCE_WINDOW = 1.0,
    -- A group prints once it holds this many accruals, so a long burst
    -- (for example, selling a full bag) still reports as it goes.
    MAX_GROUP_SIZE = 20,
}
addon.IncomeFeedback = IncomeFeedback

local Feedback = {}
Feedback.__index = Feedback

local SOURCE_LABELS = {
    auctions = "auctions",
    loot = "loot",
    mailbox = "mail",
    miscellaneous = "other income",
    playerTrades = "a trade",
    quests = "quests",
    vendorSales = "vendor sales",
}

-- `after(seconds, callback)` schedules a callback and returns false when it
-- cannot; without a scheduler every accrual prints immediately.
function IncomeFeedback.Create(output, formatter, after)
    return setmetatable({
        after = type(after) == "function" and after or nil,
        formatter = formatter or addon.MoneyFormatter,
        generation = 0,
        output = type(output) == "function" and output or function() end,
    }, Feedback)
end

-- Prints the pending group, if it reserved any whole copper. Chat grouping
-- is presentation only: every accrual was already saved when it happened.
function Feedback:Flush()
    local group = self.group
    self.group = nil
    if group == nil or group.accruedCopper <= 0 then
        return false
    end

    local reserved = self.formatter.Format(group.accruedCopper)
    local total = self.formatter.Format(group.outstandingCopper)
    if reserved == nil or total == nil then
        return false
    end

    self.output(addon.Identity.chatPrefix .. " +" .. reserved .. " tithe from " ..
        (SOURCE_LABELS[group.source] or group.source) .. " \194\183 owed " .. total)
    return true
end

-- Reports whole copper newly reserved. Nearby accruals from the same source
-- share one message with their combined amount and the latest total; a
-- different source always starts a new message. A zero-copper accrual (only
-- the fractional remainder moved) is never announced as "0 reserved".
function Feedback:Accrued(source, accruedCopper, outstandingCopper)
    if type(accruedCopper) ~= "number" or accruedCopper < 0 then
        return false
    end

    if self.group ~= nil and self.group.source ~= source then
        self:Flush()
    end
    if self.group == nil then
        if accruedCopper == 0 then
            return false
        end
        self.group = { accruedCopper = 0, count = 0, source = source }
    end

    local group = self.group
    group.accruedCopper = group.accruedCopper + accruedCopper
    group.outstandingCopper = outstandingCopper
    group.count = group.count + 1

    if group.count >= IncomeFeedback.MAX_GROUP_SIZE then
        return self:Flush()
    end

    self.generation = self.generation + 1
    local generation = self.generation
    local scheduled = self.after ~= nil and self.after(IncomeFeedback.COALESCE_WINDOW, function()
        if self.generation == generation then
            self:Flush()
        end
    end)
    if not scheduled then
        return self:Flush()
    end
    return true
end
