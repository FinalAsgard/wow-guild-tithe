local test = require("tests.test_helper")

local function loadStateModules()
    return test.newAddon(
        "Adapters/WoW.lua",
        "Core/Persistence.lua",
        "Core/CharacterState.lua"
    )
end

local function newEnvironment(name, realm, stableId, database)
    return {
        AsgardsGuildTitheDB = database,
        UnitName = function(unit)
            test.assertEqual("player", unit)
            return name
        end,
        GetRealmName = function()
            return realm
        end,
        UnitGUID = stableId and function(unit)
            test.assertEqual("player", unit)
            return stableId
        end or nil,
    }
end

local function createState(addon, environment)
    local client = addon.Compatibility.Create(environment)
    return addon.CharacterState.Create(client)
end

test.test("fresh characters receive the complete default tithe state", function()
    local addon = loadStateModules()
    local environment = newEnvironment("Arthas", "Camelot", "Player-1")
    local state = createState(addon, environment)

    test.assertTrue(state:Initialize())
    local character = state:GetCurrentCharacter()

    test.assertEqual(2, environment.AsgardsGuildTitheDB.schemaVersion)
    test.assertEqual("arthas-camelot", state:GetCharacterKey())
    test.assertEqual("Arthas", character.identity.displayName)
    test.assertEqual("Camelot", character.identity.displayRealm)
    test.assertEqual("Player-1", character.identity.stableId)
    test.assertEqual(10, character.percentage)
    test.assertEqual(0, character.outstandingCopper)
    test.assertEqual(0, character.fractionalRemainder)
    test.assertTrue(character.chatFeedback)
    test.assertTrue(character.sources.loot)
    test.assertTrue(character.sources.quests)
    test.assertTrue(character.sources.vendorSales)
    test.assertTrue(character.sources.playerTrades)
    test.assertTrue(character.sources.miscellaneous)
    test.assertFalse(character.sources.auctions)
    test.assertFalse(character.sources.mailbox)
end)

test.test("state changes survive reconstruction against the saved database", function()
    local addon = loadStateModules()
    local environment = newEnvironment("Jaina", "Camelot", nil)
    local firstState = createState(addon, environment)

    test.assertTrue(firstState:Initialize())
    test.assertTrue(firstState:SetPercentage(27))
    test.assertTrue(firstState:SetChatFeedback(false))
    test.assertTrue(firstState:SetSourceEnabled("auctions", true))
    test.assertTrue(firstState:SetFinancialState(123456, 73))

    local reloadedEnvironment = newEnvironment(
        "Jaina",
        "Camelot",
        nil,
        environment.AsgardsGuildTitheDB
    )
    local reloadedState = createState(addon, reloadedEnvironment)
    test.assertTrue(reloadedState:Initialize())
    local character = reloadedState:GetCurrentCharacter()

    test.assertEqual(27, character.percentage)
    test.assertFalse(character.chatFeedback)
    test.assertTrue(character.sources.auctions)
    test.assertEqual(123456, character.outstandingCopper)
    test.assertEqual(73, character.fractionalRemainder)
end)

test.test("same-name characters on different realms remain isolated", function()
    local addon = loadStateModules()
    local firstEnvironment = newEnvironment("Valeera", "Realm One", "Player-A")
    local firstState = createState(addon, firstEnvironment)
    test.assertTrue(firstState:Initialize())
    test.assertTrue(firstState:SetPercentage(15))
    test.assertTrue(firstState:SetFinancialState(100, 11))

    local secondEnvironment = newEnvironment(
        "Valeera",
        "Realm Two",
        "Player-B",
        firstEnvironment.AsgardsGuildTitheDB
    )
    local secondState = createState(addon, secondEnvironment)
    test.assertTrue(secondState:Initialize())
    test.assertTrue(secondState:SetPercentage(25))
    test.assertTrue(secondState:SetFinancialState(200, 22))

    local firstReload = createState(addon, newEnvironment(
        "Valeera",
        "Realm One",
        "Player-A",
        firstEnvironment.AsgardsGuildTitheDB
    ))
    test.assertTrue(firstReload:Initialize())

    test.assertEqual("valeera-realmone", firstReload:GetCharacterKey())
    test.assertEqual("valeera-realmtwo", secondState:GetCharacterKey())
    test.assertEqual(15, firstReload:GetCurrentCharacter().percentage)
    test.assertEqual(100, firstReload:GetCurrentCharacter().outstandingCopper)
    test.assertEqual(25, secondState:GetCurrentCharacter().percentage)
    test.assertEqual(200, secondState:GetCurrentCharacter().outstandingCopper)
end)

