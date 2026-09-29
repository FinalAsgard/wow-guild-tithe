local _, addon = ...

local IncomeObserver = {}
addon.IncomeObserver = IncomeObserver

local Observer = {}
Observer.__index = Observer

function IncomeObserver.Create(client, coordinator)
    return setmetatable({
        client = client,
        coordinator = coordinator,
        nextObservationId = 0,
        started = false,
    }, Observer)
end

-- Records the current carried money as the baseline, so money the character
-- already had is never treated as income, then starts watching for changes.
function Observer:Start()
    if self.started then
        return true
    end

    local baseline = self.client:GetCarriedMoney()
    if baseline == nil then
        return false, "carried money is unavailable"
    end
    self.baseline = baseline

    if not self.client:ObserveMoneyChanges(function()
        self:OnMoneyChanged()
    end) then
        return false, "money change events are unavailable"
    end

    self.started = true
    return true
end

-- The carried-money delta is authoritative: only a positive change becomes
-- an observation, and it yields exactly one terminal result.
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

    self.nextObservationId = self.nextObservationId + 1
    return self.coordinator:Finalize({
        copper = delta,
        id = self.nextObservationId,
        reason = "no specific source context",
        source = "miscellaneous",
    })
end
