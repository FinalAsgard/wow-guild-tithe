local test = require("tests.test_helper")

test.test("empty slash input prints concise help", function()
    local messages = {}
    local addon = test.newAddon("Core/CommandRouter.lua")
    local router = addon.CommandRouter.Create(function(message)
        table.insert(messages, message)
    end)

    router:Register("help", "show available commands", function()
        router:PrintHelp()
    end)

    test.assertTrue(router:Execute(""))
    test.assertEqual(1, #messages)
    test.assertEqual(
        "Asgard's Guild Tithe: /agt help - show available commands",
        messages[1]
    )
end)

test.test("commands receive arguments and can be extended", function()
    local received
    local addon = test.newAddon("Core/CommandRouter.lua")
    local router = addon.CommandRouter.Create()

    test.assertTrue(router:Register("example", "exercise the router", function(arguments)
        received = arguments
    end))

    test.assertTrue(router:Execute("  ExAmPlE   one two  "))
    test.assertEqual("one two", received)
end)

test.test("unknown commands fail safely with a useful hint", function()
    local message
    local addon = test.newAddon("Core/CommandRouter.lua")
    local router = addon.CommandRouter.Create(function(output)
        message = output
    end)

    test.assertFalse(router:Execute("missing"))
    test.assertContains(message, "unknown command 'missing'")
    test.assertContains(message, "/agt help")
end)

test.test("a registered route can become the empty-input default", function()
    local called = false
    local addon = test.newAddon("Core/CommandRouter.lua")
    local router = addon.CommandRouter.Create()
    router:Register("settings", "open settings", function()
        called = true
    end)

    test.assertFalse(router:SetDefault("missing"))
    test.assertTrue(router:SetDefault("SETTINGS"))
    test.assertTrue(router:Execute(""))
    test.assertTrue(called)
end)