test.test("normalized name and realm remain the lookup path when stable id changes", function()
    local addon = loadStateModules()
    local firstEnvironment = newEnvironment("Rexxar", "The Venture Co", "Old-GUID")
    local firstState = createState(addon, firstEnvironment)
    test.assertTrue(firstState:Initialize())
    test.assertTrue(firstState:SetPercentage(42))

    local reloadedState = createState(addon, newEnvironment(
        "  REXXAR  ",
        " the  venture co ",
        "New-GUID",
        firstEnvironment.AsgardsGuildTitheDB
    ))
    test.assertTrue(reloadedState:Initialize())
    local character = reloadedState:GetCurrentCharacter()

    test.assertEqual("rexxar-theventureco", reloadedState:GetCharacterKey())
    test.assertEqual(42, character.percentage)
    test.assertEqual("Rexxar", character.identity.displayName)
    test.assertEqual("The Venture Co", character.identity.displayRealm)
    test.assertEqual("Old-GUID", character.identity.stableId)
end)

test.test("callers receive snapshots instead of direct saved-variable records", function()
    local addon = loadStateModules()
    local environment = newEnvironment("Thrall", "Camelot", nil)
    local state = createState(addon, environment)
    test.assertTrue(state:Initialize())

    local snapshot = state:GetCurrentCharacter()
    snapshot.percentage = 99
    snapshot.sources.loot = false

    local unchanged = state:GetCurrentCharacter()
    test.assertEqual(10, unchanged.percentage)
    test.assertTrue(unchanged.sources.loot)
end)

test.test("state interface rejects invalid money, remainder, and configuration values", function()
    local addon = loadStateModules()
    local environment = newEnvironment("Anduin", "Camelot", nil)
    local state = createState(addon, environment)
    test.assertTrue(state:Initialize())

    test.assertFalse(state:SetFinancialState(-1, 0))
    test.assertFalse(state:SetFinancialState(1.5, 0))
    test.assertFalse(state:SetFinancialState(1, -1))
    test.assertFalse(state:SetFinancialState(1, 1.5))
    test.assertFalse(state:SetFinancialState(1, 100))
    test.assertFalse(state:SetFinancialState(addon.CharacterState.MAX_SAFE_INTEGER + 1, 0))
    test.assertFalse(state:SetPercentage(-1))
    test.assertFalse(state:SetPercentage(10.5))
    test.assertFalse(state:SetPercentage(101))
    test.assertFalse(state:SetChatFeedback("yes"))
    test.assertFalse(state:SetSourceEnabled("unknown", true))

    local character = state:GetCurrentCharacter()
    test.assertEqual(0, character.outstandingCopper)
    test.assertEqual(0, character.fractionalRemainder)
    test.assertEqual(10, character.percentage)
    test.assertTrue(character.chatFeedback)
end)

test.test("missing identity or an unsupported schema does not overwrite saved data", function()
    local addon = loadStateModules()
    local futureDatabase = {
        schemaVersion = 99,
        characters = { untouched = true },
    }
    local futureEnvironment = newEnvironment("Malfurion", "Camelot", nil, futureDatabase)
    local futureState = createState(addon, futureEnvironment)

    test.assertFalse(futureState:Initialize())
    test.assertEqual(futureDatabase, futureEnvironment.AsgardsGuildTitheDB)
    test.assertTrue(futureEnvironment.AsgardsGuildTitheDB.characters.untouched)

    local missingIdentityEnvironment = {
        AsgardsGuildTitheDB = futureDatabase,
    }
    local missingIdentityState = createState(addon, missingIdentityEnvironment)
    test.assertFalse(missingIdentityState:Initialize())
    test.assertEqual(futureDatabase, missingIdentityEnvironment.AsgardsGuildTitheDB)
end)
