# Opens the project Kdenlive had open last (the root "open-last-project.cmd" runs this).
# Kdenlive (KRecentFilesAction) appends the newest file at the end of [Recent Files], so the highest FileN is the last one.
# A project that no longer exists is skipped; with none left Kdenlive starts empty.
#   powershell -NoProfile -ExecutionPolicy Bypass -File engine\tools\kd-open-last.ps1 [-ProfileDir <dir>] [-DryRun]
param([string]$ProfileDir, [switch]$DryRun)
$ErrorActionPreference = 'Stop'
$engine = Split-Path $PSScriptRoot -Parent
if (-not $ProfileDir) { $ProfileDir = Join-Path $engine 'profile-kdenlive' }
$rc = [IO.Path]::Combine($ProfileDir, 'AppData', 'Local', 'kdenliverc')

$last = $null
if (Test-Path -LiteralPath $rc) {
    $inRecent = $false
    $files = @{}
    foreach ($line in [IO.File]::ReadAllLines($rc)) {
        if ($line -match '^\[') { $inRecent = $line -eq '[Recent Files]'; continue }
        if ($inRecent -and $line -match '^File(\d+)(?:\[\$e\])?=(.+)$') { $files[[int]$matches[1]] = $matches[2].Replace('$$', '$') }
    }
    foreach ($n in ($files.Keys | Sort-Object -Descending)) {
        $path = $files[$n].Replace('/', '\')
        if ($path -like '*.kdenlive' -and (Test-Path -LiteralPath $path -PathType Leaf)) { $last = $path; break }
    }
}

if ($DryRun) { if ($last) { "last project: $last" } else { 'no project to open: Kdenlive would start empty' }; exit 0 }

if (-not $last) {
    . (Join-Path $PSScriptRoot 'kd-state.ps1')
    $exe = Join-Path $engine 'Kdenlive\kdenlive-26.08.3_standalone\bin\kdenlive.exe'
    [void](Start-KdDetached $exe '' $ProfileDir -Normal)
    'no project in the recent list: Kdenlive started empty'
    exit 0
}
# a copied or moved folder: write its new place into the project first (as engine\kdenlive.cmd does)
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'kd-rebase.ps1') -Project $last | Out-Null
if ($LASTEXITCODE -ne 0) { throw "could not update the project folder inside $last" }
& (Join-Path $PSScriptRoot 'kd-open.ps1') -Project $last -ProfileDir $ProfileDir -Normal
exit $LASTEXITCODE
