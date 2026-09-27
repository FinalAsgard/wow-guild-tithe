# wow-guild-tithe

A World of Warcraft: Forever add-on that tracks a configurable guild tithe and deposits it at the guild bank.

## Current foundation

The add-on currently provides its Forever manifest, load lifecycle, client compatibility boundary, per-character saved state, and extensible `/gt` command router. On clients with the supported native Settings API, `/gt` opens an AddOns settings page where the current character's whole-number tithe percentage, seven income-source preferences, and routine chat-feedback preference can be changed. Clients without that API keep loading normally and explain that settings are unavailable.

Accounting and balance presentation arrive in subsequent feature slices.

All direct WoW API access belongs in `Adapters/WoW.lua`; core modules are client-independent Lua. See [the testing conventions](docs/testing.md) for the project boundary and test style.

## Verify the scaffold

Run the automated suite with Lua 5.1:

```sh
lua5.1 tests/run.lua
```

For client verification, follow the [initial in-game checklist](docs/in-game-checklist.md).
