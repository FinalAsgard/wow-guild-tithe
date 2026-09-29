local test = require("tests.test_helper")

-- Builds a feedback presenter with a controllable scheduler.
local function newFeedback(withScheduler)
    local addon = test.newAddon("Core/MoneyFormatter.lua", "Core/IncomeFeedback.lua")
    local messages = {}
    local timers = {}
    local after
    if withScheduler ~= false then
        after = function(_, callback)
            table.insert(timers, callback)
            return true
        end
    end
    local feedback = addon.IncomeFeedback.Create(function(message)
        table.insert(messages, message)
    end, addon.MoneyFormatter, after)
    local function runTimers()
        local pending = timers
        timers = {}
        local index
        for index = 1, #pending do
            pending[index]()
        end
    end
    return feedback, messages, runTimers, addon.IncomeFeedback
end

test.test("feedback groups same-source accruals into one message with the latest total", function()
    local feedback, messages, runTimers = newFeedback()

    feedback:Accrued("loot", 100, 100)
    feedback:Accrued("loot", 250, 350)
    feedback:Accrued("loot", 50, 400)
    test.assertEqual(0, #messages)

    runTimers()

    test.assertEqual(1, #messages)
    test.assertEqual(
        "Asgard's Guild Tithe: reserved 0g 04s 00c from loot income. Total owed: 0g 04s 00c.",
        messages[1]
    )
end)

test.test("feedback never merges different sources under one label", function()
    local feedback, messages, runTimers = newFeedback()

    feedback:Accrued("loot", 100, 100)
    feedback:Accrued("vendorSales", 200, 300)
    feedback:Accrued("loot", 50, 350)
    runTimers()

    test.assertEqual(3, #messages)
    test.assertContains(messages[1], "reserved 0g 01s 00c from loot income. Total owed: 0g 01s 00c.")
    test.assertContains(messages[2], "reserved 0g 02s 00c from vendor sale income. Total owed: 0g 03s 00c.")
    test.assertContains(messages[3], "reserved 0g 00s 50c from loot income. Total owed: 0g 03s 50c.")
end)

test.test("a fractional-only accrual is silent until the group reserves whole copper", function()
    local feedback, messages, runTimers = newFeedback()

    feedback:Accrued("loot", 0, 7)
    runTimers()
    test.assertEqual(0, #messages)

    feedback:Accrued("loot", 3, 10)
    feedback:Accrued("loot", 0, 10)
    runTimers()

    test.assertEqual(1, #messages)
    test.assertContains(messages[1], "reserved 0g 00s 03c from loot income. Total owed: 0g 00s 10c.")
end)

test.test("a long burst reports once the group reaches its size limit", function()
    local feedback, messages, _, module = newFeedback()

    local index
    for index = 1, module.MAX_GROUP_SIZE do
        feedback:Accrued("vendorSales", 10, index * 10)
    end

    test.assertEqual(1, #messages)
    test.assertContains(messages[1], "reserved 0g 02s 00c from vendor sale income")
end)

test.test("without a scheduler every accrual reports immediately", function()
    local feedback, messages = newFeedback(false)

    feedback:Accrued("quests", 100, 100)
    feedback:Accrued("quests", 100, 200)

    test.assertEqual(2, #messages)
end)

test.test("feedback rejects invalid amounts without printing", function()
    local feedback, messages, runTimers = newFeedback()

    test.assertFalse(feedback:Accrued("loot", -5, 10))
    test.assertFalse(feedback:Accrued("loot", "lots", 10))
    runTimers()

    test.assertEqual(0, #messages)
end)
