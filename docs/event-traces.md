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

## Replaying traces as tests

`tests/trace_replay.lua` replays a captured trace through the real add-on under the matching client profile. The fake clock follows the captured timestamps, carried money follows each entry, and every captured event is fired with its arguments. Hooked function-call entries, such as mail collection, are not replayed. A trace that outgrew the 2,000-entry limit records `baselineMoney`, the balance before its first kept entry, and replay starts from it. `tests/spec/trace_replay_spec.lua` asserts the exact tithe results for event-based replay. Add a new capture by saving only its `AsgardsGuildTitheDevTraceDB` table (with no character data) under `tests/fixtures/traces/<client>/` and adding a replay test.

## Observed timings

These real captures confirm the timing windows in `Core/IncomeCorrelator.lua` and `Core/IncomeObserver.lua`:

| Capture | What happened | Timing |
| --- | --- | --- |
| `forever/vendor-sale.lua` (Forever 1.60.1) | `MERCHANT_SHOW`, then the sale's `PLAYER_MONEY`, then `MERCHANT_UPDATE` | Vendor window opened 3.7s before the money; the update arrived 5 ms after it |
| `retail/quest-turn-ins.lua` (Retail 12.1.0) | `QUEST_TURNED_IN(questID, xp, money)`, then `PLAYER_MONEY` with a delta equal to the money argument | 0.10–0.31s after the turn-in, across 4 turn-ins |
| `retail/quest-turn-ins.lua` | `GUILDBANK_UPDATE_MONEY` / `GUILDBANK_UPDATE_WITHDRAWMONEY` with the guild bank closed | No change to carried money (the Retail guild perk); never used as context |

The slowest corroborating message (0.31s) fits the 1s note window, and the 0.3s finalize delay covers messages that arrive just after the money. No window needed retuning.
