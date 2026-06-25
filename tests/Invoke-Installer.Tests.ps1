#Requires -Module Pester
<#
.SYNOPSIS
    Tests for install-v3.ps1
.DESCRIPTION
    Runs the installer inside a temporary directory to verify it creates all
    expected files without touching the real project.
#>

BeforeAll {
    $ProjectRoot      = Split-Path $PSScriptRoot -Parent
    $Script:Installer = Join-Path $ProjectRoot "install-v3.ps1"

    # Helper: run the installer in a target directory and return exit code
    function Invoke-Installer {
        param([string]$TargetDir)

        $psi = [System.Diagnostics.ProcessStartInfo]::new()
        $psi.FileName               = "powershell.exe"
        $psi.Arguments              = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$Script:Installer`""
        $psi.WorkingDirectory       = $TargetDir
        $psi.UseShellExecute        = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError  = $true

        $proc = [System.Diagnostics.Process]::Start($psi)
        $proc.StandardOutput.ReadToEnd() | Out-Null
        $proc.WaitForExit(30000) | Out-Null
        return $proc.ExitCode
    }

    # Create a fresh temp directory for a clean install
    $Script:TmpClean = Join-Path ([System.IO.Path]::GetTempPath()) "pester-installer-clean-$(Get-Random)"
    New-Item -ItemType Directory -Path $Script:TmpClean -Force | Out-Null

    # Create a .gitignore so the installer can update it
    "# existing" | Out-File (Join-Path $Script:TmpClean ".gitignore") -Encoding UTF8

    # Run the installer once for the main test suite
    Invoke-Installer -TargetDir $Script:TmpClean | Out-Null
}

AfterAll {
    foreach ($dir in @($Script:TmpClean, $Script:TmpReinstall)) {
        if ($dir -and (Test-Path $dir)) {
            Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe "install-v3.ps1 - settings.json" {

    It "creates .claude/settings.json" {
        Join-Path $Script:TmpClean ".claude\settings.json" | Should -Exist
    }

    It "settings.json contains statusLine key" {
        $s = Get-Content (Join-Path $Script:TmpClean ".claude\settings.json") -Raw | ConvertFrom-Json
        $s.statusLine | Should -Not -BeNullOrEmpty
    }

    It "settings.json contains hooks key" {
        $s = Get-Content (Join-Path $Script:TmpClean ".claude\settings.json") -Raw | ConvertFrom-Json
        $s.hooks | Should -Not -BeNullOrEmpty
    }

    It "settings.json statusLine has type=command" {
        $s = Get-Content (Join-Path $Script:TmpClean ".claude\settings.json") -Raw | ConvertFrom-Json
        $s.statusLine.type | Should -Be "command"
    }
}

Describe "install-v3.ps1 - hook files" {

    It "creates statusline-monitor.ps1" {
        Join-Path $Script:TmpClean ".claude\hooks\statusline-monitor.ps1" | Should -Exist
    }

    It "creates save-context.ps1" {
        Join-Path $Script:TmpClean ".claude\hooks\save-context.ps1" | Should -Exist
    }

    It "creates pre-compact.ps1" {
        Join-Path $Script:TmpClean ".claude\hooks\pre-compact.ps1" | Should -Exist
    }

    It "creates stop-hook.ps1" {
        Join-Path $Script:TmpClean ".claude\hooks\stop-hook.ps1" | Should -Exist
    }
}

Describe "install-v3.ps1 - slash command" {

    It "creates .claude/commands/save-context.md" {
        Join-Path $Script:TmpClean ".claude\commands\save-context.md" | Should -Exist
    }
}

Describe "install-v3.ps1 - .gitignore" {

    It ".gitignore contains threshold-state.json entry" {
        $content = Get-Content (Join-Path $Script:TmpClean ".gitignore") -Raw
        $content | Should -Match 'threshold-state\.json'
    }

    It ".gitignore contains context-saves.log entry" {
        $content = Get-Content (Join-Path $Script:TmpClean ".gitignore") -Raw
        $content | Should -Match 'context-saves\.log'
    }
}

Describe "install-v3.ps1 - reinstall behaviour" {

    BeforeAll {
        # Set up a fresh temp dir for reinstall tests
        $Script:TmpReinstall = Join-Path ([System.IO.Path]::GetTempPath()) "pester-installer-reinstall-$(Get-Random)"
        New-Item -ItemType Directory -Path $Script:TmpReinstall -Force | Out-Null
        New-Item -ItemType Directory -Path "$Script:TmpReinstall\.claude" -Force | Out-Null

        # Seed a threshold-state.json to verify it gets removed
        @{ t70 = $true; t85 = $true; t95 = $false; lastPct = 80 } | ConvertTo-Json |
            Out-File (Join-Path $Script:TmpReinstall ".claude\threshold-state.json") -Encoding UTF8

        # Seed settings.json with an extra key that should be preserved after merge
        @{ customKey = "keepMe"; otherSetting = 42 } | ConvertTo-Json |
            Out-File (Join-Path $Script:TmpReinstall ".claude\settings.json") -Encoding UTF8

        # Run the installer
        Invoke-Installer -TargetDir $Script:TmpReinstall | Out-Null
    }

    It "removes threshold-state.json on reinstall" {
        Join-Path $Script:TmpReinstall ".claude\threshold-state.json" | Should -Not -Exist
    }

    It "settings.json still has statusLine after reinstall merge" {
        $s = Get-Content (Join-Path $Script:TmpReinstall ".claude\settings.json") -Raw | ConvertFrom-Json
        $s.statusLine | Should -Not -BeNullOrEmpty
    }

    It "settings.json still has hooks after reinstall merge" {
        $s = Get-Content (Join-Path $Script:TmpReinstall ".claude\settings.json") -Raw | ConvertFrom-Json
        $s.hooks | Should -Not -BeNullOrEmpty
    }

    It "settings.json preserves pre-existing extra keys after merge" {
        $s = Get-Content (Join-Path $Script:TmpReinstall ".claude\settings.json") -Raw | ConvertFrom-Json
        $s.customKey | Should -Be "keepMe"
    }
}
