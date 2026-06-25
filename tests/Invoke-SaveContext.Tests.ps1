#Requires -Module Pester
<#
.SYNOPSIS
    Tests for .claude/hooks/save-context.ps1
.DESCRIPTION
    Exercises save-context.ps1 with a temporary directory that has a .git repo
    so git commands inside the script succeed and produce meaningful output.
#>

BeforeAll {
    $ProjectRoot    = Split-Path $PSScriptRoot -Parent
    $Script:SaveCtx = Join-Path $ProjectRoot ".claude\hooks\save-context.ps1"

    # Create a temp project directory with a real git repo for isolation
    $Script:TmpDir = Join-Path ([System.IO.Path]::GetTempPath()) "pester-savecontext-$(Get-Random)"
    New-Item -ItemType Directory -Path $Script:TmpDir -Force | Out-Null

    # Init git repo in temp dir so git commands inside save-context work
    & git -C $Script:TmpDir init --quiet 2>$null
    & git -C $Script:TmpDir config user.email "test@test.com" 2>$null
    & git -C $Script:TmpDir config user.name  "Test" 2>$null

    # Create an initial commit so git log has something to show
    $readmeFile = Join-Path $Script:TmpDir "README.md"
    "# Test Project" | Out-File $readmeFile -Encoding UTF8
    & git -C $Script:TmpDir add . 2>$null
    & git -C $Script:TmpDir commit -m "Initial commit" --quiet 2>$null

    # Helper: run save-context.ps1 against the temp dir
    function Invoke-SaveContext {
        param(
            [string]$Trigger     = "manual",
            [string]$ProjectRoot = $Script:TmpDir
        )

        $psi = [System.Diagnostics.ProcessStartInfo]::new()
        $psi.FileName               = "powershell.exe"
        $psi.Arguments              = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$Script:SaveCtx`" -Trigger `"$Trigger`" -ProjectRoot `"$ProjectRoot`""
        $psi.UseShellExecute        = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError  = $true

        $proc = [System.Diagnostics.Process]::Start($psi)
        $stdout = $proc.StandardOutput.ReadToEnd()
        $proc.WaitForExit(15000) | Out-Null
        return $stdout.Trim()
    }
}

AfterAll {
    if (Test-Path $Script:TmpDir) {
        Remove-Item $Script:TmpDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe "save-context.ps1 - CONTEXT.md creation" {

    BeforeEach {
        # Remove any existing CONTEXT.md and log before each test
        $ctxFile = Join-Path $Script:TmpDir "CONTEXT.md"
        if (Test-Path $ctxFile) { Remove-Item $ctxFile -Force }
    }

    It "creates CONTEXT.md when called with -Trigger manual" {
        Invoke-SaveContext -Trigger "manual" | Out-Null
        $ctxFile = Join-Path $Script:TmpDir "CONTEXT.md"
        $ctxFile | Should -Exist
    }

    It "CONTEXT.md contains YAML frontmatter with 'trigger: manual'" {
        Invoke-SaveContext -Trigger "manual" | Out-Null
        $content = Get-Content (Join-Path $Script:TmpDir "CONTEXT.md") -Raw
        $content | Should -Match 'trigger: manual'
    }

    It "CONTEXT.md contains 'saved_at:' timestamp in frontmatter" {
        Invoke-SaveContext -Trigger "manual" | Out-Null
        $content = Get-Content (Join-Path $Script:TmpDir "CONTEXT.md") -Raw
        $content | Should -Match 'saved_at: \d{4}-\d{2}-\d{2}T'
    }

    It "CONTEXT.md contains 'Git Log' section" {
        Invoke-SaveContext -Trigger "manual" | Out-Null
        $content = Get-Content (Join-Path $Script:TmpDir "CONTEXT.md") -Raw
        $content | Should -Match '## Git Log'
    }

    It "CONTEXT.md contains 'Pending Changes' section" {
        Invoke-SaveContext -Trigger "manual" | Out-Null
        $content = Get-Content (Join-Path $Script:TmpDir "CONTEXT.md") -Raw
        $content | Should -Match '## Pending Changes'
    }

    It "CONTEXT.md contains 'Git Status' section" {
        Invoke-SaveContext -Trigger "manual" | Out-Null
        $content = Get-Content (Join-Path $Script:TmpDir "CONTEXT.md") -Raw
        $content | Should -Match '## Git Status'
    }

    It "CONTEXT.md reflects the correct trigger when called with threshold_85pct_used" {
        Invoke-SaveContext -Trigger "threshold_85pct_used" | Out-Null
        $content = Get-Content (Join-Path $Script:TmpDir "CONTEXT.md") -Raw
        $content | Should -Match 'trigger: threshold_85pct_used'
    }
}

Describe "save-context.ps1 - log file behaviour" {

    BeforeAll {
        # Clean log before this describe block
        $logPath = Join-Path $Script:TmpDir ".claude\context-saves.log"
        if (Test-Path $logPath) { Remove-Item $logPath -Force }
    }

    It "creates context-saves.log after first run" {
        Invoke-SaveContext -Trigger "manual" | Out-Null
        $logPath = Join-Path $Script:TmpDir ".claude\context-saves.log"
        $logPath | Should -Exist
    }

    It "log entry contains the trigger name" {
        Invoke-SaveContext -Trigger "manual" | Out-Null
        $logPath = Join-Path $Script:TmpDir ".claude\context-saves.log"
        $logContent = Get-Content $logPath -Raw
        $logContent | Should -Match 'trigger: manual'
    }

    It "appends a new log entry on subsequent calls (does not overwrite)" {
        # First call already happened in the previous test (same BeforeAll block)
        Invoke-SaveContext -Trigger "pre_compact" | Out-Null
        $logPath  = Join-Path $Script:TmpDir ".claude\context-saves.log"
        $lines    = Get-Content $logPath | Where-Object { $_.Trim() -ne '' }
        $lines.Count | Should -BeGreaterThan 1
    }

    It "log contains entry for threshold_85pct_used trigger" {
        Invoke-SaveContext -Trigger "threshold_85pct_used" | Out-Null
        $logPath    = Join-Path $Script:TmpDir ".claude\context-saves.log"
        $logContent = Get-Content $logPath -Raw
        $logContent | Should -Match 'trigger: threshold_85pct_used'
    }
}

Describe "save-context.ps1 - stdout output" {

    It "prints confirmation message to stdout" {
        $out = Invoke-SaveContext -Trigger "manual"
        $out | Should -Match 'CONTEXT\.md saved'
    }
}
