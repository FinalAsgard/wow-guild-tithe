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
        "|cffd4af37[Guild Tithe]|r +4|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t tithe from loot · owed 4|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t",
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
    test.assertContains(messages[1], "+1|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t tithe from loot · owed 1|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t")
    test.assertContains(messages[2], "+2|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t tithe from vendor sales · owed 3|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t")
    test.assertContains(messages[3], "+50|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t tithe from loot · owed 3|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t 50|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t")
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
    test.assertContains(messages[1], "+3|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t tithe from loot · owed 10|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t")
end)

test.test("a long burst reports once the group reaches its size limit", function()
    local feedback, messages, _, module = newFeedback()

    local index
    for index = 1, module.MAX_GROUP_SIZE do
        feedback:Accrued("vendorSales", 10, index * 10)
    end

    test.assertEqual(1, #messages)
    test.assertContains(messages[1], "+2|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t tithe from vendor sales")
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
