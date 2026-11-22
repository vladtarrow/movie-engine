# Makes the running Kdenlive write the user's edits to the project file. No focus change, no keystrokes.
# Exit codes: 0 file is current, 3 Kdenlive with this project is not running, 4 could not be confirmed.
param([string]$Project, [int]$TimeoutSec = 600)
$ErrorActionPreference = 'Stop'
try {
    . (Join-Path $PSScriptRoot 'tools\kd-ui.ps1')
    $lock = $null
    if ($Project) { $Project = (Resolve-Path $Project).Path; $lock = Enter-KdLock $Project }
    try { $r = Invoke-KdPull $Project $TimeoutSec } finally { Exit-KdLock $lock }
} catch { Write-Output "FAILED: $($_.Exception.Message)"; exit 4 }
Write-Output $r.Message
exit $r.Code
