# kdp-ops.ps1 - effects, compositions, tracks, titles, guides, markers, speed, mixes, subtitles,
# folders, groups, project creation, preview and validation for Kdenlive 26.08 projects.
# Dot-source after kdp-core.ps1. Effect/composition definitions are read from Kdenlive's own
# data files shipped in engine\Kdenlive\...\bin\data\kdenlive (effects\*.xml, transitions\*.xml).

$script:KdpData = Join-Path $script:KdpBin 'data\kdenlive'
$script:KdpProfiles = Join-Path (Split-Path $script:KdpBin -Parent) 'share\mlt\profiles'
$script:KdpEffectCache = $null
$script:KdpTransitionCache = $null

# ---------- asset catalogs ----------
function Read-KdpAssetFile([string]$path, [string]$kind) {
    $x = New-Object System.Xml.XmlDocument; $x.XmlResolver = $null
    try { $x.Load($path) } catch { return @() }
    $nodes = @($x.SelectNodes("//*[local-name()='$kind']"))
    if (-not $nodes) { return @() }
    # several versions of one asset may share a file: keep the highest version
    $best = $nodes | Sort-Object { [double]('0' + $_.GetAttribute('version')) } -Descending | Select-Object -First 1
    $params = foreach ($p in $best.SelectNodes("*[local-name()='parameter']")) {
        $names = $p.GetAttribute('name') -split "`n"; $defs = $p.GetAttribute('default') -split "`n"
        for ($i = 0; $i -lt $names.Count; $i++) {
            [pscustomobject]@{ Name = $names[$i]; Type = $p.GetAttribute('type'); Default = $(if ($i -lt $defs.Count) { $defs[$i] } else { '' }); Min = $p.GetAttribute('min'); Max = $p.GetAttribute('max'); Factor = $p.GetAttribute('factor'); List = $p.GetAttribute('paramlist'); Label = ($p.SelectSingleNode("*[local-name()='name']")).InnerText }
        }
    }
    $id = $best.GetAttribute('id'); if (-not $id) { $id = $best.GetAttribute('tag') }
    [pscustomobject]@{ Id = $id; Tag = $best.GetAttribute('tag'); Type = $best.GetAttribute('type'); Unique = ($best.GetAttribute('unique') -eq '1'); Version = $best.GetAttribute('version'); Name = ($best.SelectSingleNode("*[local-name()='name']")).InnerText; Description = ($best.SelectSingleNode("*[local-name()='description']")).InnerText; Params = @($params); File = (Split-Path $path -Leaf); Category = '' }
}
function Get-KdpEffectCatalog {
    if ($script:KdpEffectCache) { return $script:KdpEffectCache }
    $cats = @{}
    $rc = New-Object System.Xml.XmlDocument; $rc.XmlResolver = $null; $rc.Load((Join-Path $script:KdpData 'kdenliveeffectscategory.rc'))
    foreach ($g in $rc.SelectNodes('//group')) { $t = $g.SelectSingleNode('text').InnerText; foreach ($e in $g.GetAttribute('list').Split(',')) { $cats[$e.Trim()] = $t } }
    $list = foreach ($f in Get-ChildItem (Join-Path $script:KdpData 'effects') -Filter *.xml) { Read-KdpAssetFile $f.FullName 'effect' }
    foreach ($e in $list) { if ($cats.ContainsKey($e.Id)) { $e.Category = $cats[$e.Id] } }
    $script:KdpEffectCache = @($list | Sort-Object Id -Unique)
    return $script:KdpEffectCache
}
function Get-KdpTransitionCatalog {
    if ($script:KdpTransitionCache) { return $script:KdpTransitionCache }
    $list = foreach ($f in Get-ChildItem (Join-Path $script:KdpData 'transitions') -Filter *.xml) { Read-KdpAssetFile $f.FullName 'transition' }
    $script:KdpTransitionCache = @($list | Sort-Object Id -Unique)
    return $script:KdpTransitionCache
}
function Get-KdpEffectDef([string]$id) { $e = Get-KdpEffectCatalog | Where-Object Id -eq $id; if (-not $e) { throw "Unknown effect id '$id'. Use: kdp.ps1 effects -Search <text>" }; $e }
function Get-KdpTransitionDef([string]$id) { $e = Get-KdpTransitionCatalog | Where-Object Id -eq $id; if (-not $e) { throw "Unknown composition id '$id'. Use: kdp.ps1 compositions" }; $e }

# Resolve a definition default such as "0 0 %width %height 1" or "%fade".
function Resolve-KdpDefault([KdpDoc]$d, [string]$v, [hashtable]$ctx) {
    if ($null -eq $v) { return '' }
    $w = $d.Xml.mlt.profile.width; $h = $d.Xml.mlt.profile.height
    $v = $v.Replace('%width', $w).Replace('%height', $h).Replace('%maxWidth', $w).Replace('%maxHeight', $h).Replace('%contentWidth', $w).Replace('%contentHeight', $h)
    $v = $v.Replace('%fittedContentWidth', $w).Replace('%fittedContentHeight', $h).Replace('%in', "$($ctx.In)")
    $v = $v.Replace('%fade', "$($ctx.Fade)").Replace('%position', "$($ctx.In)").Replace('%out', "$($ctx.Out)").Replace('%lumaPaths', '').Replace('%lumaPaths', '')
    if ($v -match '%') { $v = [regex]::Replace($v, '%\w+', '0') }
    return $v
}
# A default in Kdenlive's asset files is ALREADY the MLT value: 'factor' only scales what the panel shows
# (AssetParameterModel::parseAttribute never divides). Until 2026-11-22 this tool divided by it, so an effect
# added without -Params got values up to 1000 times too small. Never divide here.
function Format-KdpParamValue($p, [string]$v, [hashtable]$ctx) {
    if ($p.Type -eq 'position' -and $v -match '^-\d+$') { return "$([int]$v + $ctx.Out)" }   # negative = counted from the end
    return $v
}
# What this Windows build can really load. The catalog also lists assets whose MLT module is missing here
# (sox, ladspa, movit, some frei0r): added to a project they silently do nothing.
$script:KdpServices = @{}
function Assert-KdpService([string]$kind, $def) {
    if (-not $script:KdpServices.ContainsKey($kind)) {
        $list = @{}
        $eap = $ErrorActionPreference; $ErrorActionPreference = 'SilentlyContinue'
        $lines = & (Join-Path $script:KdpBin 'melt.exe') -query $kind 2>$null
        $ErrorActionPreference = $eap
        foreach ($line in $lines) { if ($line -match '^\s+-\s+(\S.*?)\s*$') { $list[$matches[1]] = 1 } }
        if (-not $list.Count) { throw "Could not read the list of $kind from melt" }
        $script:KdpServices[$kind] = $list
    }
    if (-not $script:KdpServices[$kind].ContainsKey($def.Tag)) { throw "'$($def.Id)' is not available in this Windows build of Kdenlive (MLT has no '$($def.Tag)'); it would do nothing. Pick another one, or render the effect outside and add it as a clip." }
}
# Build a <filter> or <transition> element from a definition. $values: name->value (raw MLT values).
function New-KdpAssetNode([KdpDoc]$d, [string]$element, $def, [hashtable]$values, [hashtable]$ctx) {
    Assert-KdpService "${element}s" $def
    $n = $d.Xml.CreateElement($element)
    $n.SetAttribute('id', (New-KdpId $d $element))
    foreach ($p in $def.Params) {
        if (-not $p.Name) { continue }
        if ($p.Name -in 'in', 'out') { continue }   # handled as attributes by callers
        if ($values.ContainsKey($p.Name)) { $v = "$($values[$p.Name])" }
        else { $v = Format-KdpParamValue $p (Resolve-KdpDefault $d $p.Default $ctx) $ctx }
        Set-KdpProp $n $p.Name $v
    }
    foreach ($k in $values.Keys) { if (-not ($def.Params | Where-Object Name -eq $k) -and $k -notin 'in', 'out') { Set-KdpProp $n $k $values[$k] } }
    Set-KdpProp $n 'mlt_service' $def.Tag
    Set-KdpProp $n 'kdenlive_id' $def.Id
    return $n
}
function ConvertFrom-KdpParamString([string]$s) {
    $h = @{}
    if (-not $s) { return $h }
    foreach ($pair in ($s -split '\|\|')) { if ($pair -match '^\s*([^=]+?)\s*=(.*)$') { $h[$matches[1]] = $matches[2] } }
    return $h
}

# ---------- effects ----------
# Target: -Track V1 -At 3 (clip), -Track V1 (whole track), or -Master.
function Get-KdpEffectHost([KdpDoc]$d, [string]$track, $at, [switch]$Master) {
    if ($Master) { return @{ Node = (Get-KdpSequence $d); Kind = 'master'; Audio = $null; In = 0; Out = 0 } }
    $t = Get-KdpTrack $d $track
    if ($null -eq $at -or "$at" -eq '') { return @{ Node = $t.Tractor; Kind = 'track'; Audio = $t.Audio; In = 0; Out = 0 } }
    $c = Find-KdpClip $d $track ([double]$at)
    return @{ Node = $c.Node; Kind = 'clip'; Audio = $t.Audio; In = (ConvertTo-KdpFrames $d $c.Node.in); Out = (ConvertTo-KdpFrames $d $c.Node.out) }
}
function Add-KdpEffect([KdpDoc]$d, [string]$id, [string]$track, $at, [switch]$Master, [hashtable]$values = @{}, [double]$fadeSeconds = 1) {
    $def = Get-KdpEffectDef $id
    $hostInfo = Get-KdpEffectHost $d $track $at -Master:$Master
    if ($null -ne $hostInfo.Audio) {
        if ($def.Type -eq 'audio' -and -not $hostInfo.Audio) { throw "'$id' is an audio effect; target an audio track/clip." }
        if ($def.Type -ne 'audio' -and $def.Type -ne 'custom' -and $hostInfo.Audio -and $def.Type -ne '') { throw "'$id' is a video effect; target a video track/clip." }
    }
    $fadeF = SecToFrames $d $fadeSeconds
    $ctx = @{ Fade = $fadeF; In = $hostInfo.In; Out = $hostInfo.Out }
    if ($def.Unique) { foreach ($f in @($hostInfo.Node.SelectNodes('filter'))) { if ((Get-KdpProp $f 'kdenlive_id') -eq $id) { [void]$hostInfo.Node.RemoveChild($f) } } }
    $n = New-KdpAssetNode $d 'filter' $def $values $ctx
    if ($hostInfo.Kind -eq 'clip') {
        $inF = $hostInfo.In; $outF = $hostInfo.Out
        switch -Regex ($id) {
            '^(fade_from_black|fadein|fade_in.*)$' { $n.SetAttribute('in', (ConvertTo-KdpTime $d $inF)); $n.SetAttribute('out', (ConvertTo-KdpTime $d ([math]::Min($outF, $inF + $fadeF - 1)))) }
            '^(fade_to_black|fadeout|fade_out.*)$' { $n.SetAttribute('in', (ConvertTo-KdpTime $d ([math]::Max($inF, $outF - $fadeF + 1)))); $n.SetAttribute('out', (ConvertTo-KdpTime $d $outF)) }
            default {
                if ($values.ContainsKey('in')) { $n.SetAttribute('in', (ConvertTo-KdpTime $d ($inF + (SecToFrames $d ([double]$values['in']))))) }
                if ($values.ContainsKey('out')) { $n.SetAttribute('out', (ConvertTo-KdpTime $d ($inF + (SecToFrames $d ([double]$values['out']))))) }
            }
        }
    }
    if ($hostInfo.Kind -eq 'master') {
        # master effects go after the sequence's transitions, before internal filters is fine
        [void]$hostInfo.Node.AppendChild($n)
    } else { [void]$hostInfo.Node.AppendChild($n) }
    return $n
}
function Get-KdpEffects([KdpDoc]$d, [string]$track, $at, [switch]$Master) {
    $hostInfo = Get-KdpEffectHost $d $track $at -Master:$Master
    $i = 0
    foreach ($f in $hostInfo.Node.SelectNodes('filter')) {
        if (Get-KdpProp $f 'internal_added') { continue }
        [pscustomobject]@{ Index = $i; Id = (Get-KdpProp $f 'kdenlive_id'); Service = (Get-KdpProp $f 'mlt_service'); Disabled = ((Get-KdpProp $f 'disable') -eq '1'); In = $f.GetAttribute('in'); Out = $f.GetAttribute('out'); Params = (($f.SelectNodes('property') | Where-Object { $_.name -notin 'mlt_service', 'kdenlive_id' } | ForEach-Object { "$($_.name)=$($_.InnerText)" }) -join '; '); Node = $f }
        $i++
    }
}
function Get-KdpEffectNode([KdpDoc]$d, [string]$track, $at, [switch]$Master, [string]$effect) {
    $list = @(Get-KdpEffects $d $track $at -Master:$Master)
    $e = if ($effect -match '^\d+$') { $list | Where-Object Index -eq ([int]$effect) } else { $list | Where-Object Id -eq $effect | Select-Object -First 1 }
    if (-not $e) { throw "Effect '$effect' not found. Present: " + (($list | ForEach-Object { "$($_.Index):$($_.Id)" }) -join ', ') }
    return $e.Node
}
function Set-KdpEffect([KdpDoc]$d, [string]$track, $at, [switch]$Master, [string]$effect, [hashtable]$values, $disable = $null) {
    $n = Get-KdpEffectNode $d $track $at -Master:$Master $effect
    foreach ($k in $values.Keys) { Set-KdpProp $n $k $values[$k] }
    if ($null -ne $disable) { Set-KdpProp $n 'disable' $(if ($disable) { 1 } else { 0 }) }
}
function Remove-KdpEffect([KdpDoc]$d, [string]$track, $at, [switch]$Master, [string]$effect) {
    $n = Get-KdpEffectNode $d $track $at -Master:$Master $effect; [void]$n.ParentNode.RemoveChild($n)
}

