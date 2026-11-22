# kdp.ps1 - command line for editing a Kdenlive 26.08 project without the GUI.
# Every project command, reading ones too, first makes the running Kdenlive save the user's edits (pull) and
# stops if that cannot be confirmed. An edit is written only if the user changed nothing meanwhile.
# kd-watch.ps1 (if running for this project) makes the open Kdenlive show the change.
# Linked audio+video halves follow move, trim, split, remove, slip and ripple-trim (-Alone = only this half).
# Failures exit with code 1 and write nothing. Seconds use a dot: 2.5, not 2,5.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File engine\kdp.ps1 <command> -Project <file.kdenlive> [options]
#
# Times are seconds. Tracks: V1 V2 ... (video, V1 lowest), A1 A2 ... (audio, A1 nearest video).
# A clip is addressed by -Track and any time -At inside it. Params: -Params "name=value||name=value".
#
# PROJECT   new -Profile vertical_hd_30 [-VideoTracks 2 -AudioTracks 2]   | profiles [-Search hd]
#           info | validate | fonts [-Search text]
# BIN       bin-add -File f [-Name n] [-Seconds 5] | bin-color -Color '#RRGGBB' [-Seconds 5] [-Name n]
#           title -Text "line1`nline2" [-Seconds 5 -Font 'Segoe UI' -Size 96 -Color '#FFFFFF' -Place center|top|bottom|lower-third
#                 -X -Y -Weight 700 -OutlineColor '#000000' -Outline 0 -Bg '#00000000' -Align center|left|right -Name n]
#           title-text -Bin id -Text t | bin-rename -Bin id -Name n | bin-remove -Bin id [-Force]
#           folder -Name n [-Parent id] | bin-folder -Bin id -Folder id|name|root | marker -Bin id -At s -Text t [-Category 0..8 -Dur s]
# TIMELINE  add -Bin id -Track V1 -At 0 [-In 0] [-Dur s] [-Overwrite|-Insert] | add-av -Bin id -Track V1 -AudioTrack A1 -At 0 [-In -Dur]
#           move -Track V1 -At 3 [-ToTrack V2] -To 10 [-Overwrite] | trim -Track V1 -At 3 [-NewIn s] [-NewDur s] [-KeepEnd]
#           split -Track V1 -At 4.5 | remove -Track V1 -At 3 [-Ripple] | speed -Track V1 -At 3 -Speed 2 (negative = reverse) [-KeepPitch]
#           disable / enable -Track V1 -At 3 | group -Clips "V1@0.5,V2@1" | mix -Track V1 -At <cut> [-Dur 1] | unmix -Track V1
# EFFECTS   effects [-Search text] [-Category text] | effect-info -Id id
#           effect-add -Id id (-Track V1 [-At 3] | -Master) [-Params ...] [-Fade 1] | effect-list (-Track V1 [-At 3] | -Master)
#           effect-set -Effect id|index (-Track .. [-At ..] | -Master) [-Params ...] [-Disable|-Enable] | effect-remove -Effect id|index ...
# COMPOSE   compositions [-Search text] | comp-info -Id id | comp-add -Id id -Track V2 -At 0 -Dur 3 [-Below V1] [-Params ...]
#           comp-list | comp-set -Track V2 -At 1 -Params ... | comp-remove -Track V2 -At 1
# TRACKS    track-add [-Audio] [-Name n] | track-remove -Track V3 [-Force] | track-set -Track A1 [-Name n] [-Lock|-Unlock] [-Hide|-Show]
# GUIDES    guide-add -At s -Text t [-Category 0..8 -Dur s] | guide-list | guide-remove -At s
# SUBTITLES sub-add -At s -Dur s -Text t
# SEQUENCES sequence-add -Name n [-VideoTracks 2 -AudioTracks 1] | sequences
#           any command + -Sequence <name|uuid|bin id> works inside that sequence (default: the main one)
#           use a sequence as a clip: add -Bin <sequence name> -Track V1 -At 0
# SPECIAL   slideshow -File <folder | C:\..\img_%04d.png> [-Ext png -Seconds 1 (per image) -Loop -Crop -FadeSlides -Animation Pan|Zoom|"Pan and zoom"]
#           bin-add of .json/.rawr/.lottie adds a Lottie/Glaxnimate animation
#           remap -Track V1 -At 3 (-Speed 0.5 | -Map "0=2;1.5=4;3=4.5") [-KeepPitch -Blend]  (out-seconds=source-seconds)
#           proxy -Enable|-Disable   (Kdenlive generates proxy files itself when the project is open)
# OUTPUT    frame -At s -Out file.png [-Width 540] | preview [-From s -To s] [-Out f.mp4] (melt, fast)
#           render [-Out out\<name>\<name>-vNN.mp4]   (Kdenlive's own renderer, hidden, final quality)
#           presets | render -Preset "WebM-VP9/Opus (libre)" [-Quality 25] [-From s -ToTime s] [-Out f]   (melt with a Kdenlive/MLT preset)
# HISTORY   undo | redo | clear-history   (snapshots of project + subtitles in projects\<p>\.kdp-history)
# EDIT      copy -Track V1 -At 3 [-ToTrack V2] -To 10 [-Overwrite|-Insert] | effect-copy -Track V1 -At 3 -ToTrack V1 -To 10 [-Force = replace]
#           effect-clear (-Track V1 [-At 3] | -Master) | effects-all -Disable|-Enable | bin-effect -Bin id -Id effect [-Params ...]
#           ungroup -Track V1 -At 3 | slip -Track V1 -At 3 -By 0.5 | ripple-trim -Track V1 -At 3 [-NewIn s] [-NewDur s]
#           space-insert -At s -Dur s [-Tracks "V1,A1"] | space-remove -At s [-Dur s] [-Tracks ...] | spaces-remove-all -Track V1 | track-clear -Track V1
#           copy-to-sequence -From s -ToTime s -Target <sequence> [-To s] | expand -Track V1 -At 3 (nested sequence -> its clips)
# BIN MORE  bin-info -Bin id | bin-set -Bin id -Params "force_fps=25||kdenlive:description=..." | bin-duplicate -Bin id [-Name n]
#           bin-replace-file -Bin id -File f | bin-reload -Bin id | relink -Folder dir | replace-in-timeline -Bin A -With B | clean
#           generator -Id count|noise|frei0r.test_pat_B [-Seconds 5] [-Params ...] | playlist-clip -File other.kdenlive|x.mlt
#           title-save -Bin id -File t.kdenlivetitle | title-template -File t.kdenlivetitle -Text "replaces %s" [-Seconds 5]
#           extract-audio -Bin id | transcode -Bin id ["-FfArgs:-c:v libx264 -crf 18 -c:a aac" (colon, one argument: the value starts with a dash)] [-Ext mp4] [-Replace]
# MARKERS   marker-list -Bin id | marker-set -Bin id -At s [-Text t] [-CategoryIndex n] [-NewAt s] | marker-remove -Bin id [-At s]
#           guide-set -At s [-Text t] [-CategoryIndex n] [-NewAt s] [-Dur s] | guide-clear | guide-export -Out chapters.txt [-Format "{timecode} {comment}"]
#           guide-category -CategoryIndex n [-Name n] [-Color '#rrggbb']
# SUBS MORE sub-import -File x.srt [-At offset] | sub-export -Out x.srt | sub-state [-Disable|-Enable] [-Lock|-Unlock]
# MOVED     rebase   (write today's folder into a copied or moved project)
# PROJECT+  zone -From s -ToTime s [-UseInEdits] | profile-set -Profile name | profile-from-clip -Bin id | archive -Out folder | backups
#           otio-export -Out f.otio | otio-import -File f.otio [-At s]
# JOBS      stabilize -Bin id [-Replace] | scene-split -Bin id (markers at cuts) | speed-job -Bin id -Speed 2 (new file)
#           effect-templates | effect-template -Id shut_off -Track V1 -At 3 | subclip -Bin id -From s -ToTime s [-Name n]
param(
    [Parameter(Mandatory, Position = 0)][string]$Command,
    [string]$Project,
    [string]$File, [string]$Name, [double]$Seconds = 5, [string]$Color, [string]$Text,
    [string]$Bin, [string]$Track, $At = $null, [double]$In = 0, [double]$Dur = -1,
    [string]$ToTrack, [double]$To = 0, $NewIn = $null, $NewDur = $null, [double]$Speed = 1,
    [string]$AudioTrack, [string]$Clips, [string]$Id, [string]$Effect, [string]$Params, [double]$Fade = 1,
    [string]$Below, [string]$Search, [string]$Category, [string]$Folder, [string]$Parent = '-1', [int]$CategoryIndex = 0,
    [string]$Font = 'Segoe UI', [int]$Size = 96, [string]$Place = 'center', [int]$X = 0, [int]$Y = 0, [int]$Weight = 700,
    [string]$OutlineColor = '#000000', [int]$Outline = 0, [string]$Bg = '#00000000', [string]$Align = 'center',
    [string]$Profile = 'vertical_hd_30', [int]$VideoTracks = 2, [int]$AudioTracks = 2,
    [switch]$Overwrite, [switch]$Insert, [switch]$KeepEnd, [switch]$Ripple, [switch]$NoPull, [switch]$Master, [switch]$Audio,
    [switch]$Force, [switch]$KeepPitch, [switch]$Disable, [switch]$Enable, [switch]$Lock, [switch]$Unlock, [switch]$Hide, [switch]$Show,
    $From = $null, $ToTime = $null, [int]$Width = 0, [string]$Out,
    [string]$Sequence, [string]$Ext = 'png', [switch]$Loop, [switch]$Crop, [switch]$FadeSlides, [string]$Animation = '', [string]$Map,
    [switch]$Blend, [string]$Preset, $Quality = $null,
    [double]$By = 0, [string]$Tracks, [string]$Target, [string]$With, [string]$FfArgs = '-c:v libx264 -crf 18 -preset medium -c:a aac -b:a 192k',
    [switch]$Replace, [string]$Format = '{timecode} {comment}', $NewAt = $null,
    [switch]$Alone, [switch]$UseInEdits
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'tools\kdp-core.ps1')
. (Join-Path $PSScriptRoot 'tools\kdp-ops.ps1')
. (Join-Path $PSScriptRoot 'tools\kdp-ops2.ps1')
$p = ConvertFrom-KdpParamString $Params
# PowerShell reads "2,5" as 25
foreach ($pair in @(('At', $At), ('NewIn', $NewIn), ('NewDur', $NewDur), ('From', $From), ('ToTime', $ToTime), ('NewAt', $NewAt))) {
    if ("$($pair[1])" -match ',') { throw "-$($pair[0]) '$($pair[1])': write seconds with a dot (2.5)" }
}
$atD = if ($null -ne $At -and "$At" -ne '') { [double]$At } else { $null }
$markerCategory = $null
if ($PSBoundParameters.ContainsKey('CategoryIndex')) { $markerCategory = $CategoryIndex }
elseif ($Category -match '^\d+$') { $markerCategory = [int]$Category }

