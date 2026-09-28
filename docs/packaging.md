# Release packaging

One tagged source revision produces one CurseForge package that supports WoW
Forever and WoW Retail. The package holds both production manifests, and each
client loads only its own:

| Client | Manifest | Packager game type |
| --- | --- | --- |
| WoW Forever | `AsgardsGuildTithe_Camelot.toc` | `forever` |
| WoW Retail | `AsgardsGuildTithe_Mainline.toc` | `retail` |

The [BigWigs packager](https://github.com/BigWigsMods/packager) reads these
suffixes to tag the release with each client's game versions, so CurseForge
offers the file to both clients. Keep the suffixes to ones the packager
recognizes. An unrecognized suffix, such as `_Standard`, silently drops that
client from the release tags. Forever also accepts `_Mainline`, but it always
prefers its own `_Camelot` manifest, so both manifests must ship together.

`.pkgmeta` excludes the development manifests, tests, tools, docs, `ai/`, and
CI configuration. The package keeps the production manifests, every runtime
module they load, `README.md`, and `LICENSE`, and the packager adds a
generated `CHANGELOG.md`.

## Build and inspect locally

```sh
tools/build-package.sh            # writes .release/AsgardsGuildTithe-<version>.zip
unzip -l .release/AsgardsGuildTithe-*.zip
```

The script downloads the packager and runs it with `-d`, so nothing is ever
uploaded. It fails unless the packager tags the build for both clients
(`Build type: multi-version`). It then runs `tools/check-package.sh`, which fails
when:

- a production manifest is missing, or a module it loads is not in the zip
- the production manifests disagree on `## Version`
- a development manifest, test, tool, doc, `ai/`, or CI file was packaged

The packager needs bash 4.3 or newer. macOS ships bash 3.2, so install a newer
one (for example `brew install bash`) and point the script at it:

```sh
PACKAGER_BASH=/opt/homebrew/bin/bash tools/build-package.sh
```

On macOS the packager's changelog step prints a harmless `sed` warning. CI
builds on Linux, where it does not appear.

CI runs the same script on every pull request in the **Release package** job.

## Before a release

1. Confirm each client's interface number from the running client and update
   both of that client's manifests (see the README).
2. Run both in-game checklists in [in-game-checklist.md](in-game-checklist.md).
   A release claims compatibility with a client only after that client's
   checklist passes on the current live build. A pass on one client never
   counts for the other.
3. Build and inspect the package as above.

Publishing to CurseForge, configuring its API token, and release notes are
separate release operations and are not automated in this repository.
