param(
  [string]$Exe = "build\windows\x64\runner\Release\sora_pos.exe",
  [string]$OutDir = "screenshots\motion"
)

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Motion {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hWnd, IntPtr after, int x, int y, int cx, int cy, uint flags);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint flags, uint dx, uint dy, uint data, UIntPtr extra);
  public struct RECT { public int Left, Top, Right, Bottom; }
}
"@
[void][Motion]::SetProcessDPIAware()
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$env:SORA_START_SECTION = "setup"
$env:SORA_START_PANE = "appearance"
$env:SORA_STILL = "1"
$proc = Start-Process -FilePath (Resolve-Path $Exe) -PassThru
Start-Sleep -Seconds 7
$proc.Refresh(); $hwnd = $proc.MainWindowHandle
if ($hwnd -eq [IntPtr]::Zero) { Write-Host "No window"; exit 1 }
[void][Motion]::SetWindowPos($hwnd, [IntPtr](-1), 0, 0, 0, 0, 0x43)
[void][Motion]::SetForegroundWindow($hwnd); Start-Sleep -Milliseconds 800

$rect = New-Object Motion+RECT
[void][Motion]::GetWindowRect($hwnd, [ref]$rect)
$w = $rect.Right - $rect.Left
$h = $rect.Bottom - $rect.Top

function Snap([string]$name) {
  $bmp = New-Object System.Drawing.Bitmap $w, $h
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen($rect.Left, $rect.Top, 0, 0, $bmp.Size)
  $g.Dispose()
  $bmp.Save((Join-Path (Resolve-Path $OutDir).Path "$name.png"), [System.Drawing.Imaging.ImageFormat]::Png)
  $bmp.Dispose(); Write-Host "Saved $name"
}

function ScreenPoint([double]$fx, [double]$fy) {
  return @([int]($rect.Left + $w * $fx), [int]($rect.Top + $h * $fy))
}

function ClickAt([double]$fx, [double]$fy) {
  $pt = ScreenPoint $fx $fy
  [void][Motion]::SetCursorPos($pt[0], $pt[1]); Start-Sleep -Milliseconds 80
  [Motion]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
  [Motion]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
}

# Theme spread: Aurora Blue tile, captured while the reveal is still travelling.
Snap "01-before-theme"
ClickAt 0.508 0.298
Start-Sleep -Milliseconds 190
Snap "02-theme-spread-early"
Start-Sleep -Milliseconds 200
Snap "03-theme-spread-mid"
Start-Sleep -Milliseconds 900
Snap "04-theme-spread-done"

# Static backdrop: the same screen with the cursor at opposite edges must be
# identical. SORA_STILL freezes the small S.S sweep so only backdrop motion would
# change the image.
$l = ScreenPoint 0.12 0.5
$r = ScreenPoint 0.88 0.5
[void][Motion]::SetCursorPos($l[0], $l[1]); Start-Sleep -Milliseconds 800
Snap "05-static-left"
[void][Motion]::SetCursorPos($r[0], $r[1]); Start-Sleep -Milliseconds 800
Snap "06-static-right"
$leftHash = (Get-FileHash (Join-Path (Resolve-Path $OutDir).Path "05-static-left.png") -Algorithm SHA256).Hash
$rightHash = (Get-FileHash (Join-Path (Resolve-Path $OutDir).Path "06-static-right.png") -Algorithm SHA256).Hash
Write-Host "static-backdrop-identical=$($leftHash -eq $rightHash)"

# Tear down and open the till to verify the draggable receipt divider.
Stop-Process -Id $proc.Id -Force
Start-Sleep -Milliseconds 600
Remove-Item Env:SORA_START_SECTION -ErrorAction SilentlyContinue
Remove-Item Env:SORA_START_PANE -ErrorAction SilentlyContinue
$proc = Start-Process -FilePath (Resolve-Path $Exe) -PassThru
Start-Sleep -Seconds 6
$proc.Refresh(); $hwnd = $proc.MainWindowHandle
[void][Motion]::SetWindowPos($hwnd, [IntPtr](-1), 0, 0, 0, 0, 0x43)
[void][Motion]::SetForegroundWindow($hwnd); Start-Sleep -Milliseconds 700
[void][Motion]::GetWindowRect($hwnd, [ref]$rect)
$w = $rect.Right - $rect.Left; $h = $rect.Bottom - $rect.Top
Snap "07-till-before-drag"

$grip = ScreenPoint 0.706 0.55
$target = ScreenPoint 0.545 0.55
[void][Motion]::SetCursorPos($grip[0], $grip[1]); Start-Sleep -Milliseconds 200
[Motion]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
for ($i = 1; $i -le 24; $i++) {
  $x = [int]($grip[0] + ($target[0] - $grip[0]) * $i / 24.0)
  [void][Motion]::SetCursorPos($x, $grip[1])
  Start-Sleep -Milliseconds 12
}
[Motion]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
Start-Sleep -Milliseconds 600
Snap "08-till-after-drag"

Stop-Process -Id $proc.Id -Force
Remove-Item Env:SORA_STILL -ErrorAction SilentlyContinue
Write-Host "Done."