# commands that need no project
switch ($Command) {
    'effects' { Get-KdpEffectCatalog | Where-Object { (-not $Search -or $_.Id -like "*$Search*" -or $_.Name -like "*$Search*" -or $_.Description -like "*$Search*") -and (-not $Category -or $_.Category -like "*$Category*") } | Format-Table Id, Type, Category, Name -AutoSize | Out-String -Width 220; return }
    'effect-info' { $e = Get-KdpEffectDef $Id; "$($e.Id)  tag=$($e.Tag)  type=$($e.Type)  unique=$($e.Unique)  category=$($e.Category)`n$($e.Name): $($e.Description)"; $e.Params | Format-Table Name, Type, Default, Min, Max, Factor, Label -AutoSize | Out-String -Width 220; return }
    'compositions' { Get-KdpTransitionCatalog | Where-Object { -not $Search -or $_.Id -like "*$Search*" -or $_.Name -like "*$Search*" } | Format-Table Id, Tag, Type, Name -AutoSize | Out-String -Width 200; return }
    'comp-info' { $e = Get-KdpTransitionDef $Id; "$($e.Id)  tag=$($e.Tag)  type=$($e.Type)`n$($e.Name): $($e.Description)"; $e.Params | Format-Table Name, Type, Default, Min, Max, Factor, Label -AutoSize | Out-String -Width 220; return }
    'profiles' { Get-ChildItem $script:KdpProfiles | ForEach-Object { $c = Get-Content $_.FullName; [pscustomobject]@{ Profile = $_.Name; Description = (($c | Where-Object { $_ -like 'description=*' }) -replace 'description=') } } | Where-Object { -not $Search -or $_.Profile -like "*$Search*" -or $_.Description -like "*$Search*" } | Format-Table -AutoSize | Out-String -Width 200; return }
    'fonts' { Add-Type -AssemblyName System.Drawing; (New-Object System.Drawing.Text.InstalledFontCollection).Families | Where-Object { -not $Search -or $_.Name -like "*$Search*" } | ForEach-Object Name; return }
    'new' {
        if (-not $Project) { throw '-Project is required' }
        $Project = [IO.Path]::GetFullPath($(if ([IO.Path]::IsPathRooted($Project)) { $Project } else { Join-Path (Get-Location).Path $Project }))
        if ((Test-Path -LiteralPath $Project) -and -not $Force) { throw "$Project already exists; -Force replaces it" }
        if (Test-Path -LiteralPath $Project) { Save-KdpSnapshot $Project }
        New-KdpProject $Project $Profile $VideoTracks $AudioTracks; Set-KdWriteStamp $Project (Get-KdHash $Project); "created $Project ($Profile, $VideoTracks video + $AudioTracks audio tracks)"; return }
    'effect-templates' { . (Join-Path $PSScriptRoot 'tools\kdp-ops2.ps1'); Get-KdpEffectTemplates | Format-Table Name, Effects, Description -AutoSize | Out-String -Width 220; return }
    'presets' { Get-KdpRenderPresets | Where-Object { -not $Search -or $_.Name -like "*$Search*" -or $_.Group -like "*$Search*" } | Format-Table Group, Name, Ext, Args -AutoSize | Out-String -Width 260; return }
}
if (-not $Project) { throw '-Project is required' }
$Project = (Resolve-Path $Project).Path
$readOnly = $Command -in 'info', 'validate', 'render', 'preview', 'frame', 'effect-list', 'comp-list', 'guide-list', 'marker-list', 'sequences', 'bin-info', 'guide-export', 'sub-export', 'archive', 'backups', 'otio-export', 'title-save'
$projectLock = Enter-KdLock $Project
$assBefore = $null
$written = $false
try {
$window = $null
if (-not $NoPull -and (Get-Process kdenlive -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'tools\kd-ui.ps1')
    $pull = Invoke-KdPull $Project
    if ($pull.Code -ne 0 -and $pull.Code -ne 3) { throw "Could not get the user's edits from Kdenlive, so nothing was read or changed: $($pull.Message)" }
    if ($pull.Code -eq 0) { $window = Find-KdWindow $Project }
}
if ($Command -eq 'clear-history') { Clear-KdpHistory $Project; 'history cleared'; return }
if ($Command -in 'undo', 'redo') { Undo-KdpProject $Project -Redo:($Command -eq 'redo'); "$Command done"; return }
$d = Open-Kdp $Project
if ($readOnly) { Exit-KdLock $projectLock; $projectLock = $null }     # the document is in memory; do not block a reload during a render
else { $assBefore = Get-KdpAssState $Project }
$anchors = @{}
if (-not $readOnly -and $Command -notin 'track-add', 'track-remove', 'add-av', 'group', 'ungroup', 'profile-set', 'profile-from-clip') { $anchors = Get-KdpGroupAnchors $d }
$newPair = $null
if ($Sequence) { Select-KdpSequence $d $Sequence }
switch ($Command) {
    'sequences' { Get-KdpSequences $d | Format-Table Name, BinId, Main, Uuid -AutoSize | Out-String; return }
    'info' {
        "Profile: $($d.Xml.mlt.profile.description)  fps=$($d.Fps)  size=$($d.Xml.mlt.profile.width)x$($d.Xml.mlt.profile.height)"
        'Tracks: ' + ((Get-KdpTracks $d | ForEach-Object { $n = $_.Name; if ($_.Label) { $n += " ($($_.Label))" }; $n }) -join ', ')
        'Timeline:'
        Get-KdpClips $d | Sort-Object Track, Sub, Start | Format-Table Track, Sub, Start, End, In, Name, @{ n = 'Effects'; e = { $_.Effects -join ',' } } -AutoSize | Out-String -Width 220
        'Compositions:'; Get-KdpCompositions $d | Format-Table Id, Track, Below, Start, End -AutoSize | Out-String
        'Guides:'; Get-KdpGuides $d | Format-Table -AutoSize | Out-String
        'Bin:'; Get-KdpBinClips $d | Format-Table BinId, Name, Service, Length, Folder, Resource -AutoSize | Out-String -Width 220
        return
    }
    'validate' { $pr = Test-KdpProject $d; if ($pr.Count) { "PROBLEMS ($($pr.Count)):"; $pr } else { 'clean: no known Kdenlive load problems' }; return }
    'effect-list' { Get-KdpEffects $d $Track $atD -Master:$Master | Format-Table Index, Id, Disabled, In, Out, Params -AutoSize | Out-String -Width 250; return }
    'comp-list' { Get-KdpCompositions $d | Format-Table Id, Track, Below, Start, End -AutoSize | Out-String; return }
    'guide-list' { Get-KdpGuides $d | Format-Table -AutoSize | Out-String; return }
    'frame' { if (-not $Out) { throw '-Out file.png required' }; Export-KdpFrame $d $atD $Out $Width; return }
    'preview' {
        if (-not $Out) { $Out = Join-Path (Split-Path $PSScriptRoot -Parent) ('.shots\' + [IO.Path]::GetFileNameWithoutExtension($Project) + '-preview.mp4') }
        Export-KdpMelt $d $Out $From $ToTime; return
    }
    'render' {
        $nm = [IO.Path]::GetFileNameWithoutExtension($Project)
        if ($Preset) {
            $pp = Get-KdpRenderPresets | Where-Object Name -eq $Preset | Select-Object -First 1
            if (-not $pp) { throw "Unknown preset '$Preset' (kdp.ps1 presets)" }
            if (-not $Out) {
                $dir = Join-Path (Split-Path $PSScriptRoot -Parent) "out\$nm"; New-Item -ItemType Directory -Force $dir | Out-Null
                $n = 1; while (Test-Path (Join-Path $dir ('{0}-v{1:00}.{2}' -f $nm, $n, $pp.Ext.ToLower()))) { $n++ }
                $Out = Join-Path $dir ('{0}-v{1:00}.{2}' -f $nm, $n, $pp.Ext.ToLower())
            }
            $r = Export-KdpPreset $d $Preset $Out $Quality $From $ToTime; "rendered with preset '$Preset': $r"; return
        }
        if (-not $Out) {
            $dir = Join-Path (Split-Path $PSScriptRoot -Parent) "out\$nm"; New-Item -ItemType Directory -Force $dir | Out-Null
            $n = 1; while (Test-Path (Join-Path $dir ('{0}-v{1:00}.mp4' -f $nm, $n))) { $n++ }
            $Out = Join-Path $dir ('{0}-v{1:00}.mp4' -f $nm, $n)
        }
        $Out = [IO.Path]::GetFullPath($(if ([IO.Path]::IsPathRooted($Out)) { $Out } else { Join-Path (Get-Location).Path $Out }))
        # Kdenlive's headless renderer quits without output when the project has subtitles (verified 2026-11-21).
        # Use the same default preset Kdenlive would use, through melt, so the quality is identical.
        if ((Get-KdpSequence $d).SelectSingleNode("filter[property[@name='mlt_service']='avfilter.subtitles']")) {
            [void](Export-KdpPreset $d 'MP4-H264/AAC' $Out)
            "rendered with melt, preset MP4-H264/AAC (project has subtitles) $Out ($([math]::Round((Get-Item $Out).Length / 1MB, 2)) MB)"; return
        }
        $part = Get-KdpPartPath $Out
        $copy = New-KdpMeltCopy $d
        try {
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = Join-Path $PSScriptRoot 'Kdenlive\kdenlive-26.08.3_standalone\bin\kdenlive.exe'
            $psi.Arguments = "--render `"$copy`" `"$part`""
            $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
            Set-KdEnvironment $psi.EnvironmentVariables (Join-Path $PSScriptRoot 'profile-kdenlive')
            $pr = [Diagnostics.Process]::Start($psi); $null = $pr.StandardOutput.ReadToEndAsync(); $null = $pr.StandardError.ReadToEndAsync(); $pr.WaitForExit()
            if ($pr.ExitCode -ne 0) { throw "Kdenlive render failed (exit $($pr.ExitCode))" }
            Complete-KdpPart $part $Out 'Kdenlive render' ''
        } finally { Remove-Item $copy, $part -Force -ErrorAction SilentlyContinue }
        "rendered $Out ($([math]::Round((Get-Item $Out).Length / 1MB, 2)) MB)"
        return
    }
    'bin-add' { $c = Add-KdpMedia $d $File $Name $Seconds; "bin clip $($c.BinId) '$($c.Name)'" }
    'bin-color' { $c = Add-KdpColor $d $Color $Name $Seconds; "bin clip $($c.BinId) '$($c.Name)'" }
    'title' { $c = Add-KdpTitle $d ($Text -replace '\\n', "`n") $Name $Seconds $Font $Size $(if ($Color) { $Color } else { '#FFFFFF' }) $Place $X $Y $Weight $OutlineColor $Outline $Bg $Align; "title clip $($c.BinId) '$($c.Name)'" }
    'title-text' { Set-KdpTitleText $d $Bin ($Text -replace '\\n', "`n"); 'title updated' }
    'bin-rename' { Rename-KdpBinClip $d $Bin $Name; 'renamed' }
    'bin-remove' { Remove-KdpBinClip $d $Bin -Force:$Force; 'removed from bin' }
    'folder' { $f = Add-KdpFolder $d $Name $Parent; "folder $f '$Name'" }
    'bin-folder' { Move-KdpBinClip $d $Bin $Folder; 'moved' }
    'marker' { Add-KdpClipMarker $d $Bin $atD $Text $(if ($null -ne $markerCategory) { $markerCategory } else { 0 }) $(if ($Dur -gt 0) { $Dur } else { 0 }); 'marker added' }
    'add' { [void](Add-KdpClipToTimeline $d $Bin $Track $atD $In $Dur -Overwrite:$Overwrite -Insert:$Insert); "added '$Bin' to $Track at $atD s" }
    'add-av' { Add-KdpAVClip $d $Bin $Track $AudioTrack $atD $In $Dur; "added '$Bin' to $Track + $AudioTrack at $atD s (linked)" }
    'move' {
        $other = if ($Alone) { $null } else { Get-KdpPartnerRef $d $Track $atD }
        Move-KdpClip $d $Track $atD $ToTrack $To -Overwrite:$Overwrite
        if ($other) { Move-KdpClip $d $other.Track $other.At $other.Track ($To + $other.Offset) -Overwrite:$Overwrite; "moved, with the linked clip on $($other.Track)" } else { 'moved' }
    }
    'trim' {
        $other = if ($Alone) { $null } else { Get-KdpPartnerRef $d $Track $atD }
        Set-KdpClipTrim $d $Track $atD $NewIn $NewDur -KeepEnd:$KeepEnd
        if ($other) {
            $otherIn = if ($null -ne $NewIn) { [double]$NewIn + $other.InFrames / $d.Fps } else { $null }
            Set-KdpClipTrim $d $other.Track $other.At $otherIn $NewDur -KeepEnd:$KeepEnd
            "trimmed, with the linked clip on $($other.Track)"
        } else { 'trimmed' }
    }
    'split' {
        $other = if ($Alone) { $null } else { Get-KdpPartnerRef $d $Track $atD }
        Split-KdpClip $d $Track $atD
        if ($other) {
            Split-KdpClip $d $other.Track $atD
            $cut = SecToFrames $d $atD
            $newPair = @("$((Get-KdpTrack $d $Track).Index - 1):${cut}:-1", "$((Get-KdpTrack $d $other.Track).Index - 1):${cut}:-1")
            "split, with the linked clip on $($other.Track)"
        } else { 'split' }
    }
    'remove' {
        $other = if ($Alone) { $null } else { Get-KdpPartnerRef $d $Track $atD }
        Remove-KdpClip $d $Track $atD -Ripple:$Ripple
        if ($other) { Remove-KdpClip $d $other.Track $other.At -Ripple:$Ripple; "removed, with the linked clip on $($other.Track)" } else { 'removed' }
    }
    'rebase' { "project folder set to $($d.Root)" }
    'speed' { Set-KdpClipSpeed $d $Track $atD $Speed -KeepPitch:$KeepPitch; "speed $Speed" }
    'disable' { Set-KdpClipEnabled $d $Track $atD $false; 'clip disabled' }
    'enable' { Set-KdpClipEnabled $d $Track $atD $true; 'clip enabled' }
    'group' { Add-KdpUserGroup $d ($Clips -split ','); 'grouped' }
    'mix' { Add-KdpMix $d $Track $atD $(if ($Dur -gt 0) { $Dur } else { 1 }); 'mix added' }
    'unmix' { Remove-KdpMix $d $Track $atD; 'mix removed' }
    'effect-add' { $n = Add-KdpEffect $d $Id $Track $atD -Master:$Master -values $p -fadeSeconds $Fade; "effect $Id added" }
    'effect-set' { Set-KdpEffect $d $Track $atD -Master:$Master $Effect $p $(if ($Disable) { $true } elseif ($Enable) { $false } else { $null }); 'effect updated' }
    'effect-remove' { Remove-KdpEffect $d $Track $atD -Master:$Master $Effect; 'effect removed' }
    'comp-add' { [void](Add-KdpComposition $d $Id $Track $atD $Dur $Below $p); "composition $Id added" }
    'comp-set' { Set-KdpComposition $d $Track $atD $p; 'composition updated' }
    'comp-remove' { Remove-KdpComposition $d $Track $atD; 'composition removed' }
    'track-add' { $t = Add-KdpTrack $d -Audio:$Audio $Name; "track $t added" }
    'track-remove' { Remove-KdpTrack $d $Track -Force:$Force; 'track removed' }
    'track-set' { Set-KdpTrack $d $Track $Name $(if ($Lock) { $true } elseif ($Unlock) { $false } else { $null }) $(if ($Hide) { $true } elseif ($Show) { $false } else { $null }); 'track updated' }
    'guide-add' { Add-KdpGuide $d $atD $Text $(if ($null -ne $markerCategory) { $markerCategory } else { 0 }) $(if ($Dur -gt 0) { $Dur } else { 0 }); 'guide added' }
    'guide-remove' { Remove-KdpGuide $d $atD; 'guide removed' }
    'sub-add' { Add-KdpSubtitle $d $atD $Dur $Text; 'subtitle added' }
    'sequence-add' { $s = Add-KdpSequence $d $Name $VideoTracks $(if ($PSBoundParameters.ContainsKey('AudioTracks')) { $AudioTracks } else { 1 }); "sequence '$Name' added (bin id $($s.BinId)); edit it with -Sequence '$Name'" }
    'slideshow' { $c = Add-KdpSlideshow $d $File $Ext $(if ($PSBoundParameters.ContainsKey('Seconds')) { $Seconds } else { 1 }) $Name -Loop:$Loop -Crop:$Crop -Fade:$FadeSlides -fadeSeconds 0.5 -animation $Animation; "slideshow clip $($c.BinId) '$($c.Name)'" }
    'remap' { Set-KdpTimeRemap $d $Track $atD $Map $(if ($PSBoundParameters.ContainsKey('Speed')) { $Speed } else { 0 }) -KeepPitch:$KeepPitch -Blend:$Blend; 'time remap set' }
    'proxy' { if ([bool]$Enable -eq [bool]$Disable) { throw 'proxy needs -Enable or -Disable' }; Set-KdpProxy $d ([bool]$Enable); "proxies $(if ($Enable) { 'on' } else { 'off' })" }
    'bin-info' { $i = Get-KdpBinInfo $d $Bin; "$($i.Clip.BinId) '$($i.Clip.Name)' used at: $($i.Uses -join ', ')"; $i.Properties; return }
    'marker-list' { Get-KdpClipMarkers $d $Bin | Format-Table -AutoSize | Out-String; return }
    'guide-export' { Export-KdpGuides $d $Out $Format $(if ($PSBoundParameters.ContainsKey('CategoryIndex')) { $CategoryIndex } else { $null }); "guides written to $Out"; return }
    'sub-export' { $n = Export-KdpSrt $d $Out; "$n subtitles written to $Out"; return }
    'archive' { $r = Export-KdpArchive $d $Out; "archived to $r"; return }
    'backups' { Get-KdpBackups $d | Format-Table Name, LastWriteTime, Length -AutoSize | Out-String -Width 200; return }
    'otio-export' { Export-KdpOtio $d $Out; "OTIO written to $Out"; return }
    'title-save' { Save-KdpTitleTemplate $d $Bin $Out; "title template written to $Out"; return }
    'copy' { Copy-KdpClip $d $Track $atD $ToTrack $To -Overwrite:$Overwrite -Insert:$Insert; 'copied' }
    'effect-copy' { Copy-KdpEffects $d $Track $atD $ToTrack $To -Replace:$Force; 'effects pasted' }
    'effect-clear' { Clear-KdpEffects $d $Track $atD -Master:$Master; 'effects removed' }
    'effects-all' { if ([bool]$Enable -eq [bool]$Disable) { throw 'effects-all needs -Enable or -Disable' }; Set-KdpAllEffects $d ([bool]$Enable); "all timeline effects $(if ($Enable) { 'enabled' } else { 'disabled' })" }
    'bin-effect' { Add-KdpBinEffect $d $Bin $Id $p; "effect $Id added to every use of '$Bin'" }
    'ungroup' { Remove-KdpGroup $d $Track $atD; 'ungrouped' }
    'slip' {
        $other = if ($Alone) { $null } else { Get-KdpPartnerRef $d $Track $atD }
        Invoke-KdpSlip $d $Track $atD $By
        if ($other) { Invoke-KdpSlip $d $other.Track $other.At $By; "slipped, with the linked clip on $($other.Track)" } else { 'slipped' }
    }
    'ripple-trim' {
        $other = if ($Alone) { $null } else { Get-KdpPartnerRef $d $Track $atD }
        Invoke-KdpRippleTrim $d $Track $atD $NewIn $NewDur
        if ($other) {
            $otherIn = if ($null -ne $NewIn) { [double]$NewIn + $other.InFrames / $d.Fps } else { $null }
            Invoke-KdpRippleTrim $d $other.Track $other.At $otherIn $NewDur
            "ripple-trimmed, with the linked clip on $($other.Track)"
        } else { 'ripple-trimmed' }
    }
    'space-insert' { Add-KdpSpace $d $atD $Dur $(if ($Tracks) { $Tracks -split ',' } else { $null }); 'space inserted' }
    'space-remove' { Remove-KdpSpace $d $atD $Dur $(if ($Tracks) { $Tracks -split ',' } else { $null }); 'space removed' }
    'spaces-remove-all' { Remove-KdpAllSpaces $d $Track; 'all spaces removed' }
    'track-clear' { Clear-KdpTrack $d $Track; 'track cleared' }
    'copy-to-sequence' { $n = Copy-KdpRangeToSequence $d ([double]$From) ([double]$ToTime) $Target $To; "$n clip(s) copied to '$Target'" }
    'expand' { Expand-KdpSequenceClip $d $Track $atD }
    'bin-set' { Set-KdpBinProps $d $Bin $p; 'clip properties set' }
    'bin-duplicate' { $c = Copy-KdpBinClip $d $Bin $Name; "duplicated as $($c.BinId) '$($c.Name)'" }
    'bin-replace-file' { Set-KdpBinFile $d $Bin (Resolve-Path $File).Path; 'clip now uses the new file' }
    'bin-reload' { Update-KdpBinClip $d $Bin; 'clip reloaded' }
    'relink' { $r = Update-KdpMissingMedia $d $Folder; if ($r) { $r } else { 'nothing to relink' } }
    'replace-in-timeline' { $n = Set-KdpReplaceInTimeline $d $Bin $With; "$n use(s) replaced" }
    'clean' { $r = Remove-KdpUnusedClips $d; "removed unused: $($r -join ', ')" }
    'generator' { $c = Add-KdpGenerator $d $Id $Seconds $p $Name; "generator clip $($c.BinId) '$($c.Name)'" }
    'playlist-clip' { $c = Add-KdpPlaylistClip $d $File $Name; "playlist clip $($c.BinId) '$($c.Name)'" }
    'title-template' { $c = Add-KdpTitleTemplateClip $d $File $Text $Seconds $Name; "template clip $($c.BinId) '$($c.Name)'" }
    'extract-audio' { $c = Invoke-KdpExtractAudio $d $Bin $null; "audio extracted to bin clip $($c.BinId) '$($c.Name)'" }
    'transcode' { $c = Invoke-KdpTranscode $d $Bin $FfArgs $(if ($PSBoundParameters.ContainsKey('Ext')) { $Ext } else { 'mp4' }) -Replace:$Replace; "transcoded: $($c.BinId) '$($c.Name)'" }
    'marker-set' { Set-KdpClipMarker $d $Bin $atD $Text $markerCategory $NewAt; 'marker updated' }
    'marker-remove' { Remove-KdpClipMarker $d $Bin $atD; 'marker(s) removed' }
    'guide-set' { Set-KdpGuide $d $atD $Text $markerCategory $NewAt $(if ($Dur -ge 0) { $Dur } else { $null }); 'guide updated' }
    'guide-clear' { Clear-KdpGuides $d; 'all guides removed' }
    'guide-category' { Set-KdpGuideCategory $d $CategoryIndex $Name $Color; 'category set' }
    'sub-import' { $n = Import-KdpSrt $d $File $(if ($null -ne $atD) { $atD } else { 0 }); "$n subtitles imported" }
    'sub-state' { Set-KdpSubtitleState $d $(if ($Disable) { $true } elseif ($Enable) { $false } else { $null }) $(if ($Lock) { $true } elseif ($Unlock) { $false } else { $null }); 'subtitle state set' }
    'zone' { Set-KdpZone $d ([double]$From) ([double]$ToTime) -UseInEdits:$UseInEdits; 'zone set' }
    'profile-set' { Set-KdpProfile $d $Profile; "profile $Profile" }
    'profile-from-clip' { $pn = Find-KdpProfileForClip $d $Bin; Set-KdpProfile $d $pn; "profile $pn" }
    'otio-import' { $n = Import-KdpOtio $d $File $(if ($null -ne $atD) { $atD } else { 0 }); "$n clip(s) imported" }
    'subclip' { Add-KdpSubclip $d $Bin ([double]$From) ([double]$ToTime) $Name; 'subclip added' }
    'stabilize' { $c = Invoke-KdpStabilize $d $Bin -Replace:$Replace; "stabilized: $($c.BinId) '$($c.Name)'" }
    'scene-split' { $t = Invoke-KdpSceneSplit $d $Bin; "$(@($t).Count) scene cut(s) marked: $($t -join ', ')" }
    'speed-job' { $c = Invoke-KdpSpeedJob $d $Bin $Speed; "new clip at x$($Speed): $($c.BinId) '$($c.Name)'" }
    'effect-template' { $n = Add-KdpEffectTemplate $d $Id $Track $atD; "$n effect(s) from template '$Id'" }
    default { throw "Unknown command '$Command'. See the header of engine\kdp.ps1." }
}
Update-KdpGroupPositions $d $anchors
if ($newPair) { Add-KdpGroup $d 'AVSplit' $newPair }
$problems = Test-KdpProject $d
if ($problems.Count) { throw ("Not saved: the edit would make Kdenlive complain:`n" + ($problems -join "`n")) }
if ((Get-KdHash $Project) -ne $d.LoadedHash) { throw 'Not saved: the project file changed while this command ran (the user saved?). Run the command again.' }
if ($window -and (Get-Process -Id $window.ProcessId -ErrorAction SilentlyContinue)) {
    $unsaved = Wait-KdUnsaved $window 120
    if ($unsaved -ne $false) { throw "Not saved: the user is editing in Kdenlive (or it did not answer). Run the command again; it will take the user's edits first." }
}
Save-KdpSnapshot $Project $assBefore
Save-Kdp $d
$written = $true
}
finally {
    if ($null -ne $assBefore -and -not $written) { Set-KdpAssState $Project $assBefore }   # an edit that was not saved leaves no subtitle changes
    Exit-KdLock $projectLock
}
