local test = require("tests.test_helper")
local fixtures = require("tests.client_fixtures")

local function detect(environment)
    local addon = test.newAddon("Adapters/ClientProfile.lua")
    return addon.ClientProfile.Detect(environment, "AsgardsGuildTithe")
end

local function metadata(value)
    return {
        GetAddOnMetadata = function(addonName, field)
            test.assertEqual("AsgardsGuildTithe", addonName)
            test.assertEqual("X-Client", field)
            return value
        end,
    }
end

local DETECTION_CASES = {
    {
        name = "Forever manifest on the Forever client",
        environment = { GetAddOnMetadata = metadata("Forever").GetAddOnMetadata },
        id = "forever",
        label = "WoW Forever",
    },
    {
        name = "Forever manifest while sharing Retail project constants",
        environment = {
            GetAddOnMetadata = metadata("Forever").GetAddOnMetadata,
            WOW_PROJECT_ID = 1,
            WOW_PROJECT_MAINLINE = 1,
        },
        id = "forever",
        label = "WoW Forever",
    },
    {
        name = "Retail manifest on the Retail client",
        environment = {
            C_AddOns = metadata("Retail"),
            WOW_PROJECT_ID = 1,
            WOW_PROJECT_MAINLINE = 1,
        },
        id = "retail",
        label = "WoW Retail",
    },
    {
        name = "Retail manifest on a non-Retail project",
        environment = {
            C_AddOns = metadata("Retail"),
            WOW_PROJECT_ID = 2,
            WOW_PROJECT_MAINLINE = 1,
        },
        id = "unsupported",
        reason = "Retail manifest loaded on a non-Retail client",
    },
    {
        name = "Retail manifest without project constants",
        environment = { C_AddOns = metadata("Retail") },
        id = "unsupported",
        reason = "non-Retail client",
    },
    {
        name = "manifest without a client declaration",
        environment = {
            C_AddOns = metadata(nil),
            WOW_PROJECT_ID = 1,
            WOW_PROJECT_MAINLINE = 1,
        },
        id = "unsupported",
        reason = "does not declare a supported client",
    },
    {
        name = "manifest declaring an unknown client",
        environment = { C_AddOns = metadata("Classic") },
        id = "unsupported",
        reason = "unknown client 'Classic'",
    },
    {
        name = "client without a metadata API",
        environment = { WOW_PROJECT_ID = 1, WOW_PROJECT_MAINLINE = 1 },
        id = "unsupported",
        reason = "does not declare a supported client",
    },
    {
        name = "metadata API that raises an error",
        environment = {
            GetAddOnMetadata = function()
                error("metadata unavailable")
            end,
        },
        id = "unsupported",
        reason = "does not declare a supported client",
    },
}

local caseIndex
for caseIndex = 1, #DETECTION_CASES do
    local case = DETECTION_CASES[caseIndex]
    test.test("client profile classifies " .. case.name, function()
        local profile = detect(case.environment)

        test.assertEqual(case.id, profile.id)
        test.assertEqual(case.id ~= "unsupported", profile.supported)
        if case.label ~= nil then
            test.assertEqual(case.label, profile.label)
        else
            test.assertEqual("Unsupported client", profile.label)
            test.assertContains(profile.reason, case.reason)
        end
    end)
end

