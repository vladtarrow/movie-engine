# Before a project is opened: if the folder was copied or moved, write its new place into the project.
# Otherwise Kdenlive uses the media of the old folder for as long as that folder exists.
param([string]$Project)
if (-not $Project -or -not (Test-Path -LiteralPath $Project -PathType Leaf) -or $Project -notlike '*.kdenlive') { exit 0 }
$full = (Resolve-Path -LiteralPath $Project).Path
$reader = [IO.File]::OpenText($full)
try { $buf = New-Object char[] 4096; $n = $reader.Read($buf, 0, 4096) } finally { $reader.Close() }
$head = New-Object string ($buf, 0, $n)
if ($head -notmatch '<mlt[^>]*\sroot="([^"]*)"') { exit 0 }
$root = $matches[1].Replace('&amp;', '&').Replace('/', '\').TrimEnd('\')
if ($root -eq (Split-Path $full -Parent)) { exit 0 }
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path (Split-Path $PSScriptRoot -Parent) 'kdp.ps1') rebase -Project $full
exit $LASTEXITCODE
