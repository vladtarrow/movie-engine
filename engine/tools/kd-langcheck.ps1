# Shows which interface language a test Kdenlive starts in (menu bar names), on an invisible desktop.
#   powershell -NoProfile -ExecutionPolicy Bypass -File engine\tools\kd-langcheck.ps1 [-Report <file>]
# Set MOVIE_ENGINE_UI_LANG before running to check another language. Exit 0 when the File menu was found by name.
param([string]$Report, [switch]$Inner)
if ($Report -and -not [IO.Path]::IsPathRooted($Report)) { $Report = Join-Path (Get-Location) $Report }
if (-not $Inner) {
    $argList = '-Inner'
    if ($Report) { $argList += " -Report '$($Report.Replace("'", "''"))'" }
    & (Join-Path $PSScriptRoot 'kd-hidden.ps1') -Script $PSCommandPath -ArgList $argList -TimeoutSec 600
    exit $LASTEXITCODE
}
. (Join-Path $PSScriptRoot 'kd-testenv.ps1')
$dir = New-KdTestDir 'lang'
$project = Join-Path $dir 'lang.kdenlive'
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $script:KdTestEngine 'kdp.ps1') new -Project $project | Out-Null
$kd = Start-KdTest $dir $project
$lines = @("language check, $(Get-Date -Format 'yyyy-MM-dd HH:mm'), MOVIE_ENGINE_UI_LANG='$env:MOVIE_ENGINE_UI_LANG'")
$code = 1
if ($kd.Main) {
    $root = $script:KdAE::FromHandle($kd.Main.Handle)
    $bars = New-Object System.Windows.Automation.PropertyCondition($script:KdAE::ControlTypeProperty, [System.Windows.Automation.ControlType]::MenuBar)
    foreach ($bar in Get-KdChildren $root $bars) { $lines += 'menu bar: ' + ((Get-KdChildren $bar | ForEach-Object { $_.Current.Name }) -join ' | ') }
    $file = Find-KdFileMenu $root
    $lines += "File menu found: $([bool]$file) as '$(if ($file) { $file.Current.Name })'"
    if ($file) { $code = 0 }
} else { $lines += "Kdenlive did not start: $($kd.Why)" }
if ($kd.Process -and -not $kd.Process.HasExited) { try { $kd.Process.Kill() } catch { } }
$text = $lines -join "`r`n"
if ($Report) { [IO.File]::WriteAllText($Report, $text + "`r`n", (New-Object Text.UTF8Encoding($true))) }
$text
exit $code
