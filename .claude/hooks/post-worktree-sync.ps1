[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$raw = [Console]::In.ReadToEnd()
if (-not $raw.Trim()) { exit 0 }
try { $json = $raw | ConvertFrom-Json } catch { exit 0 }

try {
    # Source of truth is THIS project (script''s own location), regardless of cwd
    # after EnterWorktree switched the session''s working directory.
    $hooksDir    = $PSScriptRoot
    $claudeDir   = Split-Path $PSScriptRoot -Parent
    $projectRoot = Split-Path $claudeDir -Parent
    $cmdsDir     = Join-Path $claudeDir "commands"
    $settingsSrc = Join-Path $claudeDir "settings.json"
    $cfgSrc      = Join-Path $claudeDir "monitor-config.json"

    # Locate the worktree path anywhere in the payload (field name/shape not guaranteed).
    function Find-WorktreePath($obj, [int]$depth = 0) {
        if ($depth -gt 6 -or $null -eq $obj) { return $null }
        if ($obj -is [string]) {
            if ($obj -match ''\.claude[\\/]worktrees[\\/]'') { return $obj }
            return $null
        }
        if ($obj -is [System.Collections.IEnumerable] -and -not ($obj -is [string])) {
            foreach ($item in $obj) {
                $r = Find-WorktreePath $item ($depth + 1)
                if ($r) { return $r }
            }
            return $null
        }
        if ($obj.PSObject -and $obj.PSObject.Properties) {
            foreach ($p in $obj.PSObject.Properties) {
                $r = Find-WorktreePath $p.Value ($depth + 1)
                if ($r) { return $r }
            }
        }
        return $null
    }

    $wtPath = Find-WorktreePath $json
    if (-not $wtPath) { exit 0 }
    if (-not (Test-Path $wtPath)) { exit 0 }
    if ($wtPath -notlike "$projectRoot*") { exit 0 }

    $wtClaudeDir = Join-Path $wtPath ".claude"
    $wtHooksDir  = Join-Path $wtClaudeDir "hooks"
    $wtCmdsDir   = Join-Path $wtClaudeDir "commands"

    # Idempotency: skip if already synced (e.g. re-entering an existing worktree).
    if (Test-Path (Join-Path $wtHooksDir "statusline-monitor.ps1")) { exit 0 }

    New-Item -ItemType Directory -Path $wtHooksDir -Force | Out-Null
    New-Item -ItemType Directory -Path $wtCmdsDir  -Force | Out-Null

    Get-ChildItem -Path $hooksDir -Filter "*.ps1" | ForEach-Object {
        Copy-Item $_.FullName (Join-Path $wtHooksDir $_.Name) -Force
    }
    if (Test-Path $cmdsDir) {
        Get-ChildItem -Path $cmdsDir -Filter "*.md" | ForEach-Object {
            Copy-Item $_.FullName (Join-Path $wtCmdsDir $_.Name) -Force
        }
    }
    if (Test-Path $cfgSrc) {
        Copy-Item $cfgSrc (Join-Path $wtClaudeDir "monitor-config.json") -Force
    }

    $wtSettingsFile = Join-Path $wtClaudeDir "settings.json"
    if (Test-Path $settingsSrc) {
        $srcSettings = Get-Content $settingsSrc -Raw | ConvertFrom-Json
        if (Test-Path $wtSettingsFile) {
            try {
                $existing = Get-Content $wtSettingsFile -Raw | ConvertFrom-Json
                $existing | Add-Member -MemberType NoteProperty -Name "statusLine" -Value $srcSettings.statusLine -Force
                $existing | Add-Member -MemberType NoteProperty -Name "hooks"      -Value $srcSettings.hooks      -Force
                $existing | ConvertTo-Json -Depth 10 | Out-File $wtSettingsFile -Encoding UTF8 -Force
            } catch {
                Copy-Item $settingsSrc $wtSettingsFile -Force
            }
        } else {
            Copy-Item $settingsSrc $wtSettingsFile -Force
        }
    }
} catch {}
