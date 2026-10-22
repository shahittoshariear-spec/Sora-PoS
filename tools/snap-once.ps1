param(
  [string]$Exe = "build\windows\x64\runner\Release\sora_pos.exe",
  [string]$Out = "screenshots\once.png",
  [int]$Wait = 8
)

Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Once {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hWnd, IntPtr after, int x, int y, int cx, int cy, uint flags);
  public struct RECT { public int Left, Top, Right, Bottom; }
}
"@
[void][Once]::SetProcessDPIAware()
$exePath = (Resolve-Path $Exe).Path
$proc = Start-Process -FilePath $exePath -WorkingDirectory (Split-Path $exePath) -PassThru
Start-Sleep -Seconds $Wait
$proc.Refresh(); $hwnd = $proc.MainWindowHandle
if ($hwnd -eq [IntPtr]::Zero) { Write-Host "No window"; Stop-Process -Id $proc.Id -Force; exit 1 }
[void][Once]::SetWindowPos($hwnd, [IntPtr](-1), 0, 0, 0, 0, 0x43)
[void][Once]::SetForegroundWindow($hwnd)
Start-Sleep -Milliseconds 1200
$rect = New-Object Once+RECT
[void][Once]::GetWindowRect($hwnd, [ref]$rect)
$w = $rect.Right - $rect.Left; $h = $rect.Bottom - $rect.Top
$bmp = New-Object System.Drawing.Bitmap $w, $h
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($rect.Left, $rect.Top, 0, 0, $bmp.Size)
$g.Dispose()
New-Item -ItemType Directory -Force -Path (Split-Path $Out) | Out-Null
$bmp.Save((Join-Path (Resolve-Path (Split-Path $Out)).Path (Split-Path $Out -Leaf)), [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
Write-Host "Saved $Out ($w x $h)"
Stop-Process -Id $proc.Id -Force
