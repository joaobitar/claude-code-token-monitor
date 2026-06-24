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
# Compute percentage from ALL token types (including cache) so it matches
# Claude Code's internal "X% remaining" counter. used_percentage omits cache tokens.
$budgetTokens  = if ($null -ne $json.context_window.budget_tokens)               { [long]$json.context_window.budget_tokens }               else { 0 }
$tokInput      = if ($null -ne $json.context_window.total_input_tokens)          { [long]$json.context_window.total_input_tokens }          else { 0 }
$tokOutput     = if ($null -ne $json.context_window.total_output_tokens)         { [long]$json.context_window.total_output_tokens }         else { 0 }
$tokCacheWrite = if ($null -ne $json.context_window.cache_creation_input_tokens) { [long]$json.context_window.cache_creation_input_tokens } else { 0 }
$tokCacheRead  = if ($null -ne $json.context_window.cache_read_input_tokens)     { [long]$json.context_window.cache_read_input_tokens }     else { 0 }
$tokensUsed    = $tokInput + $tokOutput + $tokCacheWrite + $tokCacheRead

$pct = if ($budgetTokens -gt 0) {
    [int][math]::Ceiling($tokensUsed * 100.0 / $budgetTokens)
} elseif ($null -ne $json.context_window.used_percentage) {
    [int]$json.context_window.used_percentage
} else { 0 }

$cost  = if ($null -ne $json.cost.total_cost_usd) { $json.cost.total_cost_usd } else { 0 }
$model = if ($json.model.display_name) { $json.model.display_name } else { "Claude" }

# -- Rate limits (directly from payload) --
$pct5h      = if ($null -ne $json.rate_limits.five_hour.used_percentage) { [int]$json.rate_limits.five_hour.used_percentage } else { 0 }
$pctWeek    = if ($null -ne $json.rate_limits.seven_day.used_percentage) { [int]$json.rate_limits.seven_day.used_percentage } else { 0 }
$resetsAt   = if ($null -ne $json.rate_limits.five_hour.resets_at)       { [long]$json.rate_limits.five_hour.resets_at }       else { 0 }

$resetStr = "?"
if ($resetsAt -gt 0) {
    try { $resetStr = [DateTimeOffset]::FromUnixTimeSeconds($resetsAt).ToLocalTime().ToString("HH:mm") } catch {}
}

# -- Git info --
$repo = ""; $branch = ""
$projectDir = if ($json.workspace.project_dir) { $json.workspace.project_dir } elseif ($json.cwd) { $json.cwd } else { "" }
if ($projectDir -and (Test-Path "$projectDir\.git")) {
    try {
        $branch = (git -C $projectDir symbolic-ref --short HEAD 2>$null)
        $repo   = (Split-Path (git -C $projectDir rev-parse --show-toplevel 2>$null) -Leaf)
    } catch {}
}

# -- Threshold check (save-context at 70/85/95%) --
# Use $PSScriptRoot (absolute) so paths are reliable regardless of cwd or payload content
$hooksDir    = $PSScriptRoot                     # .claude/hooks/
$claudeDir   = Split-Path $PSScriptRoot -Parent  # .claude/
$projectRoot = Split-Path $claudeDir -Parent     # project root

$stateFile = Join-Path $claudeDir "threshold-state.json"
$state = @{ t70 = $false; t85 = $false; t95 = $false; lastPct = 0 }
if (Test-Path $stateFile) {
    try {
        $s = Get-Content $stateFile -Raw | ConvertFrom-Json
        if ($null -ne $s.t70)     { $state.t70     = [bool]$s.t70 }
        if ($null -ne $s.t85)     { $state.t85     = [bool]$s.t85 }
        if ($null -ne $s.t95)     { $state.t95     = [bool]$s.t95 }
        if ($null -ne $s.lastPct) { $state.lastPct = [int]$s.lastPct }
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

if (-not (Test-Path $claudeDir)) { New-Item -ItemType Directory -Path $claudeDir -Force | Out-Null }
$state | ConvertTo-Json | Out-File $stateFile -Encoding UTF8 -Force

if ($trigger) {
    $saveScript = Join-Path $hooksDir "save-context.ps1"
    Start-Process powershell -ArgumentList @(
        "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
        "-File", $saveScript,
        "-Trigger", $trigger,
        "-ProjectRoot", $projectRoot
    ) -WindowStyle Hidden
}

# -- Helpers --
function Format-Tokens($t) {
    if ($t -ge 1000000) { return "$([math]::Round($t/1000000,1))M" }
    if ($t -ge 1000)    { return "$([int]($t/1000))k" }
    return "$t"
}

# -- Progress bar --
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
if ($repo)   { $parts += "${bold}$e[33m${repo}$reset" }
if ($branch) { $parts += "${bold}$e[36m(${branch})$reset" }
$parts += "$alert [$bar] ${pct}% (${tokStr})"
$parts += "$e[35m5h: ${pct5h}%$reset  reset ${resetStr}"
$parts += "$e[34mWeek: ${pctWeek}%$reset"
$parts += "$e[33m${costStr}$reset"
$parts += "$e[36m${model}$reset"

Write-Host ($parts -join " ${dim}|$reset ")
