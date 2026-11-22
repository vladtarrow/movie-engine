# annotate.ps1 -Items ann.json -OutDir dir [-Only 47] [-Suffix -v2]
# Hand-drawn annotations over screenshots (Kdenlive has no draw-on strokes): renders each item to a
# transparent 1920x1080 .mov (PNG codec, alpha) of L frames, put on a track above the picture.
# ann.json: [{ "n": 88, "L": 191, "shapes": [
#     { "t": "ellipse",   "x": 461, "y": 772, "w": 420, "h": 400, "c": "#FF3B3B", "start": 70 },   x,y = centre
#     { "t": "rect",      "x": 490, "y": 30,  "w": 490, "h": 670, "c": "#FF3B3B", "start": 79 },   x,y = top-left
#     { "t": "underline", "x1": 640, "y1": 735, "x2": 1010, "y2": 728, "c": "#FF3B3B", "start": 2 },
#     { "t": "arrow",     "x1": 1000, "y1": 1000, "x2": 700, "y2": 850, "c": "#FFD21F", "start": 80 } ] }]
# Strokes draw on over 12 frames (ease-out) from "start"; ellipses are slightly irregular and overshoot
# like a marker circle; arrows draw the shaft, then the head. Output: <OutDir>\ann-<n><Suffix>.mov
param([Parameter(Mandatory)][string]$Items, [Parameter(Mandatory)][string]$OutDir, [string]$Only, [string]$Suffix = '',
    [int]$Fps = 30, [int]$Width = 11)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$engine = Split-Path $PSScriptRoot -Parent
