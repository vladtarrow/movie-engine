# kdp-ops2.ps1 - the rest of Kdenlive's project-changing operations (menu by menu, see
# docs/kdenlive-coverage.md): history (undo/redo), clipboard-like copies, bin clip management,
# generators, templates, playlist clips, space handling, slip/ripple, markers/guides management,
# subtitle import/export, zones, profile changes, archive, OTIO export/import.
# Dot-source after kdp-core.ps1 and kdp-ops.ps1.

# ---------- history: undo / redo (snapshots next to the project) ----------
function Get-KdpHistoryDir([string]$project, [string]$kind = 'undo') { Join-Path (Split-Path $project -Parent) ".kdp-history\$([IO.Path]::GetFileNameWithoutExtension($project))\$kind" }
# Subtitle files are part of the state: they are written while the edit runs, before the project is saved.
function Get-KdpAssState([string]$project) {
    $state = @{}
    $base = [IO.Path]::GetFileName($project)
    foreach ($f in Get-ChildItem -LiteralPath (Split-Path $project -Parent) -File -Filter '*.ass') {
        if ($f.Name -match ('^' + [regex]::Escape($base) + '(\{[0-9a-fA-F-]+\})?\.ass$')) { $state[$f.Name] = [IO.File]::ReadAllBytes($f.FullName) }
    }
    return $state
}
function Set-KdpAssState([string]$project, [hashtable]$state) {
    $dir = Split-Path $project -Parent
    foreach ($name in @((Get-KdpAssState $project).Keys)) { if (-not $state.ContainsKey($name)) { [IO.File]::Delete((Join-Path $dir $name)) } }
    foreach ($name in $state.Keys) { [IO.File]::WriteAllBytes((Join-Path $dir $name), $state[$name]) }
}
function New-KdpSnapshot([string]$project, [string]$dir, [hashtable]$ass) {
    [void][IO.Directory]::CreateDirectory($dir)
    do { $stamp = (Get-Date).ToString('yyyyMMdd-HHmmss-fff'); $file = Join-Path $dir "$stamp.kdenlive"; if (Test-Path $file) { Start-Sleep -Milliseconds 3 } } while (Test-Path $file)
    Copy-Item -LiteralPath $project $file
    $sub = "$file.subs"; [void][IO.Directory]::CreateDirectory($sub)
    foreach ($name in $ass.Keys) { [IO.File]::WriteAllBytes((Join-Path $sub $name), $ass[$name]) }
}
function Remove-KdpSnapshot($file) { Remove-Item -LiteralPath $file.FullName -Force; if (Test-Path -LiteralPath "$($file.FullName).subs") { Remove-Item -LiteralPath "$($file.FullName).subs" -Recurse -Force } }
function Save-KdpSnapshot([string]$project, $assBefore = $null) {
    if ($null -eq $assBefore) { $assBefore = Get-KdpAssState $project }
    $dir = Get-KdpHistoryDir $project 'undo'
    New-KdpSnapshot $project $dir $assBefore
    foreach ($old in @(Get-ChildItem $dir -File -Filter *.kdenlive | Sort-Object Name -Descending | Select-Object -Skip 100)) { Remove-KdpSnapshot $old }
    $redo = Get-KdpHistoryDir $project 'redo'
    if (Test-Path $redo) { foreach ($old in @(Get-ChildItem $redo -File -Filter *.kdenlive)) { Remove-KdpSnapshot $old } }
}
function Undo-KdpProject([string]$project, [switch]$Redo) {
    $from = Get-KdpHistoryDir $project $(if ($Redo) { 'redo' } else { 'undo' })
    $to = Get-KdpHistoryDir $project $(if ($Redo) { 'undo' } else { 'redo' })
    $snap = Get-ChildItem $from -File -Filter *.kdenlive -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1
    if (-not $snap) { throw "Nothing to $(if ($Redo) { 'redo' } else { 'undo' })." }
    New-KdpSnapshot $project $to (Get-KdpAssState $project)
    $subs = "$($snap.FullName).subs"
    if (Test-Path -LiteralPath $subs) {     # snapshots older than 2026-11-22 have no subtitle state
        $state = @{}; foreach ($f in Get-ChildItem -LiteralPath $subs -File) { $state[$f.Name] = [IO.File]::ReadAllBytes($f.FullName) }
        Set-KdpAssState $project $state
    }
    Copy-Item -LiteralPath $snap.FullName "$project.kdp-tmp" -Force
    Set-KdWriteStamp $project (Get-KdHash "$project.kdp-tmp")
    Move-KdpFileInto "$project.kdp-tmp" $project
    Remove-KdpSnapshot $snap
}
function Clear-KdpHistory([string]$project) {
    foreach ($kind in 'undo', 'redo') {
        $dir = Get-KdpHistoryDir $project $kind
        if (Test-Path $dir) { foreach ($old in @(Get-ChildItem $dir -File -Filter *.kdenlive)) { Remove-KdpSnapshot $old } }
    }
}

# ---------- linked audio+video and groups after an edit ----------
# Kdenlive stores group members as "track:startFrame", so every move would orphan them. Remember the clip nodes
# before an edit and write their new positions afterwards.
function Get-KdpGroupAnchors([KdpDoc]$d) {
    $anchors = @{}
    $saved = $d.SeqId
    foreach ($sq in @(Get-KdpSequences $d)) {
        $d.SeqId = $sq.Uuid
        $groups = @(Get-KdpJsonArray (Get-KdpProp $sq.Node 'kdenlive:sequenceproperties.groups'))
        if (-not $groups.Count) { continue }
        $index = @{}; foreach ($t in Get-KdpTracks $d) { $index[$t.Name] = $t.Index - 1 }
        $map = @{}
        foreach ($c in Get-KdpClips $d) { $key = "$($index[$c.Track]):$($c.StartFrames)"; if (-not $map.ContainsKey($key)) { $map[$key] = $c.Node } }
        $anchors[$sq.Uuid] = @{ Groups = $groups; Nodes = $map }
    }
    $d.SeqId = $saved
    return $anchors
}
function ConvertTo-KdpMovedGroup($group, $oldNodes, $newPos) {
    if ($group.PSObject.Properties['children']) {
        $kids = @(foreach ($child in $group.children) { ConvertTo-KdpMovedGroup $child $oldNodes $newPos })
        if ($kids.Count -ge 2) { [pscustomobject]@{ children = $kids; type = $group.type } } elseif ($kids.Count -eq 1 -and $kids[0].PSObject.Properties['children']) { $kids[0] }
        return
    }
    if ($group.leaf -ne 'clip') { $group; return }      # composition / subtitle members are addressed differently
    $part = "$($group.data)".Split(':'); $key = "$($part[0]):$($part[1])"
    if (-not $oldNodes.ContainsKey($key)) { return }    # already orphaned
    $node = $oldNodes[$key]
    foreach ($p in $newPos) {
        if ([object]::ReferenceEquals($p.Node, $node)) {
            $tail = if ($part.Count -gt 2) { ":$($part[2])" } else { '' }
            [pscustomobject]@{ data = "$($p.Track):$($p.Start)$tail"; leaf = 'clip'; type = 'Leaf' }
            return
        }
    }
}
function Update-KdpGroupPositions([KdpDoc]$d, [hashtable]$anchors, $added = @()) {
    $saved = $d.SeqId
    foreach ($uuid in $anchors.Keys) {
        $d.SeqId = $uuid
        $index = @{}; foreach ($t in Get-KdpTracks $d) { $index[$t.Name] = $t.Index - 1 }
        $pos = @(foreach ($c in Get-KdpClips $d) { @{ Node = $c.Node; Track = $index[$c.Track]; Start = $c.StartFrames } })
        $moved = @(foreach ($g in $anchors[$uuid].Groups) { ConvertTo-KdpMovedGroup $g $anchors[$uuid].Nodes $pos })
        Set-KdpProp (Get-KdpSequence $d) 'kdenlive:sequenceproperties.groups' (ConvertTo-KdpJson $moved)
    }
    $d.SeqId = $saved
}
# The other half of a linked pair at this position, as track + a time inside it.
function Get-KdpPartnerRef([KdpDoc]$d, [string]$track, [double]$at) {
    $c = Find-KdpClip $d $track $at
    $p = Get-KdpLinkedPartner $d $track $c.StartFrames
    if (-not $p) { return }
    [pscustomobject]@{ Track = $p.Track; At = ($p.StartFrames + 0.5) / $d.Fps; StartFrames = $p.StartFrames; Offset = ($p.StartFrames - $c.StartFrames) / $d.Fps; InFrames = (ConvertTo-KdpFrames $d (Find-KdpClip $d $p.Track (($p.StartFrames + 0.5) / $d.Fps)).Node.in) - (ConvertTo-KdpFrames $d $c.Node.in) }
}

