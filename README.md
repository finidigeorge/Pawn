# Pawn for Turtle/Octo/Capy ? WoW (Vanilla 1.12)

A port of the popular item valuation addon **Pawn** (originally for TBC 2.4.3) 

## Compatibility Fixes
- Fixed "Method 'GetItem' is nil" crashes when hovering non-item frames
- Resolved tooltip duplication bugs caused by other addons triggering multiple refreshes
- An attemt to make it compatible with Atlas-TW

## Installation
1. Download the repository
2. Rename the folder to `Pawn`
3. Move it to your `Interface/AddOns/` directory

## Usage
- Type `/pawn` in-game to open the configuration menu
- Use the **Scales** tab to create or import item weights
- Hover over any item to see its valuation based on your active scales

## Sim integration (stat weight generation)

Pawn can generate stat weights from **your** character using the
[wowsims-turtle](https://github.com/isfir/wowsims-turtle) web simulator. WoW
addons can't touch the network, so the game and the sim exchange data through
files on disk:

```
game                                 PC
---------------------------------------------------------------
Pawn -> Sim tab -> "1. Export"  -->  SavedVariables (PawnSimDump)
/reload (writes the file)
                                     .\sim.ps1
                                       reads the export, drives the web sim
                                       writes sim\SimResults.lua
/reload (loads the results)
Pawn -> Sim tab -> "2. Apply"   <--  weights land in your selected scale
```

### Usage

1. In game: Pawn window -> **Sim** tab, and pick the target scale on the
   **Scales** tab (the Sim tab always writes into the selected scale).
2. Click **1. Export character** (or `/psim dump`), then type `/reload` once.
3. From the addon folder in a PowerShell 7 (`pwsh`) terminal, run:

   ```powershell
   .\sim.ps1                    # 1000 iterations (default)
   .\sim.ps1 -Iterations 3000   # more accurate, slower
   .\sim.ps1 -Spec feral_druid  # force the spec slug
   .\sim.ps1 -SkipBrowser       # rebuild results from the last run
   .\sim.ps1 -Headed            # watch the browser
   ```

4. Back in game: `/reload`, then click **2. Apply sim results**
   (or `/psim apply`). Stats you're capped on come back as 0 and are removed
   from the scale.

### Requirements

- PowerShell 7+ (`pwsh`)
- Node.js LTS in `PATH` (runner dependencies install automatically on first run)
- Chrome or Edge installed
- Internet access to `isfir.github.io`


## Credits
Originally developed by Vger. Ported and optimized for Turtle WoW by Thornfury


## Known issues
- Trinkets and Set bonuses most like won't work unless they are straightforward stat increase
- Stat weights from `sim.ps1` are estimates, the specs in the
  wowsims-turtle fork are flagged unlaunched upstream and the item database is
  a ~Apr 2026 / 1.18.1 snapshot. For scales that don't sim well,
  https://wowsims.github.io/ remains a good source of values.
