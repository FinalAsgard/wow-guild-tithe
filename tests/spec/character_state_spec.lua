local test = require("tests.test_helper")

local function loadStateModules()
    return test.newAddon(
        "Adapters/WoW.lua",
        "Core/Persistence.lua",
        "Core/GuildSettings.lua",
        "Core/CharacterState.lua"
    )
end

-- `membership` is the player's guild: { name, realm } (realm optional, as
-- GetGuildInfo leaves it out for the player's own realm), or false for a
-- guildless character. Tests may change its fields to move guilds.
local function newEnvironment(name, realm, stableId, database, membership)
    if membership == nil then
        membership = { name = "Knights of Camelot" }
    end
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
        IsInGuild = function()
            return membership ~= false and membership.name ~= nil
        end,
        GetGuildInfo = function()
            if membership == false or membership.name == nil then
                return nil
            end
            return membership.name, "Member", 3, membership.realm
        end,
    }
end

local function createState(addon, environment)
    local client = addon.Compatibility.Create(environment)
    return addon.CharacterState.Create(client)
end

local function reload(addon, name, realm, database, membership)
    local state = createState(addon, newEnvironment(name, realm, nil, database, membership))
    test.assertTrue(state:Initialize())
    return state
end

-- A schema-4 database whose characters still carry their own settings.
local function versionFourDatabase(characters)
    return {
        schemaVersion = 4,
        characters = characters,
        quarantinedCharacters = {},
        donations = {},
        quarantinedDonations = {},
    }
end

local function legacyCharacter(name, percentage, auctions, outstandingCopper)
    return {
        identity = { displayName = name, displayRealm = "Camelot" },
        percentage = percentage,
        outstandingCopper = outstandingCopper or 0,
        fractionalRemainder = 0,
        chatFeedback = true,
        autoDeposit = true,
        sources = {
            auctions = auctions,
            loot = true,
            mailbox = false,
            miscellaneous = true,
            playerTrades = true,
            quests = true,
            vendorSales = true,
        },
        resolvedPayments = {},
        paymentSequence = 0,
    }
end

test.test("fresh characters receive the complete default tithe state", function()
    local addon = loadStateModules()
    local environment = newEnvironment("Arthas", "Camelot", "Player-1")
    local state = createState(addon, environment)

    test.assertTrue(state:Initialize())
    local character = state:GetCurrentCharacter()
    local settings = state:GetTitheSettings()

    test.assertEqual(5, environment.AsgardsGuildTitheDB.schemaVersion)
    test.assertEqual("arthas-camelot", state:GetCharacterKey())
    test.assertEqual("Arthas", character.identity.displayName)
    test.assertEqual("Camelot", character.identity.displayRealm)
    test.assertEqual("Player-1", character.identity.stableId)
    test.assertEqual(0, character.outstandingCopper)
    test.assertEqual(0, character.fractionalRemainder)
    test.assertTrue(character.chatFeedback)
    test.assertEqual(nil, character.percentage)
    test.assertEqual(nil, character.sources)

    test.assertEqual("knights of camelot-camelot", settings.guildKey)
    test.assertEqual("Knights of Camelot", settings.guild.name)
    test.assertEqual(10, settings.percentage)
    test.assertTrue(settings.sources.loot)
    test.assertTrue(settings.sources.quests)
    test.assertTrue(settings.sources.vendorSales)
    test.assertTrue(settings.sources.playerTrades)
    test.assertTrue(settings.sources.miscellaneous)
    test.assertFalse(settings.sources.auctions)
    test.assertFalse(settings.sources.mailbox)
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

    local reloadedState = reload(addon, "Jaina", "Camelot", environment.AsgardsGuildTitheDB)
    local character = reloadedState:GetCurrentCharacter()
    local settings = reloadedState:GetTitheSettings()

    test.assertEqual(27, settings.percentage)
    test.assertTrue(settings.sources.auctions)
    test.assertFalse(character.chatFeedback)
    test.assertEqual(123456, character.outstandingCopper)
    test.assertEqual(73, character.fractionalRemainder)
end)

