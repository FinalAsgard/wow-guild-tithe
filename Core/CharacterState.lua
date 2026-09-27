local _, addon = ...

local CharacterState = {
    SCHEMA_VERSION = 1,
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

local function newCharacterRecord(identity)
    return {
        identity = {
            displayName = identity.name,
            displayRealm = identity.realm,
            stableId = identity.stableId,
        },
        percentage = 10,
        outstandingCopper = 0,
        fractionalRemainder = 0,
        chatFeedback = true,
        sources = copyTable(SOURCE_DEFAULTS),
    }
end

function CharacterState.Create(client)
    return setmetatable({
        client = client,
        initialized = false,
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

    local database = self.client:GetAccountDatabase()
    if database == nil then
        database = {
            schemaVersion = CharacterState.SCHEMA_VERSION,
            characters = {},
        }
        self.client:SetAccountDatabase(database)
    end

    if type(database) ~= "table"
        or database.schemaVersion ~= CharacterState.SCHEMA_VERSION
        or type(database.characters) ~= "table"
    then
        return false, "saved data uses an unsupported schema"
    end

    local character = database.characters[characterKey]
    if character == nil then
        character = newCharacterRecord(identity)
        database.characters[characterKey] = character
    elseif type(character) ~= "table" then
        return false, "current character data is unavailable"
    end

    self.character = character
    self.characterKey = characterKey
    self.database = database
    self.initialized = true
    return true
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
