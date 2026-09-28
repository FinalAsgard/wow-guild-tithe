local test = require("tests.test_helper")

local function loadRuntimeModules()
    return test.newAddon(
        "Adapters/WoW.lua",
        "Core/CommandRouter.lua",
        "Core/Lifecycle.lua"
    )
end

local function newFrame()
    local frame = { registeredEvents = {} }

    function frame:RegisterEvent(eventName)
        self.registeredEvents[eventName] = true
    end

    function frame:SetScript(scriptName, handler)
        self.scriptName = scriptName
        self.handler = handler
    end

    return frame
end

test.test("lifecycle registers slash handling at add-on load and state at player login", function()
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
    test.assertTrue(frame.registeredEvents.ADDON_LOADED)
    test.assertTrue(frame.registeredEvents.PLAYER_LOGIN)
    test.assertTrue(frame.registeredEvents.PLAYER_ENTERING_WORLD)
    test.assertEqual("OnEvent", frame.scriptName)
    test.assertEqual(nil, environment.SLASH_AGT1)

    frame.handler(frame, "ADDON_LOADED", "SomeOtherAddon")
    test.assertFalse(lifecycle.initialized)

    frame.handler(frame, "ADDON_LOADED", "AsgardsGuildTithe")
    test.assertFalse(lifecycle.initialized)
    test.assertTrue(lifecycle.slashRegistered)
    test.assertEqual("/agt", environment.SLASH_AGT1)
    test.assertEqual("/asgardstithe", environment.SLASH_AGT2)
    test.assertEqual("function", type(environment.SlashCmdList.AGT))

    environment.SlashCmdList.AGT("")
    test.assertEqual(
        "Asgard's Guild Tithe: /agt help - show available commands",
        messages[1]
    )
end)

test.test("lifecycle registers slash handling once when duplicate load events arrive", function()
    local addon = loadRuntimeModules()
    local registrations = 0
    local client = {
        RegisterSlashCommand = function()
            registrations = registrations + 1
            return true
        end,
        IsLoggedIn = function()
            return false
        end,
    }
    local lifecycle = addon.Lifecycle.Create(client, {})

    lifecycle:OnEvent("ADDON_LOADED", "AsgardsGuildTithe")
    lifecycle:OnEvent("ADDON_LOADED", "AsgardsGuildTithe")

    test.assertEqual(1, registrations)
end)

test.test("lifecycle initializes state once when duplicate login events arrive", function()
    local addon = loadRuntimeModules()
    local initializations = 0
    local state = {
        Initialize = function()
            initializations = initializations + 1
            return true
        end,
    }
    local lifecycle = addon.Lifecycle.Create({}, {}, state)

    lifecycle:OnEvent("PLAYER_LOGIN")
    lifecycle:OnEvent("PLAYER_LOGIN")

    test.assertEqual(1, initializations)
    test.assertTrue(lifecycle.stateReady)
end)

test.test("lifecycle retries failed state initialization and stops after success", function()
    local addon = loadRuntimeModules()
    local attempts = 0
    local messages = {}
    local client = {
        Print = function(_, message)
            table.insert(messages, message)
            return true
        end,
    }
    local state = {
        Initialize = function()
            attempts = attempts + 1
            if attempts < 3 then
                return false, "current character identity is unavailable"
            end
            return true
        end,
    }
    local lifecycle = addon.Lifecycle.Create(client, {}, state)

    lifecycle:OnEvent("PLAYER_LOGIN")
    lifecycle:OnEvent("PLAYER_ENTERING_WORLD")
    lifecycle:OnEvent("PLAYER_ENTERING_WORLD")
    lifecycle:OnEvent("PLAYER_ENTERING_WORLD")

    test.assertEqual(3, attempts)
    test.assertTrue(lifecycle.stateReady)
    test.assertEqual(1, #messages)
end)

test.test("lifecycle initializes state at add-on load when the player is already logged in", function()
    local addon = loadRuntimeModules()
    local initializations = 0
    local environment = {
        IsLoggedIn = function()
            return true
        end,
        SlashCmdList = {},
    }
    local client = addon.Compatibility.Create(environment)
    local state = {
        Initialize = function()
            initializations = initializations + 1
            return true
        end,
    }
    local lifecycle = addon.Lifecycle.Create(client, addon.CommandRouter.Create(), state)

    lifecycle:OnEvent("ADDON_LOADED", "AsgardsGuildTithe")
    lifecycle:OnEvent("PLAYER_LOGIN")

    test.assertEqual(1, initializations)
    test.assertTrue(lifecycle.stateReady)
end)

test.test("missing frame capability falls back to immediate slash registration", function()
    local addon = loadRuntimeModules()
    local environment = { SlashCmdList = {} }
    local client = addon.Compatibility.Create(environment)
    local router = addon.CommandRouter.Create()
    local lifecycle = addon.Lifecycle.Create(client, router)

    test.assertFalse(lifecycle:Start())
    test.assertFalse(lifecycle.initialized)
    test.assertTrue(lifecycle.slashRegistered)
    test.assertEqual("/agt", environment.SLASH_AGT1)
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
    test.assertFalse(lifecycle.initialized)
    test.assertFalse(lifecycle.slashRegistered)
end)

test.test("client adapter contains errors raised by optional APIs", function()
    local addon = loadRuntimeModules()
    local environment = {
        CreateFrame = function()
            error("client frame API failed")
        end,
        RegisterNewSlashCommand = function()
            error("client slash API failed")
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
    test.assertEqual("/agt", environment.SLASH_AGT1)
end)

test.test("lifecycle initializes character state independently from slash handling", function()
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

    test.assertTrue(lifecycle:InitializeState())

    test.assertTrue(lifecycle.stateReady)
    test.assertEqual("state", calls[1])
    test.assertEqual(nil, calls[2])
end)

test.test("lifecycle registers settings after state initialization", function()
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

    test.assertTrue(lifecycle:InitializeState())

    test.assertTrue(lifecycle.stateReady)
    test.assertTrue(lifecycle.settingsReady)
    test.assertEqual("state", calls[1])
    test.assertEqual("settings", calls[2])
    test.assertEqual(nil, calls[3])
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

    lifecycle:RegisterSlash()
    test.assertTrue(lifecycle:InitializeState())
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

    lifecycle:RegisterSlash()
    test.assertFalse(lifecycle:InitializeState())

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

    lifecycle:RegisterSlash()
    test.assertFalse(lifecycle:InitializeState())

    test.assertFalse(lifecycle.stateReady)
    test.assertContains(messages[1], "persistence exploded")
end)
