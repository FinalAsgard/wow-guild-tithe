local _, addon = ...

-- Pays the outstanding tithe at the guild bank. The balance is reduced only
-- after the game shows the money actually left the character; anything
-- uncertain leaves the debt in place, because a later payment can fix an
-- unpaid balance but false credit corrupts the tithe.
local TithePayment = {
    -- Seconds to wait for the character's money to drop after a deposit.
    CONFIRM_TIMEOUT = 10,
}
addon.TithePayment = TithePayment

local Payment = {}
Payment.__index = Payment

-- The amount to offer: everything owed, but never more than is carried.
function TithePayment.Propose(outstandingCopper, carriedCopper)
    if type(outstandingCopper) ~= "number" or type(carriedCopper) ~= "number"
        or outstandingCopper <= 0 or carriedCopper <= 0
    then
        return 0
    end
    return math.min(outstandingCopper, carriedCopper)
end

function TithePayment.Create(client, state, formatter)
    return setmetatable({
        client = client,
        formatter = formatter or addon.MoneyFormatter,
        sessionOpen = false,
        state = state,
    }, Payment)
end

function Payment:Say(message)
    self.client:Print(addon.Identity.displayName .. ": " .. message)
end

function Payment:Money(copper)
    return self.formatter.Format(copper) or tostring(copper)
end

function Payment:Start()
    if self.started then
        return true
    end
    self.panel = self.client:CreatePaymentPanel(addon.Identity.displayName)
    self.client:ObserveMoneyChanges(function()
        self:OnMoneyChanged()
    end)
    self.started = self.client:ObserveGuildBank(function()
        self:OnGuildBankOpened()
    end, function()
        self:OnGuildBankClosed()
    end)
    return self.started
end

-- Works out what can be paid right now, or nil with a reason.
function Payment:CurrentProposal()
    local character = self.state:GetCurrentCharacter()
    if type(character) ~= "table" then
        return nil, "character state is unavailable"
    end
    local guild = self.client:GetGuildIdentity()
    if guild == nil then
        return nil, "not in a guild"
    end
    local carried = self.client:GetCarriedMoney()
    local amount = TithePayment.Propose(character.outstandingCopper, carried)
    if amount <= 0 then
        return nil, "nothing to pay"
    end
    return {
        amount = amount,
        guild = guild,
        remainder = character.outstandingCopper - amount,
    }
end

function Payment:ShowProposal()
    if self.panel == nil then
        return
    end
    local proposal = self:CurrentProposal()
    if proposal == nil then
        self.panel:Hide()
        return
    end
    self.panel:Show({
        "Pay to " .. proposal.guild.name,
        "Tithe: " .. self:Money(proposal.amount),
        "Still owed after: " .. self:Money(proposal.remainder),
    }, function()
        self:Pay()
    end)
end

function Payment:OnGuildBankOpened()
    self.sessionOpen = true
    -- Without a client timer, an unconfirmed payment from an earlier visit
    -- expires here so it can never block payments for good.
    if self.pending ~= nil and self.pending.untimed then
        self:Expire()
        return
    end
    if self.pending == nil then
        self:ShowProposal()
    end
end

-- Closing the bank discards any offer that was not acted on. A deposit that
-- was already requested keeps waiting for confirmation until it times out.
function Payment:OnGuildBankClosed()
    self.sessionOpen = false
    if self.panel ~= nil then
        self.panel:Hide()
    end
end

-- Requests the deposit for the current proposal. Only one payment can be
-- in flight at a time, and the balance is untouched until it confirms.
function Payment:Pay()
    if self.pending ~= nil or not self.sessionOpen then
        return false
    end
    local proposal, reason = self:CurrentProposal()
    if proposal == nil then
        self:Say("nothing was deposited (" .. reason .. ").")
        return false
    end

    local pending = {
        amount = proposal.amount,
        guild = proposal.guild,
        lastMoney = self.client:GetCarriedMoney(),
    }
    self.pending = pending
    if self.panel ~= nil then
        self.panel:Show({ "Depositing " .. self:Money(pending.amount) .. "..." })
    end

    if not self.client:DepositGuildBankMoney(pending.amount) then
        self.pending = nil
        self:Say("the guild bank deposit failed. Your tithe balance is unchanged.")
        self:ShowProposal()
        return false
    end

    if not self.client:After(TithePayment.CONFIRM_TIMEOUT, function()
        if self.pending == pending then
            self:Expire()
        end
    end) then
        -- Without a timer a stuck payment could block every later one, so
        -- the next money change or bank visit is its only chance to confirm.
        pending.untimed = true
    end
    return true
end

function Payment:Expire()
    self.pending = nil
    self:Say("the deposit was not confirmed, so your tithe balance is unchanged. Try again at the guild bank.")
    if self.sessionOpen then
        self:ShowProposal()
    end
end

-- Confirms the pending deposit only when a single money change drops carried
-- money by exactly the requested amount. Other changes while waiting (a
-- repair, a purchase) are tracked but never confirm the deposit.
function Payment:OnMoneyChanged()
    local pending = self.pending
    local current = self.client:GetCarriedMoney()
    if pending == nil or current == nil then
        return
    end
    local previous = pending.lastMoney
    pending.lastMoney = current
    if previous == nil or previous - current ~= pending.amount then
        return
    end
    self.pending = nil
    self:Confirm(pending)
end

function Payment:Confirm(pending)
    local character = self.state:GetCurrentCharacter()
    if type(character) ~= "table" then
        self:Say("the deposit went through, but your tithe balance could not be updated.")
        return
    end

    local remaining = math.max(0, character.outstandingCopper - pending.amount)
    if not self.state:SetFinancialState(remaining, character.fractionalRemainder) then
        self:Say("the deposit went through, but your tithe balance could not be updated.")
        return
    end

    self:Say("deposited " .. self:Money(pending.amount) .. " to " .. pending.guild.name ..
        ". Still owed: " .. self:Money(remaining) .. ".")
    if self.sessionOpen then
        self:ShowProposal()
    end
end
