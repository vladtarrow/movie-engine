# End-to-end test of kdp.ps1: runs every command the way an agent does (as a separate process) and checks the RESULT
# with its own XML reader, ffprobe or rendered pixels. The older self-tests call internal functions and cannot see
# a broken command line.
#
# Works in a throw-away copy of the engine in a folder with a space and Cyrillic in its name, then moves that
# folder and checks that projects still work (the "copy to another PC" case). Never touches the real projects.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File engine\tools\kdp-clitest.ps1 [-Report docs\proof\clitest.txt] [-Keep]
# Exit 0 = every check passed and every command of kdp.ps1 was exercised.
param([string]$Report, [switch]$Keep, [string]$Sandbox)
$ErrorActionPreference = 'Stop'
$realEngine = Split-Path $PSScriptRoot -Parent
$realHome = Split-Path $realEngine -Parent
if (-not $Sandbox) { $Sandbox = Join-Path $env:TEMP ('kdp проверка ' + [guid]::NewGuid().ToString('N').Substring(0, 6)) }
if (Test-Path -LiteralPath $Sandbox) { throw "$Sandbox already exists" }
[void][IO.Directory]::CreateDirectory("$Sandbox\engine")
[void][IO.Directory]::CreateDirectory("$Sandbox\materials\aigenerated")
[void][IO.Directory]::CreateDirectory("$Sandbox\projects")
. (Join-Path $PSScriptRoot 'kd-state.ps1')
$Sandbox = [KdPath]::Long($Sandbox)     # kdp writes long paths; TEMP may hand out USERNA~1
Copy-Item "$realEngine\*.ps1" "$Sandbox\engine"
Copy-Item "$realEngine\tools" "$Sandbox\engine\tools" -Recurse
Copy-Item "$realEngine\Kdenlive" "$Sandbox\engine\Kdenlive" -Recurse
Copy-Item "$realHome\materials\aigenerated\test-kit" "$Sandbox\materials\aigenerated\test-kit" -Recurse
Copy-Item "$realHome\materials\aigenerated\test-kit\cards" "$Sandbox\materials\aigenerated\cards" -Recurse

$script:home2 = $Sandbox
$script:results = New-Object System.Collections.ArrayList
$script:used = @{}
$script:p = ''

function At([string]$rel) { Join-Path $script:home2 $rel }
function Kit([string]$name) { At "materials\aigenerated\test-kit\$name" }
function Card([int]$n) { At "materials\aigenerated\cards\card-$n.png" }
function Invoke-Cli([string[]]$a) {
    $script:used[$a[0]] = $true
    $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try {
        $o = & powershell -NoProfile -ExecutionPolicy Bypass -File (At 'engine\kdp.ps1') @a 2>&1 | ForEach-Object { "$_" } | Out-String
        return @{ Code = $LASTEXITCODE; Out = $o }
    } finally { $ErrorActionPreference = $old }
}
function K { $r = Invoke-Cli ([string[]]$args + @('-Project', $script:p)); if ($r.Code -ne 0) { throw "exit $($r.Code): $($r.Out)" }; return $r.Out }
function K0 { $r = Invoke-Cli ([string[]]$args); if ($r.Code -ne 0) { throw "exit $($r.Code): $($r.Out)" }; return $r.Out }
function Refused {
    $h = (Get-FileHash -LiteralPath $script:p).Hash
    $r = Invoke-Cli ([string[]]$args + @('-Project', $script:p))
    if ($r.Code -eq 0) { throw 'was accepted, should have failed' }
    if ((Get-FileHash -LiteralPath $script:p).Hash -ne $h) { throw 'failed but changed the file' }
}
function Is($actual, $expected, [string]$what = 'value') { if ("$actual" -ne "$expected") { throw "$what is '$actual', expected '$expected'" } }
function Yes($condition, [string]$what) { if (-not $condition) { throw $what } }
function Check([string]$name, [scriptblock]$body) {
    try { [void](& $body); [void]$script:results.Add("PASS  $name") }
    catch { [void]$script:results.Add("FAIL  $name :: $(($_.Exception.Message -replace '\s+', ' ').Trim())") }
    Write-Host $script:results[$script:results.Count - 1]
}
function Project([string]$name, [string[]]$bins = @()) {
    $script:p = At "projects\$name\$name.kdenlive"
    [void](K0 new -Project $script:p -Profile vertical_hd_30 -VideoTracks 3 -AudioTracks 2)
    foreach ($b in $bins) {
        switch ($b) {
            'v' { [void](K bin-add -File (Kit 'test-video-vertical.mp4') -Name v) }
            'h' { [void](K bin-add -File (Kit 'test-video-horizontal.mp4') -Name h) }
            'm' { [void](K bin-add -File (Kit 'test-music.wav') -Name m) }
            'red' { [void](K bin-color -Color '#ff0000' -Name red -Seconds 5) }
            'blue' { [void](K bin-color -Color '#0000ff' -Name blue -Seconds 5) }
        }
    }
}

