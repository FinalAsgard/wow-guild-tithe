# wow-guild-tithe

A World of Warcraft: Forever add-on that tracks a configurable guild tithe and deposits it at the guild bank.

## Current foundation

The add-on currently provides its Forever manifest, load lifecycle, client compatibility boundary, per-character saved state, exact tithe accounting service, money formatter, and extensible `/gt` command router. On clients with the supported native Settings API, `/gt` opens an AddOns settings page where the current character's outstanding balance is shown read-only and the whole-number tithe percentage, seven income-source preferences, and routine chat-feedback preference can be changed. Clients without that API keep loading normally and explain that settings are unavailable.

Live income observation and classification arrive in a subsequent PRD.

All direct WoW API access belongs in `Adapters/WoW.lua`; core modules are client-independent Lua. See [the persistence schema and recovery contract](docs/persistence.md) for migration and corruption behavior, and [the testing conventions](docs/testing.md) for the project boundary and test style.

## Verify the scaffold

Run the automated suite with Lua 5.1:

```sh
lua5.1 tests/run.lua
```

For client verification, follow the [initial in-game checklist](docs/in-game-checklist.md).
