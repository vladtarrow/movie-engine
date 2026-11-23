# Shows which interface language a test Kdenlive starts in (menu bar names), on an invisible desktop.
#   powershell -NoProfile -ExecutionPolicy Bypass -File engine\tools\kd-langcheck.ps1 [-Report <file>]
# Set MOVIE_ENGINE_UI_LANG before running to check another language. Exit 0 when the File menu, the Save
# button and the Revert and Open Recent items were all found by their names in engine\tools\kd-ui.ps1.
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
    $save = Find-KdSaveButton $root
    $lines += "Save button found: $([bool]$save) as '$(if ($save) { $save.Current.Name })'"
    $revert = $null; $recent = $null
    if ($file) {
        # open the File menu on this invisible desktop and look for the items pull/reload/open use
        $menu = $file.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern)
        try { $menu.Expand() } catch { }
        for ($i = 0; $i -lt 30 -and -not ($revert -and $recent); $i++) {
            Start-Sleep -Milliseconds 200
            if (-not $revert) { $revert = Find-KdNamed $file 'Revert' }
            if (-not $recent) { $recent = Find-KdNamed $file 'Recent' }
        }
        try { $menu.Collapse() } catch { }
    }
    $lines += "Revert item found: $([bool]$revert) as '$(if ($revert) { $revert.Current.Name })'"
    $lines += "Open Recent item found: $([bool]$recent) as '$(if ($recent) { $recent.Current.Name })'"
    if ($file -and $save -and $revert -and $recent) { $code = 0 }
} else { $lines += "Kdenlive did not start: $($kd.Why)" }
if ($kd.Process -and -not $kd.Process.HasExited) { try { $kd.Process.Kill() } catch { } }
$text = $lines -join "`r`n"
if ($Report) { [IO.File]::WriteAllText($Report, $text + "`r`n", (New-Object Text.UTF8Encoding($true))) }
$text
exit $code
