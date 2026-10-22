param(
  [string]$Exe = "build\windows\x64\runner\Release\sora_pos.exe",
  [string]$OutDir = "screenshots\picker"
)

Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Picker {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hWnd, IntPtr after, int x, int y, int cx, int cy, uint flags);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint flags, uint dx, uint dy, uint data, UIntPtr extra);
  public struct RECT { public int Left, Top, Right, Bottom; }
}
"@
[void][Picker]::SetProcessDPIAware()
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$env:SORA_START_SECTION = "setup"
$env:SORA_START_PANE = "appearance"
$exePath = (Resolve-Path $Exe).Path
$proc = Start-Process -FilePath $exePath -WorkingDirectory (Split-Path $exePath) -PassThru
Start-Sleep -Seconds 7
$proc.Refresh(); $hwnd = $proc.MainWindowHandle
if ($hwnd -eq [IntPtr]::Zero) { Write-Host "No window"; exit 1 }
[void][Picker]::SetWindowPos($hwnd, [IntPtr](-1), 0, 0, 0, 0, 0x43)
[void][Picker]::SetForegroundWindow($hwnd); Start-Sleep -Milliseconds 700

$rect = New-Object Picker+RECT
[void][Picker]::GetWindowRect($hwnd, [ref]$rect)
$w = $rect.Right - $rect.Left; $h = $rect.Bottom - $rect.Top

function P([double]$fx, [double]$fy) { @([int]($rect.Left + $w * $fx), [int]($rect.Top + $h * $fy)) }

function Click([double]$fx, [double]$fy) {
  $pt = P $fx $fy
  [void][Picker]::SetCursorPos($pt[0], $pt[1]); Start-Sleep -Milliseconds 120
  [Picker]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
  [Picker]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
}

function Snap([string]$name) {
  $bmp = New-Object System.Drawing.Bitmap $w, $h
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen($rect.Left, $rect.Top, 0, 0, $bmp.Size)
  $g.Dispose()
  $bmp.Save((Join-Path (Resolve-Path $OutDir).Path "$name.png"), [System.Drawing.Imaging.ImageFormat]::Png)
  $bmp.Dispose(); Write-Host "Saved $name"
}

# Open the first custom theme's editor.
Click 0.806 0.398
Start-Sleep -Milliseconds 1000
Snap "01-dialog"

# The accent slot sits on the left of the two colour slots.
Click 0.415 0.508
Start-Sleep -Milliseconds 900
Snap "02-picker"

# Drag inside the saturation/value square, low and to the left.
$from = P 0.568 0.403
$to = P 0.43 0.53
[void][Picker]::SetCursorPos($from[0], $from[1]); Start-Sleep -Milliseconds 120
[Picker]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
for ($i = 1; $i -le 24; $i++) {
  [void][Picker]::SetCursorPos([int]($from[0] + ($to[0] - $from[0]) * $i / 24.0), [int]($from[1] + ($to[1] - $from[1]) * $i / 24.0))
  Start-Sleep -Milliseconds 12
}
[Picker]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
Start-Sleep -Milliseconds 450
Snap "03-dragged"

Stop-Process -Id $proc.Id -Force
Remove-Item Env:SORA_START_SECTION -ErrorAction SilentlyContinue
Remove-Item Env:SORA_START_PANE -ErrorAction SilentlyContinue
Write-Host "Done."
