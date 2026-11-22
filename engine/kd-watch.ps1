# Live update: makes the open Kdenlive re-read the project when the AI changes the file.
#   Start:  powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File engine\kd-watch.ps1 -Project projects\<name>\<name>.kdenlive
#   Log:    engine\kd-watch.log      Stop: delete engine\kd-watch.run or end the process.
# An AI write is recognised by the stamp Save-Kdp leaves, not by timing. For other writers: a change right after
# the Save button went enabled -> disabled is the save Kdenlive did itself; any other change is an outside write.
# A failed reload is retried. An AI version that meets unsaved user edits is kept in .kdp-history\<project>\conflict.
param([Parameter(Mandatory)][string]$Project, [int]$IntervalMs = 700, [string]$Log, [string]$RunFile)
. (Join-Path $PSScriptRoot 'tools\kd-ui.ps1')
$engine = $PSScriptRoot
if (-not $Log) { $Log = Join-Path $engine 'kd-watch.log' }
if (-not $RunFile) { $RunFile = Join-Path $engine 'kd-watch.run' }
$Project = (Resolve-Path $Project).Path
Set-Content $RunFile $PID
function Write-WatchLog([string]$m) { Add-Content -Path $Log -Value ("{0:yyyy-MM-dd HH:mm:ss} {1}" -f (Get-Date), $m) -Encoding UTF8 }

$script:button = $null
$script:buttonWindow = [IntPtr]::Zero
function Get-WatchState {
    try {
        $w = Find-KdWindow $Project
        if (-not $w) { $script:button = $null; return 'closed' }
        if (-not $script:button -or $script:buttonWindow -ne $w.Handle) {
            $script:buttonWindow = $w.Handle
            $script:button = Find-KdSaveButton ($script:KdAE::FromHandle($w.Handle))
        }
        if ($script:button) { return $(if ($script:button.Current.IsEnabled) { 'edited' } else { 'clean' }) }
    } catch { }
    $script:button = $null
    return 'busy'
}
function Save-ConflictCopy {
    $dir = Join-Path (Get-KdStateDir $Project) 'conflict'
    [void][IO.Directory]::CreateDirectory($dir)
    $copy = Join-Path $dir ((Get-Date).ToString('yyyyMMdd-HHmmss') + '.kdenlive')
    Copy-Item -LiteralPath $Project $copy -Force
    return $copy
}

Write-WatchLog "watch start pid=$PID project=$Project"
$lastHash = Get-KdHash $Project
$prev = Get-WatchState
$savedUntil = [datetime]::MinValue
$failHash = ''; $failures = 0; $retryAt = [datetime]::MinValue
while (Test-Path $RunFile) {
    Start-Sleep -Milliseconds $IntervalMs
    $state = Get-WatchState
    if ($prev -eq 'edited' -and $state -eq 'clean') { $savedUntil = (Get-Date).AddSeconds(5) }
    if ($state -ne 'busy') { $prev = $state }
    $h = Get-KdHash $Project
    if (-not $h -or $h -eq $lastHash -or $state -eq 'busy' -or (Get-Date) -lt $retryAt) { continue }
    Start-Sleep -Milliseconds 300
    if ((Get-KdHash $Project) -ne $h) { continue }
    $isAi = $h -eq (Get-KdWriteStamp $Project)
    $state = Get-WatchState
    if ($state -eq 'busy') { continue }
    if ($state -eq 'closed') { Write-WatchLog 'file changed; Kdenlive not running'; $lastHash = $h; continue }
    if (-not $isAi -and (($prev -eq 'edited' -and $state -eq 'clean') -or (Get-Date) -lt $savedUntil)) {
        Write-WatchLog 'kdenlive saved the project (user edits now on disk)'; $lastHash = $h; $prev = $state; continue
    }
    if ($state -eq 'edited') {
        Write-WatchLog "CONFLICT: file changed while Kdenlive has unsaved edits; not reloading. Copy kept: $(Save-ConflictCopy). Run kd-pull.ps1 and re-apply the change."
        $lastHash = $h; continue
    }
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $engine 'kd-reload.ps1') -Project $Project | Out-String
    $code = $LASTEXITCODE
    Write-WatchLog "AI change -> reload: exit $code $($out.Trim())"
    $script:button = $null
    $prev = 'clean'
    if ($code -eq 0 -or $code -eq 3) { $lastHash = $h; $failures = 0; $retryAt = [datetime]::MinValue; continue }
    if ($code -eq 2) { Write-WatchLog "CONFLICT: the user edited before the reload. Copy kept: $(Save-ConflictCopy)"; $lastHash = $h; continue }
    if ($failHash -ne $h) { $failHash = $h; $failures = 0 }
    $failures++
    if ($failures -ge 3) {
        Write-WatchLog "RELOAD FAILED $failures times: the open Kdenlive still shows the old version. Run kd-reload.ps1 when it is free."
        $lastHash = $h
    } else { $retryAt = (Get-Date).AddSeconds(5 * $failures) }
}
Write-WatchLog 'watch stop'
