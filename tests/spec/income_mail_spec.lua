local test = require("tests.test_helper")
local fixtures = require("tests.client_fixtures")

local STARTING_MONEY = 500000

local function character(world)
    return world.environment.AsgardsGuildTitheDB.characters["jaina-camelot"]
end

-- Auction and mailbox income are off by default; `sources` turns them on.
local function newWorld(profile, mails, sources)
    local world = fixtures.newEnvironment(profile, { money = STARTING_MONEY })
    fixtures.installMailbox(world, mails)
    fixtures.login(world)
    local bindings = world.settings.bindings
    bindings.AsgardsGuildTithe_Source_Auctions.setValue(sources.auctions == true)
    bindings.AsgardsGuildTithe_Source_Mailbox.setValue(sources.mailbox == true)
    return world
end

local function lastMessage(world)
    return world.messages[#world.messages]
end

local function registerProfileTests(profile)
    test.test(profile .. " auction sale proceeds from mail classify as auction income", function()
        local world = newWorld(profile, { { money = 20000, invoiceType = "seller" } }, {
            auctions = true,
            mailbox = true,
        })

        fixtures.collectMail(world, 1)

        test.assertContains(lastMessage(world), "from auction income")
        test.assertEqual(2000, character(world).outstandingCopper)
    end)

    test.test(profile .. " ordinary mail money classifies as mailbox income", function()
        local world = newWorld(profile, { { money = 10000 } }, { auctions = true, mailbox = true })

        fixtures.collectMail(world, 1, "AutoLootMailItem")

        test.assertContains(lastMessage(world), "from mailbox income")
        test.assertEqual(1000, character(world).outstandingCopper)
    end)

    test.test(profile .. " auction proceeds are ignored when only mailbox income is on", function()
        local world = newWorld(profile, {
            { money = 20000, invoiceType = "seller" },
            { money = 10000 },
        }, { mailbox = true })

        fixtures.collectMail(world, 1)
        test.assertEqual(0, character(world).outstandingCopper)
        test.assertEqual(0, #world.messages)

        fixtures.collectMail(world, 2)
        test.assertContains(lastMessage(world), "from mailbox income")
        test.assertEqual(1000, character(world).outstandingCopper)
    end)

    test.test(profile .. " ordinary mail is ignored when only auction income is on", function()
        local world = newWorld(profile, {
            { money = 10000 },
            { money = 20000, invoiceType = "seller" },
        }, { auctions = true })

        fixtures.collectMail(world, 1)
        test.assertEqual(0, character(world).outstandingCopper)
        test.assertEqual(0, #world.messages)

        fixtures.collectMail(world, 2)
        test.assertContains(lastMessage(world), "from auction income")
        test.assertEqual(2000, character(world).outstandingCopper)
    end)

    test.test(profile .. " money in returned mail is excluded, never miscellaneous", function()
        local world = newWorld(profile, { { money = 15000, returned = true } }, {
            auctions = true,
            mailbox = true,
        })
        local before = fixtures.snapshot(character(world))

        fixtures.collectMail(world, 1)

        fixtures.assertSameData(before, character(world))
        test.assertEqual(0, #world.messages)
    end)

    test.test(profile .. " opening the mailbox alone accrues nothing", function()
        local world = newWorld(profile, { { money = 10000 } }, { mailbox = true })
        local before = fixtures.snapshot(character(world))

        fixtures.fire(world, "MAIL_SHOW")
        fixtures.fire(world, "MAIL_INBOX_UPDATE")
        fixtures.fire(world, "MAIL_CLOSED")
        fixtures.advance(world, 5)

        fixtures.assertSameData(before, character(world))
    end)

    test.test(profile .. " several mails collected together each count once by source", function()
        local world = newWorld(profile, {
            { money = 10000 },
            { money = 10000, invoiceType = "seller" },
            { money = 3000 },
        }, { auctions = true, mailbox = true })

        fixtures.fire(world, "MAIL_SHOW")
        fixtures.fire(world, "MAIL_INBOX_UPDATE")
        world.environment.TakeInboxMoney(1)
        world.environment.TakeInboxMoney(2)
        world.environment.TakeInboxMoney(3)
        fixtures.advance(world, 0.1)
        fixtures.setMoney(world, STARTING_MONEY + 10000, false)
        fixtures.setMoney(world, STARTING_MONEY + 20000, false)
        fixtures.setMoney(world, STARTING_MONEY + 23000)

        -- Three results; the two ordinary mails share one grouped message.
        test.assertEqual(2, #world.messages)
        test.assertContains(world.messages[1], "reserved 0g 10s 00c from auction income")
        test.assertContains(world.messages[2], "reserved 0g 13s 00c from mailbox income")
        test.assertEqual(2300, character(world).outstandingCopper)
    end)

    test.test(profile .. " mail money that arrives seconds after collection is still mail income", function()
        local world = newWorld(profile, { { money = 10000 } }, { mailbox = true })

        fixtures.fire(world, "MAIL_SHOW")
        fixtures.fire(world, "MAIL_INBOX_UPDATE")
        world.environment.TakeInboxMoney(1)
        fixtures.advance(world, 3)
        fixtures.setMoney(world, STARTING_MONEY + 10000)

        test.assertContains(lastMessage(world), "from mailbox income")
    end)

    test.test(profile .. " a gain that does not match the collected mail is not mail income", function()
        local world = newWorld(profile, { { money = 10000 } }, { mailbox = true })

        fixtures.collectMail(world, 1, "TakeInboxMoney", 999)

        test.assertContains(lastMessage(world), "from miscellaneous/system income")
    end)
end

local profileIndex
for profileIndex = 1, #fixtures.PROFILES do
    registerProfileTests(fixtures.PROFILES[profileIndex])
end

test.test("mail money is miscellaneous when the client cannot hook mail collection", function()
    local world = fixtures.newEnvironment("Retail", { money = STARTING_MONEY })
    fixtures.installMailbox(world, { { money = 10000 } })
    world.environment.hooksecurefunc = nil
    fixtures.login(world)

    fixtures.collectMail(world, 1)

    test.assertContains(lastMessage(world), "from miscellaneous/system income")
end)

test.test("correlator: an exclusion reports its reason and a used amount note is consumed", function()
    local addon = test.newAddon("Core/IncomeCorrelator.lua")
    local correlator = addon.IncomeCorrelator.Create()
    correlator:Record("returnedMail", "note", 10, 500)
    correlator:Record("mailbox", "note", 10, 700)

    local source, reason, excluded = correlator:Classify(10.1, 10.3, 500)
    test.assertEqual("returnedMail", source)
    test.assertTrue(excluded)
    test.assertContains(reason, "returned to sender")

    test.assertEqual("mailbox", (correlator:Classify(10.2, 10.4, 700)))
    test.assertEqual("miscellaneous", (correlator:Classify(10.3, 10.5, 700)))
end)

test.test("coordinator excludes a known transfer without touching accounting", function()
    local addon = test.newAddon("Core/IncomeCoordinator.lua")
    local calls = 0
    local coordinator = addon.IncomeCoordinator.Create({}, {}, {
        AccrueEligibleCopper = function()
            calls = calls + 1
        end,
    })

    local result = coordinator:Finalize({
        copper = 500,
        excluded = true,
        id = 3,
        reason = "mail returned to sender",
        source = "returnedMail",
    })

    test.assertEqual("excluded", result.status)
    test.assertEqual(0, calls)
end)
