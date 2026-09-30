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

The script downloads the packager at a pinned commit (`PACKAGER_COMMIT` in
`tools/packager.env`; update it deliberately) and runs it with `-d`, so nothing is ever
uploaded. It fails unless the packager tags the build for both clients
(`Build type: multi-version`). It then runs `tools/check-package.sh`, which fails
when:

- a production manifest is missing, or a module it loads is not in the zip
- the production manifests disagree on `## Version`, or still contain an
  unreplaced `@project-version@` (and, during a release, when the version is not
  exactly the release tag)
- a development manifest, test, tool, doc, `ai/`, or CI file was packaged
- any manifest other than the two production manifests was packaged

The packager needs bash 4.3 or newer. macOS ships bash 3.2, so install a newer
one (for example `brew install bash`) and point the script at it:

```sh
PACKAGER_BASH=/opt/homebrew/bin/bash tools/build-package.sh
```

On macOS the packager's changelog step prints a harmless `sed` warning. CI
builds on Linux, where it does not appear.

CI runs the same script on every pull request in the **Release package** job.

## Before a release

1. Confirm each client's interface number from the running client
   (`/dump (select(4, GetBuildInfo()))`) and, if it changed, run
   `tools/set-interface.sh <forever|retail> <interface>`. It updates both of
   that client's manifests, the test expectation, and the README table.
2. Run both in-game checklists in [in-game-checklist.md](in-game-checklist.md).
   A release claims compatibility with a client only after that client's
   checklist passes on the current live build. A pass on one client never
   counts for the other.
3. Build and inspect the package as above.

## Publishing to CurseForge

Publishing a GitHub release publishes the add-on. The **Release** workflow
(`.github/workflows/release.yml`) runs when a release is published and:

1. checks that the release's tag is a valid version and that the production
   manifests take their version from it (`tools/check-release-tag.sh`), and that
   **Set as a pre-release**
   matches the tag (checked for `alpha`/`beta` tags, unchecked otherwise);
2. runs the Lua syntax check and the full test suite;
3. writes the release notes to `CHANGELOG.md`, so they become the changelog on
   CurseForge and inside the package (with no notes, a changelog is generated
   from git history instead);
4. builds and validates the package without uploading (`tools/build-package.sh`);
5. builds it again with the same pinned packager and uploads it to CurseForge,
   tagged for both Forever and Retail (`tools/publish-release.sh`);
6. attaches the zip to the GitHub release.

Any failed step stops the release before anything is uploaded, except the
upload steps themselves. The packager never edits the GitHub release, so the
title and notes stay exactly as written. The packager revision is pinned once,
in `tools/packager.env`, and shared by builds and releases.

### One-time setup

1. Create the add-on project on CurseForge (World of Warcraft, AddOns) and note
   its **Project ID** from the project's About panel.
2. In the GitHub repository, open **Settings → Secrets and variables → Actions**:
   - under **Variables**, add `CURSEFORGE_PROJECT_ID` with the project ID;
   - under **Secrets**, add `CF_API_KEY` with a token from
     <https://legacy.curseforge.com/account/api-tokens>.

Without both, the upload step fails with a message naming what is missing.

3. Leave CurseForge's own **automatic packaging** off, and don't add its
   webhook to GitHub. This workflow already uploads every release, so both
   together would upload each version twice.

Both are configured for this project: ID `1719265`, and the token secret.

### Versions

The add-on's version comes from the release tag. The production manifests
declare `## Version: @project-version@`, which the packager replaces with the
tag (for example `v0.2.0`) when it builds a release. That is the version shown
in the game's AddOns list and on CurseForge. The development manifests declare
`dev`. Builds that are not releases, such as those on pull requests, are
versioned by the packager from the commit instead.

### Cutting a release

1. Do the checks in **Before a release** above.
2. On GitHub, open **Releases → Draft a new release**:
   - **Choose a tag**: type the new tag, for example `v0.2.0`, and create it on
     `main`. This tag is the version: the packager writes it into the
     production manifests' `## Version`, so nothing needs editing beforehand.
   - **Release title** and **notes**: whatever players should read. The notes
     become the CurseForge changelog.
   - **Set as a pre-release**: check it for `alpha` or `beta` tags (for example
     `v0.2.0-beta1`), which CurseForge lists as alpha or beta files; leave it
     unchecked for a full release.
   - Click **Publish release**. Saving a draft does not start a release.
3. Watch the **Release** run in the repository's **Actions** tab. The zip is
   attached to the release when it finishes. CurseForge may take a few minutes
   to review and list a new file.

Pushing a tag without publishing a release does nothing. Editing a published
release's notes later changes only the GitHub page, not CurseForge. If a run
fails before uploading, fix the cause, delete the release and its tag, and
publish again.
