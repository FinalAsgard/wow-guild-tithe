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
    local lifecycle = addon.Lifecycle.Create(client, router)

    test.assertTrue(lifecycle:Start())
    test.assertEqual("ADDON_LOADED", frame.registeredEvent)
    test.assertEqual("OnEvent", frame.scriptName)
    test.assertEqual(nil, environment.SLASH_ASGARDSGUILDTITHE1)

    frame.handler(frame, "ADDON_LOADED", "SomeOtherAddon")
    test.assertFalse(lifecycle.initialized)

    frame.handler(frame, "ADDON_LOADED", "AsgardsGuildTithe")
    test.assertTrue(lifecycle.initialized)
    test.assertTrue(lifecycle.slashRegistered)
    test.assertEqual("/agt", environment.SLASH_ASGARDSGUILDTITHE1)
    test.assertEqual("function", type(environment.SlashCmdList.ASGARDSGUILDTITHE))

    environment.SlashCmdList.ASGARDSGUILDTITHE("")
    test.assertEqual(
        "Asgard's Guild Tithe: /agt help - show available commands",
        messages[1]
    )
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
    local lifecycle = addon.Lifecycle.Create(client, {})

    lifecycle:OnEvent("ADDON_LOADED", "AsgardsGuildTithe")
    lifecycle:OnEvent("ADDON_LOADED", "AsgardsGuildTithe")

    test.assertEqual(1, registrations)
end)

test.test("missing frame capability falls back to immediate slash registration", function()
    local addon = loadRuntimeModules()
    local environment = { SlashCmdList = {} }
    local client = addon.Compatibility.Create(environment)
    local router = addon.CommandRouter.Create()
    local lifecycle = addon.Lifecycle.Create(client, router)

    test.assertFalse(lifecycle:Start())
    test.assertTrue(lifecycle.initialized)
    test.assertTrue(lifecycle.slashRegistered)
    test.assertEqual("/agt", environment.SLASH_ASGARDSGUILDTITHE1)
end)

test.test("all missing client capabilities are handled without an error", function()
    local addon = loadRuntimeModules()
    local client = addon.Compatibility.Create({})
    local router = addon.CommandRouter.Create()
    local lifecycle = addon.Lifecycle.Create(client, router)

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
    local lifecycle = addon.Lifecycle.Create(client, router)

    local ok = pcall(function()
        lifecycle:Start()
    end)

    test.assertTrue(ok)
    test.assertTrue(lifecycle.slashRegistered)
end)

test.test("lifecycle initializes character state before registering consumers", function()
    local addon = loadRuntimeModules()
    local calls = {}
    local client = {
        RegisterSlashCommand = function()
            table.insert(calls, "slash")
            return true
        end,
    }
    local state = {
        Initialize = function()
            table.insert(calls, "state")
            return true
        end,
    }
    local lifecycle = addon.Lifecycle.Create(client, {}, state)

    test.assertTrue(lifecycle:Initialize())

    test.assertTrue(lifecycle.stateReady)
    test.assertEqual("state", calls[1])
    test.assertEqual("slash", calls[2])
end)

test.test("lifecycle registers settings after state and before slash handling", function()
    local addon = loadRuntimeModules()
    local calls = {}
    local client = {
        RegisterSlashCommand = function()
            table.insert(calls, "slash")
            return true
        end,
    }
    local state = {
        Initialize = function()
            table.insert(calls, "state")
            return true
        end,
    }
    local settingsController = {
        Register = function()
            table.insert(calls, "settings")
            return true
        end,
    }
    local lifecycle = addon.Lifecycle.Create(
        client,
        {},
        state,
        settingsController
    )

    test.assertTrue(lifecycle:Initialize())

    test.assertTrue(lifecycle.stateReady)
    test.assertTrue(lifecycle.settingsReady)
    test.assertEqual("state", calls[1])
    test.assertEqual("settings", calls[2])
    test.assertEqual("slash", calls[3])
end)

test.test("settings registration failure does not stop slash handling", function()
    local addon = loadRuntimeModules()
    local client = {
        RegisterSlashCommand = function()
            return true
        end,
    }
    local state = {
        Initialize = function()
            return true
        end,
    }
    local settingsController = {
        Register = function()
            error("unsupported Settings API")
        end,
    }
    local lifecycle = addon.Lifecycle.Create(
        client,
        {},
        state,
        settingsController
    )

    test.assertTrue(lifecycle:Initialize())
    test.assertFalse(lifecycle.settingsReady)
    test.assertTrue(lifecycle.slashRegistered)
end)

test.test("failed persisted state keeps settings unavailable while slash help remains usable", function()
    local addon = loadRuntimeModules()
    local settingsRegistrations = 0
    local messages = {}
    local client = {
        Print = function(_, message)
            table.insert(messages, message)
            return true
        end,
        RegisterSlashCommand = function()
            return true
        end,
    }
    local state = {
        Initialize = function()
            return false, "current character data is quarantined"
        end,
    }
    local settingsController = {
        Register = function()
            settingsRegistrations = settingsRegistrations + 1
            return true
        end,
    }
    local lifecycle = addon.Lifecycle.Create(
        client,
        {},
        state,
        settingsController
    )

    test.assertTrue(lifecycle:Initialize())

    test.assertFalse(lifecycle.stateReady)
    test.assertFalse(lifecycle.settingsReady)
    test.assertEqual(0, settingsRegistrations)
    test.assertContains(messages[1], "quarantined")
end)

test.test("state initialization exceptions retain their diagnostic message", function()
    local addon = loadRuntimeModules()
    local messages = {}
    local client = {
        Print = function(_, message)
            table.insert(messages, message)
            return true
        end,
        RegisterSlashCommand = function()
            return true
        end,
    }
    local state = {
        Initialize = function()
            error("persistence exploded")
        end,
    }
    local lifecycle = addon.Lifecycle.Create(client, {}, state)

    test.assertTrue(lifecycle:Initialize())

    test.assertFalse(lifecycle.stateReady)
    test.assertContains(messages[1], "persistence exploded")
end)
