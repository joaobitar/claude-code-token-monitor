[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# statusline-monitor.ps1 is the only hook with rate-limit data (Stop payload
# doesn't include context_window/rate_limits), so it drops pending-5h-alert.json
# here when the 5h rate-limit threshold is crossed. This hook is what Claude
# Code actually feeds back to the model - statusLine output is terminal-only
# and invisible to the model. Blocking the stop with a reason forces Claude to
# relay the warning and ask about scheduling a restart before it hands control
# back to the user.
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
