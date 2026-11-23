# Sets up everything that is not in git, inside this folder, without admin rights:
#   1. Node.js (Windows x64 .zip from nodejs.org, latest LTS unless -NodeVersion) -> engine\node\
#   2. Node packages of engine\voice (npm install, versions pinned in engine\voice\package.json)
#   3. Kdenlive 26.08.3 portable from download.kde.org, SHA-256 checked -> engine\Kdenlive\
# Steps that are already done are skipped, so it is safe to run again.
#   powershell -NoProfile -ExecutionPolicy Bypass -File engine\install.ps1 [-DryRun] [-NodeVersion v22.11.0] [-SkipKdenlive]
# -DryRun downloads nothing and changes nothing; it prints what would be done.
# Exit 0 everything ready, 1 a step failed.
param([switch]$DryRun, [string]$NodeVersion, [switch]$SkipKdenlive)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'   # Invoke-WebRequest is many times slower with the progress bar
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$engine = $PSScriptRoot
$root = Split-Path $engine -Parent
$downloads = Join-Path $engine 'installer'
$nodeDir = Join-Path $engine 'node'
$kdVersion = '26.08.3'
$kdFile = "kdenlive-$kdVersion" + '_standalone.exe'
$kdUrl = "https://download.kde.org/stable/kdenlive/26.08/windows/$kdFile"
$kdSha = 'a25427b1dff2c17e3b0386e991bb1a719382bb3176d1a90e441cdaeb6e0a967d'
$kdExe = Join-Path $engine "Kdenlive\kdenlive-$kdVersion`_standalone\bin\kdenlive.exe"

function Say([string]$text) { Write-Host $text }
function Step([string]$text) { Write-Host ''; Write-Host "== $text" }
function Get-Sha256([string]$file) { (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant() }
function Save-Url([string]$url, [string]$file) {
    Say "   downloading $url"
    $tmp = "$file.part"
    if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force }
    Invoke-WebRequest -Uri $url -OutFile $tmp -UseBasicParsing
    Move-Item -LiteralPath $tmp -Destination $file -Force
}
function Get-NodeVersionOk {
    $exe = Join-Path $nodeDir 'node.exe'
    if (-not (Test-Path -LiteralPath $exe)) { return $false }
    $v = (& $exe --version) -replace '^v', ''
    return ([version]$v -ge [version]'18.0.0')
}

