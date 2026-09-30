local test = require("tests.test_helper")
local fixtures = require("tests.client_fixtures")

local CHECKBOX_VARIABLES = {
    "AsgardsGuildTithe_Source_Loot",
    "AsgardsGuildTithe_Source_Quests",
    "AsgardsGuildTithe_Source_VendorSales",
    "AsgardsGuildTithe_Source_Auctions",
    "AsgardsGuildTithe_Source_Mailbox",
    "AsgardsGuildTithe_Source_PlayerTrades",
    "AsgardsGuildTithe_Source_Miscellaneous",
    "AsgardsGuildTithe_ChatFeedback",
    "AsgardsGuildTithe_AutoDeposit",
}

local function otherProfile(profile)
    return profile == "Forever" and "Retail" or "Forever"
end

local function registerProfileTests(profile)
    test.test(profile .. " profile opens native settings from both slash commands", function()
        local world = fixtures.newEnvironment(profile)
        fixtures.login(world)
        local environment = world.environment

        test.assertEqual("/agt", environment.SLASH_AGT1)
        test.assertEqual("/asgardstithe", environment.SLASH_AGT2)
        environment.SlashCmdList.AGT("")

        test.assertEqual("Asgard's Guild Tithe", world.settings.categoryName)
        test.assertEqual(world.settings.category, world.settings.registeredCategory)
        test.assertEqual(73, world.settings.openedCategoryID)

        world.settings.openedCategoryID = nil
        environment.SlashCmdList.AGT("settings")
        test.assertEqual(73, world.settings.openedCategoryID)
        test.assertEqual(0, #world.messages)
    end)

    test.test(profile .. " profile renders whole-number percentage, grouped checkboxes, and a read-only balance", function()
        local world = fixtures.newEnvironment(profile)
        fixtures.login(world)
        local settings = world.settings

        test.assertEqual(0, settings.sliderOptions.minimum)
        test.assertEqual(100, settings.sliderOptions.maximum)
        test.assertEqual(1, settings.sliderOptions.step)
        test.assertEqual("42%", settings.sliderFormatter(42))
        test.assertEqual(1, settings.sliders)
        test.assertEqual(#CHECKBOX_VARIABLES, settings.checkboxes)

        local headings = {}
        local index
        for index = 1, #settings.layout.initializers do
            table.insert(headings, settings.layout.initializers[index]:GetData().name)
        end
        test.assertContains(headings[1], "Current balance: 0g 00s 00c")
        test.assertEqual("Tithe - Lifetime given: 0g 00s 00c", headings[2])
        test.assertEqual("Income Sources", headings[3])
        test.assertEqual("Feedback", headings[4])
        test.assertEqual("Guild Bank", headings[5])

        -- Only the percentage and the eight preferences are editable.
        test.assertEqual(1 + #CHECKBOX_VARIABLES, #settings.bindingOrder)
        test.assertEqual("AsgardsGuildTithe_Percentage", settings.bindingOrder[1])
        for index = 1, #CHECKBOX_VARIABLES do
            test.assertEqual(CHECKBOX_VARIABLES[index], settings.bindingOrder[index + 1])
        end
    end)

    test.test(profile .. " profile applies setting changes without touching the balance", function()
        local world = fixtures.newEnvironment(profile)
        fixtures.login(world)
        local bindings = world.settings.bindings

        test.assertEqual(10, bindings.AsgardsGuildTithe_Percentage.getValue())
        bindings.AsgardsGuildTithe_Percentage.setValue(25)
        bindings.AsgardsGuildTithe_Source_Auctions.setValue(true)
        bindings.AsgardsGuildTithe_ChatFeedback.setValue(false)

        local character = world.environment.AsgardsGuildTitheDB.characters["jaina-camelot"]
        test.assertEqual(25, character.percentage)
        test.assertTrue(character.sources.auctions)
        test.assertFalse(character.chatFeedback)
        test.assertEqual(0, character.outstandingCopper)
        test.assertEqual(25, bindings.AsgardsGuildTithe_Percentage.getValue())
    end)

    test.test(profile .. " profile refreshes the balance when settings open", function()
        local world = fixtures.newEnvironment(profile)
        fixtures.login(world)
        world.environment.AsgardsGuildTitheDB.characters["jaina-camelot"].outstandingCopper = 12345

        world.environment.SlashCmdList.AGT("")

        test.assertContains(fixtures.balanceText(world), "Current balance: 1g 23s 45c")
    end)

    test.test(profile .. " profile explains a settings window that fails to open", function()
        local world = fixtures.newEnvironment(profile)
        world.settings.OpenToCategory = function()
            error("protected")
        end
        fixtures.login(world)

        world.environment.SlashCmdList.AGT("")

        test.assertEqual(1, #world.messages)
        test.assertContains(world.messages[1], "settings are unavailable")
        test.assertContains(world.messages[1], "/agt help")
    end)

    test.test(profile .. " profile keeps state and help when the Settings API is missing", function()
        local world = fixtures.newEnvironment(profile, { settings = false })
        local addon = fixtures.login(world)

        test.assertTrue(addon.lifecycle.stateReady)
        test.assertFalse(addon.lifecycle.settingsReady)
        test.assertEqual("table", type(world.environment.AsgardsGuildTitheDB.characters["jaina-camelot"]))

        world.environment.SlashCmdList.AGT("")
        test.assertContains(world.messages[1], "settings are unavailable")
    end)

    test.test(profile .. " profile keeps settings across reload and isolates characters", function()
        local first = fixtures.newEnvironment(profile)
        fixtures.login(first)
        first.settings.bindings.AsgardsGuildTithe_Percentage.setValue(30)

        -- Each session hands the game-owned SavedVariables table to the next.
        local reloaded = fixtures.newEnvironment(profile, {
            database = first.environment.AsgardsGuildTitheDB,
        })
        fixtures.login(reloaded)
        test.assertEqual(30, reloaded.settings.bindings.AsgardsGuildTithe_Percentage.getValue())

        local alt = fixtures.newEnvironment(profile, {
            database = reloaded.environment.AsgardsGuildTitheDB,
            playerName = "Thrall",
        })
        fixtures.login(alt)
        test.assertEqual(10, alt.settings.bindings.AsgardsGuildTithe_Percentage.getValue())
        alt.settings.bindings.AsgardsGuildTithe_Percentage.setValue(5)

        local database = alt.environment.AsgardsGuildTitheDB
        test.assertEqual(30, database.characters["jaina-camelot"].percentage)
        test.assertEqual(5, database.characters["thrall-camelot"].percentage)
    end)

    test.test(profile .. " profile reads data saved by " .. otherProfile(profile) .. " without rewriting it", function()
        local source = fixtures.newEnvironment(otherProfile(profile))
        fixtures.login(source)
        source.settings.bindings.AsgardsGuildTithe_Percentage.setValue(15)
        local database = source.environment.AsgardsGuildTitheDB
        database.characters["jaina-camelot"].outstandingCopper = 98765
        local before = fixtures.snapshot(database)

        local world = fixtures.newEnvironment(profile, { database = database })
        local addon = fixtures.login(world)

        test.assertTrue(addon.lifecycle.stateReady)
        test.assertEqual(15, world.settings.bindings.AsgardsGuildTithe_Percentage.getValue())
        test.assertContains(fixtures.balanceText(world), "9g 87s 65c")
        fixtures.assertSameData(before, world.environment.AsgardsGuildTitheDB)
    end)
end

local profileIndex
for profileIndex = 1, #fixtures.PROFILES do
    registerProfileTests(fixtures.PROFILES[profileIndex])
end

test.test("Forever registers slash through the native API and Retail through SlashCmdList", function()
    local forever = fixtures.newEnvironment("Forever")
    local foreverCalls = 0
    local register = forever.environment.RegisterNewSlashCommand
    forever.environment.RegisterNewSlashCommand = function(...)
        foreverCalls = foreverCalls + 1
        return register(...)
    end
    fixtures.login(forever)

    local retail = fixtures.newEnvironment("Retail")
    fixtures.login(retail)

    test.assertEqual(1, foreverCalls)
    test.assertEqual(nil, retail.environment.RegisterNewSlashCommand)
    test.assertEqual("function", type(forever.environment.SlashCmdList.AGT))
    test.assertEqual("function", type(retail.environment.SlashCmdList.AGT))
end)

local function registerClearTests(profile)
    test.test(profile .. " balance changes repaint an open settings page", function()
        local world = fixtures.newEnvironment(profile, { money = 1000 })
        fixtures.login(world)
        local header = { Title = {} }
        function header.Title:SetText(text)
            self.text = text
        end
        function header:GetElementData()
            return world.settings.layout.initializers[1]
        end
        local other = { Title = {} }
        function other.Title:SetText(text)
            self.text = text
        end
        function other:GetElementData()
            return world.settings.layout.initializers[3]
        end
        world.environment.SettingsPanel = {
            GetSettingsList = function()
                return {
                    ScrollBox = {
                        ForEachFrame = function(_, callback)
                            callback(other)
                            callback(header)
                        end,
                    },
                }
            end,
        }
        world.environment.SlashCmdList.AGT("")
        local character = world.environment.AsgardsGuildTitheDB.characters["jaina-camelot"]

        world.money = 13345
        fixtures.fire(world, "LOOT_OPENED")
        fixtures.fire(world, "PLAYER_MONEY")
        fixtures.settle(world)
        test.assertEqual(1234, character.outstandingCopper)
        test.assertContains(fixtures.balanceText(world), "0g 12s 34c")
        test.assertEqual(fixtures.balanceText(world), header.Title.text)

        world.environment.SlashCmdList.AGT("clear")
        test.assertContains(fixtures.balanceText(world), "Current balance: 0g 00s 00c")
        test.assertEqual("Tithe - Current balance: 0g 00s 00c", header.Title.text)
        test.assertEqual(nil, other.Title.text)
    end)

    test.test(profile .. " /agt clear resets the balance and reports what was cleared", function()
        local world = fixtures.newEnvironment(profile, { money = 100000 })
        fixtures.login(world)
        local character = world.environment.AsgardsGuildTitheDB.characters["jaina-camelot"]
        character.outstandingCopper = 12345
        character.fractionalRemainder = 67
        character.percentage = 25

        world.environment.SlashCmdList.AGT("clear")

        test.assertEqual(0, character.outstandingCopper)
        test.assertEqual(0, character.fractionalRemainder)
        test.assertEqual(25, character.percentage)
        test.assertEqual(
            "Asgard's Guild Tithe: cleared your tithe balance (was 1g 23s 45c).",
            world.messages[#world.messages]
        )
    end)

    test.test(profile .. " /agt clear withdraws an open guild-bank offer", function()
        local world = fixtures.newEnvironment(profile, { money = 100000 })
        local addon = fixtures.login(world)
        local character = world.environment.AsgardsGuildTitheDB.characters["jaina-camelot"]
        character.outstandingCopper = 5000
        character.autoDeposit = false
        fixtures.fire(world, "GUILDBANKFRAME_OPENED")
        test.assertTrue(addon.tithePayment.panel:IsShown())

        world.environment.SlashCmdList.AGT("clear")

        test.assertFalse(addon.tithePayment.panel:IsShown())
        test.assertEqual(0, #world.deposits)
    end)

    test.test(profile .. " /agt help lists the clear command", function()
        local world = fixtures.newEnvironment(profile)
        fixtures.login(world)

        world.environment.SlashCmdList.AGT("help")

        test.assertContains(world.messages[1], "/agt clear - clear the current tithe balance")
    end)
end

local clearIndex
for clearIndex = 1, #fixtures.PROFILES do
    registerClearTests(fixtures.PROFILES[clearIndex])
end
