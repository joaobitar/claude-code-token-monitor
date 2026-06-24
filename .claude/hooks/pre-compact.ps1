[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$raw         = [Console]::In.ReadToEnd()
$projectRoot = if ($env:CLAUDE_PROJECT_DIR) { $env:CLAUDE_PROJECT_DIR } else { (Get-Location).Path }

$trigger = "pre_compact"
try { $json = $raw | ConvertFrom-Json; if ($json.trigger) { $trigger = $json.trigger } } catch {}

& (Join-Path $PSScriptRoot "save-context.ps1") -Trigger $trigger -ProjectRoot $projectRoot
