local _, addon = ...

local MoneyFormatter = {
    MAX_SAFE_INTEGER = 9007199254740991,
}
addon.MoneyFormatter = MoneyFormatter

local function isSafeInteger(value)
    return type(value) == "number"
        and value >= 0
        and value <= MoneyFormatter.MAX_SAFE_INTEGER
        and value == math.floor(value)
end

function MoneyFormatter.Format(copper)
    if not isSafeInteger(copper) then
        return nil, "copper must be a non-negative safe integer"
    end

    local gold = math.floor(copper / 10000)
    local silver = math.floor(copper / 100) % 100
    local remainingCopper = copper % 100

    return string.format("%.0fg %02ds %02dc", gold, silver, remainingCopper)
end
