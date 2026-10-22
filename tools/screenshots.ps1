param(
  [string]$Exe = "build\windows\x64\runner\Release\sora_pos.exe",
  [string]$OutDir = "screenshots"
)

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class SoraCapture {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hWnd, IntPtr after, int x, int y, int cx, int cy, uint flags);
  public struct RECT { public int Left, Top, Right, Bottom; }
}
"@

[void][SoraCapture]::SetProcessDPIAware()
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$resolved = Resolve-Path $Exe

function Shot([string]$section, [string]$pane, [string]$name) {
  $env:SORA_START_SECTION = $section
  if ($pane -eq "") {
    Remove-Item Env:SORA_START_PANE -ErrorAction SilentlyContinue
  } else {
    $env:SORA_START_PANE = $pane
  }
  $proc = Start-Process -FilePath $resolved -PassThru
  Start-Sleep -Seconds 6
  $proc.Refresh()
  $hwnd = $proc.MainWindowHandle
  if ($hwnd -eq [IntPtr]::Zero) {
    Write-Host "No window for $name"
    if (-not $proc.HasExited) { Stop-Process -Id $proc.Id -Force }
    return
  }
  [void][SoraCapture]::SetWindowPos($hwnd, [IntPtr](-1), 0, 0, 0, 0, 0x43)
  [void][SoraCapture]::SetForegroundWindow($hwnd)
  Start-Sleep -Milliseconds 900

  $rect = New-Object SoraCapture+RECT
  [void][SoraCapture]::GetWindowRect($hwnd, [ref]$rect)
  $w = $rect.Right - $rect.Left
  $h = $rect.Bottom - $rect.Top
  $screen = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
  $bmp = New-Object System.Drawing.Bitmap $screen.Width, $screen.Height
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen($screen.Left, $screen.Top, 0, 0, $bmp.Size)
  $g.Dispose()
  $crop = $bmp.Clone((New-Object System.Drawing.Rectangle $rect.Left, $rect.Top, $w, $h), $bmp.PixelFormat)
  $target = Join-Path (Resolve-Path $OutDir).Path "$name.png"
  $crop.Save($target, [System.Drawing.Imaging.ImageFormat]::Png)
  $crop.Dispose()
  $bmp.Dispose()
  Write-Host "Saved $name ($w x $h)"
  Stop-Process -Id $proc.Id -Force
  Start-Sleep -Milliseconds 500
}

Shot "till" "" "01-till"
Shot "overview" "" "02-overview"
Shot "stock" "" "03-stock"
Shot "ledger" "" "04-ledger"
Shot "reports" "" "05-reports"
Shot "setup" "shop" "06-setup"
Shot "setup" "appearance" "07-appearance"

Remove-Item Env:SORA_START_SECTION -ErrorAction SilentlyContinue
Remove-Item Env:SORA_START_PANE -ErrorAction SilentlyContinue
Write-Host "Done."
