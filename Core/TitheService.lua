local _, addon = ...

local TitheService = {}
addon.TitheService = TitheService

local Service = {}
Service.__index = Service

function TitheService.Create(state, accounting)
    return setmetatable({
        accounting = accounting or addon.Accounting,
        state = state,
    }, Service)
end

function Service:AccrueEligibleCopper(eligibleCopper)
    if self.state == nil
        or self.accounting == nil
        or type(self.accounting.Calculate) ~= "function"
    then
        return nil, "accounting state is unavailable"
    end

    local character = self.state:GetCurrentCharacter()
    if type(character) ~= "table" then
        return nil, "current character state is unavailable"
    end

    local result, calculateError = self.accounting.Calculate(
        eligibleCopper,
        character.percentage,
        character.outstandingCopper,
        character.fractionalRemainder
    )
    if result == nil then
        return nil, calculateError
    end

    if not self.state:SetFinancialState(
        result.outstandingCopper,
        result.fractionalRemainder
    ) then
        return nil, "updated financial state was rejected"
    end

    return result
end
