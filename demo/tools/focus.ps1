# Maximize and bring to front the first visible top-level window whose title matches -Title.
# usage: powershell -File focus.ps1 -Title "Shader Selector"
param([string]$Title = "Google Chrome", [switch]$NoMaximize)
Add-Type @"
using System;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public class W {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc f, IntPtr l);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int n);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern void keybd_event(byte k, byte s, uint f, UIntPtr e);
  public static List<KeyValuePair<IntPtr,string>> All() {
    var r = new List<KeyValuePair<IntPtr,string>>();
    EnumWindows((h, l) => {
      if (IsWindowVisible(h)) { var sb = new StringBuilder(512); GetWindowText(h, sb, 512);
        if (sb.Length > 0) r.Add(new KeyValuePair<IntPtr,string>(h, sb.ToString())); }
      return true; }, IntPtr.Zero);
    return r;
  }
}
"@
$w = [W]::All() | Where-Object { $_.Value -like "*$Title*" } | Select-Object -First 1
if (-not $w) { "no window matching '$Title'"; exit 1 }
[W]::keybd_event(0x12, 0, 0, [UIntPtr]::Zero)   # tap Alt so Windows allows the focus change
[W]::keybd_event(0x12, 0, 2, [UIntPtr]::Zero)
if (-not $NoMaximize) { [W]::ShowWindow($w.Key, 3) | Out-Null }   # SW_MAXIMIZE
[W]::SetForegroundWindow($w.Key) | Out-Null
"focused: $($w.Value)"