test.test("two characters in one guild share settings but keep their own balance", function()
    local addon = loadStateModules()
    local environment = newEnvironment("Jaina", "Camelot", nil)
    local jaina = createState(addon, environment)
    test.assertTrue(jaina:Initialize())
    test.assertTrue(jaina:SetPercentage(15))
    test.assertTrue(jaina:SetSourceEnabled("loot", false))
    test.assertTrue(jaina:SetChatFeedback(false))
    test.assertTrue(jaina:SetFinancialState(500, 0))

    local thrall = reload(addon, "Thrall", "Camelot", environment.AsgardsGuildTitheDB)
    test.assertEqual(15, thrall:GetTitheSettings().percentage)
    test.assertFalse(thrall:GetTitheSettings().sources.loot)
    test.assertTrue(thrall:GetCurrentCharacter().chatFeedback)
    test.assertEqual(0, thrall:GetCurrentCharacter().outstandingCopper)

    test.assertTrue(thrall:SetPercentage(40))
    local jainaAgain = reload(addon, "Jaina", "Camelot", thrall.persistence.database)
    test.assertEqual(40, jainaAgain:GetTitheSettings().percentage)
    test.assertEqual(500, jainaAgain:GetCurrentCharacter().outstandingCopper)
end)

test.test("characters in different guilds, or same-name guilds on two realms, keep separate settings", function()
    local addon = loadStateModules()
    local environment = newEnvironment("Jaina", "Camelot", nil)
    local jaina = createState(addon, environment)
    test.assertTrue(jaina:Initialize())
    test.assertTrue(jaina:SetPercentage(15))
    local database = environment.AsgardsGuildTitheDB

    local thrall = reload(addon, "Thrall", "Camelot", database, { name = "Horde Lords" })
    test.assertEqual(10, thrall:GetTitheSettings().percentage)
    test.assertTrue(thrall:SetSourceEnabled("auctions", true))

    local valeera = reload(addon, "Valeera", "Avalon", thrall.persistence.database)
    test.assertEqual("knights of camelot-avalon", valeera:GetTitheSettings().guildKey)
    test.assertEqual(10, valeera:GetTitheSettings().percentage)
    test.assertTrue(valeera:SetPercentage(5))

    local saved = valeera.persistence.database
    local jainaAgain = reload(addon, "Jaina", "Camelot", saved)
    test.assertEqual(15, jainaAgain:GetTitheSettings().percentage)
    test.assertFalse(jainaAgain:GetTitheSettings().sources.auctions)
    test.assertTrue(saved.guilds["horde lords-camelot"].sources.auctions)
    test.assertEqual(5, saved.guilds["knights of camelot-avalon"].percentage)
end)

test.test("the same guild reported from a connected realm keys by the guild's own realm", function()
    local addon = loadStateModules()
    local environment = newEnvironment("Jaina", "Camelot", nil, nil,
        { name = "  Knights of Camelot ", realm = "Avalon" })
    local jaina = createState(addon, environment)
    test.assertTrue(jaina:Initialize())
    test.assertTrue(jaina:SetPercentage(12))

    local valeera = reload(addon, "Valeera", "Avalon", environment.AsgardsGuildTitheDB,
        { name = "knights of camelot" })
    test.assertEqual("knights of camelot-avalon", valeera:GetTitheSettings().guildKey)
    test.assertEqual(12, valeera:GetTitheSettings().percentage)
end)

test.test("the first character into a guild seeds it from its old settings and later alts adopt them", function()
    local addon = loadStateModules()
    local database = versionFourDatabase({
        ["jaina-camelot"] = legacyCharacter("Jaina", 30, true, 700),
        ["thrall-camelot"] = legacyCharacter("Thrall", 50, false, 900),
    })

    local jaina = reload(addon, "Jaina", "Camelot", database)
    test.assertEqual(30, jaina:GetTitheSettings().percentage)
    test.assertTrue(jaina:GetTitheSettings().sources.auctions)
    test.assertEqual(nil, jaina:GetCurrentCharacter().percentage)
    test.assertEqual(nil, jaina:GetCurrentCharacter().sources)

    local thrall = reload(addon, "Thrall", "Camelot", jaina.persistence.database)
    test.assertEqual(30, thrall:GetTitheSettings().percentage)
    test.assertTrue(thrall:GetTitheSettings().sources.auctions)
    test.assertEqual(nil, thrall:GetCurrentCharacter().percentage)
    test.assertEqual(900, thrall:GetCurrentCharacter().outstandingCopper)
    test.assertEqual(700, jaina:GetCurrentCharacter().outstandingCopper)
end)

