# Opens a project in a second Kdenlive on an invisible desktop with a throw-away profile and reports whether it
# loads cleanly (dialogs, changed on load, timeline length, screenshot). It cannot take the user's focus.
#   powershell -NoProfile -ExecutionPolicy Bypass -File engine\tools\kd-check.ps1 -Project <file.kdenlive> [-Shot name.png]
# Exit 0 clean load, 2 problem, 124 timeout.
param([Parameter(Mandatory)][string]$Project, [string]$Shot = 'kd-check.png', [int]$TimeoutSec = 1500, [switch]$Inner)
$Project = (Resolve-Path $Project).Path
if (-not $Inner) {
    $argList = "-Project '$($Project.Replace("'", "''"))' -Shot '$Shot' -TimeoutSec $TimeoutSec -Inner"
    & (Join-Path $PSScriptRoot 'kd-hidden.ps1') -Script $PSCommandPath -ArgList $argList -TimeoutSec ($TimeoutSec + 120)
    exit $LASTEXITCODE
}
. (Join-Path $PSScriptRoot 'kd-testenv.ps1')
. (Join-Path $script:KdTestEngine 'kdwin.ps1')
$dir = New-KdTestDir 'check'
$hash = Get-KdHash $Project
$kd = $null
$code = 2
try {
    $kd = Start-KdTest $dir $Project $TimeoutSec
    "Dialogs: $(@($kd.Dialogs).Count) $((@($kd.Dialogs) | ForEach-Object { $_.Title }) -join ' | ')"
    if ($kd.Main) {
        $modified = Get-KdUnsaved $kd.Main
        "ModifiedOnLoad: $modified"
        "Length: $(Get-KdTestLength $kd.Main)"
        "Shot: $(Save-KdShot $kd.Main.Handle $Shot)"
    }
    "FileUnchanged: $((Get-KdHash $Project) -eq $hash)"
    if ($kd.Main -and -not $kd.Why -and $modified -eq $false) { "RESULT: clean load"; $code = 0 }
    else { "RESULT: PROBLEM $($kd.Why)" }
} finally {
    Stop-KdTest $kd
    Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
}
exit $code
