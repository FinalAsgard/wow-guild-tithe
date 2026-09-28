# Testing conventions

Asgard's Guild Tithe production code and automated tests remain compatible with Lua 5.1. Run the suite from the repository root:

```sh
lua5.1 tests/run.lua
```

If `lua` on your system is Lua 5.1-compatible, `lua tests/run.lua` works as well.

## Production boundaries

- Keep accounting and other domain behavior in pure modules that do not read WoW globals.
- Put all direct use of WoW globals and client APIs in `Adapters/WoW.lua`.
- Add a method to the compatibility adapter when domain or lifecycle code needs a new client capability.
- Treat unavailable or failing optional client capabilities as expected inputs. Adapter methods return `false` or `nil` instead of leaking client errors.
- Prefer stable public functions and observable results over assertions about private tables or helper names.

## Test layout

- Put behavior specs in `tests/spec/*_spec.lua`.
- Register cases with `test.test` from `tests/test_helper.lua`.
- Use Arrange, Act, Assert structure inside each case.
- Use table-driven cases when the same behavior must be checked across several inputs.
- Build controlled WoW API fakes as ordinary Lua tables and pass them to `Compatibility.Create`. Do not install test globals.
- Add each spec module to `tests/run.lua` so the zero-dependency runner executes it.
- Keep the bootstrap spec loading every Lua file in manifest order so dependency and composition errors fail before in-game testing.

## Client profiles

Asgard's Guild Tithe supports two clients: WoW Forever and WoW Retail.
`Adapters/ClientProfile.lua` classifies the running client from the `## X-Client`
field of the manifest the client loaded (`Forever` or `Retail`); only that
client's loader selects the manifest. A Retail declaration must also be
confirmed by the Retail project constants. Shared internals never classify a
client on their own, so Forever is never mistaken for Retail. Anything else is
unsupported: the add-on prints one message, keeps `help` available, and never
reads or writes saved character data.

Core modules do not know which client is running. Only the adapter and the
composition root (`AsgardsGuildTithe.lua`) consult the profile, and `/agt help`
names the running client for diagnostics.

`tests/client_fixtures.lua` builds controlled Forever and Retail API surfaces
and loads the full add-on in manifest order inside them.

- Put a test in `tests/spec/client_profile_spec.lua` (or another profile-driven
  spec) when the behavior touches the adapter, lifecycle, or composition root
  and could differ by client. Register it for every entry in
  `fixtures.PROFILES` so neither client becomes the accidental default.
- Keep client-independent domain behavior (accounting, persistence, formatting,
  routing, settings policy) in the shared specs. They run once. Do not copy
  them per profile just to relabel the same behavior.
- When a client difference is added to the adapter, model it in the matching
  fixture and cover the shared outcome under both profiles.

Persistence behavior is tested through the public store and character-state
interfaces. Migration specs must cover every supported version transition,
repeat loads, field-local configuration repair, exact financial preservation,
quarantine isolation, reload round trips, and no-write handling of future
schemas. See [the schema and recovery contract](persistence.md).

The test runner exits nonzero after reporting every failure. CI also parses every Lua file with Lua 5.1, runs the suite, bootstraps all four manifests (production and development for Forever and Retail), checks that their module lists stay identical, and runs `tests/Install-Dev.Tests.ps1` on Windows to exercise the junction installer for Forever and Retail layouts, custom roots, repeat installs, conflicting junctions, and real-directory refusal.
