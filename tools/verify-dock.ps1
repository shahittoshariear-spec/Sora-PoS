param(
  [string]$Exe = "build\windows\x64\runner\Release\sora_pos.exe",
  [string]$OutDir = "screenshots"
)

Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class DockTest {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hWnd, IntPtr after, int x, int y, int cx, int cy, uint flags);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint flags, uint dx, uint dy, uint data, UIntPtr extra);
  public struct RECT { public int Left, Top, Right, Bottom; }
}
"@
[void][DockTest]::SetProcessDPIAware()
$env:SORA_START_SECTION = "setup"
$env:SORA_START_PANE = "appearance"
$exePath = (Resolve-Path $Exe).Path
$proc = Start-Process -FilePath $exePath -WorkingDirectory (Split-Path $exePath) -PassThru
Start-Sleep -Seconds 9
$proc.Refresh(); $hwnd = $proc.MainWindowHandle
if ($hwnd -eq [IntPtr]::Zero) { Write-Host "No window"; exit 1 }
[void][DockTest]::SetWindowPos($hwnd, [IntPtr](-1), 0, 0, 0, 0, 0x43)
[void][DockTest]::SetForegroundWindow($hwnd); Start-Sleep -Milliseconds 700

$rect = New-Object DockTest+RECT
[void][DockTest]::GetWindowRect($hwnd, [ref]$rect)
$w = $rect.Right - $rect.Left; $h = $rect.Bottom - $rect.Top
$pt = @([int]($rect.Left + $w * 0.5), [int]($rect.Top + $h * 0.17))
[void][DockTest]::SetCursorPos($pt[0], $pt[1]); Start-Sleep -Milliseconds 150
[DockTest]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
[DockTest]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
Start-Sleep -Milliseconds 400
$pt = @([int]($rect.Left + $w * 0.808), [int]($rect.Top + $h * 0.832))
[void][DockTest]::SetCursorPos($pt[0], $pt[1]); Start-Sleep -Milliseconds 150
[DockTest]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
[DockTest]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
Start-Sleep -Seconds 2

$bmp = New-Object System.Drawing.Bitmap $w, $h
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($rect.Left, $rect.Top, 0, 0, $bmp.Size)
$g.Dispose()
$bmp.Save((Join-Path (Resolve-Path $OutDir).Path "dock-on.png"), [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
Write-Host "Saved dock-on"
Stop-Process -Id $proc.Id -Force
Remove-Item Env:SORA_START_SECTION -ErrorAction SilentlyContinue
Remove-Item Env:SORA_START_PANE -ErrorAction SilentlyContinue
