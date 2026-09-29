local _, addon = ...

local IncomeFeedback = {}
addon.IncomeFeedback = IncomeFeedback

local Feedback = {}
Feedback.__index = Feedback

local SOURCE_LABELS = {
    auctions = "auction",
    loot = "loot",
    mailbox = "mailbox",
    miscellaneous = "miscellaneous/system",
    playerTrades = "player trade",
    quests = "quest",
    vendorSales = "vendor sale",
}

function IncomeFeedback.Create(output, formatter)
    return setmetatable({
        formatter = formatter or addon.MoneyFormatter,
        output = type(output) == "function" and output or function() end,
    }, Feedback)
end

-- Reports whole copper newly reserved. A zero-copper accrual (only the
-- fractional remainder moved) is never announced as "0 reserved".
function Feedback:Accrued(source, accruedCopper, outstandingCopper)
    if type(accruedCopper) ~= "number" or accruedCopper <= 0 then
        return false
    end

    local reserved = self.formatter.Format(accruedCopper)
    local total = self.formatter.Format(outstandingCopper)
    if reserved == nil or total == nil then
        return false
    end

    self.output(addon.Identity.displayName .. ": reserved " .. reserved ..
        " from " .. (SOURCE_LABELS[source] or source) .. " income. Total owed: " ..
        total .. ".")
    return true
end
