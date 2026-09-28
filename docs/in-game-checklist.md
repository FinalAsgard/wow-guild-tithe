# In-game checklists

Asgard's Guild Tithe supports two clients, WoW Forever and WoW Retail (live). Each has its own checklist below. A release is compatible with a client only after that client's checklist passes on the current live build. A pass on one client never counts for the other.

Before either checklist, enable visible Lua errors with `/console scriptErrors 1` for the test session. When reporting a failure, include the build from `/dump GetBuildInfo()` and any Lua error text.

## Shared verification steps

Both checklists run these steps after installing. Replace `<AddOns>` with the client's AddOns folder.

1. Log in to a character and confirm no Asgard's Guild Tithe Lua error appears during loading.
2. Enter `/agtdev` and confirm the native Settings window opens to **AddOns > Asgard's Guild Tithe (Dev)**. If the client does not expose the supported Settings API, confirm chat instead reports that settings are unavailable and suggests `/agtdev help`.
3. When settings are available, confirm the page has visually distinct **Tithe**, **Income Sources**, and **Feedback** sections. Confirm **Tithe percentage** starts at `10`, shows its value as a whole-number percentage, accepts whole numbers from `0` through `100`, and does not allow values outside that range.
4. Confirm **Current balance** displays `0g 00s 00c` for a fresh character, states that income tracking is not active yet, and has no editable control or fractional-remainder display.
5. Under **Income Sources**, confirm **Loot income**, **Quest income**, **Vendor sales**, **Player trades**, and **Miscellaneous/system income** start enabled, while **Auction income** and **Mailbox income** start disabled. Under **Feedback**, confirm **Routine chat feedback** starts enabled. The source options configure the future income observer; selling an item does not change the balance yet.
6. Change the percentage and each checkbox, close and reopen settings with `/agtdev`, and confirm every new value appears immediately while the balance remains unchanged.
7. Run `/reload`, reopen settings, and confirm the chosen percentage and checkbox values remain.
8. Fully exit and restart the client, reopen settings, and confirm those values remain after a complete SavedVariables round trip.
9. Log in to another character, confirm it receives the defaults, choose different values, then return to the first character and confirm each character stayed isolated.
10. Enter `/agtdev help` and confirm both the `help` and `settings` commands appear once, followed by a line naming the running client.
11. Enter `/agtdev unknown` and confirm the add-on reports an unknown command and suggests `/agtdev help` without raising an error.
12. If the production add-on is also installed, enable it on its own and confirm `/agt` and `/asgardstithe` open **Asgard's Guild Tithe** settings with values independent of the development variant.

## WoW Forever

### Install

1. From the checkout at `~/Projects/wow-guild-tithe`, run `./tools/Install-Dev.ps1` in PowerShell. Pass `-WowRoot` if the Forever client is not in its default location.
2. Confirm `_classic_beta_/Interface/AddOns/AsgardsGuildTitheDev` is a junction to the checkout and that `AsgardsGuildTitheDev_Camelot.toc`, `Core`, and `Adapters` are directly inside it.
3. Start or restart the client so it rescans add-ons.
4. At character selection, open **AddOns** and confirm **Asgard's Guild Tithe (Dev)** appears enabled and is not marked out of date. Disable the production variant if it is installed. The Forever manifests target interfaces `16000` and `16001`.

### Verify

Run the shared verification steps. In step 10, the client line reads `client - WoW Forever.`

### Sign-off

- **Date:** 2026-09-27
- **Client:** World of Warcraft: Forever (interfaces `16000`/`16001`)
- **Result:** Every step above passed in the real client after the integration fixes on PR #13. No outstanding defects.
- **Build:** Not recorded. The build number is captured only when reporting an unresolved failure.
- **Signed off by:** Jon Zenor

This sign-off predates the two-client changes. Re-run the Forever checklist before releasing Retail support and record the new result here.

## WoW Retail

### Install

1. From the checkout, run `./tools/Install-Dev.ps1 -WowRoot "C:\Program Files (x86)\World of Warcraft\_retail_"` in PowerShell, adjusting the path if Retail is installed elsewhere.
2. Confirm `_retail_/Interface/AddOns/AsgardsGuildTitheDev` is a junction to the checkout and that `AsgardsGuildTitheDev_Standard.toc`, `Core`, and `Adapters` are directly inside it.
3. Start or restart the Retail client so it rescans add-ons.
4. At character selection, open **AddOns** and confirm **Asgard's Guild Tithe (Dev)** appears enabled and is not marked out of date. Disable the production variant if it is installed.
5. Run `/dump (select(4, GetBuildInfo()))` and confirm it matches the `## Interface` value in both `_Standard.toc` manifests (currently `120100`). If it differs, update both manifests before continuing.

### Verify

Run the shared verification steps. In step 10, the client line reads `client - WoW Retail.`

### Sign-off

- **Date:**
- **Client:** World of Warcraft Retail (live)
- **Interface:**
- **Build:**
- **Result:**
- **Signed off by:**
