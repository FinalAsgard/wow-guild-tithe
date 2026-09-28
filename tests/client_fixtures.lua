local test = require("tests.test_helper")

-- Controlled WoW API surfaces representative of each supported client. Only
-- the differences the adapter must handle are modelled; everything else is
-- shared so a behavior difference between profiles is always deliberate.
local Fixtures = {
    PROFILES = { "Forever", "Retail" },
}

local MANIFESTS = {
    Forever = "AsgardsGuildTithe_Camelot.toc",
    Retail = "AsgardsGuildTithe_Standard.toc",
}

local function manifestFiles(profile)
    local files = {}
    local line
    for line in io.lines(MANIFESTS[profile]) do
        line = line:gsub("%s+$", "")
        if string.sub(line, 1, 2) ~= "##" and string.match(line, "%.lua$") then
            table.insert(files, line)
        end
    end
    return files
end

local function newFrame()
    local frame = { registeredEvents = {} }
    function frame:RegisterEvent(eventName)
        self.registeredEvents[eventName] = true
    end
    function frame:SetScript(_, handler)
        self.handler = handler
    end
    return frame
end

local function metadataReader(declaredClient)
    return function(_, field)
        if field == "X-Client" then
            return declaredClient
        end
        return nil
    end
end

local PROFILE_APIS = {
    -- Forever exposes the legacy metadata global and the newer slash API, and
    -- shares Retail's project constants, which must not make it Retail.
    Forever = function(environment, declaredClient)
        environment.GetAddOnMetadata = metadataReader(declaredClient)
        environment.WOW_PROJECT_ID = 1
        environment.WOW_PROJECT_MAINLINE = 1
        environment.RegisterNewSlashCommand = function(callback, command, alias)
            local key = string.upper(command)
            environment["SLASH_" .. key .. "1"] = "/" .. command
            environment["SLASH_" .. key .. "2"] = "/" .. alias
            environment.SlashCmdList[key] = callback
        end
    end,
    Retail = function(environment, declaredClient)
        environment.C_AddOns = { GetAddOnMetadata = metadataReader(declaredClient) }
        environment.WOW_PROJECT_ID = 1
        environment.WOW_PROJECT_MAINLINE = 1
    end,
}

-- Returns a WoW-like global environment for `profile`. `options.declaredClient`
-- overrides the manifest's X-Client value (nil keeps the profile's own name).
function Fixtures.newEnvironment(profile, options)
    options = options or {}
    local world = {
        frame = newFrame(),
        messages = {},
        playerReady = false,
    }

    local environment = {
        CreateFrame = function()
            return world.frame
        end,
        DEFAULT_CHAT_FRAME = {
            AddMessage = function(_, message)
                table.insert(world.messages, message)
            end,
        },
        GetRealmName = function()
            return "Camelot"
        end,
        IsLoggedIn = function()
            return false
        end,
        SlashCmdList = {},
        UNKNOWNOBJECT = "Unknown",
        UnitGUID = function()
            return "Player-7"
        end,
        UnitName = function()
            return world.playerReady and "Jaina" or "Unknown"
        end,
    }
    setmetatable(environment, { __index = _G })
    environment._G = environment

    local declaredClient = options.declaredClient
    if declaredClient == nil then
        declaredClient = profile
    end
    PROFILE_APIS[profile](environment, declaredClient)

    world.environment = environment
    world.profile = profile
    return world
end

-- Loads the profile's production manifest in order inside `world.environment`.
function Fixtures.loadAddon(world)
    local addon = {}
    local files = manifestFiles(world.profile)
    local index
    for index = 1, #files do
        test.loadAddonFileInEnvironment(files[index], addon, world.environment)
    end
    world.addon = addon
    return addon
end

function Fixtures.fire(world, eventName, ...)
    world.frame.handler(world.frame, eventName, ...)
end

function Fixtures.snapshot(value)
    if type(value) ~= "table" then
        return value
    end

    local copy = {}
    local key, item
    for key, item in pairs(value) do
        copy[key] = Fixtures.snapshot(item)
    end
    return copy
end

function Fixtures.assertSameData(expected, actual, path)
    path = path or "data"
    test.assertEqual(type(expected), type(actual), path .. " type")
    if type(expected) ~= "table" then
        test.assertEqual(expected, actual, path)
        return
    end

    local key
    for key in pairs(expected) do
        Fixtures.assertSameData(expected[key], actual[key], path .. "." .. tostring(key))
    end
    for key in pairs(actual) do
        test.assertTrue(expected[key] ~= nil, path .. "." .. tostring(key) .. " was added")
    end
end

return Fixtures