local function registerProfileTests(profile)
    local label = "WoW " .. profile

    test.test(profile .. " profile registers slash at load and persists state only at login", function()
        local world = fixtures.newEnvironment(profile)
        local addon = fixtures.loadAddon(world)
        local environment = world.environment

        test.assertEqual(profile == "Forever" and "forever" or "retail", addon.clientProfile.id)
        test.assertEqual(nil, environment.AsgardsGuildTitheDB)

        fixtures.fire(world, "ADDON_LOADED", "AsgardsGuildTithe")
        test.assertEqual("/agt", environment.SLASH_AGT1)
        test.assertEqual("/asgardstithe", environment.SLASH_AGT2)
        test.assertEqual(nil, environment.AsgardsGuildTitheDB)

        world.playerReady = true
        fixtures.fire(world, "PLAYER_LOGIN")
        fixtures.fire(world, "PLAYER_LOGIN")

        local database = environment.AsgardsGuildTitheDB
        test.assertEqual("table", type(database.characters["jaina-camelot"]))
        test.assertEqual(nil, database.clientProfile)
        test.assertEqual(nil, database.characters["jaina-camelot"].clientProfile)
        test.assertEqual(0, #world.messages)
    end)

    test.test(profile .. " profile never persists a placeholder character identity", function()
        local world = fixtures.newEnvironment(profile)
        fixtures.loadAddon(world)

        fixtures.fire(world, "ADDON_LOADED", "AsgardsGuildTithe")
        fixtures.fire(world, "PLAYER_LOGIN")

        local database = world.environment.AsgardsGuildTitheDB
        test.assertTrue(database == nil or database.characters["unknown-camelot"] == nil)
        test.assertEqual(1, #world.messages)
        test.assertContains(world.messages[1], "identity is unavailable")
    end)

    test.test(profile .. " profile recovers state once identity is ready after a placeholder login", function()
        local world = fixtures.newEnvironment(profile)
        local addon = fixtures.loadAddon(world)

        fixtures.fire(world, "ADDON_LOADED", "AsgardsGuildTithe")
        fixtures.fire(world, "PLAYER_LOGIN")
        fixtures.fire(world, "PLAYER_ENTERING_WORLD")
        world.playerReady = true
        fixtures.fire(world, "PLAYER_ENTERING_WORLD")
        fixtures.fire(world, "PLAYER_ENTERING_WORLD")

        local database = world.environment.AsgardsGuildTitheDB
        test.assertTrue(addon.lifecycle.stateReady)
        test.assertTrue(addon.lifecycle.settingsReady)
        test.assertEqual("table", type(database.characters["jaina-camelot"]))
        test.assertEqual(nil, database.characters["unknown-camelot"])
        test.assertEqual(1, #world.messages)
    end)

    test.test(profile .. " profile reports a missing essential capability once", function()
        local world = fixtures.newEnvironment(profile)
        world.environment.UnitName = nil
        local existing = { schemaVersion = 2, characters = {} }
        world.environment.AsgardsGuildTitheDB = existing
        local before = fixtures.snapshot(existing)
        fixtures.loadAddon(world)

        fixtures.fire(world, "ADDON_LOADED", "AsgardsGuildTithe")
        fixtures.fire(world, "PLAYER_LOGIN")
        fixtures.fire(world, "PLAYER_ENTERING_WORLD")
        fixtures.fire(world, "PLAYER_ENTERING_WORLD")

        test.assertEqual(1, #world.messages)
        test.assertContains(world.messages[1], "Saved character state is unavailable")
        fixtures.assertSameData(before, world.environment.AsgardsGuildTitheDB)
    end)

    test.test(profile .. " profile names the running client in help", function()
        local world = fixtures.newEnvironment(profile)
        fixtures.loadAddon(world)
        fixtures.fire(world, "ADDON_LOADED", "AsgardsGuildTithe")

        world.environment.SlashCmdList.AGT("help")

        test.assertEqual(
            "|cffd4af37[Guild Tithe]|r Client: " .. label .. ".",
            world.messages[#world.messages]
        )
    end)
end

local profileIndex
for profileIndex = 1, #fixtures.PROFILES do
    registerProfileTests(fixtures.PROFILES[profileIndex])
end

test.test("unsupported client reports once and leaves saved data untouched", function()
    local world = fixtures.newEnvironment("Retail", { declaredClient = false })
    local existing = {
        schemaVersion = 2,
        characters = {
            ["jaina-camelot"] = { outstandingCopper = 12345, percentage = 15 },
        },
    }
    world.environment.AsgardsGuildTitheDB = existing
    local before = fixtures.snapshot(existing)
    local addon = fixtures.loadAddon(world)

    fixtures.fire(world, "ADDON_LOADED", "AsgardsGuildTithe")
    world.playerReady = true
    fixtures.fire(world, "PLAYER_LOGIN")
    fixtures.fire(world, "PLAYER_LOGIN")

    test.assertFalse(addon.clientProfile.supported)
    test.assertEqual(1, #world.messages)
    test.assertContains(world.messages[1], "This game client is not supported")
    test.assertContains(world.messages[1], "WoW Forever and WoW Retail")
    test.assertEqual(existing, world.environment.AsgardsGuildTitheDB)
    fixtures.assertSameData(before, existing)

    world.environment.SlashCmdList.AGT("")
    test.assertEqual(
        "|cffd4af37[Guild Tithe]|r Client: Unsupported client.",
        world.messages[#world.messages]
    )
    test.assertEqual(nil, string.find(world.messages[2], "settings", 1, true))
end)
