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

-- The game's coin icons, drawn inline at text height.
MoneyFormatter.GOLD_ICON = "|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t"
MoneyFormatter.SILVER_ICON = "|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t"
MoneyFormatter.COPPER_ICON = "|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t"

-- Copper as the game shows money: a number and coin icon per unit, leaving
-- out empty units (12 gold 5 copper, not 12g 00s 05c). Zero is 0 copper.
function MoneyFormatter.Format(copper)
    if not isSafeInteger(copper) then
        return nil, "copper must be a non-negative safe integer"
    end

    local gold = math.floor(copper / 10000)
    local silver = math.floor(copper / 100) % 100
    local remainingCopper = copper % 100
    local parts = {}
    if gold > 0 then
        table.insert(parts, string.format("%.0f", gold) .. MoneyFormatter.GOLD_ICON)
    end
    if silver > 0 then
        table.insert(parts, silver .. MoneyFormatter.SILVER_ICON)
    end
    if remainingCopper > 0 or #parts == 0 then
        table.insert(parts, remainingCopper .. MoneyFormatter.COPPER_ICON)
    end
    return table.concat(parts, " ")
end