# ---------- copy / duplicate on the timeline ----------
function Copy-KdpClip([KdpDoc]$d, [string]$track, [double]$at, [string]$toTrack, [double]$to, [switch]$Overwrite, [switch]$Insert) {
    $c = Find-KdpClip $d $track $at
    if (-not $toTrack) { $toTrack = $track }
    $src = Get-KdpTrack $d $track; $dst = Get-KdpTrack $d $toTrack
    if ($src.Audio -ne $dst.Audio) { throw 'Copy between audio and video tracks is not possible; use add-av for the other half.' }
    $e = $c.Node.Clone()
    foreach ($f in $e.SelectNodes('filter')) { $f.SetAttribute('id', (New-KdpId $d 'filter')) }
    $prod = $d.Xml.mlt.SelectSingleNode("*[@id='$($c.Node.producer)']")
    if ($prod.Name -eq 'chain' -or (Get-KdpProp $prod 'mlt_service') -in 'timewarp' -or (Get-KdpProp $prod 'mlt_service') -like 'avformat*') {
        $pc = $prod.Clone(); $pc.SetAttribute('id', (New-KdpId $d $(if ($prod.Name -eq 'chain') { 'chain' } else { 'producer' })))
        foreach ($l in $pc.SelectNodes('link')) { $l.SetAttribute('id', (New-KdpId $d 'link')) }
        [void]$d.Xml.mlt.InsertBefore($pc, $dst.Playlists[0]); $e.SetAttribute('producer', $pc.id)
    }
    Set-KdpEntryAt $d $dst $e (SecToFrames $d $to) $c.LenFrames -Overwrite:$Overwrite -Insert:$Insert
}
# Copy effects of one clip onto another (Kdenlive "paste effects"); fades keep their length.
function Copy-KdpEffects([KdpDoc]$d, [string]$track, [double]$at, [string]$toTrack, [double]$to, [switch]$Replace) {
    $a = Find-KdpClip $d $track $at; $b = Find-KdpClip $d $toTrack $to
    $ta = Get-KdpTrack $d $track; $tb = Get-KdpTrack $d $toTrack
    if ($ta.Audio -ne $tb.Audio) { throw 'Effects can only be pasted between clips of the same kind (audio/video).' }
    if ($Replace) { foreach ($f in @($b.Node.SelectNodes('filter'))) { [void]$b.Node.RemoveChild($f) } }
    $aIn = ConvertTo-KdpFrames $d $a.Node.in; $aOut = ConvertTo-KdpFrames $d $a.Node.out
    $bIn = ConvertTo-KdpFrames $d $b.Node.in; $bOut = ConvertTo-KdpFrames $d $b.Node.out
    foreach ($f in $a.Node.SelectNodes('filter')) {
        $id = Get-KdpProp $f 'kdenlive_id'
        foreach ($old in @($b.Node.SelectNodes('filter'))) { if ((Get-KdpProp $old 'kdenlive_id') -eq $id) { $def = Get-KdpEffectCatalog | Where-Object Id -eq $id; if ($def -and $def.Unique) { [void]$b.Node.RemoveChild($old) } } }
        $n = $f.Clone(); $n.SetAttribute('id', (New-KdpId $d 'filter'))
        if ($f.HasAttribute('in') -and $f.HasAttribute('out')) {
            $fi = ConvertTo-KdpFrames $d $f.in; $fo = ConvertTo-KdpFrames $d $f.out
            if ($fo -ge $aOut) { $len = $fo - $fi; $n.SetAttribute('out', (ConvertTo-KdpTime $d $bOut)); $n.SetAttribute('in', (ConvertTo-KdpTime $d ([math]::Max($bIn, $bOut - $len)))) }
            else { $n.SetAttribute('in', (ConvertTo-KdpTime $d ($bIn + $fi - $aIn))); $n.SetAttribute('out', (ConvertTo-KdpTime $d ([math]::Min($bOut, $bIn + $fo - $aIn)))) }
        }
        [void]$b.Node.AppendChild($n)
    }
}
function Clear-KdpEffects([KdpDoc]$d, [string]$track, $at, [switch]$Master) {
    $h = Get-KdpEffectHost $d $track $at -Master:$Master
    foreach ($f in @($h.Node.SelectNodes('filter'))) { if (-not (Get-KdpProp $f 'internal_added')) { [void]$h.Node.RemoveChild($f) } }
}
# Bin clip effects apply to every use of the clip.
function Add-KdpBinEffect([KdpDoc]$d, [string]$bin, [string]$id, [hashtable]$values = @{}) {
    $bc = Get-KdpBinClip $d $bin; $def = Get-KdpEffectDef $id
    $n = New-KdpAssetNode $d 'filter' $def $values @{ Fade = (SecToFrames $d 1); In = 0; Out = 0 }
    [void]$bc.Node.AppendChild($n)
}
# Kdenlive's "disable timeline effects": switch every user effect of the sequence off/on.
function Set-KdpAllEffects([KdpDoc]$d, [bool]$enabled) {
    $seq = Get-KdpSequence $d
    $hosts = @($seq) + @(Get-KdpTracks $d | ForEach-Object { $_.Tractor }) + @(Get-KdpClips $d | ForEach-Object { $_.Node })
    foreach ($h in $hosts) { foreach ($f in $h.SelectNodes('filter')) { if ((Get-KdpProp $f 'kdenlive_id') -and -not (Get-KdpProp $f 'internal_added')) { Set-KdpProp $f 'disable' $(if ($enabled) { 0 } else { 1 }) } } }
}

# ---------- groups ----------
function Remove-KdpGroup([KdpDoc]$d, [string]$track, [double]$at) {
    $c = Find-KdpClip $d $track $at; $t = Get-KdpTrack $d $track
    $me = "$($t.Index - 1):$($c.StartFrames)"
    $seq = Get-KdpSequence $d
    $g = @(Get-KdpJsonArray (Get-KdpProp $seq 'kdenlive:sequenceproperties.groups') | Where-Object { -not (@($_.children | ForEach-Object { $_.data }) | Where-Object { $_ -eq $me -or $_ -like "${me}:*" }) })
    Set-KdpProp $seq 'kdenlive:sequenceproperties.groups' (ConvertTo-KdpJson $g)
}

# ---------- spaces ----------
function Add-KdpSpace([KdpDoc]$d, [double]$at, [double]$dur, [string[]]$tracks) {
    if (-not $tracks) { $tracks = Get-KdpTracks $d | ForEach-Object Name }
    $posF = SecToFrames $d $at; $lenF = SecToFrames $d $dur
    foreach ($tn in $tracks) {
        $t = Get-KdpTrack $d $tn
        if (Get-KdpClips $d | Where-Object { $_.Track -eq $t.Name -and $posF -gt $_.StartFrames -and $posF -lt $_.StartFrames + $_.LenFrames }) { throw "Space insert point $at s cuts through a clip on $($t.Name); split it first." }
        foreach ($pl in $t.Playlists) {
            $items = Read-KdpItems $d $pl; $res = New-Object System.Collections.ArrayList; $pos = 0; $done = $false
            foreach ($it in $items) {
                if (-not $done -and $pos + $it.Len -gt $posF) {
                    if ($it.Kind -eq 'blank') { [void]$res.Add(@{ Kind = 'blank'; Len = $it.Len + $lenF; Node = $null }) } else { [void]$res.Add(@{ Kind = 'blank'; Len = $lenF; Node = $null }); [void]$res.Add($it) }
                    $done = $true
                } else { [void]$res.Add($it) }
                $pos += $it.Len
            }
            Write-KdpItems $d $pl $res
        }
        foreach ($tr in $t.Tractor.SelectNodes("transition[property[@name='kdenlive:mixcut']]")) { $i = ConvertTo-KdpFrames $d $tr.in; if ($i -ge $posF) { $tr.SetAttribute('in', (ConvertTo-KdpTime $d ($i + $lenF))); $tr.SetAttribute('out', (ConvertTo-KdpTime $d ((ConvertTo-KdpFrames $d $tr.out) + $lenF))) } }
    }
}
# Remove the gap at $at (whole gap, or $dur seconds of it). -AllTracks: only where every track is free.
function Remove-KdpSpace([KdpDoc]$d, [double]$at, [double]$dur = -1, [string[]]$tracks) {
    if (-not $tracks) { $tracks = Get-KdpTracks $d | ForEach-Object Name }
    $posF = SecToFrames $d $at
    $plan = @()
    foreach ($tn in $tracks) {
        $t = Get-KdpTrack $d $tn; $pl = $t.Playlists[0]; $pos = 0
        foreach ($it in (Read-KdpItems $d $pl)) {
            if ($posF -ge $pos -and $posF -lt $pos + $it.Len) {
                if ($it.Kind -ne 'blank') { throw "There is a clip on $($t.Name) at $at s, not a gap." }
                $plan += @{ T = $t; Start = $pos; Len = $it.Len }; break
            }
            $pos += $it.Len
        }
    }
    if (-not $plan) { return }
    $maxRemovable = ($plan | ForEach-Object { $_.Len - ($posF - $_.Start) } | Measure-Object -Minimum).Minimum
    $start = ($plan | ForEach-Object Start | Measure-Object -Maximum).Maximum
    $lenF = if ($dur -gt 0) { SecToFrames $d $dur } else { ($plan | ForEach-Object { $_.Start + $_.Len } | Measure-Object -Minimum).Minimum - $start }
    if ($lenF -gt ($plan | ForEach-Object { $_.Start + $_.Len } | Measure-Object -Minimum).Minimum - $start) { throw 'The gap is shorter than requested on at least one track.' }
    foreach ($p in $plan) {
        foreach ($pl in $p.T.Playlists) {
            $items = Read-KdpItems $d $pl; $res = New-Object System.Collections.ArrayList; $pos = 0; $todo = $lenF
            foreach ($it in $items) {
                if ($todo -gt 0 -and $it.Kind -eq 'blank' -and $pos + $it.Len -gt $start -and $pos -le $start) { $cut = [math]::Min($todo, $pos + $it.Len - $start); [void]$res.Add(@{ Kind = 'blank'; Len = $it.Len - $cut; Node = $null }); $todo -= $cut }
                else { [void]$res.Add($it) }
                $pos += $it.Len
            }
            Write-KdpItems $d $pl $res
        }
        foreach ($tr in $p.T.Tractor.SelectNodes("transition[property[@name='kdenlive:mixcut']]")) { $i = ConvertTo-KdpFrames $d $tr.in; if ($i -gt $start) { $tr.SetAttribute('in', (ConvertTo-KdpTime $d ($i - $lenF))); $tr.SetAttribute('out', (ConvertTo-KdpTime $d ((ConvertTo-KdpFrames $d $tr.out) - $lenF))) } }
    }
}
function Remove-KdpAllSpaces([KdpDoc]$d, [string]$track) {
    $t = Get-KdpTrack $d $track
    if ($t.Tractor.SelectSingleNode("transition[property[@name='kdenlive:mixcut']]")) { throw 'Remove the crossfades on this track first.' }
    $items = Read-KdpItems $d $t.Playlists[0]
    $res = New-Object System.Collections.ArrayList; foreach ($it in $items) { if ($it.Kind -eq 'entry') { [void]$res.Add($it) } }
    Write-KdpItems $d $t.Playlists[0] $res
}
function Clear-KdpTrack([KdpDoc]$d, [string]$track) {
    $t = Get-KdpTrack $d $track
    foreach ($tr in @($t.Tractor.SelectNodes("transition[property[@name='kdenlive:mixcut']]"))) { [void]$t.Tractor.RemoveChild($tr) }
    foreach ($pl in $t.Playlists) { Write-KdpItems $d $pl (New-Object System.Collections.ArrayList) }
}

