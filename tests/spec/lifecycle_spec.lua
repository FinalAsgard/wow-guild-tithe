local test = require("tests.test_helper")

local function loadRuntimeModules()
    return test.newAddon(
        "Adapters/WoW.lua",
        "Core/CommandRouter.lua",
        "Core/Lifecycle.lua"
    )
end

local function newFrame()
    local frame = {}

    function frame:RegisterEvent(eventName)
        self.registeredEvent = eventName
    end

    function frame:SetScript(scriptName, handler)
        self.scriptName = scriptName
        self.handler = handler
    end

    return frame
end

test.test("lifecycle waits for this add-on and registers slash handling", function()
    local addon = loadRuntimeModules()
    local frame = newFrame()
    local messages = {}
    local environment = {
        CreateFrame = function(frameType)
            test.assertEqual("Frame", frameType)
            return frame
        end,
        SlashCmdList = {},
    }
    local client = addon.Compatibility.Create(environment)
    local router = addon.CommandRouter.Create(function(message)
        table.insert(messages, message)
    end)
    router:Register("help", "show available commands", function()
        router:PrintHelp()
    end)
    local lifecycle = addon.Lifecycle.Create(client, router, "GuildTithe")

    test.assertTrue(lifecycle:Start())
    test.assertEqual("ADDON_LOADED", frame.registeredEvent)
    test.assertEqual("OnEvent", frame.scriptName)
    test.assertEqual(nil, environment.SLASH_GUILDTITHE1)

    frame.handler(frame, "ADDON_LOADED", "SomeOtherAddon")
    test.assertFalse(lifecycle.initialized)

    frame.handler(frame, "ADDON_LOADED", "GuildTithe")
    test.assertTrue(lifecycle.initialized)
    test.assertTrue(lifecycle.slashRegistered)
    test.assertEqual("/gt", environment.SLASH_GUILDTITHE1)
    test.assertEqual("function", type(environment.SlashCmdList.GUILDTITHE))

    environment.SlashCmdList.GUILDTITHE("")
    test.assertEqual("Guild Tithe: /gt help - show available commands", messages[1])
end)

test.test("lifecycle initializes once when duplicate load events arrive", function()
    local addon = loadRuntimeModules()
    local registrations = 0
    local client = {
        RegisterSlashCommand = function()
            registrations = registrations + 1
            return true
        end,
    }
    local lifecycle = addon.Lifecycle.Create(client, {}, "GuildTithe")

    lifecycle:OnEvent("ADDON_LOADED", "GuildTithe")
    lifecycle:OnEvent("ADDON_LOADED", "GuildTithe")

    test.assertEqual(1, registrations)
end)

test.test("missing frame capability falls back to immediate slash registration", function()
    local addon = loadRuntimeModules()
    local environment = { SlashCmdList = {} }
    local client = addon.Compatibility.Create(environment)
    local router = addon.CommandRouter.Create()
    local lifecycle = addon.Lifecycle.Create(client, router, "GuildTithe")

    test.assertFalse(lifecycle:Start())
    test.assertTrue(lifecycle.initialized)
    test.assertTrue(lifecycle.slashRegistered)
    test.assertEqual("/gt", environment.SLASH_GUILDTITHE1)
end)

test.test("all missing client capabilities are handled without an error", function()
    local addon = loadRuntimeModules()
    local client = addon.Compatibility.Create({})
    local router = addon.CommandRouter.Create()
    local lifecycle = addon.Lifecycle.Create(client, router, "GuildTithe")

    local ok, started = pcall(function()
        return lifecycle:Start()
    end)

    test.assertTrue(ok)
    test.assertFalse(started)
    test.assertTrue(lifecycle.initialized)
    test.assertFalse(lifecycle.slashRegistered)
end)

test.test("client adapter contains errors raised by optional APIs", function()
    local addon = loadRuntimeModules()
    local environment = {
        CreateFrame = function()
            error("client frame API failed")
        end,
        SlashCmdList = {},
    }
    local client = addon.Compatibility.Create(environment)
    local router = addon.CommandRouter.Create()
    local lifecycle = addon.Lifecycle.Create(client, router, "GuildTithe")

    local ok = pcall(function()
        lifecycle:Start()
    end)

    test.assertTrue(ok)
    test.assertTrue(lifecycle.slashRegistered)
end)
