# Opens a project in a new Kdenlive the fast way and waits until it is loaded.
#
# Why not simply "kdenlive.exe project.kdenlive": with a file on the command line Kdenlive builds the whole timeline
# first and lays out its panels after that (ProjectManager::doOpenFile emits GUISetupDone last). Every panel button
# that changes then raises a UI Automation event, and Qt walks every timeline item for each of them. On a project
# with ~1000 clips that added about 10 minutes (stack samples, 2026-11-22). Started without a file, Kdenlive lays
# out the panels over an empty timeline at once; the project is then opened from File > Recent files.
#
# No keystrokes, mouse input or focus calls: UI Automation patterns only.
#   powershell -NoProfile -ExecutionPolicy Bypass -File engine\tools\kd-open.ps1 -Project <file.kdenlive>
#       [-ProfileDir <dir>] (tests pass a throw-away one)  [-TimeoutSec 1800]  [-Normal] (not minimized: for the user)
# Exit 0 loaded (or already open), 4 not confirmed. If the menu route fails it starts the old, slow way and says so.
param([Parameter(Mandatory)][string]$Project, [string]$ProfileDir, [int]$TimeoutSec = 1800, [switch]$Normal)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'kd-ui.ps1')
if (-not ('KdPing' -as [type])) {
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class KdPing {
  [DllImport("user32.dll")] static extern IntPtr SendMessageTimeout(IntPtr h, uint m, IntPtr w, IntPtr l, uint f, uint ms, out IntPtr r);
  // WM_NULL: does the UI thread answer? Unlike UI Automation it makes Qt do no work at all.
  public static bool Answers(IntPtr h) { IntPtr r; return SendMessageTimeout(h, 0, IntPtr.Zero, IntPtr.Zero, 2, 2000, out r) != IntPtr.Zero; }
}
"@
}
$engine = Split-Path $PSScriptRoot -Parent
$exe = Join-Path $engine 'Kdenlive\kdenlive-26.08.3_standalone\bin\kdenlive.exe'
$prof = if ($ProfileDir) { $ProfileDir } else { Join-Path $engine 'profile-kdenlive' }
$Project = [KdPath]::Long((Resolve-Path -LiteralPath $Project).Path)
$clock = [Diagnostics.Stopwatch]::StartNew()
$utf8 = New-Object Text.UTF8Encoding($false)

