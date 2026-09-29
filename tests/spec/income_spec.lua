local test = require("tests.test_helper")
local fixtures = require("tests.client_fixtures")

local STARTING_MONEY = 500000 -- 50g carried before login

local function character(world)
    return world.environment.AsgardsGuildTitheDB.characters["jaina-camelot"]
end

local function newWorld(profile, options)
    options = options or {}
    options.money = options.money or STARTING_MONEY
    local world = fixtures.newEnvironment(profile, options)
    local addon = fixtures.login(world)
    return world, addon
end

local function registerProfileTests(profile)
    test.test(profile .. " income observation uses carried money at login as a baseline", function()
        local world, addon = newWorld(profile)

        test.assertTrue(addon.lifecycle.incomeReady)
        test.assertEqual(0, character(world).outstandingCopper)
        test.assertEqual(0, character(world).fractionalRemainder)
        test.assertEqual(0, #world.messages)
    end)

    test.test(profile .. " positive money change accrues miscellaneous income and reports it", function()
        local world = newWorld(profile)

        fixtures.setMoney(world, STARTING_MONEY + 1234)

        -- 10% of 1234 copper = 123 whole copper with 40 hundredths carried.
        test.assertEqual(123, character(world).outstandingCopper)
        test.assertEqual(40, character(world).fractionalRemainder)
        test.assertEqual(1, #world.messages)
        test.assertEqual(
            "Asgard's Guild Tithe: reserved 0g 01s 23c from miscellaneous/system income. Total owed: 0g 01s 23c.",
            world.messages[1]
        )
    end)

    test.test(profile .. " spending and unchanged money never change the tithe", function()
        local world = newWorld(profile)
        fixtures.setMoney(world, STARTING_MONEY + 1000)
        local before = fixtures.snapshot(character(world))

        fixtures.setMoney(world, STARTING_MONEY - 5000)
        fixtures.setMoney(world, STARTING_MONEY - 5000)

        fixtures.assertSameData(before, character(world))
        test.assertEqual(1, #world.messages)

        -- The spent amount is not "earned back": only the new gain counts.
        fixtures.setMoney(world, STARTING_MONEY - 4000)
        test.assertEqual(200, character(world).outstandingCopper)
    end)

    test.test(profile .. " guildless gains are ignored and tracking resumes after joining a guild", function()
        local world = newWorld(profile)
        fixtures.setMoney(world, STARTING_MONEY + 1000)
        local before = fixtures.snapshot(character(world))

        world.inGuild = false
        fixtures.setMoney(world, STARTING_MONEY + 51000)

        fixtures.assertSameData(before, character(world))
        test.assertEqual(1, #world.messages)

        world.inGuild = true
        fixtures.setMoney(world, STARTING_MONEY + 52000)
        test.assertEqual(200, character(world).outstandingCopper)
    end)

    test.test(profile .. " disabled miscellaneous income leaves balance and remainder unchanged", function()
        local world = newWorld(profile)
        world.settings.bindings.AsgardsGuildTithe_Source_Miscellaneous.setValue(false)
        local before = fixtures.snapshot(character(world))

        fixtures.setMoney(world, STARTING_MONEY + 1234)

        fixtures.assertSameData(before, character(world))
        test.assertEqual(0, #world.messages)
    end)

    test.test(profile .. " chat feedback off accrues silently", function()
        local world = newWorld(profile)
        world.settings.bindings.AsgardsGuildTithe_ChatFeedback.setValue(false)

        fixtures.setMoney(world, STARTING_MONEY + 1234)

        test.assertEqual(123, character(world).outstandingCopper)
        test.assertEqual(0, #world.messages)
    end)

    test.test(profile .. " a sub-copper tithe updates the remainder without a zero message", function()
        local world = newWorld(profile)

        fixtures.setMoney(world, STARTING_MONEY + 5)

        test.assertEqual(0, character(world).outstandingCopper)
        test.assertEqual(50, character(world).fractionalRemainder)
        test.assertEqual(0, #world.messages)
    end)

    test.test(profile .. " a reload records a fresh baseline instead of re-counting money", function()
        local world = newWorld(profile)
        fixtures.setMoney(world, STARTING_MONEY + 1000)

        local reloaded = fixtures.newEnvironment(profile, {
            database = world.environment.AsgardsGuildTitheDB,
            money = STARTING_MONEY + 1000,
        })
        fixtures.login(reloaded)

        test.assertEqual(100, character(reloaded).outstandingCopper)
        test.assertEqual(0, #reloaded.messages)
    end)

    test.test(profile .. " missing money API warns once and leaves the tithe untouched", function()
        local world = fixtures.newEnvironment(profile, { money = false })
        local addon = fixtures.login(world)
        fixtures.fire(world, "PLAYER_ENTERING_WORLD")
        fixtures.fire(world, "PLAYER_MONEY")

        test.assertFalse(addon.lifecycle.incomeReady)
        test.assertTrue(addon.lifecycle.stateReady)
        test.assertEqual(1, #world.messages)
        test.assertContains(world.messages[1], "income tracking is unavailable")
        test.assertContains(world.messages[1], "balance is unchanged")
        test.assertEqual(0, character(world).outstandingCopper)
    end)

    test.test(profile .. " settings balance no longer says income tracking is inactive", function()
        local world = newWorld(profile)
        fixtures.setMoney(world, STARTING_MONEY + 1234)

        world.environment.SlashCmdList.AGT("")

        test.assertEqual("Tithe - Current balance: 0g 01s 23c", fixtures.balanceText(world))
    end)
end

local profileIndex
for profileIndex = 1, #fixtures.PROFILES do
    registerProfileTests(fixtures.PROFILES[profileIndex])
end

test.test("every positive money change yields one terminal result with a stable id", function()
    local world, addon = newWorld("Forever")

    world.money = STARTING_MONEY + 100
    addon.incomeObserver:OnMoneyChanged()
    local first = addon.incomeObserver:FinalizePending()
    world.money = STARTING_MONEY + 100
    local unchanged = addon.incomeObserver:OnMoneyChanged()
    world.inGuild = false
    world.money = STARTING_MONEY + 300
    addon.incomeObserver:OnMoneyChanged()
    local guildless = addon.incomeObserver:FinalizePending()

    test.assertEqual(1, first.id)
    test.assertEqual("accrued", first.status)
    test.assertEqual("miscellaneous", first.source)
    test.assertEqual(100, first.copper)
    test.assertEqual(nil, unchanged)
    test.assertEqual(2, guildless.id)
    test.assertEqual("guildless", guildless.status)
    test.assertEqual(200, guildless.copper)
end)

local function newCoordinator(overrides)
    local addon = test.newAddon(
        "Core/MoneyFormatter.lua",
        "Core/IncomeFeedback.lua",
        "Core/IncomeCoordinator.lua"
    )
    local messages = {}
    local calls = 0
    local snapshot = {
        chatFeedback = true,
        outstandingCopper = 0,
        sources = { miscellaneous = true },
    }
    local client = {
        IsInGuild = function()
            return overrides.inGuild
        end,
    }
    local state = {
        GetCurrentCharacter = function()
            return overrides.character ~= nil and overrides.character or snapshot
        end,
    }
    local titheService = {
        AccrueEligibleCopper = function()
            calls = calls + 1
            return overrides.accrual, overrides.accrualError
        end,
    }
    local feedback = addon.IncomeFeedback.Create(function(message)
        table.insert(messages, message)
    end)
    local coordinator = addon.IncomeCoordinator.Create(client, state, titheService, feedback)
    return coordinator, messages, function()
        return calls
    end
end

local OBSERVATION = { copper = 1000, id = 7, reason = "test", source = "miscellaneous" }

test.test("coordinator reports nothing when persisting the tithe fails", function()
    local coordinator, messages, calls = newCoordinator({
        accrualError = "updated financial state was rejected",
        inGuild = true,
    })

    local result = coordinator:Finalize(OBSERVATION)

    test.assertEqual("unresolved", result.status)
    test.assertEqual("updated financial state was rejected", result.reason)
    test.assertEqual(1, calls())
    test.assertEqual(0, #messages)
end)

test.test("coordinator does not accrue when guild membership is unknown", function()
    local coordinator, messages, calls = newCoordinator({ inGuild = nil })

    local result = coordinator:Finalize(OBSERVATION)

    test.assertEqual("unresolved", result.status)
    test.assertEqual(0, calls())
    test.assertEqual(0, #messages)
end)

test.test("coordinator reads settings at finalization, not when the gain began", function()
    local current = {
        chatFeedback = true,
        outstandingCopper = 0,
        sources = { miscellaneous = true },
    }
    local coordinator, _, calls = newCoordinator({
        accrual = { accruedCopper = 100, outstandingCopper = 100 },
        character = current,
        inGuild = true,
    })

    current.sources.miscellaneous = false
    local result = coordinator:Finalize(OBSERVATION)

    test.assertEqual("disabled", result.status)
    test.assertEqual(0, calls())
end)
