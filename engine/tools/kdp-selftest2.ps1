# Second regression test: every operation of kdp-ops2.ps1, on projects\kdp-selftest2.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'kdp-core.ps1'); . (Join-Path $PSScriptRoot 'kdp-ops.ps1'); . (Join-Path $PSScriptRoot 'kdp-ops2.ps1')
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$dir = Join-Path $root 'projects\kdp-selftest2'; $proj = Join-Path $dir 'kdp-selftest2.kdenlive'
if (Test-Path $dir) { Remove-Item $dir -Recurse -Force }
$scratch = Join-Path $root '.shots\selftest2'; New-Item -ItemType Directory -Force $scratch | Out-Null
$kit = Join-Path $root 'materials\aigenerated\test-kit'; $cards = Join-Path $root 'materials\aigenerated\test-kit\cards'
$log = New-Object System.Collections.ArrayList
function Step([string]$what, [scriptblock]$sb) { try { $r = & $sb; [void]$log.Add("OK    $what"); return $r } catch { [void]$log.Add("FAIL  $what :: $($_.Exception.Message)"); return $null } }

Step 'new project' { New-KdpProject $proj 'vertical_hd_30' 3 2 }
$d = Open-Kdp $proj
$v = Step 'bin video' { Add-KdpMedia $d "$kit\test-video-vertical.mp4" }
$h = Step 'bin video 2' { Add-KdpMedia $d "$kit\test-video-horizontal.mp4" }
$c1 = Step 'bin card' { Add-KdpMedia $d "$cards\card-1.png" -imageSeconds 3 }
$c2 = Step 'bin card 2' { Add-KdpMedia $d "$cards\card-2.png" -imageSeconds 3 }
$m = Step 'bin music' { Add-KdpMedia $d "$kit\test-music.wav" }
Step 'timeline base' { [void](Add-KdpClipToTimeline $d $c1.BinId 'V1' 0 -dur 3); [void](Add-KdpClipToTimeline $d $v.BinId 'V1' 3 -in 1 -dur 3); [void](Add-KdpClipToTimeline $d $c2.BinId 'V1' 7 -dur 3); [void](Add-KdpClipToTimeline $d $m.BinId 'A1' 0 -dur 10) }
Step 'copy clip V1@1 -> V2@10' { Copy-KdpClip $d 'V1' 1 'V2' 10 }
Step 'effects + paste effects V1@1 -> V2@11 (fade keeps length)' { [void](Add-KdpEffect $d 'fade_from_black' 'V1' 1 -fadeSeconds 1); [void](Add-KdpEffect $d 'sepia' 'V1' 1); Copy-KdpEffects $d 'V1' 1 'V2' 11; if (@((Find-KdpClip $d 'V2' 11).Effects).Count -ne 2) { throw 'effects not pasted' } }
Step 'clear effects on V2@11' { Clear-KdpEffects $d 'V2' 11; if (@((Find-KdpClip $d 'V2' 11).Effects).Count) { throw 'not cleared' } }
Step 'bin effect on card 2 (all uses)' { Add-KdpBinEffect $d $c2.BinId 'avfilter.hflip' }
Step 'disable then enable all timeline effects' { Set-KdpAllEffects $d $false; Set-KdpAllEffects $d $true }
Step 'group then ungroup' { Add-KdpUserGroup $d @('V1@1', 'V1@8'); Remove-KdpGroup $d 'V1' 1; if ((Get-KdpProp (Get-KdpSequence $d) 'kdenlive:sequenceproperties.groups') -match 'Normal') { throw 'group still there' } }
Step 'slip video by +1 s' { Invoke-KdpSlip $d 'V1' 4 1; if ((Find-KdpClip $d 'V1' 4).In -ne 2) { throw 'in not moved' } }
Step 'ripple trim video to 2 s (card 2 moves left)' { Invoke-KdpRippleTrim $d 'V1' 4 $null 2; if ((Find-KdpClip $d 'V1' 6.5).Start -ne 6) { throw 'next clip did not move' } }
Step 'insert 1 s space at 5 on all tracks' { Add-KdpSpace $d 5 1 @('V1', 'V2', 'V3') }
Step 'remove that space again' { Remove-KdpSpace $d 5.2 -1 @('V1', 'V2', 'V3') }
Step 'remove all spaces on V2' { Remove-KdpAllSpaces $d 'V2'; if ((Find-KdpClip $d 'V2' 0.5).Start -ne 0) { throw 'not packed' } }
Step 'clear track V3' { [void](Add-KdpClipToTimeline $d $c1.BinId 'V3' 0 -dur 1); Clear-KdpTrack $d 'V3'; if (@(Get-KdpClips $d | Where-Object Track -eq 'V3').Count) { throw 'not cleared' } }
Step 'clip markers: add, edit, list, remove one, remove all' { Add-KdpClipMarker $d $v.BinId 1 'A'; Add-KdpClipMarker $d $v.BinId 2 'B'; Set-KdpClipMarker $d $v.BinId 1 'A2' 3 $null; if (@(Get-KdpClipMarkers $d $v.BinId).Count -ne 2) { throw 'count' }; Remove-KdpClipMarker $d $v.BinId 2; Remove-KdpClipMarker $d $v.BinId $null; Add-KdpClipMarker $d $v.BinId 1 'Final' }
Step 'guides: add, edit, export chapters, category' { Add-KdpGuide $d 0 'Intro'; Add-KdpGuide $d 3 'Video'; Set-KdpGuide $d 3 'Видео' 2 $null 1; Export-KdpGuides $d "$scratch\chapters.txt"; if ((Get-Content "$scratch\chapters.txt").Count -ne 2) { throw 'chapters' }; Set-KdpGuideCategory $d 2 'Важное' '#ff0000' }
Step 'subtitles: import srt, export srt, disable+enable, lock' { [IO.File]::WriteAllText("$scratch\in.srt", "1`r`n00:00:00,500 --> 00:00:02,000`r`nПервая строка`r`n`r`n2`r`n00:00:03,000 --> 00:00:04,500`r`nВторая`r`nстрока`r`n", (New-Object Text.UTF8Encoding($false))); if ((Import-KdpSrt $d "$scratch\in.srt") -ne 2) { throw 'import' }; if ((Export-KdpSrt $d "$scratch\out.srt") -ne 2) { throw 'export' }; Set-KdpSubtitleState $d $true $null; Set-KdpSubtitleState $d $false $true }
Step 'zone 1-6 s' { Set-KdpZone $d 1 6 }
Step 'bin: info, set props, duplicate, rename' { $i = Get-KdpBinInfo $d $v.BinId; if (-not $i.Uses) { throw 'no uses' }; Set-KdpBinProps $d $v.BinId @{ 'kdenlive:description' = 'тест'; 'kdenlive:rating' = 4 }; $dup = Copy-KdpBinClip $d $c1.BinId 'Карточка копия'; Rename-KdpBinClip $d $dup.BinId 'Копия' }
Step 'bin: replace file of card 1 with card 3, then back' { Set-KdpBinFile $d $c1.BinId "$cards\card-3.png"; Set-KdpBinFile $d $c1.BinId "$cards\card-1.png" }
Step 'bin: reload video' { Update-KdpBinClip $d $v.BinId }
Step 'replace in timeline: card 2 -> card 1' { if ((Set-KdpReplaceInTimeline $d $c2.BinId $c1.BinId) -lt 1) { throw 'nothing replaced' } }
Step 'generators: counter, noise, colour bars' { [void](Add-KdpGenerator $d 'count' 3); [void](Add-KdpGenerator $d 'noise' 2); [void](Add-KdpGenerator $d 'frei0r.test_pat_B' 2 @{ '0' = 4 }) }
Step 'generator on timeline V3 at 0' { $g = Get-KdpBinClips $d | Where-Object Service -eq 'count'; [void](Add-KdpClipToTimeline $d $g.BinId 'V3' 0 -dur 2) }
Step 'title template: save title, add template clip with text' { $t = Add-KdpTitle $d 'Шаблон %s' -seconds 2; Save-KdpTitleTemplate $d $t.BinId "$dir\tpl.kdenlivetitle"; $tc = Add-KdpTitleTemplateClip $d "$dir\tpl.kdenlivetitle" 'подставлено' 2; [void](Add-KdpClipToTimeline $d $tc.BinId 'V3' 2 -dur 2) }
Step 'playlist clip: the first self-test project as a clip on V3 at 5' { $pc = Add-KdpPlaylistClip $d (Join-Path $root 'projects\kdp-selftest\kdp-selftest.kdenlive'); [void](Add-KdpClipToTimeline $d $pc.BinId 'V3' 5 -dur 2) }
Step 'extract audio of video into bin' { [void](Invoke-KdpExtractAudio $d $v.BinId (Join-Path $root 'materials\aigenerated\test-kit\extracted')) }
Step 'transcode horizontal video (new clip)' { [void](Invoke-KdpTranscode $d $h.BinId '-c:v libx264 -crf 30 -preset ultrafast -an' 'mp4' -outDir (Join-Path $root 'materials\aigenerated\test-kit\transcoded')) }
Step 'sequences: copy range to new sequence, use it, expand it' { [void](Add-KdpSequence $d 'Фрагмент' 3 2); if ((Copy-KdpRangeToSequence $d 0 3 'Фрагмент' 0) -lt 1) { throw 'nothing copied' }; [void](Add-KdpClipToTimeline $d 'Фрагмент' 'V2' 14 -dur 3); $r = Expand-KdpSequenceClip $d 'V2' 15; if ($r -notmatch '^[1-9]') { throw "expand: $r" } }
Step 'ambiguous bin name is refused' { try { [void](Get-KdpBinClip $d 'card-1.png'); [void](Copy-KdpBinClip $d 'card-1.png' 'card-1.png'); [void](Get-KdpBinClip $d 'card-1.png'); throw 'accepted' } catch { if ($_.Exception.Message -eq 'accepted') { throw 'two clips with one name were not refused' } } }
Step 'subclip zone on the video clip' { Add-KdpSubclip $d $v.BinId 1 3 'Средняя часть'; if (@(Get-KdpSubclips $d $v.BinId).Count -ne 1) { throw 'no subclip' } }
Step 'clip job: stabilize video (new clip)' { [void](Invoke-KdpStabilize $d $v.BinId) }
Step 'clip job: scene split (markers at cuts)' { [void](Invoke-KdpSceneSplit $d $v.BinId) }
Step 'clip job: speed x2 (new file)' { $s = Invoke-KdpSpeedJob $d $h.BinId 2; if ([int]$s.Length -lt 80 -or [int]$s.Length -gt 100) { throw "length $($s.Length) frames, expected ~90" } }
Step 'effect template shut_off on V1 first clip' { if ((Add-KdpEffectTemplate $d 'shut_off' 'V1' 1) -lt 3) { throw 'too few effects' } }
Step 'animation via its own function' { [void](Add-KdpAnimation $d "$kit\test-anim.json" 'Анимация') }
Step 'remove a bin clip' { $x = Add-KdpColor $d '#123456' 'Удалить меня' 2; Remove-KdpBinClip $d $x.BinId; if (Get-KdpBinClips $d | Where-Object Name -eq 'Удалить меня') { throw 'still in bin' } }
Step 'guides: remove one, clear all, add back' { Add-KdpGuide $d 9 'temp'; Remove-KdpGuide $d 9; if (Get-KdpGuides $d | Where-Object Comment -eq 'temp') { throw 'not removed' }; Clear-KdpGuides $d; if (@(Get-KdpGuides $d).Count) { throw 'not cleared' }; Add-KdpGuide $d 0 'Intro' }
Step 'relink a moved file' { $tmpDir = Join-Path $scratch 'relink'; New-Item -ItemType Directory -Force $tmpDir | Out-Null; Copy-Item "$cards\card-3.png" "$tmpDir\moved-card.png" -Force; $mc = Add-KdpMedia $d "$tmpDir\moved-card.png"; $moved = Join-Path $scratch 'relink-new'; New-Item -ItemType Directory -Force $moved | Out-Null; Move-Item "$tmpDir\moved-card.png" "$moved\moved-card.png" -Force; $r = Update-KdpMissingMedia $d $moved; if (-not $r) { throw 'not relinked' }; Remove-KdpBinClip $d $mc.BinId }
Step 'Kdenlive backups list' { [void](@(Get-KdpBackups $d)) }
Step 'profile matching a clip' { if ((Find-KdpProfileForClip $d $h.BinId) -notmatch '^\w') { throw 'no profile' } }
Step 'clean unused bin clips' { [void](Remove-KdpUnusedClips $d) }
Step 'save' { Save-Kdp $d }
$d = Open-Kdp $proj
Step 'archive project' { $a = Export-KdpArchive $d (Join-Path $scratch 'archive'); if (-not (Test-Path $a)) { throw 'no archive' } }
Step 'OTIO export + import into a new project' { Export-KdpOtio $d "$scratch\tl.otio"; $p2 = Join-Path $scratch 'otio-import\otio-import.kdenlive'; if (Test-Path (Split-Path $p2)) { Remove-Item (Split-Path $p2) -Recurse -Force }; New-KdpProject $p2 'vertical_hd_30' 3 2; $d2 = Open-Kdp $p2; $n = Import-KdpOtio $d2 "$scratch\tl.otio"; Save-Kdp $d2; if ($n -lt 3) { throw "only $n clips imported" } }
Step 'profile change to vertical_hd_60 and back (frame counts rescaled)' { $copy = Join-Path $scratch 'fps.kdenlive'; Copy-Item $proj $copy -Force; $d3 = Open-Kdp $copy; $d3.Root = $d.Root; Set-KdpProfile $d3 'vertical_hd_60'; Save-Kdp $d3; $d3 = Open-Kdp $copy; if ($d3.Fps -ne 60) { throw 'fps' }; Set-KdpProfile $d3 'vertical_hd_30'; Save-Kdp $d3 }
Step 'undo / redo snapshots' { $u = Join-Path $scratch 'undo.kdenlive'; Copy-Item $proj $u -Force; $h0 = (Get-FileHash $u).Hash; Save-KdpSnapshot $u; $du = Open-Kdp $u; $du.Root = $d.Root; Add-KdpGuide $du 9 'x'; Save-Kdp $du; $h1 = (Get-FileHash $u).Hash; Undo-KdpProject $u; if ((Get-FileHash $u).Hash -ne $h0) { throw 'undo failed' }; Undo-KdpProject $u -Redo; if ((Get-FileHash $u).Hash -ne $h1) { throw 'redo failed' } }
Step 'render presets: MP4 H.264 and WebM VP9 (1 s)' { foreach ($pp in 'MP4-H264/AAC', 'WebM-VP9/Opus (libre)') { $o = Join-Path $scratch ('preset-' + ($pp -replace '[^\w]', '') + $(if ($pp -like 'MP4*') { '.mp4' } else { '.webm' })); Remove-Item $o -ErrorAction SilentlyContinue; [void](Export-KdpPreset $d $pp $o $null 1 2); if (-not (Test-Path $o)) { throw "no output for $pp" } } }
$problems = Test-KdpProject (Open-Kdp $proj)
"=== steps"; $log
"=== validation: " + $(if ($problems.Count) { "$($problems.Count) problem(s)" } else { 'clean' }); $problems
"=== timeline"; Get-KdpClips (Open-Kdp $proj) | Sort-Object Track, Sub, Start | Format-Table Track, Sub, Start, End, In, Name, @{ n = 'Effects'; e = { $_.Effects -join ',' } } -AutoSize | Out-String -Width 200
if (@($log | Where-Object { $_ -like 'FAIL*' }).Count -or $problems.Count) { exit 1 }
exit 0
