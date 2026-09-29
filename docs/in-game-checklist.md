# In-game checklists

Asgard's Guild Tithe supports two clients, WoW Forever and WoW Retail (live). Each has its own checklist below. A release is compatible with a client only after that client's checklist passes on the current live build. A pass on one client never counts for the other.

Before either checklist, enable visible Lua errors with `/console scriptErrors 1` for the test session. When reporting a failure, include the build from `/dump GetBuildInfo()` and any Lua error text.

## Shared verification steps

Both checklists run these steps after installing. Replace `<AddOns>` with the client's AddOns folder.

1. Log in to a character and confirm no Asgard's Guild Tithe Lua error appears during loading.
2. Enter `/agtdev` and confirm the native Settings window opens to **AddOns > Asgard's Guild Tithe (Dev)**. If the client does not expose the supported Settings API, confirm chat instead reports that settings are unavailable and suggests `/agtdev help`.
3. When settings are available, confirm the page has visually distinct **Tithe**, **Income Sources**, and **Feedback** sections. Confirm **Tithe percentage** starts at `10`, shows its value as a whole-number percentage, accepts whole numbers from `0` through `100`, and does not allow values outside that range.
4. Confirm **Current balance** displays `0g 00s 00c` for a fresh character and has no editable control or fractional-remainder display.
5. Under **Income Sources**, confirm **Loot income**, **Quest income**, **Vendor sales**, **Player trades**, and **Miscellaneous/system income** start enabled, while **Auction income** and **Mailbox income** start disabled. Under **Feedback**, confirm **Print tithe updates** starts enabled.
6. Change the percentage and each checkbox, close and reopen settings with `/agtdev`, and confirm every new value appears immediately. Changing settings never changes the balance.
7. Run `/reload`, reopen settings, and confirm the chosen percentage and checkbox values remain.
8. Fully exit and restart the client, reopen settings, and confirm those values remain after a complete SavedVariables round trip.
9. Log in to another character, confirm it receives the defaults, choose different values, then return to the first character and confirm each character stayed isolated.
10. Enter `/agtdev help` and confirm both the `help` and `settings` commands appear once, followed by a line naming the running client.
11. Enter `/agtdev unknown` and confirm the add-on reports an unknown command and suggests `/agtdev help` without raising an error.
12. If the production add-on is also installed, enable it on its own and confirm `/agt` and `/asgardstithe` open **Asgard's Guild Tithe** settings with values independent of the development variant.

## Income tracking steps

Run these on a guilded character after the shared steps, on both clients. Every supported source is classified: loot, quest rewards, vendor sales, auction proceeds, mail, and player trades. Refunds, returned mail, and guild-bank withdrawals are never tithed. Anything else is miscellaneous/system income.

1. Note your carried gold, run `/reload`, and confirm no income message appears and the balance does not change: money you already carry never counts.
2. Sell an item to a vendor. Confirm chat shows `reserved <amount> from vendor sale income. Total owed: <total>.`, where the amount is your tithe percentage of the sale, and that reopening `/agtdev` shows the new total.
3. Spend money (for example, buy an item) and confirm no message appears and the balance is unchanged.
4. Earn a very small amount (a few copper at 10%) and confirm no "0 copper reserved" message appears.
5. Turn off **Miscellaneous/system income**, earn money, and confirm the balance does not change. Turn it back on.
6. Turn off **Print tithe updates**, earn money, and confirm the balance still increases with no chat message. Turn it back on.
7. On a guildless character, earn money and confirm the balance does not change. After joining a guild, confirm new gains are tracked again.
8. Kill a creature alone and loot its coin. Confirm the message says `from loot income`.
9. In a group, loot coin that is shared with the party. Confirm your share is reported `from loot income`.
10. Loot coin, wait a few seconds, then sell an item. Confirm the sale is reported as a vendor sale, not loot.
11. Turn off **Loot income**, loot coin, and confirm the balance does not change and no message appears. Turn it back on.
12. Sell several items to a vendor quickly, one after another. Confirm one grouped message appears about a second after the last sale, with the combined amount reserved from vendor sale income and the correct total owed. Gains from a different source always get their own message.
13. Turn in a quest that rewards money. Confirm it is reported `from quest income`. A quest that rewards only items adds nothing.
14. Turn off **Quest income** and **Vendor sales** one at a time, and confirm each stops only its own source. Turn them back on.
15. Turn on **Mailbox income**, mail gold from one of your characters to another, collect it, and confirm it is reported `from mailbox income`. Turn **Mailbox income** off again and confirm the next mailed gold changes nothing.
16. When convenient: collect auction-sale money with **Auction income** on and **Mailbox income** off, and confirm it is reported `from auction income`. Then try the reverse and confirm the auction money is ignored.
17. When convenient: receive gold in a completed trade and confirm it is reported `from player trade income`. Cancel a trade that offered gold and confirm nothing happens.
18. When convenient: withdraw gold from the guild bank and confirm the balance does not change and no message appears.
19. When convenient: buy an item from a vendor and sell it back for a refund. Confirm the refund is not tithed.

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

Two-client re-check (PRD #14):

- **Date:** 2026-09-28
- **Client:** World of Warcraft: Forever (interfaces `16000`/`16001`)
- **Result:** Signed off by Jon Zenor: the add-on launches correctly on Forever with the two-client changes (`_Camelot` and `_Mainline` manifests both present). Smoke test on the final PR commit: no Lua errors, `/agtdev help` reports `client - WoW Forever.` (so Forever loaded `_Camelot`, not `_Mainline`), and settings persist across `/reload`.
- **Build:** `1.60.1` build `70009` (Sep 23 2026), interface `16001`.
- **Signed off by:** Jon Zenor

## WoW Retail

### Install

1. From the checkout, run `./tools/Install-Dev.ps1 -Client Retail` in PowerShell. Add `-WowInstallRoot` or `-WowRoot` if Retail is not in its default location (see [the development install](development-install.md)).
2. Confirm `_retail_/Interface/AddOns/AsgardsGuildTitheDev` is a junction to the checkout and that `AsgardsGuildTitheDev_Mainline.toc`, `Core`, and `Adapters` are directly inside it.
3. Start or restart the Retail client so it rescans add-ons.
4. At character selection, open **AddOns** and confirm **Asgard's Guild Tithe (Dev)** appears enabled and is not marked out of date. Disable the production variant if it is installed.
5. Run `/dump (select(4, GetBuildInfo()))` and confirm it matches the `## Interface` value in both `_Mainline.toc` manifests (currently `120100`). If it differs, update both manifests before continuing.

### Verify

Run the shared verification steps. In step 10, the client line reads `client - WoW Retail.`

### Sign-off

- **Date:** 2026-09-28
- **Client:** World of Warcraft Retail (live)
- **Interface:** `120100`, confirmed with `/dump (select(4, GetBuildInfo()))` and matching both `_Mainline.toc` manifests
- **Build:** `12.1.0` build `69933` (Sep 18 2026).
- **Result:** Signed off by Jon Zenor: the add-on launches correctly on Retail. Smoke test on the final PR commit: no Lua errors, `/agtdev help` reports `client - WoW Retail.`, and settings persist across `/reload`.
- **Signed off by:** Jon Zenor

## Income tracking sign-off (PRD #3)

- **Date:** 2026-09-29
- **Result:** Signed off by Jon Zenor: "I tested the plugin and everything looks good." Covers the income tracking steps above.
- **Clients and builds:** Not recorded separately.
- **Signed off by:** Jon Zenor
