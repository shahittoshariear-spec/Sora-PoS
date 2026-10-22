param(
  [string]$Exe = "release\SoraPos-demo\sora_pos.exe",
  [int]$Cycles = 20
)

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Stress {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hWnd, IntPtr after, int x, int y, int cx, int cy, uint flags);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint flags, uint dx, uint dy, uint data, UIntPtr extra);
  public struct RECT { public int Left, Top, Right, Bottom; }
}
"@
[void][Stress]::SetProcessDPIAware()
$exePath = (Resolve-Path $Exe).Path
$proc = Start-Process -FilePath $exePath -WorkingDirectory (Split-Path $exePath) -PassThru
Start-Sleep -Seconds 6
$proc.Refresh(); $hwnd = $proc.MainWindowHandle
[void][Stress]::SetWindowPos($hwnd, [IntPtr](-1), 0, 0, 0, 0, 0x43)
[void][Stress]::SetForegroundWindow($hwnd); Start-Sleep -Milliseconds 700

$rect = New-Object Stress+RECT
[void][Stress]::GetWindowRect($hwnd, [ref]$rect)
$w = $rect.Right - $rect.Left; $h = $rect.Bottom - $rect.Top

function Point([double]$fx, [double]$fy) { @([int]($rect.Left + $w * $fx), [int]($rect.Top + $h * $fy)) }

function Drag([double]$fromX, [double]$toX) {
  $a = Point $fromX 0.55; $b = Point $toX 0.55
  [void][Stress]::SetCursorPos($a[0], $a[1]); Start-Sleep -Milliseconds 60
  [Stress]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
  for ($i = 1; $i -le 20; $i++) {
    [void][Stress]::SetCursorPos([int]($a[0] + ($b[0] - $a[0]) * $i / 20.0), $a[1])
    Start-Sleep -Milliseconds 16
  }
  [Stress]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
  Start-Sleep -Milliseconds 220
}

"start: working={0:N0} MB private={1:N0} MB" -f ($proc.WorkingSet64/1MB), ($proc.PrivateMemorySize64/1MB)
for ($c = 1; $c -le $Cycles; $c++) {
  Drag 0.706 0.5
  Drag 0.5 0.706
  $proc.Refresh()
  "cycle {0}: working={1:N0} MB private={2:N0} MB" -f $c, ($proc.WorkingSet64/1MB), ($proc.PrivateMemorySize64/1MB)
}
Stop-Process -Id $proc.Id -Force
Write-Host "Done."
