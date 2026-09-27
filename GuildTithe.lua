local addonName, addon = ...

local client = addon.Compatibility.Create()
local state = addon.CharacterState.Create(client)
local router = addon.CommandRouter.Create(function(message)
    client:Print(message)
end)
local settingsController = addon.SettingsController.Create(client, state)

router:Register("help", "show available commands", function()
    router:PrintHelp()
end)
settingsController:RegisterCommands(router)

local lifecycle = addon.Lifecycle.Create(client, router, addonName, state, settingsController)

addon.client = client
addon.lifecycle = lifecycle
addon.router = router
addon.settingsController = settingsController
addon.state = state

lifecycle:Start()
