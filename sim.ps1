#Requires -Version 7.0
<#
    Pawn <-> wowsims-turtle sim driver.

    WoW addons cannot access the network, so the loop is file based:

        game Lua  --(PawnSimDump saved variable on /reload)-->  sim.ps1 (PC)
        sim.ps1   --(rewrites sim\SimResults.lua)             -->  game Lua on /reload

    Usage (from the Pawn folder, in PowerShell 7+ / pwsh):
        .\sim.ps1                          # builds the import, runs the sim, writes results
        .\sim.ps1 -Iterations 1000
        .\sim.ps1 -SkipBrowser             # rebuild results from the last weights.json
        .\sim.ps1 -Headed                  # show the browser window while running
        .\sim.ps1 -Url <url>               # override the sim page
        .\sim.ps1 -Spec feral_druid        # force the spec (auto-detected from talents otherwise)

    Before running: in game open Pawn -> Sim tab -> "1. Export character",
    then type /reload once (that is when the export file is written to disk).
#>
[CmdletBinding()]
param(
    [string]$Scale,
    [int]$Iterations = 1000,
    [string]$Url,
    [string]$Spec,
    [switch]$SkipBrowser,
    [switch]$Headed
)

$ErrorActionPreference = 'Stop'

$SimDir = Join-Path $PSScriptRoot 'sim'
$GameRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$WorkDir = Join-Path $SimDir 'work'
$TemplatePath = Join-Path $SimDir 'template.json'
$ResultsPath = Join-Path $SimDir 'SimResults.lua'

# Account-level saved variables are stored in a file named after the addon FOLDER
# (this client writes WTF\Account\<account>\SavedVariables\Pawn.lua), so we search
# these candidates by content instead of relying on a file name.
$DumpGlobs = @(
    (Join-Path $GameRoot 'WTF\Account\*\SavedVariables\Pawn.lua')
    (Join-Path $GameRoot 'WTF\Account\*\SavedVariables\PawnSimDump.lua')
    (Join-Path $GameRoot 'WTF\Account\*\*\*\SavedVariables\Pawn.lua')
    (Join-Path $GameRoot 'WTF\Account\*\*\*\SavedVariables\PawnSimDump.lua')
)
$DumpPattern = 'PawnSimDump\s*=\s*"((?:[^"\\]|\\.)*)"'

function Info([string]$Message) { Write-Host "[sim] $Message" }
function Fail([string]$Message) { Write-Host "[sim] ERROR: $Message" -ForegroundColor Red; exit 1 }

# ---------------------------------------------------------------- 1. read dump
$DumpFile = $null
$Raw = $null
$Match = $null

$Candidates = $DumpGlobs | ForEach-Object { Get-ChildItem $_ -ErrorAction SilentlyContinue } |
    Sort-Object LastWriteTime -Descending
foreach ($Candidate in $Candidates) {
    $CandidateRaw = Get-Content $Candidate.FullName -Raw -ErrorAction SilentlyContinue
    if (-not $CandidateRaw) { continue }
    $CandidateMatch = [regex]::Match($CandidateRaw, $DumpPattern)
    if ($CandidateMatch.Success) {
        $DumpFile = $Candidate
        $Raw = $CandidateRaw
        $Match = $CandidateMatch
        break
    }
}

if (-not $Match) {
    Write-Host '[sim] ERROR: No character export found in the Pawn saved variables.' -ForegroundColor Red
    Write-Host ''
    Write-Host '[sim] Checklist:' -ForegroundColor Yellow
    Write-Host '  1. Pawn must be ENABLED in the AddOn list (character select screen -> AddOns).'
    Write-Host "  2. In game: Pawn -> Sim tab -> '1. Export character' (or /psim dump) - you"
    Write-Host "     should see a '[PawnSim] Character exported for sim...' message in chat."
    Write-Host '  3. Then type /reload once - this is when the file is written to disk.'
    Write-Host '  4. Run sim.ps1 again.'
    Write-Host ''
    if ($Candidates) {
        Write-Host '[sim] Pawn saved variable files found (newest first) - none contain an export:'
        foreach ($Candidate in $Candidates) { Write-Host ("  {0}  {1}" -f $Candidate.LastWriteTime, $Candidate.FullName) }
    }
    else {
        Write-Host '[sim] No Pawn saved variables exist at all - is the addon enabled?' -ForegroundColor Yellow
    }
    exit 1
}
Info "Reading $($DumpFile.FullName)"
Info "  (written $($DumpFile.LastWriteTime))"

