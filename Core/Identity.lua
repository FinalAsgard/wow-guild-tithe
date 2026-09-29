local addonName, addon = ...

local VARIANTS = {
    AsgardsGuildTithe = {
        displayName = "Asgard's Guild Tithe",
        slashAlias = "/asgardstithe",
        slashCommand = "/agt",
    },
    AsgardsGuildTitheDev = {
        displayName = "Asgard's Guild Tithe (Dev)",
        isDevelopment = true,
        slashAlias = "/asgardstithedev",
        slashCommand = "/agtdev",
        traceDatabaseName = "AsgardsGuildTitheDevTraceDB",
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
    isDevelopment = variant.isDevelopment == true,
    settingsPrefix = addonName,
    slashAlias = variant.slashAlias,
    slashCommand = variant.slashCommand,
    slashKey = string.upper(string.sub(variant.slashCommand, 2)),
    traceDatabaseName = variant.traceDatabaseName,
}
