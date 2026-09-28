# Isolated Windows development install

The development add-on is a directory junction named
`AsgardsGuildTitheDev`. It points directly at the Git checkout while remaining
separate from the production `AsgardsGuildTithe` directory managed by
CurseForge.

Production and development use separate manifests, SavedVariables, Settings
identifiers, and slash commands:

| | Production | Development |
| --- | --- | --- |
| Folder | `AsgardsGuildTithe` | `AsgardsGuildTitheDev` |
| Manifest | `AsgardsGuildTithe_Camelot.toc` | `AsgardsGuildTitheDev_Camelot.toc` |
| SavedVariables | `AsgardsGuildTitheDB` | `AsgardsGuildTitheDevDB` |
| Command | `/agt` | `/agtdev` |

## One-time installation

From PowerShell in the checkout:

```powershell
cd ~/Projects/wow-guild-tithe
./tools/Install-Dev.ps1
```

The default WoW root is
`C:\Program Files (x86)\World of Warcraft\_classic_beta_`. Pass a different
client directory when needed:

```powershell
./tools/Install-Dev.ps1 -WowRoot "D:\World of Warcraft\_classic_beta_"
```

The installer derives the repository path from its own location. It only
creates the junction under `Interface\AddOns`; it does not edit repository
files or change permissions. It is safe to run repeatedly and refuses to
replace a real directory or a junction targeting another checkout.

## Updating

The junction makes the checkout the installed development add-on, so there is
no copy or deployment step after installation:

```powershell
cd ~/Projects/wow-guild-tithe
git pull --ff-only
git status --short
```

`git status --short` should print nothing. Routine stashing is neither required
nor expected; investigate any changed files before hiding them. Use `/reload`
for Lua-only changes and fully restart WoW after manifest changes.

Keep the CurseForge-managed production directory separate. Although data and
commands are isolated, enable only one variant at a time so future event-driven
accounting cannot process the same game event twice.
