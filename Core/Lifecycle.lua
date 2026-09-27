local _, addon = ...

local Lifecycle = {}
addon.Lifecycle = Lifecycle

local Controller = {}
Controller.__index = Controller

function Lifecycle.Create(client, router, addonName)
    return setmetatable({
        addonName = addonName,
        client = client,
        initialized = false,
        router = router,
        slashRegistered = false,
    }, Controller)
end

function Controller:Initialize()
    if self.initialized then
        return self.slashRegistered
    end

    self.initialized = true
    self.slashRegistered = self.client:RegisterSlashCommand("/gt", "GUILDTITHE", function(input)
        self.router:Execute(input)
    end)

    if not self.slashRegistered then
        self.client:Print("Guild Tithe: /gt is unavailable on this client.")
    end

    return self.slashRegistered
end

function Controller:OnEvent(eventName, loadedAddonName)
    if eventName == "ADDON_LOADED" and loadedAddonName == self.addonName then
        self:Initialize()
    end
end

function Controller:Start()
    local frame = self.client:CreateEventFrame()
    if frame == nil then
        self:Initialize()
        return false
    end

    local handlerRegistered = self.client:SetEventHandler(frame, function(_, eventName, loadedAddonName)
        self:OnEvent(eventName, loadedAddonName)
    end)
    local eventRegistered = self.client:RegisterEvent(frame, "ADDON_LOADED")

    if not handlerRegistered or not eventRegistered then
        self:Initialize()
        return false
    end

    self.frame = frame
    return true
end
