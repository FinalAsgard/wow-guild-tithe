local test = require("tests.test_helper")
local fixtures = require("tests.client_fixtures")

local CARRIED = 100000 -- 10g

local function character(world)
    return world.environment.AsgardsGuildTitheDB.characters["jaina-camelot"]
end

-- Logs in with `owed` copper outstanding (and 40 hundredths carried over).
local function newWorld(profile, owed, options)
    options = options or {}
    local world = fixtures.newEnvironment(profile, {
        inGuild = options.inGuild,
        money = options.money or CARRIED,
    })
    local addon = fixtures.login(world)
    character(world).outstandingCopper = owed
    character(world).fractionalRemainder = 40
    return world, addon
end

local function panel(addon)
    return addon.tithePayment.panel
end

local function openBank(world)
    fixtures.fire(world, "GUILDBANKFRAME_OPENED")
end

local function lastMessage(world)
    return world.messages[#world.messages]
end

local function registerProfileTests(profile)
    test.test(profile .. " the guild bank offers the full tithe with recipient and remainder", function()
        local world, addon = newWorld(profile, 5000)

        openBank(world)

        test.assertTrue(panel(addon):IsShown())
        test.assertEqual(
            "Pay to Knights of Camelot\nTithe: 0g 50s 00c\nStill owed after: 0g 00s 00c",
            panel(addon).body.text
        )
        test.assertTrue(panel(addon).button.shown)
    end)

    test.test(profile .. " a confirmed deposit clears the debt and keeps the remainder", function()
        local world, addon = newWorld(profile, 5000)
        openBank(world)

        fixtures.click(panel(addon).button)
        test.assertEqual(1, #world.deposits)
        test.assertEqual(5000, world.deposits[1])
        test.assertEqual(5000, character(world).outstandingCopper)

        fixtures.setMoney(world, CARRIED - 5000)

        test.assertEqual(0, character(world).outstandingCopper)
        test.assertEqual(40, character(world).fractionalRemainder)
        test.assertEqual(
            "Asgard's Guild Tithe: deposited 0g 50s 00c to Knights of Camelot. Still owed: 0g 00s 00c.",
            lastMessage(world)
        )
        test.assertFalse(panel(addon):IsShown())
    end)

    test.test(profile .. " carrying less than owed offers and records a partial payment", function()
        local world, addon = newWorld(profile, 5000, { money = 3000 })
        openBank(world)

        test.assertContains(panel(addon).body.text, "Tithe: 0g 30s 00c")
        test.assertContains(panel(addon).body.text, "Still owed after: 0g 20s 00c")
        fixtures.click(panel(addon).button)
        fixtures.setMoney(world, 0)

        test.assertEqual(3000, world.deposits[1])
        test.assertEqual(2000, character(world).outstandingCopper)
        test.assertContains(lastMessage(world), "Still owed: 0g 20s 00c.")
    end)

    test.test(profile .. " nothing is offered with no debt, no money, or no guild", function()
        local cases = {
            { owed = 0 },
            { owed = 5000, money = 0 },
            { owed = 5000, inGuild = false },
        }
        local index
        for index = 1, #cases do
            local case = cases[index]
            local world, addon = newWorld(profile, case.owed, {
                inGuild = case.inGuild,
                money = case.money,
            })
            openBank(world)
            test.assertFalse(panel(addon):IsShown(), "case " .. index)
            test.assertEqual(0, #world.deposits)
        end
    end)

    test.test(profile .. " the guild bank opened through the interaction manager is recognized", function()
        local world, addon = newWorld(profile, 5000)

        fixtures.fire(world, "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 8)
        test.assertFalse(panel(addon):IsShown())

        fixtures.fire(world, "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 10)
        test.assertTrue(panel(addon):IsShown())
        fixtures.fire(world, "PLAYER_INTERACTION_MANAGER_FRAME_HIDE", 10)
        test.assertFalse(panel(addon):IsShown())
    end)

    test.test(profile .. " only an exact money drop confirms the deposit", function()
        local world, addon = newWorld(profile, 5000)
        openBank(world)
        fixtures.click(panel(addon).button)

        fixtures.setMoney(world, CARRIED - 200)
        test.assertEqual(5000, character(world).outstandingCopper)

        fixtures.setMoney(world, CARRIED - 5200)
        test.assertEqual(0, character(world).outstandingCopper)
    end)

    test.test(profile .. " an unconfirmed deposit times out and leaves the debt", function()
        local world, addon = newWorld(profile, 5000)
        openBank(world)
        fixtures.click(panel(addon).button)

        fixtures.advance(world, 11)

        test.assertEqual(5000, character(world).outstandingCopper)
        test.assertContains(lastMessage(world), "not confirmed")
        test.assertContains(lastMessage(world), "unchanged")
        test.assertTrue(panel(addon).button.shown)
    end)

    test.test(profile .. " a failed deposit call leaves the debt and offers a retry", function()
        local world, addon = newWorld(profile, 5000)
        world.depositError = "not allowed"
        openBank(world)

        fixtures.click(panel(addon).button)

        test.assertEqual(5000, character(world).outstandingCopper)
        test.assertContains(lastMessage(world), "deposit failed")
        test.assertTrue(panel(addon):IsShown())
        test.assertTrue(panel(addon).button.shown)
    end)

    test.test(profile .. " closing the guild bank discards the offer", function()
        local world, addon = newWorld(profile, 5000)
        openBank(world)
        local button = panel(addon).button

        fixtures.fire(world, "GUILDBANKFRAME_CLOSED")
        fixtures.click(button)

        test.assertFalse(panel(addon):IsShown())
        test.assertEqual(0, #world.deposits)
        test.assertEqual(5000, character(world).outstandingCopper)
    end)

    test.test(profile .. " clicking twice pays once", function()
        local world, addon = newWorld(profile, 5000)
        openBank(world)
        local onClick = panel(addon).button.scripts.OnClick

        onClick()
        onClick()

        test.assertEqual(1, #world.deposits)
    end)

    test.test(profile .. " payment messages print even with tithe updates off", function()
        local world, addon = newWorld(profile, 5000)
        world.settings.bindings.AsgardsGuildTithe_ChatFeedback.setValue(false)
        openBank(world)

        fixtures.click(panel(addon).button)
        fixtures.setMoney(world, CARRIED - 5000)

        test.assertContains(lastMessage(world), "deposited 0g 50s 00c")
    end)

    test.test(profile .. " a deposit is never counted as income", function()
        local world, addon = newWorld(profile, 5000)
        openBank(world)
        fixtures.click(panel(addon).button)
        fixtures.setMoney(world, CARRIED - 5000)

        test.assertEqual(1, #world.messages)
        test.assertContains(world.messages[1], "deposited")
    end)
end

local profileIndex
for profileIndex = 1, #fixtures.PROFILES do
    registerProfileTests(fixtures.PROFILES[profileIndex])
end

test.test("the proposed payment is the smaller of debt and carried money, never negative", function()
    local addon = test.newAddon("Core/MoneyFormatter.lua", "Core/TithePayment.lua")
    local propose = addon.TithePayment.Propose

    test.assertEqual(5000, propose(5000, 100000))
    test.assertEqual(3000, propose(5000, 3000))
    test.assertEqual(5000, propose(5000, 5000))
    test.assertEqual(0, propose(0, 100000))
    test.assertEqual(0, propose(5000, 0))
    test.assertEqual(0, propose(-5, 100))
    test.assertEqual(0, propose(nil, 100))
end)
