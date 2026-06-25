# Token Monitor Tests

Automated tests for Claude Code Token Monitor v3.1 using **Pester v5**.

## Quick start

```powershell
# From the project root:
powershell -ExecutionPolicy Bypass -File tests\Run-Tests.ps1
```

`Run-Tests.ps1` will install Pester v5 automatically if it is not already present.

## Structure

```
tests/
├── helpers/
│   └── New-TestPayload.ps1             # JSON payload builder
├── Invoke-StatuslineMonitor.Tests.ps1  # pct calculation, alert levels, cost, rate limits
├── Invoke-ThresholdLogic.Tests.ps1     # 70/85/95% state machine
├── Invoke-SaveContext.Tests.ps1        # CONTEXT.md creation and log appending
├── Invoke-Installer.Tests.ps1          # install-v3.ps1 file creation and merge logic
├── Run-Tests.ps1                       # entry point
└── README.md
```

## Running individual test files

```powershell
# Pester must already be imported
Import-Module Pester -MinimumVersion 5.0.0
Invoke-Pester -Path tests\Invoke-StatuslineMonitor.Tests.ps1 -Output Detailed
```

## Requirements

- Windows PowerShell 5.1 or PowerShell 7+
- Internet access for the first run (to download Pester from PSGallery)
- `git` available on `PATH` (used by save-context tests)

## Notes

- Tests never modify files in the real project. Each test suite creates its own
  temporary directory under `$env:TEMP` and cleans it up in `AfterAll`.
- Threshold logic tests copy `statusline-monitor.ps1` into a temp directory so
  `$PSScriptRoot` resolves to a controlled location for `threshold-state.json`.
- Test results are written to `tests\TestResults.xml` (NUnit XML format) for
  CI consumption.