# ---------- slip and ripple trim ----------
# Slip: show a different part of the source without moving or resizing the clip.
function Invoke-KdpSlip([KdpDoc]$d, [string]$track, [double]$at, [double]$by) {
    $c = Find-KdpClip $d $track $at; Assert-KdpNotMixed $d $c
    $e = $c.Node; $prod = $d.Xml.mlt.SelectSingleNode("*[@id='$($e.producer)']")
    $dF = SecToFrames $d $by
    $in = (ConvertTo-KdpFrames $d $e.in) + $dF; $out = (ConvertTo-KdpFrames $d $e.out) + $dF
    $lp = Get-KdpProp $prod 'length'; if (-not $lp) { $lp = Get-KdpProp $prod 'kdenlive:maxduration' }; $len = ConvertTo-KdpFrames $d $lp
    if ($in -lt 0 -or (-not (Test-KdpEndless $prod) -and $out -ge $len)) { throw "Slip by $by s goes outside the source (0..$([math]::Round($len / $d.Fps,3)) s)." }
    $e.SetAttribute('in', (ConvertTo-KdpTime $d $in)); $e.SetAttribute('out', (ConvertTo-KdpTime $d $out))
    foreach ($f in $e.SelectNodes('filter')) { if ($f.HasAttribute('in')) { $f.SetAttribute('in', (ConvertTo-KdpTime $d ((ConvertTo-KdpFrames $d $f.in) + $dF))); $f.SetAttribute('out', (ConvertTo-KdpTime $d ((ConvertTo-KdpFrames $d $f.out) + $dF))) } }
}
# Ripple trim: change the clip's in/out; everything after it on the same track moves with it.
function Invoke-KdpRippleTrim([KdpDoc]$d, [string]$track, [double]$at, $newIn, $newDur) {
    $c = Find-KdpClip $d $track $at; Assert-KdpNotMixed $d $c
    $t = Get-KdpTrack $d $track
    if ($t.Tractor.SelectSingleNode("transition[property[@name='kdenlive:mixcut']]")) { throw 'Ripple trim on a track with crossfades is not supported; unmix first.' }
    $e = $c.Node; $prod = $d.Xml.mlt.SelectSingleNode("*[@id='$($e.producer)']")
    $in = ConvertTo-KdpFrames $d $e.in; $len = $c.LenFrames
    if ($null -ne $newIn) { $ni = SecToFrames $d ([double]$newIn); $len -= ($ni - $in); $in = $ni }
    if ($null -ne $newDur) { $len = SecToFrames $d ([double]$newDur) }
    $lp = Get-KdpProp $prod 'length'; if (-not $lp) { $lp = Get-KdpProp $prod 'kdenlive:maxduration' }
    if ($in -lt 0 -or $len -lt 1 -or (-not (Test-KdpEndless $prod) -and $in + $len -gt (ConvertTo-KdpFrames $d $lp))) { throw 'Ripple trim goes outside the source.' }
    $e.SetAttribute('in', (ConvertTo-KdpTime $d $in)); $e.SetAttribute('out', (ConvertTo-KdpTime $d ($in + $len - 1)))
    # playlist positions are implicit, so later items shift by themselves
}

# ---------- markers, guides, categories ----------
function Set-KdpClipMarker([KdpDoc]$d, [string]$bin, [double]$at, [string]$comment, $category = $null, $newAt = $null) {
    $bc = Get-KdpBinClip $d $bin; $f = SecToFrames $d $at
    $m = @(Get-KdpJsonArray (Get-KdpProp $bc.Node 'kdenlive:markers') | Where-Object { $_.PSObject.Properties['pos'] })
    $x = $m | Where-Object pos -eq $f | Select-Object -First 1; if (-not $x) { throw "No marker at $at s in '$($bc.Name)'" }
    if ($comment) { $x.comment = $comment }; if ($null -ne $category) { $x.type = [int]$category }; if ($null -ne $newAt) { $x.pos = SecToFrames $d ([double]$newAt) }
    Set-KdpProp $bc.Node 'kdenlive:markers' (ConvertTo-KdpJson ($m | Sort-Object pos))
}
function Remove-KdpClipMarker([KdpDoc]$d, [string]$bin, $at = $null) {
    $bc = Get-KdpBinClip $d $bin
    if ($null -eq $at) { Set-KdpProp $bc.Node 'kdenlive:markers' "[`n]`n"; return }
    $f = SecToFrames $d ([double]$at)
    $m = @(Get-KdpJsonArray (Get-KdpProp $bc.Node 'kdenlive:markers') | Where-Object { $_.PSObject.Properties['pos'] -and $_.pos -ne $f })
    Set-KdpProp $bc.Node 'kdenlive:markers' (ConvertTo-KdpJson $m)
}
function Get-KdpClipMarkers([KdpDoc]$d, [string]$bin) { $bc = Get-KdpBinClip $d $bin; foreach ($x in (Get-KdpJsonArray (Get-KdpProp $bc.Node 'kdenlive:markers') | Where-Object { $_.PSObject.Properties['pos'] })) { [pscustomobject]@{ At = [math]::Round($x.pos / $d.Fps, 3); Dur = [math]::Round($x.duration / $d.Fps, 3); Comment = $x.comment; Category = $x.type } } }
function Set-KdpGuide([KdpDoc]$d, [double]$at, [string]$comment, $category = $null, $newAt = $null, $dur = $null) {
    $seq = Get-KdpSequence $d; $f = SecToFrames $d $at
    $g = @(Get-KdpJsonArray (Get-KdpProp $seq 'kdenlive:sequenceproperties.guides') | Where-Object { $_.PSObject.Properties['pos'] })
    $x = $g | Where-Object pos -eq $f | Select-Object -First 1; if (-not $x) { throw "No guide at $at s" }
    if ($comment) { $x.comment = $comment }; if ($null -ne $category) { $x.type = [int]$category }; if ($null -ne $newAt) { $x.pos = SecToFrames $d ([double]$newAt) }; if ($null -ne $dur) { $x.duration = SecToFrames $d ([double]$dur) }
    Set-KdpProp $seq 'kdenlive:sequenceproperties.guides' (ConvertTo-KdpJson ($g | Sort-Object pos))
}
function Clear-KdpGuides([KdpDoc]$d) { Set-KdpProp (Get-KdpSequence $d) 'kdenlive:sequenceproperties.guides' "[`n]`n" }
# Kdenlive "export guides": one line per guide, default format "{timecode} {comment}" (YouTube chapters).
function Export-KdpGuides([KdpDoc]$d, [string]$file, [string]$format = '{timecode} {comment}', $category = $null) {
    $lines = foreach ($g in (Get-KdpGuides $d | Sort-Object At)) {
        if ($null -ne $category -and $g.Category -ne [int]$category) { continue }
        $ts = [TimeSpan]::FromSeconds($g.At)
        $tc = if ($ts.TotalHours -ge 1) { '{0}:{1:00}:{2:00}' -f [int][math]::Floor($ts.TotalHours), $ts.Minutes, $ts.Seconds } else { '{0:00}:{1:00}' -f $ts.Minutes, $ts.Seconds }
        $format.Replace('{timecode}', $tc).Replace('{comment}', $g.Comment).Replace('{frame}', "$(SecToFrames $d $g.At)").Replace('{seconds}', "$($g.At)")
    }
    [IO.File]::WriteAllLines($file, [string[]]@($lines), (New-Object Text.UTF8Encoding($false)))
}
function Set-KdpGuideCategory([KdpDoc]$d, [int]$index, [string]$name, [string]$color) {
    $mb = $d.Xml.mlt.SelectSingleNode("playlist[@id='main_bin']")
    $cats = @(Get-KdpJsonArray (Get-KdpProp $mb 'kdenlive:docproperties.guidesCategories'))
    if (-not $cats.Count) { $def = '#9b59b6 #3daee9 #1abc9c #1cdc9a #c9ce3b #fdbc4b #f39c1f #f47750 #da4453'.Split(' '); $cats = @(for ($i = 0; $i -lt 9; $i++) { [pscustomobject]@{ color = $def[$i]; comment = "Category $($i + 1)"; index = $i } }) }
    $x = $cats | Where-Object index -eq $index | Select-Object -First 1
    if (-not $x) { $x = [pscustomobject]@{ color = $(if ($color) { $color } else { '#888888' }); comment = $name; index = $index }; $cats += $x }
    if ($name) { $x.comment = $name }; if ($color) { $x.color = $color }
    Set-KdpProp $mb 'kdenlive:docproperties.guidesCategories' ((ConvertTo-KdpJson ($cats | Sort-Object index)) -replace '\s+', ' ')
}