$failed = $false
try {
    # ---- 1. Node.js -------------------------------------------------------------------------------
    Step 'Node.js'
    $npm = Join-Path $nodeDir 'npm.cmd'
    if ((Get-NodeVersionOk) -and (Test-Path -LiteralPath $npm)) {
        Say "   ready: engine\node\node.exe $(& (Join-Path $nodeDir 'node.exe') --version) with npm"
    } elseif ($DryRun) {
        $what = if ($NodeVersion) { $NodeVersion } else { 'the latest LTS' }
        Say "   would download Node.js $what (win-x64 .zip), check it against SHASUMS256.txt and unpack it into engine\node\"
    } else {
        if (-not $NodeVersion) {
            $index = Invoke-RestMethod -Uri 'https://nodejs.org/dist/index.json' -UseBasicParsing
            $NodeVersion = ($index | Where-Object { $_.lts -and $_.files -contains 'win-x64-zip' } | Select-Object -First 1).version
            if (-not $NodeVersion) { throw 'could not find the latest Node.js LTS in https://nodejs.org/dist/index.json' }
        }
        if ($NodeVersion -notmatch '^v') { $NodeVersion = "v$NodeVersion" }
        $zipName = "node-$NodeVersion-win-x64.zip"
        $base = "https://nodejs.org/dist/$NodeVersion"
        [void](New-Item -ItemType Directory -Force -Path $downloads)
        $zip = Join-Path $downloads $zipName
        $sums = (Invoke-WebRequest -Uri "$base/SHASUMS256.txt" -UseBasicParsing).Content
        $line = ($sums -split "`n") | Where-Object { $_ -match "\s$([regex]::Escape($zipName))\s*$" } | Select-Object -First 1
        if (-not $line) { throw "$zipName is not listed in $base/SHASUMS256.txt" }
        $want = ($line -split '\s+')[0].ToLowerInvariant()
        if (-not ((Test-Path -LiteralPath $zip) -and (Get-Sha256 $zip) -eq $want)) { Save-Url "$base/$zipName" $zip }
        $got = Get-Sha256 $zip
        if ($got -ne $want) { Remove-Item -LiteralPath $zip -Force; throw "SHA-256 of $zipName does not match nodejs.org ($got)" }
        Say '   SHA-256 matches nodejs.org'
        $unpack = Join-Path $downloads "node-unpack-$PID"
        Expand-Archive -LiteralPath $zip -DestinationPath $unpack -Force
        $inner = Get-ChildItem -LiteralPath $unpack -Directory | Select-Object -First 1
        [void](New-Item -ItemType Directory -Force -Path $nodeDir)
        Copy-Item -Path (Join-Path $inner.FullName '*') -Destination $nodeDir -Recurse -Force
        Remove-Item -LiteralPath $unpack -Recurse -Force
        Say "   installed Node.js $NodeVersion into engine\node\"
    }

    # ---- 2. Node packages ---------------------------------------------------------------------------
    Step 'Node packages (engine\voice)'
    $mods = Join-Path $engine 'voice\node_modules'
    $have = (Test-Path -LiteralPath (Join-Path $mods 'msedge-tts\package.json')) -and (Test-Path -LiteralPath (Join-Path $mods 'ws\package.json'))
    if ($have) { Say '   ready: msedge-tts and ws are installed' }
    elseif ($DryRun) { Say '   would run: engine\node\npm.cmd install --prefix engine\voice' }
    else {
        & (Join-Path $nodeDir 'npm.cmd') install --prefix (Join-Path $engine 'voice') --no-audit --no-fund
        if ($LASTEXITCODE -ne 0) { throw "npm install failed (exit $LASTEXITCODE)" }
        Say '   installed'
    }

    # ---- 3. Kdenlive ----------------------------------------------------------------------------------
    Step "Kdenlive $kdVersion portable"
    if ($SkipKdenlive) { Say '   skipped (-SkipKdenlive)' }
    elseif (Test-Path -LiteralPath $kdExe) { Say "   ready: engine\Kdenlive\kdenlive-$kdVersion`_standalone\" }
    elseif ($DryRun) { Say "   would download $kdUrl (about 250 MB), check SHA-256 $kdSha and unpack it into engine\Kdenlive\" }
    else {
        [void](New-Item -ItemType Directory -Force -Path $downloads)
        $setup = Join-Path $downloads $kdFile
        if (-not ((Test-Path -LiteralPath $setup) -and (Get-Sha256 $setup) -eq $kdSha)) { Save-Url $kdUrl $setup }
        $got = Get-Sha256 $setup
        if ($got -ne $kdSha) { Remove-Item -LiteralPath $setup -Force; throw "SHA-256 of $kdFile does not match ($got); the file was deleted" }
        Say '   SHA-256 matches'
        # 7-Zip self-extractor: -o target folder, -y no questions; no admin, nothing outside this folder
        $p = Start-Process -FilePath $setup -ArgumentList "-o`"$(Join-Path $engine 'Kdenlive')`"", '-y' -Wait -PassThru -WindowStyle Hidden
        if ($p.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $kdExe)) { throw "unpacking $kdFile failed (exit $($p.ExitCode))" }
        Say "   unpacked into engine\Kdenlive\"
    }

    # ---- Microsoft Edge (used headless by the renderers) ---------------------------------------------
    Step 'Microsoft Edge'
    $edge = @("${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe", "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe") |
        Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
    if ($edge) { Say '   found (part of Windows)' } else { Say '   not found: html-render.mjs and film-render.mjs need Microsoft Edge' }
} catch {
    $failed = $true
    Write-Host ''
    Write-Host "FAILED: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ''
if ($failed) { exit 1 }
if ($DryRun) { Say 'Dry run: nothing was downloaded or changed.' }
else { Say 'Ready. Start the editor with engine\kdenlive.cmd, or open this folder in Claude Code or Codex.' }
exit 0