# ---------- tracks ----------
function Get-KdpMltIndex([KdpDoc]$d, $track) { return $track.Index }   # 0 = black
function Update-KdpTrackIndices([KdpDoc]$d, [int]$fromIndex, [int]$delta) {
    $seq = Get-KdpSequence $d
    foreach ($tr in $seq.SelectNodes('transition')) {
        foreach ($k in 'a_track', 'b_track') { $v = [int](Get-KdpProp $tr $k); if ($v -ge $fromIndex) { Set-KdpProp $tr $k ($v + $delta) } }
    }
    # groups: leaf data "trackPos:frame[:sub]" with trackPos excluding black => mlt index - 1
    $g = Get-KdpProp $seq 'kdenlive:sequenceproperties.groups'
    if ($g -and $g.Trim() -ne '[' -and $g -match 'data') {
        $g2 = [regex]::Replace($g, '"data"\s*:\s*"(\d+):', { param($m) $tp = [int]$m.Groups[1].Value; if ($tp + 1 -ge $fromIndex) { $tp += $delta }; '"data": "' + $tp + ':' })
        Set-KdpProp $seq 'kdenlive:sequenceproperties.groups' $g2
    }
}
function Add-KdpTrack([KdpDoc]$d, [switch]$Audio, [string]$name) {
    $seq = Get-KdpSequence $d
    $pl1 = $d.Xml.CreateElement('playlist'); $pl1.SetAttribute('id', (New-KdpId $d 'playlist'))
    [void]$d.Xml.mlt.InsertBefore($pl1, $seq)
    $pl2 = $d.Xml.CreateElement('playlist'); $pl2.SetAttribute('id', (New-KdpId $d 'playlist'))
    [void]$d.Xml.mlt.InsertBefore($pl2, $seq)
    $tt = $d.Xml.CreateElement('tractor'); $tt.SetAttribute('id', (New-KdpId $d 'tractor')); $tt.SetAttribute('in', (ConvertTo-KdpTime $d 0))
    if ($Audio) { foreach ($p in $pl1, $pl2, $tt) { Set-KdpProp $p 'kdenlive:audio_track' 1 } }
    foreach ($kv in ([ordered]@{ 'kdenlive:trackheight' = 67; 'kdenlive:timeline_active' = 1; 'kdenlive:collapsed' = 0; 'kdenlive:thumbs_format' = ''; 'kdenlive:audio_rec' = '' }).GetEnumerator()) { Set-KdpProp $tt $kv.Key $kv.Value }
    if ($name) { Set-KdpProp $tt 'kdenlive:track_name' $name }
    foreach ($p in $pl1, $pl2) { $t = $d.Xml.CreateElement('track'); $t.SetAttribute('hide', $(if ($Audio) { 'video' } else { 'audio' })); $t.SetAttribute('producer', $p.id); [void]$tt.AppendChild($t) }
    if ($Audio) {
        $f = $d.Xml.CreateElement('filter'); $f.SetAttribute('id', (New-KdpId $d 'filter')); foreach ($kv in ([ordered]@{ window = 75; max_gain = '20dB'; channel_mask = -1; mlt_service = 'volume'; internal_added = 237; disable = 1 }).GetEnumerator()) { Set-KdpProp $f $kv.Key $kv.Value }; [void]$tt.AppendChild($f)
        $f = $d.Xml.CreateElement('filter'); $f.SetAttribute('id', (New-KdpId $d 'filter')); foreach ($kv in ([ordered]@{ channel = -1; mlt_service = 'panner'; internal_added = 237; start = 0.5; disable = 1 }).GetEnumerator()) { Set-KdpProp $f $kv.Key $kv.Value }; [void]$tt.AppendChild($f)
        $f = $d.Xml.CreateElement('filter'); $f.SetAttribute('id', (New-KdpId $d 'filter')); foreach ($kv in ([ordered]@{ iec_scale = 0; prefix = 'meta.media.audio_level.'; mlt_service = 'audiolevel'; internal_added = 237; dbpeak = 1; disable = 1 }).GetEnumerator()) { Set-KdpProp $f $kv.Key $kv.Value }; [void]$tt.AppendChild($f)
    }
    [void]$d.Xml.mlt.InsertBefore($tt, $seq)
    $tracks = @($seq.SelectNodes('track'))
    $st = $d.Xml.CreateElement('track'); $st.SetAttribute('producer', $tt.id)
    if ($Audio) { $newIndex = 1; [void]$seq.InsertAfter($st, $tracks[0]) }        # new highest A number sits right after black
    else { $newIndex = $tracks.Count; [void]$seq.InsertAfter($st, $tracks[$tracks.Count - 1]) }
    if ($Audio) { Update-KdpTrackIndices $d $newIndex 1 }
    # internal compositing/mix transition for the new track
    $tr = $d.Xml.CreateElement('transition'); $tr.SetAttribute('id', (New-KdpId $d 'transition'))
    if ($Audio) { $props = [ordered]@{ a_track = 0; b_track = $newIndex; duck_threshold = 0; duck_attenuation = -12; duck_level = 0; duck_fade_in = 1500; duck_fade_out = 250; prefix = ''; mlt_service = 'mix'; kdenlive_id = 'mix'; internal_added = 237; always_active = 1; accepts_blanks = 1; sum = 1 } }
    else { $props = [ordered]@{ a_track = 0; b_track = $newIndex; compositing = 0; distort = 0; rotate_center = 0; mlt_service = 'qtblend'; kdenlive_id = 'qtblend'; internal_added = 237; always_active = 1 } }
    foreach ($kv in $props.GetEnumerator()) { Set-KdpProp $tr $kv.Key $kv.Value }
    $firstFilter = $seq.SelectSingleNode('filter')
    if ($firstFilter) { [void]$seq.InsertBefore($tr, $firstFilter) } else { [void]$seq.AppendChild($tr) }
    Set-KdpProp $seq 'kdenlive:sequenceproperties.tracksCount' (@($seq.SelectNodes('track')).Count - 1)
    return (Get-KdpTracks $d | Where-Object { [object]::ReferenceEquals($_.Tractor, $tt) }).Name
}
function Remove-KdpTrack([KdpDoc]$d, [string]$name, [switch]$Force) {
    $t = Get-KdpTrack $d $name
    $clips = @(Get-KdpClips $d | Where-Object Track -eq $t.Name)
    if ($clips.Count -and -not $Force) { throw "Track $name has $($clips.Count) clip(s); use -Force to delete them too." }
    $seq = Get-KdpSequence $d
    $idx = $t.Index
    foreach ($tr in @($seq.SelectNodes('transition'))) { if ([int](Get-KdpProp $tr 'b_track') -eq $idx -or ([int](Get-KdpProp $tr 'a_track') -eq $idx -and -not (Get-KdpProp $tr 'internal_added'))) { [void]$seq.RemoveChild($tr) } }
    [void]$seq.RemoveChild($t.SeqTrack)
    foreach ($pl in $t.Playlists) { [void]$d.Xml.mlt.RemoveChild($pl) }
    [void]$d.Xml.mlt.RemoveChild($t.Tractor)
    # drop groups that reference the removed track (an unresolvable leaf invalidates its group)
    $g = @(Get-KdpJsonArray (Get-KdpProp $seq 'kdenlive:sequenceproperties.groups'))
    if ($g.Count) {
        $keep = @($g | Where-Object { -not ((ConvertTo-Json $_ -Depth 6) -match ('"data":\s*"' + ($idx - 1) + ':')) })
        Set-KdpProp $seq 'kdenlive:sequenceproperties.groups' (ConvertTo-KdpJson $keep)
    }
    Update-KdpTrackIndices $d ($idx + 1) -1
    Set-KdpProp $seq 'kdenlive:sequenceproperties.tracksCount' (@($seq.SelectNodes('track')).Count - 1)
}
function Set-KdpTrack([KdpDoc]$d, [string]$name, [string]$label, $lock = $null, $hidden = $null) {
    $t = Get-KdpTrack $d $name
    if ($label) { Set-KdpProp $t.Tractor 'kdenlive:track_name' $label }
    if ($null -ne $lock) { if ($lock) { Set-KdpProp $t.Tractor 'kdenlive:locked_track' 1 } else { Remove-KdpProp $t.Tractor 'kdenlive:locked_track' } }
    if ($null -ne $hidden) {
        # hidden=1: mute an audio track / hide a video track
        $v = if ($hidden) { 'both' } elseif ($t.Audio) { 'video' } else { 'audio' }
        foreach ($tr in $t.Tractor.SelectNodes('track')) { $tr.SetAttribute('hide', $v) }
    }
}

# ---------- compositions (between tracks) ----------
function Add-KdpComposition([KdpDoc]$d, [string]$id, [string]$track, [double]$at, [double]$dur, [string]$below, [hashtable]$values = @{}) {
    $def = Get-KdpTransitionDef $id
    $t = Get-KdpTrack $d $track
    if ($t.Audio) { throw 'Compositions go on video tracks.' }
    if ($below) { $a = (Get-KdpTrack $d $below).Index }
    else { $lower = Get-KdpTracks $d | Where-Object { -not $_.Audio -and $_.Index -lt $t.Index } | Sort-Object Index -Descending | Select-Object -First 1; $a = if ($lower) { $lower.Index } else { 0 } }
    $ctx = @{ Fade = (SecToFrames $d $dur); In = 0; Out = (SecToFrames $d $dur) - 1 }
    $n = New-KdpAssetNode $d 'transition' $def $values $ctx
    $startF = SecToFrames $d $at; $lenF = SecToFrames $d $dur
    $n.SetAttribute('in', (ConvertTo-KdpTime $d $startF)); $n.SetAttribute('out', (ConvertTo-KdpTime $d ($startF + $lenF - 1)))
    $first = $n.FirstChild
    $pa = $d.Xml.CreateElement('property'); $pa.SetAttribute('name', 'a_track'); $pa.InnerText = "$a"; [void]$n.InsertBefore($pa, $first)
    $pb = $d.Xml.CreateElement('property'); $pb.SetAttribute('name', 'b_track'); $pb.InnerText = "$($t.Index)"; [void]$n.InsertAfter($pb, $pa)
    Set-KdpProp $n 'force_track' 1
    $seq = Get-KdpSequence $d
    $firstInternal = $seq.SelectSingleNode('transition')
    if ($firstInternal) { [void]$seq.InsertBefore($n, $firstInternal) } else { [void]$seq.AppendChild($n) }
    return $n
}
function Get-KdpCompositions([KdpDoc]$d) {
    $seq = Get-KdpSequence $d; $tracks = Get-KdpTracks $d
    foreach ($tr in $seq.SelectNodes('transition')) {
        if (Get-KdpProp $tr 'internal_added') { continue }
        $b = [int](Get-KdpProp $tr 'b_track'); $a = [int](Get-KdpProp $tr 'a_track')
        [pscustomobject]@{ Id = Get-KdpProp $tr 'kdenlive_id'; Track = ($tracks | Where-Object Index -eq $b).Name; Below = $(if ($a -eq 0) { 'black' } else { ($tracks | Where-Object Index -eq $a).Name }); Start = [math]::Round((ConvertTo-KdpFrames $d $tr.in) / $d.Fps, 3); End = [math]::Round(((ConvertTo-KdpFrames $d $tr.out) + 1) / $d.Fps, 3); Node = $tr }
    }
}
function Remove-KdpComposition([KdpDoc]$d, [string]$track, [double]$at) {
    $f = SecToFrames $d $at
    $c = Get-KdpCompositions $d | Where-Object { $_.Track -eq $track.ToUpper() -and $f -ge (SecToFrames $d $_.Start) -and $f -lt (SecToFrames $d $_.End) } | Select-Object -First 1
    if (-not $c) { throw "No composition on $track at $at s" }
    [void]$c.Node.ParentNode.RemoveChild($c.Node)
}
function Set-KdpComposition([KdpDoc]$d, [string]$track, [double]$at, [hashtable]$values) {
    $f = SecToFrames $d $at
    $c = Get-KdpCompositions $d | Where-Object { $_.Track -eq $track.ToUpper() -and $f -ge (SecToFrames $d $_.Start) -and $f -lt (SecToFrames $d $_.End) } | Select-Object -First 1
    if (-not $c) { throw "No composition on $track at $at s" }
    foreach ($k in $values.Keys) { Set-KdpProp $c.Node $k $values[$k] }
}

