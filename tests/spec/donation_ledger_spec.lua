local test = require("tests.test_helper")
local fixtures = require("tests.client_fixtures")

local function loadLedgerModules()
    return test.newAddon(
        "Adapters/WoW.lua",
        "Core/Persistence.lua",
        "Core/CharacterState.lua",
        "Core/DonationLedger.lua"
    )
end

local function newEnvironment(name, database)
    return {
        AsgardsGuildTitheDB = database,
        UnitName = function()
            return name or "Jaina"
        end,
        GetRealmName = function()
            return "Camelot"
        end,
    }
end

-- A ledger over freshly loaded state for `environment`.
local function openLedger(addon, environment)
    local state = addon.CharacterState.Create(addon.Compatibility.Create(environment))
    test.assertTrue(state:Initialize())
    return addon.DonationLedger.Create(function()
        return state:GetDonationRecords()
    end), state
end

local sequence = 0
local function donation(overrides)
    sequence = sequence + 1
    local value = {
        operationId = "jaina-camelot:1790000000:" .. sequence,
        timestamp = 1790000000 + sequence,
        amount = 5000,
        method = "button",
        character = { key = "jaina-camelot", name = "Jaina", realm = "Camelot", stableId = "Player-7" },
        guild = { name = "Knights of Camelot", realm = "Camelot" },
    }
    local key, item
    for key, item in pairs(overrides or {}) do
        value[key] = item
    end
    return value
end

test.test("a completed donation is recorded once with all of its details", function()
    local addon = loadLedgerModules()
    local environment = newEnvironment()
    local ledger = openLedger(addon, environment)
    local given = donation({ guild = { id = "42", name = "Knights of Camelot", realm = "Camelot" } })

    local ok, entry, duplicate = ledger:Append(given)

    test.assertTrue(ok)
    test.assertFalse(duplicate)
    test.assertEqual(given.operationId, entry.operationId)
    local saved = environment.AsgardsGuildTitheDB.donations[1]
    test.assertEqual(given.operationId, saved.operationId)
    test.assertEqual(given.timestamp, saved.timestamp)
    test.assertEqual(5000, saved.amount)
    test.assertEqual("button", saved.method)
    test.assertEqual("jaina-camelot", saved.character.key)
    test.assertEqual("Jaina", saved.character.name)
    test.assertEqual("Camelot", saved.character.realm)
    test.assertEqual("Player-7", saved.character.stableId)
    test.assertEqual("42", saved.guild.id)
    test.assertEqual("Knights of Camelot", saved.guild.name)
    test.assertEqual("Camelot", saved.guild.realm)
    test.assertEqual(1, ledger:Count())
    test.assertEqual(5000, ledger:Totals().overall)
end)

