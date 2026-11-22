# Coverage of Kdenlive's menu, checked against evidence of what actually ran:
#  1. every action in Kdenlive's own menu file (data\kdenliveui-26.08.3.rc) has a row in data\kdenlive-actions.csv;
#  2. every op / equiv row names commands that the end-to-end test ran on the CURRENT source with no failure
#     (docs\proof\clitest.txt records a hash of the source), or engine scripts proven by the live and portable tests;
#  3. "equiv" = the result is reached another way or only partly. Those rows are never counted as the same operation.
# Exit 0 = no gaps. A stale or failed proof is a gap.
$ErrorActionPreference = 'Stop'
$tools = $PSScriptRoot; $engine = Split-Path $tools -Parent
$proof = Join-Path (Split-Path $engine -Parent) 'docs\proof'
$rc = [IO.File]::ReadAllText((Join-Path $tools 'data\kdenliveui-26.08.3.rc'))
$rcActions = @([regex]::Matches($rc, '<Action name="([^"]+)"') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
$rows = @(Import-Csv (Join-Path $tools 'data\kdenlive-actions.csv') -Delimiter ';')
$gaps = New-Object System.Collections.ArrayList
$mapped = @{}; foreach ($r in $rows) { $mapped[$r.action] = $r }
foreach ($a in $rcActions) { if (-not $mapped.ContainsKey($a)) { [void]$gaps.Add("NOT MAPPED: Kdenlive menu action '$a'") } }

function Read-Proof([string]$name) {
    $file = Join-Path $proof $name
    if (-not (Test-Path $file)) { [void]$gaps.Add("NO PROOF: docs\proof\$name"); return '' }
    $text = [IO.File]::ReadAllText($file)
    if ($text -notmatch 'FAIL 0\b') { [void]$gaps.Add("PROOF HAS FAILURES: docs\proof\$name") }
    return $text
}
$cli = Read-Proof 'clitest.txt'
$live = Read-Proof 'live.txt'
$portable = Read-Proof 'portable.txt'
$src = (@('kdp.ps1', 'tools\kdp-core.ps1', 'tools\kdp-ops.ps1', 'tools\kdp-ops2.ps1') | ForEach-Object { [IO.File]::ReadAllText((Join-Path $engine $_)) -replace "`r`n", "`n" }) -join "`n"
$id = [BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes($src))).Replace('-', '')
if ($cli -notmatch "source: $id") { [void]$gaps.Add('STALE PROOF: kdp.ps1 or its functions changed after docs\proof\clitest.txt; run kdp-clitest.ps1') }
$ran = @{}
if ($cli -match '(?m)^commands: (.+?)\r?$') { foreach ($c in $matches[1].Split(' ')) { $ran[$c] = $true } }
$scripts = @{ 'kd-pull' = ($live -match 'PASS\s+pull saves'); 'kd-reload' = ($live -match 'PASS\s+manual reload'); 'kdenlive-bg' = ($portable -match 'PASS\s+launcher') }

foreach ($r in $rows) {
    if ($r.action -notmatch '^(job|panel):' -and $rcActions -notcontains $r.action) { [void]$gaps.Add("UNKNOWN action in csv: '$($r.action)'") }
    if ($r.kind -notin 'op', 'equiv', 'ui', 'na') { [void]$gaps.Add("UNKNOWN kind '$($r.kind)' for $($r.action)"); continue }
    if ($r.kind -in 'ui', 'na') { continue }
    if ($r.kind -eq 'equiv' -and -not $r.note) { [void]$gaps.Add("equiv without saying what differs: $($r.action)") }
    foreach ($c in ($r.commands -split ',')) {
        $c = $c.Trim()
        $ok = if ($scripts.ContainsKey($c)) { $scripts[$c] } else { $ran.ContainsKey($c) }
        if (-not $ok) { [void]$gaps.Add("NOT PROVEN: '$c' for $($r.action)") }
    }
}
function Count-Kind([string]$k) { @($rows | Where-Object kind -eq $k).Count }
"Kdenlive menu actions (kdenliveui.rc): $($rcActions.Count)"
"Rows in the map: $($rows.Count) (menu actions + $(@($rows | Where-Object { $_.action -match '^(job|panel):' }).Count) clip jobs/panels)"
"  same operation, run end to end: $(Count-Kind 'op')"
"  reached another way or only partly: $(Count-Kind 'equiv')"
foreach ($r in @($rows | Where-Object kind -eq 'equiv')) { "      $($r.action): $($r.note)" }
"  view/playback/selection/settings only: $(Count-Kind 'ui')"
"  not possible: $(Count-Kind 'na')"
foreach ($r in @($rows | Where-Object kind -eq 'na')) { "      $($r.action): $($r.note)" }
if ($gaps.Count) { "GAPS ($($gaps.Count)):"; $gaps; exit 1 } else { 'GAPS: none'; exit 0 }
