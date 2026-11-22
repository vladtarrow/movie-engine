# kdp-core.ps1 - edit Kdenlive 26.08 project files (format 1.1) without the GUI.
# Dot-source this file. All times given to public functions are seconds (double) unless the
# parameter name ends with "Frames". Track names follow Kdenlive: V1 (lowest video), V2 ...,
# A1 (audio track nearest the video tracks), A2 ...
# Every mutating function changes the in-memory document; call Save-Kdp to write it.

$script:KdpEngine = Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot 'kd-state.ps1')
$script:KdpHome = [KdPath]::Long((Split-Path $script:KdpEngine -Parent))     # the folder that gets copied to another computer
$script:KdpBin = Join-Path $script:KdpEngine 'Kdenlive\kdenlive-26.08.3_standalone\bin'

class KdpDoc { [xml]$Xml; [string]$Path; [double]$Fps; [string]$Root; [string]$SeqId; [string]$FileRoot; [string]$LoadedHash }

# ---------- load / save ----------
function Open-Kdp([string]$Path) {
    $d = [KdpDoc]::new()
    $d.Path = [KdPath]::Long((Resolve-Path $Path).Path)
    $d.Xml = New-Object System.Xml.XmlDocument
    $d.Xml.PreserveWhitespace = $false
    $d.Xml.Load($d.Path)
    $p = $d.Xml.mlt.profile
    $d.Fps = [double]$p.frame_rate_num / [double]$p.frame_rate_den
    $d.LoadedHash = Get-KdHash $d.Path
    $d.FileRoot = $d.Xml.mlt.GetAttribute('root')
    $d.Root = [KdPath]::Long((Resolve-KdpRoot $d)) -replace '\\', '/'
    Repair-KdpPaths $d
    return $d
}
# Kdenlive stores the project folder as an absolute 'root'. After the folder was copied or moved that value is
# stale, and if the old folder still exists Kdenlive and melt would silently use the OLD media.
# The project's own folder wins whenever the relative media resolve from it.
function Resolve-KdpRoot([KdpDoc]$d) {
    $here = (Split-Path $d.Path -Parent) -replace '\\', '/'
    if (-not $d.FileRoot -or $d.FileRoot.TrimEnd('/', '\') -eq $here) { return $here }
    $relative = @()
    foreach ($p in $d.Xml.mlt.SelectNodes("producer/property[@name='resource']|chain/property[@name='resource']")) {
        $r = $p.InnerText
        if ($r -match '^\.\.?/' -or $r -match '^[^:/\\]+/') { $relative += $r; if ($relative.Count -ge 40) { break } }
    }
    if (-not $relative.Count -or -not (Test-Path -LiteralPath $d.FileRoot)) { return $here }
    foreach ($r in $relative) { if (Test-Path -LiteralPath (Join-Path $here ($r -replace '%.*$', ''))) { return $here } }
    return $d.FileRoot
}
# Subtitle file of a sequence, as KdenliveDoc::subTitlePath names it:
# <project>.kdenlive.ass for the main sequence, <project>.kdenlive{uuid}.ass for the others.
function Get-KdpAssPath([KdpDoc]$d, $seqNode) {
    if (-not $seqNode) { $seqNode = Get-KdpSequence $d }
    $uuid = Get-KdpProp $seqNode 'kdenlive:uuid'
    $main = Get-KdpProp $d.Xml.mlt.SelectSingleNode("playlist[@id='main_bin']") 'kdenlive:docproperties.uuid'
    $suffix = if ($uuid -and $main -and $uuid -ne $main) { $uuid } else { '' }
    Join-Path (Split-Path $d.Path -Parent) ([IO.Path]::GetFileName($d.Path) + $suffix + '.ass')
}
# The subtitle filter needs an absolute path; point it at the file next to the project, wherever that is now.
function Repair-KdpPaths([KdpDoc]$d) {
    foreach ($f in $d.Xml.mlt.SelectNodes("tractor/filter[property[@name='mlt_service']='avfilter.subtitles']")) {
        $ass = Get-KdpAssPath $d $f.ParentNode
        if (Test-Path -LiteralPath $ass) { Set-KdpProp $f 'av.filename' ($ass -replace '\\', '/') }
    }
}
# melt reads a temporary copy with today's absolute paths, so it can never pick up media of an old location.
function New-KdpMeltCopy([KdpDoc]$d) {
    $file = Join-Path ([IO.Path]::GetTempPath()) ('kdp-render-' + [guid]::NewGuid().ToString('N') + '.kdenlive')
    # PreserveWhitespace: without it Save indents an empty <property name="resource"></property> into a line break,
    # and kdenlivetitle takes that whitespace for a file name and draws nothing (titles were missing in frame/preview).
    $x = New-Object System.Xml.XmlDocument; $x.PreserveWhitespace = $true; $x.LoadXml($d.Xml.OuterXml)
    $x.DocumentElement.SetAttribute('root', $d.Root)
    $x.Save($file)
    return $file
}
function Save-Kdp([KdpDoc]$d, [string]$Path) {
    if (-not $Path) { $Path = $d.Path }
    $Path = [IO.Path]::GetFullPath($Path)
    Update-KdpDurations $d
    $d.Xml.mlt.SetAttribute('root', $d.Root)
    $tmp = "$Path.kdp-tmp"
    $settings = New-Object System.Xml.XmlWriterSettings
    $settings.Indent = $true; $settings.IndentChars = ' '
    $settings.Encoding = New-Object System.Text.UTF8Encoding($false)
    $w = [System.Xml.XmlWriter]::Create($tmp, $settings)
    $d.Xml.Save($w); $w.Close()
    $hash = Get-KdHash $tmp
    # stamp first: the watcher may see the new file immediately
    Set-KdWriteStamp $Path $hash
    Move-KdpFileInto $tmp $Path
    $d.LoadedHash = $hash
}
# Replace in one step (Move-Item -Force deletes first), retrying while Kdenlive or the watcher reads the file.
function Move-KdpFileInto([string]$tmp, [string]$path) {
    for ($i = 1; ; $i++) {
        try {
            if ([IO.File]::Exists($path)) { [IO.File]::Replace($tmp, $path, [NullString]::Value) } else { [IO.File]::Move($tmp, $path) }
            return
        } catch { if ($i -ge 20) { throw }; Start-Sleep -Milliseconds 150 }
    }
}

# ---------- time ----------
function ConvertTo-KdpFrames([KdpDoc]$d, $t) {
    if ($null -eq $t -or "$t" -eq '') { return $null }
    $s = "$t"
    if ($s -match '^(\d+):(\d+):(\d+(?:\.\d+)?)$') { return [int][math]::Round(([double]$matches[1] * 3600 + [double]$matches[2] * 60 + [double]::Parse($matches[3], [cultureinfo]::InvariantCulture)) * $d.Fps) }
    if ($s -match '^(\d+):(\d+):(\d+):(\d+)$') { return [int]([double]$matches[1] * 3600 * $d.Fps + [double]$matches[2] * 60 * $d.Fps + [double]$matches[3] * $d.Fps + [int]$matches[4]) }
    return [int]$s
}
function ConvertTo-KdpTime([KdpDoc]$d, [int]$frames) {
    $sec = $frames / $d.Fps
    $h = [math]::Floor($sec / 3600); $m = [math]::Floor(($sec - $h * 3600) / 60); $s = $sec - $h * 3600 - $m * 60
    return ('{0:00}:{1:00}:{2}' -f $h, $m, $s.ToString('00.000', [cultureinfo]::InvariantCulture))
}
function SecToFrames([KdpDoc]$d, [double]$sec) { [int][math]::Round($sec * $d.Fps) }

# ---------- generic xml helpers ----------
function Get-KdpProp($node, [string]$name) { $p = $node.SelectSingleNode("property[@name='$name']"); if ($p) { $p.InnerText } else { $null } }
function Set-KdpProp($node, [string]$name, $value) {
    $p = $node.SelectSingleNode("property[@name='$name']")
    if (-not $p) {
        $p = $node.OwnerDocument.CreateElement('property'); $p.SetAttribute('name', $name)
        $firstNonProp = $node.SelectSingleNode('*[not(self::property)]')
        if ($firstNonProp) { [void]$node.InsertBefore($p, $firstNonProp) } else { [void]$node.AppendChild($p) }
    }
    $p.InnerText = "$value"
}
function Remove-KdpProp($node, [string]$name) { $p = $node.SelectSingleNode("property[@name='$name']"); if ($p) { [void]$node.RemoveChild($p) } }
function New-KdpUuid { '{' + [guid]::NewGuid().ToString() + '}' }
function New-KdpId([KdpDoc]$d, [string]$prefix) {
    $n = 0; while ($d.Xml.SelectSingleNode("//*[@id='$prefix$n']")) { $n++ }; "$prefix$n"
}

# ---------- sequence and tracks ----------
function Get-KdpSequences([KdpDoc]$d) {
    foreach ($t in $d.Xml.mlt.SelectNodes('tractor')) { if ((Get-KdpProp $t 'kdenlive:producer_type') -eq '17') { [pscustomobject]@{ Uuid = $t.id; Name = (Get-KdpProp $t 'kdenlive:clipname'); BinId = (Get-KdpProp $t 'kdenlive:id'); Main = ($t.id -eq (Get-KdpProp $d.Xml.mlt.SelectSingleNode("playlist[@id='main_bin']") 'kdenlive:docproperties.uuid')); Node = $t } } }
}
# Select which sequence later calls work on (name, uuid or bin id); empty = the main/active one.
function Select-KdpSequence([KdpDoc]$d, [string]$ref) {
    if (-not $ref) { $d.SeqId = $null; return }
    $s = Get-KdpSequences $d | Where-Object { $_.Uuid -eq $ref -or $_.Name -eq $ref -or $_.BinId -eq $ref } | Select-Object -First 1
    if (-not $s) { throw "Sequence '$ref' not found. Sequences: " + ((Get-KdpSequences $d | ForEach-Object Name) -join ', ') }
    $d.SeqId = $s.Uuid
}
function Get-KdpSequence([KdpDoc]$d) {
    # a sequence tractor is identified by its kdenlive:uuid property; its element id is usually the same
    # uuid but Kdenlive also accepts other ids (seen: "tractor3")
    if ($d.SeqId) { $t = $d.Xml.mlt.SelectSingleNode("tractor[@id='$($d.SeqId)']"); if ($t) { return $t } }
    $uuid = $null
    foreach ($p in $d.Xml.mlt.SelectNodes("playlist[@id='main_bin']/property[@name='kdenlive:docproperties.activetimeline']")) { $uuid = $p.InnerText }
    if ($uuid) {
        $t = $d.Xml.mlt.SelectSingleNode("tractor[@id='$uuid']"); if ($t) { return $t }
        $t = $d.Xml.mlt.SelectSingleNode("tractor[property[@name='kdenlive:uuid']='$uuid']"); if ($t) { return $t }
    }
    foreach ($t in $d.Xml.mlt.SelectNodes('tractor')) { if ((Get-KdpProp $t 'kdenlive:producer_type') -eq '17') { return $t } }
    throw 'No timeline sequence found (format 1.1 expected).'
}
function Get-KdpTracks([KdpDoc]$d) {
    $seq = Get-KdpSequence $d
    $all = @()
    $i = 0
    foreach ($tr in $seq.SelectNodes('track')) {
        $i++
        $tt = $d.Xml.mlt.SelectSingleNode("tractor[@id='$($tr.producer)']")
        if (-not $tt) { continue }   # black background producer
        $audio = (Get-KdpProp $tt 'kdenlive:audio_track') -eq '1'
        $pls = @($tt.SelectNodes('track') | ForEach-Object { $d.Xml.mlt.SelectSingleNode("playlist[@id='$($_.producer)']") })
        $all += [pscustomobject]@{ Index = $i - 1; Tractor = $tt; SeqTrack = $tr; Audio = $audio; Playlists = $pls; Name = ''; Label = (Get-KdpProp $tt 'kdenlive:track_name') }
    }
    $aud = @($all | Where-Object Audio); $vid = @($all | Where-Object { -not $_.Audio })
    for ($k = 0; $k -lt $aud.Count; $k++) { $aud[$k].Name = 'A' + ($aud.Count - $k) }
    for ($k = 0; $k -lt $vid.Count; $k++) { $vid[$k].Name = 'V' + ($k + 1) }
    return $all
}
function Get-KdpTrack([KdpDoc]$d, [string]$name) {
    $t = Get-KdpTracks $d | Where-Object { $_.Name -eq $name.ToUpper() }
    if (-not $t) { throw "Track $name not found. Tracks: " + ((Get-KdpTracks $d | ForEach-Object Name) -join ', ') }
    return $t
}

# ---------- playlist model ----------
# Items: @{ Kind='blank'|'entry'; Len=frames; Node=<entry> }
function Read-KdpItems([KdpDoc]$d, $pl) {
    $items = New-Object System.Collections.ArrayList
    foreach ($c in $pl.ChildNodes) {
        if ($c.NodeType -ne 'Element') { continue }
        if ($c.Name -eq 'blank') { [void]$items.Add(@{ Kind = 'blank'; Len = (ConvertTo-KdpFrames $d $c.length); Node = $null }) }
        elseif ($c.Name -eq 'entry') { $in = ConvertTo-KdpFrames $d $c.in; $out = ConvertTo-KdpFrames $d $c.out; [void]$items.Add(@{ Kind = 'entry'; Len = ($out - $in + 1); Node = $c }) }
    }
    return , $items
}
function Write-KdpItems([KdpDoc]$d, $pl, $items) {
    foreach ($c in @($pl.ChildNodes)) { if ($c.NodeType -eq 'Element' -and ($c.Name -eq 'blank' -or $c.Name -eq 'entry')) { [void]$pl.RemoveChild($c) } }
    # merge adjacent blanks, drop zero-length and trailing blanks
    $norm = New-Object System.Collections.ArrayList
    foreach ($it in $items) {
        if ($it.Len -le 0) { continue }
        if ($it.Kind -eq 'blank' -and $norm.Count -gt 0 -and $norm[$norm.Count - 1].Kind -eq 'blank') { $norm[$norm.Count - 1].Len += $it.Len; continue }
        [void]$norm.Add($it)
    }
    while ($norm.Count -gt 0 -and $norm[$norm.Count - 1].Kind -eq 'blank') { $norm.RemoveAt($norm.Count - 1) }
    foreach ($it in $norm) {
        if ($it.Kind -eq 'blank') { $b = $d.Xml.CreateElement('blank'); $b.SetAttribute('length', (ConvertTo-KdpTime $d $it.Len)); [void]$pl.AppendChild($b) }
        else { [void]$pl.AppendChild($it.Node) }
    }
}
function Get-KdpClips([KdpDoc]$d) {
    foreach ($t in Get-KdpTracks $d) {
        $sub = 0
        foreach ($pl in $t.Playlists) {
            $pos = 0
            foreach ($it in (Read-KdpItems $d $pl)) {
                if ($it.Kind -eq 'entry') {
                    $e = $it.Node
                    $prod = $d.Xml.mlt.SelectSingleNode("*[@id='$($e.producer)']")
                    $binId = Get-KdpProp $e 'kdenlive:id'
                    [pscustomobject]@{
                        Id = "$($t.Name)@$([math]::Round($pos / $d.Fps, 3))"; Track = $t.Name; Sub = $sub
                        Start = [math]::Round($pos / $d.Fps, 3); End = [math]::Round(($pos + $it.Len) / $d.Fps, 3); Dur = [math]::Round($it.Len / $d.Fps, 3)
                        StartFrames = $pos; LenFrames = $it.Len
                        In = [math]::Round((ConvertTo-KdpFrames $d $e.in) / $d.Fps, 3); BinId = $binId
                        Name = $(if ($prod) { Get-KdpProp $prod 'kdenlive:clipname' } else { $null })
                        Resource = $(if ($prod) { Get-KdpProp $prod 'resource' } else { $null })
                        Effects = @($e.SelectNodes('filter') | ForEach-Object { $k = Get-KdpProp $_ 'kdenlive_id'; if (-not $k) { $k = Get-KdpProp $_ 'mlt_service' }; $k })
                        Node = $e
                    }
                }
                $pos += $it.Len
            }
            $sub++
        }
    }
}

# Find clip on track covering time (seconds)
function Find-KdpClip([KdpDoc]$d, [string]$track, [double]$at) {
    $f = SecToFrames $d $at
    $all = @(Get-KdpClips $d | Where-Object { $_.Track -eq $track.ToUpper() -and $f -ge $_.StartFrames -and $f -lt ($_.StartFrames + $_.LenFrames) })
    $c = $all | Where-Object Sub -eq 0 | Select-Object -First 1
    if (-not $c) {
        if ($all | Where-Object Sub -eq 1) { throw "The clip on $track at $at s is the second half of a crossfade; remove the mix first (kdp.ps1 unmix -Track $track -At $at)." }
        throw "No clip on $track at $at s"
    }
    return $c
}

# Refuse edits that would break a same-track crossfade: the earlier clip of a mix ends inside it.
function Assert-KdpNotMixed([KdpDoc]$d, $clip) {
    $t = Get-KdpTrack $d $clip.Track
    foreach ($tr in $t.Tractor.SelectNodes("transition[property[@name='kdenlive:mixcut']]")) {
        $mIn = ConvertTo-KdpFrames $d $tr.in; $mOut = ConvertTo-KdpFrames $d $tr.out
        $end = $clip.StartFrames + $clip.LenFrames
        if ($end -ge $mIn -and $end -le $mOut + 1 -and $clip.Sub -eq 0) { throw "The clip on $($clip.Track) at $($clip.Start) s is the first half of a crossfade; remove the mix first (kdp.ps1 unmix -Track $($clip.Track) -At $([math]::Round($mIn / $d.Fps,3)))." }
    }
}
# Place an existing <entry> node on a track at frame position; requires free space unless $Overwrite.
function Set-KdpEntryAt([KdpDoc]$d, $track, $entry, [int]$posF, [int]$lenF, [switch]$Overwrite, [switch]$Insert, [int]$Sub = 0) {
    $pl = $track.Playlists[$Sub]
    $items = Read-KdpItems $d $pl
    if ($Insert) {
        if ($track.Tractor.SelectSingleNode("transition[property[@name='kdenlive:mixcut']]")) { throw "Insert on $($track.Name) would break its crossfades; unmix first, or use space-insert and then add." }
        # ripple insert: split at pos, push everything after
        $res = New-Object System.Collections.ArrayList; $pos = 0; $placed = $false
        foreach ($it in $items) {
            if (-not $placed -and $posF -ge $pos -and $posF -lt $pos + $it.Len) {
                if ($it.Kind -eq 'entry' -and $posF -gt $pos) { throw 'Insert point is inside a clip; split it first or choose a clip boundary.' }
                if ($it.Kind -eq 'blank') { [void]$res.Add(@{ Kind = 'blank'; Len = $posF - $pos; Node = $null }); [void]$res.Add(@{ Kind = 'entry'; Len = $lenF; Node = $entry }); [void]$res.Add(@{ Kind = 'blank'; Len = $pos + $it.Len - $posF; Node = $null }) }
                else { [void]$res.Add(@{ Kind = 'entry'; Len = $lenF; Node = $entry }); [void]$res.Add($it) }
                $placed = $true
            } else { [void]$res.Add($it) }
            $pos += $it.Len
        }
        if (-not $placed) { if ($posF -gt $pos) { [void]$res.Add(@{ Kind = 'blank'; Len = $posF - $pos; Node = $null }) }; [void]$res.Add(@{ Kind = 'entry'; Len = $lenF; Node = $entry }) }
        Write-KdpItems $d $pl $res; return
    }
    # overwrite / place into free space: build a frame map of segments
    $segs = New-Object System.Collections.ArrayList; $pos = 0
    foreach ($it in $items) { [void]$segs.Add(@{ S = $pos; E = $pos + $it.Len; It = $it }); $pos += $it.Len }
    $end = $posF + $lenF
    foreach ($sg in $segs) {
        if ($sg.It.Kind -eq 'entry' -and $sg.S -lt $end -and $sg.E -gt $posF -and -not $Overwrite) {
            throw ("Space {0}-{1} s on {2} is occupied by a clip at {3} s. Use -Overwrite, -Insert, or another position." -f ($posF / $d.Fps), ($end / $d.Fps), $track.Name, ($sg.S / $d.Fps))
        }
    }
    $res = New-Object System.Collections.ArrayList
    foreach ($sg in $segs) {
        if ($sg.E -le $posF -or $sg.S -ge $end) { [void]$res.Add(@{ S = $sg.S; It = $sg.It }); continue }
        # overlapping segment: keep the parts outside [posF,end)
        if ($sg.S -lt $posF) {
            if ($sg.It.Kind -eq 'blank') { [void]$res.Add(@{ S = $sg.S; It = @{ Kind = 'blank'; Len = $posF - $sg.S; Node = $null } }) }
            else { $rightPiece = if ($sg.E -gt $end) { $sg.It.Node.Clone() } else { $null }; $n = $sg.It.Node; $in = ConvertTo-KdpFrames $d $n.in; $n.SetAttribute('out', (ConvertTo-KdpTime $d ($in + $posF - $sg.S - 1))); [void]$res.Add(@{ S = $sg.S; It = @{ Kind = 'entry'; Len = $posF - $sg.S; Node = $n } }) }
        }
        if ($sg.E -gt $end) {
            if ($sg.It.Kind -eq 'blank') { [void]$res.Add(@{ S = $end; It = @{ Kind = 'blank'; Len = $sg.E - $end; Node = $null } }) }
            else { $n = if ($sg.S -lt $posF) { $rightPiece } else { $sg.It.Node }; $in = ConvertTo-KdpFrames $d $n.in; $n.SetAttribute('in', (ConvertTo-KdpTime $d ($in + $end - $sg.S))); [void]$res.Add(@{ S = $end; It = @{ Kind = 'entry'; Len = $sg.E - $end; Node = $n } }) }
        }
    }
    [void]$res.Add(@{ S = $posF; It = @{ Kind = 'entry'; Len = $lenF; Node = $entry } })
    $sorted = $res | Sort-Object { $_.S }
    $out = New-Object System.Collections.ArrayList; $cur = 0
    foreach ($r in $sorted) { if ($r.S -gt $cur) { [void]$out.Add(@{ Kind = 'blank'; Len = $r.S - $cur; Node = $null }) }; [void]$out.Add($r.It); $cur = $r.S + $r.It.Len }
    Write-KdpItems $d $pl $out
}

function Remove-KdpEntry([KdpDoc]$d, $track, $entry, [switch]$Ripple) {
    if ($Ripple -and $track.Tractor.SelectSingleNode("transition[property[@name='kdenlive:mixcut']]")) { throw "Ripple delete on $($track.Name) would break its crossfades; unmix first." }
    foreach ($pl in $track.Playlists) {
        $items = Read-KdpItems $d $pl; $found = $false
        $res = New-Object System.Collections.ArrayList
        foreach ($it in $items) {
            if ($it.Kind -eq 'entry' -and [object]::ReferenceEquals($it.Node, $entry)) { $found = $true; if (-not $Ripple) { [void]$res.Add(@{ Kind = 'blank'; Len = $it.Len; Node = $null }) } }
            else { [void]$res.Add($it) }
        }
        if ($found) { Write-KdpItems $d $pl $res; return }
    }
    throw 'Entry not found on track.'
}

# ---------- durations (keep tractor/sequence lengths consistent for melt) ----------
function Update-KdpDurations([KdpDoc]$d) {
    # every sequence, in document order (nested sequences are defined before their users)
    $saved = $d.SeqId
    try { foreach ($s in @(Get-KdpSequences $d)) { $d.SeqId = $s.Uuid; Update-KdpSequenceDuration $d } }
    finally { $d.SeqId = $saved }
}
function Update-KdpSequenceDuration([KdpDoc]$d) {
    $seq = Get-KdpSequence $d
    $max = 0
    foreach ($t in Get-KdpTracks $d) {
        $tmax = 0
        foreach ($pl in $t.Playlists) { $sum = 0; foreach ($it in (Read-KdpItems $d $pl)) { $sum += $it.Len }; if ($sum -gt $tmax) { $tmax = $sum } }
        if ($tmax -gt 0) { $t.Tractor.SetAttribute('out', (ConvertTo-KdpTime $d ($tmax - 1))) } else { $t.Tractor.RemoveAttribute('out') }
        if ($tmax -gt $max) { $max = $tmax }
    }
    if ($max -lt 1) { $max = 1 }
    $outT = ConvertTo-KdpTime $d ($max - 1)
    $seq.SetAttribute('out', $outT)
    Set-KdpProp $seq 'kdenlive:duration' (ConvertTo-KdpTime $d $max)
    Set-KdpProp $seq 'kdenlive:maxduration' $max
    $uuid = $seq.id
    foreach ($e in $d.Xml.mlt.SelectNodes("playlist[@id='main_bin']/entry[@producer='$uuid']")) { $e.SetAttribute('out', $outT) }
    # timeline uses of this sequence inside other sequences carry its length
    foreach ($e in $d.Xml.mlt.SelectNodes("playlist[@id!='main_bin']/entry[@producer='$uuid']")) { Set-KdpProp $e 'kdenlive:maxduration' $max }
    foreach ($pt in $d.Xml.mlt.SelectNodes('tractor')) {
        if ((Get-KdpProp $pt 'kdenlive:projectTractor') -eq '1') {
            $pt.SetAttribute('out', $outT)
            foreach ($tr in $pt.SelectNodes("track[@producer='$uuid']")) { $tr.SetAttribute('out', $outT) }
        }
    }
}

# ---------- bin ----------
function Get-KdpBinClips([KdpDoc]$d) {
    foreach ($e in $d.Xml.mlt.SelectNodes("playlist[@id='main_bin']/entry")) {
        $p = $d.Xml.mlt.SelectSingleNode("*[@id='$($e.producer)']")
        if (-not $p) { continue }
        $len = Get-KdpProp $p 'length'; if (-not $len) { $len = Get-KdpProp $p 'kdenlive:maxduration' }
        $svc = Get-KdpProp $p 'mlt_service'; if ($p.Name -eq 'tractor') { $svc = 'sequence' }
        [pscustomobject]@{ BinId = Get-KdpProp $p 'kdenlive:id'; ProducerId = $p.id; Name = Get-KdpProp $p 'kdenlive:clipname'; Type = Get-KdpProp $p 'kdenlive:clip_type'; Service = $svc; Resource = Get-KdpProp $p 'resource'; Length = $len; Folder = Get-KdpProp $p 'kdenlive:folderid'; Node = $p }
    }
}
function Get-KdpBinClip([KdpDoc]$d, [string]$ref) {
    $all = @(Get-KdpBinClips $d)
    $c = $all | Where-Object { $_.BinId -eq $ref -or $_.ProducerId -eq $ref } | Select-Object -First 1
    if ($c) { return $c }
    $byName = @($all | Where-Object { $_.Name -eq $ref })
    if ($byName.Count -gt 1) { throw "Several bin clips are named '$ref' (ids $(($byName | ForEach-Object BinId) -join ', ')); use the bin id." }
    if (-not $byName) { throw "Bin clip '$ref' not found" }
    return $byName[0]
}
function Get-KdpNextBinId([KdpDoc]$d) {
    $max = 1
    foreach ($p in $d.Xml.SelectNodes("//property[@name='kdenlive:id']")) { $v = 0; if ([int]::TryParse($p.InnerText, [ref]$v) -and $v -gt $max) { $max = $v } }
    foreach ($p in $d.Xml.SelectNodes("//property[starts-with(@name,'kdenlive:folder.')]")) { $parts = $p.GetAttribute('name').Split('.'); $v = 0; if ([int]::TryParse($parts[-1], [ref]$v) -and $v -gt $max) { $max = $v } }
    return $max + 1
}
function Get-KdpRelPath([KdpDoc]$d, [string]$file) {
    $full = [KdPath]::Long((Resolve-Path $file).Path)
    $root = $d.Root -replace '/', '\'
    $u1 = New-Object System.Uri(($root.TrimEnd('\') + '\'))
    $u2 = New-Object System.Uri($full)
    return [System.Uri]::UnescapeDataString($u1.MakeRelativeUri($u2).ToString())
}
function Get-KdpMediaInfo([string]$file) {
    $j = & (Join-Path $script:KdpBin 'ffprobe.exe') -v error -print_format json -show_streams -show_format $file | Out-String | ConvertFrom-Json
    $v = @($j.streams | Where-Object { $_.codec_type -eq 'video' -and -not ($_.disposition.attached_pic -eq 1) })
    $a = @($j.streams | Where-Object codec_type -eq 'audio')
    [pscustomobject]@{ Duration = [double]::Parse($j.format.duration, [cultureinfo]::InvariantCulture); VideoIndex = $(if ($v) { $v[0].index } else { -1 }); AudioIndex = $(if ($a) { $a[0].index } else { -1 }); Width = $(if ($v) { $v[0].width } else { 0 }); Height = $(if ($v) { $v[0].height } else { 0 }); Streams = $j.streams.Count }
}
# Adds a bin clip node + main_bin entry. $kind: av|image|color|title|other
function Add-KdpBinProducer([KdpDoc]$d, [string]$elementName, [string]$idPrefix, [hashtable]$props, [int]$lenF, [string]$folderId = '-1') {
    $binId = Get-KdpNextBinId $d
    $p = $d.Xml.CreateElement($elementName)
    $p.SetAttribute('id', (New-KdpId $d $idPrefix))
    $p.SetAttribute('in', (ConvertTo-KdpTime $d 0)); $p.SetAttribute('out', (ConvertTo-KdpTime $d ($lenF - 1)))
    foreach ($k in $props.Keys) { Set-KdpProp $p $k $props[$k] }
    Set-KdpProp $p 'kdenlive:folderid' $folderId
    Set-KdpProp $p 'kdenlive:id' $binId
    Set-KdpProp $p 'kdenlive:control_uuid' (New-KdpUuid)
    $bin = $d.Xml.mlt.SelectSingleNode("playlist[@id='main_bin']")
    [void]$d.Xml.mlt.InsertBefore($p, $d.Xml.mlt.SelectSingleNode('playlist'))
    $e = $d.Xml.CreateElement('entry'); $e.SetAttribute('producer', $p.id); $e.SetAttribute('in', $p.in); $e.SetAttribute('out', $p.out)
    $firstEntry = $bin.SelectSingleNode('entry')
    if ($firstEntry) { [void]$bin.InsertBefore($e, $firstEntry) } else { [void]$bin.AppendChild($e) }
    return Get-KdpBinClip $d "$binId"
}
# Kdenlive's clip hash (ProjectClip::getFileHash): MD5 of the whole file, or of the first and
# last 1,000,000 bytes when the file is larger than 2,000,000 bytes.
function Get-KdpFileHash([string]$file) {
    $fs = [IO.File]::OpenRead($file)
    try {
        if ($fs.Length -gt 2000000) {
            $buf = New-Object byte[] 2000000
            [void]$fs.Read($buf, 0, 1000000); [void]$fs.Seek(-1000000, 'End'); [void]$fs.Read($buf, 1000000, 1000000)
        } else { $buf = New-Object byte[] $fs.Length; [void]$fs.Read($buf, 0, $buf.Length) }
    } finally { $fs.Close() }
    $md5 = [Security.Cryptography.MD5]::Create()
    return (($md5.ComputeHash($buf) | ForEach-Object { $_.ToString('x2') }) -join '')
}
function Add-KdpMedia([KdpDoc]$d, [string]$file, [string]$name, [double]$imageSeconds = 5, [string]$folderId = '-1') {
    $ext = [IO.Path]::GetExtension($file).ToLower()
    $rel = Get-KdpRelPath $d $file
    if (-not $name) { $name = [IO.Path]::GetFileName($file) }
    $hash = Get-KdpFileHash $file; $size = (Get-Item $file).Length
    if ($ext -in '.json', '.rawr', '.lottie') { return Add-KdpAnimation $d $file $name }
    if ($ext -in '.png', '.jpg', '.jpeg', '.bmp', '.gif', '.webp', '.tif', '.tiff', '.svg') {
        $lenF = SecToFrames $d $imageSeconds
        $svc = if ($ext -eq '.svg') { 'qimage' } else { 'qimage' }
        return Add-KdpBinProducer $d 'producer' 'producer' ([ordered]@{ length = $lenF; eof = 'pause'; resource = $rel; ttl = 25; aspect_ratio = 1; seekable = 1; mlt_service = $svc; 'kdenlive:clipname' = $name; 'kdenlive:duration' = $lenF; 'kdenlive:clip_type' = 2; 'kdenlive:file_size' = $size; 'kdenlive:file_hash' = $hash }) $lenF $folderId
    }
    $mi = Get-KdpMediaInfo $file
    $lenF = [int][math]::Floor($mi.Duration * $d.Fps + 0.01)
    # kdenlive:clip_type in the XML is the A/V state: 0 audio+video, 1 audio only, 2 video only (images/colour/titles too)
    $type = if ($mi.VideoIndex -ge 0 -and $mi.AudioIndex -ge 0) { 0 } elseif ($mi.VideoIndex -ge 0) { 2 } else { 1 }
    return Add-KdpBinProducer $d 'chain' 'chain' ([ordered]@{ length = $lenF; eof = 'pause'; resource = $rel; mlt_service = 'avformat-novalidate'; seekable = 1; audio_index = $mi.AudioIndex; video_index = $mi.VideoIndex; 'kdenlive:clipname' = $name; 'kdenlive:clip_type' = $type; 'kdenlive:file_size' = $size; 'kdenlive:file_hash' = $hash; mute_on_pause = 0 }) $lenF $folderId
}
function Add-KdpColor([KdpDoc]$d, [string]$color, [string]$name, [double]$seconds = 5) {
    # color as #RRGGBB or 0xRRGGBBAA
    if ($color -match '^#([0-9a-fA-F]{6})$') { $color = '0x' + $matches[1] + 'ff' }
    $lenF = SecToFrames $d $seconds
    if (-not $name) { $name = 'Color ' + $color }
    return Add-KdpBinProducer $d 'producer' 'producer' ([ordered]@{ length = $lenF; eof = 'pause'; resource = $color; aspect_ratio = 1; mlt_service = 'color'; 'kdenlive:clipname' = $name; 'kdenlive:duration' = (ConvertTo-KdpTime $d $lenF); 'kdenlive:clip_type' = 2; mlt_image_format = 'rgb' }) $lenF
}

# True if sequence $outer (uuid) contains sequence $inner anywhere down its nesting.
function Test-KdpSequenceUses([KdpDoc]$d, [string]$outer, [string]$inner, [int]$depth = 0) {
    if ($depth -gt 20) { return $true }
    $t = $d.Xml.mlt.SelectSingleNode("tractor[@id='$outer']"); if (-not $t) { return $false }
    foreach ($tr in $t.SelectNodes('track')) {
        $tt = $d.Xml.mlt.SelectSingleNode("tractor[@id='$($tr.producer)']"); if (-not $tt) { continue }
        foreach ($pt in $tt.SelectNodes('track')) {
            foreach ($e in $d.Xml.mlt.SelectNodes("playlist[@id='$($pt.producer)']/entry")) {
                if ($e.producer -eq $inner) { return $true }
                if ($d.Xml.mlt.SelectSingleNode("tractor[@id='$($e.producer)']") -and (Test-KdpSequenceUses $d $e.producer $inner ($depth + 1))) { return $true }
            }
        }
    }
    return $false
}
# Stills (images, colour, titles, text) can be stretched to any length on the timeline.
function Test-KdpEndless($prod) { (Get-KdpProp $prod 'mlt_service') -in 'color', 'colour', 'qimage', 'pixbuf', 'kdenlivetitle', 'qtext', 'glaxnimate' }
# melt stops an image/colour/title producer at its 'length' even though Kdenlive lets such clips be stretched:
# a timeline entry past it shows the next clip early (verified 2026-11-21: 5 s images used for 8.8 s drifted the cut).
function Expand-KdpEndlessLength([KdpDoc]$d, $prod, [int]$needFrames) {
    if (-not (Test-KdpEndless $prod)) { return }
    $l = Get-KdpProp $prod 'length'; if (-not $l) { return }
    $cur = if ($l -match '^\d+$') { [int]$l } else { ConvertTo-KdpFrames $d $l }
    if ($cur -lt $needFrames) { Set-KdpProp $prod 'length' $needFrames }
}
function Test-KdpHasAudio($prod) {
    if ($prod.Name -eq 'tractor') { return (Get-KdpProp $prod 'kdenlive:sequenceproperties.hasAudio') -ne '0' }
    $svc = Get-KdpProp $prod 'mlt_service'
    if ($svc -notlike 'avformat*' -and $svc -ne 'timewarp' -and $prod.Name -ne 'chain') { return $false }
    $ai = Get-KdpProp $prod 'audio_index'; return ($null -eq $ai -or [int]$ai -ge 0)
}
function Test-KdpHasVideo($prod) {
    if ($prod.Name -eq 'tractor') { return (Get-KdpProp $prod 'kdenlive:sequenceproperties.hasVideo') -ne '0' }
    $svc = Get-KdpProp $prod 'mlt_service'
    if ($svc -notlike 'avformat*' -and $svc -ne 'timewarp' -and $prod.Name -ne 'chain') { return $true }
    $vi = Get-KdpProp $prod 'video_index'; return ($null -eq $vi -or [int]$vi -ge 0)
}
# Timeline instance of a bin clip for a given track type.
function New-KdpInstance([KdpDoc]$d, $binClip, $track, [int]$inF, [int]$outF) {
    $src = $binClip.Node
    $needsCopy = $src.Name -eq 'chain' -or (Get-KdpProp $src 'mlt_service') -like 'avformat*'
    $prodId = $src.id
    if ($needsCopy) {
        $copy = $src.Clone()
        $copy.SetAttribute('id', (New-KdpId $d $(if ($src.Name -eq 'chain') { 'chain' } else { 'producer' })))
        if ($track.Audio) { Set-KdpProp $copy 'set.test_audio' 0; Set-KdpProp $copy 'set.test_image' 1 }
        else { Set-KdpProp $copy 'set.test_audio' 1; Set-KdpProp $copy 'set.test_image' 0 }
        # The copy MUST keep the bin clip's kdenlive:control_uuid: Kdenlive maps timeline clips
        # to bin clips by it and drops clips without it ("without bin reference found and removed").
        [void]$d.Xml.mlt.InsertBefore($copy, $track.Playlists[0])
        $prodId = $copy.id
    }
    $e = $d.Xml.CreateElement('entry')
    $e.SetAttribute('producer', $prodId); $e.SetAttribute('in', (ConvertTo-KdpTime $d $inF)); $e.SetAttribute('out', (ConvertTo-KdpTime $d $outF))
    Set-KdpProp $e 'kdenlive:id' $binClip.BinId
    if ($src.Name -eq 'tractor') { Set-KdpProp $e 'kdenlive:maxduration' (Get-KdpProp $src 'kdenlive:maxduration') }
    return $e
}

# ---------- high-level timeline ops (seconds) ----------
function Add-KdpClipToTimeline([KdpDoc]$d, [string]$bin, [string]$trackName, [double]$at, [double]$in = 0, [double]$dur = -1, [switch]$Overwrite, [switch]$Insert) {
    $bc = Get-KdpBinClip $d $bin
    $t = Get-KdpTrack $d $trackName
    if ($bc.Node.Name -eq 'tractor') {
        Update-KdpDurations $d; $bc = Get-KdpBinClip $d $bin
        $cur = (Get-KdpSequence $d).id
        if ($bc.ProducerId -eq $cur) { throw 'A sequence cannot contain itself.' }
        if (Test-KdpSequenceUses $d $bc.ProducerId $cur) { throw "Sequence '$($bc.Name)' already contains this sequence (cycle)." }
        if ([int](Get-KdpProp $bc.Node 'kdenlive:maxduration') -lt 1) { throw "Sequence '$($bc.Name)' is empty." }
        # MLT needs the nested sequence defined before the sequence that uses it
        $firstOfCur = (Get-KdpTracks $d | Select-Object -First 1).Playlists[0]
        $pos = @($d.Xml.mlt.ChildNodes).IndexOf($bc.Node); $posCur = @($d.Xml.mlt.ChildNodes).IndexOf($firstOfCur)
        if ($pos -gt $posCur) { throw "Sequence '$($bc.Name)' is defined after the current sequence; create nested sequences with kdp.ps1 sequence-add (it places them first)." }
    }
    if ($t.Audio -and -not (Test-KdpHasAudio $bc.Node)) { throw "Clip '$($bc.Name)' has no audio; put it on a video track." }
    if (-not $t.Audio -and -not (Test-KdpHasVideo $bc.Node)) { throw "Clip '$($bc.Name)' is audio-only; put it on an audio track." }
    $inF = SecToFrames $d $in
    $len = if ($bc.Length -match '^\d+$') { [int]$bc.Length } else { (ConvertTo-KdpFrames $d $bc.Length) }
    $avail = $len - $inF
    $lenF = if ($dur -gt 0) { SecToFrames $d $dur } else { $avail }
    if (-not (Test-KdpEndless $bc.Node) -and $lenF -gt $avail) { throw "Requested $dur s but only $([math]::Round($avail / $d.Fps,3)) s of source remain after in=$in." }
    Expand-KdpEndlessLength $d $bc.Node ($inF + $lenF)
    $e = New-KdpInstance $d $bc $t $inF ($inF + $lenF - 1)
    Set-KdpEntryAt $d $t $e (SecToFrames $d $at) $lenF -Overwrite:$Overwrite -Insert:$Insert
    return $e
}
function Move-KdpClip([KdpDoc]$d, [string]$track, [double]$at, [string]$toTrack, [double]$to, [switch]$Overwrite) {
    $c = Find-KdpClip $d $track $at
    Assert-KdpNotMixed $d $c
    if (-not $toTrack) { $toTrack = $track }
    $src = Get-KdpTrack $d $track; $dst = Get-KdpTrack $d $toTrack
    if ($src.Audio -ne $dst.Audio) { throw 'Cannot move between audio and video tracks.' }
    Remove-KdpEntry $d $src $c.Node
    try { Set-KdpEntryAt $d $dst $c.Node (SecToFrames $d $to) $c.LenFrames -Overwrite:$Overwrite }
    catch { Set-KdpEntryAt $d $src $c.Node $c.StartFrames $c.LenFrames; throw }
}
function Set-KdpClipTrim([KdpDoc]$d, [string]$track, [double]$at, $newIn, $newDur, [switch]$KeepEnd) {
    $c = Find-KdpClip $d $track $at
    Assert-KdpNotMixed $d $c
    $t = Get-KdpTrack $d $track
    $e = $c.Node
    $inF = ConvertTo-KdpFrames $d $e.in
    $startF = $c.StartFrames
    if ($null -ne $newIn) { $ni = SecToFrames $d ([double]$newIn); if ($KeepEnd) { $startF += ($ni - $inF); $lenF = $c.LenFrames - ($ni - $inF) } else { $lenF = $c.LenFrames }; $inF = $ni } else { $lenF = $c.LenFrames }
    if ($null -ne $newDur) { $lenF = SecToFrames $d ([double]$newDur) }
    $prod = $d.Xml.mlt.SelectSingleNode("*[@id='$($e.producer)']"); $lp = Get-KdpProp $prod 'length'; if (-not $lp) { $lp = Get-KdpProp $prod 'kdenlive:maxduration' }; $srcLen = ConvertTo-KdpFrames $d $lp
    if ($prod.SelectSingleNode("link[property[@name='mlt_service']='timeremap']")) { $srcLen = [int]::MaxValue }
    if (-not (Test-KdpEndless $prod) -and $inF + $lenF -gt $srcLen) { throw "Trim exceeds source length ($([math]::Round($srcLen / $d.Fps,3)) s)." }
    Expand-KdpEndlessLength $d $prod ($inF + $lenF)
    Remove-KdpEntry $d $t $e
    $e.SetAttribute('in', (ConvertTo-KdpTime $d $inF)); $e.SetAttribute('out', (ConvertTo-KdpTime $d ($inF + $lenF - 1)))
    Set-KdpEntryAt $d $t $e $startF $lenF
}
function Split-KdpClip([KdpDoc]$d, [string]$track, [double]$at) {
    $f = SecToFrames $d $at
    $c = Find-KdpClip $d $track $at
    Assert-KdpNotMixed $d $c
    if ($f -le $c.StartFrames) { throw 'Split point is at the clip start.' }
    $t = Get-KdpTrack $d $track
    $e = $c.Node; $inF = ConvertTo-KdpFrames $d $e.in
    $leftLen = $f - $c.StartFrames
    $right = $e.Clone()
    $prod = $d.Xml.mlt.SelectSingleNode("*[@id='$($e.producer)']")
    if ($prod.Name -eq 'chain' -or (Get-KdpProp $prod 'mlt_service') -in 'timewarp' -or (Get-KdpProp $prod 'mlt_service') -like 'avformat*') {
        $pc = $prod.Clone(); $pc.SetAttribute('id', (New-KdpId $d $(if ($prod.Name -eq 'chain') { 'chain' } else { 'producer' }))); [void]$d.Xml.mlt.InsertBefore($pc, $t.Playlists[0]); $right.SetAttribute('producer', $pc.id)
    }
    $right.SetAttribute('in', (ConvertTo-KdpTime $d ($inF + $leftLen)))
    $e.SetAttribute('out', (ConvertTo-KdpTime $d ($inF + $leftLen - 1)))
    $pl = $t.Playlists[0]
    $items = Read-KdpItems $d $pl
    $res = New-Object System.Collections.ArrayList
    foreach ($it in $items) { if ($it.Kind -eq 'entry' -and [object]::ReferenceEquals($it.Node, $e)) { [void]$res.Add(@{ Kind = 'entry'; Len = $leftLen; Node = $e }); [void]$res.Add(@{ Kind = 'entry'; Len = $c.LenFrames - $leftLen; Node = $right }) } else { [void]$res.Add($it) } }
    Write-KdpItems $d $pl $res
}
function Remove-KdpClip([KdpDoc]$d, [string]$track, [double]$at, [switch]$Ripple) {
    $c = Find-KdpClip $d $track $at
    Assert-KdpNotMixed $d $c
    Remove-KdpEntry $d (Get-KdpTrack $d $track) $c.Node -Ripple:$Ripple
}