# ---- independent reader (frames at 30 fps)
function Doc { $x = New-Object System.Xml.XmlDocument; $x.Load($script:p); return , $x }
function Prop($node, [string]$name) { $n = $node.SelectSingleNode("property[@name='$name']"); if ($n) { $n.InnerText } }
function F([string]$t) { if ($t -match '^(\d+):(\d+):([\d.]+)$') { [int][math]::Round(([int]$matches[1] * 3600 + [int]$matches[2] * 60 + [double]$matches[3]) * 30) } else { [int]$t } }
function Seq([string]$name) {
    $x = Doc
    $main = Prop $x.SelectSingleNode("/mlt/playlist[@id='main_bin']") 'kdenlive:docproperties.uuid'
    foreach ($t in $x.SelectNodes('/mlt/tractor')) {
        if ((Prop $t 'kdenlive:producer_type') -ne '17') { continue }
        if (($name -and (Prop $t 'kdenlive:clipname') -eq $name) -or (-not $name -and (Prop $t 'kdenlive:uuid') -eq $main)) { return $t }
    }
}
function TrackNodes([string]$seqName) {
    $s = Seq $seqName; $x = $s.OwnerDocument
    $all = @(foreach ($tr in $s.SelectNodes('track')) { $t = $x.SelectSingleNode("/mlt/tractor[@id='$($tr.producer)']"); if ($t) { $t } })
    $audio = @($all | Where-Object { (Prop $_ 'kdenlive:audio_track') -eq '1' })
    $video = @($all | Where-Object { (Prop $_ 'kdenlive:audio_track') -ne '1' })
    $map = @{}
    for ($i = 0; $i -lt $audio.Count; $i++) { $map["A$($audio.Count - $i)"] = $audio[$i] }
    for ($i = 0; $i -lt $video.Count; $i++) { $map["V$($i + 1)"] = $video[$i] }
    return $map
}
function Items([string]$track, [string]$seqName, [int]$sub = 0) {
    $t = (TrackNodes $seqName)[$track]; $x = $t.OwnerDocument
    $pl = $x.SelectSingleNode("/mlt/playlist[@id='$(@($t.SelectNodes('track'))[$sub].producer)']")
    $pos = 0
    foreach ($c in $pl.ChildNodes) {
        if ($c.Name -eq 'blank') { $pos += F $c.length }
        elseif ($c.Name -eq 'entry') {
            $len = (F $c.GetAttribute('out')) - (F $c.GetAttribute('in')) + 1
            [pscustomobject]@{ S = $pos; L = $len; In = (F $c.GetAttribute('in')); Node = $c; Prod = $x.SelectSingleNode("/mlt/*[@id='$($c.producer)']") }
            $pos += $len
        }
    }
}
# "start+length@in" of every clip on a track
function Shape([string]$track, [string]$seqName, [int]$sub = 0) { (@(Items $track $seqName $sub) | ForEach-Object { "$($_.S)+$($_.L)@$($_.In)" }) -join ' ' }
function BinNodes { $x = Doc; foreach ($e in $x.SelectNodes("/mlt/playlist[@id='main_bin']/entry")) { $x.SelectSingleNode("/mlt/*[@id='$($e.producer)']") } }
function BinNode([string]$name) { BinNodes | Where-Object { (Prop $_ 'kdenlive:clipname') -eq $name } | Select-Object -First 1 }
function MainBin([string]$name) { Prop (Doc).SelectSingleNode("/mlt/playlist[@id='main_bin']") $name }
function SeqProp([string]$name, [string]$seqName) { Prop (Seq $seqName) "kdenlive:sequenceproperties.$name" }
function Json([string]$s) { $r = $s | ConvertFrom-Json; foreach ($i in $r) { $i } }
function Effects([string]$track, [int]$i = 0) { @(@(Items $track)[$i].Node.SelectNodes('filter') | ForEach-Object { Prop $_ 'kdenlive_id' }) -join ',' }
function Leaves { $list = @([regex]::Matches((SeqProp 'groups'), '"data"\s*:\s*"(\d+:\d+)') | ForEach-Object { $_.Groups[1].Value } | Sort-Object); $list -join ' ' }
function Probe([string]$file, [string]$entries) { (& (At 'engine\Kdenlive\kdenlive-26.08.3_standalone\bin\ffprobe.exe') -v error -show_entries $entries -of csv=p=0 $file) -join ' ' }
function Seconds([string]$file) { [double]::Parse((Probe $file 'format=duration'), [cultureinfo]::InvariantCulture) }
Add-Type -AssemblyName System.Drawing
function Pixel([double]$at, [double]$fx = 0.5, [double]$fy = 0.5) {
    $png = At ('frame-' + [guid]::NewGuid().ToString('N') + '.png')
    [void](K frame -At $at -Out $png)
    $b = New-Object System.Drawing.Bitmap $png
    try { $c = $b.GetPixel([int]($b.Width * $fx), [int]($b.Height * $fy)); return @{ R = [int]$c.R; G = [int]$c.G; B = [int]$c.B; W = $b.Width; H = $b.Height } } finally { $b.Dispose() }
}

