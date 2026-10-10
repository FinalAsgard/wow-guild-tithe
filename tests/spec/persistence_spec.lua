local test = require("tests.test_helper")

local function loadPersistenceModules()
    return test.newAddon(
        "Adapters/WoW.lua",
        "Core/Persistence.lua",
        "Core/GuildSettings.lua",
        "Core/CharacterState.lua",
        "Core/Accounting.lua",
        "Core/TitheService.lua"
    )
end

-- `guildName` puts the character in that guild on its own realm; without it
-- the client reports no guild API, so characters keep their own settings.
local function newEnvironment(name, realm, database, guildName)
    return {
        AsgardsGuildTitheDB = database,
        IsInGuild = guildName and function()
            return true
        end or nil,
        GetGuildInfo = guildName and function()
            return guildName, "Member", 3, nil
        end or nil,
        UnitName = function()
            return name or "Jaina"
        end,
        GetRealmName = function()
            return realm or "Camelot"
        end,
    }
end

local function completeCharacter(overrides)
    local character = {
        identity = {
            displayName = "Jaina",
            displayRealm = "Camelot",
            stableId = "Player-7",
            portrait = "mage",
        },
        percentage = 37,
        outstandingCopper = 123456,
        fractionalRemainder = 78,
        chatFeedback = false,
        autoDeposit = false,
        sources = {
            auctions = true,
            loot = false,
            mailbox = true,
            miscellaneous = false,
            playerTrades = false,
            quests = false,
            vendorSales = false,
            futureSource = "preserved",
        },
        displayMetadata = { note = "preserve me" },
    }

    local key, value
    for key, value in pairs(overrides or {}) do
        character[key] = value
    end
    return character
end

local function copy(value)
    if type(value) ~= "table" then
        return value
    end

    local result = {}
    local key, child
    for key, child in pairs(value) do
        result[copy(key)] = copy(child)
    end
    return result
end

local function assertDeepEqual(expected, actual, path)
    path = path or "value"
    test.assertEqual(type(expected), type(actual), path .. " type")
    if type(expected) ~= "table" then
        test.assertEqual(expected, actual, path)
        return
    end

    local key, expectedValue
    for key, expectedValue in pairs(expected) do
        assertDeepEqual(expectedValue, actual[key], path .. "." .. tostring(key))
    end
    for key in pairs(actual) do
        if expected[key] == nil then
            error(path .. " has unexpected key " .. tostring(key), 2)
        end
    end
end

local function createStore(addon, environment)
    return addon.Persistence.Create(addon.Compatibility.Create(environment))
end