# Undo the saved-variable string escaping (\\, \", \n, ...)
$Json = [regex]::Replace($Match.Groups[1].Value, '\\(.)', {
        param($m)
        switch ($m.Groups[1].Value) {
            'n' { "`n" }
            'r' { '' }
            't' { "`t" }
            default { $m.Groups[1].Value }
        }
    })

$Dump = $Json | ConvertFrom-Json
Info "Character: $($Dump.char.name) ($($Dump.char.class), $($Dump.char.race), level $($Dump.char.level))"

if ($Scale) { $Dump.scale = $Scale }
if (-not $Dump.scale) { $Dump.scale = 'Pawn value' }
Info "Target scale: $($Dump.scale)"

# ------------------------------------------------------------ 2. talents string
$TalentParts = @()
foreach ($Tab in $Dump.talents) {
    $TabString = -join ($Tab | ForEach-Object { [string]$_ })
    $TalentParts += ($TabString -replace '0+$', '')
}
$TalentsString = $TalentParts -join '-'
Info "Talents string: $TalentsString"

# Spec selection (used for the sim URL). Auto-detected from the talent points;
# pass -Spec to force one, e.g. -Spec feral_tank_druid.
$ClassSpecs = @{
    'ClassDruid'   = @('balance_druid', 'feral_druid', 'feral_tank_druid', 'restoration_druid')
    'ClassShaman'  = @('elemental_shaman', 'enhancement_shaman', 'restoration_shaman', 'warden_shaman')
    'ClassHunter'  = @('hunter')
    'ClassMage'    = @('mage')
    'ClassRogue'   = @('rogue')
    'ClassPaladin' = @('holy_paladin', 'protection_paladin', 'retribution_paladin')
    'ClassPriest'  = @('healing_priest', 'shadow_priest')
    'ClassWarlock' = @('warlock')
    'ClassWarrior' = @('warrior', 'tank_warrior')
}

$SpecUrl = $Url
if (-not $SpecUrl) {
    $ClassToken = [string]$Dump.char.classToken
    $Available = $ClassSpecs[$ClassToken]
    if (-not $Available) { Fail "No sim is known for class token '$ClassToken'." }

    $SpecName = $Spec
    if ($SpecName) {
        if ($Available -notcontains $SpecName) {
            Fail "-Spec '$SpecName' is not valid for $ClassToken. Available: $($Available -join ', ')."
        }
        Info "Using spec from -Spec: $SpecName"
    }
    elseif ($Available.Count -eq 1) {
        $SpecName = $Available[0]
    }
    else {
        # Talent trees are in the client's tab order; the tree with the most
        # points wins.
        $Totals = @()
        foreach ($Tab in $Dump.talents) {
            $Sum = 0
            foreach ($Rank in $Tab) { $Sum += [int]$Rank }
            $Totals += $Sum
        }
        $MaxTree = 1
        for ($i = 1; $i -lt $Totals.Count; $i++) {
            if ($Totals[$i] -gt $Totals[$MaxTree - 1]) { $MaxTree = $i + 1 }
        }
        Info "Talent points per tree: $($Totals -join ' / ') (dominant tree: $MaxTree)"

        switch ($ClassToken) {
            'ClassWarrior' { $SpecName = if ($MaxTree -eq 3) { 'tank_warrior' } else { 'warrior' } }
            'ClassPaladin' { $SpecName = switch ($MaxTree) { 1 { 'holy_paladin' } 2 { 'protection_paladin' } default { 'retribution_paladin' } } }
            'ClassPriest'  { $SpecName = if ($MaxTree -eq 3) { 'shadow_priest' } else { 'healing_priest' } }
            'ClassDruid'   { $SpecName = switch ($MaxTree) { 1 { 'balance_druid' } 2 { 'feral_druid' } default { 'restoration_druid' } } }
            'ClassShaman'  { $SpecName = switch ($MaxTree) { 1 { 'elemental_shaman' } 2 { 'enhancement_shaman' } default { 'restoration_shaman' } } }
            default        { $SpecName = $Available[0] }
        }
        Info "Detected spec: $SpecName (override with -Spec <slug>; available: $($Available -join ', '))"
    }

    $SpecUrl = "https://isfir.github.io/wowsims-turtle/$SpecName/"
}
if (-not $SpecName) {
    $SpecName = ($SpecUrl.TrimEnd('/') -split '/')[-1]
}
Info "Sim URL: $SpecUrl"