test.test("a guildless character keeps its old settings until it joins a guild", function()
    local addon = loadStateModules()
    local database = versionFourDatabase({
        ["jaina-camelot"] = legacyCharacter("Jaina", 30, true),
    })
    local membership = { name = nil }
    local environment = newEnvironment("Jaina", "Camelot", nil, database, membership)
    local state = createState(addon, environment)
    test.assertTrue(state:Initialize())

    test.assertEqual(nil, state:GetTitheSettings())
    test.assertFalse(state:SetPercentage(20))
    test.assertFalse(state:SetSourceEnabled("loot", false))
    test.assertTrue(state:SetChatFeedback(false))
    test.assertTrue(state:SetAutoDeposit(false))
    test.assertEqual(30, state:GetCurrentCharacter().percentage)
    test.assertTrue(state:GetCurrentCharacter().sources.auctions)

    membership.name = "Knights of Camelot"
    test.assertEqual(30, state:GetTitheSettings().percentage)
    test.assertEqual(nil, state:GetCurrentCharacter().percentage)
end)

test.test("changing guilds mid-session switches to the new guild's settings", function()
    local addon = loadStateModules()
    local membership = { name = "Knights of Camelot" }
    local environment = newEnvironment("Jaina", "Camelot", nil, nil, membership)
    local state = createState(addon, environment)
    test.assertTrue(state:Initialize())
    test.assertTrue(state:SetPercentage(25))

    membership.name = "Horde Lords"
    test.assertEqual("horde lords-camelot", state:GetTitheSettings().guildKey)
    test.assertEqual(10, state:GetTitheSettings().percentage)
    test.assertTrue(state:SetPercentage(3))

    membership.name = "Knights of Camelot"
    test.assertEqual(25, state:GetTitheSettings().percentage)
end)

test.test("a quarantined guild record leaves its settings unavailable", function()
    local addon = loadStateModules()
    local database = versionFourDatabase({})
    database.schemaVersion = 5
    database.guilds = { ["knights of camelot-camelot"] = "unreadable" }
    database.quarantinedGuilds = {}
    database.ui = { minimap = { hide = false } }

    local state = reload(addon, "Jaina", "Camelot", database)

    test.assertEqual(nil, state:GetTitheSettings())
    test.assertFalse(state:SetPercentage(20))
    test.assertEqual("unreadable",
        state.persistence.database.quarantinedGuilds["knights of camelot-camelot"][1].record)
end)

test.test("normalized name and realm remain the lookup path when stable id changes", function()
    local addon = loadStateModules()
    local firstEnvironment = newEnvironment("Rexxar", "The Venture Co", "Old-GUID")
    local firstState = createState(addon, firstEnvironment)
    test.assertTrue(firstState:Initialize())
    test.assertTrue(firstState:SetFinancialState(42, 0))

    local reloadedState = createState(addon, newEnvironment(
        "  REXXAR  ",
        " the  venture co ",
        "New-GUID",
        firstEnvironment.AsgardsGuildTitheDB
    ))
    test.assertTrue(reloadedState:Initialize())
    local character = reloadedState:GetCurrentCharacter()

    test.assertEqual("rexxar-theventureco", reloadedState:GetCharacterKey())
    test.assertEqual(42, character.outstandingCopper)
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
    snapshot.outstandingCopper = 99
    local settings = state:GetTitheSettings()
    settings.percentage = 99
    settings.sources.loot = false
    settings.guild.name = "Changed"

    test.assertEqual(0, state:GetCurrentCharacter().outstandingCopper)
    local unchanged = state:GetTitheSettings()
    test.assertEqual(10, unchanged.percentage)
    test.assertTrue(unchanged.sources.loot)
    test.assertEqual("Knights of Camelot", unchanged.guild.name)
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
    test.assertFalse(state:SetSourceEnabled("loot", "no"))

    local character = state:GetCurrentCharacter()
    test.assertEqual(0, character.outstandingCopper)
    test.assertEqual(0, character.fractionalRemainder)
    test.assertEqual(10, state:GetTitheSettings().percentage)
    test.assertTrue(state:GetTitheSettings().sources.loot)
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