function Start-Kd([string]$arguments) {
    # A leftover crash flag makes Kdenlive wait for an answer on its splash screen, which nobody sees when minimized.
    $flag = [IO.Path]::Combine($prof, 'AppData', 'Local', 'Temp', 'kdenlivelock')
    if (-not $script:othersRunning -and (Test-Path -LiteralPath $flag)) { [IO.File]::Delete($flag) }
    Start-KdDetached $exe $arguments $prof -Normal:$Normal
}
# Puts the project into the profile's Recent files. Entries with the same file name are dropped, so the menu item
# is unambiguous (the menu shortens long paths in the middle, the name is the reliable part).
function Add-RecentFile([string]$rcFile, [string]$path) {
    $name = [IO.Path]::GetFileName($path)
    $lines = New-Object System.Collections.ArrayList
    $keep = New-Object System.Collections.ArrayList
    $in = $false
    foreach ($line in [IO.File]::ReadAllLines($rcFile)) {
        if ($line -match '^\[') { $in = $line -eq '[Recent Files]'; if ($in) { continue } }
        if (-not $in) { [void]$lines.Add($line); continue }
        if ($line -match '^File\d+(?:\[\$e\])?=(.+)$') {
            $file = $matches[1]
            if (($file -replace '^.*[/\\]', '') -ne $name) { [void]$keep.Add($file) }
        }
    }
    while ($keep.Count -gt 9) { $keep.RemoveAt(0) }
    [void]$keep.Add($path.Replace('\', '/').Replace('$', '$$'))
    [void]$lines.Add('')
    [void]$lines.Add('[Recent Files]')
    for ($i = 0; $i -lt $keep.Count; $i++) {
        [void]$lines.Add("File$($i + 1)[`$e]=$($keep[$i])")
        [void]$lines.Add("Name$($i + 1)[`$e]=$($keep[$i] -replace '^.*[/\\]', '')")
    }
    [IO.File]::WriteAllText($rcFile, (($lines -join "`n") + "`n"), $utf8)
}
# The main window of the empty editor, once the splash is gone.
function Wait-EmptyEditor($proc, [int]$sec) {
    $wait = [Diagnostics.Stopwatch]::StartNew()
    while ($wait.Elapsed.TotalSeconds -lt $sec -and -not $proc.HasExited) {
        Start-Sleep -Milliseconds 500
        $all = @(Get-KdTopWindows $proc.Id)
        if ($all | Where-Object { $_.Title -match '^Splash Screen' }) { continue }
        $main = $all | Where-Object { $_.Title -match '\s/\s.*Kdenlive$' } | Select-Object -First 1
        if ($main -and [KdNative]::IsWindowEnabled($main.Handle) -and [KdPing]::Answers($main.Handle)) { return $main }
    }
}
# File > Recent files > the project. $true once the click was sent.
function Open-FromRecent($proc, $main, [string]$name) {
    $root = $script:KdAE::FromHandle($main.Handle)
    $expand = [System.Windows.Automation.ExpandCollapsePattern]::Pattern
    $isItem = New-Object System.Windows.Automation.PropertyCondition($script:KdAE::ControlTypeProperty, [System.Windows.Automation.ControlType]::MenuItem)
    foreach ($attempt in 1..4) {
        $menu = $null
        try {
            Start-Sleep -Milliseconds 700
            $menu = Find-KdFileMenu $root
            if (-not $menu) { throw 'File menu not found' }
            $menu.GetCurrentPattern($expand).Expand()
            Start-Sleep -Milliseconds 400
            $recent = Find-KdNamed $root 'Recent'   # the editor is still empty here
            if (-not $recent) { throw 'Recent files not found' }
            $recent.GetCurrentPattern($expand).Expand()
            Start-Sleep -Milliseconds 600
            $roots = @($root) + @(Get-KdTopWindows $proc.Id | Where-Object { $_.Handle -ne $main.Handle } | ForEach-Object { $script:KdAE::FromHandle($_.Handle) })
            foreach ($r in $roots) {
                foreach ($item in $r.FindAll($script:KdScope::Descendants, $isItem)) {
                    if ($item.Current.Name.Replace('&', '').StartsWith($name.Replace('&', '') + ' [')) {
                        # Invoke returns only when loading ends or after about 60 s; success is checked by the caller.
                        try { $item.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke() } catch { }
                        return $true
                    }
                }
            }
            throw 'project not in the Recent files menu'
        } catch {
            $script:openError = $_.Exception.Message
            if ($menu) { try { $menu.GetCurrentPattern($expand).Collapse() } catch { } }
        }
    }
    return $false
}
# Loaded = the title names the project, no modal progress or question, and the UI thread answers twice in a row.
function Wait-Loaded($proc) {
    $rx = Get-KdTitlePattern $Project
    $good = 0
    while ($clock.Elapsed.TotalSeconds -lt $TimeoutSec) {
        if ($proc.HasExited) { return $null }
        Start-Sleep -Seconds 1
        $all = @(Get-KdTopWindows $proc.Id)
        $main = $all | Where-Object { $_.Title -match $rx } | Select-Object -First 1
        if ($main -and -not ($all | Where-Object { $_.Title -match '^Splash Screen' }) -and [KdNative]::IsWindowEnabled($main.Handle) -and [KdPing]::Answers($main.Handle)) {
            $good++
            if ($good -ge 2) { return $main }
        } else { $good = 0 }
    }
    return $null
}

$open = Find-KdWindow $Project
if ($open) { "already open: pid $($open.ProcessId)"; exit 0 }
try { $lock = Enter-KdLock "$Project.open" 2 } catch { "this project is already being opened"; exit 4 }
try {
    $script:othersRunning = [bool](Get-Process kdenlive -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $exe -and (Get-KdTopWindows $_.Id) })
    $rc = [IO.Path]::Combine($prof, 'AppData', 'Local', 'kdenliverc')
    $proc = $null
    $script:openError = ''
    # Without settings there is no Recent list yet, and the first-run wizard has to be shown anyway.
    if (Test-Path -LiteralPath $rc) {
        Add-RecentFile $rc $Project
        $proc = Start-Kd '--no-welcome'
        $empty = Wait-EmptyEditor $proc 180
        $sent = $false
        if ($empty) {
            if ($empty.Title -match (Get-KdTitlePattern $Project)) { $sent = $true }   # "open last project" is on
            else { $sent = Open-FromRecent $proc $empty ([IO.Path]::GetFileName($Project)) }
        } else { $script:openError = 'the empty editor did not appear' }
        if (-not $sent) {
            "fast open failed ($script:openError); starting the slow way"
            if (-not $proc.HasExited) {
                if ($empty) { [void](Close-KdWindow $empty) }
                if (-not $proc.WaitForExit(15000)) { $proc.Kill(); [void]$proc.WaitForExit(10000) }   # only the process started above
            }
            $proc = $null
        } else { "started kdenlive pid $($proc.Id)" }
    }
    if (-not $proc) {
        $proc = Start-Kd "`"$Project`""
        "started kdenlive pid $($proc.Id)"
    }
    if (Wait-Loaded $proc) { "loaded in {0:N0} s" -f $clock.Elapsed.TotalSeconds; exit 0 }
    $seen = (Get-KdTopWindows $proc.Id | ForEach-Object { $_.Title } | Where-Object { $_ }) -join ' | '
    "NOT confirmed after {0:N0} s; windows: {1}" -f $clock.Elapsed.TotalSeconds, $seen
    exit 4
} finally { Exit-KdLock $lock }
