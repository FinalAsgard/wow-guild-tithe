local test = require("tests.test_helper")
local fixtures = require("tests.client_fixtures")

local function newCorrelator()
    local addon = test.newAddon("Core/IncomeCorrelator.lua")
    return addon.IncomeCorrelator.Create(), addon.IncomeCorrelator
end

-- Each case replays context records { at, source, action } and then
-- classifies a gain observed at `observedAt` and finalized at `finalizedAt`.
local CASES = {
    {
        name = "no context falls back to miscellaneous",
        records = {},
        observedAt = 10, finalizedAt = 10.3,
        source = "miscellaneous",
    },
    {
        name = "an open loot window explains the gain",
        records = { { 9, "loot", "open" } },
        observedAt = 10, finalizedAt = 10.3,
        source = "loot",
    },
    {
        name = "a loot window closed within the grace period still explains it",
        records = { { 9, "loot", "open" }, { 9.5, "loot", "close" } },
        observedAt = 10, finalizedAt = 10.3,
        source = "loot",
    },
    {
        name = "a loot window closed beyond the grace period does not",
        records = { { 5, "loot", "open" }, { 6, "loot", "close" } },
        observedAt = 10, finalizedAt = 10.3,
        source = "miscellaneous",
    },
    {
        name = "a loot message just before the gain explains it",
        records = { { 9.5, "loot", "note" } },
        observedAt = 10, finalizedAt = 10.3,
        source = "loot",
    },
    {
        name = "a loot message after the gain but before finalization still counts",
        records = { { 10.1, "loot", "note" } },
        observedAt = 10, finalizedAt = 10.3,
        source = "loot",
    },
    {
        name = "an expired loot message does not explain a later gain",
        records = { { 7, "loot", "note" } },
        observedAt = 10, finalizedAt = 10.3,
        source = "miscellaneous",
    },
    {
        name = "a loot message after finalization does not count",
        records = { { 10.5, "loot", "note" } },
        observedAt = 10, finalizedAt = 10.3,
        source = "miscellaneous",
    },
    {
        name = "a loot window opened after the gain does not explain it",
        records = { { 10.1, "loot", "open" } },
        observedAt = 10, finalizedAt = 10.3,
        source = "miscellaneous",
    },
    {
        name = "a loot window that never closed stops counting after the limit",
        records = { { 10, "loot", "open" } },
        observedAt = 200, finalizedAt = 200.3,
        source = "miscellaneous",
    },
    {
        name = "context for an unknown source is ignored",
        records = { { 9.9, "unknownSource", "note" } },
        observedAt = 10, finalizedAt = 10.3,
        source = "miscellaneous",
    },
}

local caseIndex
for caseIndex = 1, #CASES do
    local case = CASES[caseIndex]
    test.test("correlator: " .. case.name, function()
        local correlator = newCorrelator()
        local index
        for index = 1, #case.records do
            local record = case.records[index]
            correlator:Record(record[2], record[3], record[1])
        end

        local source, reason = correlator:Classify(case.observedAt, case.finalizedAt)

        test.assertEqual(case.source, source)
        test.assertEqual("string", type(reason))
    end)
end

test.test("correlator rejects malformed context and classifies without a clock", function()
    local correlator = newCorrelator()

    test.assertFalse(correlator:Record(nil, "open", 1))
    test.assertFalse(correlator:Record("loot", "sideways", 1))
    test.assertFalse(correlator:Record("loot", "open", nil))
    test.assertFalse(correlator:Record("loot", "open", 0 / 0))

    local source, reason = correlator:Classify(nil, 5)
    test.assertEqual("miscellaneous", source)
    test.assertContains(reason, "no clock")
end)

test.test("correlator reset discards pending context", function()
    local correlator = newCorrelator()
    correlator:Record("loot", "open", 9)
    correlator:Record("loot", "note", 9.9)

    correlator:Reset()

    test.assertEqual("miscellaneous", (correlator:Classify(10, 10.3)))
end)

