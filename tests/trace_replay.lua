local fixtures = require("tests.client_fixtures")

-- Replays a captured event trace (tests/fixtures/traces/<client>/*.lua)
-- through the real add-on under the matching client profile. The fake clock
-- follows the captured timestamps, carried money follows each entry's
-- recorded money, and every captured event is fired with its arguments.
local TraceReplay = {}

local PROFILES = {
    ["WoW Forever"] = "Forever",
    ["WoW Retail"] = "Retail",
}

function TraceReplay.load(path)
    local chunk = assert(loadfile(path))
    return chunk()
end

-- Returns the world after replaying `trace` and letting the last gain settle.
function TraceReplay.run(trace, options)
    options = options or {}
    local profile = PROFILES[trace.header.client]
    assert(profile ~= nil, "unknown trace client " .. tostring(trace.header.client))

    local entries = trace.entries
    local world = fixtures.newEnvironment(profile, { money = entries[1].money })
    fixtures.login(world)
    if options.prepare ~= nil then
        options.prepare(world)
    end

    local offset = world.now - entries[1].t
    local index
    for index = 1, #entries do
        local entry = entries[index]
        local at = entry.t + offset
        if at > world.now then
            fixtures.advance(world, at - world.now)
        end
        world.money = entry.money
        if entry.kind == "event" then
            fixtures.fire(world, entry.name, unpack(entry.args))
        end
    end

    fixtures.settle(world)
    return world
end

return TraceReplay
