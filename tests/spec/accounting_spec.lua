local test = require("tests.test_helper")

local function loadAccountingModules()
    return test.newAddon(
        "Core/Accounting.lua",
        "Core/TitheService.lua"
    )
end

local function assertResult(expectedAccrued, expectedBalance, expectedRemainder, result)
    test.assertEqual(expectedAccrued, result.accruedCopper)
    test.assertEqual(expectedBalance, result.outstandingCopper)
    test.assertEqual(expectedRemainder, result.fractionalRemainder)
end

test.test("accounting calculates exact whole copper at common percentages", function()
    local accounting = loadAccountingModules().Accounting
    local cases = {
        { percentage = 0, accrued = 0, balance = 57, remainder = 23 },
        { percentage = 1, accrued = 1, balance = 58, remainder = 23 },
        { percentage = 10, accrued = 10, balance = 67, remainder = 23 },
        { percentage = 100, accrued = 100, balance = 157, remainder = 23 },
    }
    local index

    for index = 1, #cases do
        local case = cases[index]
        local result = accounting.Calculate(100, case.percentage, 57, 23)
        assertResult(case.accrued, case.balance, case.remainder, result)
    end
end)

test.test("repeated sub-copper gains carry exact hundredths forward", function()
    local accounting = loadAccountingModules().Accounting
    local balance = 0
    local remainder = 0
    local iteration

    for iteration = 1, 9 do
        local result = accounting.Calculate(1, 10, balance, remainder)
        assertResult(0, 0, iteration * 10, result)
        balance = result.outstandingCopper
        remainder = result.fractionalRemainder
    end

    local result = accounting.Calculate(1, 10, balance, remainder)
    assertResult(1, 1, 0, result)
end)

test.test("rate changes affect future income without reinterpreting debt or remainder", function()
    local accounting = loadAccountingModules().Accounting

    local first = accounting.Calculate(3, 10, 250, 0)
    assertResult(0, 250, 30, first)

    local paused = accounting.Calculate(
        900,
        0,
        first.outstandingCopper,
        first.fractionalRemainder
    )
    assertResult(0, 250, 30, paused)

    local changed = accounting.Calculate(
        7,
        100,
        paused.outstandingCopper,
        paused.fractionalRemainder
    )
    assertResult(7, 257, 30, changed)
end)

test.test("maximum safe eligible copper remains exact without intermediate overflow", function()
    local accounting = loadAccountingModules().Accounting
    local maximum = accounting.MAX_SAFE_INTEGER

    local full = accounting.Calculate(maximum, 100, 0, 0)
    assertResult(maximum, maximum, 0, full)

    local onePercent = accounting.Calculate(maximum, 1, 0, 0)
    assertResult(90071992547409, 90071992547409, 91, onePercent)
end)

test.test("accounting rejects invalid inputs and unsafe results", function()
    local accounting = loadAccountingModules().Accounting
    local maximum = accounting.MAX_SAFE_INTEGER
    local invalidCalls = {
        { -1, 10, 0, 0 },
        { 1.5, 10, 0, 0 },
        { "1", 10, 0, 0 },
        { maximum + 1, 10, 0, 0 },
        { 1, -1, 0, 0 },
        { 1, 1.5, 0, 0 },
        { 1, 101, 0, 0 },
        { 1, 10, -1, 0 },
        { 1, 10, 1.5, 0 },
        { 1, 10, maximum + 1, 0 },
        { 1, 10, 0, -1 },
        { 1, 10, 0, 1.5 },
        { 1, 10, 0, 100 },
        { 1, 100, maximum, 0 },
    }
    local index

    for index = 1, #invalidCalls do
        local call = invalidCalls[index]
        local result, calculateError = accounting.Calculate(
            call[1], call[2], call[3], call[4]
        )
        test.assertEqual(nil, result, "invalid case " .. index)
        test.assertEqual("string", type(calculateError), "invalid case " .. index)
    end
end)

test.test("tithe service persists through state only after successful calculation", function()
    local addon = loadAccountingModules()
    local character = {
        percentage = 10,
        outstandingCopper = 12,
        fractionalRemainder = 50,
    }
    local writes = 0
    local state = {
        GetCurrentCharacter = function()
            return {
                percentage = character.percentage,
                outstandingCopper = character.outstandingCopper,
                fractionalRemainder = character.fractionalRemainder,
            }
        end,
        SetFinancialState = function(_, outstandingCopper, fractionalRemainder)
            writes = writes + 1
            character.outstandingCopper = outstandingCopper
            character.fractionalRemainder = fractionalRemainder
            return true
        end,
    }
    local service = addon.TitheService.Create(state, addon.Accounting)

    local result = service:AccrueEligibleCopper(15)
    assertResult(2, 14, 0, result)
    test.assertEqual(1, writes)

    local failed, accrueError = service:AccrueEligibleCopper(-1)
    test.assertEqual(nil, failed)
    test.assertEqual("string", type(accrueError))
    test.assertEqual(1, writes)
    test.assertEqual(14, character.outstandingCopper)
    test.assertEqual(0, character.fractionalRemainder)
end)

test.test("tithe service reports rejected state writes without returning success", function()
    local addon = loadAccountingModules()
    local state = {
        GetCurrentCharacter = function()
            return {
                percentage = 10,
                outstandingCopper = 0,
                fractionalRemainder = 0,
            }
        end,
        SetFinancialState = function()
            return false
        end,
    }
    local service = addon.TitheService.Create(state, addon.Accounting)

    local result, accrueError = service:AccrueEligibleCopper(10)
    test.assertEqual(nil, result)
    test.assertEqual("updated financial state was rejected", accrueError)
end)
