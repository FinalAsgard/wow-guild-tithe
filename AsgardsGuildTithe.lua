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

local state, titheService, settingsController, incomeObserver
if clientProfile.supported then
    state = addon.CharacterState.Create(client)
    titheService = addon.TitheService.Create(state, addon.Accounting)
    settingsController = addon.SettingsController.Create(client, state, addon.MoneyFormatter)
    settingsController:RegisterCommands(router)
    local incomeFeedback = addon.IncomeFeedback.Create(function(message)
        client:Print(message)
    end, addon.MoneyFormatter)
    local incomeCoordinator = addon.IncomeCoordinator.Create(
        client,
        state,
        titheService,
        incomeFeedback
    )
    incomeObserver = addon.IncomeObserver.Create(client, incomeCoordinator)
else
    -- Never touch saved character data on a client we cannot identify.
    client:Print(addon.Identity.displayName .. ": this game client is not supported (" ..
        clientProfile.reason .. "). Supported clients are WoW Forever and WoW Retail. " ..
        "Saved data was left unchanged.")
end

local lifecycle = addon.Lifecycle.Create(
    client,
    router,
    state,
    settingsController,
    incomeObserver
)

addon.client = client
addon.clientProfile = clientProfile
addon.incomeObserver = incomeObserver
addon.lifecycle = lifecycle
addon.router = router
addon.settingsController = settingsController
addon.state = state
addon.titheService = titheService

lifecycle:Start()
