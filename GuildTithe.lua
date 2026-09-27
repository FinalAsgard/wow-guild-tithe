local addonName, addon = ...

local client = addon.Compatibility.Create()
local router = addon.CommandRouter.Create(function(message)
    client:Print(message)
end)

router:Register("help", "show available commands", function()
    router:PrintHelp()
end)

local lifecycle = addon.Lifecycle.Create(client, router, addonName)

addon.client = client
addon.lifecycle = lifecycle
addon.router = router

lifecycle:Start()
