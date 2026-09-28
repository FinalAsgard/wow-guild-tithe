local _, addon = ...

local Persistence = {
    LATEST_SCHEMA_VERSION = 2,
    MAX_SAFE_INTEGER = 9007199254740991,
}
addon.Persistence = Persistence

local Store = {}
Store.__index = Store

local SOURCE_DEFAULTS = {
    auctions = false,
    loot = true,
    mailbox = false,
    miscellaneous = true,
    playerTrades = true,
    quests = true,
    vendorSales = true,
}

local function copyValue(source, ancestors)
    if type(source) ~= "table" then
        return source
    end

    ancestors = ancestors or {}
    if ancestors[source] then
        return nil, "saved data contains a cyclic table"
    end
    ancestors[source] = true

    local result = {}
    local key, value

    for key, value in pairs(source) do
        local copiedKey, keyError = copyValue(key, ancestors)
        if keyError ~= nil then
            ancestors[source] = nil
            return nil, keyError
        end

        local copiedValue, valueError = copyValue(value, ancestors)
        if valueError ~= nil then
            ancestors[source] = nil
            return nil, valueError
        end

        result[copiedKey] = copiedValue
    end

    ancestors[source] = nil
    return result
end

local function isSafeInteger(value)
    return type(value) == "number"
        and value >= 0
        and value <= Persistence.MAX_SAFE_INTEGER
        and value == math.floor(value)
end

local function isPercentage(value)
    return isSafeInteger(value) and value <= 100
end

local function isRemainder(value)
    return isSafeInteger(value) and value < 100
end

local function newReport(schemaVersion)
    return {
        fromSchemaVersion = schemaVersion,
        schemaVersion = Persistence.LATEST_SCHEMA_VERSION,
        migrations = {},
        repairedFields = {},
        quarantinedCharacters = {},
    }
end

local function recordRepair(report, characterKey, field)
    table.insert(report.repairedFields, {
        characterKey = characterKey,
        field = field,
    })
end

local function defaultSources()
    return copyValue(SOURCE_DEFAULTS)
end

local function newCharacter(identity)
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
        sources = defaultSources(),
    }
end

local function migrateVersion1To2(database)
    if database.quarantinedCharacters == nil then
        database.quarantinedCharacters = {}
    end
    database.schemaVersion = 2
end

local MIGRATIONS = {
    [1] = migrateVersion1To2,
}

local function validateQuarantine(database)
    if database.quarantinedCharacters == nil then
        database.quarantinedCharacters = {}
        return true
    end

    if type(database.quarantinedCharacters) ~= "table" then
        return false, "saved data quarantine is invalid"
    end

    local _, entries
    for _, entries in pairs(database.quarantinedCharacters) do
        if type(entries) ~= "table" then
            return false, "saved data quarantine contains an invalid entry"
        end
    end

    return true
end

local function nextInvalidCharacterKey(database)
    local index = 1
    local characterKey

    repeat
        characterKey = "__invalid_character_key_" .. tostring(index)
        index = index + 1
    until database.characters[characterKey] == nil
        and database.quarantinedCharacters[characterKey] == nil

    return characterKey
end

local function isCharacterKey(value)
    if type(value) ~= "string"
        or value ~= string.lower(value)
        or string.find(value, "%s") ~= nil
    then
        return false
    end

    local name, realm = string.match(value, "^([^-]+)%-(.+)$")
    return name ~= nil and realm ~= nil
end

local function quarantineCharacter(database, report, sourceKey, quarantineKey,
    character, reason)
    local entries = database.quarantinedCharacters[quarantineKey]
    if entries == nil then
        entries = {}
        database.quarantinedCharacters[quarantineKey] = entries
    end

    local quarantined = {
        reason = reason,
        record = character,
        schemaVersion = Persistence.LATEST_SCHEMA_VERSION,
    }
    if sourceKey ~= quarantineKey then
        quarantined.originalCharacterKey = sourceKey
    end
    table.insert(entries, quarantined)
    database.characters[sourceKey] = nil
    table.insert(report.quarantinedCharacters, {
        characterKey = tostring(sourceKey),
        quarantineKey = quarantineKey,
        reason = reason,
    })
end

local function repairIdentity(character, characterKey, report, currentCharacter)
    if type(character.identity) ~= "table" then
        character.identity = {}
        recordRepair(report, characterKey, "identity")
    end

    local fields = {
        { key = "displayName", identityKey = "name" },
        { key = "displayRealm", identityKey = "realm" },
        { key = "stableId", identityKey = "stableId" },
    }
    local index
    for index = 1, #fields do
        local field = fields[index]
        local value = character.identity[field.key]
        local valid = value == nil or (type(value) == "string" and value ~= "")
        if not valid then
            character.identity[field.key] = nil
            recordRepair(report, characterKey, "identity." .. field.key)
        end

        if character.identity[field.key] == nil
            and type(currentCharacter) == "table"
            and type(currentCharacter.identity) == "table"
        then
            local replacement = currentCharacter.identity[field.identityKey]
            if type(replacement) == "string" and replacement ~= "" then
                character.identity[field.key] = replacement
                if valid then
                    recordRepair(report, characterKey, "identity." .. field.key)
                end
            end
        end
    end
