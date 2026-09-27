local test = require("tests.test_helper")

local function loadSettingsModules()
    return test.newAddon(
        "Adapters/WoW.lua",
        "Core/CharacterState.lua",
        "Core/CommandRouter.lua",
        "Core/SettingsController.lua"
    )
end

local function newEnvironment(name, realm, database, settings)
    return {
        GuildTitheDB = database,
        Settings = settings,
        UnitName = function()
            return name
        end,
        GetRealmName = function()
            return realm
        end,
    }
end

local function newSettingsAPI()
    local category = {}
    function category:GetID()
        return 73
    end

    local api = {
        VarType = { Number = "number" },
        category = category,
    }

    function api.RegisterVerticalLayoutCategory(name)
        api.categoryName = name
        return category
    end

    function api.RegisterProxySetting(registeredCategory, variable, variableType, label,
        defaultValue, getValue, setValue)
        api.binding = {
            category = registeredCategory,
            variable = variable,
            variableType = variableType,
            label = label,
            defaultValue = defaultValue,
            getValue = getValue,
            setValue = setValue,
        }
        return { kind = "proxy-setting" }
    end

    function api.CreateSliderOptions(minimum, maximum, step)
        api.sliderOptions = {
            minimum = minimum,
            maximum = maximum,
            step = step,
        }
        return api.sliderOptions
    end

    function api.CreateSlider(registeredCategory, setting, options, tooltip)
        api.slider = {
            category = registeredCategory,
            setting = setting,
            options = options,
            tooltip = tooltip,
        }
        return { kind = "slider" }
    end

    function api.RegisterAddOnCategory(registeredCategory)
        api.registeredCategory = registeredCategory
    end

    function api.OpenToCategory(categoryID)
        api.openedCategoryID = categoryID
    end

    return api
end

local function createController(addon, environment)
    local client = addon.Compatibility.Create(environment)
    local state = addon.CharacterState.Create(client)
    test.assertTrue(state:Initialize())
    return addon.SettingsController.Create(client, state), state
end

test.test("native percentage setting binds immediately without changing financial state", function()
    local addon = loadSettingsModules()
    local api = newSettingsAPI()
    local environment = newEnvironment("Jaina", "Camelot", nil, api)
    local controller, state = createController(addon, environment)
    test.assertTrue(state:SetFinancialState(98765, 42))

    test.assertTrue(controller:Register())

    test.assertEqual("Guild Tithe", api.categoryName)
    test.assertEqual(api.category, api.registeredCategory)
    test.assertEqual("GuildTithe_Percentage", api.binding.variable)
    test.assertEqual("number", api.binding.variableType)
    test.assertEqual("Tithe percentage", api.binding.label)
    test.assertEqual(10, api.binding.defaultValue)
    test.assertEqual(0, api.sliderOptions.minimum)
    test.assertEqual(100, api.sliderOptions.maximum)
    test.assertEqual(1, api.sliderOptions.step)
    test.assertEqual(10, api.binding.getValue())

    test.assertTrue(api.binding.setValue(37))
    local character = state:GetCurrentCharacter()
    test.assertEqual(37, character.percentage)
    test.assertEqual(98765, character.outstandingCopper)
    test.assertEqual(42, character.fractionalRemainder)
end)

test.test("percentage binding rejects malformed values without corrupting state", function()
    local addon = loadSettingsModules()
    local api = newSettingsAPI()
    local controller, state = createController(
        addon,
        newEnvironment("Anduin", "Camelot", nil, api)
    )
    test.assertTrue(controller:Register())

    local invalidValues = { "20", "not a number", 1.5, -1, 101 }
    local index
    for index = 1, #invalidValues do
        test.assertFalse(api.binding.setValue(invalidValues[index]))
        test.assertEqual(10, state:GetCurrentCharacter().percentage)
    end
end)

test.test("settings changes survive reload and remain isolated by character", function()
    local addon = loadSettingsModules()
    local firstAPI = newSettingsAPI()
    local firstEnvironment = newEnvironment("Valeera", "Realm One", nil, firstAPI)
    local firstController = createController(addon, firstEnvironment)
    test.assertTrue(firstController:Register())
    test.assertTrue(firstAPI.binding.setValue(23))

    local secondAPI = newSettingsAPI()
    local secondEnvironment = newEnvironment(
        "Valeera",
        "Realm Two",
        firstEnvironment.GuildTitheDB,
        secondAPI
    )
    local secondController = createController(addon, secondEnvironment)
    test.assertTrue(secondController:Register())
    test.assertEqual(10, secondAPI.binding.getValue())
    test.assertTrue(secondAPI.binding.setValue(55))

    local reloadAPI = newSettingsAPI()
    local reloadedController = createController(addon, newEnvironment(
        "Valeera",
        "Realm One",
        firstEnvironment.GuildTitheDB,
        reloadAPI
    ))
    test.assertTrue(reloadedController:Register())
    test.assertEqual(23, reloadAPI.binding.getValue())
    test.assertEqual(55, secondAPI.binding.getValue())
end)

test.test("empty slash input opens the registered add-on settings category", function()
    local addon = loadSettingsModules()
    local api = newSettingsAPI()
    local environment = newEnvironment("Thrall", "Camelot", nil, api)
    local controller = createController(addon, environment)
    local client = addon.Compatibility.Create(environment)
    local router = addon.CommandRouter.Create()
    router:Register("help", "show available commands", function()
        router:PrintHelp()
    end)
    test.assertTrue(controller:RegisterCommands(router))
    test.assertTrue(controller:Register())

    test.assertTrue(router:Execute(""))
    test.assertEqual(73, api.openedCategoryID)
end)

test.test("missing or incompatible settings APIs preserve data and explain slash fallback", function()
    local addon = loadSettingsModules()
    local messages = {}
    local environment = newEnvironment("Rexxar", "Camelot")
    environment.DEFAULT_CHAT_FRAME = {
        AddMessage = function(_, message)
            table.insert(messages, message)
        end,
    }
    local controller, state = createController(addon, environment)
    local database = environment.GuildTitheDB
    local router = addon.CommandRouter.Create()
    router:Register("help", "show available commands", function()
        router:PrintHelp()
    end)
    controller:RegisterCommands(router)

    test.assertFalse(controller:Register())
    test.assertTrue(router:Execute(""))
    test.assertEqual(database, environment.GuildTitheDB)
    test.assertEqual(10, state:GetCurrentCharacter().percentage)
    test.assertContains(messages[1], "settings are unavailable")
    test.assertContains(messages[1], "/gt help")

    local incompatibleAPI = newSettingsAPI()
    incompatibleAPI.RegisterProxySetting = function()
        error("unsupported signature")
    end
    environment.Settings = incompatibleAPI
    test.assertFalse(controller:Register())
    test.assertEqual(database, environment.GuildTitheDB)
    test.assertEqual(10, state:GetCurrentCharacter().percentage)
end)
