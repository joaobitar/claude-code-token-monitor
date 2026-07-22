[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$claudeDir = Split-Path $PSScriptRoot -Parent
$alertFile = Join-Path $claudeDir "pending-5h-alert.json"

if (Test-Path $alertFile) {
    try {
        $alert = Get-Content $alertFile -Raw | ConvertFrom-Json
        Remove-Item $alertFile -Force -ErrorAction SilentlyContinue

        $reason = "Uso de tokens do intervalo de 5 horas atingiu $($alert.pct5h)% (limite configurado: $($alert.threshold)%). O CONTEXT.md ja foi salvo automaticamente (trigger: threshold_5h_ratelimit). Informe o usuario que o uso esta proximo do limite da janela de 5h e pergunte se deseja agendar um reinicio automatico, sugerindo o horario do proximo reset: $($alert.resetStr)."

        @{ decision = "block"; reason = $reason } | ConvertTo-Json -Compress | Write-Host
        exit 0
    } catch {}
}

exit 0
