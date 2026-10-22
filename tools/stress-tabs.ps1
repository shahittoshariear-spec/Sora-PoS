param(
  [string]$Exe = "build\windows\x64\runner\Release\sora_pos.exe",
  [string]$OutDir = "screenshots\tabs",
  [int]$Cycles = 4
)

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Tabs {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hWnd, IntPtr after, int x, int y, int cx, int cy, uint flags);
  public struct RECT { public int Left, Top, Right, Bottom; }
}
"@
[void][Tabs]::SetProcessDPIAware()
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$exePath = (Resolve-Path $Exe).Path
$proc = Start-Process -FilePath $exePath -WorkingDirectory (Split-Path $exePath) -PassThru
Start-Sleep -Seconds 7
$proc.Refresh(); $hwnd = $proc.MainWindowHandle
if ($hwnd -eq [IntPtr]::Zero) { Write-Host "No window"; exit 1 }
[void][Tabs]::SetWindowPos($hwnd, [IntPtr](-1), 0, 0, 0, 0, 0x43)
[void][Tabs]::SetForegroundWindow($hwnd); Start-Sleep -Milliseconds 700

$rect = New-Object Tabs+RECT
[void][Tabs]::GetWindowRect($hwnd, [ref]$rect)
$w = $rect.Right - $rect.Left; $h = $rect.Bottom - $rect.Top
function Snap([string]$name) {
  $bmp = New-Object System.Drawing.Bitmap $w, $h
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen($rect.Left, $rect.Top, 0, 0, $bmp.Size)
  $g.Dispose()
  $bmp.Save((Join-Path (Resolve-Path $OutDir).Path "$name.png"), [System.Drawing.Imaging.ImageFormat]::Png)
  $bmp.Dispose(); Write-Host "Saved $name"
}

"start: working={0:N0} MB private={1:N0} MB" -f ($proc.WorkingSet64/1MB), ($proc.PrivateMemorySize64/1MB)
$pages = @(
  @('{F2}', 'stock'),
  @('{F3}', 'ledger'),
  @('{F4}', 'overview'),
  @('{F5}', 'reports'),
  @('{F6}', 'setup'),
  @('{F1}', 'till')
)
for ($cycle = 1; $cycle -le $Cycles; $cycle++) {
  foreach ($page in $pages) {
    [System.Windows.Forms.SendKeys]::SendWait($page[0])
    Start-Sleep -Milliseconds 450
    if ($cycle -eq 1) { Snap ("{0:D2}-{1}" -f [array]::IndexOf($pages, $page), $page[1]) }
    if ($cycle -eq 2) { Start-Sleep -Milliseconds 80 }
  }
  $proc.Refresh()
  "cycle {0}: working={1:N0} MB private={2:N0} MB" -f $cycle, ($proc.WorkingSet64/1MB), ($proc.PrivateMemorySize64/1MB)
}
Stop-Process -Id $proc.Id -Force
Write-Host "Done."
