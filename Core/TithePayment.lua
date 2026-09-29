local _, addon = ...

-- Pays the outstanding tithe at the guild bank. The balance is reduced only
-- after the game shows the money actually left the character; anything
-- uncertain leaves the debt in place, because a later payment can fix an
-- unpaid balance but false credit corrupts the tithe.
local TithePayment = {
    -- Seconds to wait for the character's money to drop after a deposit.
    CONFIRM_TIMEOUT = 10,
    -- Seconds between the guild bank opening and an automatic deposit, so
    -- the bank has finished opening before money is sent to it.
    AUTO_DEPOSIT_DELAY = 1,
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

local function normalized(value)
    return (string.lower(value):gsub("%s+", ""))
end

-- Guilds match by stable id when both sides have one, otherwise by
-- realm-qualified name.
function TithePayment.SameGuild(first, second)
    if type(first) ~= "table" or type(second) ~= "table" then
        return false
    end
    if first.id ~= nil and second.id ~= nil then
        return first.id == second.id
    end
    return type(first.name) == "string" and type(second.name) == "string"
        and type(first.realm) == "string" and type(second.realm) == "string"
        and string.lower(first.name) == string.lower(second.name)
        and normalized(first.realm) == normalized(second.realm)
end

function TithePayment.Create(client, state, formatter)
    return setmetatable({
        client = client,
        formatter = formatter or addon.MoneyFormatter,
        listeners = {},
        sessionOpen = false,
        state = state,
    }, Payment)
end

-- Calls listener(donation) once for each confirmed payment, after the
-- reduced balance is saved. The donation holds operationId, timestamp,
-- amount, method, character {key, name, realm}, and guild {id, name, realm}.
function Payment:OnDonation(listener)
    if type(listener) == "function" then
        table.insert(self.listeners, listener)
    end
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
    self.client:ObserveGuildBankDeposits(function(copper)
        self:OnManualDeposit(copper)
    end)
    self.client:ObserveActionBlocked(function(functionName)
        self:OnActionBlocked(functionName)
    end)
    self:ResumeSavedPayment()
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

-- A payment saved before a reload is confirmed if carried money already
-- shows the deposit, and otherwise keeps waiting for it with a fresh timeout.
function Payment:ResumeSavedPayment()
    local intent = self.state:GetPendingPayment()
    if intent == nil then
        return
    end
    local current = self.client:GetCarriedMoney()
    self.pending = { intent = intent, lastMoney = current }
    if current ~= nil and intent.moneyBefore - current == intent.amount then
        self:Reconcile(self.pending)
        return
    end
    self:StartTimeout(self.pending)
end

function Payment:StartTimeout(pending)
    if not self.client:After(TithePayment.CONFIRM_TIMEOUT, function()
        if self.pending == pending then
            self:Expire()
        end
    end) then
        -- Without a timer a stuck payment could block every later one, so
        -- the next money change or bank visit is its only chance to confirm.
        pending.untimed = true
    end
end

-- Re-reads the balance into an open guild-bank offer, e.g. after it changed.
function Payment:RefreshOffer()
    if self.sessionOpen and self.pending == nil then
        self:ShowProposal()
    end
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
        self.bankVisit = (self.bankVisit or 0) + 1
        local visit = self.bankVisit
        if not self.client:After(TithePayment.AUTO_DEPOSIT_DELAY, function()
            -- Only for the visit that scheduled it, while the bank is open.
            if self.bankVisit == visit and self.sessionOpen and self.pending == nil then
                self:DepositAutomatically()
            end
        end) then
            self:DepositAutomatically()
        end
    end
end

-- With the setting on, pays the proposal without a click. The button stays
-- as the fallback, and after the client blocks an automatic deposit it is
-- not tried again this session, so the player never sees repeated errors.
function Payment:DepositAutomatically()
    local character = self.state:GetCurrentCharacter()
    if type(character) ~= "table"
        or character.autoDeposit ~= true
        or self.autoDepositBlocked
        or self:CurrentProposal() == nil
    then
        return false
    end
    return self:Pay("automatic")
end

function Payment:OnActionBlocked(functionName)
    if functionName ~= nil
        and not string.find(tostring(functionName), "DepositGuildBankMoney", 1, true)
    then
        return
    end
    local pending = self.pending
    if pending == nil or pending.intent.method ~= "automatic" then
        return
    end

    self.autoDepositBlocked = true
    self:Resolve(pending, "rejected")
    self:Say("the game blocked the automatic deposit, so your tithe balance is unchanged. " ..
        "Use the Give Tithe button on the guild bank.")
    if self.sessionOpen then
        self:ShowProposal()
    end
end

-- Closing the bank discards any offer that was not acted on. A deposit that
-- was already requested keeps waiting for confirmation until it times out.
function Payment:OnGuildBankClosed()
    self.sessionOpen = false
    self.bankVisit = (self.bankVisit or 0) + 1
    if self.panel ~= nil then
        self.panel:Hide()
    end
end

-- Requests the deposit for the current proposal. Only one payment can be
-- in flight at a time, and the balance is untouched until it confirms.
-- `method` records how the payment was started (default "button").
function Payment:Pay(method)
    if self.pending ~= nil or not self.sessionOpen then
        return false
    end
    local proposal, reason = self:CurrentProposal()
    if proposal == nil then
        self:Say("nothing was deposited (" .. reason .. ").")
        return false
    end

    local pending = self:BeginPending(proposal.amount, method or "button", proposal.guild)
    if pending == nil then
        self:Say("nothing was deposited (the payment could not be saved).")
        return false
    end
    local intent = pending.intent
    if self.panel ~= nil then
        self.panel:Show({ "Depositing " .. self:Money(intent.amount) .. "..." })
    end

    -- The deposit hook also sees this call, but this payment is already in
    -- flight, so it can never be counted a second time as a manual deposit.
    if not self.client:DepositGuildBankMoney(intent.amount) then
        self:Resolve(pending, "rejected")
        self:Say("the guild bank deposit failed. Your tithe balance is unchanged.")
        self:ShowProposal()
        return false
    end

    self:StartTimeout(pending)
    return true
end

-- Saves a new pending intent for `amount` and makes it the one in flight.
function Payment:BeginPending(amount, method, guild)
    local character = self.state:GetCurrentCharacter()
    local moneyBefore = self.client:GetCarriedMoney()
    if type(character) ~= "table" or moneyBefore == nil then
        return nil
    end
    local identity = character.identity or {}
    local createdAt = self.client:Timestamp() or self.client:Now() or 0
    local intent = {
        operationId = self.state:NextPaymentOperationId(createdAt),
        amount = amount,
        method = method,
        character = {
            key = self.state:GetCharacterKey(),
            name = identity.displayName,
            realm = identity.displayRealm,
        },
        guild = guild,
        moneyBefore = moneyBefore,
        createdAt = createdAt,
        status = "pending",
    }
    if not self.state:BeginPayment(intent) then
        return nil
    end

    local pending = { intent = intent, lastMoney = moneyBefore }
    self.pending = pending
    return pending
end

-- A deposit the player made through the game's own guild-bank window. It
-- becomes a pending intent like any other and counts only when carried
-- money drops by exactly the deposited amount. While another payment is in
-- flight it is ignored rather than guessed at.
function Payment:OnManualDeposit(copper)
    if not self.sessionOpen
        or self.pending ~= nil
        or type(copper) ~= "number"
        or copper <= 0
    then
        return
    end
    local guild = self.client:GetGuildIdentity()
    if guild == nil then
        return
    end
    local pending = self:BeginPending(copper, "manual", guild)
    if pending ~= nil then
        self:StartTimeout(pending)
    end
end

-- Ends `pending` with a terminal status that leaves the balance unchanged.
function Payment:Resolve(pending, status)
    if self.pending == pending then
        self.pending = nil
    end
    self.state:ResolvePayment(pending.intent.operationId, status)
end

function Payment:Expire()
    local pending = self.pending
    self:Resolve(pending, "expired")
    if pending.intent.method == "manual" then
        self:Say("your guild-bank deposit was not confirmed, so it was not counted toward your tithe.")
        return
    end
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
    if previous == nil or previous - current ~= pending.intent.amount then
        return
    end
    self:Reconcile(pending)
end

-- Credits the deposit only to the guild it was made for. If the character
-- left or switched guilds meanwhile, the payment stays unresolved and the
-- balance is untouched rather than credited to the wrong guild.
function Payment:Reconcile(pending)
    local intent = pending.intent
    if not TithePayment.SameGuild(intent.guild, self.client:GetGuildIdentity()) then
        self:Resolve(pending, "unresolved")
        self:Say("your guild changed before the deposit to " .. intent.guild.name ..
            " was confirmed, so your tithe balance is unchanged.")
        return
    end
    self:Confirm(pending)
end

function Payment:Confirm(pending)
    local intent = pending.intent
    if self.pending == pending then
        self.pending = nil
    end
    local character = self.state:GetCurrentCharacter()
    if type(character) ~= "table" then
        self:Say("the deposit went through, but your tithe balance could not be updated.")
        return
    end

    -- Only the requested amount is ever credited, and never below zero.
    local remaining = math.max(0, character.outstandingCopper - intent.amount)
    if not self.state:ResolvePayment(intent.operationId, "confirmed",
        remaining, character.fractionalRemainder)
    then
        -- Already resolved (a replayed signal) or not saved: credit nothing.
        return
    end

    self:Say("deposited " .. self:Money(intent.amount) .. " to " .. intent.guild.name ..
        ". Still owed: " .. self:Money(remaining) .. ".")
    self:Publish(intent)
    if self.sessionOpen then
        self:ShowProposal()
    end
end

function Payment:Publish(intent)
    local donation = {
        operationId = intent.operationId,
        timestamp = self.client:Timestamp() or intent.createdAt,
        amount = intent.amount,
        method = intent.method,
        character = {
            key = intent.character.key,
            name = intent.character.name,
            realm = intent.character.realm,
        },
        guild = {
            id = intent.guild.id,
            name = intent.guild.name,
            realm = intent.guild.realm,
        },
    }
    local index
    for index = 1, #self.listeners do
        -- A failing listener must not undo or repeat a saved payment.
        pcall(self.listeners[index], donation)
    end
end
