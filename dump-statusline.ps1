[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$raw = [Console]::In.ReadToEnd()
$raw | Out-File (Join-Path (Split-Path $PSScriptRoot -Parent) "statusline-dump.json") -Encoding UTF8 -Force
Write-Host "DUMP OK - check .claude/statusline-dump.json"
