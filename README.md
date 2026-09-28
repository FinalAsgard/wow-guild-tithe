# Asgard's Guild Tithe

A World of Warcraft: Forever add-on foundation for configuring and accounting for a guild tithe. Live income tracking and guild-bank deposits are planned for later PRDs.

## Current foundation

The add-on currently provides its Forever manifest, load lifecycle, client compatibility boundary, per-character saved state, exact tithe accounting service, money formatter, and extensible `/agt` command router. On clients with the supported native Settings API, `/agt` opens an AddOns settings page where the current character's outstanding balance is shown read-only and the whole-number tithe percentage, seven income-source preferences, and routine chat-feedback preference can be changed. Clients without that API keep loading normally and explain that settings are unavailable.

All direct WoW API access belongs in `Adapters/WoW.lua`; core modules are client-independent Lua. See [the persistence schema and recovery contract](docs/persistence.md) for migration and corruption behavior, and [the testing conventions](docs/testing.md) for the project boundary and test style.

## Verify the scaffold

Run the automated suite with Lua 5.1:

```sh
lua5.1 tests/run.lua
```

For Windows development setup, use the [isolated development install](docs/development-install.md), then follow the [initial in-game checklist](docs/in-game-checklist.md).
