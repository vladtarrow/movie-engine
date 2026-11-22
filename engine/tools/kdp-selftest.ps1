# Builds projects\kdp-selftest\kdp-selftest.kdenlive from scratch using every kdp operation,
# validates it, renders check frames with melt, and prints a report. Safe to re-run.
param([string]$Name = 'kdp-selftest')
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'kdp-core.ps1')
. (Join-Path $PSScriptRoot 'kdp-ops.ps1')
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$dir = Join-Path $root "projects\$Name"; $proj = Join-Path $dir "$Name.kdenlive"
if (Test-Path $dir) { Remove-Item $dir -Recurse -Force }
$kit = Join-Path $root 'materials\aigenerated\test-kit'
$cards = Join-Path $root 'materials\aigenerated\test-kit\cards'
$log = New-Object System.Collections.ArrayList
function Step([string]$what, [scriptblock]$sb) { try { $r = & $sb; [void]$log.Add("OK    $what"); return $r } catch { [void]$log.Add("FAIL  $what :: $($_.Exception.Message)"); return $null } }

Step 'new project vertical_hd_30, 3 video + 2 audio tracks' { New-KdpProject $proj 'vertical_hd_30' 3 2 }
$d = Open-Kdp $proj
$v = Step 'bin: add video+audio file' { Add-KdpMedia $d "$kit\test-video-vertical.mp4" }
$h = Step 'bin: add horizontal video' { Add-KdpMedia $d "$kit\test-video-horizontal.mp4" }
$m = Step 'bin: add music (audio only)' { Add-KdpMedia $d "$kit\test-music.wav" }
$c1 = Step 'bin: add image' { Add-KdpMedia $d "$cards\card-1.png" -imageSeconds 4 }
$c2 = Step 'bin: add image 2' { Add-KdpMedia $d "$cards\card-2.png" -imageSeconds 4 }
$col = Step 'bin: add colour clip' { Add-KdpColor $d '#203060' 'Фон' 4 }
$ti = Step 'bin: add title' { Add-KdpTitle $d "Заголовок`nвторая строка" -seconds 4 -size 110 -place 'center' -outline 4 }
$fid = Step 'bin: add folder and move image into it' { $id = Add-KdpFolder $d 'Карточки'; Move-KdpBinClip $d $c1.BinId $id; $id }
Step 'bin: rename clip' { Rename-KdpBinClip $d $c2.BinId 'Карточка 2' }
Step 'bin: clip marker' { Add-KdpClipMarker $d $v.BinId 1.5 'Маркер в клипе' 2 }
Step 'timeline: image on V1 at 0' { [void](Add-KdpClipToTimeline $d $c1.BinId 'V1' 0 -dur 3) }
Step 'timeline: image 2 on V1 at 3' { [void](Add-KdpClipToTimeline $d $c2.BinId 'V1' 3 -dur 3) }
Step 'timeline: linked video+audio on V1/A1 at 6 (in 1 s)' { Add-KdpAVClip $d $v.BinId 'V1' 'A1' 6 -in 1 -dur 4 }
Step 'timeline: colour on V1 at 10' { [void](Add-KdpClipToTimeline $d $col.BinId 'V1' 10 -dur 4) }
Step 'timeline: title on V2 at 0' { [void](Add-KdpClipToTimeline $d $ti.BinId 'V2' 0 -dur 4) }
Step 'timeline: horizontal video on V3 at 2 (picture in picture later)' { [void](Add-KdpClipToTimeline $d $h.BinId 'V3' 2 -dur 3) }
Step 'timeline: music on A2 at 0' { [void](Add-KdpClipToTimeline $d $m.BinId 'A2' 0 -dur 14) }
Step 'timeline: refuse overlap' { try { [void](Add-KdpClipToTimeline $d $c1.BinId 'V1' 1 -dur 1); throw 'overlap was accepted' } catch { if ($_.Exception.Message -eq 'overlap was accepted') { throw } } }
Step 'timeline: insert with ripple at 3' { [void](Add-KdpClipToTimeline $d $c1.BinId 'V1' 3 -dur 1 -Insert) }
Step 'timeline: ripple delete it again' { Remove-KdpClip $d 'V1' 3.5 -Ripple }
Step 'timeline: split colour at 12' { Split-KdpClip $d 'V1' 12 }
Step 'timeline: trim colour right part to 1.5 s' { Set-KdpClipTrim $d 'V1' 12.5 -newDur 1.5 }
Step 'timeline: move colour right part to 15' { Move-KdpClip $d 'V1' 12.5 'V1' 15 }
Step 'timeline: speed x2 on video clip' { Set-KdpClipSpeed $d 'V1' 7 2 }
Step 'timeline: disable then enable a clip' { Set-KdpClipEnabled $d 'V1' 1 $false; Set-KdpClipEnabled $d 'V1' 1 $true }
Step 'mix: crossfade between images on V1 at 3 (0.5 s)' { Add-KdpMix $d 'V1' 3 0.5 }
Step 'effect: fade in on V1 first clip' { [void](Add-KdpEffect $d 'fade_from_black' 'V1' 0.5 -fadeSeconds 1) }
Step 'effect: fade out on title' { [void](Add-KdpEffect $d 'fade_to_black' 'V2' 1 -fadeSeconds 1) }
Step 'effect: transform (qtblend) keyframes on title' { [void](Add-KdpEffect $d 'qtblend' 'V2' 1 -values @{ rect = '00:00:00.000=0 300 1080 1920 1;00:00:03.000=0 0 1080 1920 1' }) }
Step 'effect: colour correction avfilter.eq on colour clip' { [void](Add-KdpEffect $d 'avfilter.eq' 'V1' 10.5 -values @{ 'av.saturation' = '1.5' }) }
Step 'effect: blur on V1 track' { [void](Add-KdpEffect $d 'avfilter.gblur' 'V1' $null) }
Step 'effect: remove blur from track' { Remove-KdpEffect $d 'V1' $null -effect 'avfilter.gblur' }
Step 'effect: audio fade in on music' { [void](Add-KdpEffect $d 'fadein' 'A2' 1 -fadeSeconds 2) }
Step 'effect: gain 0.5 on music' { [void](Add-KdpEffect $d 'gain' 'A2' 1 -values @{ gain = '0.5' }) }
Step 'effect: set gain to 0.7' { Set-KdpEffect $d 'A2' 1 -effect 'gain' -values @{ gain = '0.7' } }
Step 'effect: master sepia then disable' { [void](Add-KdpEffect $d 'sepia' $null $null -Master); Set-KdpEffect $d $null $null -Master -effect 'sepia' -values @{} -disable $true }
Step 'effect: refuse audio effect on video clip' { try { [void](Add-KdpEffect $d 'fadein' 'V1' 0.5); throw 'accepted' } catch { if ($_.Exception.Message -eq 'accepted') { throw } } }
Step 'composition: picture-in-picture qtblend V3 over V1 2-5 s' { [void](Add-KdpComposition $d 'qtblend' 'V3' 2 3 -values @{ rect = '00:00:00.000=540 1200 480 270 1' }) }
Step 'composition: dissolve on V2 over V1' { [void](Add-KdpComposition $d 'dissolve' 'V2' 3 1) }
Step 'composition: remove dissolve' { Remove-KdpComposition $d 'V2' 3.5 }
Step 'track: add video track V4' { Add-KdpTrack $d -name 'Extra' }
Step 'track: add audio track (becomes A3)' { Add-KdpTrack $d -Audio -name 'Voice' }
Step 'track: rename, lock, mute A3' { Set-KdpTrack $d 'A3' 'Голос' $true $true }
Step 'track: remove empty V4' { Remove-KdpTrack $d 'V4' }
Step 'guides: two guides' { Add-KdpGuide $d 0 'Начало' 0; Add-KdpGuide $d 6 'Видео' 2 1 }
Step 'subtitles: two lines' { Add-KdpSubtitle $d 0.5 2 'Первый субтитр'; Add-KdpSubtitle $d 3 2 'Второй субтитр' }
Step 'group: user group of two V1 clips' { Add-KdpUserGroup $d @('V1@0.5', 'V1@10.5') }
# --- second batch of features ---
Step 'speed: linked clip back to 1x via the audio half (video half follows)' { Set-KdpClipSpeed $d 'A1' 6.5 1; $v1 = Find-KdpClip $d 'V1' 6.5; if ([math]::Abs($v1.Dur - 4) -gt 0.05) { throw "video half not updated: dur $($v1.Dur)" }; Set-KdpClipSpeed $d 'A1' 6.5 2 }
Step 'mix: second crossfade on V1 (video -> colour at 8, after trimming colour start)' { Set-KdpClipTrim $d 'V1' 10.5 -newIn 1 -newDur 2 -KeepEnd; Add-KdpClipToTimeline $d $col.BinId 'V1' 8 -dur 3 -Overwrite | Out-Null; Add-KdpMix $d 'V1' 8 0.5 }
Step 'mix: unmix the second one by time, then mix again' { Remove-KdpMix $d 'V1' 8; Add-KdpMix $d 'V1' 8 0.5 }
Step 'guard: speed change of a clip that starts a crossfade is refused' { try { Set-KdpClipSpeed $d 'V1' 6.5 1; throw 'accepted' } catch { if ($_.Exception.Message -eq 'accepted') { throw 'speed change on a mixed clip was accepted' } } }
$sb = Step 'sequence: add sequence B (1 video, 0 audio)' { Add-KdpSequence $d 'Вставка' 1 0 }
Step 'sequence: put a colour clip and a title inside B' { Select-KdpSequence $d 'Вставка'; [void](Add-KdpClipToTimeline $d $col.BinId 'V1' 0 -dur 2); Select-KdpSequence $d '' }
$ss = Step 'slideshow: 3 numbered images, 1 s each, fade' { Add-KdpSlideshow $d "$kit\slides\img_%04d.png" -perImage 1 -name 'Слайды' -Fade }
$an = Step 'animation: Lottie JSON' { Add-KdpMedia $d "$kit\test-anim.json" }
Step 'timeline: sequence B on V3 at 6' { [void](Add-KdpClipToTimeline $d 'Вставка' 'V3' 6) }
Step 'timeline: slideshow on V3 at 9' { [void](Add-KdpClipToTimeline $d $ss.BinId 'V3' 9) }
Step 'timeline: animation on V2 at 5' { [void](Add-KdpClipToTimeline $d $an.BinId 'V2' 5) }
$hv = Step 'remap: horizontal video, constant 0.5x' { [void](Add-KdpClipToTimeline $d $h.BinId 'V2' 12 -in 0 -dur 2); Set-KdpTimeRemap $d 'V2' 12.5 '' 0.5 }
Step 'proxy: enable then disable' { Set-KdpProxy $d $true; Set-KdpProxy $d $false }
Step 'image longer than its bin length: producer length grows (melt would cut it short)' {
    $lp = Join-Path $dir 'len-check.kdenlive'; New-KdpProject $lp 'vertical_hd_30' 1 0; $ld = Open-Kdp $lp
    $li = Add-KdpMedia $ld "$cards\card-1.png" -imageSeconds 1
    [void](Add-KdpClipToTimeline $ld $li.BinId 'V1' 0 -dur 3); Set-KdpClipTrim $ld 'V1' 1 -newDur 4
    $len = [int](Get-KdpProp (Get-KdpBinClip $ld $li.BinId).Node 'length'); Remove-Item $lp
    if ($len -lt 120) { throw "producer length $len < 120 frames" } }
Step 'save' { Save-Kdp $d }
$d = Open-Kdp $proj
$problems = Test-KdpProject $d
"=== steps"; $log
"=== validation: " + $(if ($problems.Count) { "$($problems.Count) problem(s)" } else { 'clean' }); $problems
"=== timeline"; Get-KdpClips $d | Sort-Object Track, Sub, Start | Format-Table Track, Sub, Start, End, In, Name, @{ n = 'Effects'; e = { $_.Effects -join ',' } } -AutoSize | Out-String -Width 200
"=== compositions"; Get-KdpCompositions $d | Format-Table Id, Track, Below, Start, End -AutoSize | Out-String
"=== tracks"; Get-KdpTracks $d | Format-Table Name, Label, Index -AutoSize | Out-String
if (@($log | Where-Object { $_ -like 'FAIL*' }).Count -or $problems.Count) { exit 1 }
exit 0
