# Helpers for looking at a running Kdenlive WITHOUT taking focus or sending keystrokes.
# Usage (Windows PowerShell 5.1):  . engine\kdwin.ps1 ; Get-KdWindows ; Save-KdShot (Get-KdProc).MainWindowHandle 'kd.png'
# Screenshots capture only Kdenlive's own window (PrintWindow), never the desktop.
# Note: PrintWindow returns a black image for Qt popup menus; read menus through UI Automation instead.
Add-Type -AssemblyName System.Drawing
if (-not ("KdWin" -as [type])) {
Add-Type @"
using System; using System.Runtime.InteropServices; using System.Text; using System.Collections.Generic;
public class KdWin {
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out R r);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr dc, uint f);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  public struct R { public int L, T, Ri, B; }
  public delegate bool EP(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EP cb, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  public static List<IntPtr> For(uint pid) { var l = new List<IntPtr>(); EnumWindows((h, x) => { uint p; GetWindowThreadProcessId(h, out p); if (p == pid && IsWindowVisible(h)) l.Add(h); return true; }, IntPtr.Zero); return l; }
  public static string Title(IntPtr h) { var sb = new StringBuilder(512); GetWindowText(h, sb, 512); return sb.ToString(); }
}
"@
}
$global:KdShots = Join-Path $PSScriptRoot '..\.shots'
function Get-KdProc { Get-Process kdenlive -ErrorAction SilentlyContinue | Select-Object -First 1 }
function Get-KdWindows {
  $p = Get-KdProc; if (-not $p) { return }
  foreach ($w in [KdWin]::For([uint32]$p.Id)) {
    $r = New-Object KdWin+R; [void][KdWin]::GetWindowRect($w, [ref]$r)
    [pscustomobject]@{ Handle = $w; Title = [KdWin]::Title($w); W = $r.Ri - $r.L; H = $r.B - $r.T; Main = ($w -eq $p.MainWindowHandle) }
  }
}
function Save-KdShot([IntPtr]$h, [string]$name) {
  New-Item -ItemType Directory -Force $global:KdShots | Out-Null
  $r = New-Object KdWin+R; [void][KdWin]::GetWindowRect($h, [ref]$r)
  $w = $r.Ri - $r.L; $ht = $r.B - $r.T
  $bmp = New-Object System.Drawing.Bitmap $w, $ht; $g = [System.Drawing.Graphics]::FromImage($bmp)
  $dc = $g.GetHdc(); [void][KdWin]::PrintWindow($h, $dc, 2); $g.ReleaseHdc($dc)
  $path = Join-Path $global:KdShots $name; $bmp.Save($path); $g.Dispose(); $bmp.Dispose(); return $path
}
