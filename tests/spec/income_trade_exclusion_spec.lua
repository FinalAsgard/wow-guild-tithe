local test = require("tests.test_helper")
local fixtures = require("tests.client_fixtures")

local STARTING_MONEY = 500000

local function character(world)
    return world.environment.AsgardsGuildTitheDB.characters["jaina-camelot"]
end

local function newWorld(profile, purchases)
    local world = fixtures.newEnvironment(profile, { money = STARTING_MONEY })
    fixtures.installTransferCalls(world, purchases or {})
    fixtures.login(world)
    return world
end

local function lastMessage(world)
    return world.messages[#world.messages]
end

local function registerProfileTests(profile)
    test.test(profile .. " money from a completed trade is player trade income", function()
        local world = newWorld(profile)

        fixtures.fire(world, "TRADE_SHOW")
        fixtures.fire(world, "TRADE_MONEY_CHANGED")
        fixtures.fire(world, "TRADE_ACCEPT_UPDATE", 1, 1)
        fixtures.setMoney(world, STARTING_MONEY + 50000, false)
        fixtures.fire(world, "TRADE_CLOSED")
        fixtures.fire(world, "TRADE_CLOSED")
        fixtures.settle(world)

        test.assertEqual(1, #world.messages)
        test.assertContains(lastMessage(world), "from player trade income")
        test.assertEqual(5000, character(world).outstandingCopper)
    end)

    test.test(profile .. " a trade seen only through the interaction manager is still a trade", function()
        local world = newWorld(profile)

        fixtures.fire(world, "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 1)
        fixtures.fire(world, "PLAYER_INTERACTION_MANAGER_FRAME_HIDE", 1)
        fixtures.setMoney(world, STARTING_MONEY + 50000)

        test.assertContains(lastMessage(world), "from player trade income")
    end)

    test.test(profile .. " a cancelled trade records nothing", function()
        local world = newWorld(profile)
        local before = fixtures.snapshot(character(world))

        fixtures.fire(world, "TRADE_SHOW")
        fixtures.fire(world, "TRADE_MONEY_CHANGED")
        fixtures.fire(world, "TRADE_REQUEST_CANCEL")
        fixtures.fire(world, "TRADE_CLOSED")
        fixtures.advance(world, 5)

        fixtures.assertSameData(before, character(world))
        test.assertEqual(0, #world.messages)
    end)

    test.test(profile .. " disabled player trades leave the tithe unchanged", function()
        local world = newWorld(profile)
        world.settings.bindings.AsgardsGuildTithe_Source_PlayerTrades.setValue(false)
        local before = fixtures.snapshot(character(world))

        fixtures.fire(world, "TRADE_SHOW")
        fixtures.setMoney(world, STARTING_MONEY + 50000, false)
        fixtures.fire(world, "TRADE_CLOSED")
        fixtures.advance(world, 1)

        fixtures.assertSameData(before, character(world))
    end)

    test.test(profile .. " a guild-bank withdrawal is excluded, never miscellaneous", function()
        local world = newWorld(profile)
        local before = fixtures.snapshot(character(world))

        fixtures.fire(world, "GUILDBANKFRAME_OPENED")
        world.environment.WithdrawGuildBankMoney(100000)
        fixtures.setMoney(world, STARTING_MONEY + 100000)
        fixtures.fire(world, "GUILDBANKFRAME_CLOSED")

        fixtures.assertSameData(before, character(world))
        test.assertEqual(0, #world.messages)
    end)

    test.test(profile .. " a guild-bank withdrawal seen through the interaction manager is excluded", function()
        local world = newWorld(profile)
        local before = fixtures.snapshot(character(world))

        fixtures.fire(world, "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 10)
        fixtures.setMoney(world, STARTING_MONEY + 100000)
        fixtures.fire(world, "PLAYER_INTERACTION_MANAGER_FRAME_HIDE", 10)

        fixtures.assertSameData(before, character(world))
    end)

    test.test(profile .. " guild funds updates with the bank closed never exclude a gain", function()
        local world = newWorld(profile)

        fixtures.fire(world, "GUILDBANK_UPDATE_MONEY")
        fixtures.fire(world, "GUILDBANK_UPDATE_WITHDRAWMONEY")
        fixtures.setMoney(world, STARTING_MONEY + 1000)

        test.assertContains(lastMessage(world), "from miscellaneous/system income")
    end)

    test.test(profile .. " an item refund at a vendor is excluded while real sales still count", function()
        local world = newWorld(profile, { ["0:3"] = 5000 })

        fixtures.fire(world, "MERCHANT_SHOW")
        world.environment.C_Container.ContainerRefundItemPurchase(0, 3)
        fixtures.setMoney(world, STARTING_MONEY + 5000)
        test.assertEqual(0, character(world).outstandingCopper)
        test.assertEqual(0, #world.messages)

        fixtures.setMoney(world, STARTING_MONEY + 6000)
        test.assertContains(lastMessage(world), "from vendor sale income")
        test.assertEqual(100, character(world).outstandingCopper)
    end)

    test.test(profile .. " a refund whose money arrives seconds later is still excluded", function()
        local world = newWorld(profile, { ["0:3"] = 5000 })

        fixtures.fire(world, "MERCHANT_SHOW")
        world.environment.C_Container.ContainerRefundItemPurchase(0, 3)
        fixtures.advance(world, 3)
        fixtures.setMoney(world, STARTING_MONEY + 5000)

        test.assertEqual(0, character(world).outstandingCopper)
        test.assertEqual(0, #world.messages)
    end)

    test.test(profile .. " a refund without a reported price is excluded by timing", function()
        local world = newWorld(profile)

        fixtures.fire(world, "MERCHANT_SHOW")
        world.environment.C_Container.ContainerRefundItemPurchase(1, 1)
        fixtures.setMoney(world, STARTING_MONEY + 5000)

        test.assertEqual(0, character(world).outstandingCopper)
        test.assertEqual(0, #world.messages)
    end)

    test.test(profile .. " long vendor, trade, and guild-bank sessions keep their meaning", function()
        local world = newWorld(profile)

        fixtures.fire(world, "MERCHANT_SHOW")
        fixtures.advance(world, 600)
        fixtures.setMoney(world, STARTING_MONEY + 1000)
        test.assertContains(world.messages[#world.messages], "from vendor sale income")
        fixtures.fire(world, "MERCHANT_CLOSED")
        fixtures.advance(world, 5)

        fixtures.fire(world, "TRADE_SHOW")
        fixtures.advance(world, 300)
        fixtures.setMoney(world, STARTING_MONEY + 2000, false)
        fixtures.fire(world, "TRADE_CLOSED")
        fixtures.settle(world)
        test.assertContains(world.messages[#world.messages], "from player trade income")
        fixtures.advance(world, 5)

        -- A withdrawal after ten minutes at the guild bank, with no hooked
        -- withdraw call, must still be excluded rather than tithed.
        local owed = character(world).outstandingCopper
        local messages = #world.messages
        character(world).autoDeposit = false
        fixtures.fire(world, "GUILDBANKFRAME_OPENED")
        fixtures.advance(world, 600)
        fixtures.setMoney(world, STARTING_MONEY + 102000)
        test.assertEqual(owed, character(world).outstandingCopper)
        test.assertEqual(messages, #world.messages)
    end)

    test.test(profile .. " depositing into the guild bank changes nothing", function()
        local world = newWorld(profile)
        local before = fixtures.snapshot(character(world))

        fixtures.fire(world, "GUILDBANKFRAME_OPENED")
        fixtures.setMoney(world, STARTING_MONEY - 20000)
        fixtures.fire(world, "GUILDBANKFRAME_CLOSED")

        fixtures.assertSameData(before, character(world))
    end)
end

local profileIndex
for profileIndex = 1, #fixtures.PROFILES do
    registerProfileTests(fixtures.PROFILES[profileIndex])
end

test.test("correlator: exclusions outrank a vendor window and the miscellaneous fallback", function()
    local addon = test.newAddon("Core/IncomeCorrelator.lua")
    local correlator = addon.IncomeCorrelator.Create()
    correlator:Record("vendorSales", "open", 5)
    correlator:Record("guildBankWithdrawal", "open", 5)

    local source, _, excluded = correlator:Classify(10, 10.3, 1000)

    test.assertEqual("guildBankWithdrawal", source)
    test.assertTrue(excluded)
end)
