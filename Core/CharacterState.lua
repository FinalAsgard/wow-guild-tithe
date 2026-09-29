local _, addon = ...

local CharacterState = {
    MAX_SAFE_INTEGER = 9007199254740991,
}
addon.CharacterState = CharacterState

local State = {}
State.__index = State

local SOURCE_DEFAULTS = {
    auctions = false,
    loot = true,
    mailbox = false,
    miscellaneous = true,
    playerTrades = true,
    quests = true,
    vendorSales = true,
}

local function isInteger(value)
    return type(value) == "number"
        and value >= 0
        and value <= CharacterState.MAX_SAFE_INTEGER
        and value == math.floor(value)
end

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

local function trim(value)
    return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function normalizeName(value)
    return string.lower(trim(value))
end

local function normalizeRealm(value)
    return string.lower(trim(value)):gsub("%s+", "")
end

local function buildCharacterKey(identity)
    if type(identity) ~= "table"
        or type(identity.name) ~= "string"
        or type(identity.realm) ~= "string"
    then
        return nil
    end

    local name = normalizeName(identity.name)
    local realm = normalizeRealm(identity.realm)
    if name == "" or realm == "" then
        return nil
    end

    return name .. "-" .. realm
end

function CharacterState.Create(client, persistence)
    return setmetatable({
        client = client,
        initialized = false,
        persistence = persistence or addon.Persistence.Create(client),
    }, State)
end

function State:Initialize()
    if self.initialized then
        return true
    end

    local identity = self.client:GetCurrentCharacterIdentity()
    local characterKey = buildCharacterKey(identity)
    if characterKey == nil then
        return false, "current character identity is unavailable"
    end

    local database, persistenceError = self.persistence:Load({
        characterKey = characterKey,
        identity = identity,
    })
    if database == nil then
        return false, persistenceError
    end

    local character = database.characters[characterKey]
    if character == nil then
        if self.persistence:IsCharacterQuarantined(characterKey) then
            return false, "current character data is quarantined"
        end
        character = self.persistence:CreateCharacter(characterKey, identity)
        if character == nil then
            return false, "current character data is unavailable"
        end
    end

    self.character = character
    self.characterKey = characterKey
    self.initialized = true
    return true
end

function State:GetPersistenceReport()
    return self.persistence:GetReport()
end

function State:GetCharacterKey()
    return self.characterKey
end

function State:GetCurrentCharacter()
    if not self.initialized then
        return nil
    end

    return copyTable(self.character)
end

function State:SetPercentage(percentage)
    if not self.initialized
        or not isInteger(percentage)
        or percentage > 100
    then
        return false
    end

    self.character.percentage = percentage
    return true
end

function State:SetChatFeedback(enabled)
    if not self.initialized or type(enabled) ~= "boolean" then
        return false
    end

    self.character.chatFeedback = enabled
    return true
end

function State:SetAutoDeposit(enabled)
    if not self.initialized or type(enabled) ~= "boolean" then
        return false
    end

    self.character.autoDeposit = enabled
    return true
end

function State:SetSourceEnabled(source, enabled)
    if not self.initialized
        or SOURCE_DEFAULTS[source] == nil
        or type(enabled) ~= "boolean"
    then
        return false
    end

    self.character.sources[source] = enabled
    return true
end

function State:SetFinancialState(outstandingCopper, fractionalRemainder)
    if not self.initialized
        or not isInteger(outstandingCopper)
        or not isInteger(fractionalRemainder)
        or fractionalRemainder >= 100
    then
        return false
    end

    self.character.outstandingCopper = outstandingCopper
    self.character.fractionalRemainder = fractionalRemainder
    return true
end

local function isResolved(character, operationId)
    local index
    for index = 1, #character.resolvedPayments do
        if character.resolvedPayments[index] == operationId then
            return true
        end
    end
    return false
end

function State:GetPendingPayment()
    if not self.initialized or self.character.pendingPayment == nil then
        return nil
    end

    return copyTable(self.character.pendingPayment)
end

-- A new operation id unique among this character's remembered payments.
function State:NextPaymentOperationId(timestamp)
    if not self.initialized then
        return nil
    end

    local operationId
    repeat
        self.character.paymentSequence = self.character.paymentSequence + 1
        operationId = self.characterKey .. ":" .. tostring(timestamp or 0) .. ":" ..
            tostring(self.character.paymentSequence)
    until not isResolved(self.character, operationId)
    return operationId
end

-- Saves `intent` as the one pending payment. Refused while another payment
-- is pending or when the operation id was already resolved.
function State:BeginPayment(intent)
    if not self.initialized
        or self.character.pendingPayment ~= nil
        or not addon.Persistence.IsPendingPayment(intent)
        or isResolved(self.character, intent.operationId)
    then
        return false
    end

    self.character.pendingPayment = copyTable(intent)
    return true
end

-- Resolves the pending payment `operationId` exactly once. A confirmed
-- payment saves the reduced balance in the same step, so a replayed signal
-- or a reload can never apply it twice.
function State:ResolvePayment(operationId, status, outstandingCopper, fractionalRemainder)
    if not self.initialized then
        return false
    end
    local pending = self.character.pendingPayment
    if pending == nil
        or pending.operationId ~= operationId
        or isResolved(self.character, operationId)
    then
        return false
    end

    if status == "confirmed" then
        if not self:SetFinancialState(outstandingCopper, fractionalRemainder) then
            return false
        end
    end

    local resolved = self.character.resolvedPayments
    table.insert(resolved, operationId)
    while #resolved > addon.Persistence.MAX_RESOLVED_PAYMENTS do
        table.remove(resolved, 1)
    end
    self.character.pendingPayment = nil
    return true
end
