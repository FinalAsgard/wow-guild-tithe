# Isolated Windows development install

The development add-on is a directory junction named
`AsgardsGuildTitheDev`. It points directly at the Git checkout while remaining
separate from the production `AsgardsGuildTithe` directory managed by
CurseForge. The same checkout serves both supported clients: each client loads
only its own development manifest from the junction.

Production and development use separate manifests, SavedVariables, Settings
identifiers, and slash commands on both clients:

| | Production | Development |
| --- | --- | --- |
| Folder | `AsgardsGuildTithe` | `AsgardsGuildTitheDev` |
| Forever manifest | `AsgardsGuildTithe_Camelot.toc` | `AsgardsGuildTitheDev_Camelot.toc` |
| Retail manifest | `AsgardsGuildTithe_Mainline.toc` | `AsgardsGuildTitheDev_Mainline.toc` |
| SavedVariables | `AsgardsGuildTitheDB` | `AsgardsGuildTitheDevDB` |
| Command | `/agt` | `/agtdev` |

The long aliases are `/asgardstithe` and `/asgardstithedev`. Each WoW
installation keeps its own SavedVariables, so Forever and Retail data never
mix.

## One-time installation

From PowerShell in the checkout, choose the client with `-Client`:

```powershell
cd ~/Projects/wow-guild-tithe
./tools/Install-Dev.ps1                 # WoW Forever (default)
./tools/Install-Dev.ps1 -Client Retail  # WoW Retail
```

| `-Client` | Default client directory |
| --- | --- |
| `Forever` (default) | `C:\Program Files (x86)\World of Warcraft\_classic_beta_` |
| `Retail` | `C:\Program Files (x86)\World of Warcraft\_retail_` |

If WoW is installed somewhere else, pass the `World of Warcraft` folder with
`-WowInstallRoot`, and the client directory is still chosen by `-Client`:

```powershell
./tools/Install-Dev.ps1 -Client Retail -WowInstallRoot "D:\World of Warcraft"
```

For an unusual layout, pass the exact client directory with `-WowRoot`. It
overrides the directory derived from `-Client`:

```powershell
./tools/Install-Dev.ps1 -Client Forever -WowRoot "D:\Games\WoW Forever"
```

To develop against both clients, run the installer once per client. Both
junctions point at the same checkout.

The installer derives the repository path from its own location and checks that
the requested client's development manifest exists. It only creates the
junction under `Interface\AddOns`; it does not edit repository files or change
permissions. It is safe to run repeatedly and refuses to replace a real
directory or a junction targeting another checkout.

The installer's behavior is covered by `tests/Install-Dev.Tests.ps1`, which CI
runs on Windows. Run it locally with `pwsh ./tests/Install-Dev.Tests.ps1`.

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
