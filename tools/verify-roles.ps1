param(
  [string]$Exe = "build\windows\x64\runner\Release\sora_pos.exe",
  [string]$OutDir = "screenshots\roles"
)

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Roles {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hWnd, IntPtr after, int x, int y, int cx, int cy, uint flags);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint flags, uint dx, uint dy, uint data, UIntPtr extra);
  public struct RECT { public int Left, Top, Right, Bottom; }
}
"@
[void][Roles]::SetProcessDPIAware()
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$exePath = (Resolve-Path $Exe).Path

function Snap([string]$name, [IntPtr]$hwnd) {
  $rect = New-Object Roles+RECT
  [void][Roles]::GetWindowRect($hwnd, [ref]$rect)
  $w = $rect.Right - $rect.Left; $h = $rect.Bottom - $rect.Top
  $bmp = New-Object System.Drawing.Bitmap $w, $h
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen($rect.Left, $rect.Top, 0, 0, $bmp.Size)
  $g.Dispose()
  $bmp.Save((Join-Path (Resolve-Path $OutDir).Path "$name.png"), [System.Drawing.Imaging.ImageFormat]::Png)
  $bmp.Dispose(); Write-Host "Saved $name"
}

function SignIn([double]$tileY, [string]$password, [string]$name) {
  $proc = Start-Process -FilePath $exePath -WorkingDirectory (Split-Path $exePath) -PassThru
  Start-Sleep -Seconds 10
  $proc.Refresh(); $hwnd = $proc.MainWindowHandle
  [void][Roles]::SetWindowPos($hwnd, [IntPtr](-1), 0, 0, 0, 0, 0x43)
  [void][Roles]::SetForegroundWindow($hwnd); Start-Sleep -Milliseconds 700
  $rect = New-Object Roles+RECT
  [void][Roles]::GetWindowRect($hwnd, [ref]$rect)
  $x = [int]($rect.Left + ($rect.Right - $rect.Left) * 0.61)
  $y = [int]($rect.Top + ($rect.Bottom - $rect.Top) * $tileY)
  [void][Roles]::SetCursorPos($x, $y); Start-Sleep -Milliseconds 120
  [Roles]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
  [Roles]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
  Start-Sleep -Milliseconds 250
  [Roles]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
  [Roles]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
  Write-Host "clicked $name at $x,$y"
  Start-Sleep -Milliseconds 1400
  Snap "$name-dialog" $hwnd
  [System.Windows.Forms.SendKeys]::SendWait($password)
  Start-Sleep -Milliseconds 500
  [System.Windows.Forms.SendKeys]::SendWait("{ENTER}")
  Start-Sleep -Milliseconds 2600
  Snap $name $hwnd
  Stop-Process -Id $proc.Id -Force
  Start-Sleep -Milliseconds 500
}

SignIn 0.502 "manager1234" "manager"
SignIn 0.583 "cashier1234" "cashier"
Write-Host "Done."
