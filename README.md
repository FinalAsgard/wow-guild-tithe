# Asgard's Guild Tithe

A World of Warcraft add-on for configuring and accounting for a guild tithe. It watches the character's carried money and reserves the configured percentage of new income for the guild. Source-specific income classification is being added, and guild-bank deposits are planned for a later PRD.

## Supported clients

| Client | Status | Production manifest | Interface |
|---|---|---|---|
| World of Warcraft: Forever | Supported | `AsgardsGuildTithe_Camelot.toc` | `16000`, `16001` |
| World of Warcraft Retail (live) | Supported | `AsgardsGuildTithe_Mainline.toc` | `120100` |
| WoW Classic Era, progression Classic, Anniversary, and seasonal Classic | Not supported | — | — |
| Retail PTR, alpha, and beta | Not supported | — | — |

Both supported clients get the same add-on name, commands, settings, and saved-data format from one source tree and one version. Each game installation keeps its own SavedVariables, and nothing is synchronized between Forever and Retail. Each client loads only its own manifest. Retail uses `_Mainline`, the suffix the WoW packager and CurseForge tag as Retail. Forever also accepts `_Mainline`, but it always prefers its own `_Camelot` manifest, so the two manifests must always ship together. On an unsupported client the add-on reports that once and leaves saved data untouched.

Interface numbers are release metadata, not permanent constants. Confirm them from each running client with `/dump (select(4, GetBuildInfo()))` after every game patch and before each release, and update both manifests for that client together.

## Current foundation

The add-on currently provides its Forever and Retail manifests, load lifecycle, client compatibility boundary, per-character saved state, exact tithe accounting service, money formatter, and extensible `/agt` command router. On clients with the supported native Settings API, `/agt` opens an AddOns settings page where the current character's outstanding balance is shown read-only and the whole-number tithe percentage, seven income-source preferences, and print-tithe-updates preference can be changed. Clients without that API keep loading normally and explain that settings are unavailable.

All direct WoW API access belongs in `Adapters/`; core modules are client-independent Lua. See [the persistence schema and recovery contract](docs/persistence.md) for migration and corruption behavior, and [the testing conventions](docs/testing.md) for the project boundary, client profiles, and test style.

## Income tracking

At login the add-on records the character's carried money as a starting point, so money already in the bags never counts. Each later increase is one income observation. While the character is in a guild and the matching income source is enabled, the configured percentage is added to the outstanding tithe and chat reports the source, the amount reserved, and the total owed (unless **Print tithe updates** is off). Spending, gains while guildless, and gains from disabled sources never change the balance or its fractional remainder. For now every increase is classified as miscellaneous/system income; loot, quest, vendor, mail, auction, and trade classification follow in later issues.

## Verify the scaffold

Run the automated suite with Lua 5.1:

```sh
lua5.1 tests/run.lua
```

For Windows development setup, use the [isolated development install](docs/development-install.md), then follow the [in-game checklists](docs/in-game-checklist.md). To build and inspect the multi-client release zip, see [release packaging](docs/packaging.md).
