local test = require("tests.test_helper")

local function loadPersistenceModules()
    return test.newAddon(
        "Adapters/WoW.lua",
        "Core/Persistence.lua",
        "Core/CharacterState.lua",
        "Core/Accounting.lua",
        "Core/TitheService.lua"
    )
end

local function newEnvironment(name, realm, database)
    return {
        AsgardsGuildTitheDB = database,
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

    test.assertEqual(3, database.schemaVersion)
    test.assertEqual("1 -> 2", report.migrations[1])
    test.assertEqual("2 -> 3", report.migrations[2])
    test.assertEqual(2, #report.migrations)
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

test.test("missing optional configuration receives defaults without touching money", function()
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

    test.assertEqual(10, repaired.percentage)
    test.assertTrue(repaired.chatFeedback)
    test.assertTrue(repaired.sources.loot)
    test.assertFalse(repaired.sources.auctions)
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

    local first = addon.CharacterState.Create(addon.Compatibility.Create(environment))
    test.assertTrue(first:Initialize())
    test.assertTrue(first:SetPercentage(62))
    test.assertTrue(first:SetSourceEnabled("auctions", false))
    test.assertTrue(first:SetFinancialState(7654321, 9))

    local reloaded = addon.CharacterState.Create(addon.Compatibility.Create(environment))
    test.assertTrue(reloaded:Initialize())
    local character = reloaded:GetCurrentCharacter()

    test.assertEqual(62, character.percentage)
    test.assertFalse(character.sources.auctions)
    test.assertTrue(character.sources.loot)
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

test.test("schema two migrates to schema three with empty payment state", function()
    local addon = loadPersistenceModules()
    local character = completeCharacter()
    local environment = newEnvironment("Jaina", "Camelot", {
        schemaVersion = 2,
        characters = { ["jaina-camelot"] = character },
        quarantinedCharacters = {},
    })

    local database, report = createStore(addon, environment):Load()
    local migrated = database.characters["jaina-camelot"]

    test.assertEqual(3, database.schemaVersion)
    test.assertEqual("2 -> 3", report.migrations[1])
    test.assertEqual(1, #report.migrations)
    test.assertEqual(0, #report.repairedFields)
    test.assertEqual(nil, migrated.pendingPayment)
    test.assertEqual(0, #migrated.resolvedPayments)
    test.assertEqual(0, migrated.paymentSequence)
    test.assertEqual(123456, migrated.outstandingCopper)
    test.assertEqual(78, migrated.fractionalRemainder)
    test.assertEqual(3, environment.AsgardsGuildTitheDB.schemaVersion)

    local snapshot = copy(database)
    local again, againReport = createStore(addon, environment):Load()
    assertDeepEqual(snapshot, again)
    test.assertEqual(0, #againReport.migrations)
    test.assertEqual(0, #againReport.repairedFields)
end)

test.test("a valid pending payment and resolved ids survive reloads unchanged", function()
    local addon = loadPersistenceModules()
    local environment = newEnvironment("Jaina", "Camelot", {
        schemaVersion = 3,
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
