local addonName, addon = ...

local VARIANTS = {
    AsgardsGuildTithe = {
        displayName = "Asgard's Guild Tithe",
        slashCommand = "/agt",
    },
    AsgardsGuildTitheDev = {
        displayName = "Asgard's Guild Tithe (Dev)",
        slashCommand = "/agtdev",
    },
}

local variant = VARIANTS[addonName]
if variant == nil then
    error("unsupported Asgard's Guild Tithe add-on identity: " .. tostring(addonName))
end

addon.Identity = {
    addonName = addonName,
    databaseName = addonName .. "DB",
    displayName = variant.displayName,
    settingsPrefix = addonName,
    slashCommand = variant.slashCommand,
    slashKey = string.upper(addonName),
}
