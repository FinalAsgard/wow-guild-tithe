# Testing conventions

Asgard's Guild Tithe production code and automated tests remain compatible with Lua 5.1. Run the suite from the repository root:

```sh
lua5.1 tests/run.lua
```

If `lua` on your system is Lua 5.1-compatible, `lua tests/run.lua` works as well.

## Production boundaries

- Keep accounting and other domain behavior in pure modules that do not read WoW globals.
- Put all direct use of WoW globals and client APIs in `Adapters/WoW.lua`.
- Add a method to the compatibility adapter when domain or lifecycle code needs a new client capability.
- Treat unavailable or failing optional client capabilities as expected inputs. Adapter methods return `false` or `nil` instead of leaking client errors.
- Prefer stable public functions and observable results over assertions about private tables or helper names.

## Test layout

- Put behavior specs in `tests/spec/*_spec.lua`.
- Register cases with `test.test` from `tests/test_helper.lua`.
- Use Arrange, Act, Assert structure inside each case.
- Use table-driven cases when the same behavior must be checked across several inputs.
- Build controlled WoW API fakes as ordinary Lua tables and pass them to `Compatibility.Create`. Do not install test globals.
- Add each spec module to `tests/run.lua` so the zero-dependency runner executes it.
- Keep the bootstrap spec loading every Lua file in manifest order so dependency and composition errors fail before in-game testing.

Persistence behavior is tested through the public store and character-state
interfaces. Migration specs must cover every supported version transition,
repeat loads, field-local configuration repair, exact financial preservation,
quarantine isolation, reload round trips, and no-write handling of future
schemas. See [the schema and recovery contract](persistence.md).

The test runner exits nonzero after reporting every failure. CI also parses every Lua file with Lua 5.1, runs the suite, bootstraps both manifests, and exercises the Windows junction installer twice to prove idempotency.
