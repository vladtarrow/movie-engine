# Re-reads the project in the running Kdenlive (File > Revert). Exit 0 only when the reload was CONFIRMED; a big project takes about 2 minutes, several times longer on a busy machine.
# Exit codes: 0 confirmed, 2 unsaved edits (nothing done), 3 not running, 4 failed or not confirmed.
param([string]$Project, [int]$TimeoutSec = 1500)
$ErrorActionPreference = 'Stop'
try {
    . (Join-Path $PSScriptRoot 'tools\kd-ui.ps1')
    $lock = $null
    if ($Project) { $Project = (Resolve-Path $Project).Path; $lock = Enter-KdLock $Project }
    try { $r = Invoke-KdReload $Project $TimeoutSec } finally { Exit-KdLock $lock }
} catch { Write-Output "FAILED: $($_.Exception.Message)"; exit 4 }
Write-Output $r.Message
exit $r.Code
