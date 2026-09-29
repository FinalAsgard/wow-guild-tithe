local _, addon = ...

local IncomeObserver = {
    -- Seconds a gain waits for corroborating context before it is finalized.
    FINALIZE_DELAY = 0.3,
}
addon.IncomeObserver = IncomeObserver

local Observer = {}
Observer.__index = Observer

function IncomeObserver.Create(client, coordinator, correlator)
    return setmetatable({
        client = client,
        coordinator = coordinator,
        correlator = correlator or addon.IncomeCorrelator.Create(),
        nextObservationId = 0,
        started = false,
    }, Observer)
end

-- Records the current carried money as the baseline, so money the character
-- already had is never treated as income, then starts watching for changes.
-- Pending context from before this session is discarded.
function Observer:Start()
    if self.started then
        return true
    end

    local baseline = self.client:GetCarriedMoney()
    if baseline == nil then
        return false, "carried money is unavailable"
    end
    -- Without guild membership every gain would be unresolved, so report
    -- the missing capability once instead of silently tracking nothing.
    if self.client:IsInGuild() == nil then
        return false, "guild membership is unavailable"
    end
    self.baseline = baseline
    self.pending = nil
    self.correlator:Reset()

    if not self.client:ObserveMoneyChanges(function()
        self:OnMoneyChanged()
    end) then
        return false, "money change events are unavailable"
    end

    -- Source context is optional: without it every gain is miscellaneous.
    self.client:ObserveIncomeContext(function(source, action, amount)
        self.correlator:Record(source, action, self.client:Now(), amount)
    end)

    self.started = true
    return true
end

-- The carried-money delta is authoritative: only a positive change becomes
-- an observation. It is finalized after a short delay so context that
-- arrives just after the money change can still classify it.
function Observer:OnMoneyChanged()
    local current = self.client:GetCarriedMoney()
    if current == nil or self.baseline == nil then
        return nil
    end

    local delta = current - self.baseline
    self.baseline = current
    if delta <= 0 then
        return nil
    end

    -- Finalize any earlier gain first so each keeps its own context.
    self:FinalizePending()

    self.nextObservationId = self.nextObservationId + 1
    local observation = {
        copper = delta,
        id = self.nextObservationId,
        observedAt = self.client:Now(),
    }
    self.pending = observation

    if not self.client:After(IncomeObserver.FINALIZE_DELAY, function()
        if self.pending == observation then
            self:FinalizePending()
        end
    end) then
        self:FinalizePending()
    end

    return observation
end

-- Produces the single terminal result for the pending gain, if any.
function Observer:FinalizePending()
    local observation = self.pending
    if observation == nil then
        return nil
    end
    self.pending = nil

    local finalizedAt = self.client:Now()
    observation.source, observation.reason, observation.excluded = self.correlator:Classify(
        observation.observedAt,
        finalizedAt,
        observation.copper
    )
    self.correlator:Prune(finalizedAt)
    return self.coordinator:Finalize(observation)
end
