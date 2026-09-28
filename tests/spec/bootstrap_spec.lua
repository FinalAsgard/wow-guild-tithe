local test = require("tests.test_helper")

local MANIFEST_FILES = {
    "Core/Identity.lua",
    "Adapters/WoW.lua",
    "Core/Persistence.lua",
    "Core/CharacterState.lua",
    "Core/Accounting.lua",
    "Core/TitheService.lua",
    "Core/MoneyFormatter.lua",
    "Core/CommandRouter.lua",
    "Core/SettingsController.lua",
    "Core/Lifecycle.lua",
    "AsgardsGuildTithe.lua",
}

local VARIANTS = {
    {
        addonName = "AsgardsGuildTithe",
        databaseName = "AsgardsGuildTitheDB",
        displayName = "Asgard's Guild Tithe",
        otherDatabaseName = "AsgardsGuildTitheDevDB",
        slashCommand = "/agt",
        slashKey = "ASGARDSGUILDTITHE",
        toc = "AsgardsGuildTithe_Camelot.toc",
    },
    {
        addonName = "AsgardsGuildTitheDev",
        databaseName = "AsgardsGuildTitheDevDB",
        displayName = "Asgard's Guild Tithe (Dev)",
        otherDatabaseName = "AsgardsGuildTitheDB",
        slashCommand = "/agtdev",
        slashKey = "ASGARDSGUILDTITHEDEV",
        toc = "AsgardsGuildTitheDev_Camelot.toc",
    },
}

local function tocFiles(path)
    if type(io) ~= "table" or type(io.lines) ~= "function" then
        return MANIFEST_FILES
    end

    local files = {}
    local line
    for line in io.lines(path) do
        line = line:gsub("%s+$", "")
        if string.sub(line, 1, 2) ~= "##" and string.match(line, "%.lua$") then
            table.insert(files, line)
        end
    end
    return files
end

local function newSettingsAPI()
    local category = {}
    function category:GetID()
        return 73
    end

    local layout = { initializers = {} }
    function layout:AddInitializer(initializer)
        table.insert(self.initializers, initializer)
    end

    local settings = {
        VarType = { Boolean = "boolean", Number = "number" },
        bindings = {},
        category = category,
        layout = layout,
    }

    function settings.RegisterVerticalLayoutCategory(name)
        settings.categoryName = name
        return category, layout
    end

    function settings.RegisterProxySetting(_, variable, _, _, _, getValue, setValue)
        local setting = { getValue = getValue, setValue = setValue }
        settings.bindings[variable] = setting
        return setting
    end

    function settings.CreateSliderOptions(minimum, maximum, step)
        return { minimum = minimum, maximum = maximum, step = step }
    end

    function settings.CreateSlider()
        return {}
    end

    function settings.CreateCheckbox()
        return {}
    end

    function settings.RegisterAddOnCategory(registeredCategory)
        settings.registeredCategory = registeredCategory
    end

    function settings.OpenToCategory(categoryID)
        settings.openedCategoryID = categoryID
    end

    return settings
end

local function registerBootstrapTest(variant)
    test.test(variant.displayName .. " composes and bootstraps in manifest order", function()
        local frame = {}
        function frame:RegisterEvent(eventName)
            self.eventName = eventName
        end
        function frame:SetScript(scriptName, handler)
            self.scriptName = scriptName
            self.handler = handler
        end

        local settings = newSettingsAPI()
        local messages = {}
        local environment = {
            CreateFrame = function(frameType)
                test.assertEqual("Frame", frameType)
                return frame
            end,
            CreateSettingsListSectionHeaderInitializer = function(name)
                local initializer = { data = { name = name } }
                function initializer:GetData()
                    return self.data
                end
                return initializer
            end,
            DEFAULT_CHAT_FRAME = {
                AddMessage = function(_, message)
                    table.insert(messages, message)
                end,
            },
            GetRealmName = function()
                return "Camelot"
            end,
            Settings = settings,
            SlashCmdList = {},
            UnitGUID = function()
                return "Player-7"
            end,
            UnitName = function()
                return "Jaina"
            end,
        }
        setmetatable(environment, { __index = _G })
        environment._G = environment
        local legacyDatabase = { sentinel = "legacy GuildTithe data" }
        local otherVariantDatabase = { sentinel = "other isolated variant" }
        environment.GuildTitheDB = legacyDatabase
        environment[variant.otherDatabaseName] = otherVariantDatabase

        local addon = {}
        local files = tocFiles(variant.toc)
        local index
        for index = 1, #files do
            test.loadAddonFileInEnvironment(
                files[index],
                addon,
                environment,
                variant.addonName
            )
        end

        test.assertEqual("ADDON_LOADED", frame.eventName)
        test.assertEqual("OnEvent", frame.scriptName)
        test.assertEqual(nil, environment[variant.databaseName])

        frame.handler(frame, "ADDON_LOADED", variant.addonName)

        local database = environment[variant.databaseName]
        test.assertEqual(2, database.schemaVersion)
        test.assertEqual("table", type(database.characters["jaina-camelot"]))
        test.assertEqual(otherVariantDatabase, environment[variant.otherDatabaseName])
        test.assertEqual(legacyDatabase, environment.GuildTitheDB)
        test.assertEqual(variant.displayName, settings.categoryName)
        test.assertEqual("table", type(settings.bindings[
            variant.addonName .. "_Percentage"
        ]))
        test.assertEqual(
            variant.slashCommand,
            environment["SLASH_" .. variant.slashKey .. "1"]
        )
        test.assertEqual("function", type(environment.SlashCmdList[variant.slashKey]))
        test.assertEqual(settings.category, settings.registeredCategory)

        environment.SlashCmdList[variant.slashKey]("")
        test.assertEqual(73, settings.openedCategoryID)
        test.assertEqual(0, #messages)
    end)
end

local index
for index = 1, #VARIANTS do
    registerBootstrapTest(VARIANTS[index])
end