# ---------- subtitles: import .srt, export .srt, disable, lock ----------
function Import-KdpSrt([KdpDoc]$d, [string]$srt, [double]$offset = 0) {
    $txt = [IO.File]::ReadAllText((Resolve-Path $srt).Path)
    $blocks = [regex]::Matches($txt, '(?ms)^\s*\d+\s*\r?\n(\d+):(\d+):(\d+)[,.](\d+)\s*-->\s*(\d+):(\d+):(\d+)[,.](\d+)\s*\r?\n(.*?)(?=\r?\n\s*\r?\n|\z)')
    if (-not $blocks.Count) { throw "No subtitles found in $srt" }
    foreach ($b in $blocks) {
        $g = $b.Groups
        $s = [int]$g[1].Value * 3600 + [int]$g[2].Value * 60 + [int]$g[3].Value + [int]$g[4].Value / 1000.0
        $e = [int]$g[5].Value * 3600 + [int]$g[6].Value * 60 + [int]$g[7].Value + [int]$g[8].Value / 1000.0
        Add-KdpSubtitle $d ($s + $offset) ($e - $s) ($g[9].Value.Trim() -replace '<[^>]+>', '')
    }
    return $blocks.Count
}
function Export-KdpSrt([KdpDoc]$d, [string]$file) {
    $ass = Get-KdpAssPath $d; if (-not (Test-Path $ass)) { throw 'The project has no subtitles.' }
    $n = 0
    $out = foreach ($m in [regex]::Matches([IO.File]::ReadAllText($ass), '(?m)^Dialogue:\s*\d+,(\d+):(\d+):(\d+)\.(\d+),(\d+):(\d+):(\d+)\.(\d+),[^,]*,[^,]*,[^,]*,[^,]*,[^,]*,[^,]*,(.*)$')) {
        $g = $m.Groups; $n++
        "$n"; ('{0:00}:{1:00}:{2:00},{3:000} --> {4:00}:{5:00}:{6:00},{7:000}' -f [int]$g[1].Value, [int]$g[2].Value, [int]$g[3].Value, ([int]$g[4].Value * 10), [int]$g[5].Value, [int]$g[6].Value, [int]$g[7].Value, ([int]$g[8].Value * 10)); ($g[9].Value.TrimEnd() -replace '\\N', "`n"); ''
    }
    [IO.File]::WriteAllLines($file, [string[]]@($out), (New-Object Text.UTF8Encoding($false)))
    return $n
}
function Set-KdpSubtitleState([KdpDoc]$d, $disabled = $null, $locked = $null) {
    $f = (Get-KdpSequence $d).SelectSingleNode("filter[property[@name='mlt_service']='avfilter.subtitles']")
    if (-not $f) { throw 'The project has no subtitles.' }
    if ($null -ne $disabled) { Set-KdpProp $f 'disable' $(if ($disabled) { 1 } else { 0 }) }
    if ($null -ne $locked) { Set-KdpProp $f 'kdenlive:locked' $(if ($locked) { 1 } else { 0 }) }
}

# ---------- zone ----------
function Set-KdpZone([KdpDoc]$d, [double]$from, [double]$to, [switch]$UseInEdits) {
    $seq = Get-KdpSequence $d
    Set-KdpProp $seq 'kdenlive:sequenceproperties.zonein' (SecToFrames $d $from)
    Set-KdpProp $seq 'kdenlive:sequenceproperties.zoneout' (SecToFrames $d $to)
    Set-KdpProp $d.Xml.mlt.SelectSingleNode("playlist[@id='main_bin']") 'kdenlive:docproperties.enableTimelineZone' $(if ($UseInEdits) { 1 } else { 0 })
}