$ff = Join-Path $engine 'Kdenlive\kdenlive-26.08.3_standalone\bin\ffmpeg.exe'
$list = Get-Content $Items -Raw -Encoding UTF8 | ConvertFrom-Json
New-Item -ItemType Directory -Force $OutDir | Out-Null
function Clamp01([double]$v) { [math]::Max([double]0, [math]::Min([double]1, $v)) }   # typed: Min(1,$v) would pick the int overload and round
function EaseOut([double]$p) { 1 - [math]::Pow(1 - $p, 3) }
function Pts($sh) {
    $pts = New-Object System.Collections.Generic.List[Drawing.PointF]
    switch ($sh.t) {
        'ellipse' {
            $rx = $sh.w / 2; $ry = $sh.h / 2; $a0 = -2.2; $turn = 2 * [math]::PI * 1.12
            for ($i = 0; $i -le 160; $i++) {
                $q = $i / 160; $a = $a0 + $turn * $q
                $wob = 1 + 0.035 * [math]::Sin(3 * $a + 0.7) + 0.05 * $q   # irregular, ends slightly outside the start
                $pts.Add((New-Object Drawing.PointF ([single]($sh.x + $rx * $wob * [math]::Cos($a))), ([single]($sh.y + $ry * $wob * [math]::Sin($a)))))
            }
        }
        'rect' {
            $x = $sh.x; $y = $sh.y; $w = $sh.w; $h = $sh.h; $j = 6
            $corners = @(@(($x - $j), ($y + 2)), @(($x + $w + $j), ($y - 3)), @(($x + $w + 2), ($y + $h + $j)), @(($x - 3), ($y + $h - 2)), @(($x + 2), ($y - $j - 4)))
            for ($c = 0; $c -lt 4; $c++) { for ($i = 0; $i -lt 40; $i++) { $q = $i / 40; $pts.Add((New-Object Drawing.PointF ([single]($corners[$c][0] + ($corners[$c + 1][0] - $corners[$c][0]) * $q)), ([single]($corners[$c][1] + ($corners[$c + 1][1] - $corners[$c][1]) * $q)))) } }
            $pts.Add((New-Object Drawing.PointF ([single]$corners[4][0]), ([single]$corners[4][1])))
        }
        'underline' {
            for ($i = 0; $i -le 60; $i++) { $q = $i / 60; $pts.Add((New-Object Drawing.PointF ([single]($sh.x1 + ($sh.x2 - $sh.x1) * $q)), ([single]($sh.y1 + ($sh.y2 - $sh.y1) * $q + 10 * [math]::Sin([math]::PI * $q))))) }
        }
        'arrow' {
            # slightly curved shaft
            $mx = ($sh.x1 + $sh.x2) / 2 - ($sh.y2 - $sh.y1) * 0.18; $my = ($sh.y1 + $sh.y2) / 2 + ($sh.x2 - $sh.x1) * 0.18
            for ($i = 0; $i -le 60; $i++) { $q = $i / 60; $u = 1 - $q
                $pts.Add((New-Object Drawing.PointF ([single]($u * $u * $sh.x1 + 2 * $u * $q * $mx + $q * $q * $sh.x2)), ([single]($u * $u * $sh.y1 + 2 * $u * $q * $my + $q * $q * $sh.y2)))) }
        }
    }
    , $pts
}
foreach ($it in $list) {
    if ($Only -and "$($it.n)" -ne $Only) { continue }
    $L = [int]$it.L
    $shapes = foreach ($sh in $it.shapes) { [pscustomobject]@{ sh = $sh; pts = (Pts $sh); col = [Drawing.ColorTranslator]::FromHtml($sh.c) } }
    $tmp = Join-Path $OutDir "frames-ann-$($it.n)"; New-Item -ItemType Directory -Force $tmp | Out-Null
    for ($f = 0; $f -lt $L; $f++) {
        $bmp = New-Object Drawing.Bitmap 1920, 1080, ([Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $g = [Drawing.Graphics]::FromImage($bmp); $g.SmoothingMode = 'AntiAlias'; $g.Clear([Drawing.Color]::Transparent)
        foreach ($s in $shapes) {
            $p = EaseOut (Clamp01 (($f - [int]$s.sh.start) / 12.0)); if ($p -le 0) { continue }
            $all = $s.pts; $cnt = [math]::Max(2, [int][math]::Ceiling($all.Count * $p))
            $part = $all.GetRange(0, [math]::Min($cnt, $all.Count)).ToArray()
            foreach ($pass in 'shadow', 'ink') {
                if ($pass -eq 'shadow') { $col = [Drawing.Color]::FromArgb(70, 0, 0, 0); $off = 3 } else { $col = $s.col; $off = 0 }
                $pen = New-Object Drawing.Pen $col, ([single]$Width); $pen.StartCap = 'Round'; $pen.EndCap = 'Round'; $pen.LineJoin = 'Round'
                $m = New-Object Drawing.Drawing2D.Matrix; $m.Translate($off, $off); $g.Transform = $m
                $g.DrawLines($pen, $part)
                if ($s.sh.t -eq 'arrow') {
                    $hp = EaseOut (Clamp01 (($f - [int]$s.sh.start - 12) / 6.0))
                    if ($hp -gt 0) {
                        $tip = $all[$all.Count - 1]; $prev = $all[$all.Count - 6]
                        $ang = [math]::Atan2($tip.Y - $prev.Y, $tip.X - $prev.X); $len = 46 * $hp
                        foreach ($da in 2.55, -2.55) { $g.DrawLine($pen, $tip, (New-Object Drawing.PointF ([single]($tip.X + $len * [math]::Cos($ang + $da))), ([single]($tip.Y + $len * [math]::Sin($ang + $da))))) }
                    }
                }
                $g.ResetTransform(); $pen.Dispose()
            }
        }
        $g.Dispose(); $bmp.Save((Join-Path $tmp ('f{0:D4}.png' -f $f)), [Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
    }
    $out = Join-Path $OutDir "ann-$($it.n)$Suffix.mov"
    & $ff -hide_banner -loglevel error -y -framerate $Fps -i (Join-Path $tmp 'f%04d.png') -c:v png -pix_fmt rgba $out
    if ($LASTEXITCODE -ne 0) { throw "ffmpeg failed for item $($it.n)" }
    Remove-Item $tmp -Recurse -Force
    $out
}