# ---------- titles ----------
function Test-KdpFont([string]$family) {
    Add-Type -AssemblyName System.Drawing
    $fc = New-Object System.Drawing.Text.InstalledFontCollection
    return [bool]($fc.Families | Where-Object { $_.Name -eq $family })
}
function ConvertTo-KdpRgba([string]$c) {
    if ($c -match '^#([0-9a-fA-F]{2})([0-9a-fA-F]{2})([0-9a-fA-F]{2})([0-9a-fA-F]{2})?$') {
        $a = if ($matches[4]) { [Convert]::ToInt32($matches[4], 16) } else { 255 }
        return "{0},{1},{2},{3}" -f [Convert]::ToInt32($matches[1], 16), [Convert]::ToInt32($matches[2], 16), [Convert]::ToInt32($matches[3], 16), $a
    }
    if ($c -match '^\d+,\d+,\d+,\d+$') { return $c }
    throw "Colour must be #RRGGBB or #RRGGBBAA, got '$c'"
}
# Builds the kdenlivetitle XML. Lines separated by "`n" in $text.
function New-KdpTitleXml([KdpDoc]$d, [string]$text, [string]$font, [int]$size, [string]$color, [string]$place, [int]$x, [int]$y, [int]$weight, [string]$outlineColor, [int]$outline, [string]$bg, [int]$lenF, [string]$align) {
    $W = [int]$d.Xml.mlt.profile.width; $H = [int]$d.Xml.mlt.profile.height
    $lines = @($text -split "`n").Count
    $margin = [int]($W * 0.06)
    $boxW = $W - 2 * $margin; $boxH = [int]([math]::Ceiling($size * 1.35 * $lines))
    $alignVal = switch ($align) { 'left' { 1 } 'right' { 2 } default { 4 } }
    if ($place) {
        $x = $margin
        switch ($place) {
            'top' { $y = [int]($H * 0.08) }
            'center' { $y = [int](($H - $boxH) / 2) }
            'bottom' { $y = [int]($H * 0.92 - $boxH) }
            'lower-third' { $y = [int]($H * 0.72) }
            default { throw "Place must be top, center, bottom or lower-third" }
        }
    }
    $esc = [Security.SecurityElement]::Escape($text)
    $shadow = '0;#64000000;3;3;3'
    $bgItem = ''
    $xml = @"
<kdenlivetitle width="$W" height="$H" out="$($lenF - 1)">
 <item type="QGraphicsTextItem" z-index="1">
  <position x="$x" y="$y">
   <transform>1,0,0,0,1,0,0,0,1</transform>
  </position>
  <content font="$font" font-pixel-size="$size" font-color="$(ConvertTo-KdpRgba $color)" font-weight="$weight" font-italic="0" font-underline="0" font-outline-color="$(ConvertTo-KdpRgba $outlineColor)" font-outline="$outline" letter-spacing="0" line-spacing="0" alignment="$alignVal" shadow="$shadow" kdenlive-axis-x-inverted="0" kdenlive-axis-y-inverted="0" box-width="$boxW" box-height="$boxH">$esc</content>
 </item>
 <startviewport rect="0,0,$W,$H"/>
 <endviewport rect="0,0,$W,$H"/>
 <background color="$(ConvertTo-KdpRgba $bg)"/>
</kdenlivetitle>
"@
    return $xml
}
function Add-KdpTitle([KdpDoc]$d, [string]$text, [string]$name, [double]$seconds = 5, [string]$font = 'Segoe UI', [int]$size = 96, [string]$color = '#FFFFFF', [string]$place = 'center', [int]$x = 0, [int]$y = 0, [int]$weight = 700, [string]$outlineColor = '#000000', [int]$outline = 0, [string]$bg = '#00000000', [string]$align = 'center') {
    if (-not (Test-KdpFont $font)) { throw "Font '$font' is not installed; Kdenlive would show a modal dialog. Pick an installed font (kdp.ps1 fonts)." }
    $lenF = SecToFrames $d $seconds
    $xml = New-KdpTitleXml $d $text $font $size $color $place $x $y $weight $outlineColor $outline $bg $lenF $align
    if (-not $name) { $name = ($text -split "`n")[0]; if ($name.Length -gt 40) { $name = $name.Substring(0, 40) } }
    return Add-KdpBinProducer $d 'producer' 'producer' ([ordered]@{ length = $lenF; eof = 'pause'; resource = ''; xmldata = $xml; mlt_service = 'kdenlivetitle'; 'kdenlive:duration' = (ConvertTo-KdpTime $d $lenF); 'kdenlive:clipname' = $name; 'kdenlive:clip_type' = 2; force_reload = 0 }) $lenF
}
function Set-KdpTitleText([KdpDoc]$d, [string]$bin, [string]$text) {
    $bc = Get-KdpBinClip $d $bin
    if ((Get-KdpProp $bc.Node 'mlt_service') -ne 'kdenlivetitle') { throw "'$bin' is not a title clip" }
    $x = New-Object System.Xml.XmlDocument; $x.LoadXml((Get-KdpProp $bc.Node 'xmldata'))
    $c = $x.SelectSingleNode('//item[@type="QGraphicsTextItem"]/content'); $c.InnerText = $text
    Set-KdpProp $bc.Node 'xmldata' $x.OuterXml
}

