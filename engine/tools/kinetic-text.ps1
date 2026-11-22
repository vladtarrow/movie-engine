# kinetic-text.ps1 -Cards cards.json -OutDir dir [-Only 234] [-FontFile engine\fonts\Poppins-Bold.ttf | -Font 'Segoe UI'] [-Color '#F0337B']
# Per-letter kinetic text (Kdenlive cannot animate single letters): renders each card to a
# transparent 1920x1080 .mov (PNG codec, alpha) that goes on a track above the pictures.
# cards.json: [{ "n": 234, "L": 139, "lines": ["The key is to make", "your brand stand out"],
#                "hl": "stand out", "starts": [2,4,13,...] }]   (L = frames, starts = first frame of each word)
# Letters rise, scale up and fade in one after another; the highlighted phrase gets a rounded
# colour box that grows from the left behind it. Output: <OutDir>\text-<n><Suffix>.mov
param([Parameter(Mandatory)][string]$Cards, [Parameter(Mandatory)][string]$OutDir, [string]$Only,
    [string]$FontFile, [string]$Font,
    [string]$Color = '#F0337B', [int]$Fps = 30, [string]$Suffix = '')
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$engine = Split-Path $PSScriptRoot -Parent
if (-not $FontFile) { $FontFile = Join-Path $engine 'fonts\Poppins-Bold.ttf' }
$ff = Join-Path $engine 'Kdenlive\kdenlive-26.08.3_standalone\bin\ffmpeg.exe'
$list = Get-Content $Cards -Raw -Encoding UTF8 | ConvertFrom-Json
New-Item -ItemType Directory -Force $OutDir | Out-Null
# the font is loaded from its file (portable: nothing is installed into Windows)
if ($Font) { $fam = New-Object Drawing.FontFamily $Font } else { $pfc = New-Object Drawing.Text.PrivateFontCollection; $pfc.AddFontFile((Resolve-Path $FontFile).Path); $fam = $pfc.Families[0] }
$style = [Drawing.FontStyle]::Bold
$hlCol = [Drawing.ColorTranslator]::FromHtml($Color)
$sfT = [Drawing.StringFormat]::GenericTypographic
$sfT.FormatFlags = $sfT.FormatFlags -bor [Drawing.StringFormatFlags]::MeasureTrailingSpaces
function Clamp01([double]$v) { [math]::Max([double]0, [math]::Min([double]1, $v)) }   # typed: Min(1,$v) would pick the int overload and round
function EaseBack([double]$p) { $c1 = 1.70158; $c3 = $c1 + 1; 1 + $c3 * [math]::Pow($p - 1, 3) + $c1 * [math]::Pow($p - 1, 2) }
function EaseCubic([double]$p) { 1 - [math]::Pow(1 - $p, 3) }
function RoundRect([double]$x, [double]$y, [double]$w, [double]$h, [double]$r) {
    $gp = New-Object Drawing.Drawing2D.GraphicsPath; $r = [math]::Min($r, [math]::Min($w, $h) / 2); if ($r -lt 1) { $r = 1 }
    $gp.AddArc($x, $y, 2 * $r, 2 * $r, 180, 90); $gp.AddArc($x + $w - 2 * $r, $y, 2 * $r, 2 * $r, 270, 90)
    $gp.AddArc($x + $w - 2 * $r, $y + $h - 2 * $r, 2 * $r, 2 * $r, 0, 90); $gp.AddArc($x, $y + $h - 2 * $r, 2 * $r, 2 * $r, 90, 90); $gp.CloseFigure(); $gp
}
$meas = [Drawing.Graphics]::FromImage((New-Object Drawing.Bitmap 8, 8))
function TextW([string]$s, [double]$size) { if (-not $s) { return 0 }; $f = New-Object Drawing.Font $fam, ([single]$size), $style, ([Drawing.GraphicsUnit]::Pixel); $w = $meas.MeasureString($s, $f, 100000, $sfT).Width; $f.Dispose(); $w }

