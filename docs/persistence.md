# Persistence schema and recovery

`AsgardsGuildTitheDB` is the production account-wide SavedVariables table;
`AsgardsGuildTitheDevDB` is its isolated development counterpart. Runtime
identity selects the declared table, and production code reads and writes it
only through `Adapters/WoW.lua`. `Core/Persistence.lua` is the single loading,
migration, and validation boundary used by character state. Settings and
accounting receive state only after that boundary succeeds.

## Current schema: version 4

The persisted shape is:

```lua
AsgardsGuildTitheDB = {
    schemaVersion = 4,
    characters = {
        ["normalizedname-normalizedrealm"] = {
            identity = {
                displayName = "Character",
                displayRealm = "Realm",
                stableId = "optional-client-identifier",
            },
            percentage = 10,
            outstandingCopper = 0,
            fractionalRemainder = 0,
            chatFeedback = true,
            sources = {
                auctions = false,
                loot = true,
                mailbox = false,
                miscellaneous = true,
                playerTrades = true,
                quests = true,
                vendorSales = true,
            },
            -- At most one guild-bank payment waiting for confirmation.
            pendingPayment = {
                operationId = "jaina-camelot:1790001000:1",
                amount = 5000,              -- requested copper
                method = "button",          -- "automatic", "button", or "manual"
                character = { key = "jaina-camelot", name = "Jaina", realm = "Camelot" },
                guild = { id = "42", name = "Guild", realm = "Realm" }, -- id optional
                moneyBefore = 100000,       -- carried copper when requested
                createdAt = 1790001000,     -- server time
                status = "pending",
            },
            resolvedPayments = { "jaina-camelot:1790000000:1" }, -- newest last, at most 20
            paymentSequence = 1,
        },
    },
    quarantinedCharacters = {
        ["normalizedname-normalizedrealm"] = {
            {
                reason = "diagnostic text",
                record = {}, -- preserved original record
                schemaVersion = 4,
            },
        },
    },
    -- Account-wide, append-only record of completed donations.
    donations = {
        {
            operationId = "jaina-camelot:1790001000:1",
            timestamp = 1790001004,     -- server time
            amount = 5000,              -- exact copper, always positive
            method = "button",          -- "automatic", "button", or "manual"
            character = { key = "jaina-camelot", name = "Jaina", realm = "Camelot",
                stableId = "Player-7" },  -- stableId optional
            guild = { id = "42", name = "Guild", realm = "Realm" }, -- id optional
        },
    },
    -- Ledger entries that could not be read, kept intact.
    quarantinedDonations = {
        { reason = "diagnostic text", record = {}, schemaVersion = 4 },
    },
}
```

Unknown account, character, identity, and source metadata is retained when the
database is copied forward. Callers receive snapshots rather than direct saved
records.

## Migration sequence

Migrations operate on a deep copy and advance exactly one version at a time.
The copy is written back only after migration and full validation succeed.

- Version 1 to version 2 adds `quarantinedCharacters` when absent, preserves an
  existing quarantine, then runs the version-2 validator over every character.
- Version 2 to version 3 gives every character record an empty
  `resolvedPayments` list and a `paymentSequence` of 0. No payment is pending
  after the upgrade.
- Version 3 to version 4 adds an empty account-wide `donations` ledger and an
  empty `quarantinedDonations` list when absent.
- Version 4 is validated and repaired without a schema change.

Loading the result again performs no migration and makes no further structural
or value changes.

## Validation and recovery

Configuration is repaired at field granularity. An invalid percentage,
chat-feedback value, individual source flag, or optional identity value receives
only its own default or safe current-character metadata. Valid sibling fields,
financial state, display metadata, and unrelated character records are retained.

Payment state is repaired the same way. An unreadable `pendingPayment` is
dropped, an invalid `resolvedPayments` list is emptied, and an invalid
`paymentSequence` restarts at 0. Dropping payment state never changes the
balance, so the worst case is a debt that a later payment can settle.

Financial fields are never coerced, rounded, or reset. `outstandingCopper` must
be a non-negative safe integer, and `fractionalRemainder` must be an integer from
0 through 99. A record that violates either rule is moved intact to its
character's quarantine history with a diagnostic reason. Other valid characters
remain available. If the quarantined key belongs to the current character, no
replacement record is created and settings and accounting remain unavailable.

