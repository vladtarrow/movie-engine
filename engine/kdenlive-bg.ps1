# Starts Kdenlive minimized, with the in-project profile, without taking focus.
# Usage: powershell -File engine\kdenlive-bg.ps1 [project.kdenlive]
# With a project it returns when the project is loaded (exit 0) or could not be confirmed (exit 4); see tools\kd-open.ps1.
param([string]$Project)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'tools\kd-state.ps1')
$prof = Join-Path $PSScriptRoot 'profile-kdenlive'
$exe = Join-Path $PSScriptRoot 'Kdenlive\kdenlive-26.08.3_standalone\bin\kdenlive.exe'
$arguments = ''
if ($Project) {
    $Project = (Resolve-Path $Project).Path
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'tools\kd-rebase.ps1') -Project $Project | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "could not update the project folder inside $Project" }
    if ($Project -like '*.kdenlive') {
        & (Join-Path $PSScriptRoot 'tools\kd-open.ps1') -Project $Project
        exit $LASTEXITCODE
    }
    $arguments = "`"$Project`""
}
# A leftover crash flag makes Kdenlive wait for an answer on its splash screen, which nobody sees when minimized.
$flag = Join-Path $prof 'AppData\Local\Temp\kdenlivelock'
if (-not (Get-Process kdenlive -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $exe }) -and (Test-Path $flag)) { Remove-Item $flag -Force }
$p = Start-KdDetached $exe $arguments $prof
"started kdenlive pid $($p.Id)"