# ---------- guides and markers (JSON arrays) ----------
# Windows PowerShell 5.1: ConvertFrom-Json returns a JSON array as ONE pipeline object, so it must be
# unrolled, otherwise "+=" nests arrays and ConvertTo-Json writes {"value":[...],"Count":n} garbage.
function Get-KdpJsonArray([string]$s) {
    if (-not $s -or $s.Trim() -in '', '[', '[]') { return }
    try { $r = $s | ConvertFrom-Json } catch { return }
    foreach ($x in $r) { if ($x -is [array]) { foreach ($y in $x) { $y } } else { $x } }
}
# Minimal JSON writer for the guide/marker/group structures (avoids ConvertTo-Json quirks).
function ConvertTo-KdpJsonValue($v, [string]$ind) {
    if ($null -eq $v) { return 'null' }
    if ($v -is [string]) { return '"' + ($v.Replace('\', '\\').Replace('"', '\"').Replace("`n", '\n').Replace("`r", '\r').Replace("`t", '\t')) + '"' }
    if ($v -is [bool]) { return $(if ($v) { 'true' } else { 'false' }) }
    if ($v -is [int] -or $v -is [long] -or $v -is [double] -or $v -is [decimal]) { return ([double]$v).ToString([cultureinfo]::InvariantCulture) }
    if ($v -is [System.Collections.IEnumerable] -and $v -isnot [System.Collections.IDictionary] -and $v -isnot [psobject] -or $v -is [array]) {
        $items = @(foreach ($x in $v) { $ind + '    ' + (ConvertTo-KdpJsonValue $x ($ind + '    ')) })
        if (-not $items.Count) { return '[]' }
        return "[`n" + ($items -join ",`n") + "`n$ind]"
    }
    $props = if ($v -is [System.Collections.IDictionary]) { $v.Keys | ForEach-Object { @{ Name = $_; Value = $v[$_] } } } else { $v.PSObject.Properties | ForEach-Object { @{ Name = $_.Name; Value = $_.Value } } }
    $parts = @(foreach ($p in $props) { $ind + '    "' + $p.Name + '": ' + (ConvertTo-KdpJsonValue $p.Value ($ind + '    ')) })
    return "{`n" + ($parts -join ",`n") + "`n$ind}"
}
function ConvertTo-KdpJson($arr) {
    $list = @(foreach ($x in $arr) { if ($null -ne $x) { $x } })
    if (-not $list.Count) { return "[`n]`n" }
    return (ConvertTo-KdpJsonValue -v $list -ind '') + "`n"
}
function Add-KdpGuide([KdpDoc]$d, [double]$at, [string]$comment, [int]$category = 0, [double]$dur = 0) {
    $seq = Get-KdpSequence $d
    $g = @(Get-KdpJsonArray (Get-KdpProp $seq 'kdenlive:sequenceproperties.guides') | Where-Object { $_.PSObject.Properties['pos'] })
    $g += [pscustomobject]@{ comment = $comment; duration = (SecToFrames $d $dur); pos = (SecToFrames $d $at); type = $category }
    Set-KdpProp $seq 'kdenlive:sequenceproperties.guides' (ConvertTo-KdpJson ($g | Sort-Object pos))
}
function Get-KdpGuides([KdpDoc]$d) { foreach ($x in (Get-KdpJsonArray (Get-KdpProp (Get-KdpSequence $d) 'kdenlive:sequenceproperties.guides') | Where-Object { $_.PSObject.Properties['pos'] })) { [pscustomobject]@{ At = [math]::Round($x.pos / $d.Fps, 3); Dur = [math]::Round($x.duration / $d.Fps, 3); Comment = $x.comment; Category = $x.type } } }
function Remove-KdpGuide([KdpDoc]$d, [double]$at) {
    $seq = Get-KdpSequence $d; $f = SecToFrames $d $at
    $g = @(Get-KdpJsonArray (Get-KdpProp $seq 'kdenlive:sequenceproperties.guides') | Where-Object { $_.PSObject.Properties['pos'] -and $_.pos -ne $f })
    Set-KdpProp $seq 'kdenlive:sequenceproperties.guides' (ConvertTo-KdpJson $g)
}
function Add-KdpClipMarker([KdpDoc]$d, [string]$bin, [double]$at, [string]$comment, [int]$category = 0, [double]$dur = 0) {
    $bc = Get-KdpBinClip $d $bin
    $m = @(Get-KdpJsonArray (Get-KdpProp $bc.Node 'kdenlive:markers'))
    $m += [pscustomobject]@{ comment = $comment; duration = (SecToFrames $d $dur); pos = (SecToFrames $d $at); type = $category }
    Set-KdpProp $bc.Node 'kdenlive:markers' (ConvertTo-KdpJson ($m | Sort-Object pos))
}

# ---------- clip state: speed, enable/disable ----------
# Partner of a clip in an AVSplit group (the other half of a linked audio+video clip), or $null.
function Get-KdpLinkedPartner([KdpDoc]$d, [string]$track, [int]$startF) {
    $t = Get-KdpTrack $d $track
    $me = "$($t.Index - 1):$startF"
    foreach ($g in @(Get-KdpGroupsDeep (Get-KdpJsonArray (Get-KdpProp (Get-KdpSequence $d) 'kdenlive:sequenceproperties.groups')))) {
        if ($g.type -ne 'AVSplit') { continue }
        $leaves = @($g.children | ForEach-Object { $_.data })
        if (-not ($leaves | Where-Object { $_ -eq $me -or $_ -like "${me}:*" })) { continue }
        $other = $leaves | Where-Object { -not ($_ -eq $me -or $_ -like "${me}:*") } | Select-Object -First 1
        $parts = $other.Split(':')
        $pt = Get-KdpTracks $d | Where-Object Index -eq ([int]$parts[0] + 1)
        if ($pt) { return [pscustomobject]@{ Track = $pt.Name; StartFrames = [int]$parts[1] } }
    }
    return $null
}
# every group, however deeply nested (a user group can contain a linked audio+video pair)
function Get-KdpGroupsDeep($groups) { foreach ($g in @($groups)) { if ($g -and $g.PSObject.Properties['children']) { $g; Get-KdpGroupsDeep $g.children } } }
function Set-KdpClipSpeed([KdpDoc]$d, [string]$track, [double]$at, [double]$speed, [switch]$KeepPitch, [switch]$NoLinked) {
    if ($speed -eq 0) { throw 'Speed cannot be 0' }
    $c = Find-KdpClip $d $track $at
    Assert-KdpNotMixed $d $c
    if (-not $NoLinked) {
        $partner = Get-KdpLinkedPartner $d $track $c.StartFrames
        if ($partner) { Set-KdpClipSpeed $d $partner.Track (($partner.StartFrames + 0.5) / $d.Fps) $speed -KeepPitch:$KeepPitch -NoLinked; $c = Find-KdpClip $d $track $at }
    }
    $t = Get-KdpTrack $d $track
    $e = $c.Node
    $prod = $d.Xml.mlt.SelectSingleNode("*[@id='$($e.producer)']")
    $bin = Get-KdpBinClip $d (Get-KdpProp $e 'kdenlive:id')
    if (Test-KdpEndless $bin.Node) { throw 'Speed change applies to video/audio clips only.' }
    $oldSpeed = 1.0; if ((Get-KdpProp $prod 'mlt_service') -eq 'timewarp') { $oldSpeed = [double]::Parse((Get-KdpProp $prod 'warp_speed'), [cultureinfo]::InvariantCulture) }
    $srcLen = ConvertTo-KdpFrames $d (Get-KdpProp $bin.Node 'length')
    $inOut = ConvertTo-KdpFrames $d $e.in; $outOut = ConvertTo-KdpFrames $d $e.out
    # current source range
    if ($oldSpeed -gt 0) { $srcIn = [int][math]::Round($inOut * $oldSpeed); $srcOut = [int][math]::Round(($outOut + 1) * $oldSpeed) - 1 }
    else { $a = [math]::Abs($oldSpeed); $srcOut = $srcLen - 1 - [int][math]::Round($inOut * $a); $srcIn = $srcLen - [int][math]::Round(($outOut + 1) * $a) }
    $abs = [math]::Abs($speed)
    if ($speed -gt 0) { $newIn = [int][math]::Floor($srcIn / $abs) } else { $newIn = [int][math]::Floor(($srcLen - 1 - $srcOut) / $abs) }
    $newLen = [int][math]::Max(1, [math]::Round(($srcOut - $srcIn + 1) / $abs))
    Remove-KdpEntry $d $t $e
    if ($speed -eq 1) {
        $copy = $bin.Node.Clone(); $copy.SetAttribute('id', (New-KdpId $d $bin.Node.Name))
        $newIn = $srcIn; $newLen = $srcOut - $srcIn + 1
    } else {
        $copy = $d.Xml.CreateElement('producer'); $copy.SetAttribute('id', (New-KdpId $d 'producer'))
        $sp = $speed.ToString('0.###############', [cultureinfo]::InvariantCulture)
        $res = Get-KdpProp $bin.Node 'resource'
        $copy.SetAttribute('in', (ConvertTo-KdpTime $d 0)); $copy.SetAttribute('out', (ConvertTo-KdpTime $d ([int][math]::Round($srcLen / $abs) - 1)))
        foreach ($kv in ([ordered]@{ length = [int][math]::Round($srcLen / $abs); eof = 'pause'; resource = "${sp}:$res"; warp_speed = $sp; warp_resource = $res; warp_pitch = $(if ($KeepPitch) { 1 } else { 0 }); mlt_service = 'timewarp'; audio_index = (Get-KdpProp $bin.Node 'audio_index'); video_index = (Get-KdpProp $bin.Node 'video_index'); 'kdenlive:clipname' = $bin.Name; 'kdenlive:clip_type' = (Get-KdpProp $bin.Node 'kdenlive:clip_type'); 'kdenlive:id' = $bin.BinId; 'kdenlive:control_uuid' = (Get-KdpProp $bin.Node 'kdenlive:control_uuid') }).GetEnumerator()) { if ($null -ne $kv.Value) { Set-KdpProp $copy $kv.Key $kv.Value } }
    }
    if ($t.Audio) { Set-KdpProp $copy 'set.test_audio' 0; Set-KdpProp $copy 'set.test_image' 1 } else { Set-KdpProp $copy 'set.test_audio' 1; Set-KdpProp $copy 'set.test_image' 0 }
    [void]$d.Xml.mlt.InsertBefore($copy, $t.Playlists[0])
    $e.SetAttribute('producer', $copy.id); $e.SetAttribute('in', (ConvertTo-KdpTime $d $newIn)); $e.SetAttribute('out', (ConvertTo-KdpTime $d ($newIn + $newLen - 1)))
    try { Set-KdpEntryAt $d $t $e $c.StartFrames $newLen }
    catch { throw "Clip at new speed needs $([math]::Round($newLen / $d.Fps,3)) s but runs into the next clip: $($_.Exception.Message)" }
}
function Set-KdpClipEnabled([KdpDoc]$d, [string]$track, [double]$at, [bool]$enabled) {
    $c = Find-KdpClip $d $track $at; $t = Get-KdpTrack $d $track; $e = $c.Node
    $prod = $d.Xml.mlt.SelectSingleNode("*[@id='$($e.producer)']")
    $bin = Get-KdpBinClip $d (Get-KdpProp $e 'kdenlive:id')
    if ([object]::ReferenceEquals($prod, $bin.Node)) {
        $copy = $prod.Clone(); $copy.SetAttribute('id', (New-KdpId $d $prod.Name)); [void]$d.Xml.mlt.InsertBefore($copy, $t.Playlists[0]); $e.SetAttribute('producer', $copy.id); $prod = $copy
    }
    if ($enabled) { if ($t.Audio) { Set-KdpProp $prod 'set.test_audio' 0; Set-KdpProp $prod 'set.test_image' 1 } else { Set-KdpProp $prod 'set.test_audio' 1; Set-KdpProp $prod 'set.test_image' 0 } }
    else { Set-KdpProp $prod 'set.test_audio' 1; Set-KdpProp $prod 'set.test_image' 1 }
}

# ---------- same-track mix (crossfade) ----------
# $at = the cut time between clip A (ending at $at) and clip B (starting at $at). B is extended
# $dur seconds to the left (needs that much unused source before its in-point) and moved to the
# track's second playlist; a luma (video) or mix (audio) transition joins them.
function Add-KdpMix([KdpDoc]$d, [string]$track, [double]$at, [double]$dur = 1) {
    $t = Get-KdpTrack $d $track
    $cutF = SecToFrames $d $at; $dF = SecToFrames $d $dur
    $clips = @(Get-KdpClips $d | Where-Object { $_.Track -eq $t.Name -and $_.Sub -eq 0 })
    $A = $clips | Where-Object { $_.StartFrames + $_.LenFrames -eq $cutF }
    $B = $clips | Where-Object { $_.StartFrames -eq $cutF }
    if (-not $A -or -not $B) { throw "Need one clip ending and one clip starting exactly at $at s on $track (the earlier clip must not itself be the second half of another crossfade)." }
    if ($dF -ge $A.LenFrames -or $dF -ge $B.LenFrames) { throw 'Crossfade must be shorter than both clips.' }
    $bIn = ConvertTo-KdpFrames $d $B.Node.in
    $bProd = $d.Xml.mlt.SelectSingleNode("*[@id='$($B.Node.producer)']")
    if ($bIn -lt $dF -and -not (Test-KdpEndless $bProd)) { throw "Clip B has only $([math]::Round($bIn / $d.Fps,3)) s of source before its in-point; need $dur s. Trim B's start first." }
    $newIn = [math]::Max(0, $bIn - $dF)
    Remove-KdpEntry $d $t $B.Node        # leaves a blank of B's length on playlist 0
    $B.Node.SetAttribute('in', (ConvertTo-KdpTime $d $newIn))
    try { Set-KdpEntryAt $d $t $B.Node ($cutF - $dF) ($B.LenFrames + $dF) -Sub 1 }
    catch { $B.Node.SetAttribute('in', (ConvertTo-KdpTime $d $bIn)); Set-KdpEntryAt $d $t $B.Node $cutF $B.LenFrames -Overwrite; throw "Another crossfade on $track overlaps this one: $($_.Exception.Message)" }
    $tr = $d.Xml.CreateElement('transition'); $tr.SetAttribute('id', (New-KdpId $d 'transition'))
    $tr.SetAttribute('in', (ConvertTo-KdpTime $d ($cutF - $dF))); $tr.SetAttribute('out', (ConvertTo-KdpTime $d ($cutF - 1)))
    if ($t.Audio) { $props = [ordered]@{ a_track = 0; b_track = 1; start = -1; accepts_blanks = 1; mlt_service = 'mix'; kdenlive_id = 'mix'; 'kdenlive:mixcut' = $dF; reverse = 0 } }
    else { $props = [ordered]@{ a_track = 0; b_track = 1; factory = 'loader'; resource = ''; mlt_service = 'luma'; kdenlive_id = 'luma'; 'kdenlive:mixcut' = $dF; softness = 0; alpha_over = 1; invert = 0; reverse = 0 } }
    foreach ($kv in $props.GetEnumerator()) { Set-KdpProp $tr $kv.Key $kv.Value }
    [void]$t.Tractor.AppendChild($tr)
}
function Remove-KdpMix([KdpDoc]$d, [string]$track, $at = $null) {
    $t = Get-KdpTrack $d $track
    $mixes = @($t.Tractor.SelectNodes("transition[property[@name='kdenlive:mixcut']]"))
    if (-not $mixes.Count) { throw "No mix on $track" }
    if ($null -ne $at -and "$at" -ne '') {
        $f = SecToFrames $d ([double]$at)
        $tr = $mixes | Where-Object { $f -ge (ConvertTo-KdpFrames $d $_.in) - 1 -and $f -le (ConvertTo-KdpFrames $d $_.out) + 1 } | Select-Object -First 1
        if (-not $tr) { throw "No mix on $track around $at s" }
    } elseif ($mixes.Count -gt 1) { throw "Several mixes on $track; give -At inside the one to remove." } else { $tr = $mixes[0] }
    $startF = ConvertTo-KdpFrames $d $tr.in
    $B = Get-KdpClips $d | Where-Object { $_.Track -eq $t.Name -and $_.Sub -eq 1 -and $_.StartFrames -eq $startF } | Select-Object -First 1
    if (-not $B) { throw 'Mix found but its second clip is missing.' }
    $dF = [int](Get-KdpProp $tr 'kdenlive:mixcut')
    [void]$t.Tractor.RemoveChild($tr)
    Remove-KdpEntry $d $t $B.Node -Ripple:$false
    $inF = ConvertTo-KdpFrames $d $B.Node.in
    $B.Node.SetAttribute('in', (ConvertTo-KdpTime $d ($inF + $dF)))
    Set-KdpEntryAt $d $t $B.Node ($B.StartFrames + $dF) ($B.LenFrames - $dF) -Overwrite
}

# ---------- linked audio+video (AV split group) ----------
function Add-KdpAVClip([KdpDoc]$d, [string]$bin, [string]$videoTrack, [string]$audioTrack, [double]$at, [double]$in = 0, [double]$dur = -1) {
    $ev = Add-KdpClipToTimeline $d $bin $videoTrack $at $in $dur
    $ea = Add-KdpClipToTimeline $d $bin $audioTrack $at $in $dur
    $vt = Get-KdpTrack $d $videoTrack; $atk = Get-KdpTrack $d $audioTrack
    $f = SecToFrames $d $at
    Add-KdpGroup $d 'AVSplit' @("$($atk.Index - 1):$($f):-1", "$($vt.Index - 1):$($f):-1")
}
function Add-KdpGroup([KdpDoc]$d, [string]$type, [string[]]$leafData) {
    $seq = Get-KdpSequence $d
    $g = @(Get-KdpJsonArray (Get-KdpProp $seq 'kdenlive:sequenceproperties.groups'))
    $children = @($leafData | ForEach-Object { [pscustomobject]@{ data = $_; leaf = 'clip'; type = 'Leaf' } })
    $g += [pscustomobject]@{ children = $children; type = $type }
    Set-KdpProp $seq 'kdenlive:sequenceproperties.groups' (ConvertTo-KdpJson $g)
}
function Add-KdpUserGroup([KdpDoc]$d, [string[]]$clipRefs) {
    # clipRefs like "V1@3" (track@seconds)
    $leaves = foreach ($r in $clipRefs) { $tn, $s = $r.Split('@'); $c = Find-KdpClip $d $tn ([double]$s); $t = Get-KdpTrack $d $tn; "$($t.Index - 1):$($c.StartFrames):-1" }
    Add-KdpGroup $d 'Normal' $leaves
}

# ---------- folders and bin management ----------
function Add-KdpFolder([KdpDoc]$d, [string]$name, [string]$parent = '-1') {
    $id = Get-KdpNextBinId $d
    $mb = $d.Xml.mlt.SelectSingleNode("playlist[@id='main_bin']")
    $p = $d.Xml.CreateElement('property'); $p.SetAttribute('name', "kdenlive:folder.$parent.$id"); $p.InnerText = $name
    [void]$mb.InsertBefore($p, $mb.FirstChild)
    return $id
}
function Get-KdpFolders([KdpDoc]$d) { foreach ($p in $d.Xml.mlt.SelectNodes("playlist[@id='main_bin']/property[starts-with(@name,'kdenlive:folder.')]")) { $parts = $p.GetAttribute('name').Split('.'); [pscustomobject]@{ Id = $parts[-1]; Parent = $parts[-2]; Name = $p.InnerText } } }
function Move-KdpBinClip([KdpDoc]$d, [string]$bin, [string]$folder) {
    $bc = Get-KdpBinClip $d $bin
    $f = if ($folder -eq '-1' -or $folder -eq 'root') { '-1' } else { $x = Get-KdpFolders $d | Where-Object { $_.Id -eq $folder -or $_.Name -eq $folder } | Select-Object -First 1; if (-not $x) { throw "Folder '$folder' not found" }; $x.Id }
    Set-KdpProp $bc.Node 'kdenlive:folderid' $f
}
function Rename-KdpBinClip([KdpDoc]$d, [string]$bin, [string]$name) { $bc = Get-KdpBinClip $d $bin; Set-KdpProp $bc.Node 'kdenlive:clipname' $name }
function Remove-KdpBinClip([KdpDoc]$d, [string]$bin, [switch]$Force) {
    $bc = Get-KdpBinClip $d $bin
    # uses in every sequence, not only the current one
    $savedSeq = $d.SeqId
    $uses = @(foreach ($sq in @(Get-KdpSequences $d)) {
        $d.SeqId = $sq.Uuid
        foreach ($u in @(Get-KdpClips $d | Where-Object BinId -eq $bc.BinId)) { @{ Seq = $sq.Uuid; Track = $u.Track; Node = $u.Node } }
    })
    $d.SeqId = $savedSeq
    if ($uses.Count -and -not $Force) { throw "Clip '$($bc.Name)' is used $($uses.Count) time(s) on the timeline; remove those first or use -Force." }
    foreach ($u in $uses) { $d.SeqId = $u.Seq; Remove-KdpEntry $d (Get-KdpTrack $d $u.Track) $u.Node }
    $d.SeqId = $savedSeq
    foreach ($e in @($d.Xml.mlt.SelectNodes("playlist[@id='main_bin']/entry[@producer='$($bc.ProducerId)']"))) { [void]$e.ParentNode.RemoveChild($e) }
    [void]$d.Xml.mlt.RemoveChild($bc.Node)
}

# ---------- subtitles (.ass sidecar + burn-in filter) ----------
function Format-KdpAssTime([double]$s) { $t = [TimeSpan]::FromSeconds($s); '{0}:{1:00}:{2:00}.{3:00}' -f [int][math]::Floor($t.TotalHours), $t.Minutes, $t.Seconds, [int][math]::Floor($t.Milliseconds / 10) }
function Add-KdpSubtitle([KdpDoc]$d, [double]$at, [double]$dur, [string]$text, [string]$font = 'Segoe UI', [int]$size = 64) {
    $seq = Get-KdpSequence $d
    $assPath = Get-KdpAssPath $d $seq
    $assName = [IO.Path]::GetFileName($assPath)
    if (-not (Test-Path $assPath)) {
        $W = $d.Xml.mlt.profile.width; $H = $d.Xml.mlt.profile.height
        $hdr = "[Script Info]`n; Script generated by Kdenlive 26.08.3`nScriptType: v4.00+`nPlayResX: $W`nPlayResY: $H`nLayoutResX: $W`nLayoutResY: $H`nWrapStyle: 0`nScaledBorderAndShadow: yes`nYCbCr Matrix: None`n`n[V4+ Styles]`nFormat: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding`nStyle: Default,$font,$size,&H00ffffff,&H000000ff,&H00000000,&H00000000,0,0,0,0,100,100,0,0,1,2,0,2,10,10,60,1`n`n[Events]`nFormat: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text`n"
        [IO.File]::WriteAllText($assPath, $hdr, (New-Object Text.UTF8Encoding($false)))
    }
    $line = "Dialogue: 0,$(Format-KdpAssTime $at),$(Format-KdpAssTime ($at + $dur)),Default,,0,0,0,,$($text -replace "`r?`n", '\N')`n"
    $all = [IO.File]::ReadAllText($assPath)
    $dlg = @(([regex]::Matches($all, '(?m)^Dialogue:.*$') | ForEach-Object { $_.Value.TrimEnd() })) + $line.TrimEnd()
    $dlg = $dlg | Sort-Object { if ($_ -match '^Dialogue:\s*\d+,(\d+):(\d+):(\d+)\.(\d+),') { [int]$matches[1] * 3600 + [int]$matches[2] * 60 + [int]$matches[3] + [int]$matches[4] / 100 } else { 0 } }
    $headOnly = [regex]::Replace($all, '(?m)^Dialogue:.*\r?\n?', '')
    [IO.File]::WriteAllText($assPath, $headOnly.TrimEnd() + "`n" + ($dlg -join "`n") + "`n", (New-Object Text.UTF8Encoding($false)))
    Set-KdpProp $seq 'kdenlive:sequenceproperties.subtitlesList' ("[{""file"":""$assName"",""id"":0,""name"":""Subtitles""}]")
    Set-KdpProp $seq 'kdenlive:sequenceproperties.activeSubtitleIndex' 0
    $f = $seq.SelectSingleNode("filter[property[@name='mlt_service']='avfilter.subtitles']")
    if (-not $f) {
        $f = $d.Xml.CreateElement('filter'); $f.SetAttribute('id', (New-KdpId $d 'filter'))
        Set-KdpProp $f 'av.filename' ($assPath -replace '\\', '/'); Set-KdpProp $f 'mlt_service' 'avfilter.subtitles'; Set-KdpProp $f 'internal_added' 237; Set-KdpProp $f 'av.alpha' 1; Set-KdpProp $f 'disable' 0
        [void]$seq.AppendChild($f)
    }
}

# ---------- new project ----------
function New-KdpProject([string]$path, [string]$profile = 'vertical_hd_30', [int]$videoTracks = 2, [int]$audioTracks = 2) {
    $pf = Join-Path $script:KdpProfiles $profile
    if (-not (Test-Path $pf)) { throw "Unknown profile '$profile'. See engine\Kdenlive\...\share\mlt\profiles" }
    $pr = @{}; foreach ($l in Get-Content $pf) { if ($l -match '^(\w+)=(.*)$') { $pr[$matches[1]] = $matches[2] } }
    $dir = Split-Path ([IO.Path]::GetFullPath($path)) -Parent; New-Item -ItemType Directory -Force $dir | Out-Null
    $dir = [KdPath]::Long($dir)
    $root = $dir -replace '\\', '/'
    $uuid = '{' + [guid]::NewGuid().ToString() + '}'; $session = '{' + [guid]::NewGuid().ToString() + '}'
    $docid = [string][DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    $cats = '[{"color":"#9b59b6","comment":"Category 1","index":0},{"color":"#3daee9","comment":"Category 2","index":1},{"color":"#1abc9c","comment":"Category 3","index":2},{"color":"#1cdc9a","comment":"Category 4","index":3},{"color":"#c9ce3b","comment":"Category 5","index":4},{"color":"#fdbc4b","comment":"Category 6","index":5},{"color":"#f39c1f","comment":"Category 7","index":6},{"color":"#f47750","comment":"Category 8","index":7},{"color":"#da4453","comment":"Category 9","index":8}]'
    $sb = New-Object Text.StringBuilder
    [void]$sb.AppendLine("<?xml version='1.0' encoding='utf-8'?>")
    [void]$sb.AppendLine("<mlt LC_NUMERIC=""C"" producer=""main_bin"" root=""$root"" version=""7.43.0"">")
    [void]$sb.AppendLine(" <profile colorspace=""$($pr.colorspace)"" description=""$($pr.description)"" display_aspect_den=""$($pr.display_aspect_den)"" display_aspect_num=""$($pr.display_aspect_num)"" frame_rate_den=""$($pr.frame_rate_den)"" frame_rate_num=""$($pr.frame_rate_num)"" height=""$($pr.height)"" progressive=""$($pr.progressive)"" sample_aspect_den=""$($pr.sample_aspect_den)"" sample_aspect_num=""$($pr.sample_aspect_num)"" width=""$($pr.width)""/>")
    [void]$sb.AppendLine(' <producer id="producer0" in="00:00:00.000" out="00:05:00.000"><property name="length">2147483647</property><property name="eof">continue</property><property name="resource">black</property><property name="aspect_ratio">1</property><property name="mlt_service">color</property><property name="kdenlive:playlistid">black_track</property><property name="mlt_image_format">rgba</property><property name="set.test_audio">0</property></producer>')
    $trackIds = @(); $n = 0; $tn = 0
    for ($i = 0; $i -lt $audioTracks; $i++) {
        [void]$sb.AppendLine(" <playlist id=""playlist$n""><property name=""kdenlive:audio_track"">1</property></playlist>"); $p1 = "playlist$n"; $n++
        [void]$sb.AppendLine(" <playlist id=""playlist$n""><property name=""kdenlive:audio_track"">1</property></playlist>"); $p2 = "playlist$n"; $n++
        [void]$sb.AppendLine(" <tractor id=""tractor$tn"" in=""00:00:00.000""><property name=""kdenlive:audio_track"">1</property><property name=""kdenlive:trackheight"">67</property><property name=""kdenlive:timeline_active"">1</property><property name=""kdenlive:collapsed"">0</property><property name=""kdenlive:thumbs_format""/><property name=""kdenlive:audio_rec""/><track hide=""video"" producer=""$p1""/><track hide=""video"" producer=""$p2""/><filter id=""filter$($tn)a""><property name=""window"">75</property><property name=""max_gain"">20dB</property><property name=""channel_mask"">-1</property><property name=""mlt_service"">volume</property><property name=""internal_added"">237</property><property name=""disable"">1</property></filter><filter id=""filter$($tn)b""><property name=""channel"">-1</property><property name=""mlt_service"">panner</property><property name=""internal_added"">237</property><property name=""start"">0.5</property><property name=""disable"">1</property></filter><filter id=""filter$($tn)c""><property name=""iec_scale"">0</property><property name=""prefix"">meta.media.audio_level.</property><property name=""mlt_service"">audiolevel</property><property name=""internal_added"">237</property><property name=""dbpeak"">1</property><property name=""disable"">1</property></filter></tractor>")
        $trackIds += @{ Id = "tractor$tn"; Audio = $true }; $tn++
    }
    for ($i = 0; $i -lt $videoTracks; $i++) {
        [void]$sb.AppendLine(" <playlist id=""playlist$n""/>"); $p1 = "playlist$n"; $n++
        [void]$sb.AppendLine(" <playlist id=""playlist$n""/>"); $p2 = "playlist$n"; $n++
        [void]$sb.AppendLine(" <tractor id=""tractor$tn"" in=""00:00:00.000""><property name=""kdenlive:trackheight"">67</property><property name=""kdenlive:timeline_active"">1</property><property name=""kdenlive:collapsed"">0</property><property name=""kdenlive:thumbs_format""/><property name=""kdenlive:audio_rec""/><track hide=""audio"" producer=""$p1""/><track hide=""audio"" producer=""$p2""/></tractor>")
        $trackIds += @{ Id = "tractor$tn"; Audio = $false }; $tn++
    }
    $total = $audioTracks + $videoTracks
    [void]$sb.AppendLine(" <tractor id=""$uuid"" in=""00:00:00.000"" out=""00:00:00.000"">")
    foreach ($kv in ([ordered]@{ 'kdenlive:uuid' = $uuid; 'kdenlive:clipname' = 'Sequence 1'; 'kdenlive:sequenceproperties.hasAudio' = 1; 'kdenlive:sequenceproperties.hasVideo' = 1; 'kdenlive:sequenceproperties.activeTrack' = $audioTracks; 'kdenlive:sequenceproperties.tracksCount' = $total; 'kdenlive:sequenceproperties.documentuuid' = $uuid; 'kdenlive:control_uuid' = $uuid; 'kdenlive:duration' = '00:00:00.033'; 'kdenlive:maxduration' = 1; 'kdenlive:producer_type' = 17; 'kdenlive:id' = 3; 'kdenlive:clip_type' = 0; 'kdenlive:file_size' = 0; 'kdenlive:folderid' = 2; 'kdenlive:sequenceproperties.audioTarget' = -1; 'kdenlive:sequenceproperties.disablepreview' = 0; 'kdenlive:sequenceproperties.position' = 0; 'kdenlive:sequenceproperties.scrollPos' = 0; 'kdenlive:sequenceproperties.videoTarget' = $audioTracks; 'kdenlive:sequenceproperties.zonein' = 0; 'kdenlive:sequenceproperties.zoneout' = 75; 'kdenlive:sequenceproperties.zoom' = 8; 'kdenlive:sequenceproperties.groups' = "[`n]`n"; 'kdenlive:sequenceproperties.guides' = "[`n]`n" }).GetEnumerator()) { [void]$sb.AppendLine("  <property name=""$($kv.Key)"">$([Security.SecurityElement]::Escape([string]$kv.Value))</property>") }
    [void]$sb.AppendLine('  <track producer="producer0"/>')
    foreach ($t in $trackIds) { [void]$sb.AppendLine("  <track producer=""$($t.Id)""/>") }
    $ti = 0; $idx = 1
    foreach ($t in $trackIds) {
        if ($t.Audio) { [void]$sb.AppendLine("  <transition id=""transition$ti""><property name=""a_track"">0</property><property name=""b_track"">$idx</property><property name=""duck_threshold"">0</property><property name=""duck_attenuation"">-12</property><property name=""duck_level"">0</property><property name=""duck_fade_in"">1500</property><property name=""duck_fade_out"">250</property><property name=""prefix""/><property name=""mlt_service"">mix</property><property name=""kdenlive_id"">mix</property><property name=""internal_added"">237</property><property name=""always_active"">1</property><property name=""accepts_blanks"">1</property><property name=""sum"">1</property></transition>") }
        else { [void]$sb.AppendLine("  <transition id=""transition$ti""><property name=""a_track"">0</property><property name=""b_track"">$idx</property><property name=""compositing"">0</property><property name=""distort"">0</property><property name=""rotate_center"">0</property><property name=""mlt_service"">qtblend</property><property name=""kdenlive_id"">qtblend</property><property name=""internal_added"">237</property><property name=""always_active"">1</property></transition>") }
        $ti++; $idx++
    }
    [void]$sb.AppendLine('  <filter id="filterm1"><property name="window">75</property><property name="max_gain">20dB</property><property name="channel_mask">-1</property><property name="mlt_service">volume</property><property name="internal_added">237</property><property name="disable">1</property></filter>')
    [void]$sb.AppendLine('  <filter id="filterm2"><property name="channel">-1</property><property name="mlt_service">panner</property><property name="internal_added">237</property><property name="start">0.5</property><property name="disable">1</property></filter>')
    [void]$sb.AppendLine(' </tractor>')
    [void]$sb.AppendLine(' <playlist id="main_bin">')
    foreach ($kv in ([ordered]@{ 'kdenlive:folder.-1.2' = 'Sequences'; 'kdenlive:sequenceFolder' = 2; 'kdenlive:docproperties.audioChannels' = 2; 'kdenlive:docproperties.binsort' = 0; 'kdenlive:docproperties.compositing' = 1; 'kdenlive:docproperties.documentid' = $docid; 'kdenlive:docproperties.enableTimelineZone' = 0; 'kdenlive:docproperties.enableexternalproxy' = 0; 'kdenlive:docproperties.enableproxy' = 0; 'kdenlive:docproperties.generateimageproxy' = 0; 'kdenlive:docproperties.generateproxy' = 0; 'kdenlive:docproperties.guidesCategories' = $cats; 'kdenlive:docproperties.kdenliveversion' = '26.08.3'; 'kdenlive:docproperties.patchversion' = 1; 'kdenlive:docproperties.profile' = $profile; 'kdenlive:docproperties.proxyimageminsize' = 2000; 'kdenlive:docproperties.proxyimagesize' = 800; 'kdenlive:docproperties.proxyminsize' = 1000; 'kdenlive:docproperties.proxyresize' = 640; 'kdenlive:docproperties.seekOffset' = 30000; 'kdenlive:docproperties.sessionid' = $session; 'kdenlive:docproperties.uuid' = $uuid; 'kdenlive:docproperties.version' = '1.1'; 'kdenlive:docproperties.verticalzoom' = 1; 'kdenlive:docproperties.zoom' = 7; 'kdenlive:expandedFolders' = ''; 'kdenlive:binZoom' = 4; 'kdenlive:extraBins' = 'project_bin:-1:0'; 'kdenlive:documentnotes' = ''; 'kdenlive:documentnotesversion' = 2; 'kdenlive:docproperties.opensequences' = $uuid; 'kdenlive:docproperties.activetimeline' = $uuid; 'xml_retain' = 1 }).GetEnumerator()) { [void]$sb.AppendLine("  <property name=""$($kv.Key)"">$([Security.SecurityElement]::Escape([string]$kv.Value))</property>") }
    [void]$sb.AppendLine("  <entry in=""00:00:00.000"" out=""00:00:00.000"" producer=""$uuid""/>")
    [void]$sb.AppendLine(' </playlist>')
    [void]$sb.AppendLine(" <tractor id=""tractor$tn"" in=""00:00:00.000"" out=""00:00:00.000""><property name=""kdenlive:projectTractor"">1</property><track in=""00:00:00.000"" out=""00:00:00.000"" producer=""$uuid""/></tractor>")
    [void]$sb.AppendLine('</mlt>')
    [IO.File]::WriteAllText([IO.Path]::GetFullPath($path), $sb.ToString(), (New-Object Text.UTF8Encoding($false)))
}

# ---------- additional sequences (nested timelines) ----------
# Creates sequence B with its own tracks, placed before every existing sequence in the file
# (MLT needs a nested sequence defined before the sequence that uses it). Use it on another
# sequence's track with Add-KdpClipToTimeline -bin <name>; edit it after Select-KdpSequence.
function Add-KdpSequence([KdpDoc]$d, [string]$name, [int]$videoTracks = 2, [int]$audioTracks = 1) {
    if (Get-KdpSequences $d | Where-Object Name -eq $name) { throw "A sequence named '$name' already exists." }
    $mb = $d.Xml.mlt.SelectSingleNode("playlist[@id='main_bin']")
    $docUuid = Get-KdpProp $mb 'kdenlive:docproperties.uuid'
    $folder = Get-KdpProp $mb 'kdenlive:sequenceFolder'; if (-not $folder) { $folder = '-1' }
    $uuid = '{' + [guid]::NewGuid().ToString() + '}'
    $binId = Get-KdpNextBinId $d
    # anchor = the first track playlist of the file: B goes after every bin producer (its clips must be
    # defined before it) and before every existing sequence (they may use B)
    $anchor = $d.Xml.mlt.SelectSingleNode("playlist[@id!='main_bin']")
    function NewEl([string]$tag, [string]$prefix) { $e = $d.Xml.CreateElement($tag); $e.SetAttribute('id', (New-KdpId $d $prefix)); [void]$d.Xml.mlt.InsertBefore($e, $anchor); $e }
    $black = NewEl 'producer' 'producer'; $black.SetAttribute('in', '00:00:00.000'); $black.SetAttribute('out', '00:05:00.000')
    foreach ($kv in ([ordered]@{ length = 2147483647; eof = 'continue'; resource = 'black'; aspect_ratio = 1; mlt_service = 'color'; 'kdenlive:playlistid' = 'black_track'; mlt_image_format = 'rgba'; 'set.test_audio' = 0 }).GetEnumerator()) { Set-KdpProp $black $kv.Key $kv.Value }
    $tracks = @()
    for ($i = 0; $i -lt $audioTracks + $videoTracks; $i++) {
        $isAudio = $i -lt $audioTracks
        $p1 = NewEl 'playlist' 'playlist'; $p2 = NewEl 'playlist' 'playlist'
        $tt = NewEl 'tractor' 'tractor'; $tt.SetAttribute('in', '00:00:00.000')
        if ($isAudio) { foreach ($p in $p1, $p2, $tt) { Set-KdpProp $p 'kdenlive:audio_track' 1 } }
        foreach ($kv in ([ordered]@{ 'kdenlive:trackheight' = 67; 'kdenlive:timeline_active' = 1; 'kdenlive:collapsed' = 0; 'kdenlive:thumbs_format' = ''; 'kdenlive:audio_rec' = '' }).GetEnumerator()) { Set-KdpProp $tt $kv.Key $kv.Value }
        foreach ($p in $p1, $p2) { $t = $d.Xml.CreateElement('track'); $t.SetAttribute('hide', $(if ($isAudio) { 'video' } else { 'audio' })); $t.SetAttribute('producer', $p.id); [void]$tt.AppendChild($t) }
        $tracks += @{ Node = $tt; Audio = $isAudio }
    }
    $seq = $d.Xml.CreateElement('tractor'); $seq.SetAttribute('id', $uuid); $seq.SetAttribute('in', '00:00:00.000'); $seq.SetAttribute('out', '00:00:00.000')
    [void]$d.Xml.mlt.InsertBefore($seq, $anchor)
    foreach ($kv in ([ordered]@{ 'kdenlive:uuid' = $uuid; 'kdenlive:clipname' = $name; 'kdenlive:sequenceproperties.hasAudio' = $(if ($audioTracks) { 1 } else { 0 }); 'kdenlive:sequenceproperties.hasVideo' = 1; 'kdenlive:sequenceproperties.activeTrack' = $audioTracks; 'kdenlive:sequenceproperties.tracksCount' = ($audioTracks + $videoTracks); 'kdenlive:sequenceproperties.documentuuid' = $docUuid; 'kdenlive:control_uuid' = $uuid; 'kdenlive:duration' = '00:00:00.033'; 'kdenlive:maxduration' = 1; 'kdenlive:producer_type' = 17; 'kdenlive:id' = $binId; 'kdenlive:clip_type' = $(if ($audioTracks) { 0 } else { 2 }); 'kdenlive:file_size' = 0; 'kdenlive:folderid' = $folder; 'kdenlive:sequenceproperties.audioTarget' = -1; 'kdenlive:sequenceproperties.videoTarget' = $audioTracks; 'kdenlive:sequenceproperties.zonein' = 0; 'kdenlive:sequenceproperties.zoneout' = 75; 'kdenlive:sequenceproperties.groups' = "[`n]`n"; 'kdenlive:sequenceproperties.guides' = "[`n]`n" }).GetEnumerator()) { Set-KdpProp $seq $kv.Key $kv.Value }
    $tb = $d.Xml.CreateElement('track'); $tb.SetAttribute('producer', $black.id); [void]$seq.AppendChild($tb)
    foreach ($t in $tracks) { $tr = $d.Xml.CreateElement('track'); $tr.SetAttribute('producer', $t.Node.id); [void]$seq.AppendChild($tr) }
    $idx = 1
    foreach ($t in $tracks) {
        $tr = $d.Xml.CreateElement('transition'); $tr.SetAttribute('id', (New-KdpId $d 'transition'))
        if ($t.Audio) { $props = [ordered]@{ a_track = 0; b_track = $idx; mlt_service = 'mix'; kdenlive_id = 'mix'; internal_added = 237; always_active = 1; accepts_blanks = 1; sum = 1 } }
        else { $props = [ordered]@{ a_track = 0; b_track = $idx; compositing = 0; distort = 0; rotate_center = 0; mlt_service = 'qtblend'; kdenlive_id = 'qtblend'; internal_added = 237; always_active = 1 } }
        foreach ($kv in $props.GetEnumerator()) { Set-KdpProp $tr $kv.Key $kv.Value }
        [void]$seq.AppendChild($tr); $idx++
    }
    $e = $d.Xml.CreateElement('entry'); $e.SetAttribute('producer', $uuid); $e.SetAttribute('in', '00:00:00.000'); $e.SetAttribute('out', '00:00:00.000')
    [void]$mb.AppendChild($e)
    return Get-KdpBinClip $d "$binId"
}

# ---------- slideshow (image sequence) ----------
# $source: a folder (all images with -Ext) or a printf pattern like C:\...\img_%04d.png
function Add-KdpSlideshow([KdpDoc]$d, [string]$source, [string]$ext = 'png', [double]$perImage = 1, [string]$name, [switch]$Loop, [switch]$Crop, [switch]$Fade, [double]$fadeSeconds = 0.5, [string]$animation = '') {
    if (Test-Path $source -PathType Container) {
        $files = @(Get-ChildItem $source -Filter "*.$ext" -File | Sort-Object Name)
        if (-not $files) { throw "No *.$ext files in $source" }
        $full = (Resolve-Path $source).Path.TrimEnd('\') + "\.all.$ext"
        $count = $files.Count
    } else {
        $dir = Split-Path $source -Parent; $leaf = Split-Path $source -Leaf
        if ($leaf -notmatch '^(.*)%0(\d)d(\..+)$') { throw 'Pattern must look like img_%04d.png' }
        $rx = '^' + [regex]::Escape($matches[1]) + '\d{' + $matches[2] + '}' + [regex]::Escape($matches[3]) + '$'
        $count = @(Get-ChildItem $dir -File | Where-Object { $_.Name -match $rx }).Count
        if (-not $count) { throw "No files match $source" }
        $full = (Resolve-Path $dir).Path.TrimEnd('\') + '\' + $leaf
    }
    $root = $d.Root -replace '/', '\'
    $full = Join-Path ([KdPath]::Long((Split-Path $full -Parent))) (Split-Path $full -Leaf)
    $u1 = New-Object System.Uri(($root.TrimEnd('\') + '\')); $u2 = New-Object System.Uri(($full -replace '%', 'KDPPCT'))
    $rel = [System.Uri]::UnescapeDataString($u1.MakeRelativeUri($u2).ToString()) -replace 'KDPPCT', '%'
    $ttl = SecToFrames $d $perImage; $lenF = $ttl * $count
    if (-not $name) { $name = "Slideshow ($count)" }
    $props = [ordered]@{ length = $lenF; eof = 'pause'; resource = $rel; ttl = $ttl; mlt_service = 'qimage'; loop = $(if ($Loop) { 1 } else { 0 }); crop = $(if ($Crop) { 1 } else { 0 }); fade = $(if ($Fade) { 1 } else { 0 }); luma_duration = (SecToFrames $d $fadeSeconds); luma_file = ''; softness = 0; animation = $animation; 'low-pass' = 0; 'kdenlive:clipname' = $name; 'kdenlive:duration' = (ConvertTo-KdpTime $d $lenF); 'kdenlive:clip_type' = 2 }
    return Add-KdpBinProducer $d 'producer' 'producer' $props $lenF
}

# ---------- Lottie / Glaxnimate animation ----------
function Add-KdpAnimation([KdpDoc]$d, [string]$file, [string]$name) {
    $full = (Resolve-Path $file).Path
    # ask MLT for the length in project frames
    $tmp = [IO.Path]::GetTempFileName() + '.mlt'
    $prof = [IO.Path]::GetFileName((Get-ChildItem $script:KdpProfiles | Where-Object { (Get-Content $_.FullName) -contains "width=$($d.Xml.mlt.profile.width)" -and (Get-Content $_.FullName) -contains "height=$($d.Xml.mlt.profile.height)" -and (Get-Content $_.FullName) -contains "frame_rate_num=$($d.Xml.mlt.profile.frame_rate_num)" -and (Get-Content $_.FullName) -contains "frame_rate_den=$($d.Xml.mlt.profile.frame_rate_den)" } | Select-Object -First 1).FullName)
    $args1 = @(); if ($prof) { $args1 += '-profile'; $args1 += $prof }
    $p = Start-Process -FilePath (Join-Path $script:KdpBin 'melt.exe') -ArgumentList ($args1 + @("glaxnimate:`"$full`"", '-consumer', "xml:`"$tmp`"")) -NoNewWindow -Wait -PassThru -RedirectStandardError ([IO.Path]::GetTempFileName())
    [xml]$x = Get-Content $tmp -Raw; Remove-Item $tmp -ErrorAction SilentlyContinue
    $lenF = [int](($x.mlt.producer | Select-Object -First 1).property | Where-Object name -eq 'length').'#text'
    if ($lenF -lt 1) { throw "MLT could not read the animation $file" }
    if (-not $name) { $name = [IO.Path]::GetFileName($file) }
    $props = [ordered]@{ length = $lenF; eof = 'pause'; resource = (Get-KdpRelPath $d $full); background = '#00000000'; aspect_ratio = 1; progressive = 1; seekable = 1; mlt_service = 'glaxnimate'; 'kdenlive:clipname' = $name; 'kdenlive:clip_type' = 2; 'kdenlive:file_size' = (Get-Item $full).Length; 'kdenlive:file_hash' = (Get-KdpFileHash $full) }
    return Add-KdpBinProducer $d 'producer' 'producer' $props $lenF
}

# ---------- time remapping ----------
# $map: "outputSeconds=sourceSeconds;..." (output time counted from the clip start), or use
# $speed for a constant remap. Applies to the linked audio/video partner too.
function Set-KdpTimeRemap([KdpDoc]$d, [string]$track, [double]$at, [string]$map, [double]$speed = 0, [switch]$KeepPitch, [switch]$Blend, [switch]$NoLinked) {
    $c = Find-KdpClip $d $track $at
    Assert-KdpNotMixed $d $c
    if (-not $NoLinked) { $partner = Get-KdpLinkedPartner $d $track $c.StartFrames; if ($partner) { Set-KdpTimeRemap $d $partner.Track (($partner.StartFrames + 0.5) / $d.Fps) $map $speed -KeepPitch:$KeepPitch -Blend:$Blend -NoLinked; $c = Find-KdpClip $d $track $at } }
    $t = Get-KdpTrack $d $track; $e = $c.Node
    $bin = Get-KdpBinClip $d (Get-KdpProp $e 'kdenlive:id')
    if ($bin.Node.Name -ne 'chain') { throw 'Time remapping works on video/audio file clips only.' }
    $prod = $d.Xml.mlt.SelectSingleNode("*[@id='$($e.producer)']")
    if ((Get-KdpProp $prod 'mlt_service') -eq 'timewarp') { throw 'This clip has a speed change; set speed 1 first (remap and speed cannot be combined).' }
    $inF = ConvertTo-KdpFrames $d $e.in
    $srcStart = $inF / $d.Fps
    $remap = $prod.SelectSingleNode("link[property[@name='mlt_service']='timeremap']")
    if ($remap) { $old = Get-KdpProp $remap 'time_map'; if ($old -match '^[^=]+=([\d.]+)') { $srcStart = [double]::Parse($matches[1], [cultureinfo]::InvariantCulture) } }
    if (-not $map) {
        if ($speed -le 0) { throw 'Give -Map "outSec=srcSec;..." or a positive -Speed.' }
        $srcDur = $c.LenFrames / $d.Fps * $(if ($remap) { 1 } else { 1 })
        $outDur = $srcDur / $speed
        $map = "0=$srcStart;$outDur=$($srcStart + $srcDur)"
    }
    $keys = @($map.Split(';') | Where-Object { $_ } | ForEach-Object { $k, $v = $_.Split('='); @{ Out = [double]::Parse($k, [cultureinfo]::InvariantCulture); Src = [double]::Parse($v, [cultureinfo]::InvariantCulture) } } | Sort-Object { $_.Out })
    if ($keys.Count -lt 2) { throw 'A remap needs at least two keyframes.' }
    $srcLen = (ConvertTo-KdpFrames $d (Get-KdpProp $bin.Node 'length')) / $d.Fps
    foreach ($k in $keys) { if ($k.Src -lt 0 -or $k.Src -gt $srcLen) { throw "Source time $($k.Src) s is outside the clip (0..$srcLen s)." } }
    $outLen = [int][math]::Round($keys[-1].Out * $d.Fps)
    # chain output frames start at the entry's in: keep in, keys shifted by it; last key one frame late (Kdenlive's rule)
    $parts = for ($i = 0; $i -lt $keys.Count; $i++) {
        $f = $inF + [int][math]::Round($keys[$i].Out * $d.Fps); if ($i -eq $keys.Count - 1) { $f += 1 }
        (ConvertTo-KdpTime $d $f) + '=' + $keys[$i].Src.ToString('0.######', [cultureinfo]::InvariantCulture)
    }
    $copy = $bin.Node.Clone(); $copy.SetAttribute('id', (New-KdpId $d 'chain'))
    foreach ($l in @($copy.SelectNodes('link'))) { [void]$copy.RemoveChild($l) }
    if ($t.Audio) { Set-KdpProp $copy 'set.test_audio' 0; Set-KdpProp $copy 'set.test_image' 1 } else { Set-KdpProp $copy 'set.test_audio' 1; Set-KdpProp $copy 'set.test_image' 0 }
    $link = $d.Xml.CreateElement('link'); $link.SetAttribute('id', (New-KdpId $d 'link'))
    Set-KdpProp $link 'mlt_service' 'timeremap'; Set-KdpProp $link 'time_map' ($parts -join ';'); Set-KdpProp $link 'pitch' $(if ($KeepPitch -or $t.Audio) { 1 } else { 0 }); Set-KdpProp $link 'image_mode' $(if ($Blend) { 'blend' } else { 'nearest' })
    [void]$copy.AppendChild($link)
    [void]$d.Xml.mlt.InsertBefore($copy, $t.Playlists[0])
    Remove-KdpEntry $d $t $e
    $e.SetAttribute('producer', $copy.id); $e.SetAttribute('out', (ConvertTo-KdpTime $d ($inF + $outLen - 1)))
    try { Set-KdpEntryAt $d $t $e $c.StartFrames $outLen } catch { throw "The remapped clip needs $([math]::Round($outLen / $d.Fps,3)) s and runs into the next clip: $($_.Exception.Message)" }
}

# ---------- proxies ----------
function Set-KdpProxy([KdpDoc]$d, [bool]$on) {
    $mb = $d.Xml.mlt.SelectSingleNode("playlist[@id='main_bin']")
    Set-KdpProp $mb 'kdenlive:docproperties.enableproxy' $(if ($on) { 1 } else { 0 })
    Set-KdpProp $mb 'kdenlive:docproperties.generateproxy' $(if ($on) { 1 } else { 0 })
}

# ---------- render presets (Kdenlive's export\profiles.xml + MLT presets) ----------
function Get-KdpRenderPresets {
    $x = New-Object System.Xml.XmlDocument; $x.XmlResolver = $null; $x.Load((Join-Path $script:KdpData 'export\profiles.xml'))
    $list = foreach ($g in $x.SelectNodes('//group')) { foreach ($p in $g.SelectNodes('profile')) { [pscustomobject]@{ Name = $p.GetAttribute('name'); Group = $g.GetAttribute('name'); Ext = $p.GetAttribute('extension'); Args = $p.GetAttribute('args'); Quality = $p.GetAttribute('defaultquality'); AudioQuality = $p.GetAttribute('defaultaudioquality'); AudioBitrate = $p.GetAttribute('defaultaudiobitrate'); Bitrate = $p.GetAttribute('defaultbitrate'); Speeds = $p.GetAttribute('speeds'); SpeedIndex = $p.GetAttribute('defaultspeedindex') } } }
    $mltPresets = Join-Path (Split-Path $script:KdpBin -Parent) 'share\mlt\presets\consumer\avformat'
    foreach ($sub in 'ten_bit', 'lossless', 'stills') { foreach ($f in Get-ChildItem (Join-Path $mltPresets $sub) -File -ErrorAction SilentlyContinue) { $ext = ((Get-Content $f.FullName | Where-Object { $_ -like 'meta.preset.extension=*' }) -replace 'meta.preset.extension='); $list += [pscustomobject]@{ Name = $f.Name; Group = $sub; Ext = $ext; Args = "properties=`"$sub/$($f.Name)`""; Quality = ''; AudioQuality = ''; AudioBitrate = ''; Bitrate = ''; Speeds = ''; SpeedIndex = '' } } }
    $list += [pscustomobject]@{ Name = 'GIF'; Group = 'image'; Ext = 'gif'; Args = 'properties=GIF'; Quality = ''; AudioQuality = ''; AudioBitrate = ''; Bitrate = ''; Speeds = ''; SpeedIndex = '' }
    return $list
}
function Expand-KdpPresetArgs($p, $quality = $null) {
    $a = $p.Args
    $q = if ($null -ne $quality) { $quality } else { $p.Quality }
    $a = $a.Replace('%quality', "$q").Replace('%audioquality', "$($p.AudioQuality)").Replace("%audiobitrate+'k'", "$($p.AudioBitrate)k").Replace('%audiobitrate', "$($p.AudioBitrate)").Replace("%bitrate+'k'", "$($p.Bitrate)k").Replace('%bitrate', "$($p.Bitrate)")
    if ($p.Speeds) {
        $sp = $p.Speeds.Split(';'); $idx = if ($p.SpeedIndex) { [int]$p.SpeedIndex } else { [int][math]::Floor(($sp.Count - 1) * 0.75) }
        foreach ($kv in ($sp[$idx] -split '\s+')) { $k = $kv.Split('=')[0]; if ($a -notmatch "(^|\s)$([regex]::Escape($k))=") { $a += " $kv" } }
    }
    if ($a -match '%') { throw "Preset '$($p.Name)' uses placeholders this tool does not expand: $a" }
    return $a
}
# Runs a bundled tool; throws with its error text when it fails.
function Invoke-KdpTool([string]$exe, [string]$arguments, [string]$what) {
    $err = [IO.Path]::GetTempFileName(); $std = [IO.Path]::GetTempFileName()
    try {
        $p = Start-Process -FilePath (Join-Path $script:KdpBin $exe) -ArgumentList $arguments -NoNewWindow -Wait -PassThru -RedirectStandardError $err -RedirectStandardOutput $std
        $text = [IO.File]::ReadAllText($err)
        if ($p.ExitCode -ne 0) { throw "$what failed (exit $($p.ExitCode)): $text" }
        return $text
    } finally { Remove-Item $err, $std -Force -ErrorAction SilentlyContinue }
}
# Outputs are written next to the target under a temporary name: an older file can never pass for a fresh render.
function Get-KdpPartPath([string]$out) { Join-Path (Split-Path ([IO.Path]::GetFullPath($out)) -Parent) ('.part-' + [guid]::NewGuid().ToString('N') + [IO.Path]::GetExtension($out)) }
function Complete-KdpPart([string]$part, [string]$out, [string]$what, [string]$log) {
    if (-not (Test-Path -LiteralPath $part) -or (Get-Item -LiteralPath $part -Force).Length -eq 0) { throw "$what produced no output: $log" }
    Move-KdpFileInto $part ([IO.Path]::GetFullPath($out))
}
function Get-KdpMeltZone([KdpDoc]$d, $from, $to) {
    if ($null -eq $from) { return '' }
    if ($null -eq $to) { throw '-From needs -ToTime' }
    "in=$(SecToFrames $d ([double]$from)) out=$((SecToFrames $d ([double]$to)) - 1) "
}
function Export-KdpPreset([KdpDoc]$d, [string]$preset, [string]$out, $quality = $null, $from = $null, $to = $null) {
    $p = Get-KdpRenderPresets | Where-Object { $_.Name -eq $preset } | Select-Object -First 1
    if (-not $p) { throw "Unknown preset '$preset'. See: kdp.ps1 presets" }
    $a = Expand-KdpPresetArgs $p $quality
    $zone = Get-KdpMeltZone $d $from $to
    $out = [IO.Path]::GetFullPath($out)
    $isSeries = $p.Ext -eq 'png'
    if ($isSeries -and $out -notmatch '%0\dd') { $out = [IO.Path]::Combine([IO.Path]::GetDirectoryName($out), [IO.Path]::GetFileNameWithoutExtension($out) + '-%04d.png') }
    $target = if ($isSeries) { $out } else { Get-KdpPartPath $out }
    $src = New-KdpMeltCopy $d
    $began = (Get-Date).AddSeconds(-2)
    try {
        $log = Invoke-KdpTool 'melt.exe' "`"$src`" $zone-silent -consumer avformat:`"$target`" rescale=bilinear deinterlacer=onefield $a" "Render with preset '$preset'"
        if ($isSeries) {
            if (-not (Get-ChildItem (Split-Path $out -Parent) -Filter '*.png' | Where-Object { $_.LastWriteTime -ge $began })) { throw "Render with preset '$preset' produced no images: $log" }
        } else { Complete-KdpPart $target $out "Render with preset '$preset'" $log }
    } finally {
        Remove-Item $src -Force -ErrorAction SilentlyContinue
        if (-not $isSeries) { Remove-Item -LiteralPath $target -Force -ErrorAction SilentlyContinue }
    }
    return $out
}

# ---------- preview / render with melt (headless) ----------
function Export-KdpFrame([KdpDoc]$d, [double]$at, [string]$png, [int]$width = 0) {
    $f = SecToFrames $d $at
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ("kdp-frame-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force $tmp | Out-Null
    $src = New-KdpMeltCopy $d
    try {
        $log = Invoke-KdpTool 'melt.exe' "`"$src`" in=$f out=$f -silent -consumer avformat:`"$tmp\f-%05d.png`" vcodec=png" 'Frame render'
        $img = Get-ChildItem $tmp -Filter 'f-*.png' | Select-Object -First 1
        if (-not $img) { throw "melt produced no frame: $log" }
        $dir = Split-Path ([IO.Path]::GetFullPath($png)) -Parent
        if ($dir) { [void][IO.Directory]::CreateDirectory($dir) }
        if ($width -gt 0) { [void](Invoke-KdpTool 'ffmpeg.exe' "-v error -y -i `"$($img.FullName)`" -vf scale=${width}:-2 `"$([IO.Path]::GetFullPath($png))`"" 'Frame resize') }
        else { Copy-Item $img.FullName $png -Force }
    } finally { Remove-Item $src -Force -ErrorAction SilentlyContinue; Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue }
    return $png
}
function Export-KdpMelt([KdpDoc]$d, [string]$out, $from = $null, $to = $null, [string]$codec = 'crf=23 g=15 preset=veryfast acodec=aac ab=160k') {
    $zone = Get-KdpMeltZone $d $from $to
    New-Item -ItemType Directory -Force (Split-Path ([IO.Path]::GetFullPath($out)) -Parent) | Out-Null
    $part = Get-KdpPartPath $out
    $src = New-KdpMeltCopy $d
    try {
        $log = Invoke-KdpTool 'melt.exe' "`"$src`" $zone-silent -consumer avformat:`"$part`" f=mp4 movflags=+faststart vcodec=libx264 $codec" 'melt render'
        Complete-KdpPart $part $out 'melt render' $log
    } finally { Remove-Item $src, $part -Force -ErrorAction SilentlyContinue }
    return $out
}

# ---------- validation (mirrors Kdenlive's DocumentChecker rules that open modal dialogs) ----------
function Test-KdpProject([KdpDoc]$d) {
    $problems = New-Object System.Collections.ArrayList
    $mb = $d.Xml.mlt.SelectSingleNode("playlist[@id='main_bin']")
    if (-not $mb) { [void]$problems.Add('no main_bin playlist'); return $problems }
    if ((Get-KdpProp $mb 'xml_retain') -ne '1') { [void]$problems.Add('main_bin lacks xml_retain=1 (no bin clip would load)') }
    if ((Get-KdpProp $mb 'kdenlive:docproperties.version') -ne '1.1') { [void]$problems.Add('document version is not 1.1 (upgrade dialog on first save)') }
    if ((Get-KdpProp $mb 'kdenlive:docproperties.patchversion') -ne '1') { [void]$problems.Add('patchversion is not 1 (upgrade dialog on first save)') }
    if ((Get-KdpProp $mb 'kdenlive:docproperties.documentid') -notmatch '^\d+$') { [void]$problems.Add('documentid is not numeric') }
    $binUuids = @{}
    foreach ($bc in Get-KdpBinClips $d) {
        $u = Get-KdpProp $bc.Node 'kdenlive:control_uuid'
        if (-not $u) { [void]$problems.Add("bin clip $($bc.BinId) '$($bc.Name)' has no control_uuid") } else { $binUuids[$u] = $bc }
        $svc = Get-KdpProp $bc.Node 'mlt_service'
        if ($svc -like 'avformat*' -or $svc -in 'qimage', 'pixbuf', 'glaxnimate') {
            $res = $bc.Resource; $full = if ([IO.Path]::IsPathRooted($res)) { $res } else { Join-Path ($d.Root -replace '/', '\') $res }
            if ($res -match '%|[\\/]\.all\.') { if (-not (Test-Path (Split-Path $full -Parent))) { [void]$problems.Add("missing slideshow folder for '$($bc.Name)': $(Split-Path $full -Parent)") }; continue }
            if (-not (Test-Path $full)) { [void]$problems.Add("missing media for '$($bc.Name)': $full") }
            else {
                $h = Get-KdpProp $bc.Node 'kdenlive:file_hash'
                if ($h -and $res -notmatch '%' -and (Get-KdpFileHash $full) -ne $h) { [void]$problems.Add("file_hash mismatch for '$($bc.Name)' (Kdenlive asks to reload)") }
            }
        }
        if ($svc -eq 'kdenlivetitle') {
            $fonts = [regex]::Matches((Get-KdpProp $bc.Node 'xmldata'), 'font="([^"]+)"') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique
            foreach ($fn in $fonts) { if (-not (Test-KdpFont $fn)) { [void]$problems.Add("title '$($bc.Name)' uses font '$fn' that is not installed") } }
        }
    }
    $effIds = @{}; foreach ($e in Get-KdpEffectCatalog) { $effIds[$e.Id] = 1 }
    $trIds = @{}; foreach ($e in Get-KdpTransitionCatalog) { $trIds[$e.Id] = 1 }
    $savedSeq = $d.SeqId
    foreach ($sq in @(Get-KdpSequences $d)) {
    $d.SeqId = $sq.Uuid
    $ku = Get-KdpProp $sq.Node 'kdenlive:uuid'
    if (-not $ku -or (Get-KdpProp $sq.Node 'kdenlive:control_uuid') -ne $ku) { [void]$problems.Add("sequence '$($sq.Name)' needs kdenlive:control_uuid equal to its kdenlive:uuid") }
    foreach ($t in Get-KdpTracks $d) {
        foreach ($pl in $t.Playlists) {
            foreach ($e in $pl.SelectNodes('entry')) {
                $p = $d.Xml.mlt.SelectSingleNode("*[@id='$($e.producer)']")
                if (-not $p) { [void]$problems.Add("$($t.Name): entry references missing producer $($e.producer)"); continue }
                $u = Get-KdpProp $p 'kdenlive:control_uuid'
                if (-not $u -or -not $binUuids.ContainsKey($u)) { [void]$problems.Add("$($t.Name): clip producer $($p.id) has no matching bin control_uuid (Kdenlive would drop it)") }
                foreach ($f in $e.SelectNodes('filter')) { $k = Get-KdpProp $f 'kdenlive_id'; if (-not $k) { [void]$problems.Add("$($t.Name): clip effect without kdenlive_id is ignored") } elseif (-not $effIds.ContainsKey($k)) { [void]$problems.Add("$($t.Name): unknown effect id '$k'") } }
            }
        }
        if (@($t.Playlists[1].SelectNodes('entry')).Count -and -not $t.Tractor.SelectSingleNode("transition[property[@name='kdenlive:mixcut']]")) { [void]$problems.Add("$($t.Name): clip on the second playlist without a mix (repair dialog)") }
        foreach ($f in $t.Tractor.SelectNodes('filter')) { if (-not (Get-KdpProp $f 'internal_added')) { $k = Get-KdpProp $f 'kdenlive_id'; if ($k -and -not $effIds.ContainsKey($k)) { [void]$problems.Add("$($t.Name): unknown track effect '$k'") } } }
    }
    $seq = Get-KdpSequence $d
    foreach ($tr in $seq.SelectNodes('transition')) { if (-not (Get-KdpProp $tr 'internal_added')) { $k = Get-KdpProp $tr 'kdenlive_id'; if (-not $trIds.ContainsKey($k)) { [void]$problems.Add("unknown composition id '$k'") } } }
    foreach ($f in $seq.SelectNodes('filter')) { if (-not (Get-KdpProp $f 'internal_added')) { $k = Get-KdpProp $f 'kdenlive_id'; if ($k -and -not $effIds.ContainsKey($k)) { [void]$problems.Add("unknown master effect '$k'") } } }
    }
    $d.SeqId = $savedSeq
    return $problems
}