# ----------------------------------------------------------- 3. build import JSON
$Template = Get-Content $TemplatePath -Raw | ConvertFrom-Json

$Template.player.name = if ($Dump.char.name) { [string]$Dump.char.name } else { 'Player' }
if ($Dump.char.raceToken) { $Template.player.race = [string]$Dump.char.raceToken }
if ($Dump.char.classToken) { $Template.player.class = [string]$Dump.char.classToken }
$Template.player.talentsString = $TalentsString

# The template ships with enhancement-shaman flavoured defaults. Strip the
# shaman-only bits for other specs so their import stays clean.
if ($SpecName -ne 'enhancement_shaman') {
    $Template.player.PSObject.Properties.Remove('enhancementShaman')
    $Template.player.PSObject.Properties.Remove('stormstrikeFrequency')
    $Template.player.PSObject.Properties.Remove('stormstrikeNatureAttackerFrequency')
}
if ($SpecName -notlike '*shaman') {
    # Windfury imbue only exists for shaman; other classes use their own
    # temporary weapon enchants (poisons/stones), which the sim defaults to.
    $Template.player.consumes.PSObject.Properties.Remove('mainHandImbue')
}

$Items = @()
foreach ($Entry in $Dump.items) {
    $ItemId = [int]$Entry[1]
    $EnchantId = [int]$Entry[2]
    if ($ItemId -gt 0) {
        if ($EnchantId -gt 0) { $Items += [pscustomobject]@{ id = $ItemId; enchant = $EnchantId } }
        else { $Items += [pscustomobject]@{ id = $ItemId } }
    }
    else { $Items += [pscustomobject]@{} }
}
$Template.player.equipment.items = $Items

if (-not (Test-Path $WorkDir)) { New-Item -ItemType Directory -Path $WorkDir | Out-Null }
$ImportPath = Join-Path $WorkDir 'import.json'
$WeightsPath = Join-Path $WorkDir 'weights.json'
$Template | ConvertTo-Json -Depth 40 | Set-Content -Path $ImportPath -Encoding utf8
Info "Wrote $ImportPath"

if ($SkipBrowser -and -not (Test-Path $WeightsPath)) {
    Info "SkipBrowser set - import the JSON above into the sim manually, then rerun without -SkipBrowser."
    exit 0
}

if ($SkipBrowser) {
    Info "SkipBrowser set - reusing the existing $WeightsPath to rebuild SimResults.lua."
}
else {
    # ------------------------------------------------------- 4. run the web sim
    $Node = Get-Command node -ErrorAction SilentlyContinue
    if (-not $Node) { Fail 'Node.js was not found in PATH. Install Node.js LTS from https://nodejs.org/.' }

    Push-Location $SimDir
    try {
        if (-not (Test-Path (Join-Path $SimDir 'node_modules\playwright-core'))) {
            Info 'Installing runner dependencies (playwright-core)...'
            & npm install --no-fund --no-audit | Out-Host
            if ($LASTEXITCODE -ne 0) { Fail 'npm install failed.' }
        }

        $RunnerArgs = @('runner.mjs', '--input', $ImportPath, '--output', $WeightsPath, '--url', $SpecUrl, '--iterations', $Iterations)
        if ($Headed) { $RunnerArgs += '--headed' }
        foreach ($Entry in $Dump.items) {
            if ([int]$Entry[0] -eq 16 -and [int]$Entry[1] -gt 0 -and $Entry[3]) {
                $RunnerArgs += @('--expect', [string]$Entry[3])
                break
            }
        }

        Info 'Running the sim (this can take a few minutes)...'
        & node @RunnerArgs | Out-Host
        if ($LASTEXITCODE -ne 0) { Fail "Sim runner failed (exit code $LASTEXITCODE)." }
    }
    finally {
        Pop-Location
    }
}

