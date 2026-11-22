# Finds the Kdenlive window that has a given project open. Uses EnumWindows, not Process.MainWindowHandle:
# that property is empty on a test desktop and points at the splash or a popup during loading.
if (-not ('KdNative' -as [type])) {
Add-Type @"
using System; using System.Collections.Generic; using System.Runtime.InteropServices; using System.Text;
public static class KdNative {
  delegate bool EP(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] static extern bool EnumWindows(EP cb, IntPtr l);
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint p);
  [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsWindowEnabled(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  public static string Title(IntPtr h) { var b = new StringBuilder(512); GetWindowText(h, b, 512); return b.ToString(); }
  public static IntPtr[] Windows(int pid) {
    var list = new List<IntPtr>();
    EnumWindows((h, x) => { uint p; GetWindowThreadProcessId(h, out p); if (p == (uint)pid && IsWindowVisible(h)) list.Add(h); return true; }, IntPtr.Zero);
    return list.ToArray();
  }
}
"@
}
function Get-KdTopWindows([int]$processId) {
    foreach ($h in [KdNative]::Windows($processId)) { [pscustomobject]@{ Handle = $h; Title = [KdNative]::Title($h); ProcessId = $processId } }
}
# "<project>[*] / <profile> - Kdenlive", or "<sequence>:<project>[*] / ..." with several sequences
function Get-KdTitlePattern([string]$project) {
    if (-not $project) { return '\s/\s.*Kdenlive$' }
    '^(?:[^/:]*:)?' + [regex]::Escape([IO.Path]::GetFileNameWithoutExtension($project)) + '\s?\*?\s?/'
}
function Find-KdWindow([string]$Project) {
    $rx = Get-KdTitlePattern $Project
    $found = @(foreach ($p in @(Get-Process kdenlive -ErrorAction SilentlyContinue)) { Get-KdTopWindows $p.Id | Where-Object { $_.Title -match $rx } | Select-Object -First 1 })
    if ($found.Count -gt 1) { throw "Several Kdenlive windows match '$Project'; refusing to guess." }
    if ($found.Count) { return $found[0] }
}
function Find-KdProcess([string]$Project) {
    $w = Find-KdWindow $Project
    if ($w) { Get-Process -Id $w.ProcessId }
}