test.test("schema one migrates to the latest schema without losing recognized or display data", function()
    local addon = loadPersistenceModules()
    local character = completeCharacter()
    local environment = newEnvironment("Jaina", "Camelot", {
        schemaVersion = 1,
        characters = {
            ["jaina-camelot"] = character,
        },
        accountMetadata = { imported = true },
    })
    local store = createStore(addon, environment)

    local database, report = store:Load()

    test.assertEqual(5, database.schemaVersion)
    test.assertEqual("1 -> 2", report.migrations[1])
    test.assertEqual("2 -> 3", report.migrations[2])
    test.assertEqual("3 -> 4", report.migrations[3])
    test.assertEqual("4 -> 5", report.migrations[4])
    test.assertEqual(4, #report.migrations)
    test.assertEqual(0, #report.repairedFields)
    test.assertEqual(37, database.characters["jaina-camelot"].percentage)
    test.assertEqual(123456, database.characters["jaina-camelot"].outstandingCopper)
    test.assertEqual(78, database.characters["jaina-camelot"].fractionalRemainder)
    test.assertFalse(database.characters["jaina-camelot"].chatFeedback)
    test.assertTrue(database.characters["jaina-camelot"].sources.auctions)
    test.assertEqual("mage", database.characters["jaina-camelot"].identity.portrait)
    test.assertEqual("preserve me",
        database.characters["jaina-camelot"].displayMetadata.note)
    test.assertTrue(database.accountMetadata.imported)
    test.assertEqual("table", type(database.quarantinedCharacters))
end)

test.test("loading a migrated database repeatedly is structurally idempotent", function()
    local addon = loadPersistenceModules()
    local environment = newEnvironment("Jaina", "Camelot", {
        schemaVersion = 1,
        characters = {
            ["jaina-camelot"] = completeCharacter(),
        },
    })

    local firstDatabase = createStore(addon, environment):Load()
    local firstSnapshot = copy(firstDatabase)
    local secondDatabase, secondReport = createStore(addon, environment):Load()

    assertDeepEqual(firstSnapshot, secondDatabase)
    test.assertEqual(0, #secondReport.migrations)
    test.assertEqual(0, #secondReport.repairedFields)
    test.assertEqual(0, #secondReport.quarantinedCharacters)
end)

test.test("configuration repair defaults only invalid fields and preserves valid siblings", function()
    local addon = loadPersistenceModules()
    local character = completeCharacter({
        percentage = "37",
        chatFeedback = false,
        sources = {
            auctions = true,
            loot = false,
            mailbox = "yes",
            miscellaneous = false,
            playerTrades = false,
            quests = false,
            vendorSales = false,
            futureSource = "preserved",
        },
    })
    character.identity.displayName = 42
    local environment = newEnvironment("Jaina", "Camelot", {
        schemaVersion = 2,
        characters = { ["jaina-camelot"] = character },
        quarantinedCharacters = {},
    })

    local database, report = createStore(addon, environment):Load({
        characterKey = "jaina-camelot",
        identity = { name = "Jaina", realm = "Camelot" },
    })
    local repaired = database.characters["jaina-camelot"]

    test.assertEqual(10, repaired.percentage)
    test.assertFalse(repaired.chatFeedback)
    test.assertTrue(repaired.sources.auctions)
    test.assertFalse(repaired.sources.loot)
    test.assertFalse(repaired.sources.miscellaneous)
    test.assertFalse(repaired.sources.playerTrades)
    test.assertFalse(repaired.sources.quests)
    test.assertFalse(repaired.sources.vendorSales)
    test.assertFalse(repaired.sources.mailbox)
    test.assertEqual("preserved", repaired.sources.futureSource)
    test.assertEqual("Jaina", repaired.identity.displayName)
    test.assertEqual("Camelot", repaired.identity.displayRealm)
    test.assertEqual(123456, repaired.outstandingCopper)
    test.assertEqual(78, repaired.fractionalRemainder)
    test.assertEqual(3, #report.repairedFields)
end)

test.test("missing optional configuration receives defaults and absent tithe settings stay absent", function()
    local addon = loadPersistenceModules()
    local environment = newEnvironment("Jaina", "Camelot", {
        schemaVersion = 2,
        characters = {
            ["jaina-camelot"] = {
                outstandingCopper = 987654,
                fractionalRemainder = 12,
            },
        },
        quarantinedCharacters = {},
    })

    local database = createStore(addon, environment):Load()
    local repaired = database.characters["jaina-camelot"]

    -- Percentage and sources belong to the guild since schema 5.
    test.assertEqual(nil, repaired.percentage)
    test.assertEqual(nil, repaired.sources)
    test.assertTrue(repaired.chatFeedback)
    test.assertTrue(repaired.autoDeposit)
    test.assertEqual(987654, repaired.outstandingCopper)
    test.assertEqual(12, repaired.fractionalRemainder)
end)

test.test("unrecoverable financial records are quarantined without blocking valid characters", function()
    local addon = loadPersistenceModules()
    local invalid = completeCharacter({ outstandingCopper = "123456" })
    local valid = completeCharacter({ percentage = 19, outstandingCopper = 700 })
    local environment = newEnvironment("Thrall", "Camelot", {
        schemaVersion = 2,
        characters = {
            ["jaina-camelot"] = invalid,
            ["thrall-camelot"] = valid,
        },
        quarantinedCharacters = {},
    })

    local database, report = createStore(addon, environment):Load()

    test.assertEqual(nil, database.characters["jaina-camelot"])
    test.assertEqual(19, database.characters["thrall-camelot"].percentage)
    test.assertEqual(700, database.characters["thrall-camelot"].outstandingCopper)
    test.assertEqual(1, #database.quarantinedCharacters["jaina-camelot"])
    test.assertEqual("123456",
        database.quarantinedCharacters["jaina-camelot"][1].record.outstandingCopper)
    test.assertContains(
        database.quarantinedCharacters["jaina-camelot"][1].reason,
        "outstanding copper"
    )
    test.assertEqual(1, #report.quarantinedCharacters)

    local state = addon.CharacterState.Create(addon.Compatibility.Create(environment))
    test.assertTrue(state:Initialize())
    test.assertEqual(19, state:GetCurrentCharacter().percentage)
end)

test.test("malformed character keys are preserved in quarantine without blocking valid records", function()
    local addon = loadPersistenceModules()
    local environment = newEnvironment("Thrall", "Camelot", {
        schemaVersion = 2,
        characters = {
            [42] = completeCharacter({ outstandingCopper = 4200 }),
            ["Jaina-Camelot"] = completeCharacter({ outstandingCopper = 1700 }),
            ["thrall-camelot"] = completeCharacter({ outstandingCopper = 700 }),
        },
        quarantinedCharacters = {},
    })

    local database, report = createStore(addon, environment):Load()

    test.assertEqual(700, database.characters["thrall-camelot"].outstandingCopper)
    test.assertEqual(nil, database.characters[42])
    test.assertEqual(nil, database.characters["Jaina-Camelot"])
    test.assertEqual(2, #report.quarantinedCharacters)

    local preserved = {}
    local _, entries
    for _, entries in pairs(database.quarantinedCharacters) do
        local entry = entries[1]
        if entry ~= nil and entry.originalCharacterKey ~= nil then
            preserved[tostring(entry.originalCharacterKey)] = entry.record.outstandingCopper
            test.assertContains(entry.reason, "key")
        end
    end
    test.assertEqual(4200, preserved["42"])
    test.assertEqual(1700, preserved["Jaina-Camelot"])
end)

test.test("a quarantined current character stays unavailable to state and accounting", function()
    local addon = loadPersistenceModules()
    local environment = newEnvironment("Jaina", "Camelot", {
        schemaVersion = 2,
        characters = {
            ["jaina-camelot"] = completeCharacter({ fractionalRemainder = 100 }),
        },
        quarantinedCharacters = {},
    })
    local state = addon.CharacterState.Create(addon.Compatibility.Create(environment))

    local initialized, stateError = state:Initialize()

    test.assertFalse(initialized)
    test.assertContains(stateError, "quarantined")
    test.assertEqual(nil, state:GetCurrentCharacter())
    test.assertFalse(state:SetFinancialState(0, 0))
    local result, accountingError = addon.TitheService.Create(
        state,
        addon.Accounting
    ):AccrueEligibleCopper(100)
    test.assertEqual(nil, result)
    test.assertEqual("current character state is unavailable", accountingError)
    test.assertEqual(100,
        environment.AsgardsGuildTitheDB.quarantinedCharacters["jaina-camelot"][1]
            .record.fractionalRemainder)
end)

test.test("migration and validation failure leave the original database untouched", function()
    local addon = loadPersistenceModules()
    local original = {
        schemaVersion = 1,
        characters = "not a character collection",
        sentinel = { value = 17 },
    }
    local snapshot = copy(original)
    local environment = newEnvironment("Jaina", "Camelot", original)

    local database, loadError = createStore(addon, environment):Load()

    test.assertEqual(nil, database)
    test.assertContains(loadError, "character collection")
    test.assertEqual(original, environment.AsgardsGuildTitheDB)
    assertDeepEqual(snapshot, environment.AsgardsGuildTitheDB)
end)

test.test("cyclic saved data is rejected without mutation or writeback", function()
    local addon = loadPersistenceModules()
    local original = {
        schemaVersion = 2,
        characters = {},
        quarantinedCharacters = {},
    }
    original.metadata = { parent = original }
    local writes = 0
    local client = {
        GetAccountDatabase = function()
            return original
        end,
        SetAccountDatabase = function()
            writes = writes + 1
            return true
        end,
    }

    local database, loadError = addon.Persistence.Create(client):Load()

    test.assertEqual(nil, database)
    test.assertContains(loadError, "cyclic")
    test.assertEqual(0, writes)
    test.assertEqual(original, original.metadata.parent)
end)

test.test("version one migration preserves an existing quarantine", function()
    local addon = loadPersistenceModules()
    local quarantined = {
        ["jaina-camelot"] = {
            { reason = "previous failure", record = { raw = true } },
        },
    }
    local environment = newEnvironment("Thrall", "Camelot", {
        schemaVersion = 1,
        characters = {
            ["thrall-camelot"] = completeCharacter(),
        },
        quarantinedCharacters = quarantined,
    })

    local database = createStore(addon, environment):Load()

    test.assertEqual("previous failure",
        database.quarantinedCharacters["jaina-camelot"][1].reason)
    test.assertTrue(database.quarantinedCharacters["jaina-camelot"][1].record.raw)
end)

test.test("future schemas are returned as incompatible without writeback or mutation", function()
    local addon = loadPersistenceModules()
    local future = {
        schemaVersion = 99,
        characters = {
            ["jaina-camelot"] = {
                outstandingCopper = "future representation",
                nested = { 1, false, "three" },
            },
        },
        futureField = { enabled = true },
    }
    local snapshot = copy(future)
    local writes = 0
    local client = {
        GetAccountDatabase = function()
            return future
        end,
        SetAccountDatabase = function()
            writes = writes + 1
            return true
        end,
    }

    local database, loadError = addon.Persistence.Create(client):Load()

    test.assertEqual(nil, database)
    test.assertContains(loadError, "newer")
    test.assertEqual(0, writes)
    assertDeepEqual(snapshot, future)
end)

test.test("repaired state survives a reload round trip without further changes", function()
    local addon = loadPersistenceModules()
    local environment = newEnvironment("Jaina", "Camelot", {
        schemaVersion = 1,
        characters = {
            ["jaina-camelot"] = completeCharacter({
                percentage = nil,
                chatFeedback = "invalid",
            }),
        },
    })
    environment.AsgardsGuildTitheDB.characters["jaina-camelot"].sources.loot = nil
    environment.IsInGuild = function()
        return true
    end
    environment.GetGuildInfo = function()
        return "Knights of Camelot", "Member", 3, nil
    end

    local first = addon.CharacterState.Create(addon.Compatibility.Create(environment))
    test.assertTrue(first:Initialize())
    test.assertTrue(first:SetPercentage(62))
    test.assertTrue(first:SetSourceEnabled("auctions", false))
    test.assertTrue(first:SetFinancialState(7654321, 9))

    local reloaded = addon.CharacterState.Create(addon.Compatibility.Create(environment))
    test.assertTrue(reloaded:Initialize())
    local character = reloaded:GetCurrentCharacter()
    local settings = reloaded:GetTitheSettings()

    test.assertEqual(62, settings.percentage)
    test.assertFalse(settings.sources.auctions)
    test.assertTrue(settings.sources.loot)
    test.assertTrue(character.chatFeedback)
    test.assertEqual(7654321, character.outstandingCopper)
    test.assertEqual(9, character.fractionalRemainder)
    test.assertEqual(0, #reloaded:GetPersistenceReport().repairedFields)
end)

local function pendingPayment(overrides)
    local intent = {
        operationId = "jaina-camelot:1790001000:1",
        amount = 5000,
        method = "button",
        character = { key = "jaina-camelot", name = "Jaina", realm = "Camelot" },
        guild = { name = "Knights of Camelot", realm = "Camelot" },
        moneyBefore = 100000,
        createdAt = 1790001000,
        status = "pending",
    }
    local key, value
    for key, value in pairs(overrides or {}) do
        intent[key] = value
    end
    return intent
end

test.test("schema two migrates forward with empty payment state", function()
    local addon = loadPersistenceModules()
    local character = completeCharacter()
    local environment = newEnvironment("Jaina", "Camelot", {
        schemaVersion = 2,
        characters = { ["jaina-camelot"] = character },
        quarantinedCharacters = {},
    })

    local database, report = createStore(addon, environment):Load()
    local migrated = database.characters["jaina-camelot"]

    test.assertEqual(5, database.schemaVersion)
    test.assertEqual("2 -> 3", report.migrations[1])
    test.assertEqual("3 -> 4", report.migrations[2])
    test.assertEqual("4 -> 5", report.migrations[3])
    test.assertEqual(3, #report.migrations)
    test.assertEqual(0, #report.repairedFields)
    test.assertEqual(nil, migrated.pendingPayment)
    test.assertEqual(0, #migrated.resolvedPayments)
    test.assertEqual(0, migrated.paymentSequence)
    test.assertEqual(123456, migrated.outstandingCopper)
    test.assertEqual(78, migrated.fractionalRemainder)
    test.assertEqual(5, environment.AsgardsGuildTitheDB.schemaVersion)

    local snapshot = copy(database)
    local again, againReport = createStore(addon, environment):Load()
    assertDeepEqual(snapshot, again)
    test.assertEqual(0, #againReport.migrations)
    test.assertEqual(0, #againReport.repairedFields)
end)

test.test("a valid pending payment and resolved ids survive reloads unchanged", function()
    local addon = loadPersistenceModules()
    local environment = newEnvironment("Jaina", "Camelot", {
        schemaVersion = 5,
        donations = {},
        quarantinedDonations = {},
        guilds = {},
        quarantinedGuilds = {},
        ui = { minimap = { hide = false } },
        characters = {
            ["jaina-camelot"] = completeCharacter({
                pendingPayment = pendingPayment({
                    guild = { id = "42", name = "Knights of Camelot", realm = "Camelot" },
                }),
                resolvedPayments = { "jaina-camelot:1790000000:1" },
                paymentSequence = 1,
            }),
        },
        quarantinedCharacters = {},
    })
    local snapshot = copy(environment.AsgardsGuildTitheDB)

    local database, report = createStore(addon, environment):Load()

    assertDeepEqual(snapshot, database)
    test.assertEqual(0, #report.repairedFields)
end)

test.test("unreadable payment state is dropped without touching the balance", function()
    local addon = loadPersistenceModules()
    local cases = {
        { field = "pendingPayment", value = pendingPayment({ amount = 0 }) },
        { field = "pendingPayment", value = pendingPayment({ method = "wire" }) },
        { field = "pendingPayment", value = pendingPayment({ status = "confirmed" }) },
        { field = "pendingPayment", value = pendingPayment({ guild = { name = "Knights" } }) },
        { field = "pendingPayment", value = "pending" },
        { field = "resolvedPayments", value = { "ok", 7 } },
        { field = "resolvedPayments", value = { first = "not a list" } },
        { field = "paymentSequence", value = -1 },
    }
    local index
    for index = 1, #cases do
        local case = cases[index]
        local character = completeCharacter({ resolvedPayments = {}, paymentSequence = 3 })
        character[case.field] = case.value
        local environment = newEnvironment("Jaina", "Camelot", {
            schemaVersion = 3,
            characters = { ["jaina-camelot"] = character },
            quarantinedCharacters = {},
        })

        local database, report = createStore(addon, environment):Load()
        local repaired = database.characters["jaina-camelot"]

        test.assertEqual(1, #report.repairedFields, "case " .. index)
        test.assertEqual(case.field, report.repairedFields[1].field, "case " .. index)
        test.assertEqual(nil, repaired.pendingPayment, "case " .. index)
        test.assertEqual("table", type(repaired.resolvedPayments), "case " .. index)
        test.assertEqual(123456, repaired.outstandingCopper, "case " .. index)
        test.assertEqual(78, repaired.fractionalRemainder, "case " .. index)
    end
end)

test.test("the schema after the latest is incompatible without writeback", function()
    local addon = loadPersistenceModules()
    local future = {
        schemaVersion = addon.Persistence.LATEST_SCHEMA_VERSION + 1,
        characters = { ["jaina-camelot"] = completeCharacter() },
    }
    local snapshot = copy(future)
    local writes = 0
    local client = {
        GetAccountDatabase = function()
            return future
        end,
        SetAccountDatabase = function()
            writes = writes + 1
            return true
        end,
    }

    local database, loadError = addon.Persistence.Create(client):Load()

    test.assertEqual(nil, database)
    test.assertContains(loadError, "newer")
    test.assertEqual(0, writes)
    assertDeepEqual(snapshot, future)
end)

test.test("a payment resolves once and its operation id is never reused", function()
    local addon = loadPersistenceModules()
    local environment = newEnvironment("Jaina", "Camelot", nil)
    local state = addon.CharacterState.Create(addon.Compatibility.Create(environment))
    test.assertTrue(state:Initialize())
    test.assertTrue(state:SetFinancialState(5000, 40))

    local operationId = state:NextPaymentOperationId(1790001000)
    local intent = pendingPayment({ operationId = operationId })
    test.assertTrue(state:BeginPayment(intent))
    test.assertFalse(state:BeginPayment(pendingPayment({ operationId = "other" })))

    test.assertTrue(state:ResolvePayment(operationId, "confirmed", 0, 40))
    test.assertFalse(state:ResolvePayment(operationId, "confirmed", 0, 40))
    test.assertEqual(nil, state:GetPendingPayment())
    test.assertEqual(0, state:GetCurrentCharacter().outstandingCopper)

    -- A replayed intent with a resolved id can never be pending again.
    test.assertFalse(state:BeginPayment(intent))
    test.assertTrue(state:NextPaymentOperationId(1790001000) ~= operationId)

    local index
    for index = 1, addon.Persistence.MAX_RESOLVED_PAYMENTS + 5 do
        local id = state:NextPaymentOperationId(1790002000)
        test.assertTrue(state:BeginPayment(pendingPayment({ operationId = id })))
        test.assertTrue(state:ResolvePayment(id, "expired"))
    end
    test.assertEqual(addon.Persistence.MAX_RESOLVED_PAYMENTS,
        #state:GetCurrentCharacter().resolvedPayments)
    test.assertEqual(0, state:GetCurrentCharacter().outstandingCopper)
end)

test.test("existing characters gain auto-deposit on through field repair", function()
    local addon = loadPersistenceModules()
    local character = completeCharacter({ resolvedPayments = {}, paymentSequence = 2 })
    character.autoDeposit = nil
    local environment = newEnvironment("Jaina", "Camelot", {
        schemaVersion = 3,
        characters = { ["jaina-camelot"] = character },
        quarantinedCharacters = {},
    })

    local database, report = createStore(addon, environment):Load()
    local repaired = database.characters["jaina-camelot"]

    test.assertTrue(repaired.autoDeposit)
    test.assertEqual(1, #report.repairedFields)
    test.assertEqual("autoDeposit", report.repairedFields[1].field)
    test.assertEqual(37, repaired.percentage)
    test.assertFalse(repaired.chatFeedback)
    test.assertTrue(repaired.sources.auctions)
    test.assertEqual(123456, repaired.outstandingCopper)
    test.assertEqual(78, repaired.fractionalRemainder)
end)

test.test("the auto-deposit setting is saved per character and rejects non-booleans", function()
    local addon = loadPersistenceModules()
    local environment = newEnvironment("Jaina", "Camelot", nil)
    local state = addon.CharacterState.Create(addon.Compatibility.Create(environment))
    test.assertTrue(state:Initialize())
    test.assertTrue(state:GetCurrentCharacter().autoDeposit)

    test.assertFalse(state:SetAutoDeposit("no"))
    test.assertTrue(state:SetAutoDeposit(false))

    local reloaded = addon.CharacterState.Create(addon.Compatibility.Create(environment))
    test.assertTrue(reloaded:Initialize())
    test.assertFalse(reloaded:GetCurrentCharacter().autoDeposit)
end)

local function versionFourDatabase()
    return {
        schemaVersion = 4,
        characters = {
            ["jaina-camelot"] = completeCharacter({
                pendingPayment = pendingPayment(),
                resolvedPayments = { "jaina-camelot:1790000000:1" },
                paymentSequence = 1,
            }),
        },
        quarantinedCharacters = {},
        donations = {
            {
                operationId = "jaina-camelot:1790000000:1",
                timestamp = 1790000004,
                amount = 5000,
                method = "button",
                character = { key = "jaina-camelot", name = "Jaina", realm = "Camelot" },
                guild = { name = "Knights of Camelot", realm = "Camelot" },
            },
        },
        quarantinedDonations = {},
    }
end

test.test("schema four gains guild and UI tables and leaves characters and the ledger unchanged", function()
    local addon = loadPersistenceModules()
    local source = versionFourDatabase()
    local before = copy(source)
    local environment = newEnvironment("Jaina", "Camelot", source)

    local database, report = createStore(addon, environment):Load()

    test.assertEqual(5, database.schemaVersion)
    test.assertEqual("4 -> 5", report.migrations[1])
    test.assertEqual(1, #report.migrations)
    test.assertEqual(0, #report.repairedFields)
    assertDeepEqual({}, database.guilds)
    assertDeepEqual({}, database.quarantinedGuilds)
    assertDeepEqual({ minimap = { hide = false } }, database.ui)
    assertDeepEqual(before.characters, database.characters)
    assertDeepEqual(before.donations, database.donations)
    assertDeepEqual(before.quarantinedDonations, database.quarantinedDonations)

    local snapshot = copy(database)
    local again, againReport = createStore(addon, environment):Load()
    assertDeepEqual(snapshot, again)
    test.assertEqual(0, #againReport.migrations)
end)

test.test("a fresh install starts at schema five with empty guild and default UI tables", function()
    local addon = loadPersistenceModules()
    local environment = newEnvironment("Jaina", "Camelot", nil)

    local database = createStore(addon, environment):Load()

    test.assertEqual(5, database.schemaVersion)
    assertDeepEqual({}, database.guilds)
    assertDeepEqual({}, database.quarantinedGuilds)
    assertDeepEqual({ minimap = { hide = false } }, database.ui)
end)

local function versionFiveDatabase(guilds, ui)
    return {
        schemaVersion = 5,
        characters = {},
        quarantinedCharacters = {},
        donations = {},
        quarantinedDonations = {},
        guilds = guilds,
        quarantinedGuilds = {},
        ui = ui or { minimap = { hide = false } },
    }
end

test.test("invalid guild settings are repaired field by field and reported", function()
    local addon = loadPersistenceModules()
    local environment = newEnvironment("Jaina", "Camelot", versionFiveDatabase({
        ["knights of camelot-camelot"] = {
            identity = { displayName = "Knights of Camelot", displayRealm = "Camelot", id = 42 },
            percentage = 140,
            sources = {
                auctions = true,
                loot = "yes",
                futureSource = "preserved",
            },
            note = "preserve me",
        },
        ["horde lords-camelot"] = {
            percentage = 12,
            sources = "broken",
        },
    }))

    local database, report = createStore(addon, environment):Load()
    local knights = database.guilds["knights of camelot-camelot"]
    local horde = database.guilds["horde lords-camelot"]

    test.assertEqual(10, knights.percentage)
    test.assertTrue(knights.sources.auctions)
    test.assertTrue(knights.sources.loot)
    test.assertFalse(knights.sources.mailbox)
    test.assertEqual("preserved", knights.sources.futureSource)
    test.assertEqual("preserve me", knights.note)
    test.assertEqual(nil, knights.identity.id)
    test.assertEqual("Knights of Camelot", knights.identity.displayName)
    test.assertEqual(12, horde.percentage)
    test.assertTrue(horde.sources.loot)
    test.assertFalse(horde.sources.auctions)

    local repaired = {}
    local index
    for index = 1, #report.repairedFields do
        local entry = report.repairedFields[index]
        repaired[tostring(entry.guildKey) .. ":" .. entry.field] = true
    end
    test.assertTrue(repaired["knights of camelot-camelot:percentage"])
    test.assertTrue(repaired["knights of camelot-camelot:sources.loot"])
    test.assertTrue(repaired["knights of camelot-camelot:sources.mailbox"])
    test.assertTrue(repaired["knights of camelot-camelot:identity.id"])
    test.assertTrue(repaired["horde lords-camelot:identity"])
    test.assertTrue(repaired["horde lords-camelot:sources"])
end)

test.test("unreadable guild records are quarantined intact and valid guilds still load", function()
    local addon = loadPersistenceModules()
    local environment = newEnvironment("Jaina", "Camelot", versionFiveDatabase({
        ["knights of camelot-camelot"] = "corrupted",
        ["Not Normalized-Camelot"] = { percentage = 20, sources = {} },
        ["horde lords-camelot"] = { identity = {}, percentage = 12, sources = {} },
    }))

    local database, report = createStore(addon, environment):Load()

    test.assertEqual(nil, database.guilds["knights of camelot-camelot"])
    test.assertEqual(nil, database.guilds["Not Normalized-Camelot"])
    test.assertEqual(12, database.guilds["horde lords-camelot"].percentage)
    test.assertEqual("corrupted",
        database.quarantinedGuilds["knights of camelot-camelot"][1].record)
    test.assertContains(database.quarantinedGuilds["knights of camelot-camelot"][1].reason, "not a table")
    local moved = database.quarantinedGuilds["__invalid_guild_key_1"][1]
    test.assertEqual("Not Normalized-Camelot", moved.originalGuildKey)
    test.assertEqual(20, moved.record.percentage)
    test.assertEqual(2, #report.quarantinedGuilds)

    local snapshot = copy(database)
    local again, againReport = createStore(addon, environment):Load()
    assertDeepEqual(snapshot, again)
    test.assertEqual(0, #againReport.quarantinedGuilds)
end)

test.test("a guild collection or UI table that cannot be read is replaced without blocking loading", function()
    local addon = loadPersistenceModules()
    local environment = newEnvironment("Jaina", "Camelot", versionFiveDatabase("corrupted", "broken"))

    local database, report = createStore(addon, environment):Load()

    assertDeepEqual({}, database.guilds)
    assertDeepEqual({ minimap = { hide = false } }, database.ui)
    test.assertEqual("corrupted", database.quarantinedGuilds["__invalid_guild_key_1"][1].record)
    test.assertEqual(1, #report.quarantinedGuilds)
end)
