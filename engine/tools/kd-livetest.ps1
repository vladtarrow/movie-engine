# Live-update test against a real Kdenlive on an invisible desktop: pull, reload, watcher and their races.
# The "user's edit" is made with UI Automation inside that test Kdenlive (bin button "Create Folder").
#   powershell -NoProfile -ExecutionPolicy Bypass -File engine\tools\kd-livetest.ps1 [-Big <large project>] [-Report docs\proof\live.txt]
# -Big also reloads a COPY of a large project, where UI Automation's Invoke times out (the false-success case).
param([string]$Big, [string]$Report, [int]$TimeoutSec = 5400, [switch]$Inner)
if ($Big) { $Big = (Resolve-Path $Big).Path }
if ($Report -and -not [IO.Path]::IsPathRooted($Report)) { $Report = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) $Report }
if (-not $Inner) {
    $argList = '-Inner'
    if ($Big) { $argList += " -Big '$($Big.Replace("'", "''"))'" }
    if ($Report) { $argList += " -Report '$($Report.Replace("'", "''"))'" }
    & (Join-Path $PSScriptRoot 'kd-hidden.ps1') -Script $PSCommandPath -ArgList $argList -TimeoutSec $TimeoutSec
    exit $LASTEXITCODE
}
. (Join-Path $PSScriptRoot 'kd-testenv.ps1')
$engine = $script:KdTestEngine
$kit = Join-Path (Split-Path $engine -Parent) 'materials\aigenerated\test-kit'
$dir = New-KdTestDir 'live'
$project = Join-Path $dir 'livetest.kdenlive'
$log = Join-Path $dir 'watch.log'
$runFile = Join-Path $dir 'watch.run'
$script:lines = New-Object System.Collections.ArrayList
function Note([string]$name, [bool]$ok, [string]$detail) {
    $state = if ($ok) { 'PASS' } else { 'FAIL' }
    [void]$script:lines.Add("$state  $name :: $($detail.Trim() -replace '\s+', ' ')")
}
function Run-Script([string]$name, [string[]]$a) {
    $o = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $engine $name) @a 2>&1 | ForEach-Object { "$_" } | Out-String
    return @{ Code = $LASTEXITCODE; Out = $o }
}
function Kdp { Run-Script 'kdp.ps1' ([string[]]$args + @('-Project', $project)) }
function Wait-True([scriptblock]$probe, [int]$sec) {
    $clock = [Diagnostics.Stopwatch]::StartNew()
    while ($clock.Elapsed.TotalSeconds -lt $sec) { if (& $probe) { return $true }; Start-Sleep -Milliseconds 700 }
    return $false
}
function Count-Log([string]$pattern) { if (Test-Path $log) { @(Select-String -Path $log -Pattern $pattern).Count } else { 0 } }
function Edit-LikeUser {
    $button = Find-KdNamed ($script:KdAE::FromHandle($script:kd.Main.Handle)) 'Folder'
    try { $button.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke() } catch { }
    return (Wait-True { (Get-KdUnsaved $script:kd.Main) -eq $true } 15)
}
function Count-Folders { @(Select-String -Path $project -Pattern 'kdenlive:folder\.-1\.').Count }

$script:kd = $null
$watch = $null
try {
    [void](Kdp new)
    [void](Kdp bin-add -File "$kit\test-video-horizontal.mp4" -Name h)
    [void](Kdp bin-color -Color '#ff0000' -Name red -Seconds 30)
    [void](Kdp add -Bin red -Track V1 -At 0 -Dur 2)
    $script:kd = Start-KdTest $dir $project
    Note 'test Kdenlive loads the project' (-not $script:kd.Why) "$($script:kd.Why) length=$(Get-KdTestLength $script:kd.Main)"
    if ($script:kd.Why) { throw 'cannot continue' }

    $watch = Start-Process powershell -PassThru -WindowStyle Hidden -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$engine\kd-watch.ps1`" -Project `"$project`" -Log `"$log`" -RunFile `"$runFile`""
    [void](Wait-True { (Count-Log 'watch start') -gt 0 } 30)
    Start-Sleep -Seconds 2

    $r = Kdp add -Bin red -Track V1 -At 2 -Dur 3
    $ok = Wait-True { (Get-KdTestLength $script:kd.Main) -match '^00:00:04:29' } 90
    Note 'AI edit appears in the open editor' ($r.Code -eq 0 -and $ok) "kdp exit $($r.Code) $($r.Out) length=$(Get-KdTestLength $script:kd.Main)"
    $ok = Wait-True { (Count-Log 'reload: exit 0 reload confirmed') -ge 1 } 30
    Note 'watcher reports a confirmed reload' $ok "confirmed=$(Count-Log 'reload confirmed')"

    $r1 = Kdp add -Bin red -Track V1 -At 5 -Dur 1
    $r2 = Kdp add -Bin red -Track V1 -At 6 -Dur 1
    $ok = Wait-True { (Get-KdTestLength $script:kd.Main) -match '^00:00:06:29' } 120
    Note 'two AI edits in a row both appear' ($r1.Code -eq 0 -and $r2.Code -eq 0 -and $ok) "exit $($r1.Code),$($r2.Code) $($r1.Out) $($r2.Out) length=$(Get-KdTestLength $script:kd.Main)"
    Start-Sleep -Seconds 4

    $edited = Edit-LikeUser
    Note 'user edit makes the document modified' $edited ''
    $before = Get-KdHash $project
    $r = Run-Script 'kd-reload.ps1' @('-Project', $project)
    Note 'reload refuses while the user has unsaved edits' ($r.Code -eq 2 -and (Get-KdUnsaved $script:kd.Main) -eq $true -and (Get-KdHash $project) -eq $before) "exit $($r.Code) $($r.Out)"

    # The old watcher took an AI write that came within 5 s of the pull's save for that save, and did not reload.
    $folders = Count-Folders
    $r = Kdp add -Bin red -Track V1 -At 7 -Dur 2
    Note 'AI command saves the user edit first and keeps it' ($r.Code -eq 0 -and (Count-Folders) -gt $folders) "exit $($r.Code) $($r.Out) folders $folders -> $(Count-Folders)"
    $ok = Wait-True { (Get-KdTestLength $script:kd.Main) -match '^00:00:08:29' } 120
    Note 'AI write right after a save still reloads' $ok "length=$(Get-KdTestLength $script:kd.Main)"
    Start-Sleep -Seconds 4

    [void](Edit-LikeUser)
    $folders = Count-Folders
    $r = Kdp info
    Note 'reading commands see unsaved user edits' ($r.Code -eq 0 -and (Count-Folders) -gt $folders) "exit $($r.Code) folders $folders -> $(Count-Folders)"
    Start-Sleep -Seconds 8

    [void](Edit-LikeUser)
    $r = Run-Script 'kdp.ps1' @('guide-add', '-At', '1', '-Text', 'forced', '-NoPull', '-Project', $project)
    $ok = Wait-True { (Count-Log 'CONFLICT') -ge 1 } 30
    $kept = @(Get-ChildItem (Join-Path (Get-KdStateDir $project) 'conflict') -Filter *.kdenlive -ErrorAction SilentlyContinue).Count
    Note 'conflict: user edits stay, AI version is kept' ($ok -and $kept -ge 1 -and (Get-KdUnsaved $script:kd.Main) -eq $true) "conflict logged=$ok copies=$kept kdp exit $($r.Code)"

    $r = Run-Script 'kd-pull.ps1' @('-Project', $project)
    Note 'pull saves and confirms' ($r.Code -eq 0 -and (Get-KdUnsaved $script:kd.Main) -eq $false) "exit $($r.Code) $($r.Out)"
    Start-Sleep -Seconds 6
    $r = Run-Script 'kd-reload.ps1' @('-Project', $project)
    Note 'manual reload is confirmed' ($r.Code -eq 0 -and $r.Out -match 'confirmed') "exit $($r.Code) $($r.Out)"

    Remove-Item $runFile -ErrorAction SilentlyContinue
    [void]$watch.WaitForExit(15000)
    Stop-KdTest $script:kd; $script:kd = $null
    $r = Run-Script 'kd-reload.ps1' @('-Project', $project)
    Note 'no Kdenlive: reload says so instead of success' ($r.Code -eq 3) "exit $($r.Code)"

    if ($Big) {
        $project = Join-Path $dir 'bigcopy.kdenlive'
        Copy-Item -LiteralPath $Big $project
        if (Test-Path -LiteralPath "$Big.ass") { Copy-Item -LiteralPath "$Big.ass" "$project.ass" }
        $source = Get-KdHash $Big
        $script:kd = Start-KdTest $dir $project 2100
        Note 'big project copy loads' (-not $script:kd.Why) "$($script:kd.Why)"
        if (-not $script:kd.Why) {
            $old = Get-KdTimelineId $script:kd.Main
            $clock = [Diagnostics.Stopwatch]::StartNew()
            $r = Run-Script 'kd-reload.ps1' @('-Project', $project)
            $new = Get-KdTimelineId $script:kd.Main
            Note 'big project: success is reported only after the real reload' ($r.Code -eq 0 -and $new -and $new -ne $old) ("exit {0} after {1:N0} s {2}" -f $r.Code, $clock.Elapsed.TotalSeconds, $r.Out)
            $r = Run-Script 'kd-reload.ps1' @('-Project', $project, '-TimeoutSec', '15')
            Note 'a reload that cannot be confirmed in time is a failure' ($r.Code -eq 4) "exit $($r.Code) $($r.Out)"
        }
        Note 'the real big project was not touched' ((Get-KdHash $Big) -eq $source) ''
    }
} catch {
    Note 'test run' $false "$($_.Exception.Message) $($_.InvocationInfo.PositionMessage)"
} finally {
    if (Test-Path $log) { $watchLog = @(Get-Content $log -Encoding UTF8) } else { $watchLog = @() }
    Stop-KdTest $script:kd
    if ($watch -and -not $watch.HasExited) { $watch.Kill() }
    $fail = @($script:lines | Where-Object { $_ -like 'FAIL*' }).Count
    $all = @("live-update test, $(Get-Date -Format 'yyyy-MM-dd HH:mm')", "PASS $($script:lines.Count - $fail)  FAIL $fail", '') + $script:lines + @('', '--- watcher log') + ($watchLog -replace [regex]::Escape($dir), '<sandbox>')
    $all
    if ($Report) { [IO.File]::WriteAllLines($Report, [string[]]$all, (New-Object Text.UTF8Encoding($false))) }
    Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
}
if ($fail) { exit 1 }
exit 0
