[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$raw = [Console]::In.ReadToEnd()
if (-not $raw.Trim()) { exit 0 }
try { $json = $raw | ConvertFrom-Json } catch { exit 0 }

$e     = [char]27
$reset = "$e[0m"
$bold  = "$e[1m"
$dim   = "$e[2m"

# -- Context window (current session) --
# total_input_tokens already includes cache tokens (verified via payload dump).
# context_window_size is the correct field name (not budget_tokens).
# We take Max(calcPct, used_percentage) to never underestimate vs Claude Code's own counter.
$budgetTokens = if ($null -ne $json.context_window.context_window_size) { [long]$json.context_window.context_window_size } else { 0 }
$tokInput     = if ($null -ne $json.context_window.total_input_tokens)  { [long]$json.context_window.total_input_tokens }  else { 0 }
$tokOutput    = if ($null -ne $json.context_window.total_output_tokens) { [long]$json.context_window.total_output_tokens } else { 0 }
$tokensUsed   = $tokInput + $tokOutput

$apiPct  = if ($null -ne $json.context_window.used_percentage) { [int]$json.context_window.used_percentage } else { 0 }
$calcPct = if ($budgetTokens -gt 0) { [int][math]::Ceiling($tokensUsed * 100.0 / $budgetTokens) } else { 0 }
$pct     = [Math]::Max($calcPct, $apiPct)

$cost  = if ($null -ne $json.cost.total_cost_usd) { $json.cost.total_cost_usd } else { 0 }
$model = if ($json.model.display_name) { $json.model.display_name } else { "Claude" }

# â”€â”€ Rate limits (directly from payload) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
$pct5h      = if ($null -ne $json.rate_limits.five_hour.used_percentage) { [int]$json.rate_limits.five_hour.used_percentage } else { 0 }
$pctWeek    = if ($null -ne $json.rate_limits.seven_day.used_percentage) { [int]$json.rate_limits.seven_day.used_percentage } else { 0 }
$resetsAt   = if ($null -ne $json.rate_limits.five_hour.resets_at)       { [long]$json.rate_limits.five_hour.resets_at }       else { 0 }

$resetStr = "?"
if ($resetsAt -gt 0) {
    try { $resetStr = [DateTimeOffset]::FromUnixTimeSeconds($resetsAt).ToLocalTime().ToString("HH:mm") } catch {}
}

# â”€â”€ Git info â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
$repo = ""; $branch = ""
$projectDir = if ($json.workspace.project_dir) { $json.workspace.project_dir } elseif ($json.cwd) { $json.cwd } else { "" }
if ($projectDir -and (Test-Path "$projectDir\.git")) {
    try {
        $branch = (git -C $projectDir symbolic-ref --short HEAD 2>$null)
        $repo   = (Split-Path (git -C $projectDir rev-parse --show-toplevel 2>$null) -Leaf)
    } catch {}
}

# -- Threshold check (save-context at 70/85/95%, plus the 5h rate-limit alert) --
# Use $PSScriptRoot (absolute) so paths are reliable regardless of cwd or payload content
$hooksDir    = $PSScriptRoot                     # .claude/hooks/
$claudeDir   = Split-Path $PSScriptRoot -Parent  # .claude/
$projectRoot = Split-Path $claudeDir -Parent     # project root

$saveDoneFile = Join-Path $claudeDir "save-done.txt"
$saveNotify = ""
if (Test-Path $saveDoneFile) {
    try {
        $saveNotify = "CONTEXT.md saved at " + (Get-Content $saveDoneFile -Raw).Trim()
        Remove-Item $saveDoneFile -Force -ErrorAction SilentlyContinue
    } catch {}
}

# -- Display config (also holds the 5h-threshold feature flags) --
$cfgFile = Join-Path $claudeDir "monitor-config.json"
$cfg = @{ show_repo=$true; show_branch=$true; show_context=$true; show_5h=$true; show_reset=$true; show_week=$true; show_cost=$true; show_model=$true; save_on_5h_threshold=$true; rate_limit_5h_threshold_pct=96 }
if (Test-Path $cfgFile) {
    try {
        $c = Get-Content $cfgFile -Raw | ConvertFrom-Json
        foreach ($k in @('show_repo','show_branch','show_context','show_5h','show_reset','show_week','show_cost','show_model','save_on_5h_threshold')) {
            if ($null -ne $c.$k) { $cfg[$k] = [bool]$c.$k }
        }
        if ($null -ne $c.rate_limit_5h_threshold_pct) { $cfg['rate_limit_5h_threshold_pct'] = [int]$c.rate_limit_5h_threshold_pct }
    } catch {}
}

$stateFile = Join-Path $claudeDir "threshold-state.json"
$state = @{ t70 = $false; t85 = $false; t95 = $false; lastPct = 0; t5h = $false; last5hResetsAt = 0 }
if (Test-Path $stateFile) {
    try {
        $s = Get-Content $stateFile -Raw | ConvertFrom-Json
        if ($null -ne $s.t70)            { $state.t70            = [bool]$s.t70 }
        if ($null -ne $s.t85)            { $state.t85            = [bool]$s.t85 }
        if ($null -ne $s.t95)            { $state.t95            = [bool]$s.t95 }
        if ($null -ne $s.lastPct)        { $state.lastPct        = [int]$s.lastPct }
        if ($null -ne $s.t5h)            { $state.t5h            = [bool]$s.t5h }
        if ($null -ne $s.last5hResetsAt) { $state.last5hResetsAt = [long]$s.last5hResetsAt }
    } catch {}
}

$isNewSession = ($state.lastPct -gt 20) -and ($pct -lt 5)
if ($isNewSession) { $state.t70 = $false; $state.t85 = $false; $state.t95 = $false }

# Fire highest newly-crossed threshold; mark all lower ones done to avoid duplicates
# when usage jumps across multiple boundaries (e.g. 60% -> 87% skipping 70%)
$trigger = $null
if ($pct -ge 95 -and -not $state.t95) {
    $state.t95 = $true; $state.t85 = $true; $state.t70 = $true
    $trigger = "threshold_95pct_used"
} elseif ($pct -ge 85 -and -not $state.t85) {
    $state.t85 = $true; $state.t70 = $true
    $trigger = "threshold_85pct_used"
} elseif ($pct -ge 70 -and -not $state.t70) {
    $state.t70 = $true
    $trigger = "threshold_70pct_used"
}
$state.lastPct = $pct

# -- 5h rate-limit threshold (default 96%, configurable via rate_limit_5h_threshold_pct) --
# A new 5h window is detected by resets_at changing; that's what re-arms t5h,
# since pct5h alone can dip and climb without a window actually resetting.
$trigger5h = $false
if ($resetsAt -gt 0 -and $state.last5hResetsAt -gt 0 -and $resetsAt -ne $state.last5hResetsAt) {
    $state.t5h = $false
}
if ($resetsAt -gt 0) { $state.last5hResetsAt = $resetsAt }

if ($cfg.save_on_5h_threshold -and $pct5h -ge $cfg.rate_limit_5h_threshold_pct -and -not $state.t5h) {
    $state.t5h = $true
    $trigger5h = $true
}

if (-not (Test-Path $claudeDir)) { New-Item -ItemType Directory -Path $claudeDir -Force | Out-Null }
$state | ConvertTo-Json | Out-File $stateFile -Encoding UTF8 -Force

if ($trigger) {
    $saveNotify = "Saving CONTEXT.md (${pct}% used, trigger: $trigger)..."
    $saveScript = Join-Path $hooksDir "save-context.ps1"
    Start-Process powershell -ArgumentList @(
        "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
        "-File", $saveScript,
        "-Trigger", $trigger,
        "-ProjectRoot", $projectRoot
    ) -WindowStyle Hidden
}

if ($trigger5h) {
    $saveNotify = "5h rate limit at ${pct5h}% (reset ${resetStr}) - saving CONTEXT.md..."
    $saveScript = Join-Path $hooksDir "save-context.ps1"
    Start-Process powershell -ArgumentList @(
        "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
        "-File", $saveScript,
        "-Trigger", "threshold_5h_ratelimit",
        "-ProjectRoot", $projectRoot
    ) -WindowStyle Hidden

    # Leaves a marker for stop-hook.ps1, which is the only hook Claude Code
    # actually feeds back to the model - statusLine output here is terminal-only.
    $alertObj = [ordered]@{
        pct5h     = $pct5h
        threshold = $cfg.rate_limit_5h_threshold_pct
        resetsAt  = $resetsAt
        resetStr  = $resetStr
    }
    $alertObj | ConvertTo-Json | Out-File (Join-Path $claudeDir "pending-5h-alert.json") -Encoding UTF8 -Force
}

# â”€â”€ Helpers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
function Format-Tokens($t) {
    if ($t -ge 1000000) { return "$([math]::Round($t/1000000,1))M" }
    if ($t -ge 1000)    { return "$([int]($t/1000))k" }
    return "$t"
}

# â”€â”€ Progress bar â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
$barWidth = 20
$filled   = [math]::Round($pct * $barWidth / 100)
$bar = ""
for ($i = 0; $i -lt $barWidth; $i++) {
    $pos = if ($barWidth -gt 1) { [int]($i * 100 / ($barWidth - 1)) } else { 0 }
    if ($pos -le 50) {
        $r = [int](220 * $pos / 50); $g = 200; $b = [int](80 - 80 * $pos / 50)
    } else {
        $adj = $pos - 50; $r = 220; $g = [int](200 - 160 * $adj / 50); $b = [int](20 * $adj / 50)
    }
    $c = "$e[38;2;${r};${g};${b}m"
    $bar += if ($i -lt $filled) { "${c}#" } else { "$e[38;2;50;50;50m-" }
}
$bar += $reset

$alert = if ($pct -ge 95) { "$e[31mCRIT$reset" } `
    elseif ($pct -ge 85) { "$e[33mWARN$reset" } `
    elseif ($pct -ge 70) { "$e[33m ATN$reset" } `
    elseif ($pct -ge 20) { "$e[32m OK $reset" } `
    else                 { "$e[36mFREE$reset" }

$costStr = "`${0:F3}" -f $cost
$tokStr  = Format-Tokens $tokensUsed

$parts = @()
if ($cfg.show_repo    -and $repo)   { $parts += "${bold}$e[33m${repo}$reset" }
if ($cfg.show_branch  -and $branch) { $parts += "${bold}$e[36m(${branch})$reset" }
if ($cfg.show_context) { $parts += "$alert [$bar] ${pct}% (${tokStr})" }
$rateStr = @()
if ($cfg.show_5h)    { $rateStr += "$e[35m5h: ${pct5h}%$reset" }
if ($cfg.show_reset) { $rateStr += "reset ${resetStr}" }
if ($rateStr.Count -gt 0) { $parts += ($rateStr -join "  ") }
if ($cfg.show_week)  { $parts += "$e[34mWeek: ${pctWeek}%$reset" }
if ($cfg.show_cost)  { $parts += "$e[33m${costStr}$reset" }
if ($cfg.show_model) { $parts += "$e[36m${model}$reset" }

if ($saveNotify) { Write-Host $saveNotify }
Write-Host ($parts -join " ${dim}|$reset ")
