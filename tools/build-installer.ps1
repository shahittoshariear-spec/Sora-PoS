param(
  [string]$Iscc = "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe",
  [string]$Script = "installer\sora_pos.iss"
)

if (-not (Test-Path $Iscc)) {
  $fallback = "C:\Program Files (x86)\Inno Setup 6\ISCC.exe"
  if (Test-Path $fallback) {
    $Iscc = $fallback
  } else {
    Write-Error "Inno Setup 6 was not found. Install it, or pass -Iscc <path to ISCC.exe>."
    exit 1
  }
}

& $Iscc $Script
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Write-Host "Installer written to release\."
