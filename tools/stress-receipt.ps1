param(
  [string]$Exe = "build\windows\x64\runner\Release\sora_pos.exe",
  [int]$Seconds = 20
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class ReceiptStress {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hWnd, IntPtr after, int x, int y, int cx, int cy, uint flags);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint flags, uint dx, uint dy, uint data, UIntPtr extra);
  public struct RECT { public int Left, Top, Right, Bottom; }
}
"@
[void][ReceiptStress]::SetProcessDPIAware()
$exePath = (Resolve-Path $Exe).Path
$proc = Start-Process -FilePath $exePath -WorkingDirectory (Split-Path $exePath) -PassThru
Start-Sleep -Seconds 7
$proc.Refresh(); $hwnd = $proc.MainWindowHandle
if ($hwnd -eq [IntPtr]::Zero) { Write-Host "No window"; exit 1 }
[void][ReceiptStress]::SetWindowPos($hwnd, [IntPtr](-1), 0, 0, 0, 0, 0x43)
[void][ReceiptStress]::SetForegroundWindow($hwnd); Start-Sleep -Milliseconds 700

$rect = New-Object ReceiptStress+RECT
[void][ReceiptStress]::GetWindowRect($hwnd, [ref]$rect)
$w = $rect.Right - $rect.Left; $h = $rect.Bottom - $rect.Top
function P([double]$fx, [double]$fy) { @([int]($rect.Left + $w * $fx), [int]($rect.Top + $h * $fy)) }
function Click([double]$fx, [double]$fy) {
  $pt = P $fx $fy
  [void][ReceiptStress]::SetCursorPos($pt[0], $pt[1]); Start-Sleep -Milliseconds 120
  [ReceiptStress]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
  [ReceiptStress]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
}

# Add the first product, pay cash 500, and wait for the sale-complete sheet.
Click 0.269 0.337
Start-Sleep -Milliseconds 500
[System.Windows.Forms.SendKeys]::SendWait("{F8}")
Start-Sleep -Milliseconds 900
[System.Windows.Forms.SendKeys]::SendWait("500")
Start-Sleep -Milliseconds 400
[System.Windows.Forms.SendKeys]::SendWait("{ENTER}")
Start-Sleep -Seconds 2

"start: working={0:N0} MB private={1:N0} MB" -f ($proc.WorkingSet64/1MB), ($proc.PrivateMemorySize64/1MB)
$handle = P 0.448 0.511
[void][ReceiptStress]::SetCursorPos($handle[0], $handle[1]); Start-Sleep -Milliseconds 150
[ReceiptStress]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)

$deadline = (Get-Date).AddSeconds($Seconds)
$nextSample = (Get-Date)
$i = 0
while ((Get-Date) -lt $deadline) {
  $phase = ($i % 60) / 59.0
  $x = if (($i % 120) -lt 60) {
    [int]($rect.Left + $w * (0.44 + 0.24 * $phase))
  } else {
    [int]($rect.Left + $w * (0.68 - 0.24 * $phase))
  }
  [void][ReceiptStress]::SetCursorPos($x, $handle[1])
  $i++
  if ((Get-Date) -ge $nextSample) {
    $proc.Refresh()
    "t+{0:N0}s events={1}: working={2:N0} MB private={3:N0} MB" -f ((Get-Date) - ($deadline.AddSeconds(-$Seconds))).TotalSeconds, $i, ($proc.WorkingSet64/1MB), ($proc.PrivateMemorySize64/1MB)
    $nextSample = (Get-Date).AddSeconds(3)
  }
  Start-Sleep -Milliseconds 2
}
[ReceiptStress]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
Start-Sleep -Milliseconds 1000
$proc.Refresh()
"after release: working={0:N0} MB private={1:N0} MB events={2}" -f ($proc.WorkingSet64/1MB), ($proc.PrivateMemorySize64/1MB), $i
Stop-Process -Id $proc.Id -Force
Write-Host "Done."