# ---------- bin clip management ----------
function Get-KdpClipCopies([KdpDoc]$d, $binNode) {
    $u = Get-KdpProp $binNode 'kdenlive:control_uuid'
    foreach ($n in $d.Xml.mlt.SelectNodes('producer|chain')) { if (-not [object]::ReferenceEquals($n, $binNode) -and (Get-KdpProp $n 'kdenlive:control_uuid') -eq $u) { $n } }
}
function Get-KdpBinInfo([KdpDoc]$d, [string]$bin) {
    $bc = Get-KdpBinClip $d $bin
    $uses = @(Get-KdpClips $d | Where-Object BinId -eq $bc.BinId | ForEach-Object { "$($_.Track)@$($_.Start)" })
    [pscustomobject]@{ Clip = $bc; Uses = $uses; Properties = ($bc.Node.SelectNodes('property') | ForEach-Object { "$($_.name)=$($_.InnerText)" }) }
}
# Clip properties as in Kdenlive's clip properties panel (force_fps, force_aspect_ratio,
# force_progressive, force_tff, rotate, audio_index, video_index, set.force_full_luma,
# kdenlive:description, kdenlive:tags, kdenlive:rating...). Applied to the bin clip and all its timeline copies.
function Set-KdpBinProps([KdpDoc]$d, [string]$bin, [hashtable]$values) {
    $bc = Get-KdpBinClip $d $bin
    foreach ($n in @($bc.Node) + @(Get-KdpClipCopies $d $bc.Node)) { foreach ($k in $values.Keys) { if ("$($values[$k])" -eq '') { Remove-KdpProp $n $k } else { Set-KdpProp $n $k $values[$k] } } }
}
function Copy-KdpBinClip([KdpDoc]$d, [string]$bin, [string]$name) {
    $bc = Get-KdpBinClip $d $bin
    if ($bc.Node.Name -eq 'tractor') { throw 'Use sequence-add to make a new sequence.' }
    $n = $bc.Node.Clone(); $n.SetAttribute('id', (New-KdpId $d $bc.Node.Name))
    Set-KdpProp $n 'kdenlive:id' (Get-KdpNextBinId $d); Set-KdpProp $n 'kdenlive:control_uuid' (New-KdpUuid)
    Set-KdpProp $n 'kdenlive:clipname' $(if ($name) { $name } else { "$($bc.Name) (copy)" })
    [void]$d.Xml.mlt.InsertBefore($n, $bc.Node.NextSibling)
    $e = $d.Xml.CreateElement('entry'); $e.SetAttribute('producer', $n.id); $e.SetAttribute('in', $n.GetAttribute('in')); $e.SetAttribute('out', $n.GetAttribute('out'))
    [void]$d.Xml.mlt.SelectSingleNode("playlist[@id='main_bin']").AppendChild($e)
    return Get-KdpBinClip $d (Get-KdpProp $n 'kdenlive:id')
}
# Point a bin clip (and all its uses) at another media file; lengths and hashes are refreshed.
function Set-KdpBinFile([KdpDoc]$d, [string]$bin, [string]$file) {
    $bc = Get-KdpBinClip $d $bin
    $svc = Get-KdpProp $bc.Node 'mlt_service'
    $rel = Get-KdpRelPath $d $file
    $vals = @{ resource = $rel; 'kdenlive:file_hash' = (Get-KdpFileHash $file); 'kdenlive:file_size' = (Get-Item $file).Length }
    if ($bc.Node.Name -eq 'chain' -or $svc -like 'avformat*') {
        $mi = Get-KdpMediaInfo $file
        $vals['length'] = [int][math]::Floor($mi.Duration * $d.Fps + 0.01); $vals['audio_index'] = $mi.AudioIndex; $vals['video_index'] = $mi.VideoIndex
        $vals['kdenlive:clip_type'] = $(if ($mi.VideoIndex -ge 0 -and $mi.AudioIndex -ge 0) { 0 } elseif ($mi.VideoIndex -ge 0) { 2 } else { 1 })
        foreach ($n in @($bc.Node) + @(Get-KdpClipCopies $d $bc.Node)) { foreach ($p in @($n.SelectNodes("property[starts-with(@name,'meta.')]"))) { [void]$n.RemoveChild($p) } }
    }
    Set-KdpBinProps $d $bin $vals
    foreach ($n in @(Get-KdpClipCopies $d $bc.Node)) { if ((Get-KdpProp $n 'mlt_service') -eq 'timewarp') { $sp = Get-KdpProp $n 'warp_speed'; Set-KdpProp $n 'resource' "${sp}:$rel"; Set-KdpProp $n 'warp_resource' $rel } }
}
function Update-KdpBinClip([KdpDoc]$d, [string]$bin) {
    $bc = Get-KdpBinClip $d $bin
    $res = $bc.Resource; $full = if ([IO.Path]::IsPathRooted($res)) { $res } else { Join-Path ($d.Root -replace '/', '\') $res }
    if (-not (Test-Path $full)) { throw "Media missing: $full (use relink)" }
    if ((Get-KdpProp $bc.Node 'mlt_service') -eq 'qimage' -and $res -match '%|\.all\.') { return }
    Set-KdpBinFile $d $bin $full
}
# Find missing media by file name under a folder and relink every clip that points to it.
function Update-KdpMissingMedia([KdpDoc]$d, [string]$searchDir) {
    $fixed = @()
    foreach ($bc in Get-KdpBinClips $d) {
        if (-not $bc.Resource -or $bc.Service -in 'color', 'colour', 'kdenlivetitle', 'sequence') { continue }
        $full = if ([IO.Path]::IsPathRooted($bc.Resource)) { $bc.Resource } else { Join-Path ($d.Root -replace '/', '\') $bc.Resource }
        if ($bc.Resource -match '%|\.all\.' -or (Test-Path $full)) { continue }
        $cand = Get-ChildItem $searchDir -Recurse -File -Filter ([IO.Path]::GetFileName($full)) -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($cand) { Set-KdpBinFile $d $bc.BinId $cand.FullName; $fixed += "$($bc.Name) -> $($cand.FullName)" }
    }
    return $fixed
}
# Replace every timeline use of clip A by clip B (same in/out, same effects) - "replace in timeline".
function Set-KdpReplaceInTimeline([KdpDoc]$d, [string]$binA, [string]$binB) {
    $a = Get-KdpBinClip $d $binA; $b = Get-KdpBinClip $d $binB; $n = 0
    $saved = $d.SeqId
    foreach ($sq in @(Get-KdpSequences $d)) {
        $d.SeqId = $sq.Uuid
        foreach ($c in @(Get-KdpClips $d | Where-Object BinId -eq $a.BinId)) {
            $t = Get-KdpTrack $d $c.Track
            if ($t.Audio -and -not (Test-KdpHasAudio $b.Node)) { continue }
            if (-not $t.Audio -and -not (Test-KdpHasVideo $b.Node)) { continue }
            $new = New-KdpInstance $d $b $t (ConvertTo-KdpFrames $d $c.Node.in) (ConvertTo-KdpFrames $d $c.Node.out)
            $c.Node.SetAttribute('producer', $new.producer); Set-KdpProp $c.Node 'kdenlive:id' $b.BinId; $n++
        }
    }
    $d.SeqId = $saved
    return $n
}
function Remove-KdpUnusedClips([KdpDoc]$d) {
    $used = @{}
    $saved = $d.SeqId
    foreach ($sq in @(Get-KdpSequences $d)) { $d.SeqId = $sq.Uuid; foreach ($c in Get-KdpClips $d) { $used[$c.BinId] = 1 } }
    $d.SeqId = $saved
    $removed = @()
    foreach ($bc in @(Get-KdpBinClips $d)) { if ($bc.Node.Name -ne 'tractor' -and -not $used.ContainsKey($bc.BinId)) { Remove-KdpBinClip $d $bc.BinId; $removed += $bc.Name } }
    return $removed
}

# ---------- generators (Kdenlive: Project > Add Generator) ----------
function Add-KdpGenerator([KdpDoc]$d, [string]$id, [double]$seconds = 5, [hashtable]$values = @{}, [string]$name) {
    $f = Get-ChildItem (Join-Path $script:KdpData 'generators') -Filter *.xml | Where-Object { (Select-String -Path $_.FullName -Pattern "id=`"$([regex]::Escape($id))`"" -Quiet) } | Select-Object -First 1
    if (-not $f) { throw "Unknown generator '$id' (count, noise, frei0r.test_pat_B)" }
    $x = New-Object System.Xml.XmlDocument; $x.XmlResolver = $null; $x.Load($f.FullName)
    $g = $x.SelectSingleNode('//generator')
    $lenF = SecToFrames $d $seconds
    $props = [ordered]@{ length = $lenF; eof = 'pause'; resource = ''; mlt_service = $g.GetAttribute('tag') }
    foreach ($p in $g.SelectNodes('parameter')) { $nm = $p.GetAttribute('name'); $props[$nm] = $(if ($values.ContainsKey($nm)) { $values[$nm] } else { $p.GetAttribute('default') }) }
    $props['kdenlive:clipname'] = $(if ($name) { $name } else { $g.SelectSingleNode('name').InnerText })
    $props['kdenlive:duration'] = (ConvertTo-KdpTime $d $lenF)
    $props['kdenlive:clip_type'] = $(if ($g.GetAttribute('type') -match 'audio') { 0 } else { 2 })
    return Add-KdpBinProducer $d 'producer' 'producer' $props $lenF
}

# ---------- title templates (.kdenlivetitle files) ----------
function Save-KdpTitleTemplate([KdpDoc]$d, [string]$bin, [string]$file) {
    $bc = Get-KdpBinClip $d $bin; $xml = Get-KdpProp $bc.Node 'xmldata'; if (-not $xml) { throw "'$bin' is not a title" }
    [IO.File]::WriteAllText($file, $xml, (New-Object Text.UTF8Encoding($false)))
}
# A template clip shows a .kdenlivetitle file; "%s" in its text is replaced by $text.
function Add-KdpTitleTemplateClip([KdpDoc]$d, [string]$file, [string]$text, [double]$seconds = 5, [string]$name) {
    $full = (Resolve-Path $file).Path
    $tpl = [IO.File]::ReadAllText($full)
    $fonts = [regex]::Matches($tpl, 'font="([^"]+)"') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique
    foreach ($fn in $fonts) { if (-not (Test-KdpFont $fn)) { throw "Template uses font '$fn' that is not installed." } }
    $lenF = SecToFrames $d $seconds
    $props = [ordered]@{ length = $lenF; eof = 'pause'; resource = (Get-KdpRelPath $d $full); templatetext = $text; mlt_service = 'kdenlivetitle'; 'kdenlive:duration' = (ConvertTo-KdpTime $d $lenF); 'kdenlive:clipname' = $(if ($name) { $name } else { [IO.Path]::GetFileNameWithoutExtension($full) }); 'kdenlive:clip_type' = 2 }
    return Add-KdpBinProducer $d 'producer' 'producer' $props $lenF
}

# ---------- playlist / other project as a clip ----------
function Add-KdpPlaylistClip([KdpDoc]$d, [string]$file, [string]$name) {
    $full = (Resolve-Path $file).Path
    $tmp = [IO.Path]::GetTempFileName() + '.mlt'
    $p = Start-Process -FilePath (Join-Path $script:KdpBin 'melt.exe') -ArgumentList @("`"$full`"", '-consumer', "xml:`"$tmp`"", 'all=1') -NoNewWindow -Wait -PassThru -RedirectStandardError ([IO.Path]::GetTempFileName())
    [xml]$x = Get-Content $tmp -Raw -Encoding UTF8; Remove-Item $tmp -ErrorAction SilentlyContinue
    $last = $x.mlt.SelectNodes('tractor|playlist') | Select-Object -Last 1
    $lenF = (ConvertTo-KdpFrames $d $last.GetAttribute('out')) + 1
    if ($lenF -lt 1) { throw "Could not read the length of $file" }
    $props = [ordered]@{ length = $lenF; eof = 'pause'; resource = (Get-KdpRelPath $d $full); mlt_service = 'xml'; 'kdenlive:clipname' = $(if ($name) { $name } else { [IO.Path]::GetFileName($full) }); 'kdenlive:clip_type' = 0; 'kdenlive:file_size' = (Get-Item $full).Length; 'kdenlive:file_hash' = (Get-KdpFileHash $full) }
    return Add-KdpBinProducer $d 'producer' 'producer' $props $lenF
}

# ---------- clip jobs: extract audio, transcode ----------
function Invoke-KdpExtractAudio([KdpDoc]$d, [string]$bin, [string]$outDir) {
    $bc = Get-KdpBinClip $d $bin
    $full = Get-KdpBinFullPath $d $bc
    if (-not $outDir) { $outDir = Get-KdpJobDir $d 'extracted' }
    New-Item -ItemType Directory -Force $outDir | Out-Null
    $out = New-KdpJobFile $outDir ([IO.Path]::GetFileNameWithoutExtension($full) + '-audio') '.wav'
    [void](Invoke-KdpTool 'ffmpeg.exe' "-v error -y -i `"$full`" -vn -acodec pcm_s16le `"$out`"" 'Extract audio')
    return Add-KdpMedia $d $out
}
function Invoke-KdpTranscode([KdpDoc]$d, [string]$bin, [string]$ffArgs = '-c:v libx264 -crf 18 -preset medium -c:a aac -b:a 192k', [string]$ext = 'mp4', [switch]$Replace, [string]$outDir) {
    $bc = Get-KdpBinClip $d $bin
    $full = Get-KdpBinFullPath $d $bc
    if (-not $outDir) { $outDir = Get-KdpJobDir $d 'transcoded' }
    New-Item -ItemType Directory -Force $outDir | Out-Null
    $out = New-KdpJobFile $outDir ([IO.Path]::GetFileNameWithoutExtension($full) + '-transcoded') ".$ext"
    [void](Invoke-KdpTool 'ffmpeg.exe' "-v error -y -i `"$full`" $ffArgs `"$out`"" 'Transcode')
    if ($Replace) { Set-KdpBinFile $d $bin $out; return $bc } else { return Add-KdpMedia $d $out }
}

# ---------- subclips (Kdenlive: monitor "insert zone in project bin") ----------
# Stored as kdenlive:clipzones JSON [{"name","in","out"}] on the bin clip (ProjectClip::updateZones).
# Use a subclip on the timeline with: add -Bin <parent> -In <from> -Dur <length>.
function Add-KdpSubclip([KdpDoc]$d, [string]$bin, [double]$from, [double]$to, [string]$name) {
    $bc = Get-KdpBinClip $d $bin
    $z = @(Get-KdpJsonArray (Get-KdpProp $bc.Node 'kdenlive:clipzones') | Where-Object { $_.PSObject.Properties['in'] })
    $z += [pscustomobject]@{ name = $(if ($name) { $name } else { "$($bc.Name) $from-$to" }); in = (SecToFrames $d $from); out = (SecToFrames $d $to) }
    Set-KdpProp $bc.Node 'kdenlive:clipzones' (ConvertTo-KdpJson $z)
}
function Get-KdpSubclips([KdpDoc]$d, [string]$bin) { $bc = Get-KdpBinClip $d $bin; foreach ($x in (Get-KdpJsonArray (Get-KdpProp $bc.Node 'kdenlive:clipzones') | Where-Object { $_.PSObject.Properties['in'] })) { [pscustomobject]@{ Name = $x.name; From = [math]::Round($x.in / $d.Fps, 3); To = [math]::Round($x.out / $d.Fps, 3) } } }

# ---------- clip jobs from clipjobsettings.rc: stabilize, scene split, speed (timewarp) ----------
function Get-KdpBinFullPath([KdpDoc]$d, $bc) { if ([IO.Path]::IsPathRooted($bc.Resource)) { $bc.Resource } else { [IO.Path]::GetFullPath((Join-Path ($d.Root -replace '/', '\') ($bc.Resource -replace '/', '\'))) } }
# Job results stay inside the project folder: materials\aigenerated\<project>\<job>\. An existing file is never overwritten.
function Get-KdpJobDir([KdpDoc]$d, [string]$sub) {
    $dir = Join-Path $script:KdpHome ("materials\aigenerated\{0}\{1}" -f [IO.Path]::GetFileNameWithoutExtension($d.Path), $sub)
    [void][IO.Directory]::CreateDirectory($dir)
    return $dir
}
function New-KdpJobFile([string]$dir, [string]$stem, [string]$ext) {
    $file = Join-Path $dir "$stem$ext"; $n = 1
    while (Test-Path -LiteralPath $file) { $n++; $file = Join-Path $dir "$stem-$n$ext" }
    return $file
}
# Stabilize with vid.stab, the filter Kdenlive's own job uses (two passes: analyse, then render).
# ffmpeg's deshake is much weaker; do not go back to it.
function Invoke-KdpStabilize([KdpDoc]$d, [string]$bin, [switch]$Replace, [int]$shakiness = 4, [int]$smoothing = 10) {
    $bc = Get-KdpBinClip $d $bin; $src = Get-KdpBinFullPath $d $bc
    $out = New-KdpJobFile (Get-KdpJobDir $d 'stabilized') ([IO.Path]::GetFileNameWithoutExtension($src) + '-stabilized') '.mp4'
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ('kdp-stab-' + [guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($tmp)
    try {
        $mlt = "$tmp\pass.mlt"
        [void](Invoke-KdpTool 'melt.exe' "-silent `"$src`" -attach vidstab shakiness=$shakiness smoothing=$smoothing filename=`"$tmp\motion.trf`" -consumer xml:`"$mlt`" all=1 real_time=-1" 'Stabilize, analysis pass')
        if (-not (Test-Path "$tmp\motion.trf")) { throw 'Stabilize: the analysis wrote no motion data' }
        $codec = if ((Get-KdpMediaInfo $src).AudioIndex -ge 0) { 'acodec=aac ab=256k' } else { 'an=1' }
        [void](Invoke-KdpTool 'melt.exe' "-silent `"$mlt`" -consumer avformat:`"$out`" real_time=-1 vcodec=libx264 crf=16 preset=medium $codec" 'Stabilize, render pass')
        if (-not (Test-Path -LiteralPath $out)) { throw 'Stabilize produced no file' }
    } finally { Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue }
    if ($Replace) { Set-KdpBinFile $d $bin $out; return $bc } else { return Add-KdpMedia $d $out }
}
# Scene split: detect cuts and add a clip marker at each (Kdenlive's scenesplit job adds markers).
function Invoke-KdpSceneSplit([KdpDoc]$d, [string]$bin, [double]$threshold = 10) {
    $bc = Get-KdpBinClip $d $bin; $src = Get-KdpBinFullPath $d $bc
    $err = [IO.Path]::GetTempFileName()
    $p = Start-Process -FilePath (Join-Path $script:KdpBin 'ffmpeg.exe') -ArgumentList "-hide_banner -i `"$src`" -vf `"scdet=threshold=$($threshold.ToString([cultureinfo]::InvariantCulture)),metadata=print`" -an -f null -" -NoNewWindow -Wait -PassThru -RedirectStandardError $err
    $times = @([regex]::Matches((Get-Content $err -Raw), 'lavfi\.scd\.time=([\d.]+)') | ForEach-Object { [double]::Parse($_.Groups[1].Value, [cultureinfo]::InvariantCulture) } | Sort-Object -Unique)
    Remove-Item $err
    $i = 1; foreach ($t in $times) { Add-KdpClipMarker $d $bc.BinId $t "Scene $i"; $i++ }
    return $times
}
# Speed job: render a new file at the given speed (Kdenlive's timewarp clip job), then add it.
function Invoke-KdpSpeedJob([KdpDoc]$d, [string]$bin, [double]$speed) {
    if ($speed -le 0) { throw 'Speed must be positive (use speed -Speed -1 on the timeline for reverse).' }
    $bc = Get-KdpBinClip $d $bin; $src = Get-KdpBinFullPath $d $bc
    $out = New-KdpJobFile (Get-KdpJobDir $d 'speed') ([IO.Path]::GetFileNameWithoutExtension($src) + "-x$($speed.ToString([cultureinfo]::InvariantCulture))") '.mp4'
    $at = @(); $s = $speed; while ($s -gt 2) { $at += 'atempo=2.0'; $s /= 2 }; while ($s -lt 0.5) { $at += 'atempo=0.5'; $s /= 0.5 }; $at += "atempo=$($s.ToString([cultureinfo]::InvariantCulture))"
    $mi = Get-KdpMediaInfo $src
    $af = if ($mi.AudioIndex -ge 0) { "-af `"$($at -join ',')`" -c:a aac" } else { '-an' }
    $p = Start-Process -FilePath (Join-Path $script:KdpBin 'ffmpeg.exe') -ArgumentList "-v error -y -i `"$src`" -vf `"setpts=PTS/$($speed.ToString([cultureinfo]::InvariantCulture))`" $af -c:v libx264 -crf 18 -preset medium `"$out`"" -NoNewWindow -Wait -PassThru
    if ($p.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $out)) { throw "speed job failed (ffmpeg exit $($p.ExitCode))" }
    return Add-KdpMedia $d $out
}

# ---------- effect templates (data/kdenlive/effect-templates/*.xml, effect groups) ----------
function Get-KdpEffectTemplates { Get-ChildItem (Join-Path $script:KdpData 'effect-templates') -Filter *.xml | ForEach-Object { $x = New-Object System.Xml.XmlDocument; $x.Load($_.FullName); [pscustomobject]@{ Name = $_.BaseName; Id = $x.DocumentElement.GetAttribute('id'); Description = $x.SelectSingleNode('//description').InnerText; Effects = (@($x.SelectNodes('//effect')) | ForEach-Object { $_.GetAttribute('id') }) -join ', '; File = $_.FullName } } }
function Add-KdpEffectTemplate([KdpDoc]$d, [string]$template, [string]$track, $at) {
    $t = Get-KdpEffectTemplates | Where-Object { $_.Name -eq $template -or $_.Id -eq $template } | Select-Object -First 1
    if (-not $t) { throw "Unknown effect template '$template' (kdp.ps1 effect-templates)" }
    $x = New-Object System.Xml.XmlDocument; $x.Load($t.File)
    $relative = $x.DocumentElement.GetAttribute('parentIn') -eq '1'
    $hostInfo = Get-KdpEffectHost $d $track $at
    $shift = if ($relative) { $hostInfo.In } else { 0 }
    $n = 0
    foreach ($e in $x.SelectNodes('//effect')) {
        $vals = @{}
        foreach ($p in $e.SelectNodes('property')) {
            if ($p.GetAttribute('name') -like 'kdenlive:*') { continue }
            $v = $p.InnerText.Trim()
            if ($shift -and $v -match '^\d+=') { $v = (($v -split ';') | ForEach-Object { if ($_ -match '^(\d+)(.?)=(.*)$') { "$([int]$matches[1] + $shift)$($matches[2])=$($matches[3])" } else { $_ } }) -join ';' }
            $vals[$p.GetAttribute('name')] = $v
        }
        [void](Add-KdpEffect $d $e.GetAttribute('id') $track $at -values $vals); $n++
    }
    return $n
}

# ---------- archive project (Kdenlive: File > Archive project) ----------
# Copies the project and every media file it uses into $dest, with relative paths, so the folder
# can be moved anywhere. Returns the archived project path.
function Export-KdpArchive([KdpDoc]$d, [string]$dest) {
    New-Item -ItemType Directory -Force $dest | Out-Null
    $destFull = (Resolve-Path $dest).Path
    $media = Join-Path $destFull 'media'; New-Item -ItemType Directory -Force $media | Out-Null
    $copy = New-Object System.Xml.XmlDocument; $copy.LoadXml($d.Xml.OuterXml)
    $root = $d.Root -replace '/', '\'
    $map = @{}
    foreach ($n in $copy.SelectNodes('//producer|//chain')) {
        foreach ($pn in 'resource', 'warp_resource') {
            $p = $n.SelectSingleNode("property[@name='$pn']"); if (-not $p) { continue }
            $res = $p.InnerText; $prefix = ''
            if ($pn -eq 'resource' -and (Get-KdpProp $n 'mlt_service') -eq 'timewarp' -and $res -match '^(-?[\d.]+):(.+)$') { $prefix = $matches[1] + ':'; $res = $matches[2] }
            if (-not $res -or $res -in 'black', '0' -or $res -match '^0x' -or (Get-KdpProp $n 'mlt_service') -in 'color', 'colour') { continue }
            $full = [IO.Path]::GetFullPath($(if ([IO.Path]::IsPathRooted($res)) { $res } else { Join-Path $root ($res -replace '/', '\') }))
            $isSeq = $res -match '%|\.all\.'
            $srcItem = if ($isSeq) { Split-Path $full -Parent } else { $full }
            if (-not (Test-Path $srcItem)) { continue }
            if (-not $map.ContainsKey($srcItem)) {
                $nm = Split-Path $srcItem -Leaf; $target = Join-Path $media $nm; $k = 1
                while (Test-Path $target) { $target = Join-Path $media ("{0}-{1}{2}" -f [IO.Path]::GetFileNameWithoutExtension($nm), $k, [IO.Path]::GetExtension($nm)); $k++ }
                if ($isSeq) { Copy-Item $srcItem $target -Recurse } else { Copy-Item $srcItem $target }
                $map[$srcItem] = 'media/' + (Split-Path $target -Leaf)
            }
            $newRel = if ($isSeq) { $map[$srcItem] + '/' + (Split-Path $full -Leaf) } else { $map[$srcItem] }
            $p.InnerText = $prefix + $newRel
        }
    }
    $copy.DocumentElement.SetAttribute('root', ($destFull -replace '\\', '/'))
    foreach ($f in $copy.SelectNodes("/mlt/tractor/filter[property[@name='mlt_service']='avfilter.subtitles']")) {
        $ass = Get-KdpAssPath $d $f.ParentNode
        if (Test-Path -LiteralPath $ass) {
            $to = Join-Path $destFull ([IO.Path]::GetFileName($ass)); Copy-Item -LiteralPath $ass $to -Force
            Set-KdpProp $f 'av.filename' ($to -replace '\\', '/')
        }
    }
    $out = Join-Path $destFull ([IO.Path]::GetFileName($d.Path))
    $settings = New-Object System.Xml.XmlWriterSettings; $settings.Indent = $true; $settings.IndentChars = ' '; $settings.Encoding = New-Object System.Text.UTF8Encoding($false)
    $w = [System.Xml.XmlWriter]::Create($out, $settings); $copy.Save($w); $w.Close()
    return $out
}

# ---------- Kdenlive's own backups (File > Open backup) ----------
function Get-KdpBackups([KdpDoc]$d) {
    $dir = Join-Path $script:KdpEngine 'profile-kdenlive\AppData\Roaming\kdenlive\.backup'
    $base = [IO.Path]::GetFileNameWithoutExtension($d.Path)
    $docid = Get-KdpProp $d.Xml.mlt.SelectSingleNode("playlist[@id='main_bin']") 'kdenlive:docproperties.documentid'
    Get-ChildItem $dir -Filter "$base-*.kdenlive" -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "$base-$docid-*" -or $_.Name -like "$base-*" } | Sort-Object LastWriteTime -Descending | Select-Object Name, LastWriteTime, Length, FullName
}

# ---------- profile (Project settings > video profile) ----------
# Changes the project profile. With a different frame rate, frame-count properties are rescaled;
# clock-time positions stay. -FromClip <bin> picks the profile matching that clip.
function Set-KdpProfile([KdpDoc]$d, [string]$profile) {
    $pf = Join-Path $script:KdpProfiles $profile
    if (-not (Test-Path $pf)) { throw "Unknown profile '$profile' (kdp.ps1 profiles)" }
    $pr = @{}; foreach ($l in Get-Content $pf) { if ($l -match '^(\w+)=(.*)$') { $pr[$matches[1]] = $matches[2] } }
    $oldFps = $d.Fps; $newFps = [double]$pr.frame_rate_num / [double]$pr.frame_rate_den
    $pe = $d.Xml.mlt.profile
    foreach ($k in 'colorspace', 'description', 'display_aspect_den', 'display_aspect_num', 'frame_rate_den', 'frame_rate_num', 'height', 'progressive', 'sample_aspect_den', 'sample_aspect_num', 'width') { $pe.SetAttribute($k, $pr[$k]) }
    Set-KdpProp $d.Xml.mlt.SelectSingleNode("playlist[@id='main_bin']") 'kdenlive:docproperties.profile' $profile
    if ([math]::Abs($oldFps - $newFps) -gt 0.0001) {
        $r = $newFps / $oldFps
        function Scale([string]$v) { if ($v -match '^\d+$') { [string][int][math]::Round([int]$v * $r) } else { $v } }
        foreach ($n in $d.Xml.SelectNodes("//property[@name='length' or @name='kdenlive:duration' or @name='kdenlive:maxduration' or @name='ttl' or @name='kdenlive:mixcut' or @name='luma_duration' or @name='kdenlive:sequenceproperties.zonein' or @name='kdenlive:sequenceproperties.zoneout']")) { if ($n.InnerText -ne '2147483647') { $n.InnerText = Scale $n.InnerText } }
        foreach ($n in $d.Xml.SelectNodes("//property[@name='kdenlive:sequenceproperties.guides' or @name='kdenlive:markers']")) {
            $arr = @(Get-KdpJsonArray $n.InnerText | Where-Object { $_.PSObject.Properties['pos'] }); foreach ($x in $arr) { $x.pos = [int][math]::Round($x.pos * $r); $x.duration = [int][math]::Round($x.duration * $r) }
            $n.InnerText = ConvertTo-KdpJson $arr
        }
        foreach ($n in $d.Xml.SelectNodes("//property[@name='kdenlive:sequenceproperties.groups']")) { $n.InnerText = [regex]::Replace($n.InnerText, '"data":\s*"(\d+):(\d+)', { param($m) '"data": "' + $m.Groups[1].Value + ':' + [int][math]::Round([int]$m.Groups[2].Value * $r) }) }
        foreach ($n in $d.Xml.SelectNodes("//producer[property[@name='mlt_service']='kdenlivetitle']/property[@name='xmldata']")) { $n.InnerText = [regex]::Replace($n.InnerText, 'out="(\d+)"', { param($m) 'out="' + [int][math]::Round([int]$m.Groups[1].Value * $r) + '"' }) }
    }
    $d.Fps = $newFps
}
function Find-KdpProfileForClip([KdpDoc]$d, [string]$bin) {
    $bc = Get-KdpBinClip $d $bin
    $full = if ([IO.Path]::IsPathRooted($bc.Resource)) { $bc.Resource } else { Join-Path ($d.Root -replace '/', '\') $bc.Resource }
    $j = & (Join-Path $script:KdpBin 'ffprobe.exe') -v error -select_streams v:0 -show_entries stream=width,height,r_frame_rate,field_order,sample_aspect_ratio -of json $full | Out-String | ConvertFrom-Json
    $s = $j.streams[0]; $fr = $s.r_frame_rate.Split('/')
    # scan type and pixel shape must match too: the first size+fps match for 1080p30 is the INTERLACED 1080i profile
    $progressive = if ($s.field_order -in 'tt', 'bb', 'tb', 'bt') { 0 } else { 1 }
    $sar = if ($s.sample_aspect_ratio -match '^([1-9]\d*):([1-9]\d*)$') { @($matches[1], $matches[2]) } else { @('1', '1') }
    foreach ($f in Get-ChildItem $script:KdpProfiles) {
        $c = Get-Content $f.FullName
        if ($c -contains "width=$($s.width)" -and $c -contains "height=$($s.height)" -and $c -contains "frame_rate_num=$($fr[0])" -and $c -contains "frame_rate_den=$($fr[1])" -and $c -contains "progressive=$progressive" -and $c -contains "sample_aspect_num=$($sar[0])" -and $c -contains "sample_aspect_den=$($sar[1])") { return $f.Name }
    }
    throw "No installed profile matches $($s.width)x$($s.height) @ $($s.r_frame_rate)"
}

# ---------- range copy between sequences (Kdenlive: copy to sequence / send to sequence) ----------
function Copy-KdpRangeToSequence([KdpDoc]$d, [double]$from, [double]$to, [string]$target, [double]$at = 0) {
    $src = $d.SeqId
    $fromF = SecToFrames $d $from; $toF = SecToFrames $d $to
    $clips = @(Get-KdpClips $d | Where-Object { $_.Sub -eq 0 -and $_.StartFrames -ge $fromF -and $_.StartFrames + $_.LenFrames -le $toF })
    if (-not $clips) { throw "No whole clips between $from and $to s" }
    $srcTracks = Get-KdpTracks $d
    Select-KdpSequence $d $target
    $dstTracks = Get-KdpTracks $d
    foreach ($c in $clips) {
        $st = $srcTracks | Where-Object Name -eq $c.Track
        $dt = $dstTracks | Where-Object Name -eq $c.Track
        if (-not $dt) { $d.SeqId = $src; throw "Target sequence has no track $($c.Track)." }
        $e = $c.Node.Clone()
        $prod = $d.Xml.mlt.SelectSingleNode("*[@id='$($c.Node.producer)']")
        if ($prod.Name -eq 'chain' -or (Get-KdpProp $prod 'mlt_service') -in 'timewarp' -or (Get-KdpProp $prod 'mlt_service') -like 'avformat*') { $pc = $prod.Clone(); $pc.SetAttribute('id', (New-KdpId $d $prod.Name)); [void]$d.Xml.mlt.InsertBefore($pc, $dt.Playlists[0]); $e.SetAttribute('producer', $pc.id) }
        foreach ($f in $e.SelectNodes('filter')) { $f.SetAttribute('id', (New-KdpId $d 'filter')) }
        Set-KdpEntryAt $d $dt $e ((SecToFrames $d $at) + $c.StartFrames - $fromF) $c.LenFrames
    }
    $d.SeqId = $src
    return $clips.Count
}
# Replace a nested-sequence clip by the clips inside it (Kdenlive: expand clip).
function Expand-KdpSequenceClip([KdpDoc]$d, [string]$track, [double]$at) {
    $c = Find-KdpClip $d $track $at
    $inner = $d.Xml.mlt.SelectSingleNode("tractor[@id='$($c.Node.producer)']")
    if (-not $inner) { throw 'The clip is not a nested sequence.' }
    $innerName = Get-KdpProp $inner 'kdenlive:clipname'
    $inF = ConvertTo-KdpFrames $d $c.Node.in; $start = $c.StartFrames; $len = $c.LenFrames
    Remove-KdpEntry $d (Get-KdpTrack $d $track) $c.Node
    $outer = $d.SeqId
    $d.SeqId = $inner.id
    $n = 0
    try {
        $clips = @(Get-KdpClips $d | Where-Object { $_.Sub -eq 0 -and $_.StartFrames -lt $inF + $len -and $_.StartFrames + $_.LenFrames -gt $inF })
        $innerTracks = Get-KdpTracks $d
    } finally { $d.SeqId = $outer }
    $outerTracks = Get-KdpTracks $d
    foreach ($ic in $clips) {
        $dt = $outerTracks | Where-Object Name -eq $ic.Track
        if (-not $dt) { continue }
        $e = $ic.Node.Clone(); foreach ($f in $e.SelectNodes('filter')) { $f.SetAttribute('id', (New-KdpId $d 'filter')) }
        $prod = $d.Xml.mlt.SelectSingleNode("*[@id='$($ic.Node.producer)']")
        if ($prod.Name -eq 'chain' -or (Get-KdpProp $prod 'mlt_service') -in 'timewarp' -or (Get-KdpProp $prod 'mlt_service') -like 'avformat*') { $pc = $prod.Clone(); $pc.SetAttribute('id', (New-KdpId $d $prod.Name)); [void]$d.Xml.mlt.InsertBefore($pc, $dt.Playlists[0]); $e.SetAttribute('producer', $pc.id) }
        # crop to the used part of the nested sequence
        $s = [math]::Max($ic.StartFrames, $inF); $eF = [math]::Min($ic.StartFrames + $ic.LenFrames, $inF + $len)
        $ein = (ConvertTo-KdpFrames $d $ic.Node.in) + ($s - $ic.StartFrames)
        $e.SetAttribute('in', (ConvertTo-KdpTime $d $ein)); $e.SetAttribute('out', (ConvertTo-KdpTime $d ($ein + $eF - $s - 1)))
        Set-KdpEntryAt $d $dt $e ($start + $s - $inF) ($eF - $s) -Overwrite
        $n++
    }
    return "$n clip(s) from '$innerName'"
}

# ---------- OpenTimelineIO export / import (Kdenlive: File > Export/Import OpenTimelineIO) ----------
function Export-KdpOtio([KdpDoc]$d, [string]$file) {
    $rate = $d.Fps
    function RT([double]$v) { [ordered]@{ 'OTIO_SCHEMA' = 'RationalTime.1'; rate = $rate; value = [double]$v } }
    function TR([double]$s, [double]$l) { [ordered]@{ 'OTIO_SCHEMA' = 'TimeRange.1'; duration = (RT $l); start_time = (RT $s) } }
    $tracks = @()
    foreach ($t in (Get-KdpTracks $d | Sort-Object Index)) {
        $children = @(); $pos = 0
        foreach ($it in (Read-KdpItems $d $t.Playlists[0])) {
            if ($it.Kind -eq 'blank') { $children += [ordered]@{ 'OTIO_SCHEMA' = 'Gap.1'; name = ''; source_range = (TR 0 $it.Len); metadata = @{}; effects = @(); markers = @(); enabled = $true } }
            else {
                $prod = $d.Xml.mlt.SelectSingleNode("*[@id='$($it.Node.producer)']"); $res = Get-KdpProp $prod 'resource'
                if ((Get-KdpProp $prod 'mlt_service') -eq 'timewarp') { $res = Get-KdpProp $prod 'warp_resource' }
                $full = if ($res -and -not [IO.Path]::IsPathRooted($res) -and $res -notmatch '^0x') { Join-Path ($d.Root -replace '/', '\') $res } else { $res }
                $mr = if ($full -and (Test-Path $full -ErrorAction SilentlyContinue)) { [ordered]@{ 'OTIO_SCHEMA' = 'ExternalReference.1'; target_url = ([Uri]$full).AbsoluteUri; available_range = $null; metadata = @{} } } else { [ordered]@{ 'OTIO_SCHEMA' = 'MissingReference.1'; metadata = @{}; available_range = $null } }
                $children += [ordered]@{ 'OTIO_SCHEMA' = 'Clip.2'; name = (Get-KdpProp $prod 'kdenlive:clipname'); source_range = (TR (ConvertTo-KdpFrames $d $it.Node.in) $it.Len); media_references = [ordered]@{ DEFAULT_MEDIA = $mr }; active_media_reference_key = 'DEFAULT_MEDIA'; metadata = @{ kdenlive = @{ binId = (Get-KdpProp $it.Node 'kdenlive:id') } }; effects = @(); markers = @(); enabled = $true }
            }
            $pos += $it.Len
        }
        $tracks += [ordered]@{ 'OTIO_SCHEMA' = 'Track.1'; name = $t.Name; kind = $(if ($t.Audio) { 'Audio' } else { 'Video' }); children = $children; source_range = $null; metadata = @{}; effects = @(); markers = @(); enabled = $true }
    }
    $tl = [ordered]@{ 'OTIO_SCHEMA' = 'Timeline.1'; name = [IO.Path]::GetFileNameWithoutExtension($d.Path); global_start_time = $null; metadata = @{}; tracks = [ordered]@{ 'OTIO_SCHEMA' = 'Stack.1'; name = 'tracks'; children = $tracks; source_range = $null; metadata = @{}; effects = @(); markers = @(); enabled = $true } }
    [IO.File]::WriteAllText($file, (ConvertTo-KdpJsonValue -v $tl -ind ''), (New-Object Text.UTF8Encoding($false)))
}
# Import an OTIO timeline into the current sequence: media get added to the bin, clips placed on
# tracks V1.. / A1.. in OTIO order (tracks are added when missing). Gaps and clips only.
function Import-KdpOtio([KdpDoc]$d, [string]$file, [double]$at = 0) {
    $j = Get-Content $file -Raw -Encoding UTF8 | ConvertFrom-Json
    $stack = $j.tracks; $vIdx = 0; $aIdx = 0; $placed = 0
    $binByUrl = @{}
    foreach ($tr in $stack.children) {
        $isAudio = $tr.kind -eq 'Audio'
        if ($isAudio) { $aIdx++; $tn = "A$aIdx" } else { $vIdx++; $tn = "V$vIdx" }
        while (-not (Get-KdpTracks $d | Where-Object Name -eq $tn)) { [void](Add-KdpTrack $d -Audio:$isAudio) }
        $pos = 0.0
        foreach ($ch in $tr.children) {
            $sr = $ch.source_range; $durS = [double]$sr.duration.value / [double]$sr.duration.rate
            if ($ch.OTIO_SCHEMA -like 'Clip*') {
                $ref = $null
                if ($ch.PSObject.Properties['media_references']) { $ref = $ch.media_references.($ch.active_media_reference_key) } elseif ($ch.PSObject.Properties['media_reference']) { $ref = $ch.media_reference }
                if ($ref -and $ref.target_url) {
                    $path = ([Uri]$ref.target_url).LocalPath
                    $ok = (Test-Path $path) -and ([IO.Path]::GetExtension($path).ToLower() -notin '.kdenlivetitle', '.kdenlive', '.mlt', '')
                    if ($ok -and -not $binByUrl.ContainsKey($path)) { try { $binByUrl[$path] = (Add-KdpMedia $d $path).BinId } catch { $ok = $false } }
                    if ($ok -and $binByUrl.ContainsKey($path)) {
                        $inS = [double]$sr.start_time.value / [double]$sr.start_time.rate
                        [void](Add-KdpClipToTimeline $d $binByUrl[$path] $tn ($at + $pos) $inS $durS -Overwrite)
                        $placed++
                    }
                }
            }
            $pos += $durS
        }
    }
    return $placed
}
