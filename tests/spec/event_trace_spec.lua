local test = require("tests.test_helper")
local fixtures = require("tests.client_fixtures")

local DEV = "AsgardsGuildTitheDev"

local function loginDev(profile, options)
    local world = fixtures.newEnvironment(profile, options)
    world.environment.GetBuildInfo = function()
        return "12.1.0", "69933", "Sep 18 2026", 120100
    end
    world.environment.GetTime = function()
        return 100.5
    end
    local addon = fixtures.loadAddon(world, DEV)
    fixtures.fire(world, "ADDON_LOADED", DEV)
    world.playerReady = true
    fixtures.fire(world, "PLAYER_LOGIN")
    return world, addon
end

local function trace(world, arguments)
    world.environment.SlashCmdList.AGTDEV("trace " .. arguments)
    return world.messages[#world.messages]
end

local function entries(world)
    return world.environment.AsgardsGuildTitheDevTraceDB.entries
end

local function registeredFor(world, eventName)
    local count = 0
    local index
    for index = 1, #world.frames do
        if world.frames[index].registeredEvents[eventName] then
            count = count + 1
        end
    end
    return count
end

local function registerProfileTests(profile)
    test.test(profile .. " dev trace records guild-bank calls, blocks, and the add-on's messages", function()
        local world = fixtures.newEnvironment(profile, { money = 100000 })
        world.environment.GetTime = function()
            return 100.5
        end
        fixtures.installTransferCalls(world, {})
        local addon = fixtures.loadAddon(world, DEV)
        fixtures.fire(world, "ADDON_LOADED", DEV)
        world.playerReady = true
        fixtures.fire(world, "PLAYER_LOGIN")
        local character = world.environment.AsgardsGuildTitheDevDB.characters["jaina-camelot"]
        character.outstandingCopper = 5000
        trace(world, "start")

        fixtures.fire(world, "GUILDBANKFRAME_OPENED")
        fixtures.advance(world, 1)
        fixtures.fire(world, "ADDON_ACTION_BLOCKED", DEV, "SomeCall()")
        world.environment.WithdrawGuildBankMoney(700)
        fixtures.setMoney(world, 95000)

        local found = {}
        local index
        for index = 1, #entries(world) do
            local entry = entries(world)[index]
            found[entry.kind .. ":" .. entry.name] = entry
        end
        test.assertEqual(5000, found["call:DepositGuildBankMoney"].args[1])
        test.assertEqual(700, found["call:WithdrawGuildBankMoney"].args[1])
        test.assertEqual("SomeCall()", found["event:ADDON_ACTION_BLOCKED"].args[2])
        test.assertContains(found["chat:message"].args[1], "deposited 0g 50s 00c")
        test.assertEqual(0, character.outstandingCopper)
    end)

    test.test(profile .. " production build has no trace command or trace data", function()
        local world = fixtures.newEnvironment(profile)
        local addon = fixtures.login(world)

        world.environment.SlashCmdList.AGT("help")

        test.assertEqual(nil, addon.eventTrace)
        test.assertEqual(nil, string.find(world.messages[1], "trace", 1, true))
        test.assertEqual(nil, rawget(world.environment, "AsgardsGuildTitheDevTraceDB"))
    end)

    test.test(profile .. " dev trace is off until started and records events with money", function()
        local world = loginDev(profile, { money = 1000 })

        -- Income tracking also listens for money messages; the trace adds its
        -- own registration only while running.
        local listeners = registeredFor(world, "CHAT_MSG_MONEY")
        test.assertContains(trace(world, "status"), "is stopped with 0 entries")

        test.assertContains(trace(world, "start"), "trace started.")
        test.assertEqual(listeners + 1, registeredFor(world, "CHAT_MSG_MONEY"))
        world.money = 1250
        fixtures.fire(world, "CHAT_MSG_MONEY", "You loot 2 Silver 50 Copper")

        local database = world.environment.AsgardsGuildTitheDevTraceDB
        test.assertEqual("WoW " .. profile, database.header.client)
        test.assertEqual("12.1.0", database.header.build[2])
        local last = database.entries[#database.entries]
        test.assertEqual("event", last.kind)
        test.assertEqual("CHAT_MSG_MONEY", last.name)
        test.assertEqual("You loot 2 Silver 50 Copper", last.args[1])
        test.assertEqual(1250, last.money)
        test.assertEqual(100.5, last.t)
        test.assertFalse(last.combat)
    end)

    test.test(profile .. " stopping the dev trace unregisters events and stops recording", function()
        local world = loginDev(profile)
        local listeners = registeredFor(world, "CHAT_MSG_MONEY")
        trace(world, "start")

        test.assertContains(trace(world, "stop"), "stopped")
        local count = #entries(world)
        fixtures.fire(world, "CHAT_MSG_MONEY", "ignored")

        test.assertEqual(listeners, registeredFor(world, "CHAT_MSG_MONEY"))
        test.assertEqual(count, #entries(world))
        test.assertEqual("trace stopped", entries(world)[count].name)
        test.assertContains(trace(world, "stop"), "was not running")
    end)
end

local profileIndex
for profileIndex = 1, #fixtures.PROFILES do
    registerProfileTests(fixtures.PROFILES[profileIndex])
end

test.test("dev trace skips events the client does not know", function()
    local world = loginDev("Forever")
    world.unknownEvents = { PLAYER_INTERACTION_MANAGER_FRAME_SHOW = true }

    test.assertContains(trace(world, "start"), "trace started.")

    local header = world.environment.AsgardsGuildTitheDevTraceDB.header
    test.assertEqual("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", header.skipped[1])
    test.assertEqual(1, #header.skipped)
end)

test.test("dev trace keeps only the newest entries", function()
    local world, addon = loginDev("Retail")
    addon.EventTrace.MAX_ENTRIES = 5
    trace(world, "start")

    local index
    for index = 1, 10 do
        fixtures.fire(world, "UI_INFO_MESSAGE", index)
    end

    test.assertEqual(5, #entries(world))
    test.assertEqual(10, entries(world)[5].args[1])
    test.assertEqual(6, entries(world)[1].args[1])
end)

test.test("a trimmed trace keeps the balance from before its first entry", function()
    local world, addon = loginDev("Retail", { money = 100 })
    addon.EventTrace.MAX_ENTRIES = 2
    trace(world, "start")

    world.money = 150
    fixtures.fire(world, "UI_INFO_MESSAGE", 1)
    world.money = 175
    fixtures.fire(world, "PLAYER_MONEY")
    fixtures.fire(world, "UI_INFO_MESSAGE", 2)

    local database = world.environment.AsgardsGuildTitheDevTraceDB
    test.assertEqual(2, #database.entries)
    test.assertEqual("PLAYER_MONEY", database.entries[1].name)
    test.assertEqual(150, database.baselineMoney)
end)

test.test("dev trace records mail money collection with invoice details", function()
    local world = fixtures.newEnvironment("Retail")
    local environment = world.environment
    environment.TakeInboxMoney = function() end
    environment.GetInboxInvoiceInfo = function(index)
        return "seller", "Sold Item", "Buyer", 5000, 250, 25, 0
    end
    environment.GetInboxHeaderInfo = function(index)
        return nil, nil, "Auction House", "Auction successful", 4725
    end
    environment.hooksecurefunc = function(name, hook)
        local original = environment[name]
        environment[name] = function(...)
            original(...)
            hook(...)
        end
    end
    fixtures.loadAddon(world, DEV)
    fixtures.fire(world, "ADDON_LOADED", DEV)
    world.playerReady = true
    fixtures.fire(world, "PLAYER_LOGIN")

    environment.TakeInboxMoney(3)
    test.assertEqual(nil, environment.AsgardsGuildTitheDevTraceDB)

    trace(world, "start")
    environment.TakeInboxMoney(3)

    local last = entries(world)[#entries(world)]
    test.assertEqual("call", last.kind)
    test.assertEqual("TakeInboxMoney", last.name)
    test.assertEqual(3, last.args[1])
    test.assertEqual("seller", last.extra.invoice[2])
    test.assertEqual(4725, last.extra.header[6])
end)

test.test("dev trace stores only plain values and clears on request", function()
    local world = loginDev("Forever")
    trace(world, "start")

    fixtures.fire(world, "UI_ERROR_MESSAGE", {}, nil, string.rep("x", 400), true)

    local last = entries(world)[#entries(world)]
    test.assertEqual("<table>", last.args[1])
    test.assertEqual("<nil>", last.args[2])
    test.assertEqual(255, string.len(last.args[3]))
    test.assertTrue(last.args[4])

    test.assertContains(trace(world, "clear"), "cleared.")
    test.assertEqual(0, #entries(world))
end)
