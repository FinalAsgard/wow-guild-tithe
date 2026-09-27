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
        VarType = {
            Boolean = "boolean",
            Number = "number",
        },
        bindings = {},
        checkboxes = {},
        category = category,
    }

    function api.RegisterVerticalLayoutCategory(name)
        api.categoryName = name
        return category
    end

    function api.RegisterProxySetting(registeredCategory, variable, variableType, label,
        defaultValue, getValue, setValue)
        local binding = {
            category = registeredCategory,
            variable = variable,
            variableType = variableType,
            label = label,
            defaultValue = defaultValue,
            getValue = getValue,
            setValue = setValue,
        }
        api.bindings[variable] = binding
        if variableType == api.VarType.Number then
            api.binding = binding
        end
        return binding
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

    function api.CreateCheckbox(registeredCategory, setting, tooltip)
        local checkbox = {
            category = registeredCategory,
            setting = setting,
            tooltip = tooltip,
        }
        table.insert(api.checkboxes, checkbox)
        return checkbox
    end

    function api.RegisterAddOnCategory(registeredCategory)
        api.registeredCategory = registeredCategory
    end

    function api.OpenToCategory(categoryID)
        api.openedCategoryID = categoryID
    end

    return api
end

local PREFERENCE_CASES = {
    {
        variable = "GuildTithe_Source_Loot",
        source = "loot",
        defaultValue = true,
    },
    {
        variable = "GuildTithe_Source_Quests",
        source = "quests",
        defaultValue = true,
    },
    {
        variable = "GuildTithe_Source_VendorSales",
        source = "vendorSales",
        defaultValue = true,
    },
    {
        variable = "GuildTithe_Source_Auctions",
        source = "auctions",
        defaultValue = false,
    },
    {
        variable = "GuildTithe_Source_Mailbox",
        source = "mailbox",
        defaultValue = false,
    },
    {
        variable = "GuildTithe_Source_PlayerTrades",
        source = "playerTrades",
        defaultValue = true,
    },
    {
        variable = "GuildTithe_Source_Miscellaneous",
        source = "miscellaneous",
        defaultValue = true,
    },
    {
        variable = "GuildTithe_ChatFeedback",
        field = "chatFeedback",
        defaultValue = true,
    },
}

local function preferenceValue(character, preference)
    if preference.source ~= nil then
        return character.sources[preference.source]
    end

    return character[preference.field]
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

test.test("settings expose all source and chat preferences with fresh-character defaults", function()
    local addon = loadSettingsModules()
    local api = newSettingsAPI()
    local controller = createController(addon, newEnvironment("Tyrande", "Camelot", nil, api))

    test.assertTrue(controller:Register())
    test.assertEqual(8, #api.checkboxes)

    local index
    for index = 1, #PREFERENCE_CASES do
        local preference = PREFERENCE_CASES[index]
        local binding = api.bindings[preference.variable]
        test.assertEqual("boolean", binding.variableType, preference.variable)
        test.assertEqual(preference.defaultValue, binding.defaultValue, preference.variable)
        test.assertEqual(preference.defaultValue, binding.getValue(), preference.variable)
    end
end)

test.test("every preference updates only itself and preserves financial state", function()
    local index

    for index = 1, #PREFERENCE_CASES do
        local addon = loadSettingsModules()
        local api = newSettingsAPI()
        local controller, state = createController(
            addon,
            newEnvironment("Moira", "Camelot", nil, api)
        )
        test.assertTrue(state:SetFinancialState(654321, 87))
        test.assertTrue(controller:Register())

        local preference = PREFERENCE_CASES[index]
        local binding = api.bindings[preference.variable]
        local before = state:GetCurrentCharacter()
        local changedValue = not preference.defaultValue

        test.assertTrue(binding.setValue(changedValue), preference.variable)
        test.assertEqual(changedValue, binding.getValue(), preference.variable)

        local after = state:GetCurrentCharacter()
        test.assertEqual(before.percentage, after.percentage, preference.variable)
        test.assertEqual(654321, after.outstandingCopper, preference.variable)
        test.assertEqual(87, after.fractionalRemainder, preference.variable)

        local otherIndex
        for otherIndex = 1, #PREFERENCE_CASES do
            local other = PREFERENCE_CASES[otherIndex]
            local expected = other.defaultValue
            if otherIndex == index then
                expected = changedValue
            end
            test.assertEqual(expected, preferenceValue(after, other),
                preference.variable .. " changed " .. other.variable)
        end
    end
end)

test.test("preference bindings reject non-boolean values without changing state", function()
    local addon = loadSettingsModules()
    local api = newSettingsAPI()
    local controller, state = createController(
        addon,
        newEnvironment("Baine", "Camelot", nil, api)
    )
    test.assertTrue(controller:Register())

    local index
    for index = 1, #PREFERENCE_CASES do
        local preference = PREFERENCE_CASES[index]
        test.assertFalse(api.bindings[preference.variable].setValue("yes"), preference.variable)
        test.assertEqual(preference.defaultValue,
            preferenceValue(state:GetCurrentCharacter(), preference), preference.variable)
    end
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

test.test("all preferences survive reload and remain isolated by character", function()
    local addon = loadSettingsModules()
    local firstAPI = newSettingsAPI()
    local firstEnvironment = newEnvironment("Valeera", "Realm One", nil, firstAPI)
    local firstController = createController(addon, firstEnvironment)
    test.assertTrue(firstController:Register())

    local index
    for index = 1, #PREFERENCE_CASES do
        local preference = PREFERENCE_CASES[index]
        test.assertTrue(firstAPI.bindings[preference.variable].setValue(
            not preference.defaultValue
        ), preference.variable)
    end

    local secondAPI = newSettingsAPI()
    local secondController = createController(addon, newEnvironment(
        "Valeera",
        "Realm Two",
        firstEnvironment.GuildTitheDB,
        secondAPI
    ))
    test.assertTrue(secondController:Register())

    local reloadAPI = newSettingsAPI()
    local reloadedController = createController(addon, newEnvironment(
        "Valeera",
        "Realm One",
        firstEnvironment.GuildTitheDB,
        reloadAPI
    ))
    test.assertTrue(reloadedController:Register())

    for index = 1, #PREFERENCE_CASES do
        local preference = PREFERENCE_CASES[index]
        test.assertEqual(preference.defaultValue,
            secondAPI.bindings[preference.variable].getValue(), preference.variable)
        test.assertEqual(not preference.defaultValue,
            reloadAPI.bindings[preference.variable].getValue(), preference.variable)
    end
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

    local missingCheckboxAPI = newSettingsAPI()
    missingCheckboxAPI.CreateCheckbox = nil
    environment.Settings = missingCheckboxAPI
    test.assertFalse(controller:Register())
    test.assertEqual(database, environment.GuildTitheDB)
    test.assertTrue(state:GetCurrentCharacter().sources.loot)

    local failedCheckboxAPI = newSettingsAPI()
    failedCheckboxAPI.CreateCheckbox = function()
        return nil
    end
    environment.Settings = failedCheckboxAPI
    test.assertFalse(controller:Register())
    test.assertEqual(database, environment.GuildTitheDB)
    test.assertTrue(state:GetCurrentCharacter().sources.loot)
end)
