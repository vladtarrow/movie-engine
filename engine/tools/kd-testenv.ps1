# A test Kdenlive with its own profile and TEMP. Use only on the hidden desktop (kd-hidden.ps1).
# The user's profile, crash flag, window layout and focus are never involved.
. (Join-Path $PSScriptRoot 'kd-ui.ps1')
$script:KdTestEngine = Split-Path $PSScriptRoot -Parent

function New-KdTestDir([string]$tag) {
    $dir = Join-Path ([IO.Path]::GetTempPath()) ("kd-$tag-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    $local = [IO.Path]::Combine($dir, 'profile', 'AppData', 'Local')
    [void][IO.Directory]::CreateDirectory($local)
    # kdenliverc only: without it the first-run wizard opens
    $rc = [IO.Path]::Combine($script:KdTestEngine, 'profile-kdenlive', 'AppData', 'Local', 'kdenliverc')
    if (Test-Path $rc) { Copy-Item $rc $local }
    else { [IO.File]::WriteAllText((Join-Path $local 'kdenliverc'), "[version]`nversion=26.08.3`n") }
    return $dir
}
function Start-KdTest([string]$dir, [string]$project, [int]$timeoutSec = 300) {
    $prof = Join-Path $dir 'profile'
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = Join-Path $script:KdTestEngine 'Kdenlive\kdenlive-26.08.3_standalone\bin\kdenlive.exe'
    $psi.Arguments = "`"$project`""
    $psi.UseShellExecute = $false; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    Set-KdEnvironment $psi.EnvironmentVariables $prof
    $flag = [IO.Path]::Combine($prof, 'AppData', 'Local', 'Temp', 'kdenlivelock')
    if (Test-Path $flag) { [IO.File]::Delete($flag) }
    $proc = [Diagnostics.Process]::Start($psi)
    $null = $proc.StandardOutput.ReadToEndAsync(); $null = $proc.StandardError.ReadToEndAsync()
    $rx = Get-KdTitlePattern $project
    $clock = [Diagnostics.Stopwatch]::StartNew()
    $dialogSince = $null
    while ($clock.Elapsed.TotalSeconds -lt $timeoutSec) {
        Start-Sleep -Milliseconds 700
        if ($proc.HasExited) { return @{ Process = $proc; Main = $null; Dialogs = @(); Why = 'Kdenlive exited' } }
        $all = @(Get-KdTopWindows $proc.Id)
        $splash = @($all | Where-Object { $_.Title -match '^Splash Screen' })
        $main = $all | Where-Object { $_.Title -match $rx } | Select-Object -First 1
        $other = @($all | Where-Object { $_.Title -and $_.Title -ne 'Kdenlive' -and $_.Title -notmatch '^Splash Screen' -and $_.Title -notmatch $rx -and $_.Title -notmatch $script:KdProgressTitle })
        if ($main -and -not $splash.Count -and [KdNative]::IsWindowEnabled($main.Handle)) {
            Start-Sleep -Seconds 4
            if ($null -eq (Wait-KdUnsaved $main 120)) { return @{ Process = $proc; Main = $main; Dialogs = @(); Why = 'window does not answer' } }
            if ([KdNative]::IsWindowEnabled($main.Handle)) { return @{ Process = $proc; Main = $main; Dialogs = @(); Why = '' } }
        }
        if ($other.Count) {
            if ($null -eq $dialogSince) { $dialogSince = $clock.Elapsed.TotalSeconds }
            elseif ($clock.Elapsed.TotalSeconds -gt $dialogSince + 6) { return @{ Process = $proc; Main = $main; Dialogs = $other; Why = "dialog '$($other[0].Title)'" } }
        } else { $dialogSince = $null }
    }
    return @{ Process = $proc; Main = $null; Dialogs = @(); Why = "not loaded in $timeoutSec s" }
}
function Get-KdTestLength($main) {
    try {
        foreach ($el in $script:KdAE::FromHandle($main.Handle).FindAll($script:KdScope::Descendants, (New-Object System.Windows.Automation.PropertyCondition($script:KdAE::ControlTypeProperty, [System.Windows.Automation.ControlType]::Button)))) {
            if ($el.Current.Name -match '^\d\d:\d\d:\d\d:\d\d / (\d\d:\d\d:\d\d:\d\d)') { return $matches[1] }
        }
    } catch { }
    return $null
}
# The process this harness started, and nothing else.
function Stop-KdTest($started) {
    if ($started -and $started.Process -and -not $started.Process.HasExited) { $started.Process.Kill(); [void]$started.Process.WaitForExit(10000) }
}
