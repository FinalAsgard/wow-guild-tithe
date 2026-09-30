local test = require("tests.test_helper")
local replay = require("tests.trace_replay")

local function character(world)
    return world.environment.AsgardsGuildTitheDB.characters["jaina-camelot"]
end

test.test("captured Forever vendor sale replays as one vendor sale", function()
    local trace = replay.load("tests/fixtures/traces/forever/vendor-sale.lua")

    local world = replay.run(trace)

    -- 28 copper at 10% is 2 whole copper with 80 hundredths carried.
    test.assertEqual(1, #world.messages)
    test.assertEqual(
        "|cffd4af37[Guild Tithe]|r +2|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t tithe from vendor sales · owed 2|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t",
        world.messages[1]
    )
    test.assertEqual(2, character(world).outstandingCopper)
    test.assertEqual(80, character(world).fractionalRemainder)
end)

test.test("captured Retail questing replays as exactly four quest rewards", function()
    local trace = replay.load("tests/fixtures/traces/retail/quest-turn-ins.lua")

    local world = replay.run(trace)

    -- Rewards 255060, 25505, 127530, 127530 copper at 10%. Combat, gossip,
    -- repeated quest events, and guild-bank money updates add nothing.
    test.assertEqual(4, #world.messages)
    test.assertContains(world.messages[1], "+2|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t 55|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t 6|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t tithe from quests")
    test.assertContains(world.messages[2], "+25|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t 50|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t tithe from quests")
    test.assertContains(world.messages[3], "+1|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t 27|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t 53|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t tithe from quests")
    test.assertContains(world.messages[4], "+1|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t 27|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t 53|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t tithe from quests · owed 5|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t 35|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t 62|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t")
    test.assertEqual(53562, character(world).outstandingCopper)
    test.assertEqual(50, character(world).fractionalRemainder)
end)

test.test("captured Retail questing with quest income off accrues nothing", function()
    local trace = replay.load("tests/fixtures/traces/retail/quest-turn-ins.lua")

    local world = replay.run(trace, {
        prepare = function(world)
            world.settings.bindings.AsgardsGuildTithe_Source_Quests.setValue(false)
        end,
    })

    test.assertEqual(0, #world.messages)
    test.assertEqual(0, character(world).outstandingCopper)
end)

test.test("captured quest rewards arrive inside the correlation window", function()
    local addon = test.newAddon("Core/IncomeCorrelator.lua")
    local trace = replay.load("tests/fixtures/traces/retail/quest-turn-ins.lua")

    local largestGap = 0
    local turnedIn
    local index
    for index = 1, #trace.entries do
        local entry = trace.entries[index]
        if entry.name == "QUEST_TURNED_IN" then
            turnedIn = entry
        elseif entry.name == "PLAYER_MONEY" and turnedIn ~= nil then
            largestGap = math.max(largestGap, entry.t - turnedIn.t)
            turnedIn = nil
        end
    end

    -- The slowest captured gap (about 0.31s) must fit the 1s note window.
    test.assertTrue(largestGap > 0.3 and largestGap < 0.32, "largest gap " .. largestGap)
    test.assertTrue(largestGap < addon.IncomeCorrelator.NOTE_WINDOW)
end)
