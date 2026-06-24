# Hook de diagnóstico — despeja o JSON bruto recebido do Claude Code
# Uso: copie para .claude/hooks/dump-hook.ps1 e adicione ao settings.json como Stop hook
# O JSON fica salvo em .claude/hook-dump.json para inspeção

[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$raw = [Console]::In.ReadToEnd()
$outFile = Join-Path (Split-Path $PSScriptRoot -Parent) "hook-dump.json"
$raw | Out-File $outFile -Encoding UTF8 -Force
