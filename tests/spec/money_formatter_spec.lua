local test = require("tests.test_helper")

local function loadFormatter()
    return test.newAddon("Core/MoneyFormatter.lua").MoneyFormatter
end

test.test("money shows coin icons and leaves out empty units", function()
    local formatter = loadFormatter()
    local G, S, C = formatter.GOLD_ICON, formatter.SILVER_ICON, formatter.COPPER_ICON
    test.assertEqual("|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t", G)
    local cases = {
        { 0, "0" .. C },
        { 1, "1" .. C },
        { 99, "99" .. C },
        { 100, "1" .. S },
        { 9999, "99" .. S .. " 99" .. C },
        { 10000, "1" .. G },
        { 10005, "1" .. G .. " 5" .. C },
        { 123456, "12" .. G .. " 34" .. S .. " 56" .. C },
        { formatter.MAX_SAFE_INTEGER, "900719925474" .. G .. " 9" .. S .. " 91" .. C },
    }
    local index

    for index = 1, #cases do
        local case = cases[index]
        test.assertEqual(case[2], formatter.Format(case[1]))
    end
end)

test.test("money formatter rejects values outside the exact copper domain", function()
    local formatter = loadFormatter()
    local invalid = { -1, 1.5, "100", formatter.MAX_SAFE_INTEGER + 1 }
    local index

    for index = 1, #invalid do
        local formatted, formatError = formatter.Format(invalid[index])
        test.assertEqual(nil, formatted)
        test.assertEqual("string", type(formatError))
    end
end)

test.test("money formatting does not mutate its input or stored state", function()
    local formatter = loadFormatter()
    local state = { outstandingCopper = 123456, fractionalRemainder = 78 }
    local before = state.outstandingCopper

    test.assertEqual("12" .. formatter.GOLD_ICON .. " 34" .. formatter.SILVER_ICON ..
        " 56" .. formatter.COPPER_ICON, formatter.Format(state.outstandingCopper))
    test.assertEqual(before, state.outstandingCopper)
    test.assertEqual(78, state.fractionalRemainder)
end)
