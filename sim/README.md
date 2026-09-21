# Pawn <-> wowsims-turtle bridge

Turns the [wowsims-turtle](https://github.com/isfir/wowsims-turtle) Enhancement Shaman
simulator into a Pawn stat-weight generator for **your** character.

## Why this is a two-step loop

WoW addons cannot access the network, files, or processes (no sockets, no HTTP).
So the game and the sim talk through files:

```
game                                  PC
---------------------------------------------------------------
Pawn -> Sim tab -> "1. Export"   -->   SavedVariables\Pawn.lua (PawnSimDump)
      /reload (flushes it to disk)
                                       .\sim.ps1
                                         reads the dump
                                         runs the sim in a headless browser
                                         writes sim\SimResults.lua
      /reload (loads the results)
Pawn -> Sim tab -> "2. Apply"    <--   weights land in your scale
```

## Usage (in game)

1. Pawn window -> **Sim** tab.
2. Select the scale you want the weights to go into on the **Scales** tab
   (the Sim tab always targets the currently selected scale).
3. Click **1. Export character** (or `/psim dump`).
4. Type `/reload` once - this is when the export file is written to disk.

## Usage (PC)

From this folder (`Interface\AddOns\Pawn`) in a PowerShell 7 (`pwsh`) terminal:

```powershell
.\sim.ps1                    # 1000 iterations (default)
.\sim.ps1 -Iterations 1000   # more accurate, slower
.\sim.ps1 -SkipBrowser       # rebuild SimResults.lua from the last weights.json (no browser)
.\sim.ps1 -Headed            # watch what the bot does
.\sim.ps1 -Spec feral_druid  # override the auto-detected spec
```

Then in game: `/reload` and click **2. Apply sim results** (or `/psim apply`).
The simulated weights overwrite the target scale; stats you are capped on
(e.g. melee hit) come back as 0 and are removed from the scale.

## Requirements

- PowerShell 7+ (`pwsh`).
- Node.js LTS in PATH (for `playwright-core`, installed automatically).
- Chrome or Edge installed (the script auto-detects common paths;
  override with `$env:PW_CHANNEL='msedge'` or `--executable <path>`).
- Internet access for `isfir.github.io`.

## Files

| File | Purpose |
|---|---|
| `../sim.ps1` | main entry point (read dump -> import -> simulate -> write results) |
| `runner.mjs` | headless-browser automation of the sim site |
| `template.json` | sim configuration: buffs, debuffs, consumes, encounter (melee-flavoured defaults). **Edit this** to change what the sim assumes (e.g. no raid buffs, caster flasks). |
| `SimResults.lua` | written by `sim.ps1`, loaded by the addon on `/reload` |
| `work/import.json` | the character JSON that was imported into the sim |
| `work/weights.json` | raw sim output (EP values, AP = 1.0) |
| `work/import-sample.json` | sample character for testing the runner |

## Known caveats

- Every sim in this fork is marked "unlaunched" upstream (`launched_sims.ts`);
  the runner un-disables the buttons. Results are plausible but not officially
  validated - treat them as a very good estimate, not gospel.
- Item and enchant IDs must exist in the fork's Turtle item database
  (~Apr 2026 / 1.18.1). If the import verification fails, an item or enchant
  may be missing/renamed; check `work/import.json` and the sim console output.
- Weights depend on your gear, talents, buffs and the encounter in
  `template.json`; re-run when things change.
- All classes/specs from the fork are wired up. The spec is auto-detected from
  your talent points (dominant tree); force one with `-Spec <slug>` when the
  guess is wrong (e.g. feral cat vs `feral_tank_druid`, `warden_shaman`).
  Valid slugs: `balance_druid feral_druid feral_tank_druid restoration_druid
  elemental_shaman enhancement_shaman restoration_shaman warden_shaman hunter
  mage rogue holy_paladin protection_paladin retribution_paladin
  healing_priest shadow_priest warlock warrior tank_warrior`.
- `template.json` is flavoured for melee (enhancement shaman): physical
  consumes/elixirs and a Windfury imbue. For casters/healers consider editing
  the flask/elixirs/`mainHandImbue` entries. Weights stay relative and usable,
  but absolute EP will drift if the buff/consume assumptions don't fit.
- Stats the sim reports but Pawn does not know (e.g. `Spell Pen`, `Ranged AP`)
  are listed in the run output and skipped.