test.test("invalid donations are rejected without writing anything", function()
    local addon = loadLedgerModules()
    local environment = newEnvironment()
    local ledger = openLedger(addon, environment)
    local cases = {
        donation({ operationId = "" }),
        donation({ amount = 0 }),
        donation({ amount = -5 }),
        donation({ amount = 12.5 }),
        donation({ timestamp = "yesterday" }),
        donation({ timestamp = -1 }),
        donation({ method = "wire" }),
        donation({ character = { name = "Jaina" } }),
        donation({ guild = { name = "Knights of Camelot" } }),
        donation({ guild = "Knights of Camelot" }),
        "not a donation",
    }
    local index
    for index = 1, #cases do
        local ok, reason = ledger:Append(cases[index])
        test.assertEqual(nil, ok, "case " .. index)
        test.assertContains(reason, "invalid")
    end
    test.assertEqual(0, #environment.AsgardsGuildTitheDB.donations)
    test.assertEqual(0, ledger:Totals().overall)
end)

test.test("an operation already recorded never counts twice, even after a reload", function()
    local addon = loadLedgerModules()
    local environment = newEnvironment()
    local ledger = openLedger(addon, environment)
    local given = donation()

    test.assertTrue(ledger:Append(given))
    local ok, entry, duplicate = ledger:Append(given)
    test.assertTrue(ok)
    test.assertTrue(duplicate)
    test.assertEqual(given.operationId, entry.operationId)

    local reloaded = openLedger(addon, environment)
    test.assertTrue(reloaded:Append(given))
    test.assertEqual(1, reloaded:Count())
    test.assertEqual(5000, reloaded:Totals().overall)
end)

test.test("guild totals keep distinct guilds apart and follow stable ids through renames", function()
    local addon = loadLedgerModules()
    local ledger = openLedger(addon, newEnvironment())

    -- Same guild name on two realms: two guilds.
    ledger:Append(donation({ amount = 100, guild = { name = "Knights", realm = "Camelot" } }))
    ledger:Append(donation({ amount = 200, guild = { name = "Knights", realm = "Avalon" } }))
    -- Fallback identity ignores case and realm spacing.
    ledger:Append(donation({ amount = 300, guild = { name = "KNIGHTS", realm = "Came lot" } }))
    -- One stable id through a rename: one guild, shown by its newest name.
    ledger:Append(donation({ amount = 1000, timestamp = 10, guild = { id = "7", name = "Old Name", realm = "Camelot" } }))
    ledger:Append(donation({ amount = 2000, timestamp = 20, guild = { id = "7", name = "New Name", realm = "Camelot" } }))
    -- Same name as the renamed guild but a different id: a different guild.
    ledger:Append(donation({ amount = 50, guild = { id = "8", name = "New Name", realm = "Camelot" } }))
    -- A second character counts toward the same account-wide totals.
    ledger:Append(donation({ amount = 5, character = { key = "thrall-camelot" },
        guild = { name = "Knights", realm = "Camelot" } }))

    local totals = ledger:Totals()
    test.assertEqual(4, #totals.guilds)
    test.assertEqual("New Name", totals.guilds[1].name)
    test.assertEqual(3000, totals.guilds[1].amount)
    test.assertEqual(405, totals.guilds[2].amount)
    test.assertEqual("Camelot", totals.guilds[2].realm)
    test.assertEqual(200, totals.guilds[3].amount)
    test.assertEqual("Avalon", totals.guilds[3].realm)
    test.assertEqual(50, totals.guilds[4].amount)

    local sum = 0
    local index
    for index = 1, #totals.guilds do
        sum = sum + totals.guilds[index].amount
    end
    test.assertEqual(3655, totals.overall)
    test.assertEqual(totals.overall, sum)
end)

test.test("entries come newest first with a stable order and paging", function()
    local addon = loadLedgerModules()
    local ledger = openLedger(addon, newEnvironment())
    ledger:Append(donation({ operationId = "b", timestamp = 50 }))
    ledger:Append(donation({ operationId = "a", timestamp = 90 }))
    ledger:Append(donation({ operationId = "c", timestamp = 50 }))
    ledger:Append(donation({ operationId = "d", timestamp = 10 }))

    local all = ledger:Entries()
    test.assertEqual("a", all[1].operationId)
    test.assertEqual("c", all[2].operationId)
    test.assertEqual("b", all[3].operationId)
    test.assertEqual("d", all[4].operationId)

    local page = ledger:Entries(1, 2)
    test.assertEqual(2, #page)
    test.assertEqual("c", page[1].operationId)
    test.assertEqual("b", page[2].operationId)
    test.assertEqual(0, #ledger:Entries(10, 5))

    -- Returned entries are copies; changing them never changes the ledger.
    all[1].amount = 1
    page[1].guild.name = "Changed"
    test.assertEqual(5000, ledger:Entries(0, 1)[1].amount)
    test.assertEqual("Knights of Camelot", ledger:Entries(1, 1)[1].guild.name)
end)

test.test("a large ledger keeps exact totals and quick queries", function()
    local addon = loadLedgerModules()
    local ledger = openLedger(addon, newEnvironment())
    local count = 5000
    local index
    for index = 1, count do
        ledger:Append(donation({
            operationId = "big:" .. index,
            timestamp = 1790000000 + (index * 7919) % count,
            amount = 99999999 + index,
        }))
    end

    local started = os.clock()
    local page = ledger:Entries(0, 20)
    local totals = ledger:Totals()
    local elapsed = os.clock() - started

    test.assertEqual(count, ledger:Count())
    test.assertEqual(20, #page)
    test.assertTrue(page[1].timestamp >= page[20].timestamp)
    test.assertEqual(count * 99999999 + count * (count + 1) / 2, totals.overall)
    test.assertTrue(elapsed < 1, "queries took " .. elapsed .. "s")
end)

test.test("append listeners hear each new donation once and cannot break the ledger", function()
    local addon = loadLedgerModules()
    local ledger = openLedger(addon, newEnvironment())
    local heard = {}
    ledger:OnAppend(function(entry)
        table.insert(heard, entry.operationId)
    end)
    ledger:OnAppend(function()
        error("a broken listener")
    end)
    local given = donation()

    test.assertTrue(ledger:Append(given))
    test.assertTrue(ledger:Append(given))

    test.assertEqual(1, #heard)
    test.assertEqual(given.operationId, heard[1])
    test.assertEqual(1, ledger:Count())
end)

test.test("the ledger is unavailable until character state is loaded", function()
    local addon = loadLedgerModules()
    local state = addon.CharacterState.Create(addon.Compatibility.Create(newEnvironment()))
    local ledger = addon.DonationLedger.Create(function()
        return state:GetDonationRecords()
    end)

    local ok, reason = ledger:Append(donation())

    test.assertEqual(nil, ok)
    test.assertContains(reason, "unavailable")
    test.assertEqual(0, ledger:Count())
    test.assertEqual(0, #ledger:Entries())
    test.assertEqual(0, ledger:Totals().overall)
end)

test.test("schema three gains an empty ledger and loads again unchanged", function()
    local addon = loadLedgerModules()
    local environment = newEnvironment("Jaina", {
        schemaVersion = 3,
        characters = {},
        quarantinedCharacters = {},
    })
    local store = addon.Persistence.Create(addon.Compatibility.Create(environment))

    local database, report = store:Load()

    test.assertEqual(4, database.schemaVersion)
    test.assertEqual("3 -> 4", report.migrations[1])
    test.assertEqual(0, #database.donations)
    test.assertEqual(0, #database.quarantinedDonations)

    local again, againReport = addon.Persistence.Create(addon.Compatibility.Create(environment)):Load()
    test.assertEqual(0, #againReport.migrations)
    test.assertEqual(0, #againReport.quarantinedDonations)
    test.assertEqual(0, #again.donations)
end)

test.test("unreadable ledger entries are set aside while valid ones stay", function()
    local addon = loadLedgerModules()
    local first = donation({ operationId = "keep-1", amount = 700 })
    local second = donation({ operationId = "keep-2", amount = 300 })
    local environment = newEnvironment("Jaina", {
        schemaVersion = 4,
        characters = {},
        quarantinedCharacters = {},
        donations = {
            first,
            donation({ operationId = "bad-amount", amount = -1 }),
            second,
            donation({ operationId = "keep-1", amount = 999 }),
            "garbage",
        },
        quarantinedDonations = {},
    })

    local ledger = openLedger(addon, environment)
    local database = environment.AsgardsGuildTitheDB

    test.assertEqual(2, ledger:Count())
    test.assertEqual(1000, ledger:Totals().overall)
    test.assertEqual(3, #database.quarantinedDonations)
    test.assertEqual("bad-amount", database.quarantinedDonations[1].record.operationId)
    test.assertContains(database.quarantinedDonations[2].reason, "repeated")
    test.assertEqual(999, database.quarantinedDonations[2].record.amount)
    test.assertEqual("garbage", database.quarantinedDonations[3].record)

    local reloaded = openLedger(addon, environment)
    test.assertEqual(2, reloaded:Count())
    test.assertEqual(3, #environment.AsgardsGuildTitheDB.quarantinedDonations)
end)

test.test("a ledger that is not a list is set aside and replaced with an empty one", function()
    local addon = loadLedgerModules()
    local environment = newEnvironment("Jaina", {
        schemaVersion = 4,
        characters = {},
        quarantinedCharacters = {},
        donations = "corrupted",
    })

    local ledger = openLedger(addon, environment)

    test.assertEqual(0, ledger:Count())
    test.assertEqual("corrupted", environment.AsgardsGuildTitheDB.quarantinedDonations[1].record)
    test.assertTrue(ledger:Append(donation()))
    test.assertEqual(1, ledger:Count())
end)

-- End to end through the add-on as a player would use it.
local CARRIED = 100000

local function character(world)
    return world.environment.AsgardsGuildTitheDB.characters[string.lower(world.playerName) .. "-camelot"]
end

local function newWorld(profile, owed, options)
    options = options or {}
    local world = fixtures.newEnvironment(profile, {
        database = options.database,
        money = options.money or CARRIED,
        playerName = options.playerName,
    })
    fixtures.installTransferCalls(world, {})
    local addon = fixtures.login(world)
    character(world).outstandingCopper = owed
    character(world).autoDeposit = false
    return world, addon
end

local function openBank(world)
    fixtures.fire(world, "GUILDBANKFRAME_OPENED")
    fixtures.advance(world, 1)
end

local function giveByButton(world, addon)
    openBank(world)
    fixtures.click(addon.tithePayment.panel.button)
    fixtures.setMoney(world, world.money - world.deposits[#world.deposits])
end

local function registerProfileTests(profile)
    test.test(profile .. " confirmed payments of every kind land in the ledger once", function()
        local world, addon = newWorld(profile, 5000)
        local ledger = addon.donationLedger

        giveByButton(world, addon)
        test.assertEqual(1, ledger:Count())
        local entry = ledger:Entries(0, 1)[1]
        test.assertEqual(5000, entry.amount)
        test.assertEqual("button", entry.method)
        test.assertEqual("jaina-camelot", entry.character.key)
        test.assertEqual("Jaina", entry.character.name)
        test.assertEqual("Player-7", entry.character.stableId)
        test.assertEqual("Knights of Camelot", entry.guild.name)
        test.assertEqual("Camelot", entry.guild.realm)

        -- A manual deposit with nothing owed still counts in full.
        world.environment.DepositGuildBankMoney(3000)
        fixtures.setMoney(world, world.money - 3000)
        test.assertEqual(2, ledger:Count())
        test.assertEqual("manual", ledger:Entries(0, 1)[1].method)
        test.assertEqual(8000, ledger:Totals().overall)

        -- A replayed money signal adds nothing.
        fixtures.fire(world, "PLAYER_MONEY")
        test.assertEqual(2, ledger:Count())
    end)

    test.test(profile .. " failed payments and income never reach the ledger", function()
        local world, addon = newWorld(profile, 5000)
        world.depositError = "not allowed"
        openBank(world)
        fixtures.click(addon.tithePayment.panel.button)
        world.depositError = nil
        fixtures.click(addon.tithePayment.panel.button)
        fixtures.advance(world, 11)
        fixtures.fire(world, "GUILDBANKFRAME_CLOSED")

        fixtures.fire(world, "LOOT_OPENED")
        fixtures.setMoney(world, CARRIED + 20000)

        test.assertEqual(0, addon.donationLedger:Count())
        test.assertEqual(0, #world.environment.AsgardsGuildTitheDB.donations)
    end)

    test.test(profile .. " the ledger survives a reload and is shared across characters", function()
        local world, addon = newWorld(profile, 5000)
        giveByButton(world, addon)

        local thrall, thrallAddon = newWorld(profile, 700, {
            database = fixtures.snapshot(world.environment.AsgardsGuildTitheDB),
            playerName = "Thrall",
        })
        test.assertEqual(1, thrallAddon.donationLedger:Count())
        giveByButton(thrall, thrallAddon)

        local ledger = thrallAddon.donationLedger
        test.assertEqual(2, ledger:Count())
        test.assertEqual(5700, ledger:Totals().overall)
        test.assertEqual("thrall-camelot", ledger:Entries(0, 1)[1].character.key)
        -- Balances stay per character.
        test.assertEqual(0, character(thrall).outstandingCopper)
        test.assertEqual(0,
            thrall.environment.AsgardsGuildTitheDB.characters["jaina-camelot"].outstandingCopper)
    end)
end

local profileIndex
for profileIndex = 1, #fixtures.PROFILES do
    registerProfileTests(fixtures.PROFILES[profileIndex])
end
