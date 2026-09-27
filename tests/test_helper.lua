local Harness = {
    failures = 0,
    tests = {},
}

local function render(value)
    if type(value) == "string" then
        return string.format("%q", value)
    end
    return tostring(value)
end

function Harness.test(name, callback)
    table.insert(Harness.tests, { name = name, callback = callback })
end

function Harness.assertEqual(expected, actual, message)
    if expected ~= actual then
        error((message or "values differ") .. ": expected " .. render(expected) .. ", got " .. render(actual), 2)
    end
end

function Harness.assertTrue(value, message)
    if value ~= true then
        error((message or "expected true") .. ", got " .. render(value), 2)
    end
end

function Harness.assertFalse(value, message)
    if value ~= false then
        error((message or "expected false") .. ", got " .. render(value), 2)
    end
end

function Harness.assertContains(haystack, needle, message)
    if type(haystack) ~= "string" or string.find(haystack, needle, 1, true) == nil then
        error((message or "text not found") .. ": expected " .. render(haystack) .. " to contain " .. render(needle), 2)
    end
end

function Harness.loadAddonFile(path, addon)
    local chunk, loadError = loadfile(path)
    if chunk == nil then
        error(loadError, 2)
    end
    chunk("GuildTithe", addon)
end

function Harness.newAddon(...)
    local addon = {}
    local index

    for index = 1, select("#", ...) do
        Harness.loadAddonFile(select(index, ...), addon)
    end

    return addon
end

function Harness.run()
    local index

    for index = 1, #Harness.tests do
        local testCase = Harness.tests[index]
        local ok, failure = pcall(testCase.callback)
        if ok then
            io.write("PASS ", testCase.name, "\n")
        else
            Harness.failures = Harness.failures + 1
            io.write("FAIL ", testCase.name, "\n  ", failure, "\n")
        end
    end

    io.write(string.format("\n%d tests, %d failures\n", #Harness.tests, Harness.failures))
    return Harness.failures == 0
end

return Harness
