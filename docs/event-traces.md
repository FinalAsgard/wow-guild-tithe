# Capturing event traces

The development build (`AsgardsGuildTitheDev`) can record the raw client events around income activity. These recordings become test fixtures and are used to tune how long income context stays valid. The production add-on has no trace command and never records anything.

## Commands

| Command | What it does |
| --- | --- |
| `/agtdev trace start` | Starts recording. Nothing is recorded until you run this. |
| `/agtdev trace stop` | Stops recording and unregisters every traced event. |
| `/agtdev trace status` | Shows whether tracing is running and how many entries it holds. |
| `/agtdev trace clear` | Deletes the recorded entries. |

Each entry stores a timestamp, the event or function name, its arguments (tables and functions are replaced with placeholders, and long strings are cut to 255 characters), your carried copper at that moment, and whether you were in combat. The trace header stores the client (`WoW Forever` or `WoW Retail`), the `GetBuildInfo()` values, and which events the client did not recognize. Only the newest 2,000 entries are kept.

Traces can contain character, realm, and player names from chat and trade events. They are cleaned before being committed as fixtures.

## What to capture

On each client, use a guilded character. Run `/agtdev trace clear` and then `/agtdev trace start`, and do the activities below. A few seconds between activities helps separate them in the trace.

1. Loot coin from a creature you killed alone.
2. In a group, loot coin that is shared with the party.
3. Turn in a quest that rewards money.
4. Sell several items to a vendor quickly, one after another.
5. Collect money from an auction-sale mail.
6. Collect money from an ordinary (non-auction) mail.
7. Complete a trade where the other player gives you money.
8. Start a trade with money offered, then cancel it.
9. Withdraw money from the guild bank, if you have permission.
10. Buy an item and sell it back for a refund, if the client offers one.

Then run `/agtdev trace stop` and `/reload` (or log out) so the game writes the trace to disk.

## Where the file is

The trace is saved with the development build's SavedVariables:

- WoW Forever: `World of Warcraft\_classic_beta_\WTF\Account\<ACCOUNT>\SavedVariables\AsgardsGuildTitheDev.lua`
- WoW Retail: `World of Warcraft\_retail_\WTF\Account\<ACCOUNT>\SavedVariables\AsgardsGuildTitheDev.lua`

The trace is the `AsgardsGuildTitheDevTraceDB` table in that file. Attach the file to the capture issue, or copy it to `tests/fixtures/traces/<client>/`, and note which activities you performed.
