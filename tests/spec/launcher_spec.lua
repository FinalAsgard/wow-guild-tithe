local test = require("tests.test_helper")
local fixtures = require("tests.client_fixtures")

local BUTTON = "LibDBIcon10_AsgardsGuildTithe"

local function login(profile, options)
    local world = fixtures.newEnvironment(profile, options)
    local addon = fixtures.login(world)
    return world, addon
end

local function icon(world)
    return world.environment[BUTTON]
end

-- Hovers the minimap icon and returns the tooltip's lines.
local function hover(world)
    local button = icon(world)
    button.scripts.OnEnter(button)
    return world.environment.LibDBIconTooltip.lines
end

local function hasLine(lines, text)
    local index
    for index = 1, #lines do
        if string.find(lines[index], text, 1, true) ~= nil then
            return true
        end
    end
    return false
end

local function registerProfileTests(profile)
    test.test(profile .. " a fresh install shows the gold-coin icon on the minimap", function()
        local world, addon = login(profile)

        local button = icon(world)
        test.assertEqual("table", type(button), "minimap button")
        test.assertTrue(button.shown)
        test.assertEqual("Interface\\Icons\\INV_Misc_Coin_01", button.icon.path)
        test.assertTrue(addon.lifecycle.launcherReady)
        test.assertFalse(world.environment.AsgardsGuildTitheDB.ui.minimap.hide)
    end)

    test.test(profile .. " the tooltip shows the balance, guild, percentage, and click hints", function()
        local world, addon = login(profile)
        test.assertTrue(addon.state:SetFinancialState(12345, 0))
        test.assertTrue(addon.state:SetPercentage(15))

        local lines = hover(world)

        test.assertContains(lines[1], "Asgard's Guild Tithe")
        test.assertEqual("Balance owed: |cffffffff" .. addon.MoneyFormatter.Format(12345) .. "|r",
            lines[2])
        test.assertEqual("Tithing |cffffffff15%|r to |cffffffffKnights of Camelot|r", lines[3])
        test.assertTrue(hasLine(lines, "Left-click:|r open settings"))
        test.assertTrue(hasLine(lines, "Right-click:|r open donation history"))
    end)

    test.test(profile .. " a guildless character's tooltip shows its balance and no guild", function()
        local world, addon = login(profile, { inGuild = false })
        test.assertTrue(addon.state:SetFinancialState(500, 0))

        local lines = hover(world)

        test.assertEqual("Balance owed: |cffffffff" .. addon.MoneyFormatter.Format(500) .. "|r",
            lines[2])
        test.assertEqual("Not in a guild", lines[3])
        test.assertFalse(hasLine(lines, "Tithing"))
        test.assertFalse(hasLine(lines, "%"))
    end)

    test.test(profile .. " the tooltip follows a guild change without a reload", function()
        local world = login(profile)
        world.inGuild = false
        fixtures.fire(world, "PLAYER_GUILD_UPDATE")
        test.assertEqual("Not in a guild", hover(world)[3])

        world.inGuild = true
        world.guildName = "Order of the Lion"
        fixtures.fire(world, "PLAYER_GUILD_UPDATE")
        test.assertEqual("Tithing |cffffffff10%|r to |cffffffffOrder of the Lion|r", hover(world)[3])
    end)

    test.test(profile .. " left-click opens settings and right-click opens donation history", function()
        local world = login(profile)
        local button = icon(world)

        fixtures.click(button, "RightButton")
        test.assertEqual(74, world.settings.openedCategoryID)

        fixtures.click(button, "LeftButton")
        test.assertEqual(73, world.settings.openedCategoryID)
    end)

    test.test(profile .. " the icon's position and visibility are shared by every character", function()
        local world = login(profile)
        local button = icon(world)

        -- Drag the icon to the top of the minimap.
        button.scripts.OnDragStart(button)
        world.cursor = { 0, 50 }
        button.scripts.OnUpdate(button)
        button.scripts.OnDragStop(button)

        local saved = world.environment.AsgardsGuildTitheDB
        test.assertEqual(90, math.floor(saved.ui.minimap.minimapPos + 0.5))
        saved.ui.minimap.hide = true

        local alt = login(profile, { database = saved, playerName = "Thrall" })
        local altSaved = alt.environment.AsgardsGuildTitheDB
        test.assertEqual("table", type(altSaved.characters["thrall-camelot"]))
        test.assertEqual(90, math.floor(altSaved.ui.minimap.minimapPos + 0.5))
        test.assertFalse(icon(alt).shown, "hidden on the other character too")
    end)

    test.test(profile .. " without the icon libraries the add-on loads and works without an icon", function()
        local world, addon = login(profile, { libraries = false })

        test.assertEqual(nil, world.environment.LibStub)
        test.assertEqual(nil, icon(world))
        test.assertFalse(addon.lifecycle.launcherReady)
        test.assertTrue(addon.lifecycle.stateReady)
        test.assertTrue(addon.lifecycle.incomeReady)
        test.assertEqual(0, #world.messages)

        world.environment.SlashCmdList.AGT("")
        test.assertEqual(73, world.settings.openedCategoryID)
        fixtures.setMoney(world, 20000)
        test.assertEqual(2000,
            world.environment.AsgardsGuildTitheDB.characters["jaina-camelot"].outstandingCopper)
    end)
end

local index
for index = 1, #fixtures.PROFILES do
    registerProfileTests(fixtures.PROFILES[index])
end

test.test("the icon is skipped when another copy of the library lacks a dependency", function()
    local world = fixtures.newEnvironment("Retail")
    local addon = fixtures.loadAddon(world)
    -- Simulates a broken shared copy: LibStub is present, LibDBIcon is not.
    world.environment.LibStub.libs["LibDBIcon-1.0"] = nil
    fixtures.fire(world, "ADDON_LOADED", "AsgardsGuildTithe")
    world.playerReady = true
    fixtures.fire(world, "PLAYER_LOGIN")

    test.assertTrue(addon.lifecycle.stateReady)
    test.assertFalse(addon.lifecycle.launcherReady)
    test.assertEqual(nil, world.environment[BUTTON])
end)
