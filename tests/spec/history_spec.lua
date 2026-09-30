local test = require("tests.test_helper")
local fixtures = require("tests.client_fixtures")

local CARRIED = 100000

local function character(world)
    return world.environment.AsgardsGuildTitheDB.characters["jaina-camelot"]
end

local function login(profile, options)
    options = options or {}
    local world = fixtures.newEnvironment(profile, {
        money = CARRIED,
        settings = options.settings,
    })
    if options.withoutSubpages and world.settings ~= nil then
        world.settings.RegisterCanvasLayoutSubcategory = nil
    end
    fixtures.installTransferCalls(world, {})
    local addon = fixtures.login(world)
    character(world).autoDeposit = false
    return world, addon
end

local sequence = 0
local function record(addon, overrides)
    sequence = sequence + 1
    local donation = {
        operationId = "history:" .. sequence,
        -- 2026-09-28 12:00:00 UTC plus one minute per donation.
        timestamp = 1790596800 + sequence * 60,
        amount = 5000,
        method = "button",
        character = { key = "jaina-camelot", name = "Jaina", realm = "Camelot" },
        guild = { name = "Knights of Camelot", realm = "Camelot" },
    }
    local key, value
    for key, value in pairs(overrides or {}) do
        donation[key] = value
    end
    test.assertTrue(addon.donationLedger:Append(donation))
    return donation
end

local function page(addon)
    return addon.historyController.page
end

local function row(addon, index)
    local cells = page(addon).rows[index]
    return {
        date = cells.date.text,
        guild = cells.guild.text,
        character = cells.character.text,
        amount = cells.amount.text,
        method = cells.method.text,
    }
end

local function history(world)
    world.environment.SlashCmdList.AGT("history")
end