end

local function repairConfiguration(character, characterKey, report)
    if not isPercentage(character.percentage) then
        character.percentage = 10
        recordRepair(report, characterKey, "percentage")
    end

    if type(character.chatFeedback) ~= "boolean" then
        character.chatFeedback = true
        recordRepair(report, characterKey, "chatFeedback")
    end

    if type(character.sources) ~= "table" then
        character.sources = defaultSources()
        recordRepair(report, characterKey, "sources")
        return
    end

    local source, defaultValue
    for source, defaultValue in pairs(SOURCE_DEFAULTS) do
        if type(character.sources[source]) ~= "boolean" then
            character.sources[source] = defaultValue
            recordRepair(report, characterKey, "sources." .. source)
        end
    end
end

local function validateCharacters(database, report, context)
    if type(database.characters) ~= "table" then
        return false, "saved data character collection is invalid"
    end

    local invalid = {}
    local characterKey, character
    for characterKey, character in pairs(database.characters) do
        local reason
        local quarantineKey = characterKey
        if not isCharacterKey(characterKey) then
            reason = "character key is not normalized"
            quarantineKey = nil
        elseif type(character) ~= "table" then
            reason = "character record is not a table"
        elseif not isSafeInteger(character.outstandingCopper) then
            reason = "outstanding copper is not a non-negative safe integer"
        elseif not isRemainder(character.fractionalRemainder) then
            reason = "fractional remainder is not an integer from 0 through 99"
        end

        if reason ~= nil then
            table.insert(invalid, {
                characterKey = characterKey,
                character = character,
                quarantineKey = quarantineKey,
                reason = reason,
            })
        else
            local currentCharacter
            if type(context) == "table" and context.characterKey == characterKey then
                currentCharacter = context
            end
            repairIdentity(character, characterKey, report, currentCharacter)
            repairConfiguration(character, characterKey, report)
        end
    end

    local index
    for index = 1, #invalid do
        local entry = invalid[index]
        quarantineCharacter(
            database,
            report,
            entry.characterKey,
            entry.quarantineKey or nextInvalidCharacterKey(database),
            entry.character,
            entry.reason
        )
    end

    return true
end

function Persistence.Create(client)
    return setmetatable({ client = client }, Store)
end

function Store:Load(context)
    local source = self.client:GetAccountDatabase()
    if source == nil then
        local database = {
            schemaVersion = Persistence.LATEST_SCHEMA_VERSION,
            characters = {},
            quarantinedCharacters = {},
        }
        if self.client:SetAccountDatabase(database) ~= true then
            return nil, "new saved data could not be stored"
        end

        self.database = database
        self.report = newReport(Persistence.LATEST_SCHEMA_VERSION)
        return database, self.report
    end

    if type(source) ~= "table" then
        return nil, "saved data root is invalid"
    end

    local schemaVersion = source.schemaVersion
    if type(schemaVersion) ~= "number"
        or schemaVersion ~= math.floor(schemaVersion)
        or schemaVersion < 1
    then
        return nil, "saved data uses an unsupported schema"
    end

    if schemaVersion > Persistence.LATEST_SCHEMA_VERSION then
        return nil, "saved data schema is newer than this add-on supports"
    end

    local database, copyError = copyValue(source)
    if database == nil then
        return nil, copyError
    end
    local report = newReport(schemaVersion)

    while database.schemaVersion < Persistence.LATEST_SCHEMA_VERSION do
        local migration = MIGRATIONS[database.schemaVersion]
        if migration == nil then
            return nil, "saved data uses an unsupported schema"
        end

        local previousVersion = database.schemaVersion
        migration(database)
        if database.schemaVersion ~= previousVersion + 1 then
            return nil, "saved data migration did not advance one schema version"
        end
        table.insert(report.migrations,
            tostring(previousVersion) .. " -> " .. tostring(database.schemaVersion))
    end

    local quarantineOk, quarantineError = validateQuarantine(database)
    if not quarantineOk then
        return nil, quarantineError
    end

    local charactersOk, charactersError = validateCharacters(database, report, context)
    if not charactersOk then
        return nil, charactersError
    end

    if self.client:SetAccountDatabase(database) ~= true then
        return nil, "validated saved data could not be stored"
    end

    self.database = database
    self.report = report
    return database, report
end

function Store:CreateCharacter(characterKey, identity)
    if self.database == nil
        or type(characterKey) ~= "string"
        or type(identity) ~= "table"
        or self.database.characters[characterKey] ~= nil
        or self:IsCharacterQuarantined(characterKey)
    then
        return nil
    end

    local character = newCharacter(identity)
    self.database.characters[characterKey] = character
    return character
end

function Store:IsCharacterQuarantined(characterKey)
    return self.database ~= nil
        and self.database.quarantinedCharacters[characterKey] ~= nil
end

function Store:GetReport()
    if self.report == nil then
        return nil
    end

    return copyValue(self.report)
end
