<#
.SYNOPSIS
    Installs or updates SpeakStone (the base addon + chosen
    per-expansion voice packs) straight into your WoW AddOns folder.

.DESCRIPTION
    Run this fresh, or re-run it any time to pick up new voices -- it only
    re-downloads a pack when its content actually changed (checked by
    sha256 against the manifest), so a re-run after a small update is fast.

    One-line install/update:
        irm https://raw.githubusercontent.com/dandwhelan/SpeakStone-Quest-Reader-Main/main/Install-SpeakStone.ps1 | iex

    To pick specific expansions instead of everything:
        $env:SPEAKSTONE_PACKS = "Classic_Part1,Classic_Part2,Cataclysm_Part1"
        irm https://raw.githubusercontent.com/dandwhelan/SpeakStone-Quest-Reader-Main/main/Install-SpeakStone.ps1 | iex

.NOTES
    Safe to re-run. Never overwrites a pack in place -- state is tracked in
    QuestReaderAddon\.speakstone_manifest.json inside the AddOns folder.
#>

$ErrorActionPreference = "Stop"

$ManifestUrl = "https://pub-4540fb6ba9bb4cc3a33d41df5c9978bb.r2.dev/manifest.json"
$BaseUrl     = "https://pub-4540fb6ba9bb4cc3a33d41df5c9978bb.r2.dev"

function Find-AddonsDir {
    if ($env:SPEAKSTONE_ADDONS_DIR) { return $env:SPEAKSTONE_ADDONS_DIR }

    $candidates = @(
        "C:\Program Files (x86)\World of Warcraft\_retail_\Interface\AddOns",
        "C:\Program Files\World of Warcraft\_retail_\Interface\AddOns",
        "D:\World of Warcraft\_retail_\Interface\AddOns",
        "D:\Games\World of Warcraft\_retail_\Interface\AddOns"
    )
    foreach ($c in $candidates) {
        if (Test-Path $c) { return $c }
    }

    Write-Host "Could not auto-detect your WoW AddOns folder." -ForegroundColor Yellow
    $manual = Read-Host "Paste the full path to ...\_retail_\Interface\AddOns"
    if (-not (Test-Path $manual)) {
        throw "Path not found: $manual"
    }
    return $manual
}

function Get-Sha256 {
    param([string]$Path)
    (Get-FileHash -Path $Path -Algorithm SHA256).Hash.ToLower()
}

Write-Host "SpeakStone installer/updater" -ForegroundColor Cyan
Write-Host "========================================"

$AddonsDir = Find-AddonsDir
Write-Host "AddOns folder: $AddonsDir"

Write-Host "`nFetching manifest ..."
$manifest = Invoke-RestMethod -Uri $ManifestUrl

$stateDir = Join-Path $AddonsDir "QuestReaderAddon"
$statePath = Join-Path $stateDir ".speakstone_manifest.json"
$state = $null
if (Test-Path $statePath) {
    try { $state = Get-Content $statePath -Raw | ConvertFrom-Json } catch { $state = $null }
}

$tmpRoot = Join-Path $env:TEMP "speakstone_install_$(Get-Random)"
New-Item -ItemType Directory -Path $tmpRoot | Out-Null

