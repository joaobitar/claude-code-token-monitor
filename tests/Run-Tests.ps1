param(
    [string]$Tag       = "",
    [string]$TestName  = "",
    [switch]$Verbose
)

Set-StrictMode -Off
$ErrorActionPreference = "Stop"

$pesterModule = Get-Module -ListAvailable -Name Pester | Sort-Object Version -Descending | Select-Object -First 1

if (-not $pesterModule -or $pesterModule.Version.Major -lt 5) {
    Write-Host "Pester v5 not found -- installing..." -ForegroundColor Yellow
    try {
        Install-Module -Name Pester -MinimumVersion 5.0.0 -Force -Scope CurrentUser -SkipPublisherCheck
        Write-Host "Pester installed successfully." -ForegroundColor Green
    } catch {
        Write-Error "Failed to install Pester: $_"
        exit 1
    }
}

Import-Module Pester -MinimumVersion 5.0.0 -Force

$testsDir = $PSScriptRoot

$config = New-PesterConfiguration
$config.Run.Path            = $testsDir
$config.Run.PassThru        = $true
$config.Filter.ExcludeTag   = @()
$config.Output.Verbosity    = if ($Verbose) { "Detailed" } else { "Normal" }
$config.TestResult.Enabled  = $true
$config.TestResult.OutputPath   = Join-Path $testsDir "TestResults.xml"
$config.TestResult.OutputFormat = "NUnitXml"

if ($Tag)      { $config.Filter.Tag      = @($Tag) }
if ($TestName) { $config.Filter.FullName = $TestName }

Write-Host ""
Write-Host "Running Claude Code Token Monitor tests..." -ForegroundColor Cyan
Write-Host "Test directory: $testsDir" -ForegroundColor Gray
Write-Host ""

$result = Invoke-Pester -Configuration $config

Write-Host ""
if ($result.FailedCount -gt 0) {
    Write-Host "FAILED: $($result.FailedCount) test(s) failed out of $($result.TotalCount)." -ForegroundColor Red
    exit 1
} else {
    Write-Host "PASSED: All $($result.TotalCount) test(s) passed." -ForegroundColor Green
    exit 0
}