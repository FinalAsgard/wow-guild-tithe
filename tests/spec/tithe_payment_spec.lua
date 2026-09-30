local test = require("tests.test_helper")
local fixtures = require("tests.client_fixtures")

local CARRIED = 100000 -- 10g

local function character(world)
    return world.environment.AsgardsGuildTitheDB.characters["jaina-camelot"]
end

-- Logs in with `owed` copper outstanding (and 40 hundredths carried over).
local function newWorld(profile, owed, options)
    options = options or {}
    local world = fixtures.newEnvironment(profile, {
        inGuild = options.inGuild,
        money = options.money or CARRIED,
    })
    -- Hooks let Blizzard-window deposits and withdrawals be observed.
    fixtures.installTransferCalls(world, {})
    local addon = fixtures.login(world)
    character(world).outstandingCopper = owed
    character(world).fractionalRemainder = 40
    -- Button payments unless a test asks for automatic deposit.
    character(world).autoDeposit = options.autoDeposit == true
    return world, addon
end

local function panel(addon)
    return addon.tithePayment.panel
end

-- Opens the guild bank and lets the automatic-deposit delay pass.
local function openBank(world)
    fixtures.fire(world, "GUILDBANKFRAME_OPENED")
    fixtures.advance(world, 1)
end

local function lastMessage(world)
    return world.messages[#world.messages]
end

local function database(world)
    return world.environment.AsgardsGuildTitheDB
end

-- Logs in against saved data, collecting completed donations from the start
-- the way a history listener registered at composition time would.
local function loginWithDonations(profile, options)
    local world = fixtures.newEnvironment(profile, options)
    local addon = fixtures.loadAddon(world)
    local donations = {}
    addon.tithePayment:OnDonation(function(donation)
        table.insert(donations, donation)
    end)
    fixtures.fire(world, "ADDON_LOADED", "AsgardsGuildTithe")
    world.playerReady = true
    fixtures.fire(world, "PLAYER_LOGIN")
    return world, addon, donations
end

-- Starts a payment of `owed`, then reloads with carried money `after`.
local function reloadDuringPayment(profile, owed, after)
    local world, addon = newWorld(profile, owed)
    openBank(world)
    fixtures.click(panel(addon).button)
    return loginWithDonations(profile, {
        database = fixtures.snapshot(database(world)),
        money = after,
    })
end

local function registerProfileTests(profile)
    test.test(profile .. " the guild bank offers the full tithe with recipient and remainder", function()
        local world, addon = newWorld(profile, 5000)

        openBank(world)

        test.assertTrue(panel(addon):IsShown())
        test.assertEqual(
            "Pay to Knights of Camelot\nTithe: 0g 50s 00c",
            panel(addon).body.text
        )
        test.assertTrue(panel(addon).button.shown)
    end)

    test.test(profile .. " the panel sits beside a guild bank window that loads after login", function()
        local world, addon = newWorld(profile, 5000)
        local frame = panel(addon).frame
        test.assertEqual("DIALOG", frame.strata)

        -- The game loads its guild bank window on demand, after login.
        local bank = world.environment.CreateFrame("Frame")
        world.environment.GuildBankFrame = bank
        openBank(world)

        test.assertEqual(bank, frame.parent)
        test.assertEqual("TOPLEFT", frame.point[1])
        test.assertEqual(bank, frame.point[2])
        test.assertEqual("TOPRIGHT", frame.point[3])
        test.assertEqual("DIALOG", frame.strata)
        test.assertTrue(panel(addon):IsShown())
    end)

    -- Loads a guild bank window whose Withdraw button is found by `naming`.
    local function loadBankWindow(world, naming)
        local bank = world.environment.CreateFrame("Frame")
        local withdraw = world.environment.CreateFrame("Button")
        if naming == "global" then
            world.environment.GuildBankFrameWithdrawButton = withdraw
        else
            bank.WithdrawButton = withdraw
        end
        world.environment.GuildBankFrame = bank
        local tooltip = { lines = {} }
        function tooltip:SetOwner(owner)
            self.owner = owner
        end
        function tooltip:SetText(text)
            self.lines = { text }
        end
        function tooltip:AddLine(text)
            table.insert(self.lines, text)
        end
        function tooltip:Show()
            self.shown = true
        end
        function tooltip:Hide()
            self.shown = false
        end
        world.environment.GameTooltip = tooltip
        return withdraw, tooltip
    end

    test.test(profile .. " the Give Tithe button sits left of the bank's Withdraw button", function()
        local namings = { "parentKey", "global" }
        local index
        for index = 1, #namings do
            local world, addon = newWorld(profile, 5000)
            local withdraw, tooltip = loadBankWindow(world, namings[index])

            openBank(world)
            local inline = panel(addon).inlineButton

            test.assertTrue(inline.shown, namings[index])
            test.assertFalse(panel(addon).frame.shown, namings[index])
            test.assertTrue(panel(addon):IsShown(), namings[index])
            test.assertEqual("Give Tithe", inline.text)
            test.assertTrue(inline.enabled)
            test.assertEqual("RIGHT", inline.point[1])
            test.assertEqual(withdraw, inline.point[2])
            test.assertEqual("LEFT", inline.point[3])

            inline.scripts.OnEnter(inline)
            test.assertTrue(tooltip.shown)
            test.assertEqual("Asgard's Guild Tithe", tooltip.lines[1])
            test.assertEqual("Pay to Knights of Camelot", tooltip.lines[2])
            test.assertEqual("Tithe: 0g 50s 00c", tooltip.lines[3])
            test.assertEqual(nil, tooltip.lines[4])
            inline.scripts.OnLeave(inline)
            test.assertFalse(tooltip.shown)

            fixtures.click(inline)
            test.assertEqual(1, #world.deposits)
            test.assertEqual("Depositing...", inline.text)
            test.assertFalse(inline.enabled)
            fixtures.click(inline)
            test.assertEqual(1, #world.deposits)

            fixtures.setMoney(world, CARRIED - 5000)
            test.assertEqual(0, character(world).outstandingCopper)
            test.assertTrue(inline.shown)
            test.assertEqual("Give Tithe", inline.text)
            test.assertFalse(inline.enabled)
            fixtures.click(inline)
            test.assertEqual(1, #world.deposits)
        end
    end)

    test.test(profile .. " with nothing to give the button stays, disabled, and says why", function()
        local cases = {
            { owed = 0, text = "no tithe is owed" },
            { owed = 5000, money = 0, text = "you carry no gold" },
        }
        local index
        for index = 1, #cases do
            local case = cases[index]
            local world, addon = newWorld(profile, case.owed, {
                autoDeposit = true,
                money = case.money,
            })
            local _, tooltip = loadBankWindow(world)

            openBank(world)
            local inline = panel(addon).inlineButton

            test.assertTrue(inline.shown, "case " .. index)
            test.assertEqual("Give Tithe", inline.text)
            test.assertFalse(inline.enabled, "case " .. index)
            test.assertTrue(inline.motionWhileDisabled, "case " .. index)
            test.assertEqual(0, #world.deposits)
            inline.scripts.OnEnter(inline)
            test.assertContains(tooltip.lines[2], case.text)
        end
    end)

    test.test(profile .. " a partial tithe's tooltip shows what will still be owed", function()
        local world, addon = newWorld(profile, 5000, { money = 3000 })
        local _, tooltip = loadBankWindow(world)
        openBank(world)
        local inline = panel(addon).inlineButton

        inline.scripts.OnEnter(inline)

        test.assertEqual("Tithe: 0g 30s 00c", tooltip.lines[3])
        test.assertEqual("Still owed after: 0g 20s 00c", tooltip.lines[4])
    end)

    test.test(profile .. " the button appears when the bank window loads after the open event", function()
        local world, addon = newWorld(profile, 5000)

        fixtures.fire(world, "GUILDBANKFRAME_OPENED")
        test.assertTrue(panel(addon).frame.shown)
        loadBankWindow(world)
        fixtures.advance(world, 0.2)

        test.assertTrue(panel(addon).inlineButton.shown)
        test.assertFalse(panel(addon).frame.shown)
        test.assertEqual("Give Tithe", panel(addon).inlineButton.text)
    end)

    test.test(profile .. " a slow-loading bank window still gets the button a second later", function()
        local world, addon = newWorld(profile, 5000)

        fixtures.fire(world, "GUILDBANKFRAME_OPENED")
        fixtures.advance(world, 0.5)
        loadBankWindow(world)
        fixtures.advance(world, 0.5)

        test.assertTrue(panel(addon).inlineButton.shown)
        test.assertFalse(panel(addon).frame.shown)
    end)

    test.test(profile .. " the Give Tithe button hides when the bank closes", function()
        local world, addon = newWorld(profile, 5000)
        loadBankWindow(world)
        openBank(world)
        local inline = panel(addon).inlineButton

        fixtures.fire(world, "GUILDBANKFRAME_CLOSED")
        fixtures.click(inline)

        test.assertFalse(inline.shown)
        test.assertEqual(0, #world.deposits)
    end)

    test.test(profile .. " a confirmed deposit clears the debt and keeps the remainder", function()
        local world, addon = newWorld(profile, 5000)
        openBank(world)

        fixtures.click(panel(addon).button)
        test.assertEqual(1, #world.deposits)
        test.assertEqual(5000, world.deposits[1])
        test.assertEqual(5000, character(world).outstandingCopper)

        fixtures.setMoney(world, CARRIED - 5000)

        test.assertEqual(0, character(world).outstandingCopper)
        test.assertEqual(40, character(world).fractionalRemainder)
        test.assertEqual(
            "Asgard's Guild Tithe: deposited 0g 50s 00c to Knights of Camelot. Still owed: 0g 00s 00c.",
            lastMessage(world)
        )
        test.assertFalse(panel(addon):IsShown())
    end)

    test.test(profile .. " carrying less than owed offers and records a partial payment", function()
        local world, addon = newWorld(profile, 5000, { money = 3000 })
        openBank(world)

        test.assertContains(panel(addon).body.text, "Tithe: 0g 30s 00c")
        test.assertContains(panel(addon).body.text, "Still owed after: 0g 20s 00c")
        fixtures.click(panel(addon).button)
        fixtures.setMoney(world, 0)

        test.assertEqual(3000, world.deposits[1])
        test.assertEqual(2000, character(world).outstandingCopper)
        test.assertContains(lastMessage(world), "Still owed: 0g 20s 00c.")
    end)

    test.test(profile .. " nothing is offered with no debt, no money, or no guild", function()
        local cases = {
            { owed = 0 },
            { owed = 5000, money = 0 },
            { owed = 5000, inGuild = false },
        }
        local index
        for index = 1, #cases do
            local case = cases[index]
            local world, addon = newWorld(profile, case.owed, {
                inGuild = case.inGuild,
                money = case.money,
            })
            openBank(world)
            test.assertFalse(panel(addon):IsShown(), "case " .. index)
            test.assertEqual(0, #world.deposits)
        end
    end)

    test.test(profile .. " the guild bank opened through the interaction manager is recognized", function()
        local world, addon = newWorld(profile, 5000)

        fixtures.fire(world, "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 8)
        test.assertFalse(panel(addon):IsShown())

        fixtures.fire(world, "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 10)
        test.assertTrue(panel(addon):IsShown())
        fixtures.fire(world, "PLAYER_INTERACTION_MANAGER_FRAME_HIDE", 10)
        test.assertFalse(panel(addon):IsShown())
    end)

    test.test(profile .. " only an exact money drop confirms the deposit", function()
        local world, addon = newWorld(profile, 5000)
        openBank(world)
        fixtures.click(panel(addon).button)

        fixtures.setMoney(world, CARRIED - 200)
        test.assertEqual(5000, character(world).outstandingCopper)

        fixtures.setMoney(world, CARRIED - 5200)
        test.assertEqual(0, character(world).outstandingCopper)
    end)

    test.test(profile .. " an unconfirmed deposit times out and leaves the debt", function()
        local world, addon = newWorld(profile, 5000)
        openBank(world)
        fixtures.click(panel(addon).button)

        fixtures.advance(world, 11)

        test.assertEqual(5000, character(world).outstandingCopper)
        test.assertContains(lastMessage(world), "not confirmed")
        test.assertContains(lastMessage(world), "unchanged")
        test.assertTrue(panel(addon).button.shown)
    end)

    test.test(profile .. " a failed deposit call leaves the debt and offers a retry", function()
        local world, addon = newWorld(profile, 5000)
        world.depositError = "not allowed"
        openBank(world)

        fixtures.click(panel(addon).button)

        test.assertEqual(5000, character(world).outstandingCopper)
        test.assertContains(lastMessage(world), "deposit failed")
        test.assertTrue(panel(addon):IsShown())
        test.assertTrue(panel(addon).button.shown)
    end)

    test.test(profile .. " closing the guild bank discards the offer", function()
        local world, addon = newWorld(profile, 5000)
        openBank(world)
        local button = panel(addon).button

        fixtures.fire(world, "GUILDBANKFRAME_CLOSED")
        fixtures.click(button)

        test.assertFalse(panel(addon):IsShown())
        test.assertEqual(0, #world.deposits)
        test.assertEqual(5000, character(world).outstandingCopper)
    end)

    test.test(profile .. " clicking twice pays once", function()
        local world, addon = newWorld(profile, 5000)
        openBank(world)
        local onClick = panel(addon).button.scripts.OnClick

        onClick()
        onClick()

        test.assertEqual(1, #world.deposits)
    end)

    test.test(profile .. " payment messages print even with tithe updates off", function()
        local world, addon = newWorld(profile, 5000)
        world.settings.bindings.AsgardsGuildTithe_ChatFeedback.setValue(false)
        openBank(world)

        fixtures.click(panel(addon).button)
        fixtures.setMoney(world, CARRIED - 5000)

        test.assertContains(lastMessage(world), "deposited 0g 50s 00c")
    end)

    test.test(profile .. " a payment is saved as a pending intent until it resolves", function()
        local world, addon = newWorld(profile, 5000)
        openBank(world)
        fixtures.click(panel(addon).button)

        local intent = character(world).pendingPayment
        test.assertEqual("jaina-camelot:1790001001:1", intent.operationId)
        test.assertEqual(5000, intent.amount)
        test.assertEqual("button", intent.method)
        test.assertEqual("jaina-camelot", intent.character.key)
        test.assertEqual("Jaina", intent.character.name)
        test.assertEqual("Camelot", intent.character.realm)
        test.assertEqual("Knights of Camelot", intent.guild.name)
        test.assertEqual("Camelot", intent.guild.realm)
        test.assertEqual(CARRIED, intent.moneyBefore)
        test.assertEqual(1790001001, intent.createdAt)
        test.assertEqual("pending", intent.status)

        fixtures.setMoney(world, CARRIED - 5000)

        test.assertEqual(nil, character(world).pendingPayment)
        test.assertEqual(intent.operationId, character(world).resolvedPayments[1])
    end)

    test.test(profile .. " replayed money signals confirm a payment once", function()
        local world, addon = newWorld(profile, 5000)
        local donations = {}
        addon.tithePayment:OnDonation(function(donation)
            table.insert(donations, donation)
        end)
        openBank(world)
        fixtures.click(panel(addon).button)

        fixtures.setMoney(world, CARRIED - 5000)
        fixtures.fire(world, "PLAYER_MONEY")
        fixtures.setMoney(world, CARRIED - 10000)
        fixtures.advance(world, 30)

        test.assertEqual(1, #donations)
        test.assertEqual(1, #character(world).resolvedPayments)
        test.assertEqual(0, character(world).outstandingCopper)
    end)

    test.test(profile .. " the donation event carries the payment and follows the saved balance", function()
        local world, addon = newWorld(profile, 8000)
        world.guildClubId = 42
        local savedBalance
        local donations = {}
        addon.tithePayment:OnDonation(function(donation)
            savedBalance = character(world).outstandingCopper
            table.insert(donations, donation)
        end)
        addon.tithePayment:OnDonation(function()
            error("a broken listener")
        end)
        openBank(world)
        fixtures.click(panel(addon).button)
        fixtures.advance(world, 3)
        fixtures.setMoney(world, CARRIED - 8000)

        test.assertEqual(0, savedBalance)
        local donation = donations[1]
        test.assertEqual("jaina-camelot:1790001001:1", donation.operationId)
        test.assertEqual(1790001004, donation.timestamp)
        test.assertEqual(8000, donation.amount)
        test.assertEqual("button", donation.method)
        test.assertEqual("jaina-camelot", donation.character.key)
        test.assertEqual("Jaina", donation.character.name)
        test.assertEqual("Camelot", donation.character.realm)
        test.assertEqual("42", donation.guild.id)
        test.assertEqual("Knights of Camelot", donation.guild.name)
        test.assertEqual("Camelot", donation.guild.realm)
        test.assertContains(lastMessage(world), "deposited 0g 80s 00c")
    end)

    test.test(profile .. " a deposit that lands before a reload is confirmed once after it", function()
        local world, addon, donations = reloadDuringPayment(profile, 5000, CARRIED - 5000)

        test.assertEqual(0, character(world).outstandingCopper)
        test.assertEqual(40, character(world).fractionalRemainder)
        test.assertEqual(1, #donations)
        test.assertEqual(nil, character(world).pendingPayment)

        local again, _, againDonations = loginWithDonations(profile, {
            database = fixtures.snapshot(database(world)),
            money = CARRIED - 5000,
        })
        test.assertEqual(0, character(again).outstandingCopper)
        test.assertEqual(0, #againDonations)
    end)

    test.test(profile .. " a reloaded payment waits for the guild to load before crediting it", function()
        local world, addon = newWorld(profile, 5000)
        openBank(world)
        fixtures.click(panel(addon).button)

        local reloaded, _, donations = loginWithDonations(profile, {
            database = fixtures.snapshot(database(world)),
            inGuild = false,
            money = CARRIED - 5000,
        })
        test.assertEqual(5000, character(reloaded).outstandingCopper)
        test.assertTrue(character(reloaded).pendingPayment ~= nil)

        fixtures.advance(reloaded, 12)
        test.assertTrue(character(reloaded).pendingPayment ~= nil)
        reloaded.inGuild = true
        fixtures.advance(reloaded, 2)

        test.assertEqual(0, character(reloaded).outstandingCopper)
        test.assertEqual(1, #donations)
    end)

    test.test(profile .. " a reloaded payment is left unresolved if the guild never loads", function()
        local world, addon = newWorld(profile, 5000)
        openBank(world)
        fixtures.click(panel(addon).button)

        local reloaded, _, donations = loginWithDonations(profile, {
            database = fixtures.snapshot(database(world)),
            inGuild = false,
            money = CARRIED - 5000,
        })
        fixtures.advance(reloaded, 29)
        test.assertTrue(character(reloaded).pendingPayment ~= nil)
        fixtures.advance(reloaded, 2)

        test.assertEqual(nil, character(reloaded).pendingPayment)
        test.assertEqual(5000, character(reloaded).outstandingCopper)
        test.assertEqual(0, #donations)
        test.assertContains(reloaded.messages[#reloaded.messages], "guild changed")
    end)

    test.test(profile .. " a payment still in flight at a reload waits for its deposit", function()
        local world, addon, donations = reloadDuringPayment(profile, 5000, CARRIED)

        test.assertEqual(5000, character(world).outstandingCopper)
        test.assertTrue(character(world).pendingPayment ~= nil)
        fixtures.setMoney(world, CARRIED - 5000)

        test.assertEqual(0, character(world).outstandingCopper)
        test.assertEqual(1, #donations)
    end)

    test.test(profile .. " a payment still unconfirmed after a reload expires safely", function()
        local world, addon, donations = reloadDuringPayment(profile, 5000, CARRIED - 700)

        fixtures.advance(world, 11)

        test.assertEqual(5000, character(world).outstandingCopper)
        test.assertEqual(nil, character(world).pendingPayment)
        test.assertEqual(0, #donations)
        test.assertContains(lastMessage(world), "not confirmed")
        openBank(world)
        test.assertTrue(panel(addon).button.shown)
    end)

    test.test(profile .. " expired and failed payments leave no pending intent", function()
        local world, addon = newWorld(profile, 5000)
        openBank(world)
        fixtures.click(panel(addon).button)
        fixtures.advance(world, 11)
        test.assertEqual(nil, character(world).pendingPayment)
        test.assertEqual(1, #character(world).resolvedPayments)

        world.depositError = "not allowed"
        fixtures.click(panel(addon).button)
        test.assertEqual(nil, character(world).pendingPayment)
        test.assertEqual(2, #character(world).resolvedPayments)
        test.assertEqual(5000, character(world).outstandingCopper)
    end)

    test.test(profile .. " leaving or switching guilds mid-payment never credits a guild", function()
        local changes = {
            function(world)
                world.guildName = "Horde Traders"
            end,
            function(world)
                world.inGuild = false
            end,
            function(world)
                world.guildRealm = "Avalon"
            end,
        }
        local index
        for index = 1, #changes do
            local world, addon = newWorld(profile, 5000)
            local donations = {}
            addon.tithePayment:OnDonation(function(donation)
                table.insert(donations, donation)
            end)
            openBank(world)
            fixtures.click(panel(addon).button)

            changes[index](world)
            fixtures.setMoney(world, CARRIED - 5000)
            -- A missing guild is waited on before the payment is given up.
            fixtures.advance(world, 31)

            test.assertEqual(5000, character(world).outstandingCopper, "change " .. index)
            test.assertEqual(0, #donations, "change " .. index)
            test.assertEqual(nil, character(world).pendingPayment, "change " .. index)
            test.assertContains(lastMessage(world), "guild changed")
        end
    end)

    test.test(profile .. " a stable guild id decides the guild over its name", function()
        local renamed, renamedAddon = newWorld(profile, 5000)
        renamed.guildClubId = "42"
        openBank(renamed)
        fixtures.click(panel(renamedAddon).button)
        renamed.guildName = "Knights of Avalon"
        fixtures.setMoney(renamed, CARRIED - 5000)
        test.assertEqual(0, character(renamed).outstandingCopper)

        local other, otherAddon = newWorld(profile, 5000)
        other.guildClubId = "42"
        openBank(other)
        fixtures.click(panel(otherAddon).button)
        other.guildClubId = "77"
        fixtures.setMoney(other, CARRIED - 5000)
        test.assertEqual(5000, character(other).outstandingCopper)
    end)

    test.test(profile .. " the whole balance is offered to the guild the character is in now", function()
        local world, addon = newWorld(profile, 5000)
        world.guildName = "Horde Traders"

        openBank(world)

        test.assertContains(panel(addon).body.text, "Pay to Horde Traders")
        test.assertContains(panel(addon).body.text, "Tithe: 0g 50s 00c")
    end)

    test.test(profile .. " with auto-deposit on, opening the bank pays without a click", function()
        local world, addon = newWorld(profile, 5000, { autoDeposit = true })
        local donations = {}
        addon.tithePayment:OnDonation(function(donation)
            table.insert(donations, donation)
        end)

        openBank(world)
        test.assertEqual(1, #world.deposits)
        test.assertEqual(5000, world.deposits[1])
        test.assertEqual("automatic", character(world).pendingPayment.method)
        test.assertEqual(5000, character(world).outstandingCopper)

        fixtures.setMoney(world, CARRIED - 5000)

        test.assertEqual(0, character(world).outstandingCopper)
        test.assertEqual("automatic", donations[1].method)
        test.assertContains(lastMessage(world), "deposited 0g 50s 00c")
    end)

    test.test(profile .. " the automatic deposit waits a moment after the bank opens", function()
        local world, addon = newWorld(profile, 5000, { autoDeposit = true })

        fixtures.fire(world, "GUILDBANKFRAME_OPENED")
        test.assertEqual(0, #world.deposits)
        test.assertTrue(panel(addon).button.shown)

        fixtures.advance(world, 1)
        test.assertEqual(1, #world.deposits)
    end)

    test.test(profile .. " closing the bank or clicking first cancels the automatic deposit", function()
        local closed = newWorld(profile, 5000, { autoDeposit = true })
        fixtures.fire(closed, "GUILDBANKFRAME_OPENED")
        fixtures.fire(closed, "GUILDBANKFRAME_CLOSED")
        fixtures.fire(closed, "GUILDBANKFRAME_OPENED")
        fixtures.fire(closed, "GUILDBANKFRAME_CLOSED")
        fixtures.advance(closed, 5)
        test.assertEqual(0, #closed.deposits)

        local clicked, clickedAddon = newWorld(profile, 5000, { autoDeposit = true })
        fixtures.fire(clicked, "GUILDBANKFRAME_OPENED")
        fixtures.click(panel(clickedAddon).button)
        fixtures.advance(clicked, 1)
        test.assertEqual(1, #clicked.deposits)
        test.assertEqual("button", character(clicked).pendingPayment.method)
    end)

    test.test(profile .. " with auto-deposit off, only the button pays", function()
        local world, addon = newWorld(profile, 5000, { autoDeposit = true })
        world.settings.bindings.AsgardsGuildTithe_AutoDeposit.setValue(false)
        local donations = {}
        addon.tithePayment:OnDonation(function(donation)
            table.insert(donations, donation)
        end)

        openBank(world)
        test.assertEqual(0, #world.deposits)
        test.assertTrue(panel(addon).button.shown)
        test.assertContains(panel(addon).body.text, "Tithe: 0g 50s 00c")

        fixtures.click(panel(addon).button)
        fixtures.setMoney(world, CARRIED - 5000)
        test.assertEqual("button", donations[1].method)
    end)

    test.test(profile .. " a failed automatic deposit falls back to the button", function()
        local world, addon = newWorld(profile, 5000, { autoDeposit = true })
        world.depositError = "not now"

        openBank(world)

        test.assertEqual(5000, character(world).outstandingCopper)
        test.assertContains(lastMessage(world), "deposit failed")
        test.assertTrue(panel(addon).button.shown)
        test.assertEqual(nil, character(world).pendingPayment)
    end)

    test.test(profile .. " an unconfirmed automatic deposit falls back to the button", function()
        local world, addon = newWorld(profile, 5000, { autoDeposit = true })
        openBank(world)

        fixtures.advance(world, 11)

        test.assertEqual(5000, character(world).outstandingCopper)
        test.assertContains(lastMessage(world), "not confirmed")
        test.assertTrue(panel(addon).button.shown)
    end)

    test.test(profile .. " a blocked automatic deposit falls back and is not retried this session", function()
        local events = { "ADDON_ACTION_FORBIDDEN", "ADDON_ACTION_BLOCKED" }
        local index
        for index = 1, #events do
            local world, addon = newWorld(profile, 5000, { autoDeposit = true })
            local deposit = world.environment.DepositGuildBankMoney
            world.environment.DepositGuildBankMoney = function(copper)
                deposit(copper)
                if #world.deposits == 1 then
                    fixtures.fire(world, events[index], "AsgardsGuildTithe",
                        "DepositGuildBankMoney()")
                end
            end

            openBank(world)
            test.assertEqual(5000, character(world).outstandingCopper, events[index])
            test.assertEqual(nil, character(world).pendingPayment, events[index])
            test.assertContains(lastMessage(world), "blocked the automatic deposit")
            test.assertTrue(panel(addon).button.shown, events[index])

            fixtures.fire(world, "GUILDBANKFRAME_CLOSED")
            openBank(world)
            test.assertEqual(1, #world.deposits, events[index])
            test.assertTrue(panel(addon).button.shown, events[index])

            fixtures.click(panel(addon).button)
            test.assertEqual(2, #world.deposits, events[index])
            test.assertEqual("button", character(world).pendingPayment.method)
            fixtures.setMoney(world, CARRIED - 5000)
            test.assertEqual(0, character(world).outstandingCopper, events[index])
        end
    end)

    test.test(profile .. " a blocked action from another add-on changes nothing", function()
        local world, addon = newWorld(profile, 5000, { autoDeposit = true })
        openBank(world)

        fixtures.fire(world, "ADDON_ACTION_BLOCKED", "SomeOtherAddon", "DepositGuildBankMoney()")
        fixtures.fire(world, "ADDON_ACTION_BLOCKED", "AsgardsGuildTithe", "CastSpellByName()")
        fixtures.setMoney(world, CARRIED - 5000)

        test.assertEqual(0, character(world).outstandingCopper)
    end)

    test.test(profile .. " an automatic deposit and a click never both pay", function()
        local world, addon = newWorld(profile, 5000, { autoDeposit = true })
        openBank(world)

        test.assertFalse(addon.tithePayment:Pay("button"))
        fixtures.click(panel(addon).button)

        test.assertEqual(1, #world.deposits)
        test.assertEqual("automatic", character(world).pendingPayment.method)
    end)

    test.test(profile .. " auto-deposit offers nothing when nothing is owed", function()
        local world, addon = newWorld(profile, 0, { autoDeposit = true })

        openBank(world)

        test.assertEqual(0, #world.deposits)
        test.assertFalse(panel(addon):IsShown())
    end)

    local function manualWorld(owed, options)
        local world, addon = newWorld(profile, owed, options)
        local donations = {}
        addon.tithePayment:OnDonation(function(donation)
            table.insert(donations, donation)
        end)
        return world, addon, donations
    end

    -- A deposit typed into the game's own guild-bank money window.
    local function depositByHand(world, copper)
        world.environment.DepositGuildBankMoney(copper)
    end

    test.test(profile .. " manual deposits reduce the debt but record the full amount", function()
        local cases = {
            { owed = 5000, deposit = 2000, remaining = 3000 },
            { owed = 5000, deposit = 5000, remaining = 0 },
            { owed = 5000, deposit = 8000, remaining = 0 },
            { owed = 0, deposit = 3000, remaining = 0 },
        }
        local index
        for index = 1, #cases do
            local case = cases[index]
            local world, addon, donations = manualWorld(case.owed)
            openBank(world)

            depositByHand(world, case.deposit)
            test.assertEqual("manual", character(world).pendingPayment.method, "case " .. index)
            fixtures.setMoney(world, CARRIED - case.deposit)

            test.assertEqual(case.remaining, character(world).outstandingCopper, "case " .. index)
            test.assertEqual(40, character(world).fractionalRemainder, "case " .. index)
            test.assertEqual(1, #donations, "case " .. index)
            test.assertEqual(case.deposit, donations[1].amount, "case " .. index)
            test.assertEqual("manual", donations[1].method, "case " .. index)
            test.assertEqual("Knights of Camelot", donations[1].guild.name, "case " .. index)
            test.assertContains(lastMessage(world), "deposited " .. addon.MoneyFormatter.Format(case.deposit))
        end
    end)

    test.test(profile .. " withdrawals, spending, and unmatched drops are never credited", function()
        local world, addon, donations = manualWorld(5000)
        openBank(world)

        world.environment.WithdrawGuildBankMoney(3000)
        fixtures.setMoney(world, CARRIED + 3000)
        fixtures.setMoney(world, CARRIED + 1000)
        test.assertEqual(nil, character(world).pendingPayment)

        depositByHand(world, 2000)
        fixtures.setMoney(world, CARRIED - 500)
        fixtures.advance(world, 11)

        test.assertEqual(5000, character(world).outstandingCopper)
        test.assertEqual(0, #donations)
        test.assertEqual(nil, character(world).pendingPayment)
        test.assertContains(lastMessage(world), "was not counted toward your tithe")
    end)

    test.test(profile .. " a deposit call outside a guild-bank session is ignored", function()
        local world, addon, donations = manualWorld(5000)

        depositByHand(world, 2000)
        fixtures.setMoney(world, CARRIED - 2000)

        test.assertEqual(5000, character(world).outstandingCopper)
        test.assertEqual(0, #donations)
        test.assertEqual(0, #character(world).resolvedPayments)
    end)

    test.test(profile .. " duplicate signals credit a manual deposit once", function()
        local world, addon, donations = manualWorld(5000)
        openBank(world)

        depositByHand(world, 2000)
        fixtures.setMoney(world, CARRIED - 2000)
        fixtures.fire(world, "PLAYER_MONEY")
        fixtures.setMoney(world, CARRIED - 4000)
        fixtures.advance(world, 30)

        test.assertEqual(3000, character(world).outstandingCopper)
        test.assertEqual(1, #donations)
        test.assertEqual(1, #character(world).resolvedPayments)
    end)

    test.test(profile .. " each manual deposit gets its own operation id", function()
        local world, addon, donations = manualWorld(5000)
        openBank(world)

        depositByHand(world, 1000)
        fixtures.setMoney(world, CARRIED - 1000)
        depositByHand(world, 1000)
        fixtures.setMoney(world, CARRIED - 2000)

        test.assertEqual(2, #donations)
        test.assertTrue(donations[1].operationId ~= donations[2].operationId)
        test.assertEqual(3000, character(world).outstandingCopper)
    end)

    test.test(profile .. " button and automatic deposits are never also counted as manual", function()
        local world, addon, donations = manualWorld(5000)
        openBank(world)
        fixtures.click(panel(addon).button)
        fixtures.setMoney(world, CARRIED - 5000)

        local auto, _, autoDonations = manualWorld(5000, { autoDeposit = true })
        openBank(auto)
        fixtures.setMoney(auto, CARRIED - 5000)

        test.assertEqual(1, #donations)
        test.assertEqual("button", donations[1].method)
        test.assertEqual(1, #autoDonations)
        test.assertEqual("automatic", autoDonations[1].method)
        test.assertEqual(1, #character(auto).resolvedPayments)
    end)

    test.test(profile .. " a manual deposit during an automatic one is not guessed at", function()
        local world, addon, donations = manualWorld(5000, { autoDeposit = true })
        openBank(world)

        depositByHand(world, 2000)
        fixtures.setMoney(world, CARRIED - 2000)
        test.assertEqual(5000, character(world).outstandingCopper)

        fixtures.setMoney(world, CARRIED - 7000)
        test.assertEqual(0, character(world).outstandingCopper)
        test.assertEqual(1, #donations)
        test.assertEqual("automatic", donations[1].method)
    end)

    test.test(profile .. " a manual deposit that lands before a reload is credited once", function()
        local world = newWorld(profile, 5000)
        openBank(world)
        depositByHand(world, 2000)

        local reloaded, _, donations = loginWithDonations(profile, {
            database = fixtures.snapshot(database(world)),
            money = CARRIED - 2000,
        })

        test.assertEqual(3000, character(reloaded).outstandingCopper)
        test.assertEqual(1, #donations)
        test.assertEqual("manual", donations[1].method)
    end)

    test.test(profile .. " a deposit is never counted as income", function()
        local world, addon = newWorld(profile, 5000)
        openBank(world)
        fixtures.click(panel(addon).button)
        fixtures.setMoney(world, CARRIED - 5000)

        test.assertEqual(1, #world.messages)
        test.assertContains(world.messages[1], "deposited")
    end)
end

local profileIndex
for profileIndex = 1, #fixtures.PROFILES do
    registerProfileTests(fixtures.PROFILES[profileIndex])
end

test.test("the proposed payment is the smaller of debt and carried money, never negative", function()
    local addon = test.newAddon("Core/MoneyFormatter.lua", "Core/TithePayment.lua")
    local propose = addon.TithePayment.Propose

    test.assertEqual(5000, propose(5000, 100000))
    test.assertEqual(3000, propose(5000, 3000))
    test.assertEqual(5000, propose(5000, 5000))
    test.assertEqual(0, propose(0, 100000))
    test.assertEqual(0, propose(5000, 0))
    test.assertEqual(0, propose(-5, 100))
    test.assertEqual(0, propose(nil, 100))
end)