function Install-Zip {
    param(
        [string]$Name,
        [string]$ZipFile,
        [string]$Sha256,
        [string]$TargetFolder
    )

    $prevSha = $null
    if ($state -and $state.installed.$Name) { $prevSha = $state.installed.$Name.sha256 }
    if ($prevSha -eq $Sha256 -and (Test-Path (Join-Path $AddonsDir $TargetFolder))) {
        Write-Host "  $Name -- up to date, skipping"
        return
    }

    Write-Host "  $Name -- downloading ..."
    $zipPath = Join-Path $tmpRoot "$Name.zip"
    Invoke-WebRequest -Uri "$BaseUrl/$ZipFile" -OutFile $zipPath

    $actualSha = Get-Sha256 $zipPath
    if ($actualSha -ne $Sha256) {
        throw "$Name -- checksum mismatch after download, aborting install for this pack"
    }

    $target = Join-Path $AddonsDir $TargetFolder
    if (Test-Path $target) {
        $backup = "$target.backup_$(Get-Date -Format yyyyMMdd-HHmmss)"
        Write-Host "    backing up existing install to $backup"
        Move-Item -Path $target -Destination $backup
    }

    $extractDir = Join-Path $tmpRoot "extract_$Name"
    Expand-Archive -Path $zipPath -DestinationPath $extractDir -Force
    Move-Item -Path $extractDir -Destination $target

    Write-Host "    installed -> $target" -ForegroundColor Green
    return $Sha256
}

# --- base addon (always installed/updated) ---
Write-Host "`nBase addon:"
$baseSha = Install-Zip -Name "base" -ZipFile $manifest.base.file `
    -Sha256 $manifest.base.sha256 -TargetFolder "QuestReaderAddon"

# --- pick packs ---
$availablePacks = $manifest.packs.PSObject.Properties.Name | Sort-Object

$selected = @()
if ($env:SPEAKSTONE_PACKS) {
    if ($env:SPEAKSTONE_PACKS -eq "All") {
        $selected = $availablePacks
    } else {
        $selected = $env:SPEAKSTONE_PACKS -split "," | ForEach-Object { $_.Trim() }
    }
} elseif ($state -and $state.selected_packs) {
    # re-run: keep whatever was chosen last time, no re-prompt
    $selected = $state.selected_packs
} else {
    Write-Host "`nAvailable voice packs:"
    $i = 1
    $indexMap = @{}
    foreach ($p in $availablePacks) {
        $sizeMb = [math]::Round($manifest.packs.$p.size / 1MB, 0)
        Write-Host ("  [{0}] {1} ({2} clips, {3} MB)" -f $i, $p, $manifest.packs.$p.clip_count, $sizeMb)
        $indexMap[$i] = $p
        $i++
    }
    Write-Host "`nEnter pack numbers separated by commas, or 'all' for everything:"
    $answer = Read-Host "Packs"
    if ($answer.Trim().ToLower() -eq "all") {
        $selected = $availablePacks
    } else {
        $selected = $answer -split "," | ForEach-Object {
            $n = $_.Trim()
            if ($indexMap.ContainsKey([int]$n)) { $indexMap[[int]$n] }
        } | Where-Object { $_ }
    }
}

if (-not $selected -or $selected.Count -eq 0) {
    Write-Host "No packs selected -- base addon only." -ForegroundColor Yellow
}

Write-Host "`nInstalling/updating $($selected.Count) pack(s):"
$installedShas = @{}
foreach ($p in $selected) {
    if (-not $manifest.packs.$p) {
        Write-Host "  $p -- not found in manifest, skipping" -ForegroundColor Yellow
        continue
    }
    $sha = Install-Zip -Name $p -ZipFile $manifest.packs.$p.file `
        -Sha256 $manifest.packs.$p.sha256 -TargetFolder "QuestReaderAddon_Pack_$p"
    if ($sha) { $installedShas[$p] = @{ sha256 = $sha } }
    elseif ($state -and $state.installed.$p) { $installedShas[$p] = $state.installed.$p }
}
if ($baseSha) { $installedShas["base"] = @{ sha256 = $baseSha } }
elseif ($state -and $state.installed.base) { $installedShas["base"] = $state.installed.base }

New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
@{
    installed      = $installedShas
    selected_packs = $selected
    updated        = (Get-Date -Format "o")
} | ConvertTo-Json -Depth 5 | Set-Content -Path $statePath -Encoding UTF8

Remove-Item -Path $tmpRoot -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "`nDone. Restart WoW (or /reload) to pick up the update." -ForegroundColor Cyan
Write-Host "Re-run this same command any time to check for new voices."
