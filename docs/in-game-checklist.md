# Initial in-game checklist

Use this checklist with the current World of Warcraft: Forever client.

## Install

1. Copy the repository folder to `_classic_beta_/Interface/AddOns/GuildTithe`.
2. Confirm `GuildTithe_Camelot.toc` and the `Core` and `Adapters` folders are directly inside `GuildTithe`.
3. Start or restart the client so it rescans add-ons.
4. At character selection, open **AddOns** and confirm **Guild Tithe** appears enabled and is not marked out of date. The manifest targets Forever interfaces `16000` and `16001`.
5. Enable visible Lua errors with `/console scriptErrors 1` for the test session.

## Verify

1. Log in to a character and confirm no Guild Tithe Lua error appears during loading.
2. Enter `/gt` and confirm the native Settings window opens to **AddOns > Guild Tithe**. If this Forever build does not expose the supported Settings API, confirm chat instead reports that settings are unavailable and suggests `/gt help`.
3. When settings are available, confirm **Tithe percentage** starts at `10`, accepts whole numbers from `0` through `100`, and does not allow values outside that range.
4. Confirm **Current balance** displays `0g 00s 00c` for a fresh character and has no editable control or fractional-remainder display.
5. Confirm **Loot income**, **Quest income**, **Vendor sales**, **Player trades**, **Miscellaneous/system income**, and **Routine chat feedback** start enabled, while **Auction income** and **Mailbox income** start disabled.
6. Change the percentage and each checkbox, close and reopen settings with `/gt`, and confirm every new value appears immediately while the balance remains unchanged.
7. Run `/reload`, reopen settings, and confirm the chosen percentage and checkbox values remain.
8. Log in to another character, confirm it receives the defaults, choose different values, then return to the first character and confirm each character stayed isolated.
9. Enter `/gt help` and confirm both the `help` and `settings` commands appear once.
10. Enter `/gt unknown` and confirm the add-on reports an unknown command and suggests `/gt help` without raising an error.

Record the Forever build from `/dump GetBuildInfo()` and any Lua error text when reporting a failure.