foreach ($c in $list) {
    if ($Only -and "$($c.n)" -ne $Only) { continue }
    $lines = @($c.lines); $L = [int]$c.L; $starts = @($c.starts | ForEach-Object { [int]$_ })
    $size = switch ($lines.Count) { 1 { 128 } 2 { 128 } 3 { 112 } default { 100 } }   # deck: Poppins Bold 48 pt = 128 px
    $maxW = ($lines | ForEach-Object { TextW $_ $size } | Measure-Object -Maximum).Maximum
    if ($maxW -gt 1700) { $size = [math]::Floor($size * 1700 / $maxW) }
    $lh = $size * 1.2
    $asc = $fam.GetCellAscent($style) / $fam.GetEmHeight($style) * $size
    $base0 = 540 - ($lines.Count - 1) * $lh / 2 + 0.36 * $size   # x-height centred on the frame
    # letter layout
    $letters = New-Object System.Collections.ArrayList; $wordIdx = 0; $hlBoxes = @()
    $hlWords = @($c.hl -split ' ')
    for ($li = 0; $li -lt $lines.Count; $li++) {
        $ln = $lines[$li]; $lw = TextW $ln $size; $x0 = (1920 - $lw) / 2; $bl = $base0 + $li * $lh; $y = $bl - $asc
        $pos = 0; $words = $ln -split ' '
        for ($wi = 0; $wi -lt $words.Count; $wi++) {
            $w = $words[$wi]; $ws = $starts[[math]::Min($wordIdx, $starts.Count - 1)]
            $wx = $x0 + (TextW ($ln.Substring(0, $pos)) $size)
            for ($k = 0; $k -lt $w.Length; $k++) {
                $lx = $x0 + (TextW ($ln.Substring(0, $pos + $k)) $size)
                [void]$letters.Add([pscustomobject]@{ ch = $w[$k]; x = $lx; y = $y; bl = $bl; w = (TextW ([string]$w[$k]) $size); start = $ws + $k })
            }
            # highlighted phrase: consecutive words matching hl
            $match = $true; for ($q = 0; $q -lt $hlWords.Count; $q++) { if ($wi + $q -ge $words.Count -or $words[$wi + $q] -ne $hlWords[$q]) { $match = $false } }
            if ($match) {
                $endPos = $pos + (($words[$wi..($wi + $hlWords.Count - 1)]) -join ' ').Length
                $ex = $x0 + (TextW ($ln.Substring(0, $endPos)) $size)
                $hlBoxes += [pscustomobject]@{ x = $wx - 0.2 * $size; y = $bl - 0.92 * $size; w = ($ex - $wx) + 0.4 * $size; h = 1.36 * $size; start = $ws + 2 }
            }
            $pos += $w.Length + 1; $wordIdx++
        }
    }
    $tmp = Join-Path $OutDir "frames-$($c.n)"; New-Item -ItemType Directory -Force $tmp | Out-Null
    $font = New-Object Drawing.Font $fam, ([single]$size), $style, ([Drawing.GraphicsUnit]::Pixel)
    for ($f = 0; $f -lt $L; $f++) {
        $bmp = New-Object Drawing.Bitmap 1920, 1080, ([Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $g = [Drawing.Graphics]::FromImage($bmp); $g.SmoothingMode = 'AntiAlias'; $g.Clear([Drawing.Color]::Transparent)
        foreach ($b in $hlBoxes) {
            $p = EaseCubic (Clamp01 (($f - $b.start) / 8.0))
            if ($p -gt 0.01) { $gp = RoundRect $b.x $b.y ($b.w * $p) $b.h (0.16 * $size); $g.FillPath((New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb([int](255 * (Clamp01 ($p * 3))), $hlCol))), $gp); $gp.Dispose() }
        }
        foreach ($t in $letters) {
            $p = Clamp01 (($f - $t.start) / 9.0); if ($p -le 0) { continue }
            $e = EaseBack $p; $a = Clamp01 ($p * 2.2); $sc = 0.55 + 0.45 * $e; $dy = (1 - $e) * 0.5 * $size
            $gp = New-Object Drawing.Drawing2D.GraphicsPath
            $gp.AddString([string]$t.ch, $fam, [int]$style, [single]$size, (New-Object Drawing.PointF ([single]$t.x), ([single]$t.y)), $sfT)
            $m = New-Object Drawing.Drawing2D.Matrix
            $cx = $t.x + $t.w / 2; $cy = $t.bl - 0.35 * $size
            $m.Translate([single]$cx, [single]($cy + $dy)); $m.Scale([single]$sc, [single]$sc); $m.Translate([single](-$cx), [single](-$cy))
            $gp.Transform($m)
            $sh = $gp.Clone(); $m2 = New-Object Drawing.Drawing2D.Matrix; $m2.Translate(0, [single]($size * 0.04)); $sh.Transform($m2)
            $g.FillPath((New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb([int](70 * $a), 30, 0, 40))), $sh)
            $g.FillPath((New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb([int](255 * $a), 255, 255, 255))), $gp)
            $gp.Dispose(); $sh.Dispose()
        }
        $g.Dispose(); $bmp.Save((Join-Path $tmp ('f{0:D4}.png' -f $f)), [Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
    }
    $out = Join-Path $OutDir "text-$($c.n)$Suffix.mov"
    & $ff -hide_banner -loglevel error -y -framerate $Fps -i (Join-Path $tmp 'f%04d.png') -c:v png -pix_fmt rgba $out
    if ($LASTEXITCODE -ne 0) { throw "ffmpeg failed for card $($c.n)" }
    Remove-Item $tmp -Recurse -Force
    $out
}
