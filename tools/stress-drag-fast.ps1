param(
  [string]$Exe = "release\SoraPos-demo\sora_pos.exe",
  [int]$Seconds = 15
)

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class FastDrag {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hWnd, IntPtr after, int x, int y, int cx, int cy, uint flags);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint flags, uint dx, uint dy, uint data, UIntPtr extra);
  public struct RECT { public int Left, Top, Right, Bottom; }
}
"@
[void][FastDrag]::SetProcessDPIAware()
$exePath = (Resolve-Path $Exe).Path
$proc = Start-Process -FilePath $exePath -WorkingDirectory (Split-Path $exePath) -PassThru
Start-Sleep -Seconds 7
$proc.Refresh(); $hwnd = $proc.MainWindowHandle
if ($hwnd -eq [IntPtr]::Zero) { Write-Host "No window"; exit 1 }
[void][FastDrag]::SetWindowPos($hwnd, [IntPtr](-1), 0, 0, 0, 0, 0x43)
[void][FastDrag]::SetForegroundWindow($hwnd); Start-Sleep -Milliseconds 700

$rect = New-Object FastDrag+RECT
[void][FastDrag]::GetWindowRect($hwnd, [ref]$rect)
$w = $rect.Right - $rect.Left; $h = $rect.Bottom - $rect.Top
$y = [int]($rect.Top + $h * 0.55)
$startX = [int]($rect.Left + $w * 0.706)

"start: working={0:N0} MB private={1:N0} MB" -f ($proc.WorkingSet64/1MB), ($proc.PrivateMemorySize64/1MB)
[void][FastDrag]::SetCursorPos($startX, $y); Start-Sleep -Milliseconds 100
[FastDrag]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)

$deadline = (Get-Date).AddSeconds($Seconds)
$nextSample = (Get-Date)
$i = 0
while ((Get-Date) -lt $deadline) {
  $phase = ($i % 60) / 59.0
  $x = if (($i % 120) -lt 60) {
    [int]($rect.Left + $w * (0.34 + 0.66 * $phase))
  } else {
    [int]($rect.Left + $w * (1.0 - 0.66 * $phase))
  }
  [void][FastDrag]::SetCursorPos($x, $y)
  $i++
  if ((Get-Date) -ge $nextSample) {
    $proc.Refresh()
    "t+{0:N0}s events={1}: working={2:N0} MB private={3:N0} MB" -f ((Get-Date) - ($deadline.AddSeconds(-$Seconds))).TotalSeconds, $i, ($proc.WorkingSet64/1MB), ($proc.PrivateMemorySize64/1MB)
    $nextSample = (Get-Date).AddSeconds(3)
  }
  Start-Sleep -Milliseconds 2
}
[FastDrag]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
Start-Sleep -Milliseconds 1200
$proc.Refresh()
"after release: working={0:N0} MB private={1:N0} MB events={2}" -f ($proc.WorkingSet64/1MB), ($proc.PrivateMemorySize64/1MB), $i
Stop-Process -Id $proc.Id -Force
Write-Host "Done."
