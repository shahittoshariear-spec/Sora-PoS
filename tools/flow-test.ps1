param(
  [string]$Exe = "build\windows\x64\runner\Release\sora_pos.exe",
  [string]$OutDir = "screenshots"
)

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Flow3 {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hWnd, IntPtr after, int x, int y, int cx, int cy, uint flags);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint flags, uint dx, uint dy, uint data, UIntPtr extra);
  public struct RECT { public int Left, Top, Right, Bottom; }
}
"@
[void][Flow3]::SetProcessDPIAware()
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$proc = Start-Process -FilePath (Resolve-Path $Exe) -PassThru
Start-Sleep -Seconds 6
$proc.Refresh(); $hwnd = $proc.MainWindowHandle
[void][Flow3]::SetWindowPos($hwnd, [IntPtr](-1), 0, 0, 0, 0, 0x43)
[void][Flow3]::SetForegroundWindow($hwnd); Start-Sleep -Milliseconds 700

function Snap([string]$name) {
  $rect = New-Object Flow3+RECT
  [void][Flow3]::GetWindowRect($hwnd, [ref]$rect)
  $w = $rect.Right - $rect.Left; $h = $rect.Bottom - $rect.Top
  $bmp = New-Object System.Drawing.Bitmap $w, $h
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen($rect.Left, $rect.Top, 0, 0, $bmp.Size)
  $g.Dispose()
  $bmp.Save((Join-Path (Resolve-Path $OutDir).Path "$name.png"), [System.Drawing.Imaging.ImageFormat]::Png)
  $bmp.Dispose(); Write-Host "Saved $name"
}

function Click([double]$fx, [double]$fy) {
  $rect = New-Object Flow3+RECT
  [void][Flow3]::GetWindowRect($hwnd, [ref]$rect)
  $x = [int]($rect.Left + ($rect.Right-$rect.Left)*$fx)
  $y = [int]($rect.Top + ($rect.Bottom-$rect.Top)*$fy)
  [void][Flow3]::SetWindowPos($hwnd, [IntPtr](-1), 0, 0, 0, 0, 0x43)
  [void][Flow3]::SetForegroundWindow($hwnd); Start-Sleep -Milliseconds 200
  [void][Flow3]::SetCursorPos($x, $y); Start-Sleep -Milliseconds 100
  [Flow3]::mouse_event(0x0002,0,0,0,[UIntPtr]::Zero)
  [Flow3]::mouse_event(0x0004,0,0,0,[UIntPtr]::Zero)
  Start-Sleep -Milliseconds 800
}

Click 0.247 0.315
[System.Windows.Forms.SendKeys]::SendWait("{F8}")
Start-Sleep -Milliseconds 1200
Snap "flow3-01-payment"
[System.Windows.Forms.SendKeys]::SendWait("500")
Start-Sleep -Milliseconds 500
Snap "flow3-02-tendered"
[System.Windows.Forms.SendKeys]::SendWait("{ENTER}")
Start-Sleep -Seconds 3
Snap "flow3-03-receipt"
Stop-Process -Id $proc.Id -Force
Write-Host "Done."