Character-map keys must use the normalized `name-realm` form. A malformed key
is moved to a generated quarantine entry that retains both the original key and
record, so it cannot shadow or block valid characters. Cyclic saved tables are
rejected before migration or writeback because they cannot be safely represented
as SavedVariables.

A schema version newer than 4 is incompatible. It is returned as an error before
copying, migration, validation, or writeback, leaving the SavedVariables table
and all nested values untouched for a newer add-on version to handle.

## Guild-bank payments

Each payment is saved as `pendingPayment` before the deposit is requested, and
it resolves exactly once: confirmed, rejected (the deposit call failed),
expired (no matching money drop in time), or unresolved (the guild changed
before confirmation). Resolving removes the intent and appends its operation id
to `resolvedPayments` in the same step. A confirmed payment also saves the
reduced balance in that step, so a replayed money signal or a `/reload` can
never credit it twice, and a resolved id is never accepted as pending again.

After a reload, a saved intent is confirmed if carried money already equals
`moneyBefore - amount`; otherwise it waits for that drop with a fresh timeout.
Guild identity is compared by stable id when both sides have one and by
realm-qualified name otherwise.

## Donation ledger

`donations` is shared by every character on the account and is appended to only
when a guild-bank payment is confirmed (the completed-donation event). The
operation id is the idempotency key: a donation whose id is already recorded
adds nothing, before or after a reload. Invalid donations (no id, a zero,
negative or fractional amount, a bad timestamp, an unknown method, or missing
character or guild identity) are rejected without writing anything. Income is
never recorded here.

On load, an unreadable entry, a repeated operation id (the first entry is
kept), or an entry outside the list is moved intact to `quarantinedDonations`
with a reason, and every valid entry stays. A `donations` value that is not a
list is quarantined whole and replaced with an empty list. Amounts are never
coerced.

Totals are always derived from the entries: an overall total and one total per
guild. Guilds are grouped by stable id when present, otherwise by
realm-qualified name (case and spacing ignored), so a rename under the same id
stays one guild and shows its newest name.

## Reading donation data from other add-ons

Companion add-ons, such as the planned **Guild Fellowship** leaderboard, may
read the donation ledger directly. It is the only saved data offered for
outside reading, and it is **read-only**: another add-on must never write to
the Guild Tithe database. Guild Tithe exposes no API or callbacks for this;
this section is the contract.

**Where.** The production add-on keeps its account-wide data in the global
`AsgardsGuildTitheDB`. The ledger is `AsgardsGuildTitheDB.donations`, a list
of entries in the order they were recorded. The development build uses
`AsgardsGuildTitheDevDB` instead; companion add-ons should read only the
production table.

**When.** Guild Tithe validates and upgrades its saved data when the player
logs in, and retries when the player enters the world if login was too
early. Before that, the table may still use an older schema or hold entries
that validation would move to `quarantinedDonations`. Read on demand, for
example when the leaderboard opens or on a timer, at any point after
`PLAYER_ENTERING_WORLD`. List `AsgardsGuildTithe` under `## OptionalDeps` so
it loads first. There is no change notification, so re-read to pick up new
donations.

**Which version.** Check `AsgardsGuildTitheDB.schemaVersion == 4` before
reading, and treat any other value as unavailable rather than guessing.
Guild Tithe raises `schemaVersion` whenever the donation format changes, and
this section documents the current one.

**What each entry means.** Each entry in `donations` has these fields (see
"Current schema" above):

| Field | Meaning |
| --- | --- |
| `operationId` | Unique id of the donation; use it to avoid counting one twice |
| `timestamp` | Server time (seconds) when the donation was confirmed |
| `amount` | Exact copper given, always a positive integer |
| `method` | `automatic` (deposited when the bank opened), `button` (**Give Tithe**), or `manual` (the player's own deposit through the guild bank window) |
| `character` | The donor: `key` (normalized `name-realm`), `name`, `realm`, and optional `stableId` |
| `guild` | The recipient: `name`, `realm`, and an optional stable `id` |

Only `automatic` and `button` entries are tithes paid through Guild Tithe.
A leaderboard of tithes should count those two methods and leave out
`manual`. To total one guild, match entries by `guild.id` when present, and
otherwise by `guild.name` plus `guild.realm`, ignoring case and spaces in the
realm. A player may have donated to other guilds before joining the current
one. Every character on the same WoW account shares this one ledger, so all
entries belong to one player, grouped per character by `character.key`.
Ignore `quarantinedDonations`: those entries could not be read and never
count toward totals.
