local test = require("tests.test_helper")
local fixtures = require("tests.client_fixtures")

-- Every editable setting, in page order. Sliders are marked.
local SETTING_VARIABLES = {
    { "AsgardsGuildTithe_Percentage", slider = true },
    { "AsgardsGuildTithe_AdvancedMode" },
    { "AsgardsGuildTithe_Source_Loot" },
    { "AsgardsGuildTithe_Source_Quests" },
    { "AsgardsGuildTithe_Source_VendorSales" },
    { "AsgardsGuildTithe_Source_Auctions" },
    { "AsgardsGuildTithe_Source_Mailbox" },
    { "AsgardsGuildTithe_Source_PlayerTrades" },
    { "AsgardsGuildTithe_Source_Miscellaneous" },
    { "AsgardsGuildTithe_SourcePercentage_Loot", slider = true },
    { "AsgardsGuildTithe_SourcePercentage_Quests", slider = true },
    { "AsgardsGuildTithe_SourcePercentage_VendorSales", slider = true },
    { "AsgardsGuildTithe_SourcePercentage_Auctions", slider = true },
    { "AsgardsGuildTithe_SourcePercentage_Mailbox", slider = true },
    { "AsgardsGuildTithe_SourcePercentage_PlayerTrades", slider = true },
    { "AsgardsGuildTithe_SourcePercentage_Miscellaneous", slider = true },
    { "AsgardsGuildTithe_ChatFeedback" },
    { "AsgardsGuildTithe_AutoDeposit" },
    { "AsgardsGuildTithe_MinimapIcon" },
}

local function countSettings(sliders)
    local count = 0
    local index
    for index = 1, #SETTING_VARIABLES do
        if (SETTING_VARIABLES[index].slider == true) == sliders then
            count = count + 1
        end
    end
    return count
