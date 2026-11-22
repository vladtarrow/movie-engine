# card-entrance.ps1 -Items cards.json -OutDir dir -Background bg.jpg [-Only 47] [-Suffix -v2]
# Screenshot-card entrance (the deck slides are flat images, Kdenlive cannot move the card apart from
# the background): renders a full-frame .mp4 per slide where the background stays still and the
# rounded screenshot card rises and scales in (0.86 -> 1, soft shadow), then holds for the rest of L.
# cards.json: [{ "n": 47, "L": 190, "file": "...\slide-047.png", "x": 120, "y": 80, "w": 1680, "h": 920, "r": 96 }]
#   x/y/w/h/r = the card's rectangle and corner radius on the 1920x1080 slide (from the deck's pptx).
param([Parameter(Mandatory)][string]$Items, [Parameter(Mandatory)][string]$OutDir, [Parameter(Mandatory)][string]$Background,
    [string]$Only, [string]$Suffix = '', [int]$Fps = 30, [int]$Anim = 16)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$engine = Split-Path $PSScriptRoot -Parent
$ff = Join-Path $engine 'Kdenlive\kdenlive-26.08.3_standalone\bin\ffmpeg.exe'
$list = Get-Content $Items -Raw -Encoding UTF8 | ConvertFrom-Json
New-Item -ItemType Directory -Force $OutDir | Out-Null
$bg = [Drawing.Image]::FromFile((Resolve-Path $Background).Path)
function Clamp01([double]$v) { [math]::Max([double]0, [math]::Min([double]1, $v)) }   # typed: Min(1,$v) would pick the int overload and round
function EaseOut([double]$p) { 1 - [math]::Pow(1 - $p, 3) }
function RoundRect([double]$x, [double]$y, [double]$w, [double]$h, [double]$r) {
    $gp = New-Object Drawing.Drawing2D.GraphicsPath; $r = [math]::Max(1, [math]::Min($r, [math]::Min($w, $h) / 2))
    $gp.AddArc($x, $y, 2 * $r, 2 * $r, 180, 90); $gp.AddArc($x + $w - 2 * $r, $y, 2 * $r, 2 * $r, 270, 90)
    $gp.AddArc($x + $w - 2 * $r, $y + $h - 2 * $r, 2 * $r, 2 * $r, 0, 90); $gp.AddArc($x, $y + $h - 2 * $r, 2 * $r, 2 * $r, 90, 90); $gp.CloseFigure(); $gp
}
foreach ($it in $list) {
    if ($Only -and "$($it.n)" -ne $Only) { continue }
    $L = [int]$it.L; $x = [double]$it.x; $y = [double]$it.y; $w = [double]$it.w; $h = [double]$it.h; $r = [double]$it.r
    $slide = [Drawing.Image]::FromFile((Resolve-Path $it.file).Path)
    $tex = New-Object Drawing.TextureBrush $slide
    $tmp = Join-Path $OutDir "frames-card-$($it.n)"; New-Item -ItemType Directory -Force $tmp | Out-Null
    $cx = $x + $w / 2; $cy = $y + $h / 2
    for ($f = 0; $f -le $Anim; $f++) {
        $p = EaseOut (Clamp01 ($f / [double]$Anim))
        $sc = 0.86 + 0.14 * $p; $dy = (1 - $p) * 70
        $bmp = New-Object Drawing.Bitmap 1920, 1080
        $g = [Drawing.Graphics]::FromImage($bmp); $g.SmoothingMode = 'AntiAlias'; $g.InterpolationMode = 'HighQualityBicubic'
        $g.DrawImage($bg, 0, 0, 1920, 1080)
        $m = New-Object Drawing.Drawing2D.Matrix
        $m.Translate([single]$cx, [single]($cy + $dy)); $m.Scale([single]$sc, [single]$sc); $m.Translate([single](-$cx), [single](-$cy))
        $g.Transform = $m
        # soft shadow: stacked rounded rects, offset down
        for ($k = 12; $k -ge 1; $k--) {
            $sp = RoundRect ($x - $k * 2) ($y - $k * 2 + 22) ($w + $k * 4) ($h + $k * 4) ($r + $k * 2)
            $g.FillPath((New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb([int](7 * $p + 3), 20, 0, 30))), $sp); $sp.Dispose()
        }
        $cp = RoundRect $x $y $w $h $r
        $g.FillPath($tex, $cp); $cp.Dispose()
        $g.Dispose(); $bmp.Save((Join-Path $tmp ('f{0:D4}.png' -f $f)), [Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
    }
    $tex.Dispose(); $slide.Dispose()
    $out = Join-Path $OutDir "card-$($it.n)$Suffix.mp4"
    # the last animated frame (= the slide itself) is held for the rest of the shot
    & $ff -hide_banner -loglevel error -y -framerate $Fps -i (Join-Path $tmp 'f%04d.png') -vf "tpad=stop_mode=clone:stop=$($L - $Anim - 1)" -frames:v $L -c:v libx264 -crf 14 -preset medium -pix_fmt yuv420p -r $Fps $out
    if ($LASTEXITCODE -ne 0) { throw "ffmpeg failed for card $($it.n)" }
    Remove-Item $tmp -Recurse -Force
    $out
}
