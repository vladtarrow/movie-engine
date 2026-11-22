# "Copy the folder to another PC": copies the working parts to another path, opens it there with the copy's own
# launcher on an invisible desktop, and checks that nothing points back here and no system Node is used.
#   powershell -NoProfile -ExecutionPolicy Bypass -File engine\tools\kdp-portabletest.ps1 [-Project projects\...\x.kdenlive] [-Report docs\proof\portable.txt]
param([string]$Project = 'projects\kdp-selftest2\kdp-selftest2.kdenlive', [string]$Report, [string]$Copy, [switch]$Inner)
$ErrorActionPreference = 'Stop'
$source = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
if ($Report -and -not [IO.Path]::IsPathRooted($Report)) { $Report = Join-Path $source $Report }
if (-not $Inner) {
    $Copy = Join-Path ([IO.Path]::GetTempPath()) ('movie engine перенос ' + [guid]::NewGuid().ToString('N').Substring(0, 6))
    [void][IO.Directory]::CreateDirectory($Copy)
    $code = 1
    try {
        $name = Split-Path (Split-Path $Project -Parent) -Leaf
        foreach ($part in 'engine', 'materials', "projects\$name") {
            & robocopy "$source\$part" "$Copy\$part" /E /XD "$source\engine\installer" "$source\engine\profile-kdenlive\AppData\Local\kdenlive\cache" "$source\engine\profile-kdenlive\AppData\Local\Temp" /XF kd-watch.log kd-watch.run /NFL /NDL /NJH /NJS /NP /R:1 /W:1 | Out-Null
            if ($LASTEXITCODE -ge 8) { throw "copy of $part failed (robocopy $LASTEXITCODE)" }
        }
        $argList = "-Inner -Copy '$($Copy.Replace("'", "''"))' -Project '$Project'"
        if ($Report) { $argList += " -Report '$($Report.Replace("'", "''"))'" }
        if ($Report) { [IO.File]::WriteAllText($Report, "portable test`nPASS 0  FAIL 1`n`nFAIL  the test did not reach its end`n") }
        & (Join-Path $PSScriptRoot 'kd-hidden.ps1') -Script $PSCommandPath -ArgList $argList -TimeoutSec 5400
        $code = $LASTEXITCODE
    } finally {
        Start-Sleep -Seconds 2
        # only the copy made by this run
        Remove-Item -LiteralPath $Copy -Recurse -Force -ErrorAction SilentlyContinue
    }
    exit $code
}

. (Join-Path $PSScriptRoot 'kd-ui.ps1')
$ErrorActionPreference = 'Continue'
$script:lines = New-Object System.Collections.ArrayList
function Note([string]$name, [bool]$ok, [string]$detail) {
    $state = if ($ok) { 'PASS' } else { 'FAIL' }
    [void]$script:lines.Add("$state  $name :: $("$detail".Trim() -replace '\s+', ' ')")
    # a timeout must still leave evidence of the step it stopped at
    if ($Report) { [IO.File]::WriteAllLines($Report, [string[]](@('portable test', 'PASS 0  FAIL 1', '', 'FAIL  the test did not reach its end') + $script:lines), (New-Object Text.UTF8Encoding($false))) }
}
$file = Join-Path $Copy $Project
$kdp = Join-Path $Copy 'engine\kdp.ps1'
$started = $null
try {
    $env:PATH = "$env:windir\System32;$env:windir;$env:windir\System32\WindowsPowerShell\v1.0"
    Note 'no system Node on PATH during this test' (-not (Get-Command node.exe -ErrorAction SilentlyContinue)) ''

    $o = & powershell -NoProfile -ExecutionPolicy Bypass -File "$Copy\engine\kdenlive-bg.ps1" $file 2>&1 | ForEach-Object { "$_" } | Out-String
    if ($o -match 'pid (\d+)') { $started = [int]$matches[1] }
    Note 'launcher of the copy starts Kdenlive' ([bool]$started) $o
    $head = [IO.File]::ReadAllText($file)
    $here = (Split-Path $file -Parent) -replace '\\', '/'
    Note 'project now records the new folder' ($head.Contains("root=`"$here`"")) ''
    $main = $null
    $clock = [Diagnostics.Stopwatch]::StartNew()
    while ($started -and $clock.Elapsed.TotalSeconds -lt 2100) {
        Start-Sleep -Seconds 2
        $wins = @(Get-KdTopWindows $started)
        if (-not ($wins | Where-Object { $_.Title -match '^Splash Screen' })) {
            $main = $wins | Where-Object { $_.Title -match (Get-KdTitlePattern $file) } | Select-Object -First 1
            if ($main) { break }
        }
        if (-not (Get-Process -Id $started -ErrorAction SilentlyContinue)) { break }
    }
    $dialogs = @(if ($main) { Get-KdDialogs $main })
    Note 'project opens in the copy without dialogs' ([bool]$main -and -not $dialogs.Count) (($dialogs | ForEach-Object { $_.Title }) -join ' | ')
    if ($main) { Note 'loading did not modify the document' ((Wait-KdUnsaved $main 900) -eq $false) '' }
    if ($started) { Stop-Process -Id $started -Force -ErrorAction SilentlyContinue; Start-Sleep -Seconds 2 }

    $o = & powershell -NoProfile -ExecutionPolicy Bypass -File $kdp validate -Project $file 2>&1 | ForEach-Object { "$_" } | Out-String
    Note 'every media file resolves inside the copy' ($LASTEXITCODE -eq 0 -and $o -match 'clean') $o
    $back = @([regex]::Matches([IO.File]::ReadAllText($file), '[A-Za-z]:/[^<"]+') | ForEach-Object { $_.Value } | Where-Object { -not $_.StartsWith(($Copy -replace '\\', '/')) } | Sort-Object -Unique)
    Note 'no absolute path points outside the copy' (-not $back.Count) (($back | Select-Object -First 4) -join ' | ')
    $png = Join-Path $Copy 'frame.png'
    $o = & powershell -NoProfile -ExecutionPolicy Bypass -File $kdp frame -At 12 -Out $png -Project $file 2>&1 | ForEach-Object { "$_" } | Out-String
    Note 'a frame renders from the copy' ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $png)) $o

    $o = & "$Copy\engine\node.cmd" "$Copy\engine\audio\sfx.mjs" "$Copy\sfx" 2>&1 | ForEach-Object { "$_" } | Out-String
    Note 'sound effects run on the bundled Node' ($LASTEXITCODE -eq 0 -and @(Get-ChildItem -LiteralPath "$Copy\sfx" -File -ErrorAction SilentlyContinue).Count -ge 10) $o
    $list = Join-Path $Copy 'empty-lines.json'
    [IO.File]::WriteAllText($list, '[{"id":"x","text":""}]')
    $o = & "$Copy\engine\node.cmd" "$Copy\engine\voice\voice.mjs" $list "$Copy\voice-test" 2>&1 | ForEach-Object { "$_" } | Out-String
    Note 'voice tool and its dependencies load on the bundled Node (offline)' ($LASTEXITCODE -eq 0) $o
} catch {
    Note 'test run' $false $_.Exception.Message
} finally {
    $fail = @($script:lines | Where-Object { $_ -like 'FAIL*' }).Count
    $all = @("portable test, $(Get-Date -Format 'yyyy-MM-dd HH:mm')", "PASS $($script:lines.Count - $fail)  FAIL $fail", '') + $script:lines
    $all
    if ($Report) { [IO.File]::WriteAllLines($Report, [string[]]$all, (New-Object Text.UTF8Encoding($false))) }
}
if ($fail) { exit 1 }
exit 0
