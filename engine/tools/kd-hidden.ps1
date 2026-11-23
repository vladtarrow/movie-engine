# Runs a PowerShell test script on its own Windows desktop that is never shown to the user.
# Windows on that desktop cannot take the user's focus and cannot receive or disturb the user's input.
# UI Automation and EnumWindows see only their own desktop, so the test script itself must run there,
# and it cannot see (or touch) the user's Kdenlive.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File engine\tools\kd-hidden.ps1 -Script <test.ps1> [-ArgList "-A 1 -B 2"] [-TimeoutSec 600]
#
# Everything the script starts is in one job object and ends when the script ends or times out.
# Processes the script did not start are never touched. Exit code = the script's exit code, 124 = timeout.
param([Parameter(Mandatory)][string]$Script, [string]$ArgList = '', [int]$TimeoutSec = 600)
$ErrorActionPreference = 'Stop'
Add-Type @"
using System; using System.ComponentModel; using System.Runtime.InteropServices; using System.Text;
public static class KdHidden {
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] struct SI { public int cb; public string r1, desktop, title; public int x,y,w,h,cx,cy,fill,flags; public short show,r2; public IntPtr r3,i,o,e; }
  [StructLayout(LayoutKind.Sequential)] struct PI { public IntPtr proc, thread; public int pid, tid; }
  [StructLayout(LayoutKind.Sequential)] struct BASIC { public long a,b; public uint flags; public UIntPtr min,max; public uint active; public UIntPtr affinity; public uint pri,sched; }
  [StructLayout(LayoutKind.Sequential)] struct EXT { public BASIC basic; public ulong r,w,o,rb,wb,ob; public UIntPtr pm,jm,ppm,pjm; }
  [DllImport("user32.dll", SetLastError=true, CharSet=CharSet.Unicode)] static extern IntPtr CreateDesktop(string n, IntPtr d, IntPtr m, uint f, uint a, IntPtr s);
  [DllImport("user32.dll")] static extern bool CloseDesktop(IntPtr h);
  [DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Unicode)] static extern bool CreateProcess(string a, StringBuilder c, IntPtr p, IntPtr t, bool inherit, uint f, IntPtr env, string cwd, ref SI si, out PI pi);
  [DllImport("kernel32.dll")] static extern IntPtr CreateJobObject(IntPtr a, string n);
  [DllImport("kernel32.dll", SetLastError=true)] static extern bool SetInformationJobObject(IntPtr j, int c, ref EXT e, int n);
  [DllImport("kernel32.dll", SetLastError=true)] static extern bool AssignProcessToJobObject(IntPtr j, IntPtr p);
  [DllImport("kernel32.dll")] static extern bool TerminateProcess(IntPtr p, uint code);
  [DllImport("kernel32.dll")] static extern uint ResumeThread(IntPtr t);
  [DllImport("kernel32.dll")] static extern uint WaitForSingleObject(IntPtr h, uint ms);
  [DllImport("kernel32.dll")] static extern bool GetExitCodeProcess(IntPtr h, out uint code);
  [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
  public static int Run(string cmd, string cwd, int seconds) {
    string name = "kdp-test-" + Guid.NewGuid().ToString("N");
    IntPtr desk = CreateDesktop(name, IntPtr.Zero, IntPtr.Zero, 0, 0x10000000, IntPtr.Zero);
    if (desk == IntPtr.Zero) throw new Win32Exception();
    IntPtr job = CreateJobObject(IntPtr.Zero, null);
    try {
      var e = new EXT(); e.basic.flags = 0x2000; // kill on job close
      if (!SetInformationJobObject(job, 9, ref e, Marshal.SizeOf(e))) throw new Win32Exception();
      var si = new SI(); si.cb = Marshal.SizeOf(si); si.desktop = "winsta0\\" + name;
      PI pi;
      if (!CreateProcess(null, new StringBuilder(cmd), IntPtr.Zero, IntPtr.Zero, false, 0x08000004, IntPtr.Zero, cwd, ref si, out pi)) throw new Win32Exception();
      try {
        if (!AssignProcessToJobObject(job, pi.proc)) { var err = new Win32Exception(); TerminateProcess(pi.proc, 1); throw err; }
        ResumeThread(pi.thread);
        if (WaitForSingleObject(pi.proc, (uint)seconds * 1000) != 0) return 124;
        uint code; GetExitCodeProcess(pi.proc, out code); return (int)code;
      } finally { CloseHandle(pi.thread); CloseHandle(pi.proc); }
    } finally { CloseHandle(job); CloseDesktop(desk); }
  }
}
"@
$Script = (Resolve-Path $Script).Path
$id = [guid]::NewGuid().ToString('N')
$wrap = Join-Path $env:TEMP "kd-hidden-$id.ps1"
$log = Join-Path $env:TEMP "kd-hidden-$id.log"
$body = "`$global:LASTEXITCODE = 0`r`ntry { & '$($Script.Replace("'", "''"))' $ArgList *> '$($log.Replace("'", "''"))'; exit `$LASTEXITCODE }`r`ncatch { `"ERROR: `$(`$_.Exception.Message) `$(`$_.InvocationInfo.PositionMessage)`" | Out-File -Append '$($log.Replace("'", "''"))'; exit 1 }`r`n"
[IO.File]::WriteAllText($wrap, $body, (New-Object Text.UTF8Encoding($true)))
$code = 1
# The script and everything it starts get their own TEMP (test Kdenlive folders, profiles, renders), removed when
# the run ends; the job object has ended every process by then, so nothing holds the files.
$runTemp = Join-Path $env:TEMP "kd-hidden-$id"
[void][IO.Directory]::CreateDirectory($runTemp)
$oldTemp = $env:TEMP; $oldTmp = $env:TMP
try {
    $env:TEMP = $runTemp; $env:TMP = $runTemp   # inherited by the hidden process (CreateProcess with no environment block)
    try { $code = [KdHidden]::Run("powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$wrap`"", (Split-Path $Script -Parent), $TimeoutSec) }
    finally { $env:TEMP = $oldTemp; $env:TMP = $oldTmp }
    if (Test-Path $log) { Get-Content $log }
    if ($code -eq 124) { "TIMEOUT after $TimeoutSec s" }
} finally {
    Remove-Item $wrap, $log -Force -ErrorAction SilentlyContinue
    foreach ($try in 1..5) {
        try { if (Test-Path -LiteralPath $runTemp) { Remove-Item -LiteralPath $runTemp -Recurse -Force -ErrorAction Stop }; break }
        catch { Start-Sleep -Seconds 1 }
    }
}
exit $code