test.test("correlator keeps a bounded number of notes and prunes expired context", function()
    local correlator, module = newCorrelator()
    local index
    for index = 1, module.MAX_NOTES + 10 do
        correlator:Record("loot", "note", index)
    end
    test.assertEqual(module.MAX_NOTES, #correlator.notes)

    correlator:Record("loot", "open", 100)
    correlator:Record("loot", "close", 101)
    correlator:Prune(500)

    test.assertEqual(0, #correlator.notes)
    test.assertEqual(nil, correlator.sessions.loot)
end)

local STARTING_MONEY = 500000

local function character(world)
    return world.environment.AsgardsGuildTitheDB.characters["jaina-camelot"]
end

local function newWorld(profile)
    local world = fixtures.newEnvironment(profile, { money = STARTING_MONEY })
    local addon = fixtures.login(world)
    return world, addon
end

local function lastMessage(world)
    return world.messages[#world.messages]
end

local function registerProfileTests(profile)
    test.test(profile .. " looting coin from a corpse classifies as loot", function()
        local world = newWorld(profile)

        fixtures.fire(world, "LOOT_OPENED", 0)
        fixtures.setMoney(world, STARTING_MONEY + 1000)
        fixtures.fire(world, "LOOT_CLOSED")

        test.assertEqual(100, character(world).outstandingCopper)
        test.assertContains(lastMessage(world), "from loot income")
    end)

    test.test(profile .. " a shared party coin message classifies as loot in either order", function()
        local world = newWorld(profile)

        fixtures.fire(world, "CHAT_MSG_MONEY", "Your share of the loot is 10 Silver.")
        fixtures.setMoney(world, STARTING_MONEY + 1000)
        test.assertContains(lastMessage(world), "from loot income")

        fixtures.advance(world, 5)
        fixtures.setMoney(world, STARTING_MONEY + 2000, false)
        fixtures.fire(world, "CHAT_MSG_MONEY", "Your share of the loot is 10 Silver.")
        fixtures.advance(world, 1)

        test.assertEqual(2, #world.messages)
        test.assertContains(lastMessage(world), "from loot income")
        test.assertEqual(200, character(world).outstandingCopper)
    end)

    test.test(profile .. " repeated loot and money events accrue a gain once", function()
        local world = newWorld(profile)

        fixtures.fire(world, "LOOT_OPENED", 0)
        fixtures.fire(world, "LOOT_OPENED", 0)
        fixtures.fire(world, "CHAT_MSG_MONEY", "You loot 10 Silver")
        fixtures.fire(world, "CHAT_MSG_MONEY", "You loot 10 Silver")
        fixtures.setMoney(world, STARTING_MONEY + 1000)
        fixtures.fire(world, "PLAYER_MONEY")
        fixtures.fire(world, "PLAYER_MONEY")
        fixtures.fire(world, "LOOT_CLOSED")
        fixtures.fire(world, "LOOT_CLOSED")
        fixtures.advance(world, 5)

        test.assertEqual(100, character(world).outstandingCopper)
        test.assertEqual(1, #world.messages)
    end)

    test.test(profile .. " expired loot context does not classify a later gain", function()
        local world = newWorld(profile)

        fixtures.fire(world, "LOOT_OPENED", 0)
        fixtures.fire(world, "LOOT_CLOSED")
        fixtures.fire(world, "CHAT_MSG_MONEY", "You loot 10 Silver")
        fixtures.advance(world, 10)
        fixtures.setMoney(world, STARTING_MONEY + 1000)

        test.assertContains(lastMessage(world), "from miscellaneous/system income")
    end)

    test.test(profile .. " loot disabled ignores loot gains without touching the tithe", function()
        local world = newWorld(profile)
        world.settings.bindings.AsgardsGuildTithe_Source_Loot.setValue(false)
        local before = fixtures.snapshot(character(world))

        fixtures.fire(world, "LOOT_OPENED", 0)
        fixtures.setMoney(world, STARTING_MONEY + 1000)

        fixtures.assertSameData(before, character(world))
        test.assertEqual(0, #world.messages)
    end)

    test.test(profile .. " a setting changed while a gain is pending applies at finalization", function()
        local world = newWorld(profile)

        fixtures.fire(world, "LOOT_OPENED", 0)
        fixtures.setMoney(world, STARTING_MONEY + 1000, false)
        world.settings.bindings.AsgardsGuildTithe_Source_Loot.setValue(false)
        fixtures.advance(world, 1)

        test.assertEqual(0, character(world).outstandingCopper)
        test.assertEqual(0, #world.messages)
    end)

    test.test(profile .. " loot context from before login is discarded", function()
        local world = fixtures.newEnvironment(profile, { money = STARTING_MONEY })
        fixtures.loadAddon(world)
        fixtures.fire(world, "ADDON_LOADED", "AsgardsGuildTithe")
        fixtures.fire(world, "LOOT_OPENED", 0)
        world.playerReady = true
        fixtures.fire(world, "PLAYER_LOGIN")

        fixtures.setMoney(world, STARTING_MONEY + 1000)

        test.assertContains(lastMessage(world), "from miscellaneous/system income")
    end)

    test.test(profile .. " malformed context payloads are ignored safely", function()
        local world = newWorld(profile)

        fixtures.fire(world, "CHAT_MSG_MONEY", {}, nil, 42)
        fixtures.fire(world, "LOOT_OPENED", "not a number")
        fixtures.setMoney(world, STARTING_MONEY + 1000)

        test.assertContains(lastMessage(world), "from loot income")
        test.assertEqual(100, character(world).outstandingCopper)
    end)

    test.test(profile .. " interleaved gains each keep their own source", function()
        local world = newWorld(profile)

        fixtures.fire(world, "LOOT_OPENED", 0)
        fixtures.setMoney(world, STARTING_MONEY + 1000, false)
        fixtures.fire(world, "LOOT_CLOSED")
        -- The first gain keeps its loot context; a second gain after the
        -- loot grace period has passed must not inherit it.
        fixtures.advance(world, 3)
        fixtures.setMoney(world, STARTING_MONEY + 3000)

        test.assertEqual(2, #world.messages)
        test.assertContains(world.messages[1], "from loot income")
        test.assertContains(world.messages[2], "from miscellaneous/system income")
        test.assertEqual(300, character(world).outstandingCopper)
    end)
end

local profileIndex
for profileIndex = 1, #fixtures.PROFILES do
    registerProfileTests(fixtures.PROFILES[profileIndex])
end

test.test("a new money change finalizes the previous pending gain first", function()
    local world, addon = newWorld("Retail")

    fixtures.fire(world, "LOOT_OPENED", 0)
    world.money = STARTING_MONEY + 1000
    local first = addon.incomeObserver:OnMoneyChanged()
    world.money = STARTING_MONEY + 1500
    local second = addon.incomeObserver:OnMoneyChanged()

    test.assertEqual("loot", first.source)
    test.assertEqual(nil, second.source)
    test.assertEqual(2, second.id)
    test.assertEqual(100, character(world).outstandingCopper)

    local result = addon.incomeObserver:FinalizePending()
    test.assertEqual("accrued", result.status)
    test.assertEqual("loot", result.source)
    test.assertContains(result.reason, "loot interaction was open")
    test.assertEqual(150, character(world).outstandingCopper)
end)