# ------------------------------------------------- 5. write sim\SimResults.lua
$WeightsDoc = Get-Content $WeightsPath -Raw | ConvertFrom-Json
if (-not $WeightsDoc.weights) { Fail "No 'weights' property found in $WeightsPath." }
$Weights = $WeightsDoc.weights

$Map = [ordered]@{
    'Strength'            = @('Strength')
    'Agility'             = @('Agility')
    'Intellect'           = @('Intellect')
    'Spirit'              = @('Spirit')
    'Spell Power'         = @('SpellPower')
    'Spell Damage'        = @('SpellDamage')
    'Healing Power'       = @('Healing')
    'Fire Damage'         = @('FireSpellDamage')
    'Frost Damage'        = @('FrostSpellDamage')
    'Nature Damage'       = @('NatureSpellDamage')
    'Shadow Damage'       = @('ShadowSpellDamage')
    'Arcane Damage'       = @('ArcaneSpellDamage')
    'Holy Damage'         = @('HolySpellDamage')
    'Spell Hit'           = @('SpellHit')
    'Spell Crit'          = @('SpellCrit')
    'Mana Per 5 Sec'      = @('Mp5')
    'Attack Power'        = @('Ap')
    'Melee Hit'           = @('Hit')
    'Melee Crit'          = @('Crit')
    'Melee Attack Speed'  = @('Haste')
    'Attack Speed'        = @('Haste')
    'Ranged Attack Speed' = @('Haste')
    'Main Hand DPS'       = @('MainHandDps', 'TwoHandDps')
    'Off Hand DPS'        = @('OffHandDps')
    'Ranged DPS'          = @('RangedDps')
}

$LuaStatValues = [ordered]@{}
$Summary = New-Object System.Collections.Generic.List[object]
$Unmapped = New-Object System.Collections.Generic.List[string]
foreach ($Prop in $Weights.PSObject.Properties) {
    if (-not $Map.Contains($Prop.Name)) { $Unmapped.Add($Prop.Name); continue }
    $Value = [double]$Prop.Value
    if ([double]::IsNaN($Value) -or [double]::IsInfinity($Value)) { continue }

    $Summary.Add([pscustomobject]@{ SimStat = $Prop.Name; Value = $Value; PawnKeys = ($Map[$Prop.Name] -join ', ') })
    foreach ($PawnKey in $Map[$Prop.Name]) { $LuaStatValues[$PawnKey] = $Value }
}
if ($Unmapped.Count -gt 0) {
    Info "Sim stats without a Pawn equivalent (skipped): $($Unmapped -join ', ')"
}

$LuaStats = New-Object System.Collections.Generic.List[string]
foreach ($PawnKey in $LuaStatValues.Keys) {
    $LuaStats.Add(('  ["{0}"] = {1},' -f $PawnKey, $LuaStatValues[$PawnKey].ToString([System.Globalization.CultureInfo]::InvariantCulture)))
}

$Stamp = (Get-Date).ToString('s')
$Source = ($SpecUrl -replace '^https?://[^/]+/', '') -replace '/$', ''
$LuaLines = @(
    "-- AUTO-GENERATED by sim.ps1 on $Stamp - do not edit by hand."
    'PawnSimResults = {'
    "  source = `"$Source`","
    "  generatedAt = `"$Stamp`","
    "  dps = 0,"
    '  stats = {'
) + $LuaStats + @(
    '  },'
    '}'
    ''
)
Set-Content -Path $ResultsPath -Value $LuaLines -Encoding Ascii
Info "Wrote $ResultsPath"

Write-Host ''
Write-Host 'Simulated stat weights (AP = 1.0):'
$Summary | Sort-Object -Property Value -Descending | Format-Table -AutoSize | Out-Host
Write-Host ''
Info "Done. In game: /reload, then Pawn -> Sim tab -> '2. Apply sim results' (target scale: $($Dump.scale))."
Info "Raw weights: $WeightsPath"