end


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
        test.assertEqual(countSettings(true), settings.sliders)
        test.assertEqual(countSettings(false), settings.checkboxes)

        local headings = {}
        local index
        for index = 1, #settings.layout.initializers do
            table.insert(headings, settings.layout.initializers[index]:GetData().name)
        end
        test.assertContains(headings[1], "Current balance: 0|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t")
        test.assertEqual("Shared by your characters in Knights of Camelot", headings[2])
        test.assertEqual("Income Sources", headings[3])
        test.assertEqual("Feedback", headings[4])
        test.assertEqual("Guild Bank", headings[5])
        test.assertEqual("Minimap", headings[6])

        -- Only the percentages and the preferences are editable.
        test.assertEqual(#SETTING_VARIABLES, #settings.bindingOrder)
        for index = 1, #SETTING_VARIABLES do
            test.assertEqual(SETTING_VARIABLES[index][1], settings.bindingOrder[index])
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

        local database = world.environment.AsgardsGuildTitheDB
        local character = database.characters["jaina-camelot"]
        local guild = database.guilds["knights of camelot-camelot"]
        test.assertEqual(25, guild.percentage)
        test.assertTrue(guild.sources.auctions)
        test.assertFalse(character.chatFeedback)
        test.assertEqual(0, character.outstandingCopper)
        test.assertEqual(25, bindings.AsgardsGuildTithe_Percentage.getValue())
    end)

    test.test(profile .. " profile refreshes the balance when settings open", function()
        local world = fixtures.newEnvironment(profile)
        fixtures.login(world)
        world.environment.AsgardsGuildTitheDB.characters["jaina-camelot"].outstandingCopper = 12345

        world.environment.SlashCmdList.AGT("")

        test.assertContains(fixtures.balanceText(world), "Current balance: 1|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t 23|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t 45|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t")
    end)

    test.test(profile .. " profile explains a settings window that fails to open", function()
        local world = fixtures.newEnvironment(profile)
        world.settings.OpenToCategory = function()
            error("protected")
        end
        fixtures.login(world)

        world.environment.SlashCmdList.AGT("")

        test.assertEqual(1, #world.messages)
        test.assertContains(world.messages[1], "Settings are unavailable")
        test.assertContains(world.messages[1], "/agt help")
    end)

    test.test(profile .. " profile keeps state and help when the Settings API is missing", function()
        local world = fixtures.newEnvironment(profile, { settings = false })
        local addon = fixtures.login(world)

        test.assertTrue(addon.lifecycle.stateReady)
        test.assertFalse(addon.lifecycle.settingsReady)
        test.assertEqual("table", type(world.environment.AsgardsGuildTitheDB.characters["jaina-camelot"]))

        world.environment.SlashCmdList.AGT("")
        test.assertContains(world.messages[1], "Settings are unavailable")
    end)

    test.test(profile .. " profile keeps guild settings across reload and shares them only within the guild", function()
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
        test.assertEqual(30, alt.settings.bindings.AsgardsGuildTithe_Percentage.getValue())

        local otherGuild = fixtures.newEnvironment(profile, {
            database = alt.environment.AsgardsGuildTitheDB,
            guildName = "Horde Lords",
            playerName = "Rexxar",
        })
        fixtures.login(otherGuild)
        test.assertEqual(10, otherGuild.settings.bindings.AsgardsGuildTithe_Percentage.getValue())
        otherGuild.settings.bindings.AsgardsGuildTithe_Percentage.setValue(5)

        local database = otherGuild.environment.AsgardsGuildTitheDB
        test.assertEqual(30, database.guilds["knights of camelot-camelot"].percentage)
        test.assertEqual(5, database.guilds["horde lords-camelot"].percentage)
        test.assertEqual(nil, database.characters["thrall-camelot"].percentage)
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
        test.assertContains(fixtures.balanceText(world), "9|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t 87|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t 65|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t")
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
        test.assertContains(fixtures.balanceText(world), "12|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t 34|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t")
        test.assertEqual(fixtures.balanceText(world), header.Title.text)

        world.environment.SlashCmdList.AGT("clear")
        test.assertContains(fixtures.balanceText(world), "Current balance: 0|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t")
        test.assertEqual("Tithe - Current balance: 0|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t", header.Title.text)
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
            "|cffd4af37[Guild Tithe]|r Tithe balance cleared (was 1|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t 23|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t 45|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t).",
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

    test.test(profile .. " /agt help prints each command on its own line", function()
        local world = fixtures.newEnvironment(profile)
        fixtures.login(world)

        world.environment.SlashCmdList.AGT("help")

        test.assertEqual("|cffd4af37[Guild Tithe]|r Commands:", world.messages[1])
        local expected = {
            "  /agt help - show available commands",
            "  /agt minimap - show or hide the minimap icon",
            "  /agt clear - clear the current tithe balance",
            "  /agt settings - open settings",
            "  /agt history - open donation history",
        }
        local index
        for index = 1, #expected do
            local found = false
            local line
            for line = 2, #world.messages - 1 do
                found = found or world.messages[line] == expected[index]
            end
            test.assertTrue(found, expected[index])
        end
        test.assertEqual(#expected + 2, #world.messages)
        test.assertContains(world.messages[#world.messages], "Client:")
    end)
end

local clearIndex
for clearIndex = 1, #fixtures.PROFILES do
    registerClearTests(fixtures.PROFILES[clearIndex])
end

local function character(world)
    return world.environment.AsgardsGuildTitheDB.characters["jaina-camelot"]
end

local GUILD_CONTROLS = {
    "AsgardsGuildTithe_Percentage",
    "AsgardsGuildTithe_Source_Loot",
    "AsgardsGuildTithe_Source_Quests",
    "AsgardsGuildTithe_Source_VendorSales",
    "AsgardsGuildTithe_Source_Auctions",
    "AsgardsGuildTithe_Source_Mailbox",
    "AsgardsGuildTithe_Source_PlayerTrades",
    "AsgardsGuildTithe_Source_Miscellaneous",
}

local function assertGuildControlsEnabled(world, expected)
    local index
    for index = 1, #GUILD_CONTROLS do
        local variable = GUILD_CONTROLS[index]
        test.assertEqual(expected, world.settings.controls[variable]:IsEnabled(), variable)
    end
end

local function registerGuildTests(profile)
    test.test(profile .. " settings name the guild whose settings all its characters share", function()
        local world = fixtures.newEnvironment(profile)
        fixtures.login(world)

        test.assertEqual("Shared by your characters in Knights of Camelot", fixtures.guildHeaderText(world))
        assertGuildControlsEnabled(world, true)
    end)

    test.test(profile .. " a guildless character cannot change guild settings but keeps its own preferences", function()
        local world = fixtures.newEnvironment(profile, { inGuild = false, money = 1000 })
        fixtures.login(world)
        local bindings = world.settings.bindings
        world.environment.AsgardsGuildTitheDB.characters["jaina-camelot"].outstandingCopper = 4321

        world.environment.SlashCmdList.AGT("")

        test.assertEqual("Join a guild to set its tithe", fixtures.guildHeaderText(world))
        assertGuildControlsEnabled(world, false)
        test.assertFalse(bindings.AsgardsGuildTithe_Percentage.setValue(30))
        test.assertFalse(bindings.AsgardsGuildTithe_Source_Loot.setValue(false))
        test.assertTrue(world.settings.controls.AsgardsGuildTithe_ChatFeedback:IsEnabled())
        test.assertTrue(world.settings.controls.AsgardsGuildTithe_AutoDeposit:IsEnabled())
        test.assertTrue(bindings.AsgardsGuildTithe_ChatFeedback.setValue(false))
        test.assertTrue(bindings.AsgardsGuildTithe_AutoDeposit.setValue(false))
        test.assertContains(fixtures.balanceText(world), "43|TInterface\\MoneyFrame\\UI-SilverIcon")
        test.assertEqual(0, (function()
            local count = 0
            local _
            for _ in pairs(world.environment.AsgardsGuildTitheDB.guilds) do
                count = count + 1
            end
            return count
        end)())
    end)

    test.test(profile .. " leaving, joining, and switching guilds mid-session update settings and tithing", function()
        local world = fixtures.newEnvironment(profile, { money = 100000 })
        fixtures.login(world)
        local bindings = world.settings.bindings
        local addon = world.addon
        local changes = 0
        addon.state:OnGuildSettingsChange(function()
            changes = changes + 1
        end)
        bindings.AsgardsGuildTithe_Percentage.setValue(20)
        test.assertEqual(1, changes)

        world.inGuild = false
        fixtures.fire(world, "PLAYER_GUILD_UPDATE", "player")
        test.assertEqual(2, changes)
        test.assertEqual("Join a guild to set its tithe", fixtures.guildHeaderText(world))
        assertGuildControlsEnabled(world, false)
        test.assertTrue((world.settings.notified.AsgardsGuildTithe_Percentage or 0) >= 1)
        fixtures.setMoney(world, 101000)
        test.assertEqual(0, character(world).outstandingCopper)

        world.inGuild = true
        world.guildName = "Horde Lords"
        fixtures.fire(world, "PLAYER_GUILD_UPDATE", "player")
        test.assertEqual(3, changes)
        test.assertEqual("Shared by your characters in Horde Lords", fixtures.guildHeaderText(world))
        assertGuildControlsEnabled(world, true)
        test.assertEqual(10, bindings.AsgardsGuildTithe_Percentage.getValue())
        fixtures.setMoney(world, 102000)
        test.assertEqual(100, character(world).outstandingCopper)

        world.guildName = "Knights of Camelot"
        fixtures.fire(world, "GUILD_ROSTER_UPDATE")
        test.assertEqual("Shared by your characters in Knights of Camelot", fixtures.guildHeaderText(world))
        test.assertEqual(20, bindings.AsgardsGuildTithe_Percentage.getValue())
        fixtures.setMoney(world, 103000)
        test.assertEqual(300, character(world).outstandingCopper)

        -- A roster update with no change in guild does not notify again.
        fixtures.fire(world, "GUILD_ROSTER_UPDATE")
        test.assertEqual(4, changes)
    end)

    test.test(profile .. " a guildless character with old settings seeds the guild it joins mid-session", function()
        local world = fixtures.newEnvironment(profile, {
            inGuild = false,
            database = {
                schemaVersion = 4,
                characters = {
                    ["jaina-camelot"] = {
                        identity = { displayName = "Jaina", displayRealm = "Camelot" },
                        percentage = 30,
                        outstandingCopper = 0,
                        fractionalRemainder = 0,
                        chatFeedback = true,
                        autoDeposit = true,
                        sources = {
                            auctions = true, loot = true, mailbox = false, miscellaneous = true,
                            playerTrades = true, quests = true, vendorSales = true,
                        },
                        resolvedPayments = {},
                        paymentSequence = 0,
                    },
                },
                quarantinedCharacters = {},
                donations = {},
                quarantinedDonations = {},
            },
        })
        fixtures.login(world)
        local database = world.environment.AsgardsGuildTitheDB
        test.assertEqual(30, database.characters["jaina-camelot"].percentage)

        world.inGuild = true
        fixtures.fire(world, "PLAYER_GUILD_UPDATE", "player")

        local guild = database.guilds["knights of camelot-camelot"]
        test.assertEqual(30, guild.percentage)
        test.assertTrue(guild.sources.auctions)
        test.assertEqual(nil, database.characters["jaina-camelot"].percentage)
        test.assertEqual(30, world.settings.bindings.AsgardsGuildTithe_Percentage.getValue())
    end)
end

local guildIndex
for guildIndex = 1, #fixtures.PROFILES do
    registerGuildTests(fixtures.PROFILES[guildIndex])
end


local ADVANCED_CONTROLS = {
    "AsgardsGuildTithe_SourcePercentage_Loot",
    "AsgardsGuildTithe_SourcePercentage_Quests",
    "AsgardsGuildTithe_SourcePercentage_VendorSales",
    "AsgardsGuildTithe_SourcePercentage_Auctions",
    "AsgardsGuildTithe_SourcePercentage_Mailbox",
    "AsgardsGuildTithe_SourcePercentage_PlayerTrades",
    "AsgardsGuildTithe_SourcePercentage_Miscellaneous",
}

local function assertControlsEnabled(world, variables, expected)
    local index
    for index = 1, #variables do
        local variable = variables[index]
        test.assertEqual(expected, world.settings.controls[variable]:IsEnabled(), variable)
    end
end

local function assertControlsShown(world, variables, expected)
    local index
    for index = 1, #variables do
        local variable = variables[index]
        test.assertEqual(expected, world.settings.controls[variable]:IsShown(), variable)
    end
end

local function registerAdvancedModeTests(profile)
    test.test(profile .. " advanced mode swaps which tithe controls are shown", function()
        local world = fixtures.newEnvironment(profile)
        fixtures.login(world)
        local bindings = world.settings.bindings

        test.assertFalse(bindings.AsgardsGuildTithe_AdvancedMode.getValue())
        test.assertTrue(world.settings.controls.AsgardsGuildTithe_AdvancedMode:IsShown())
        test.assertTrue(world.settings.controls.AsgardsGuildTithe_AdvancedMode:IsEnabled())
        assertControlsShown(world, GUILD_CONTROLS, true)
        assertControlsShown(world, ADVANCED_CONTROLS, false)
        assertControlsEnabled(world, GUILD_CONTROLS, true)
        assertControlsEnabled(world, ADVANCED_CONTROLS, true)
        -- Before the first switch, the sliders hold where each source starts.
        test.assertEqual(10, bindings.AsgardsGuildTithe_SourcePercentage_Loot.getValue())
        test.assertEqual(0, bindings.AsgardsGuildTithe_SourcePercentage_Auctions.getValue())

        local relayouts = world.settings.relayouts
        test.assertTrue(bindings.AsgardsGuildTithe_AdvancedMode.setValue(true))
        test.assertTrue(bindings.AsgardsGuildTithe_AdvancedMode.getValue())
        test.assertEqual(relayouts + 1, world.settings.relayouts)
        test.assertTrue(world.settings.controls.AsgardsGuildTithe_AdvancedMode:IsShown())
        assertControlsShown(world, GUILD_CONTROLS, false)
        assertControlsShown(world, ADVANCED_CONTROLS, true)

        -- Moving a slider shows and hides nothing, so the page (and the
        -- player's drag) is left alone.
        test.assertTrue(bindings.AsgardsGuildTithe_SourcePercentage_Loot.setValue(34))
        test.assertTrue(bindings.AsgardsGuildTithe_SourcePercentage_Loot.setValue(35))
        test.assertEqual(relayouts + 1, world.settings.relayouts)
        test.assertEqual(35, bindings.AsgardsGuildTithe_SourcePercentage_Loot.getValue())
        local guild = world.environment.AsgardsGuildTitheDB.guilds["knights of camelot-camelot"]
        test.assertTrue(guild.advancedMode)
        test.assertEqual(35, guild.sourcePercentages.loot)
        test.assertFalse(bindings.AsgardsGuildTithe_SourcePercentage_Loot.setValue(101))

        test.assertTrue(bindings.AsgardsGuildTithe_AdvancedMode.setValue(false))
        test.assertEqual(relayouts + 2, world.settings.relayouts)
        assertControlsShown(world, GUILD_CONTROLS, true)
        assertControlsShown(world, ADVANCED_CONTROLS, false)
        test.assertEqual(35, bindings.AsgardsGuildTithe_SourcePercentage_Loot.getValue())

        test.assertTrue(bindings.AsgardsGuildTithe_Source_Loot.setValue(false))
        test.assertTrue(bindings.AsgardsGuildTithe_Percentage.setValue(20))
        test.assertEqual(relayouts + 2, world.settings.relayouts)
    end)

    test.test(profile .. " moving to a guild in the other mode shows that mode's controls", function()
        local world = fixtures.newEnvironment(profile)
        fixtures.login(world)
        test.assertTrue(world.settings.bindings.AsgardsGuildTithe_AdvancedMode.setValue(true))

        local relayouts = world.settings.relayouts
        world.guildName = "Horde Lords"
        fixtures.fire(world, "PLAYER_GUILD_UPDATE", "player")

        test.assertEqual(relayouts + 1, world.settings.relayouts)
        assertControlsShown(world, GUILD_CONTROLS, true)
        assertControlsShown(world, ADVANCED_CONTROLS, false)
    end)

    test.test(profile .. " the open settings panel is laid out again without the inbound helper", function()
        local world = fixtures.newEnvironment(profile)
        fixtures.login(world)
        local repaired = 0
        world.environment.SettingsInbound = nil
        world.environment.SettingsPanel = {
            RepairDisplay = function(panel)
                test.assertEqual(world.environment.SettingsPanel, panel)
                repaired = repaired + 1
            end,
        }

        test.assertTrue(world.settings.bindings.AsgardsGuildTithe_AdvancedMode.setValue(true))

        test.assertEqual(1, repaired)
    end)

    test.test(profile .. " a client that cannot hide controls greys out the other mode's instead", function()
        local world = fixtures.newEnvironment(profile, { canHideSettings = false })
        fixtures.login(world)
        local bindings = world.settings.bindings

        assertControlsShown(world, GUILD_CONTROLS, true)
        assertControlsShown(world, ADVANCED_CONTROLS, true)
        assertControlsEnabled(world, GUILD_CONTROLS, true)
        assertControlsEnabled(world, ADVANCED_CONTROLS, false)

        local relayouts = world.settings.relayouts
        test.assertTrue(bindings.AsgardsGuildTithe_AdvancedMode.setValue(true))
        test.assertEqual(relayouts, world.settings.relayouts)
        test.assertTrue((world.settings.notified.AsgardsGuildTithe_SourcePercentage_Loot or 0) >= 1)
        test.assertTrue((world.settings.notified.AsgardsGuildTithe_Percentage or 0) >= 1)
        assertControlsEnabled(world, GUILD_CONTROLS, false)
        assertControlsEnabled(world, ADVANCED_CONTROLS, true)
        test.assertTrue(world.settings.controls.AsgardsGuildTithe_AdvancedMode:IsEnabled())
    end)

    test.test(profile .. " per-source sliders reuse the source labels", function()
        local world = fixtures.newEnvironment(profile)
        fixtures.login(world)
        local slider = world.settings.bindings.AsgardsGuildTithe_SourcePercentage_Loot
        local checkbox = world.settings.bindings.AsgardsGuildTithe_Source_Loot

        test.assertEqual("number", slider.variableType)
        test.assertEqual(checkbox.label, slider.label)
        test.assertEqual("Advanced mode: set a percentage for each income source",
            world.settings.bindings.AsgardsGuildTithe_AdvancedMode.label)
    end)

    test.test(profile .. " a guildless character sees the simple controls greyed out", function()
        local world = fixtures.newEnvironment(profile, { inGuild = false })
        fixtures.login(world)
        local bindings = world.settings.bindings

        test.assertFalse(world.settings.controls.AsgardsGuildTithe_AdvancedMode:IsEnabled())
        assertControlsShown(world, GUILD_CONTROLS, true)
        assertControlsShown(world, ADVANCED_CONTROLS, false)
        assertControlsEnabled(world, GUILD_CONTROLS, false)
        test.assertFalse(bindings.AsgardsGuildTithe_AdvancedMode.setValue(true))
        test.assertFalse(bindings.AsgardsGuildTithe_SourcePercentage_Loot.setValue(20))
    end)
end

local advancedIndex
for advancedIndex = 1, #fixtures.PROFILES do
    registerAdvancedModeTests(fixtures.PROFILES[advancedIndex])
end
