local addonName, addon = ...

local client = addon.Compatibility.Create()
local clientProfile = client:GetClientProfile()
local router = addon.CommandRouter.Create(function(message)
    client:Print(message)
end)

router:Register("help", "show available commands", function()
    router:PrintHelp()
    client:Print(addon.Identity.displayName .. ": client - " .. clientProfile.label .. ".")
end)

local state, titheService, settingsController, incomeObserver, tithePayment, donationLedger
local historyController
if clientProfile.supported then
    state = addon.CharacterState.Create(client)
    donationLedger = addon.DonationLedger.Create(function()
        return state:GetDonationRecords()
    end)
    titheService = addon.TitheService.Create(state, addon.Accounting)
    settingsController = addon.SettingsController.Create(client, state, addon.MoneyFormatter,
        donationLedger)
    settingsController:RegisterCommands(router)
    historyController = addon.HistoryController.Create(client, donationLedger, addon.MoneyFormatter)
    historyController:RegisterCommands(router)
    settingsController:OnRegistered(function(category)
        historyController:RegisterSettingsPage(category)
    end)
    local incomeFeedback = addon.IncomeFeedback.Create(function(message)
        client:Print(message)
    end, addon.MoneyFormatter, function(seconds, callback)
        return client:After(seconds, callback)
    end)
    local incomeCoordinator = addon.IncomeCoordinator.Create(
        client,
        state,
        titheService,
        incomeFeedback
    )
    incomeObserver = addon.IncomeObserver.Create(client, incomeCoordinator)
    tithePayment = addon.TithePayment.Create(client, state, addon.MoneyFormatter)
    -- Only confirmed payments reach the ledger; nothing else can append.
    tithePayment:OnDonation(function(donation)
        donationLedger:Append(donation)
    end)
    router:Register("clear", "clear the current tithe balance", function()
        local character = state:GetCurrentCharacter()
        if character == nil or not state:SetFinancialState(0, 0) then
            client:Print(addon.Identity.displayName ..
                ": your tithe balance is unavailable, so nothing was cleared.")
            return
        end
        client:Print(addon.Identity.displayName .. ": cleared your tithe balance (was " ..
            addon.MoneyFormatter.Format(character.outstandingCopper) .. ").")
        tithePayment:RefreshOffer()
    end)
else
    -- Never touch saved character data on a client we cannot identify.
    client:Print(addon.Identity.displayName .. ": this game client is not supported (" ..
        clientProfile.reason .. "). Supported clients are WoW Forever and WoW Retail. " ..
        "Saved data was left unchanged.")
end

-- Development-only raw event capture for building test fixtures; the
-- production add-on never registers the command or its SavedVariables.
local eventTrace
if addon.Identity.isDevelopment then
    eventTrace = addon.EventTrace.Create(client)
    local function report(message)
        client:Print(addon.Identity.displayName .. ": trace " .. message)
    end
    router:Register("trace", "capture events: start, stop, status, clear", function(arguments)
        local action = string.lower(arguments or "")
        if action == "start" then
            local started, startError = eventTrace:Start()
            report(started and "started." or ("could not start (" .. tostring(startError) .. ")."))
        elseif action == "stop" then
            report(eventTrace:Stop() and
                "stopped. /reload or log out to write it to SavedVariables." or
                "was not running.")
        elseif action == "clear" then
            eventTrace:Clear()
            report("cleared.")
        else
            local active, count = eventTrace:Status()
            report((active and "is running" or "is stopped") .. " with " .. count ..
                " entries. Use " .. addon.Identity.slashCommand ..
                " trace start|stop|status|clear.")
        end
    end)
end

local lifecycle = addon.Lifecycle.Create(
    client,
    router,
    state,
    settingsController,
    incomeObserver,
    tithePayment
)

addon.client = client
addon.clientProfile = clientProfile
addon.donationLedger = donationLedger
addon.historyController = historyController
addon.eventTrace = eventTrace
addon.incomeObserver = incomeObserver
addon.lifecycle = lifecycle
addon.router = router
addon.settingsController = settingsController
addon.state = state
addon.tithePayment = tithePayment
addon.titheService = titheService

lifecycle:Start()
