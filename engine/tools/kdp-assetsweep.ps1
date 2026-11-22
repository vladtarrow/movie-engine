# Renders one real frame with every effect and every composition Kdenlive ships (433 + 56).
# "Any effect can be added" is true only for those that MLT can load and render here.
#
# Each asset gets its own small project built by the engine, rendered by melt in a separate process
# (some crash melt, so one process for all would hide the rest).
#   powershell -NoProfile -ExecutionPolicy Bypass -File engine\tools\kdp-assetsweep.ps1 [-Report docs\proof\assets.txt]
# Report lines: RENDERS / CHANGES (output differs from the untouched frame) / FAILS.
# RENDERS without CHANGES is not a failure: many effects are neutral at their default values.
param([string]$Report, [int]$TimeoutSec = 40)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'kdp-core.ps1')
. (Join-Path $PSScriptRoot 'kdp-ops.ps1')
$work = Join-Path ([IO.Path]::GetTempPath()) ('kdp-sweep-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($work)
$kit = Join-Path $script:KdpHome 'materials\aigenerated\test-kit'
$rows = New-Object System.Collections.ArrayList

function Invoke-Melt([string]$file, [string]$out, [bool]$audio) {
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = Join-Path $script:KdpBin 'melt.exe'
    $consumer = if ($audio) { "avformat:`"$out`" vn=1 acodec=pcm_s16le f=wav" } else { "avformat:`"$out`" an=1 vcodec=png f=image2 update=1" }
    $range = if ($audio) { 'in=10 out=20' } else { 'in=10 out=10' }
    $psi.Arguments = "`"$file`" $range -silent -consumer $consumer"
    $psi.WorkingDirectory = $work
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true; $psi.RedirectStandardError = $true; $psi.RedirectStandardOutput = $true
    $p = [Diagnostics.Process]::Start($psi)
    $err = $p.StandardError.ReadToEndAsync(); $null = $p.StandardOutput.ReadToEndAsync()
    if (-not $p.WaitForExit($TimeoutSec * 1000)) { $p.Kill(); return "timeout after $TimeoutSec s" }
    if ($p.ExitCode -ne 0) { return "exit $($p.ExitCode)" }
    if ($err.Result -match '(?im)^.*(failed to load (filter|transition)|mlt_repository_create.*failed|no such filter).*$') { return "not loaded: $($matches[0].Trim())" }
    if (-not [IO.File]::Exists($out) -or (New-Object IO.FileInfo($out)).Length -eq 0) { return 'no output' }
    return ''
}

try {
    $base = Join-Path $work 'base.kdenlive'
    New-KdpProject $base 'atsc_720p_25' 2 1
    $d = Open-Kdp $base
    $v = Add-KdpMedia $d "$kit\test-video-horizontal.mp4"
    $c = Add-KdpMedia $d (Join-Path $script:KdpHome 'materials\aigenerated\test-kit\cards\card-1.png')
    $a = Add-KdpMedia $d "$kit\test-music.wav"
    [void](Add-KdpClipToTimeline $d $v.BinId 'V1' 0 -dur 2)
    [void](Add-KdpClipToTimeline $d $a.BinId 'A1' 0 -dur 2)
    Save-Kdp $d
    [void](Add-KdpClipToTimeline $d $c.BinId 'V2' 0 -dur 2)
    $two = Join-Path $work 'two.kdenlive'
    Save-Kdp $d $two
    $plain = @{}
    foreach ($case in @(@('video', $base, 'png', $false), @('audio', $base, 'wav', $true), @('two', $two, 'png', $false))) {
        $out = Join-Path $work "plain-$($case[0]).$($case[2])"
        $why = Invoke-Melt $case[1] $out $case[3]
        if ($why) { throw "reference render '$($case[0])' failed: $why" }
        $plain[$case[0]] = Get-KdHash $out
    }

    $assets = @(Get-KdpEffectCatalog | ForEach-Object { @{ Kind = 'effect'; Id = $_.Id; Def = $_ } }) + @(Get-KdpTransitionCatalog | ForEach-Object { @{ Kind = 'composition'; Id = $_.Id; Def = $_ } })
    $n = 0
    foreach ($asset in $assets) {
        $n++
        $audio = $asset.Kind -eq 'effect' -and $asset.Def.Type -eq 'audio'
        $file = Join-Path $work 'case.kdenlive'
        $ext = if ($audio) { 'wav' } else { 'png' }
        $out = Join-Path $work "case-$n.$ext"
        try {
            if ($asset.Kind -eq 'effect') {
                $doc = Open-Kdp $base
                $track = if ($audio) { 'A1' } else { 'V1' }
                [void](Add-KdpEffect $doc $asset.Id $track 0.4)
                $ref = if ($audio) { 'audio' } else { 'video' }
            } else {
                $doc = Open-Kdp $two
                [void](Add-KdpComposition $doc $asset.Id 'V2' 0 2)
                $ref = 'two'
            }
            $doc.Xml.Save($file)
            $why = Invoke-Melt $file $out $audio
            $state = if ($why) { 'FAILS' } elseif ((Get-KdHash $out) -ne $plain[$ref]) { 'CHANGES' } else { 'RENDERS' }
        } catch { $state = 'FAILS'; $why = $_.Exception.Message }
        [void]$rows.Add(("{0,-8} {1,-12} {2}  {3}" -f $state, $asset.Kind, $asset.Id, ($why -replace '\s+', ' ')).TrimEnd())
        if ([IO.File]::Exists($out)) { [IO.File]::Delete($out) }
        if ($n % 50 -eq 0) { Write-Host "$n / $($assets.Count)" }
    }
} finally {
    $summary = foreach ($kind in 'effect', 'composition') {
        $of = @($rows | Where-Object { $_ -match "^\w+\s+$kind\s" })
        "{0}: {1} tried, {2} change the output, {3} render neutral at defaults, {4} fail" -f $kind, $of.Count, @($of -match '^CHANGES').Count, @($of -match '^RENDERS').Count, @($of -match '^FAILS').Count
    }
    $summary
    if ($Report) {
        $path = if ([IO.Path]::IsPathRooted($Report)) { $Report } else { Join-Path $script:KdpHome $Report }
        [IO.File]::WriteAllLines($path, [string[]](@("asset sweep, $(Get-Date -Format 'yyyy-MM-dd HH:mm')") + @($summary) + '' + @($rows | Sort-Object)), (New-Object Text.UTF8Encoding($false)))
    }
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
