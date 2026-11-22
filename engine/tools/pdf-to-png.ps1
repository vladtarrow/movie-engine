# pdf-to-png.ps1 -Pdf deck.pdf -OutDir folder [-Width 1920] [-Pages 3,7,12] [-Force]
# Renders every PDF page to slide-NNN.png with Windows' built-in Windows.Data.Pdf (no install). Skips pages already rendered.
param([string]$Pdf, [string]$OutDir, [int]$Width = 1920, [string]$Pages, [switch]$Force)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Runtime.WindowsRuntime
$null = [Windows.Data.Pdf.PdfDocument, Windows.Data.Pdf, ContentType = WindowsRuntime]
$null = [Windows.Storage.StorageFile, Windows.Storage, ContentType = WindowsRuntime]
$null = [Windows.Storage.Streams.InMemoryRandomAccessStream, Windows.Storage.Streams, ContentType = WindowsRuntime]
$asTaskGeneric = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]
function Await($op, [Type]$t) { $m = $asTaskGeneric.MakeGenericMethod($t); $task = $m.Invoke($null, @($op)); $task.Wait(); $task.Result }
$asTaskAction = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncAction' })[0]
function AwaitA($op) { $task = $asTaskAction.Invoke($null, @($op)); try { $task.Wait() } catch { throw $_.Exception.InnerException.InnerException } }

$file = Await ([Windows.Storage.StorageFile]::GetFileFromPathAsync((Resolve-Path $Pdf).Path)) ([Windows.Storage.StorageFile])
$doc = Await ([Windows.Data.Pdf.PdfDocument]::LoadFromFileAsync($file)) ([Windows.Data.Pdf.PdfDocument])
New-Item -ItemType Directory -Force $OutDir | Out-Null
$n = $doc.PageCount
Write-Host "pages $n"
for ($i = 0; $i -lt $n; $i++) {
  $out = Join-Path $OutDir ('slide-{0:D3}.png' -f ($i + 1))
  if ($Pages -and ($i + 1) -notin ($Pages -split "[ ,]+" | ForEach-Object { [int]$_ })) { continue }
  if ((Test-Path $out) -and -not $Force) { continue }
  $page = $doc.GetPage($i)
  $opt = New-Object Windows.Data.Pdf.PdfPageRenderOptions
  $opt.DestinationWidth = $Width
  $opt.DestinationHeight = [uint32]([math]::Round($Width * $page.Size.Height / $page.Size.Width))

  $ms = New-Object Windows.Storage.Streams.InMemoryRandomAccessStream
  AwaitA ($page.RenderToStreamAsync($ms, $opt))
  $st = [System.IO.WindowsRuntimeStreamExtensions]::AsStreamForRead($ms.GetInputStreamAt(0))
  $fs = [System.IO.File]::Create($out); $st.CopyTo($fs); $fs.Close(); $st.Dispose(); $ms.Dispose(); $page.Dispose()
}
Write-Host 'done'
