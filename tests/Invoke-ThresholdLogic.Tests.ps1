#Requires -Module Pester
<#
.SYNOPSIS
    Tests for threshold logic in statusline-monitor.ps1.
.DESCRIPTION
    Tests the 70/85/95% threshold state machine by running the script with a temporary
    .claude/ directory (via a wrapper that pre-seeds the threshold-state.json) and
    verifying the resulting state file after each run.

    Strategy: we point PSScriptRoot inside a temp directory that mimics the .claude/hooks/
    structure, so the script writes threshold-state.json to our temp location.
    We use a thin wrapper script that dot-sources nothing — instead we pass the real
    script path but override its hooks/claude dirs by placing a symlink-like copy.

    Simpler alternative used here: we create a copy of statusline-monitor.ps1 in a
    temp directory so that $PSScriptRoot resolves to our controlled location, letting
    us pre-seed and read threshold-state.json without touching the real project.
#>

BeforeAll {
    . "$PSScriptRoot\helpers\New-TestPayload.ps1"

    $ProjectRoot   = Split-Path $PSScriptRoot -Parent
    $RealScript    = Join-Path $ProjectRoot ".claude\hooks\statusline-monitor.ps1"

    # We need save-context.ps1 too (threshold logic calls it via Start-Process)
    $RealSaveCtx   = Join-Path $ProjectRoot ".claude\hooks\save-context.ps1"

    # Build a temp directory that mimics .claude/hooks/ so $PSScriptRoot points there.
    # We copy both scripts into it; threshold-state.json will be written one level up.
    $Script:TmpBase  = Join-Path ([System.IO.Path]::GetTempPath()) "pester-threshold-$(Get-Random)"
    $Script:TmpHooks = Join-Path $Script:TmpBase ".claude\hooks"
    $Script:TmpClaude= Join-Path $Script:TmpBase ".claude"

    New-Item -ItemType Directory -Path $Script:TmpHooks -Force | Out-Null

    $Script:TmpScript  = Join-Path $Script:TmpHooks "statusline-monitor.ps1"
    $Script:TmpSaveCtx = Join-Path $Script:TmpHooks "save-context.ps1"

    Copy-Item -Path $RealScript  -Destination $Script:TmpScript
    Copy-Item -Path $RealSaveCtx -Destination $Script:TmpSaveCtx

    $Script:StateFile = Join-Path $Script:TmpClaude "threshold-state.json"

    # Helper: write a state file, run the monitor with given pct, return resulting state
    function Invoke-MonitorWithState {
        param(
            [hashtable]$InitialState = $null,
            [int]$Pct                = 0,
            [long]$BudgetTokens      = 200000
        )

        # Seed state file
        if ($InitialState) {
            $InitialState | ConvertTo-Json | Out-File $Script:StateFile -Encoding UTF8 -Force
        } elseif (Test-Path $Script:StateFile) {
            Remove-Item $Script:StateFile -Force
        }

        # Build a payload that produces the desired pct
        # pct = ceil(tokensUsed / budget * 100)  =>  tokensUsed = ceil(pct * budget / 100)
        $tokensNeeded = [long][math]::Ceiling($Pct * $BudgetTokens / 100.0)
        $payload = New-TestPayload -BudgetTokens $BudgetTokens -InputTokens $tokensNeeded

        $json = $payload | ConvertTo-Json -Depth 5

        $psi = [System.Diagnostics.ProcessStartInfo]::new()
        $psi.FileName               = "powershell.exe"
        $psi.Arguments              = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$Script:TmpScript`""
        $psi.UseShellExecute        = $false
        $psi.RedirectStandardInput  = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError  = $true

        $proc = [System.Diagnostics.Process]::Start($psi)
        $proc.StandardInput.WriteLine($json)
        $proc.StandardInput.Close()
        $proc.StandardOutput.ReadToEnd() | Out-Null
        $proc.WaitForExit(15000) | Out-Null

        # Read resulting state
        if (Test-Path $Script:StateFile) {
            return Get-Content $Script:StateFile -Raw | ConvertFrom-Json
        }
        return $null
    }
}

AfterAll {
    if (Test-Path $Script:TmpBase) {
        Remove-Item $Script:TmpBase -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe "Threshold logic - first crossing from empty state" {

    BeforeEach {
        # Remove state file before each test so each starts fresh
        if (Test-Path $Script:StateFile) { Remove-Item $Script:StateFile -Force }
    }

    It "pct=73 from empty state triggers threshold_70 and sets t70=true" {
        $state = Invoke-MonitorWithState -Pct 73
        $state | Should -Not -BeNullOrEmpty
        $state.t70 | Should -Be $true
        $state.t85 | Should -Be $false
        $state.t95 | Should -Be $false
        $state.lastPct | Should -Be 73
    }

    It "pct=87 from empty state triggers threshold_85 and marks t70 done (jump logic)" {
        $state = Invoke-MonitorWithState -Pct 87
        $state | Should -Not -BeNullOrEmpty
        $state.t85 | Should -Be $true
        $state.t70 | Should -Be $true   # marked done by jump logic
        $state.t95 | Should -Be $false
        $state.lastPct | Should -Be 87
    }

    It "pct=96 from empty state triggers threshold_95 and marks t85 and t70 done" {
        $state = Invoke-MonitorWithState -Pct 96
        $state | Should -Not -BeNullOrEmpty
        $state.t95 | Should -Be $true
        $state.t85 | Should -Be $true
        $state.t70 | Should -Be $true
        $state.lastPct | Should -Be 96
    }
}

Describe "Threshold logic - no re-fire when already triggered" {

    It "pct=73 when t70 already true fires no new threshold" {
        $initState = @{ t70 = $true; t85 = $false; t95 = $false; lastPct = 72 }
        $state = Invoke-MonitorWithState -InitialState $initState -Pct 73
        # t70 was already true, 85/95 not crossed — state should remain stable
        $state.t70 | Should -Be $true
        $state.t85 | Should -Be $false
        $state.t95 | Should -Be $false
        $state.lastPct | Should -Be 73
    }

    It "pct=87 when t85 already true fires no new threshold" {
        $initState = @{ t70 = $true; t85 = $true; t95 = $false; lastPct = 86 }
        $state = Invoke-MonitorWithState -InitialState $initState -Pct 87
        $state.t85 | Should -Be $true
        $state.t95 | Should -Be $false
        $state.lastPct | Should -Be 87
    }
}

Describe "Threshold logic - partial state (t70 done but not t85)" {

    It "pct=87 when t70=true but t85=false triggers threshold_85" {
        $initState = @{ t70 = $true; t85 = $false; t95 = $false; lastPct = 72 }
        $state = Invoke-MonitorWithState -InitialState $initState -Pct 87
        $state.t85 | Should -Be $true
        $state.t70 | Should -Be $true  # remains true
        $state.t95 | Should -Be $false
        $state.lastPct | Should -Be 87
    }
}

Describe "Threshold logic - new session detection" {

    It "resets all thresholds when lastPct > 20 and pct < 5 (new session)" {
        # Simulate end of previous session at 80%, new session starts at 3%
        $initState = @{ t70 = $true; t85 = $true; t95 = $false; lastPct = 80 }
        $state = Invoke-MonitorWithState -InitialState $initState -Pct 3
        # All thresholds should be reset (pct=3 is below all thresholds, so none fire after reset)
        $state.t70 | Should -Be $false
        $state.t85 | Should -Be $false
        $state.t95 | Should -Be $false
        $state.lastPct | Should -Be 3
    }

    It "after reset pct=73 triggers threshold_70 again" {
        # First call: simulate new session reset (lastPct=80, pct=3)
        $initState = @{ t70 = $true; t85 = $true; t95 = $false; lastPct = 80 }
        Invoke-MonitorWithState -InitialState $initState -Pct 3 | Out-Null

        # Second call: pct=73 — threshold_70 should fire again since state was reset
        $state = Invoke-MonitorWithState -Pct 73
        $state.t70 | Should -Be $true
        $state.t85 | Should -Be $false
        $state.t95 | Should -Be $false
        $state.lastPct | Should -Be 73
    }

    It "does not reset when lastPct <= 20 even if pct < 5" {
        # pct drop from 15% to 3% is NOT a new session (lastPct is not > 20)
        $initState = @{ t70 = $false; t85 = $false; t95 = $false; lastPct = 15 }
        $state = Invoke-MonitorWithState -InitialState $initState -Pct 3
        # No reset triggered, no threshold fired — state should remain as-is (no flags set)
        $state.t70 | Should -Be $false
        $state.lastPct | Should -Be 3
    }
}

Describe "Threshold logic - lastPct tracking" {

    It "updates lastPct in state file after each run" {
        $state = Invoke-MonitorWithState -Pct 55
        $state.lastPct | Should -Be 55
    }
}
