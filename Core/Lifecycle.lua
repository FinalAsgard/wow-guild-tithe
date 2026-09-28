local _, addon = ...

local Lifecycle = {}
addon.Lifecycle = Lifecycle

local Controller = {}
Controller.__index = Controller

function Lifecycle.Create(client, router, state, settingsController)
    return setmetatable({
        addonName = addon.Identity.addonName,
        client = client,
        initialized = false,
        router = router,
        slashRegistrationAttempted = false,
        slashRegistered = false,
        state = state,
        stateReady = false,
        settingsController = settingsController,
        settingsReady = false,
    }, Controller)
end

function Controller:RegisterSlash()
    if self.slashRegistrationAttempted then
        return self.slashRegistered
    end

    self.slashRegistrationAttempted = true
    self.slashRegistered = self.client:RegisterSlashCommand(
        addon.Identity.slashCommand,
        addon.Identity.slashAlias,
        addon.Identity.slashKey,
        function(input)
            self.router:Execute(input)
        end
    )

    if not self.slashRegistered then
        self.client:Print(addon.Identity.displayName .. ": " ..
            addon.Identity.slashCommand .. " is unavailable on this client.")
    end

    return self.slashRegistered
end

function Controller:InitializeState()
    if self.initialized then
        return self.stateReady
    end

    self.initialized = true
    if self.state ~= nil then
        local ok, initialized, stateError = pcall(self.state.Initialize, self.state)
        self.stateReady = ok and initialized == true
        if not self.stateReady then
            local failure = ok and stateError or initialized
            self.client:Print(addon.Identity.displayName ..
                ": saved character state is unavailable" ..
                (type(failure) == "string" and " (" .. failure .. ")." or "."))
        end
    end

    if self.stateReady and self.settingsController ~= nil then
        local ok, registered = pcall(self.settingsController.Register, self.settingsController)
        self.settingsReady = ok and registered == true
    end

    return self.stateReady
end

function Controller:OnEvent(eventName, loadedAddonName)
    if eventName == "ADDON_LOADED" and loadedAddonName == self.addonName then
        self:RegisterSlash()
    elseif eventName == "PLAYER_LOGIN" then
        self:InitializeState()
    end
end

function Controller:Start()
    local frame = self.client:CreateEventFrame()
    if frame == nil then
        self:RegisterSlash()
        return false
    end

    local handlerRegistered = self.client:SetEventHandler(frame, function(_, eventName, loadedAddonName)
        self:OnEvent(eventName, loadedAddonName)
    end)
    local addonLoadedRegistered = self.client:RegisterEvent(frame, "ADDON_LOADED")
    local playerLoginRegistered = self.client:RegisterEvent(frame, "PLAYER_LOGIN")

    if not handlerRegistered or not addonLoadedRegistered then
        self:RegisterSlash()
    end

    if not handlerRegistered then
        return false
    end

    self.frame = frame
    return addonLoadedRegistered and playerLoginRegistered
end
