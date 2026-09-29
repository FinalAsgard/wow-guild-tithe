local _, addon = ...

local IncomeCoordinator = {}
addon.IncomeCoordinator = IncomeCoordinator

local Coordinator = {}
Coordinator.__index = Coordinator

function IncomeCoordinator.Create(client, state, titheService, feedback)
    return setmetatable({
        client = client,
        feedback = feedback,
        state = state,
        titheService = titheService,
    }, Coordinator)
end

local function terminal(observation, status, reason)
    return {
        copper = observation.copper,
        id = observation.id,
        reason = reason,
        source = observation.source,
        status = status,
    }
end

-- Produces the single terminal result for one classified observation.
-- Guild membership and settings are read now, at finalization; any result
-- other than "accrued" leaves balance and fractional remainder untouched.
function Coordinator:Finalize(observation)
    -- A known non-income transfer never reaches accounting, whatever the
    -- guild or source settings are.
    if observation.excluded then
        return terminal(observation, "excluded", observation.reason)
    end

    local character = self.state:GetCurrentCharacter()
    if type(character) ~= "table" then
        return terminal(observation, "unresolved", "current character state is unavailable")
    end

    local inGuild = self.client:IsInGuild()
    if inGuild == nil then
        return terminal(observation, "unresolved", "guild membership is unavailable")
    end
    if not inGuild then
        return terminal(observation, "guildless", "character is not in a guild")
    end

    if type(character.sources) ~= "table" or character.sources[observation.source] ~= true then
        return terminal(observation, "disabled", observation.source .. " income is disabled")
    end

    local accrual, accrualError = self.titheService:AccrueEligibleCopper(observation.copper)
    if accrual == nil then
        return terminal(observation, "unresolved", accrualError)
    end

    local result = terminal(observation, "accrued", observation.reason)
    result.accruedCopper = accrual.accruedCopper
    result.outstandingCopper = accrual.outstandingCopper

    if character.chatFeedback == true and self.feedback ~= nil then
        self.feedback:Accrued(observation.source, accrual.accruedCopper, accrual.outstandingCopper)
    end

    return result
end
