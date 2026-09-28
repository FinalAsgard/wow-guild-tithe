# Initial in-game checklist

Use this checklist with the current World of Warcraft: Forever client.

## Install

1. From the checkout at `~/Projects/wow-guild-tithe`, run `./tools/Install-Dev.ps1` in PowerShell. Pass `-WowRoot` if the Forever client is not in its default location.
2. Confirm `_classic_beta_/Interface/AddOns/AsgardsGuildTitheDev` is a junction to the checkout and that `AsgardsGuildTitheDev_Camelot.toc`, `Core`, and `Adapters` are directly inside it.
3. Start or restart the client so it rescans add-ons.
4. At character selection, open **AddOns** and confirm **Asgard's Guild Tithe (Dev)** appears enabled and is not marked out of date. Disable the production variant if it is installed. The manifest targets Forever interfaces `16000` and `16001`.
5. Enable visible Lua errors with `/console scriptErrors 1` for the test session.

## Verify

1. Log in to a character and confirm no Asgard's Guild Tithe Lua error appears during loading.
2. Enter `/agtdev` and confirm the native Settings window opens to **AddOns > Asgard's Guild Tithe (Dev)**. If this Forever build does not expose the supported Settings API, confirm chat instead reports that settings are unavailable and suggests `/agtdev help`.
3. When settings are available, confirm **Tithe percentage** starts at `10`, accepts whole numbers from `0` through `100`, and does not allow values outside that range.
4. Confirm **Current balance** displays `0g 00s 00c` for a fresh character and has no editable control or fractional-remainder display.
5. Confirm **Loot income**, **Quest income**, **Vendor sales**, **Player trades**, **Miscellaneous/system income**, and **Routine chat feedback** start enabled, while **Auction income** and **Mailbox income** start disabled.
6. Change the percentage and each checkbox, close and reopen settings with `/agtdev`, and confirm every new value appears immediately while the balance remains unchanged.
7. Run `/reload`, reopen settings, and confirm the chosen percentage and checkbox values remain.
8. Fully exit and restart the client, reopen settings, and confirm those values remain after a complete SavedVariables round trip.
9. Log in to another character, confirm it receives the defaults, choose different values, then return to the first character and confirm each character stayed isolated.
10. Enter `/agtdev help` and confirm both the `help` and `settings` commands appear once.
11. Enter `/agtdev unknown` and confirm the add-on reports an unknown command and suggests `/agtdev help` without raising an error.

Record the Forever build from `/dump GetBuildInfo()` and any Lua error text when reporting a failure.
