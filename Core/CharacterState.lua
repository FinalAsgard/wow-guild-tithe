local _, addon = ...

local CharacterState = {
    MAX_SAFE_INTEGER = 9007199254740991,
}
addon.CharacterState = CharacterState

local State = {}
State.__index = State

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
    persistence = persistence or addon.Persistence.Create(client)
    return setmetatable({
        client = client,
        financialListeners = {},
        guildListeners = {},
        guildSettings = addon.GuildSettings.Create(persistence),
        initialized = false,
        persistence = persistence,
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
    -- Seeds or adopts the current guild's shared settings at login, then
    -- follows guild membership for the rest of the session.
    self.guildKey = self:CurrentGuildKey()
    if type(self.client.ObserveGuildChanges) == "function" then
        self.client:ObserveGuildChanges(function()
            self:RefreshGuild()
        end)
    end
    return true
end

local function notify(listeners)
    local index
    for index = 1, #listeners do
        -- A failing listener must not block state changes.
        pcall(listeners[index])
    end
end

-- The current guild's settings key, or false while guildless or unknown.
-- Resolving it seeds or adopts the guild's shared settings.
function State:CurrentGuildKey()
    local settings = self:GetTitheSettings()
    return settings and settings.guildKey or false
end

-- Re-reads guild membership, e.g. after joining, leaving, or switching
-- guilds, and tells listeners when the guild in effect changed.
function State:RefreshGuild()
    if not self.initialized then
        return false
    end
    local guildKey = self:CurrentGuildKey()
    if guildKey == self.guildKey then
        return false
    end
    self.guildKey = guildKey
    notify(self.guildListeners)
    return true
end

-- Calls listener() whenever the guild in effect or its shared settings
-- change, so pages showing them can refresh.
function State:OnGuildSettingsChange(listener)
    if type(listener) == "function" then
        table.insert(self.guildListeners, listener)
    end
end

-- The current guild as { name, realm, id }, or nil when guildless or when
-- the client cannot report it yet.
function State:GetGuildIdentity()
    if type(self.client.IsInGuild) ~= "function"
        or type(self.client.GetGuildIdentity) ~= "function"
        or self.client:IsInGuild() ~= true
    then
        return nil
    end
    return self.client:GetGuildIdentity()
end

-- Whether the client reports a guild, even before it can name it.
function State:IsInGuild()
    return type(self.client.IsInGuild) == "function" and self.client:IsInGuild() == true
end

-- The tithe settings in effect, shared by the account's characters in the
-- current guild: { guild, guildKey, percentage, sources }, or nil while
-- guildless or when the guild is unknown or its record is quarantined.
-- A guild with no record yet is created from this character's settings
-- left over from before schema 5, or the defaults; once the character's
-- guild has a record, those leftover fields are removed.
function State:GetTitheSettings()
    if not self.initialized then
        return nil
    end

    local guild = self:GetGuildIdentity()
    if guild == nil then
        return nil
    end

    local settings = self.guildSettings:Get(guild, {
        percentage = self.character.percentage,
        sources = self.character.sources,
    })
    if settings == nil then
        return nil
    end

    self.character.percentage = nil
    self.character.sources = nil
    settings.guild = copyTable(guild)
    return settings
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

-- Changes the current guild's shared percentage; refused while guildless.
function State:SetPercentage(percentage)
    if not isInteger(percentage) or percentage > 100 then
        return false
    end

    local settings = self:GetTitheSettings()
    if settings == nil or not self.guildSettings:SetPercentage(settings.guildKey, percentage) then
        return false
    end
    notify(self.guildListeners)
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

-- Turns one of the current guild's shared sources on or off; refused while
-- guildless.
function State:SetSourceEnabled(source, enabled)
    if not addon.Persistence.IsSource(source) or type(enabled) ~= "boolean" then
        return false
    end

    local settings = self:GetTitheSettings()
    if settings == nil
        or not self.guildSettings:SetSourceEnabled(settings.guildKey, source, enabled)
    then
        return false
    end
    notify(self.guildListeners)
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
    local index
    for index = 1, #self.financialListeners do
        -- A failing listener must not undo or block a saved balance.
        pcall(self.financialListeners[index])
    end
    return true
end

-- Calls listener() after every saved change to the balance, whatever its cause.
function State:OnFinancialChange(listener)
    if type(listener) == "function" then
        table.insert(self.financialListeners, listener)
    end
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

-- The account-wide donation list shared by every character, or nil before
-- state is ready. Only the donation ledger writes to it.
function State:GetDonationRecords()
    if not self.initialized or type(self.persistence.GetDonations) ~= "function" then
        return nil
    end
    return self.persistence:GetDonations()
end

-- The account-wide minimap icon state ({ hide, minimapPos }), shared by
-- every character, or nil before state is ready. It is live: the icon
-- library saves the dragged position straight into it.
function State:GetMinimapState()
    if not self.initialized or type(self.persistence.GetMinimapState) ~= "function" then
        return nil
    end
    return self.persistence:GetMinimapState()
end

-- Shows or hides the minimap icon on every character of the account.
function State:SetMinimapIconShown(shown)
    local iconState = self:GetMinimapState()
    if type(iconState) ~= "table" or type(shown) ~= "boolean" then
        return false
    end
    iconState.hide = not shown
    return true
end