local function registerProfileTests(profile)
    test.test(profile .. " donation history is a settings tab that /agt history opens", function()
        local world, addon = login(profile)

        test.assertEqual("Donation History", world.settings.subcategory.name)
        test.assertEqual(world.settings.category, world.settings.subcategory.parent)
        test.assertEqual(page(addon).frame, world.settings.subcategory.frame)

        history(world)
        test.assertEqual(74, world.settings.openedCategoryID)

        world.environment.SlashCmdList.AGT("")
        test.assertEqual(73, world.settings.openedCategoryID)
    end)

    test.test(profile .. " before the first donation the tab says so", function()
        local world, addon = login(profile)

        history(world)

        test.assertEqual("Donation History", page(addon).title.text)
        test.assertEqual("Lifetime given: 0g 00s 00c", page(addon).overall.text)
        test.assertContains(page(addon).message.text, "No donations yet")
        test.assertFalse(page(addon).headers[1].shown)
        test.assertFalse(page(addon).older.shown)
        test.assertEqual("", row(addon, 1).amount)
    end)

    test.test(profile .. " rows show date, guild, character, amount, and method, newest first", function()
        local world, addon = login(profile)
        record(addon, { amount = 12345, method = "automatic" })
        record(addon, { amount = 700, method = "manual",
            character = { key = "thrall-avalon", name = "Thrall", realm = "Avalon" },
            guild = { name = "Horde Traders", realm = "Avalon" } })
        record(addon, { amount = 5000, method = "button" })

        history(world)

        test.assertEqual("", page(addon).message.text)
        test.assertTrue(page(addon).headers[1].shown)
        test.assertEqual("Date", page(addon).headers[1].text)
        test.assertEqual("Method", page(addon).headers[5].text)
        local newest = row(addon, 1)
        test.assertEqual("2026-09-28", newest.date)
        test.assertEqual("Knights of Camelot", newest.guild)
        test.assertEqual("Jaina-Camelot", newest.character)
        test.assertEqual("0g 50s 00c", newest.amount)
        test.assertEqual("Guild Tithe", newest.method)
        test.assertEqual("Manual", row(addon, 2).method)
        test.assertEqual("Thrall-Avalon", row(addon, 2).character)
        test.assertEqual("Horde Traders", row(addon, 2).guild)
        test.assertEqual("Guild Tithe", row(addon, 3).method)
        test.assertEqual("1g 23s 45c", row(addon, 3).amount)
        test.assertEqual("", row(addon, 4).amount)

        test.assertEqual("Lifetime given: 1g 80s 45c", page(addon).overall.text)
        test.assertEqual("Knights of Camelot (Camelot): 1g 73s 45c", page(addon).guildLines[1].text)
        test.assertEqual("Horde Traders (Avalon): 0g 07s 00c", page(addon).guildLines[2].text)
        test.assertEqual("", page(addon).guildLines[3].text)
        test.assertEqual("1-3 of 3", page(addon).range.text)
        test.assertFalse(page(addon).newer.enabled)
        test.assertFalse(page(addon).older.enabled)
    end)

    test.test(profile .. " the list scrolls through a long history without changing it", function()
        local world, addon = login(profile)
        local index
        for index = 1, 30 do
            record(addon, { amount = index })
        end
        history(world)
        local before = fixtures.snapshot(world.environment.AsgardsGuildTitheDB.donations)

        test.assertEqual("1-12 of 30", page(addon).range.text)
        test.assertEqual("0g 00s 30c", row(addon, 1).amount)
        test.assertTrue(page(addon).older.enabled)
        test.assertFalse(page(addon).newer.enabled)

        fixtures.click(page(addon).older)
        test.assertEqual("13-24 of 30", page(addon).range.text)
        test.assertEqual("0g 00s 18c", row(addon, 1).amount)

        page(addon).frame.scripts.OnMouseWheel(page(addon).frame, -1)
        test.assertEqual("16-27 of 30", page(addon).range.text)

        fixtures.click(page(addon).older)
        test.assertEqual("19-30 of 30", page(addon).range.text)
        test.assertFalse(page(addon).older.enabled)
        test.assertEqual("0g 00s 01c", row(addon, 12).amount)

        page(addon).frame.scripts.OnMouseWheel(page(addon).frame, 1)
        test.assertEqual("16-27 of 30", page(addon).range.text)

        -- Reopening starts at the newest donation again.
        history(world)
        test.assertEqual("1-12 of 30", page(addon).range.text)
        test.assertEqual("Lifetime given: 0g 04s 65c", page(addon).overall.text)
        fixtures.assertSameData(before, world.environment.AsgardsGuildTitheDB.donations)
    end)

    test.test(profile .. " the tab updates live after a confirmed donation", function()
        local world, addon = login(profile)
        character(world).outstandingCopper = 5000
        history(world)
        test.assertContains(page(addon).message.text, "No donations yet")

        fixtures.fire(world, "GUILDBANKFRAME_OPENED")
        fixtures.advance(world, 1)
        fixtures.click(addon.tithePayment.panel.button)
        fixtures.setMoney(world, CARRIED - 5000)

        test.assertEqual("", page(addon).message.text)
        test.assertEqual("0g 50s 00c", row(addon, 1).amount)
        test.assertEqual("Guild Tithe", row(addon, 1).method)
        test.assertEqual("Lifetime given: 0g 50s 00c", page(addon).overall.text)
    end)

    test.test(profile .. " more than five guilds are summarized", function()
        local world, addon = login(profile)
        local index
        for index = 1, 7 do
            record(addon, { amount = 100 * index,
                guild = { name = "Guild " .. index, realm = "Camelot" } })
        end

        history(world)

        test.assertEqual("Guild 7 (Camelot): 0g 07s 00c", page(addon).guildLines[1].text)
        test.assertEqual("and 2 more guilds", page(addon).guildLines[6].text)
    end)

    test.test(profile .. " without settings tabs, history opens in its own window", function()
        local cases = { { withoutSubpages = true }, { settings = false } }
        local index
        for index = 1, #cases do
            local world, addon = login(profile, cases[index])
            record(addon, { amount = 4200 })
            test.assertEqual(nil, page(addon))

            history(world)

            local window = page(addon).window
            test.assertTrue(window ~= nil, "case " .. index)
            test.assertTrue(window.shown, "case " .. index)
            test.assertEqual("0g 42s 00c", row(addon, 1).amount)
            test.assertEqual("Lifetime given: 0g 42s 00c", page(addon).overall.text)
        end
    end)
end

local profileIndex
for profileIndex = 1, #fixtures.PROFILES do
    registerProfileTests(fixtures.PROFILES[profileIndex])
end

test.test("history reports an unreadable ledger instead of an empty one", function()
    local addon = test.newAddon(
        "Core/Identity.lua",
        "Core/MoneyFormatter.lua",
        "Core/Persistence.lua",
        "Core/DonationLedger.lua",
        "Core/HistoryController.lua"
    )
    local ledger = addon.DonationLedger.Create(function()
        return nil
    end)
    local controller = addon.HistoryController.Create({
        FormatDate = function()
            return nil
        end,
    }, ledger, addon.MoneyFormatter)

    local view = controller:View()

    test.assertContains(view.message, "unavailable")
    test.assertEqual(0, #view.rows)
end)

test.test("method labels group add-on deposits and keep manual ones distinct", function()
    local addon = test.newAddon("Core/HistoryController.lua")
    test.assertEqual("Guild Tithe", addon.HistoryController.MethodLabel("automatic"))
    test.assertEqual("Guild Tithe", addon.HistoryController.MethodLabel("button"))
    test.assertEqual("Manual", addon.HistoryController.MethodLabel("manual"))
end)
