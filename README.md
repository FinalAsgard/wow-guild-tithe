# Asgard's Guild Tithe

A World of Warcraft add-on for configuring and accounting for a guild tithe. It watches the character's carried money, works out where each gain came from, and reserves the configured percentage of income from the sources you enable. When you open your guild bank, it gives your tithe automatically, or with a **Give Tithe** button in the bank window.

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

The add-on currently provides its Forever and Retail manifests, load lifecycle, client compatibility boundary, per-character saved state, exact tithe accounting service, money formatter, and extensible `/agt` command router. On clients with the supported native Settings API, `/agt` opens an AddOns settings page where the current character's outstanding balance is shown read-only and the whole-number tithe percentage, seven income-source preferences, print-tithe-updates preference, and deposit-tithe-automatically preference can be changed. Clients without that API keep loading normally and explain that settings are unavailable. The settings page also shows **Lifetime given**: the total donated at the guild bank by every character on the account. It is kept in an account-wide donation ledger and updates as soon as a donation is confirmed. `/agt clear` resets the current character's tithe balance to zero, including its fractional remainder, and reports the amount that was cleared.

All direct WoW API access belongs in `Adapters/`; core modules are client-independent Lua. See [the persistence schema and recovery contract](docs/persistence.md) for migration and corruption behavior, and [the testing conventions](docs/testing.md) for the project boundary, client profiles, and test style.

## Income tracking

At login the add-on records the character's carried money as a starting point, so money already in the bags never counts. Each later increase is one income observation. While the character is in a guild and the matching income source is enabled, the configured percentage is added to the outstanding tithe and chat reports the source, the amount reserved, and the total owed (unless **Print tithe updates** is off). Gains from the same source within about a second, such as selling a stack of items, share one message with their combined amount; each gain is still saved the moment it happens. Spending, gains while guildless, and gains from disabled sources never change the balance or its fractional remainder. Each gain is matched to short-lived context from the game: coin looted from a corpse or shared by the party is loot income, money from turning in a quest is quest income (matched to the exact reward the game reports), money received while a vendor window is open is vendor sale income, auction sale proceeds collected from mail are auction income, and other mail money is mailbox income (the auction and mailbox settings are independent). Money received in a completed trade is player trade income. Money that was already yours is never tithed: mail returned to sender, item refunds, and money you withdraw from the guild bank. The Retail guild perk that adds a bonus to the guild bank when members earn money is ignored, because it never changes your carried money. A gain with no recognized context is miscellaneous/system income.

The game does not mark refunds from being outbid at the auction house as returns, so that money counts as mailbox income, which is off by default.

## Giving your tithe at the guild bank

Opening your guild bank adds a **Give Tithe** button to the guild bank window, just left of its **Withdraw** button. Hovering it shows the guild that will receive the tithe, the amount (everything you owe, but never more than you carry), and what you will still owe afterwards. If the add-on cannot find the Withdraw button on your client, the same offer appears in a small panel beside the guild bank instead. With **Deposit tithe automatically** checked (the default, in the settings' **Guild Bank** section), that amount is deposited a second after the bank opens. With it unchecked, or whenever an automatic deposit fails, is not confirmed, or is blocked by the game, click **Give Tithe** to pay. If the game blocks an automatic deposit, the add-on does not try again until your next login or `/reload`, so you never see repeated errors. Your tithe balance goes down only after your carried gold actually drops by exactly that amount; a failed or unconfirmed deposit leaves the balance unchanged and tells you. When you owe nothing or carry no gold, **Give Tithe** stays in the window but is greyed out, and its tooltip says why. Closing the guild bank discards the offer. Payment messages always print, even when **Print tithe updates** is off.

Gold you deposit yourself through the guild bank's own money window also counts: while the guild bank is open, the add-on sees the deposit request and credits it once your carried gold drops by exactly that amount. A deposit larger than what you owe clears the balance without going below zero. Withdrawals and other spending never count, and a deposit made while the add-on's own payment is still waiting is not counted. A deposit is counted once, even across a `/reload`. If you leave or switch guilds before a deposit is confirmed, it is not credited, and your balance stays as it was.

## Donation history

Every donation confirmed at the guild bank is recorded in an account-wide history shared by all your characters. Open it with `/agt history`, or pick **Donation History** under the add-on's entry in the game's AddOns settings. The tab shows your lifetime total, a total for each guild you have given to, and a newest-first list with the date, guild, character, amount, and how it was given: **Guild Tithe** for deposits the add-on made (automatic or the Give Tithe button) and **Manual** for deposits you made through the guild bank's own window. Scroll with the mouse wheel or the **Newer** and **Older** buttons. It updates as soon as a donation is confirmed. Before your first donation it says there are none yet. History cannot be edited or deleted. On a client whose settings cannot host the tab, `/agt history` opens the same view in its own window.

## Verify the scaffold

Run the automated suite with Lua 5.1:

```sh
lua5.1 tests/run.lua
```

For Windows development setup, use the [isolated development install](docs/development-install.md), then follow the [in-game checklists](docs/in-game-checklist.md). To build and inspect the multi-client release zip, see [release packaging](docs/packaging.md).