$began = Get-Date
try {
# ================ catalogs
Check 'effects' { Yes ((K0 effects -Search gblur) -match 'avfilter\.gblur') 'gblur not listed' }
Check 'effect-info' { Yes ((K0 effect-info -Id avfilter.gblur) -match 'av\.sigma') 'no parameter' }
Check 'compositions' { Yes ((K0 compositions) -match 'qtblend') 'qtblend not listed' }
Check 'comp-info' { Yes ((K0 comp-info -Id qtblend) -match 'rect') 'no parameter' }
Check 'profiles' { Yes ((K0 profiles -Search vertical) -match 'vertical_hd_30') 'not listed' }
Check 'fonts' { Yes ((K0 fonts -Search 'Segoe UI') -match 'Segoe UI') 'not listed' }
Check 'presets' { Yes ((K0 presets) -match 'MP4-H264/AAC') 'not listed' }
Check 'effect-templates' { Yes ((K0 effect-templates) -match 'shut_off') 'not listed' }

# ================ project and bin
Check 'new' { Project 'bin'; Is (@((TrackNodes).Keys | Sort-Object) -join ',') 'A1,A2,V1,V2,V3'; Is (Doc).mlt.profile.width 1080 }
Check 'new: refuses to overwrite' { Refused new }
Check 'bin-add: video, audio, image, animation' {
    [void](K bin-add -File (Kit 'test-video-vertical.mp4') -Name v); [void](K bin-add -File (Kit 'test-music.wav') -Name m)
    [void](K bin-add -File (Card 1) -Name img -Seconds 4); [void](K bin-add -File (Kit 'test-anim.json') -Name anim)
    Is (Prop (BinNode v) 'kdenlive:clip_type') 0; Is (Prop (BinNode m) 'kdenlive:clip_type') 1; Is (Prop (BinNode img) 'length') 120
    Is (Prop (BinNode anim) 'mlt_service') 'glaxnimate'; Yes ((Prop (BinNode v) 'resource') -like '../../materials/*') 'path is not relative'
}
Check 'bin-color' { [void](K bin-color -Color '#203060' -Name col -Seconds 2); Is (Prop (BinNode col) 'resource') '0x203060ff'; Is (Prop (BinNode col) 'length') 60 }
Check 'title' { [void](K title -Text 'Первая строка' -Name t -Size 110 -Color '#ff8800' -Seconds 3); $x = Prop (BinNode t) 'xmldata'; Yes ($x -match 'Первая строка' -and $x -match 'font-pixel-size="110"' -and $x -match '255,136,0,255') 'wrong title xml' }
Check 'title-text' { [void](K title-text -Bin t -Text 'Вторая'); Yes ((Prop (BinNode t) 'xmldata') -match 'Вторая') 'text unchanged' }
Check 'bin-rename' { [void](K bin-rename -Bin col -Name 'Фон тест'); Yes (BinNode 'Фон тест') 'not renamed' }
Check 'folder, bin-folder' {
    [void](K folder -Name 'Папка'); [void](K bin-folder -Bin img -Folder 'Папка')
    $id = Prop (BinNode img) 'kdenlive:folderid'; Is (MainBin "kdenlive:folder.-1.$id") 'Папка'
}
Check 'marker (-Category, -Dur)' { [void](K marker -Bin v -At 1 -Text 'метка' -Category 3 -Dur 0.5); $m = @(Json (Prop (BinNode v) 'kdenlive:markers'))[0]; Is "$($m.pos),$($m.type),$($m.duration),$($m.comment)" '30,3,15,метка' }
Check 'marker-list' { Yes ((K marker-list -Bin v) -match '\b1\b') 'empty' }
Check 'marker-set' { [void](K marker-set -Bin v -At 1 -Text two -CategoryIndex 5 -NewAt 2); $m = @(Json (Prop (BinNode v) 'kdenlive:markers'))[0]; Is "$($m.pos),$($m.type),$($m.comment)" '60,5,two' }
Check 'marker-remove' { [void](K marker-remove -Bin v -At 2); Is @(Json (Prop (BinNode v) 'kdenlive:markers')).Count 0 }
Check 'subclip' { [void](K subclip -Bin v -From 1 -ToTime 3 -Name part); $z = @(Json (Prop (BinNode v) 'kdenlive:clipzones'))[0]; Is "$($z.in),$($z.out),$($z.name)" '30,90,part' }
Check 'bin-set' { [void](K bin-set -Bin v -Params 'force_fps=25||kdenlive:description=test'); Is (Prop (BinNode v) 'force_fps') 25; Is (Prop (BinNode v) 'kdenlive:description') 'test' }
Check 'bin-info' { Yes ((K bin-info -Bin v) -match 'force_fps=25') 'property missing' }
Check 'bin-duplicate' { [void](K bin-duplicate -Bin img -Name img2); Yes ((Prop (BinNode img2) 'kdenlive:control_uuid') -ne (Prop (BinNode img) 'kdenlive:control_uuid')) 'same uuid' }
Check 'bin-replace-file' { [void](K bin-replace-file -Bin img2 -File (Card 2)); Yes ((Prop (BinNode img2) 'resource') -like '*card-2.png') 'file unchanged' }
Check 'bin-reload' {
    $copy = At 'materials\aigenerated\reload.png'; Copy-Item (Card 1) $copy; [void](K bin-add -File $copy -Name rl); $h1 = Prop (BinNode rl) 'kdenlive:file_hash'
    Copy-Item (Card 3) $copy -Force; [void](K bin-reload -Bin rl); Yes ((Prop (BinNode rl) 'kdenlive:file_hash') -ne $h1) 'hash unchanged'
}
Check 'relink' {
    $old = At 'materials\aigenerated\lost.png'; $dir = At 'materials\aigenerated\found'
    Copy-Item (Card 2) $old; [void](K bin-add -File $old -Name lost); [void][IO.Directory]::CreateDirectory($dir); Move-Item $old "$dir\lost.png"
    [void](K relink -Folder $dir); Yes ((Prop (BinNode lost) 'resource') -like '*found/lost.png') 'not relinked'
}
Check 'generator' { [void](K generator -Id count -Name cnt -Seconds 2); Is (Prop (BinNode cnt) 'mlt_service') 'count' }
Check 'slideshow (-FadeSlides)' { [void](K slideshow -File (Kit 'slides\img_%04d.png') -Seconds 1 -Name ss -FadeSlides); Is (Prop (BinNode ss) 'length') 90; Is (Prop (BinNode ss) 'fade') 1 }
Check 'title-save, title-template' {
    [void](K title -Text 'Привет %s' -Name tp); $f = At 'projects\bin\tpl.kdenlivetitle'
    [void](K title-save -Bin tp -Out $f); [void](K title-template -File $f -Text World -Name tc); Is (Prop (BinNode tc) 'templatetext') 'World'
}
Check 'bin-remove' { [void](K bin-remove -Bin rl); Yes (-not (BinNode rl)) 'still in bin' }
Check 'validate' { Yes ((K validate) -match 'clean') 'not clean' }
Check 'info' { Yes ((K info) -match 'img2') 'bin missing from info' }
Check 'clean' { [void](K clean); Is @(BinNodes | Where-Object { $_.Name -ne 'tractor' }).Count 0 }

# ================ timeline
Check 'add, -Insert, -Overwrite' {
    Project 'line' @('v', 'red', 'blue'); [void](K add -Bin red -Track V1 -At 0 -Dur 2); [void](K add -Bin red -Track V1 -At 2 -Dur 2)
    Is (Shape V1) '0+60@0 60+60@0'
    [void](K add -Bin blue -Track V1 -At 2 -Dur 1 -Insert); Is (Shape V1) '0+60@0 60+30@0 90+60@0'
    [void](K add -Bin blue -Track V1 -At 0.5 -Dur 1 -Overwrite); Is (Shape V1) '0+15@0 15+30@0 45+15@45 60+30@0 90+60@0'
}
Check 'add: refuses overlap, bad track, decimal comma, too-long source' { Refused add -Bin red -Track V1 -At 0 -Dur 1; Refused add -Bin red -Track V9 -At 0; Refused add -Bin red -Track V2 -At '1,5'; Refused add -Bin v -Track V2 -At 0 -Dur 60 }
Check 'copy' { [void](K copy -Track V1 -At 3.5 -ToTrack V2 -To 1); Is (Shape V2) '30+60@0' }
Check 'move' { [void](K move -Track V2 -At 1.5 -ToTrack V3 -To 0); Is (Shape V2) ''; Is (Shape V3) '0+60@0' }
Check 'trim' { [void](K trim -Track V3 -At 1 -NewIn 0.5 -KeepEnd); Is (Shape V3) '15+45@15'; [void](K trim -Track V3 -At 1 -NewDur 3); Is (Shape V3) '15+90@15' }
Check 'split' { [void](K split -Track V3 -At 1.5); Is (Shape V3) '15+30@15 45+60@45' }
Check 'remove, -Ripple' { [void](K remove -Track V3 -At 1 -Ripple); Is (Shape V3) '15+60@45'; [void](K remove -Track V3 -At 1); Is (Shape V3) '' }
Check 'slip' { [void](K add -Bin v -Track V2 -At 0 -In 1 -Dur 2); [void](K slip -Track V2 -At 1 -By 0.5); Is (Shape V2) '0+60@45' }
Check 'ripple-trim' { [void](K add -Bin red -Track V2 -At 2 -Dur 1); [void](K ripple-trim -Track V2 -At 1 -NewDur 1); Is (Shape V2) '0+30@45 30+30@0' }
Check 'speed (and back)' {
    [void](K add -Bin v -Track V3 -At 0 -Dur 4); [void](K speed -Track V3 -At 1 -Speed 2); Is (Shape V3) '0+60@0'; Is (Prop @(Items V3)[0].Prod 'warp_speed') 2
    [void](K speed -Track V3 -At 1 -Speed 1); Is (Shape V3) '0+120@0'
}
Check 'speed: reverse' { [void](K speed -Track V3 -At 1 -Speed -1); Is (Prop @(Items V3)[0].Prod 'warp_speed') -1; Is (Shape V3) '0+120@60' }
Check 'remap' { [void](K add -Bin v -Track V3 -At 5 -Dur 1); [void](K remap -Track V3 -At 5.2 -Speed 0.5); Is @(Items V3)[1].L 60; Yes (@(Items V3)[1].Prod.SelectSingleNode('link')) 'no timeremap link' }
Check 'disable, enable' {
    [void](K disable -Track V3 -At 5.2); Is (Prop @(Items V3)[1].Prod 'set.test_image') 1
    [void](K enable -Track V3 -At 5.2); Is (Prop @(Items V3)[1].Prod 'set.test_image') 0
}
Check 'space-insert' { [void](K space-insert -At 1 -Dur 1 -Tracks V2); Is (Shape V2) '0+30@45 60+30@0' }
Check 'space-remove' { [void](K space-remove -At 1.5 -Tracks V2); Is (Shape V2) '0+30@45 30+30@0' }
Check 'spaces-remove-all' { [void](K move -Track V2 -At 1.5 -To 5); [void](K spaces-remove-all -Track V2); Is (Shape V2) '0+30@45 30+30@0' }
Check 'track-clear' { [void](K track-clear -Track V2); Is (Shape V2) '' }
Check 'replace-in-timeline' { [void](K replace-in-timeline -Bin red -With blue); $id = Prop (BinNode blue) 'kdenlive:id'; foreach ($i in Items V1) { Is (Prop $i.Node 'kdenlive:id') $id } }
Check 'mix' {
    Project 'mix' @('red', 'blue'); [void](K add -Bin red -Track V1 -At 0 -Dur 2); [void](K add -Bin blue -Track V1 -At 2 -In 1 -Dur 2)
    [void](K mix -Track V1 -At 2 -Dur 1); Is (Shape V1 '' 1) '30+90@0'
    $mid = Pixel 1.5; Yes ($mid.R -gt 40 -and $mid.B -gt 40) "middle of the crossfade is not a blend: $($mid.R),$($mid.B)"
}
Check 'mix: ripple across a crossfade is refused' { Refused remove -Track V1 -At 0.2 -Ripple }
Check 'unmix' { [void](K unmix -Track V1 -At 1.5); Is (Shape V1) '0+60@0 60+60@30'; Is (Shape V1 '' 1) '' }

# ================ linked clips and groups
Check 'add-av' { Project 'linked' @('v', 'red'); [void](K add-av -Bin v -Track V1 -AudioTrack A1 -At 1 -In 1 -Dur 4); Is (Shape V1) '30+120@30'; Is (Shape A1) '30+120@30'; Is (Leaves) '1:30 2:30' }
Check 'linked: move' { [void](K move -Track V1 -At 2 -To 3); Is (Shape V1) '90+120@30'; Is (Shape A1) '90+120@30'; Is (Leaves) '1:90 2:90' }
Check 'linked: move from the audio half' { [void](K move -Track A1 -At 4 -To 2); Is (Shape V1) '60+120@30'; Is (Leaves) '1:60 2:60' }
Check 'linked: trim' { [void](K trim -Track V1 -At 3 -NewIn 2 -KeepEnd); Is (Shape V1) '90+90@60'; Is (Shape A1) '90+90@60'; Is (Leaves) '1:90 2:90' }
Check 'linked: slip' { [void](K slip -Track V1 -At 4 -By 0.5); Is (Shape V1) '90+90@75'; Is (Shape A1) '90+90@75' }
Check 'linked: ripple-trim' { [void](K ripple-trim -Track V1 -At 4 -NewDur 2); Is (Shape V1) '90+60@75'; Is (Shape A1) '90+60@75' }
Check 'linked: speed' { [void](K speed -Track A1 -At 3.5 -Speed 2); Is @(Items V1)[0].L 30; Is @(Items A1)[0].L 30; [void](K speed -Track V1 -At 3.2 -Speed 1); Is @(Items A1)[0].L 60 }
Check 'linked: split makes two pairs' { [void](K split -Track V1 -At 4); Is @(Items A1).Count 2; Is (Leaves) '1:120 1:90 2:120 2:90' }
Check 'linked: space-insert keeps links' { [void](K space-insert -At 2 -Dur 1); Is (Leaves) '1:120 1:150 2:120 2:150' }
Check 'linked: remove' { [void](K remove -Track V1 -At 4.2); Is @(Items A1).Count 1; Is (Leaves) '1:150 2:150' }
Check 'linked: -Alone' { [void](K move -Track V1 -At 5.2 -To 7 -Alone); Is @(Items A1)[0].S 150; Is @(Items V1)[0].S 210; Is (Leaves) '1:150 2:210' }
Check 'ungroup' { [void](K ungroup -Track V1 -At 7.1); Is (Leaves) '' }
Check 'group' { [void](K add -Bin red -Track V2 -At 0 -Dur 1); [void](K group -Clips 'V1@7.1,V2@0.1'); Is (Leaves) '2:210 3:0' }

# ================ effects, compositions, tracks
Check 'effect-add: clip, track, master' {
    Project 'fx' @('red', 'blue'); [void](K add -Bin red -Track V1 -At 0 -Dur 3); [void](K add -Bin blue -Track V1 -At 3 -Dur 3)
    [void](K effect-add -Id sepia -Track V1 -At 1); Is (Effects V1) 'sepia'
    [void](K effect-add -Id avfilter.gblur -Track V2); Yes (@((TrackNodes)['V2'].SelectNodes('filter') | Where-Object { (Prop $_ 'kdenlive_id') -eq 'avfilter.gblur' }).Count) 'no track effect'
    [void](K effect-add -Id avfilter.hflip -Master); Yes (@((Seq).SelectNodes('filter') | Where-Object { (Prop $_ 'kdenlive_id') -eq 'avfilter.hflip' }).Count) 'no master effect'
}
Check 'effect-add: refuses audio effect on video, unknown id' { Refused effect-add -Id fadein -Track V1 -At 1; Refused effect-add -Id no_such_effect -Track V1 -At 1 }
Check 'effect-add: defaults are raw MLT values, not divided by factor' {
    [void](K add -Bin red -Track V3 -At 0 -Dur 1); [void](K effect-add -Id avfilter.colorize -Track V3 -At 0.5)
    $stored = Prop @(Items V3)[0].Node.SelectSingleNode('filter') 'av.mix'
    Is $stored 1 'colorize av.mix (default 1, factor 100)'
}
Check 'effect-add: an effect this build lacks is refused' { Refused effect-add -Id movit.blur -Track V1 -At 1 }
Check 'comp-add: a composition this build lacks is refused' { Refused comp-add -Id region -Track V2 -At 0 -Dur 1 }
Check 'effect-list' { Yes ((K effect-list -Track V1 -At 1) -match 'sepia') 'not listed' }
Check 'effect-set, renders' {
    $s = Pixel 1; Yes ($s.G -gt 5) "sepia has no visible effect: $($s.R),$($s.G),$($s.B)"
    [void](K effect-set -Effect sepia -Track V1 -At 1 -Disable); $r = Pixel 1; Yes ($r.R -gt 220 -and $r.G -lt 25) "disabled effect still visible: $($r.R),$($r.G)"
}
Check 'effects-all' {
    [void](K effects-all -Disable); Is (Prop @(Items V1)[0].Node.SelectSingleNode('filter') 'disable') 1
    [void](K effects-all -Enable); Is (Prop @(Items V1)[0].Node.SelectSingleNode('filter') 'disable') 0
    Refused effects-all
}
Check 'effect-copy' { [void](K effect-copy -Track V1 -At 1 -ToTrack V1 -To 4); Is (Effects V1 1) 'sepia' }
Check 'effect-remove' { [void](K effect-remove -Effect sepia -Track V1 -At 4); Is (Effects V1 1) '' }
Check 'effect-clear' { [void](K effect-clear -Track V1 -At 1); Is (Effects V1) '' }
Check 'effect-template' { [void](K effect-template -Id shut_off -Track V1 -At 1); Yes ((Effects V1).Split(',').Count -ge 3) 'too few effects' }
Check 'bin-effect' { [void](K bin-effect -Bin red -Id sepia); Yes (BinNode red).SelectSingleNode("filter/property[@name='kdenlive_id'][.='sepia']") 'no bin effect' }
Check 'comp-add, renders' {
    [void](K add -Bin red -Track V2 -At 3 -Dur 2); [void](K comp-add -Id qtblend -Track V2 -At 3 -Dur 2 -Below V1 -Params 'rect=0 0 100 100 1')
    $c = (Seq).SelectSingleNode("transition[not(property[@name='internal_added'])]"); Is (Prop $c 'kdenlive_id') 'qtblend'; Is "$(F $c.GetAttribute('in'))-$(F $c.GetAttribute('out'))" '90-149'
}
Check 'comp-list' { Yes ((K comp-list) -match 'qtblend') 'not listed' }
Check 'comp-set' { [void](K comp-set -Track V2 -At 4 -Params 'rect=0 0 500 500 1'); Is (Prop (Seq).SelectSingleNode("transition[not(property[@name='internal_added'])]") 'rect') '0 0 500 500 1' }
Check 'comp-remove' { [void](K comp-remove -Track V2 -At 4); Yes (-not (Seq).SelectSingleNode("transition[not(property[@name='internal_added'])]")) 'still there' }
Check 'track-add' { [void](K track-add -Name Extra); [void](K track-add -Audio -Name Voice); $t = TrackNodes; Is (Prop $t['V4'] 'kdenlive:track_name') 'Extra'; Is (Prop $t['A3'] 'kdenlive:track_name') 'Voice'; Is (Shape V2) '90+60@0' }
Check 'track-set' {
    [void](K track-set -Track A1 -Name Music -Lock -Hide); $t = (TrackNodes)['A1']
    Is (Prop $t 'kdenlive:track_name') 'Music'; Is (Prop $t 'kdenlive:locked_track') 1; Is $t.SelectSingleNode('track').hide 'both'
}
Check 'track-remove' { [void](K track-remove -Track V4); Is (TrackNodes).Count 6; Refused track-remove -Track V2 }

# ================ guides, subtitles, history, settings
Check 'guide-add (-Category)' { Project 'notes' @('red'); [void](K add -Bin red -Track V1 -At 0 -Dur 5); [void](K guide-add -At 1 -Text Intro -Category 2 -Dur 1); $g = @(Json (SeqProp guides))[0]; Is "$($g.pos),$($g.type),$($g.duration)" '30,2,30' }
Check 'guide-list' { Yes ((K guide-list) -match 'Intro') 'not listed' }
Check 'guide-set' { [void](K guide-set -At 1 -Text Start -NewAt 2); $g = @(Json (SeqProp guides))[0]; Is "$($g.pos),$($g.comment),$($g.type)" '60,Start,2' }
Check 'guide-export' { $o = At 'chapters.txt'; [void](K guide-export -Out $o); Is ([IO.File]::ReadAllText($o).Trim()) '00:02 Start' }
Check 'guide-category' { [void](K guide-category -CategoryIndex 2 -Name Key -Color '#ff0000'); Is (@(Json (MainBin 'kdenlive:docproperties.guidesCategories')) | Where-Object index -eq 2).comment 'Key' }
Check 'guide-remove, guide-clear' {
    [void](K guide-add -At 3 -Text b); [void](K guide-remove -At 3); Is @(Json (SeqProp guides)).Count 1
    [void](K guide-clear); Is @(Json (SeqProp guides)).Count 0
}
Check 'sub-add' { [void](K sub-add -At 1 -Dur 2 -Text 'Привет'); Yes ([IO.File]::ReadAllText("$script:p.ass") -match '0:00:01\.00,0:00:03\.00,.*Привет') 'not in .ass' }
Check 'undo restores subtitles too' { [void](K undo); Yes (-not (Test-Path -LiteralPath "$script:p.ass")) '.ass left behind'; Yes (-not (Seq).SelectSingleNode("filter[property[@name='mlt_service']='avfilter.subtitles']")) 'filter left behind' }
Check 'redo' { [void](K redo); Yes ([IO.File]::ReadAllText("$script:p.ass") -match 'Привет') 'not restored' }
Check 'sub-import' {
    $srt = At 'in.srt'; [IO.File]::WriteAllText($srt, "1`r`n00:00:03,500 --> 00:00:04,500`r`nВторая`r`n")
    [void](K sub-import -File $srt); Yes ([IO.File]::ReadAllText("$script:p.ass") -match '0:00:03\.50,0:00:04\.50,.*Вторая') 'not imported'
}
Check 'sub-export' { $o = At 'out.srt'; [void](K sub-export -Out $o); Yes ([IO.File]::ReadAllText($o) -match '00:00:03,500 --> 00:00:04,500') 'bad srt' }
Check 'subtitles are visible in a render' {
    $a = At 'sub-on.png'; $b = At 'sub-off.png'
    [void](K frame -At 1.5 -Out $a); [void](K frame -At 0.2 -Out $b)
    Yes ((Get-FileHash -LiteralPath $a).Hash -ne (Get-FileHash -LiteralPath $b).Hash) 'frames with and without a subtitle are identical'
}
Check 'sub-state' { [void](K sub-state -Disable -Lock); $f = (Seq).SelectSingleNode("filter[property[@name='mlt_service']='avfilter.subtitles']"); Is (Prop $f 'disable') 1; Is (Prop $f 'kdenlive:locked') 1 }
Check 'zone (-UseInEdits)' { [void](K zone -From 1 -ToTime 4 -UseInEdits); Is (SeqProp zonein) 30; Is (SeqProp zoneout) 120; Is (MainBin 'kdenlive:docproperties.enableTimelineZone') 1 }
Check 'proxy' { [void](K proxy -Enable); Is (MainBin 'kdenlive:docproperties.enableproxy') 1; [void](K proxy -Disable); Is (MainBin 'kdenlive:docproperties.enableproxy') 0 }
Check 'profile-set' { [void](K profile-set -Profile vertical_hd_60); Is (Doc).mlt.profile.frame_rate_num 60; Is (Prop (BinNode red) 'length') 300 }
Check 'profile-from-clip' { [void](K bin-add -File (Kit 'test-video-horizontal.mp4') -Name h); [void](K profile-from-clip -Bin h); Is "$((Doc).mlt.profile.width)x$((Doc).mlt.profile.height) progressive=$((Doc).mlt.profile.progressive)" '1920x1080 progressive=1' }
Check 'clear-history' { [void](K clear-history); Refused undo }
Check 'backups' { [void](K backups) }

# ================ sequences, interchange
Check 'sequence-add, -Sequence, nested clip renders' {
    Project 'seq' @('red', 'v'); [void](K sequence-add -Name Inner -VideoTracks 2 -AudioTracks 1)
    [void](K add -Bin red -Track V1 -At 0 -Dur 2 -Sequence Inner); Is (Shape V1 Inner) '0+60@0'
    [void](K add -Bin Inner -Track V1 -At 0); Is (Shape V1) '0+60@0'
    $c = Pixel 1; Yes ($c.R -gt 220) 'nested sequence renders empty'
}
Check 'sequences' { Yes ((K sequences) -match 'Inner') 'not listed' }
Check 'subtitles of a second sequence use their own file' { [void](K sub-add -At 0 -Dur 1 -Text inner -Sequence Inner); Yes (-not (Test-Path -LiteralPath "$script:p.ass")) 'wrote into the main sequence file' }
Check 'expand' { [void](K expand -Track V1 -At 1); Is (Shape V1) '0+60@0'; Is (Prop @(Items V1)[0].Prod 'mlt_service') 'color' }
Check 'copy-to-sequence' { [void](K sequence-add -Name Part -VideoTracks 3 -AudioTracks 2); [void](K copy-to-sequence -From 0 -ToTime 2 -Target Part -To 1); Is (Shape V1 Part) '30+60@0' }
Check 'otio-export, otio-import' {
    Project 'otio' @('v'); [void](K add -Bin v -Track V1 -At 1 -In 1 -Dur 3); $o = At 't.otio'; [void](K otio-export -Out $o)
    Project 'otio-in'; [void](K otio-import -File $o); Is (Shape V1) '30+90@30'
}
Check 'playlist-clip' { [void](K playlist-clip -File (At 'projects\otio\otio.kdenlive') -Name pl); Is (Prop (BinNode pl) 'mlt_service') 'xml'; Is (Prop (BinNode pl) 'length') 120 }
Check 'archive' {
    $script:p = At 'projects\otio\otio.kdenlive'; $dest = At 'archive'; [void](K archive -Out $dest)
    Yes (Test-Path -LiteralPath "$dest\media\test-video-vertical.mp4") 'media not copied'
    $script:p = "$dest\otio.kdenlive"; Yes ((Prop @(Items V1)[0].Prod 'resource') -like 'media/*') 'path not relative'
}

# ================ jobs: files stay inside the project folder, never overwritten
Check 'extract-audio' {
    Project 'jobs' @('v', 'h'); [void](K extract-audio -Bin v); $f = At 'materials\aigenerated\jobs\extracted\test-video-vertical-audio.wav'
    Yes (Test-Path -LiteralPath $f) 'file is not in materials\aigenerated\<project>'; Yes ([math]::Abs((Seconds $f) - 6) -lt 0.15) 'wrong length'
}
Check 'job results have short relative paths' { foreach ($n in BinNodes) { $r = Prop $n 'resource'; if ($r) { Yes ($r -notmatch '(\.\./){3}') "path climbs out of the folder: $r" } } }
Check 'job results are never overwritten' { [void](K extract-audio -Bin v); Yes (Test-Path -LiteralPath (At 'materials\aigenerated\jobs\extracted\test-video-vertical-audio-2.wav')) 'no second file' }
Check 'transcode' { [void](K transcode -Bin h '-FfArgs:-c:v libx264 -crf 30 -preset ultrafast -an'); $f = At 'materials\aigenerated\jobs\transcoded\test-video-horizontal-transcoded.mp4'; Is (Probe $f 'stream=codec_type').Trim() 'video' }
Check 'transcode: a failing tool fails the command' { Refused transcode -Bin h '-FfArgs:-c:v no_such_codec' }
Check 'stabilize (vid.stab)' {
    [void](K stabilize -Bin v); $f = At 'materials\aigenerated\jobs\stabilized\test-video-vertical-stabilized.mp4'
    Yes ([math]::Abs((Seconds $f) - 6) -lt 0.2) 'wrong length'; Yes ((Probe $f 'stream=width,height') -like '*1080,1920*') 'wrong size'
}
Check 'speed-job' { [void](K speed-job -Bin h -Speed 2); $f = At 'materials\aigenerated\jobs\speed\test-video-horizontal-x2.mp4'; Yes ([math]::Abs((Seconds $f) - 3) -lt 0.2) 'wrong length' }
Check 'scene-split: finds a known cut' {
    $two = At 'materials\aigenerated\two-scenes.mp4'
    & (At 'engine\Kdenlive\kdenlive-26.08.3_standalone\bin\ffmpeg.exe') -v error -f lavfi -i 'color=c=black:s=320x240:r=30:d=2' -f lavfi -i 'color=c=white:s=320x240:r=30:d=2' -filter_complex '[0][1]concat=n=2:v=1' -c:v libx264 $two
    [void](K bin-add -File $two -Name two); [void](K scene-split -Bin two)
    $m = @(Json (Prop (BinNode two) 'kdenlive:markers')); Is $m.Count 1; Yes ([math]::Abs($m[0].pos - 60) -le 1) "cut at $($m[0].pos)"
}

# ================ output
Check 'frame' {
    Project 'out' @('red', 'blue'); [void](K add -Bin red -Track V1 -At 0 -Dur 1); [void](K add -Bin blue -Track V1 -At 1 -Dur 1)
    $a = Pixel 0.5; $b = Pixel 1.5; Yes ($a.R -gt 220 -and $b.B -gt 220) 'wrong colours'; Is "$($a.W)x$($a.H)" '1080x1920'
}
Check 'frame shows titles' {
    # a title with an opaque green background on V2 over the red clip: green only if melt really drew the title
    [void](K title -Text 'T' -Name tt -Bg '#00ff00ff' -Seconds 1); [void](K add -Bin tt -Track V2 -At 0)
    $p = Pixel 0.5 0.1 0.1; Yes ($p.G -gt 200 -and $p.R -lt 60) "title not drawn: $($p.R),$($p.G),$($p.B)"   # a corner: the letter sits in the centre
}
Check 'preview' { $o = At 'preview.mp4'; [void](K preview -Out $o); Yes ([math]::Abs((Seconds $o) - 2) -lt 0.2) 'wrong length' }
Check 'render (Kdenlive renderer)' { $o = At 'render.mp4'; [void](K render -Out $o); Yes ([math]::Abs((Seconds $o) - 2) -lt 0.2) 'wrong length'; Yes ((Probe $o 'stream=width,height') -like '*1080,1920*') 'wrong size' }
Check 'render -Preset' { $o = At 'render.webm'; [void](K render -Preset 'WebM-VP9/Opus (libre)' -Out $o -From 0 -ToTime 0.5); Yes ((Probe $o 'stream=codec_name') -match 'vp9') 'not vp9' }
Check 'render with subtitles' { [void](K sub-add -At 0 -Dur 1 -Text Sub); $o = At 'render-sub.mp4'; [void](K render -Out $o); Yes ([math]::Abs((Seconds $o) - 2) -lt 0.2) 'wrong length' }
Check 'a failed render is not passed off as the previous file' { Refused render -Preset 'no such preset' -Out (At 'render.mp4') }

# ================ moved to another place
Check 'moved folder: still works from the new place, media relative' {
    $script:p = At 'projects\otio\otio.kdenlive'; $before = Pixel 2
    $moved = "$Sandbox перенос"
    Move-Item -LiteralPath $Sandbox $moved
    $script:home2 = $moved; $script:p = At 'projects\otio\otio.kdenlive'
    Is (Shape V1) '30+90@30'; $after = Pixel 2
    Is "$($after.R),$($after.G),$($after.B)" "$($before.R),$($before.G),$($before.B)" 'pixel after the move'
}
Check 'rebase' { [void](K rebase); Is (Doc).mlt.GetAttribute('root') ((Split-Path $script:p -Parent) -replace '\\', '/') }
Check 'moved folder: edit and render subtitles' {
    $script:p = At 'projects\out\out.kdenlive'; [void](K guide-add -At 0 -Text moved)
    Is (Prop (Seq).SelectSingleNode("filter[property[@name='mlt_service']='avfilter.subtitles']") 'av.filename') ("$script:p.ass" -replace '\\', '/')
    $o = At 'render-moved.mp4'; [void](K render -Out $o); Yes ((Seconds $o) -gt 1.8) 'render failed'
}

# ================ every command was run
$cliText = [IO.File]::ReadAllText((At 'engine\kdp.ps1'))
$known = @([regex]::Matches($cliText, "(?m)^\s+'([a-z][a-z-]+)'\s*\{") | ForEach-Object { $_.Groups[1].Value }) + @('undo', 'redo', 'clear-history') | Sort-Object -Unique
$missed = @($known | Where-Object { -not $script:used.ContainsKey($_) })
Check "every command exercised ($($known.Count))" { Yes ($missed.Count -eq 0) "never run: $($missed -join ', ')" }
}
finally {
    $pass = @($script:results | Where-Object { $_ -like 'PASS*' }).Count
    $fail = @($script:results | Where-Object { $_ -like 'FAIL*' }).Count
    $hash = [Security.Cryptography.SHA256]::Create()
    $src = (@('kdp.ps1', 'tools\kdp-core.ps1', 'tools\kdp-ops.ps1', 'tools\kdp-ops2.ps1') | ForEach-Object { [IO.File]::ReadAllText((Join-Path $realEngine $_)) -replace "`r`n", "`n" }) -join "`n"
    $sourceId = [BitConverter]::ToString($hash.ComputeHash([Text.Encoding]::UTF8.GetBytes($src))).Replace('-', '')
    $lines = @("kdp.ps1 end-to-end test, $(Get-Date -Format 'yyyy-MM-dd HH:mm'), $([int]((Get-Date) - $began).TotalSeconds) s", "source: $sourceId", "commands: $((@($script:used.Keys) | Sort-Object) -join ' ')", "PASS $pass  FAIL $fail", '') + $script:results
    if ($Report) { [IO.File]::WriteAllLines([IO.Path]::GetFullPath($(if ([IO.Path]::IsPathRooted($Report)) { $Report } else { Join-Path $realHome $Report })), [string[]]$lines, (New-Object Text.UTF8Encoding($false))) }
    "PASS $pass  FAIL $fail"
    if (-not $Keep) {
        # only the folder this run created
        foreach ($dir in $Sandbox, "$Sandbox перенос") { if (Test-Path -LiteralPath $dir) { Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue } }
    } else { "sandbox: $script:home2" }
}
if ($fail) { exit 1 } else { exit 0 }
