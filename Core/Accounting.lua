local _, addon = ...

local Accounting = {
    MAX_SAFE_INTEGER = 9007199254740991,
    REMAINDER_DENOMINATOR = 100,
}
addon.Accounting = Accounting

local function isSafeInteger(value)
    return type(value) == "number"
        and value >= 0
        and value <= Accounting.MAX_SAFE_INTEGER
        and value == math.floor(value)
end

local function isPercentage(value)
    return isSafeInteger(value) and value <= 100
end

local function isRemainder(value)
    return isSafeInteger(value) and value < Accounting.REMAINDER_DENOMINATOR
end

function Accounting.IsSafeInteger(value)
    return isSafeInteger(value)
end

function Accounting.Calculate(eligibleCopper, percentage, outstandingCopper, priorRemainder)
    if not isSafeInteger(eligibleCopper) then
        return nil, "eligible copper must be a non-negative safe integer"
    end

    if not isPercentage(percentage) then
        return nil, "percentage must be an integer from 0 through 100"
    end

    if not isSafeInteger(outstandingCopper) then
        return nil, "outstanding copper must be a non-negative safe integer"
    end

    if not isRemainder(priorRemainder) then
        return nil, "fractional remainder must be an integer from 0 through 99"
    end

    -- Decompose before multiplying so every intermediate remains within the
    -- exactly representable integer range of the Lua 5.1 number type.
    local eligibleHundreds = math.floor(eligibleCopper / Accounting.REMAINDER_DENOMINATOR)
    local eligibleRemainder = eligibleCopper % Accounting.REMAINDER_DENOMINATOR
    local fractionalNumerator = eligibleRemainder * percentage + priorRemainder
    local accruedCopper = eligibleHundreds * percentage
        + math.floor(fractionalNumerator / Accounting.REMAINDER_DENOMINATOR)
    local fractionalRemainder = fractionalNumerator % Accounting.REMAINDER_DENOMINATOR

    if accruedCopper > Accounting.MAX_SAFE_INTEGER - outstandingCopper then
        return nil, "updated outstanding copper exceeds the safe integer domain"
    end

    return {
        accruedCopper = accruedCopper,
        outstandingCopper = outstandingCopper + accruedCopper,
        fractionalRemainder = fractionalRemainder,
    }
end
