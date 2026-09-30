local _, addon = ...

local Lifecycle = {}
addon.Lifecycle = Lifecycle

local Controller = {}
Controller.__index = Controller

function Lifecycle.Create(client, router, state, settingsController, incomeObserver, tithePayment)
    return setmetatable({
        addonName = addon.Identity.addonName,
        client = client,
        incomeObserver = incomeObserver,
        incomeReady = false,
        paymentReady = false,
        tithePayment = tithePayment,
        initialized = false,
        router = router,
        slashRegistrationAttempted = false,
        slashRegistered = false,
        state = state,
        stateFailureReported = false,
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
        self.client:Print(addon.Identity.chatPrefix .. " " ..
            addon.Identity.slashCommand .. " is unavailable on this client.")
    end

    return self.slashRegistered
end

function Controller:InitializeState()
    if self.initialized then
        return self.stateReady
    end

    if self.state ~= nil then
        local ok, initialized, stateError = pcall(self.state.Initialize, self.state)
        self.stateReady = ok and initialized == true
        if not self.stateReady and not self.stateFailureReported then
            -- Report once; later login events retry quietly.
            self.stateFailureReported = true
            local failure = ok and stateError or initialized
            self.client:Print(addon.Identity.chatPrefix ..
                " Saved character state is unavailable" ..
                (type(failure) == "string" and " (" .. failure .. ")." or "."))
        end
    end

    -- A failed attempt (for example, identity not ready yet) stays retryable.
    self.initialized = self.state == nil or self.stateReady

    if self.stateReady and self.settingsController ~= nil then
        local ok, registered = pcall(self.settingsController.Register, self.settingsController)
        self.settingsReady = ok and registered == true
    end

    -- Income observation needs character state; this block runs once, on the
    -- attempt that makes state ready, so a failure is reported only once.
    if self.stateReady and self.incomeObserver ~= nil then
        local ok, started, startError = pcall(self.incomeObserver.Start, self.incomeObserver)
        self.incomeReady = ok and started == true
        if not self.incomeReady then
            local failure = ok and startError or started
            self.client:Print(addon.Identity.chatPrefix ..
                " Income tracking is unavailable on this client" ..
                (type(failure) == "string" and " (" .. failure .. ")" or "") ..
                ". Your saved balance is unchanged.")
        end
    end

    -- Guild-bank payments also need character state. A client without the
    -- guild-bank events simply never offers a payment.
    if self.stateReady and self.tithePayment ~= nil then
        local ok, started = pcall(self.tithePayment.Start, self.tithePayment)
        self.paymentReady = ok and started == true
    end

    return self.stateReady
end

function Controller:OnEvent(eventName, loadedAddonName)
    if eventName == "ADDON_LOADED" and loadedAddonName == self.addonName then
        self:RegisterSlash()
        -- Loaded after login (load-on-demand): PLAYER_LOGIN has already fired.
        if self.client:IsLoggedIn() then
            self:InitializeState()
        end
    elseif eventName == "PLAYER_LOGIN" or eventName == "PLAYER_ENTERING_WORLD" then
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
    -- Retry point when identity was not ready at PLAYER_LOGIN.
    self.client:RegisterEvent(frame, "PLAYER_ENTERING_WORLD")

    if not handlerRegistered or not addonLoadedRegistered then
        self:RegisterSlash()
    end

    if not handlerRegistered then
        return false
    end

    self.frame = frame
    return addonLoadedRegistered and playerLoginRegistered
end
