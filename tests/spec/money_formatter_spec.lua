local test = require("tests.test_helper")

local function loadFormatter()
    return test.newAddon("Core/MoneyFormatter.lua").MoneyFormatter
end

test.test("money formatter renders gold silver and copper boundaries consistently", function()
    local formatter = loadFormatter()
    local cases = {
        { 0, "0g 00s 00c" },
        { 1, "0g 00s 01c" },
        { 99, "0g 00s 99c" },
        { 100, "0g 01s 00c" },
        { 9999, "0g 99s 99c" },
        { 10000, "1g 00s 00c" },
        { 123456, "12g 34s 56c" },
        { formatter.MAX_SAFE_INTEGER, "900719925474g 09s 91c" },
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

    test.assertEqual("12g 34s 56c", formatter.Format(state.outstandingCopper))
    test.assertEqual(before, state.outstandingCopper)
    test.assertEqual(78, state.fractionalRemainder)
end)
