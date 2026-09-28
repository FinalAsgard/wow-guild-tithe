local test = require("tests.test_helper")

local MANIFEST_FILES = {
    "Core/Identity.lua",
    "Adapters/ClientProfile.lua",
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

local PRODUCTS = {
    {
        addonName = "AsgardsGuildTithe",
        databaseName = "AsgardsGuildTitheDB",
        displayName = "Asgard's Guild Tithe",
        otherDatabaseName = "AsgardsGuildTitheDevDB",
        slashCommand = "/agt",
        slashAlias = "/asgardstithe",
        slashKey = "AGT",
        version = "0.1.0",
    },
    {
        addonName = "AsgardsGuildTitheDev",
        databaseName = "AsgardsGuildTitheDevDB",
        displayName = "Asgard's Guild Tithe (Dev)",
        otherDatabaseName = "AsgardsGuildTitheDB",
        slashCommand = "/agtdev",
        slashAlias = "/asgardstithedev",
        slashKey = "AGTDEV",
        version = "0.1.0-dev",
    },
}

-- Interface numbers are release metadata: re-verify them from the running
-- clients after each game patch (see README).
local CLIENTS = {
    { name = "Forever", suffix = "_Camelot", interface = "16000, 16001" },
    { name = "Retail", suffix = "_Mainline", interface = "120100" },
}

local VARIANTS = {}
local productIndex, clientIndex
for productIndex = 1, #PRODUCTS do
    for clientIndex = 1, #CLIENTS do
        local product = PRODUCTS[productIndex]
        local client = CLIENTS[clientIndex]
        local variant = {}
        local key, value
        for key, value in pairs(product) do
            variant[key] = value
        end
        variant.client = client.name
        variant.interface = client.interface
        variant.toc = product.addonName .. client.suffix .. ".toc"
        table.insert(VARIANTS, variant)
    end
end

local function tocMetadata(path)
    local metadata = {}
    local line
    for line in io.lines(path) do
        local field, value = string.match(line, "^## ([%w%-]+):%s*(.-)%s*$")
        if field ~= nil then
            metadata[field] = value
        end
    end
    return metadata
end

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
        local options = { minimum = minimum, maximum = maximum, step = step }
        function options:SetLabelFormatter(label, formatter)
            settings.sliderLabel = label
            settings.sliderFormatter = formatter
        end
        return options
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
    test.test(variant.displayName .. " composes and bootstraps from " .. variant.toc, function()
        local frame = { registeredEvents = {} }
        function frame:RegisterEvent(eventName)
            self.registeredEvents[eventName] = true
        end
        function frame:SetScript(scriptName, handler)
            self.scriptName = scriptName
            self.handler = handler
        end

        local settings = newSettingsAPI()
        local messages = {}
        local playerReady = false
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
            GetAddOnMetadata = function(addonName, field)
                test.assertEqual(variant.addonName, addonName)
                return tocMetadata(variant.toc)[field]
            end,
            GetRealmName = function()
                return "Camelot"
            end,
            MinimalSliderWithSteppersMixin = {
                Label = { Right = "right" },
            },
            Settings = settings,
            SlashCmdList = {},
            UnitGUID = function()
                return "Player-7"
            end,
            UnitName = function()
                return playerReady and "Jaina" or "Unknown"
            end,
            WOW_PROJECT_ID = 1,
            WOW_PROJECT_MAINLINE = 1,
        }
        setmetatable(environment, { __index = _G })
        environment._G = environment
        environment.RegisterNewSlashCommand = function(callback, command, alias)
            local key = string.upper(command)
            environment["SLASH_" .. key .. "1"] = "/" .. command
            environment["SLASH_" .. key .. "2"] = "/" .. alias
            environment.SlashCmdList[key] = callback
            environment.registeredSlashAlias = "/" .. alias
        end
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

        test.assertTrue(frame.registeredEvents.ADDON_LOADED)
        test.assertTrue(frame.registeredEvents.PLAYER_LOGIN)
        test.assertEqual("OnEvent", frame.scriptName)
        test.assertEqual(nil, environment[variant.databaseName])

        frame.handler(frame, "ADDON_LOADED", variant.addonName)

        test.assertEqual(nil, environment[variant.databaseName])
        test.assertEqual(
            variant.slashCommand,
            environment["SLASH_" .. variant.slashKey .. "1"]
        )

        playerReady = true
        frame.handler(frame, "PLAYER_LOGIN")

        local database = environment[variant.databaseName]
        test.assertEqual(2, database.schemaVersion)
        test.assertEqual("table", type(database.characters["jaina-camelot"]))
        test.assertEqual(otherVariantDatabase, environment[variant.otherDatabaseName])
        test.assertEqual(legacyDatabase, environment.GuildTitheDB)
        test.assertEqual(variant.displayName, settings.categoryName)
        test.assertEqual("right", settings.sliderLabel)
        test.assertEqual("42%", settings.sliderFormatter(42))
        test.assertEqual("table", type(settings.bindings[
            variant.addonName .. "_Percentage"
        ]))
        test.assertEqual(
            variant.slashCommand,
            environment["SLASH_" .. variant.slashKey .. "1"]
        )
        test.assertEqual(variant.slashAlias, environment.registeredSlashAlias)
        test.assertEqual("function", type(environment.SlashCmdList[variant.slashKey]))
        test.assertEqual(settings.category, settings.registeredCategory)

        environment.SlashCmdList[variant.slashKey]("")
        test.assertEqual(73, settings.openedCategoryID)
        test.assertEqual(0, #messages)
        test.assertEqual(variant.client == "Forever" and "forever" or "retail", addon.clientProfile.id)
    end)
end

local function registerManifestTest(variant)
    test.test(variant.toc .. " declares its client, product identity, and SavedVariables", function()
        local metadata = tocMetadata(variant.toc)

        test.assertEqual(variant.interface, metadata.Interface)
        test.assertEqual(variant.displayName, metadata.Title)
        test.assertEqual(variant.version, metadata.Version)
        test.assertEqual(variant.databaseName, metadata.SavedVariables)
        test.assertEqual(variant.client, metadata["X-Client"])
        test.assertEqual(nil, string.find(metadata.SavedVariables, variant.otherDatabaseName, 1, true))
    end)
end

local index
for index = 1, #VARIANTS do
    registerManifestTest(VARIANTS[index])
    registerBootstrapTest(VARIANTS[index])
end

test.test("every manifest loads the same modules in the same order", function()
    local expected = tocFiles(VARIANTS[1].toc)
    test.assertEqual(#MANIFEST_FILES, #expected, VARIANTS[1].toc .. " module count")

    local variantIndex, fileIndex
    for variantIndex = 1, #VARIANTS do
        local files = tocFiles(VARIANTS[variantIndex].toc)
        test.assertEqual(#expected, #files, VARIANTS[variantIndex].toc .. " module count")
        for fileIndex = 1, #expected do
            test.assertEqual(
                expected[fileIndex],
                files[fileIndex],
                VARIANTS[variantIndex].toc .. " module " .. fileIndex
            )
        end
    end
end)

test.test("only the supported client manifests exist", function()
    if type(io.popen) ~= "function" then
        return
    end

    local expected = {}
    local variantIndex
    for variantIndex = 1, #VARIANTS do
        expected[VARIANTS[variantIndex].toc] = true
    end

    local listing = io.popen("ls")
    local found = 0
    local name
    for name in listing:lines() do
        if string.match(name, "%.toc$") then
            test.assertTrue(expected[name], "unexpected manifest " .. name)
            found = found + 1
        end
    end
    listing:close()
    test.assertEqual(#VARIANTS, found)
end)

test.test("each client's production and development manifests share one version line", function()
    local clientIndex
    for clientIndex = 1, #CLIENTS do
        local suffix = CLIENTS[clientIndex].suffix
        local production = tocMetadata("AsgardsGuildTithe" .. suffix .. ".toc")
        local development = tocMetadata("AsgardsGuildTitheDev" .. suffix .. ".toc")
        test.assertEqual(production.Version .. "-dev", development.Version, suffix)
        test.assertEqual(production.Interface, development.Interface, suffix)
    end
end)
