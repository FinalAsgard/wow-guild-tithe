local test = require("tests.test_helper")

-- Controlled WoW API surfaces representative of each supported client. Only
-- the differences the adapter must handle are modelled; everything else is
-- shared so a behavior difference between profiles is always deliberate.
local Fixtures = {
    PROFILES = { "Forever", "Retail" },
}

local MANIFESTS = {
    Forever = "AsgardsGuildTithe_Camelot.toc",
    Retail = "AsgardsGuildTithe_Mainline.toc",
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

local function newFrame(world)
    local frame = { registeredEvents = {} }
    table.insert(world.frames, frame)
    function frame:RegisterEvent(eventName)
        self.registeredEvents[eventName] = true
    end
    function frame:SetScript(_, handler)
        self.handler = handler
    end
    return frame
end

-- The native Settings surface both clients expose for add-on categories.
local function newSettingsAPI()
    local category = {}
    function category:GetID()
        return 73
    end

    local layout = { initializers = {} }
    function layout:AddInitializer(initializer)
        table.insert(self.initializers, initializer)
    end

    local api = {
        VarType = { Boolean = "boolean", Number = "number" },
        bindings = {},
        bindingOrder = {},
        category = category,
        checkboxes = 0,
        layout = layout,
        sliders = 0,
    }

    function api.RegisterVerticalLayoutCategory(name)
        api.categoryName = name
        return category, layout
    end

    function api.RegisterProxySetting(_, variable, variableType, label, defaultValue, getValue, setValue)
        local binding = {
            defaultValue = defaultValue,
            getValue = getValue,
            label = label,
            setValue = setValue,
            variableType = variableType,
        }
        api.bindings[variable] = binding
        table.insert(api.bindingOrder, variable)
        return binding
    end

    function api.CreateSliderOptions(minimum, maximum, step)
        local options = { maximum = maximum, minimum = minimum, step = step }
        function options:SetLabelFormatter(_, formatter)
            api.sliderFormatter = formatter
        end
        api.sliderOptions = options
        return options
    end

    function api.CreateSlider()
        api.sliders = api.sliders + 1
        return {}
    end

    function api.CreateCheckbox()
        api.checkboxes = api.checkboxes + 1
        return {}
    end

    function api.RegisterAddOnCategory(registeredCategory)
        api.registeredCategory = registeredCategory
    end

    function api.OpenToCategory(categoryID)
        api.openedCategoryID = categoryID
    end

    return api
end

local function installSettings(environment)
    local api = newSettingsAPI()
    environment.Settings = api
    environment.MinimalSliderWithSteppersMixin = { Label = { Right = "right" } }
    environment.CreateSettingsListSectionHeaderInitializer = function(name)
        local initializer = { data = { name = name } }
        function initializer:GetData()
            return self.data
        end
        return initializer
    end
    return api
end

-- The text currently shown by the read-only balance header.
function Fixtures.balanceText(world)
    return world.settings.layout.initializers[1]:GetData().name
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
-- overrides the manifest's X-Client value (nil keeps the profile's own name),
-- `options.settings = false` omits the native Settings API, `options.database`
-- seeds the production SavedVariables, `options.playerName` sets the
-- character reported once the player is ready, `options.money` sets carried
-- copper (false omits the money API), and `options.inGuild` sets guild
-- membership (false = guildless; `options.guildApi = false` omits the API).
function Fixtures.newEnvironment(profile, options)
    options = options or {}
    local world = {
        frames = {},
        inGuild = options.inGuild ~= false,
        messages = {},
        money = options.money or 0,
        playerName = options.playerName or "Jaina",
        playerReady = false,
    }

    local environment = {
        CreateFrame = function()
            return newFrame(world)
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
            return world.playerReady and world.playerName or "Unknown"
        end,
    }
    setmetatable(environment, { __index = _G })
    environment._G = environment
    environment.AsgardsGuildTitheDB = options.database
    if options.money ~= false then
        environment.GetMoney = function()
            return world.money
        end
    end
    if options.guildApi ~= false then
        environment.IsInGuild = function()
            return world.inGuild
        end
    end
    if options.settings ~= false then
        world.settings = installSettings(environment)
    end

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

-- Delivers a client event to every frame that registered for it.
function Fixtures.fire(world, eventName, ...)
    local index
    for index = 1, #world.frames do
        local frame = world.frames[index]
        if frame.registeredEvents[eventName] and frame.handler ~= nil then
            frame.handler(frame, eventName, ...)
        end
    end
end

-- Changes carried money and fires the client's money event.
function Fixtures.setMoney(world, copper)
    world.money = copper
    Fixtures.fire(world, "PLAYER_MONEY")
end

-- Loads the add-on and runs the normal load then login sequence.
function Fixtures.login(world)
    local addon = Fixtures.loadAddon(world)
    Fixtures.fire(world, "ADDON_LOADED", "AsgardsGuildTithe")
    world.playerReady = true
    Fixtures.fire(world, "PLAYER_LOGIN")
    return addon
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
