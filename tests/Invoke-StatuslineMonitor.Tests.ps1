#Requires -Module Pester
<#
.SYNOPSIS
    Tests for .claude/hooks/statusline-monitor.ps1
.DESCRIPTION
    Runs the statusline-monitor.ps1 script via a child process, passing JSON via stdin,
    and asserts on the captured stdout output.
#>

BeforeAll {
    . "$PSScriptRoot\helpers\New-TestPayload.ps1"

    $ProjectRoot = Split-Path $PSScriptRoot -Parent
    $Script:ScriptPath = Join-Path $ProjectRoot ".claude\hooks\statusline-monitor.ps1"

    # Helper: pipe JSON string to the script and capture stdout (ANSI stripped)
    function Invoke-StatuslineMonitor {
        param([string]$Json)

        $psi = [System.Diagnostics.ProcessStartInfo]::new()
        $psi.FileName               = "powershell.exe"
        $psi.Arguments              = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$Script:ScriptPath`""
        $psi.UseShellExecute        = $false
        $psi.RedirectStandardInput  = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError  = $true

        $proc = [System.Diagnostics.Process]::Start($psi)
        $proc.StandardInput.WriteLine($Json)
        $proc.StandardInput.Close()

        $stdout = $proc.StandardOutput.ReadToEnd()
        $proc.WaitForExit(15000) | Out-Null

        # Strip ANSI escape sequences so assertions are colour-agnostic
        $clean = $stdout -replace '\x1b\[[0-9;]*[mK]', ''
        return $clean.Trim()
    }
}

Describe "statusline-monitor.ps1 - percentage calculation" {

    It "calculates 73% when tokens sum to 146000 of 200000 budget" {
        $payload = New-TestPayload -BudgetTokens 200000 -InputTokens 100000 -OutputTokens 20000 -CacheWriteTokens 16000 -CacheReadTokens 10000
        $json    = $payload | ConvertTo-Json -Depth 5
        $out     = Invoke-StatuslineMonitor -Json $json
        $out | Should -Match '73%'
    }

    It "applies ceil so 170001/200000 = 86% (not 85%)" {
        # 170001 / 200000 * 100 = 85.0005 -> ceil = 86
        $payload = New-TestPayload -BudgetTokens 200000 -InputTokens 170001
        $json    = $payload | ConvertTo-Json -Depth 5
        $out     = Invoke-StatuslineMonitor -Json $json
        $out | Should -Match '86%'
    }

    It "falls back to used_percentage when budget_tokens is 0" {
        $payload = New-TestPayload -BudgetTokens 0 -UsedPercentage 45
        $json    = $payload | ConvertTo-Json -Depth 5
        $out     = Invoke-StatuslineMonitor -Json $json
        $out | Should -Match '45%'
    }
}

Describe "statusline-monitor.ps1 - robustness" {

    It "does not crash and produces no output on empty input" {
        $out = Invoke-StatuslineMonitor -Json ""
        # Empty input should be silent (exit 0)
        $out | Should -BeNullOrEmpty
    }

    It "does not crash on invalid JSON" {
        # Script should exit 0 silently on bad JSON; just verify the helper call completes
        $out = Invoke-StatuslineMonitor -Json "{ this is not valid json !!!"
        # Output will be empty because the script exits early on parse failure
        $out | Should -BeNullOrEmpty
    }
}

Describe "statusline-monitor.ps1 - rate limit fields" {

    It "shows 5h percentage in output" {
        $payload = New-TestPayload -BudgetTokens 200000 -InputTokens 10000 -Pct5h 32
        $json    = $payload | ConvertTo-Json -Depth 5
        $out     = Invoke-StatuslineMonitor -Json $json
        $out | Should -Match '5h:.*32%'
    }

    It "shows weekly percentage in output" {
        $payload = New-TestPayload -BudgetTokens 200000 -InputTokens 10000 -PctWeek 17
        $json    = $payload | ConvertTo-Json -Depth 5
        $out     = Invoke-StatuslineMonitor -Json $json
        $out | Should -Match 'Week:.*17%'
    }

    It "shows reset time when resets_at is provided" {
        # Use a future Unix timestamp; we just need to verify a HH:mm appears
        $futureTs = [long][DateTimeOffset]::UtcNow.AddHours(2).ToUnixTimeSeconds()
        $payload  = New-TestPayload -BudgetTokens 200000 -InputTokens 10000 -ResetsAt $futureTs
        $json     = $payload | ConvertTo-Json -Depth 5
        $out      = Invoke-StatuslineMonitor -Json $json
        # Should contain a time like "reset 14:30" — match HH:mm pattern
        $out | Should -Match 'reset \d{2}:\d{2}'
    }

    It "shows '?' for reset time when resets_at is 0" {
        $payload = New-TestPayload -BudgetTokens 200000 -InputTokens 10000 -ResetsAt 0
        $json    = $payload | ConvertTo-Json -Depth 5
        $out     = Invoke-StatuslineMonitor -Json $json
        $out | Should -Match 'reset \?'
    }
}

Describe "statusline-monitor.ps1 - cost display" {

    It "shows total_cost_usd as dollar amount" {
        $payload = New-TestPayload -BudgetTokens 200000 -InputTokens 10000 -TotalCostUsd 0.042
        $json    = $payload | ConvertTo-Json -Depth 5
        $out     = Invoke-StatuslineMonitor -Json $json
        # The script uses PowerShell's -f format which respects system locale
        # (e.g. "0.042" on en-US, "0,042" on pt-BR). Match either decimal separator.
        $out | Should -Match '\$0[.,]042'
    }

    It "shows zero cost when not provided" {
        $payload = New-TestPayload -BudgetTokens 200000 -InputTokens 10000
        $json    = $payload | ConvertTo-Json -Depth 5
        $out     = Invoke-StatuslineMonitor -Json $json
        # Locale-agnostic: accept dot or comma as decimal separator
        $out | Should -Match '\$0[.,]000'
    }
}

Describe "statusline-monitor.ps1 - model name" {

    It "shows model display name in output" {
        $payload = New-TestPayload -BudgetTokens 200000 -InputTokens 10000 -ModelName "Claude Sonnet 4.6"
        $json    = $payload | ConvertTo-Json -Depth 5
        $out     = Invoke-StatuslineMonitor -Json $json
        $out | Should -Match 'Claude Sonnet 4\.6'
    }
}

Describe "statusline-monitor.ps1 - alert levels" {

    It "shows FREE when pct < 20" {
        $payload = New-TestPayload -BudgetTokens 200000 -InputTokens 5000
        $json    = $payload | ConvertTo-Json -Depth 5
        $out     = Invoke-StatuslineMonitor -Json $json
        $out | Should -Match 'FREE'
    }

    It "shows OK when pct >= 20 and < 70" {
        $payload = New-TestPayload -BudgetTokens 200000 -InputTokens 80000
        $json    = $payload | ConvertTo-Json -Depth 5
        $out     = Invoke-StatuslineMonitor -Json $json
        $out | Should -Match 'OK'
    }

    It "shows ATN when pct >= 70 and < 85" {
        $payload = New-TestPayload -BudgetTokens 200000 -InputTokens 146000
        $json    = $payload | ConvertTo-Json -Depth 5
        $out     = Invoke-StatuslineMonitor -Json $json
        $out | Should -Match 'ATN'
    }

    It "shows WARN when pct >= 85 and < 95" {
        $payload = New-TestPayload -BudgetTokens 200000 -InputTokens 172000
        $json    = $payload | ConvertTo-Json -Depth 5
        $out     = Invoke-StatuslineMonitor -Json $json
        $out | Should -Match 'WARN'
    }

    It "shows CRIT when pct >= 95" {
        $payload = New-TestPayload -BudgetTokens 200000 -InputTokens 191000
        $json    = $payload | ConvertTo-Json -Depth 5
        $out     = Invoke-StatuslineMonitor -Json $json
        $out | Should -Match 'CRIT'
    }
}
