$p = Join-Path $env:APPDATA "Sora PoS\sora-pos-data.json"
$enc = New-Object System.Text.UTF8Encoding($false)
$text = [IO.File]::ReadAllText($p, [Text.Encoding]::UTF8)
$text = $text.Replace('"dockNav": false', '"dockNav": true')
[IO.File]::WriteAllText($p, $text, $enc)
Write-Host "dock enabled"
