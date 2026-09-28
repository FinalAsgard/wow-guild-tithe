# Persistence schema and recovery

`AsgardsGuildTitheDB` is the production account-wide SavedVariables table;
`AsgardsGuildTitheDevDB` is its isolated development counterpart. Runtime
identity selects the declared table, and production code reads and writes it
only through `Adapters/WoW.lua`. `Core/Persistence.lua` is the single loading,
migration, and validation boundary used by character state. Settings and
accounting receive state only after that boundary succeeds.

## Current schema: version 2

The persisted shape is:

```lua
AsgardsGuildTitheDB = {
    schemaVersion = 2,
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
        },
    },
    quarantinedCharacters = {
        ["normalizedname-normalizedrealm"] = {
            {
                reason = "diagnostic text",
                record = {}, -- preserved original record
                schemaVersion = 2,
            },
        },
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
- Version 2 is validated and repaired without a schema change.

Loading the result again performs no migration and makes no further structural
or value changes.

## Validation and recovery

Configuration is repaired at field granularity. An invalid percentage,
chat-feedback value, individual source flag, or optional identity value receives
only its own default or safe current-character metadata. Valid sibling fields,
financial state, display metadata, and unrelated character records are retained.

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

A schema version newer than 2 is incompatible. It is returned as an error before
copying, migration, validation, or writeback, leaving the SavedVariables table
and all nested values untouched for a newer add-on version to handle.
