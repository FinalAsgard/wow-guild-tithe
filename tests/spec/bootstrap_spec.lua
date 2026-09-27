local test = require("tests.test_helper")

local MANIFEST_FILES = {
    "Adapters/WoW.lua",
    "Core/Persistence.lua",
    "Core/CharacterState.lua",
    "Core/Accounting.lua",
    "Core/TitheService.lua",
    "Core/MoneyFormatter.lua",
    "Core/CommandRouter.lua",
    "Core/SettingsController.lua",
    "Core/Lifecycle.lua",
    "GuildTithe.lua",
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
        category = category,
        layout = layout,
    }

    function settings.RegisterVerticalLayoutCategory()
        return category, layout
    end

    function settings.RegisterProxySetting(_, _, _, _, _, getValue, setValue)
        return { getValue = getValue, setValue = setValue }
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

test.test("manifest files compose and bootstrap in declared load order", function()
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

    local addon = {}
    local files = tocFiles("GuildTithe_Camelot.toc")
    local index
    for index = 1, #files do
        test.loadAddonFileInEnvironment(files[index], addon, environment)
    end

    test.assertEqual("ADDON_LOADED", frame.eventName)
    test.assertEqual("OnEvent", frame.scriptName)
    test.assertEqual(nil, environment.GuildTitheDB)

    frame.handler(frame, "ADDON_LOADED", "GuildTithe")

    test.assertEqual(2, environment.GuildTitheDB.schemaVersion)
    test.assertEqual("table", type(environment.GuildTitheDB.characters["jaina-camelot"]))
    test.assertEqual("/gt", environment.SLASH_GUILDTITHE1)
    test.assertEqual("function", type(environment.SlashCmdList.GUILDTITHE))
    test.assertEqual(settings.category, settings.registeredCategory)

    environment.SlashCmdList.GUILDTITHE("")
    test.assertEqual(73, settings.openedCategoryID)
    test.assertEqual(0, #messages)
end)
