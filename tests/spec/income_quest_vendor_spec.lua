local test = require("tests.test_helper")
local fixtures = require("tests.client_fixtures")

local STARTING_MONEY = 500000

local function character(world)
    return world.environment.AsgardsGuildTitheDB.characters["jaina-camelot"]
end

local function newWorld(profile)
    local world = fixtures.newEnvironment(profile, { money = STARTING_MONEY })
    fixtures.login(world)
    return world
end

local function lastMessage(world)
    return world.messages[#world.messages]
end

local function turnInQuest(world, reward)
    fixtures.fire(world, "QUEST_COMPLETE")
    fixtures.fire(world, "QUEST_TURNED_IN", 66115, 10465, reward)
    fixtures.fire(world, "QUEST_FINISHED")
end

local function registerProfileTests(profile)
    test.test(profile .. " quest money classifies as quest income", function()
        local world = newWorld(profile)

        turnInQuest(world, 25505)
        fixtures.advance(world, 0.2)
        fixtures.setMoney(world, STARTING_MONEY + 25505)

        test.assertContains(lastMessage(world), "from quest income")
        test.assertEqual(2550, character(world).outstandingCopper)
    end)

    test.test(profile .. " a quest reward that does not match the gain is not quest income", function()
        local world = newWorld(profile)

        turnInQuest(world, 25505)
        fixtures.setMoney(world, STARTING_MONEY + 1000)

        test.assertContains(lastMessage(world), "from miscellaneous/system income")
    end)

    test.test(profile .. " a malformed quest reward still counts by timing", function()
        local world = newWorld(profile)

        fixtures.fire(world, "QUEST_TURNED_IN", 66115, 10465, "lots")
        fixtures.setMoney(world, STARTING_MONEY + 1000)

        test.assertContains(lastMessage(world), "from quest income")
    end)

    test.test(profile .. " an item-only quest accrues nothing", function()
        local world = newWorld(profile)
        local before = fixtures.snapshot(character(world))

        turnInQuest(world, 0)
        fixtures.advance(world, 5)

        fixtures.assertSameData(before, character(world))
        test.assertEqual(0, #world.messages)
    end)

    test.test(profile .. " rapid vendor sales each count once and share one message", function()
        local world = newWorld(profile)

        fixtures.fire(world, "MERCHANT_SHOW")
        fixtures.setMoney(world, STARTING_MONEY + 1000, false)
        fixtures.advance(world, 0.4)
        -- Each sale is saved as soon as it finalizes, before any message.
        test.assertEqual(100, character(world).outstandingCopper)
        fixtures.setMoney(world, STARTING_MONEY + 3000, false)
        fixtures.advance(world, 0.4)
        test.assertEqual(300, character(world).outstandingCopper)
        fixtures.setMoney(world, STARTING_MONEY + 6000, false)
        fixtures.fire(world, "MERCHANT_UPDATE")
        fixtures.advance(world, 0.4)
        test.assertEqual(600, character(world).outstandingCopper)
        test.assertEqual(0, #world.messages)

        fixtures.fire(world, "MERCHANT_CLOSED")
        fixtures.advance(world, 5)

        test.assertEqual(1, #world.messages)
        test.assertEqual(
            "Asgard's Guild Tithe: reserved 0g 06s 00c from vendor sale income. Total owed: 0g 06s 00c.",
            world.messages[1]
        )
    end)

    test.test(profile .. " gold looted after closing a vendor is loot, not a vendor sale", function()
        local world = newWorld(profile)

        fixtures.fire(world, "MERCHANT_SHOW")
        fixtures.fire(world, "MERCHANT_CLOSED")
        fixtures.fire(world, "CHAT_MSG_MONEY", "You loot 10 Silver")
        fixtures.setMoney(world, STARTING_MONEY + 1000)
        test.assertContains(lastMessage(world), "from loot income")

        fixtures.advance(world, 5)
        fixtures.setMoney(world, STARTING_MONEY + 2000)
        test.assertContains(lastMessage(world), "from miscellaneous/system income")
    end)

    test.test(profile .. " a quest turned in at a vendor is quest income", function()
        local world = newWorld(profile)

        fixtures.fire(world, "MERCHANT_SHOW")
        turnInQuest(world, 5000)
        fixtures.setMoney(world, STARTING_MONEY + 5000)

        test.assertContains(lastMessage(world), "from quest income")
    end)

    test.test(profile .. " disabled quest and vendor sources leave the tithe unchanged", function()
        local world = newWorld(profile)
        world.settings.bindings.AsgardsGuildTithe_Source_Quests.setValue(false)
        world.settings.bindings.AsgardsGuildTithe_Source_VendorSales.setValue(false)
        local before = fixtures.snapshot(character(world))

        turnInQuest(world, 5000)
        fixtures.setMoney(world, STARTING_MONEY + 5000)
        fixtures.advance(world, 5)
        fixtures.fire(world, "MERCHANT_SHOW")
        fixtures.setMoney(world, STARTING_MONEY + 7000)

        fixtures.assertSameData(before, character(world))
        test.assertEqual(0, #world.messages)
    end)
end

local profileIndex
for profileIndex = 1, #fixtures.PROFILES do
    registerProfileTests(fixtures.PROFILES[profileIndex])
end

local function newCorrelator()
    local addon = test.newAddon("Core/IncomeCorrelator.lua")
    return addon.IncomeCorrelator.Create()
end

test.test("correlator: an amount note only explains a gain of that exact size", function()
    local correlator = newCorrelator()
    correlator:Record("quests", "note", 10, 25505)

    test.assertEqual("quests", (correlator:Classify(10.2, 10.5, 25505)))
    test.assertEqual("miscellaneous", (correlator:Classify(10.2, 10.5, 25506)))
end)

test.test("correlator: a note outranks an open interaction", function()
    local correlator = newCorrelator()
    correlator:Record("vendorSales", "open", 5)
    correlator:Record("loot", "note", 10)

    test.assertEqual("loot", (correlator:Classify(10.1, 10.4, 1000)))
    test.assertEqual("vendorSales", (correlator:Classify(20, 20.3, 1000)))
end)

test.test("correlator: a negative or non-numeric note amount is ignored", function()
    local correlator = newCorrelator()
    correlator:Record("quests", "note", 10, -5)
    correlator:Record("quests", "note", 10, "many")

    test.assertEqual("quests", (correlator:Classify(10.1, 10.4, 777)))
end)

test.test("correlator: exact-amount notes wait longer than timing-only notes", function()
    local correlator = newCorrelator()
    correlator:Record("mailbox", "note", 10, 700)
    correlator:Record("loot", "note", 10)

    test.assertEqual("miscellaneous", (correlator:Classify(15, 15.3, 999)))
    test.assertEqual("mailbox", (correlator:Classify(15, 15.3, 700)))

    correlator:Record("mailbox", "note", 20, 700)
    test.assertEqual("miscellaneous", (correlator:Classify(35, 35.3, 700)))
end)
