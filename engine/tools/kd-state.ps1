# State shared by kdp.ps1, kd-pull, kd-reload and kd-watch. No UI code here.
#  - write stamp: hash of the last file the AI wrote. Without it the watcher cannot tell an AI write that follows
#    a save by a few seconds from the save itself.
#  - project lock: one named mutex per project, held by kdp.ps1 from pull to write, and during a reload.
#  - the environment every Kdenlive started by this engine gets.

# The long spelling of a path. TEMP and some shells hand out short names (USERNA~1); mixing the two spellings
# made relative paths climb to C:\ and back down, which broke them as soon as the folder moved (2026-11-22).
if (-not ('KdPath' -as [type])) {
Add-Type @"
using System.Text; using System.Runtime.InteropServices;
public static class KdPath {
  [DllImport("kernel32.dll", CharSet=CharSet.Unicode)] static extern uint GetLongPathName(string s, StringBuilder b, uint n);
  public static string Long(string p) {
    string full = System.IO.Path.GetFullPath(p), rest = "";
    // the last parts may not exist yet
    for (string cur = full; !string.IsNullOrEmpty(cur); ) {
      var b = new StringBuilder(2048);
      if (GetLongPathName(cur, b, 2048) > 0) return rest == "" ? b.ToString() : System.IO.Path.Combine(b.ToString(), rest);
      string parent = System.IO.Path.GetDirectoryName(cur);
      if (string.IsNullOrEmpty(parent)) break;
      string name = System.IO.Path.GetFileName(cur);
      rest = rest == "" ? name : System.IO.Path.Combine(name, rest);
      cur = parent;
    }
    return full;
  }
}
"@
}
function Get-KdHash([string]$path) {
    try {
        $stream = New-Object IO.FileStream($path, [IO.FileMode]::Open, [IO.FileAccess]::Read, ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
        try { $sha = [Security.Cryptography.SHA256]::Create(); return [BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-', '') }
        finally { $stream.Close() }
    } catch { return $null }
}
function Get-KdStateDir([string]$project) {
    $full = [IO.Path]::GetFullPath($project)
    Join-Path (Split-Path $full -Parent) ('.kdp-history\' + [IO.Path]::GetFileNameWithoutExtension($full))
}
function Set-KdWriteStamp([string]$project, [string]$hash) {
    $dir = Get-KdStateDir $project
    [void][IO.Directory]::CreateDirectory($dir)
    [IO.File]::WriteAllText((Join-Path $dir 'last-write.sha256'), $hash)
}
function Get-KdWriteStamp([string]$project) {
    $file = Join-Path (Get-KdStateDir $project) 'last-write.sha256'
    try { return [IO.File]::ReadAllText($file).Trim() } catch { return $null }
}

# Re-entrant on the same thread, so a holder may call pull or reload functions that lock again.
function Enter-KdLock([string]$project, [int]$timeoutSec = 1800) {
    $key = [KdPath]::Long($project).ToLowerInvariant()
    $md5 = [Security.Cryptography.MD5]::Create()
    $name = 'Local\kdp-' + [BitConverter]::ToString($md5.ComputeHash([Text.Encoding]::UTF8.GetBytes($key))).Replace('-', '')
    $mutex = New-Object Threading.Mutex($false, $name)
    try {
        if (-not $mutex.WaitOne($timeoutSec * 1000)) { throw "Another engine operation has held '$project' for over $timeoutSec s." }
    } catch [Threading.AbandonedMutexException] { }   # the previous holder died; the lock is ours now
    return $mutex
}
function Exit-KdLock($mutex) { if ($mutex) { try { $mutex.ReleaseMutex() } catch { }; $mutex.Dispose() } }

# TEMP is redirected as well: Kdenlive keeps its crash flag (kdenlivelock) and subtitle work files there.
# In the Windows temp folder a killed test instance made the next normal start report a crash (seen 2026-11-22).
# Starts Kdenlive for the launchers. Do not use Process.Start there (both found by test, 2026-11-22):
#  - it passes every handle on, so whoever captures the launcher's output waits until Kdenlive is closed;
#  - with UseShellExecute=false it drops WindowStyle, so "minimized, without focus" never reached Kdenlive.
# Without -Normal it returns once the main window exists and is minimized (or after MinimizeWaitSec).
function Start-KdDetached([string]$exe, [string]$arguments, [string]$profileDir, [switch]$Normal, [int]$MinimizeWaitSec = 300) {
    if (-not ('KdSpawn' -as [type])) {
        Add-Type @"
using System; using System.Collections; using System.Collections.Specialized; using System.ComponentModel; using System.Runtime.InteropServices; using System.Text;
public static class KdSpawn {
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] struct SI { public int cb; public string r1, desktop, title; public int x,y,w,h,cx,cy,fill,flags; public short show,r2; public IntPtr r3,i,o,e; }
  [StructLayout(LayoutKind.Sequential)] struct PI { public IntPtr proc, thread; public int pid, tid; }
  [DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Unicode)] static extern bool CreateProcess(string a, StringBuilder c, IntPtr p, IntPtr t, bool inherit, uint f, IntPtr env, string cwd, ref SI si, out PI pi);
  [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
  delegate bool EP(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] static extern bool EnumWindows(EP cb, IntPtr l);
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint p);
  [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] static extern bool ShowWindowAsync(IntPtr h, int cmd);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  // The splash uses up the start flag, so Qt shows the main window restored. Minimize it as it appears:
  // 7 does not activate anything; 6 is for a window that already got the focus and hands it back to the window below.
  public static bool Minimize(int pid) {
    bool done = false;
    EnumWindows((h, x) => { uint p; GetWindowThreadProcessId(h, out p);
      if (p != (uint)pid || !IsWindowVisible(h)) return true;
      var b = new StringBuilder(512); GetWindowText(h, b, 512); string t = b.ToString();
      if (!t.EndsWith(" - Kdenlive") || !t.Contains(" / ")) return true;
      if (!IsIconic(h)) ShowWindowAsync(h, GetForegroundWindow() == h ? 6 : 7);
      done = true;
      return false; }, IntPtr.Zero);
    return done;
  }
  public static int Start(string cmd, StringDictionary env, short show) {
    var keys = new ArrayList(env.Keys); keys.Sort(StringComparer.OrdinalIgnoreCase);
    var b = new StringBuilder();
    foreach (string k in keys) b.Append(k).Append('=').Append(env[k]).Append('\0');
    b.Append('\0');
    IntPtr mem = Marshal.StringToHGlobalUni(b.ToString());
    try {
      var si = new SI(); si.cb = Marshal.SizeOf(si); si.flags = 1; si.show = show;
      PI pi;
      if (!CreateProcess(null, new StringBuilder(cmd), IntPtr.Zero, IntPtr.Zero, false, 0x400, mem, null, ref si, out pi)) throw new Win32Exception();
      CloseHandle(pi.thread); CloseHandle(pi.proc);
      return pi.pid;
    } finally { Marshal.FreeHGlobal(mem); }
  }
}
"@
    }
    $info = New-Object Diagnostics.ProcessStartInfo
    Set-KdEnvironment $info.EnvironmentVariables $profileDir
    $show = if ($Normal) { 1 } else { 7 }     # 7 = minimized and not activated
    $id = [KdSpawn]::Start("`"$exe`" $arguments".Trim(), $info.EnvironmentVariables, $show)
    $proc = [Diagnostics.Process]::GetProcessById($id)
    if (-not $Normal) {
        $clock = [Diagnostics.Stopwatch]::StartNew()
        while (-not $proc.HasExited -and $clock.Elapsed.TotalSeconds -lt $MinimizeWaitSec -and -not [KdSpawn]::Minimize($id)) { Start-Sleep -Milliseconds 50 }
    }
    return $proc
}
function Set-KdEnvironment($vars, [string]$profileDir) {
    $local = [IO.Path]::Combine($profileDir, 'AppData', 'Local')
    $roaming = [IO.Path]::Combine($profileDir, 'AppData', 'Roaming')
    $temp = [IO.Path]::Combine($local, 'Temp')
    foreach ($dir in $local, $roaming, $temp) { [void][IO.Directory]::CreateDirectory($dir) }
    $vars['USERPROFILE'] = $profileDir
    $vars['APPDATA'] = $roaming
    $vars['LOCALAPPDATA'] = $local
    $vars['XDG_CONFIG_HOME'] = $local
    $vars['XDG_DATA_HOME'] = $local
    $vars['XDG_CACHE_HOME'] = [IO.Path]::Combine($local, 'cache')
    $vars['TEMP'] = $temp
    $vars['TMP'] = $temp
    # Interface language: English unless MOVIE_ENGINE_UI_LANG names another (ru, de, ...). UI Automation finds
    # English and Russian names (kd-ui.ps1, $KdNames); another language needs its names added there.
    $lang = if ($env:MOVIE_ENGINE_UI_LANG) { $env:MOVIE_ENGINE_UI_LANG } else { 'en_US' }
    $vars['LANGUAGE'] = $lang
    $vars['LANG'] = $lang
}
