param(
  [string]$Exe = "build\windows\x64\runner\Release\sora_pos.exe",
  [string]$OutDir = "screenshots"
)

Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Guide {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hWnd, IntPtr after, int x, int y, int cx, int cy, uint flags);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint flags, uint dx, uint dy, uint data, UIntPtr extra);
  public struct RECT { public int Left, Top, Right, Bottom; }
}
"@
[void][Guide]::SetProcessDPIAware()
$exePath = (Resolve-Path $Exe).Path
$proc = Start-Process -FilePath $exePath -WorkingDirectory (Split-Path $exePath) -PassThru
Start-Sleep -Seconds 7
$proc.Refresh(); $hwnd = $proc.MainWindowHandle
if ($hwnd -eq [IntPtr]::Zero) { Write-Host "No window"; exit 1 }
[void][Guide]::SetWindowPos($hwnd, [IntPtr](-1), 0, 0, 0, 0, 0x43)
[void][Guide]::SetForegroundWindow($hwnd); Start-Sleep -Milliseconds 700

$rect = New-Object Guide+RECT
[void][Guide]::GetWindowRect($hwnd, [ref]$rect)
$w = $rect.Right - $rect.Left; $h = $rect.Bottom - $rect.Top
function Snap([string]$name) {
  $bmp = New-Object System.Drawing.Bitmap $w, $h
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen($rect.Left, $rect.Top, 0, 0, $bmp.Size)
  $g.Dispose()
  $bmp.Save((Join-Path (Resolve-Path $OutDir).Path "$name.png"), [System.Drawing.Imaging.ImageFormat]::Png)
  $bmp.Dispose(); Write-Host "Saved $name"
}

$y = [int]($rect.Top + $h * 0.55)
$startX = [int]($rect.Left + $w * 0.696)
$endX = [int]($rect.Left + $w * 0.45)
# Focus click on the header, so the next press is not consumed by activation.
$focusX = [int]($rect.Left + $w * 0.5)
$focusY = [int]($rect.Top + $h * 0.07)
[void][Guide]::SetCursorPos($focusX, $focusY); Start-Sleep -Milliseconds 120
[Guide]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
[Guide]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
Start-Sleep -Milliseconds 300
[void][Guide]::SetCursorPos($startX, $y); Start-Sleep -Milliseconds 150
[Guide]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
for ($i = 1; $i -le 20; $i++) {
  [void][Guide]::SetCursorPos([int]($startX + ($endX - $startX) * $i / 20.0), $y)
  Start-Sleep -Milliseconds 14
}
Start-Sleep -Milliseconds 300
Snap "drag-guide"
[Guide]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
Start-Sleep -Milliseconds 700
Snap "drag-guide-released"
Stop-Process -Id $proc.Id -Force
Write-Host "Done."
