param(
  [string]$Folder = "release\SoraPos-demo"
)
$resolved = Resolve-Path $Folder
$exe = Join-Path $resolved.Path "sora_pos.exe"
$proc = Start-Process -FilePath $exe -WorkingDirectory $resolved.Path -PassThru
Start-Sleep -Seconds 14
$proc.Refresh()
Write-Host "exited=$($proc.HasExited) title=$($proc.MainWindowTitle)"
$dataDir = Join-Path $env:APPDATA "Sora PoS"
Write-Host "data exists: $(Test-Path (Join-Path $dataDir 'sora-pos-data.json'))"
Write-Host "sidecar exists: $(Test-Path (Join-Path $dataDir 'bin\sora_core.exe'))"
Write-Host "error log exists: $(Test-Path (Join-Path $dataDir 'sora-errors.log'))"
if (Test-Path (Join-Path $dataDir 'sora-errors.log')) {
  Get-Content (Join-Path $dataDir 'sora-errors.log') -Tail 30
}
if (-not $proc.HasExited) { Stop-Process -Id $proc.Id -Force }
Write-Host "Done."
