# Claude Code Token Monitor - Install v3
# - Budget: 200k tokens
# - Thresholds: 70%, 85%, 95% used (saves CONTEXT.md at each)
# - Status line: tokens used, 5h window stats, weekly stats
# - Installs /save-context slash command locally
# - Pre-compact hook saves before compaction

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$root      = (Get-Location).Path
$claudeDir = Join-Path $root ".claude"
$hooksDir  = Join-Path $claudeDir "hooks"
$cmdsDir   = Join-Path $claudeDir "commands"
$settings  = Join-Path $claudeDir "settings.json"

Write-Host ""
Write-Host "Claude Code Token Monitor v3" -ForegroundColor Cyan
Write-Host "============================" -ForegroundColor Cyan
Write-Host "Project: $root"
Write-Host ""

# -----------------------------------------------------------------------
# STEP 1: Clean up previous install
# -----------------------------------------------------------------------
Write-Host "[1/6] Cleaning up previous install..." -ForegroundColor Yellow

$cleaned = $false

# v1 used a separate .claude-code/ directory
$oldDir = Join-Path $root ".claude-code"
if (Test-Path $oldDir) {
    Remove-Item -Recurse -Force $oldDir
    Write-Host "      Removed .claude-code/" -ForegroundColor Gray; $cleaned = $true
}

# Remove old hook file names used in previous versions
@("monitor.ps1", "token-monitor.ps1", "threshold-monitor.ps1", "context-monitor.ps1") | ForEach-Object {
    $oldHook = Join-Path $hooksDir $_
    if (Test-Path $oldHook) {
        Remove-Item -Force $oldHook
        Write-Host "      Removed old hook: $_" -ForegroundColor Gray; $cleaned = $true
    }
}

# Reset threshold state so all thresholds fire fresh after reinstall
$oldState = Join-Path $claudeDir "threshold-state.json"
if (Test-Path $oldState) {
    Remove-Item -Force $oldState
    Write-Host "      Reset threshold-state.json" -ForegroundColor Gray; $cleaned = $true
}

if (-not $cleaned) { Write-Host "      Nothing to clean" -ForegroundColor Gray }
Write-Host "[OK] Cleanup done" -ForegroundColor Green

# -----------------------------------------------------------------------
# STEP 2: Create directories
# -----------------------------------------------------------------------
Write-Host "[2/6] Creating .claude/hooks/ and .claude/commands/..." -ForegroundColor Yellow
New-Item -ItemType Directory -Path $hooksDir -Force | Out-Null
New-Item -ItemType Directory -Path $cmdsDir  -Force | Out-Null
Write-Host "[OK] Directories ready" -ForegroundColor Green

# -----------------------------------------------------------------------
# STEP 2b: monitor-config.json (only if not already present)
# -----------------------------------------------------------------------
$cfgFile = Join-Path $claudeDir "monitor-config.json"
if (-not (Test-Path $cfgFile)) {
    @'
{
  "show_repo":    true,
  "show_branch":  true,
  "show_context": true,
  "show_5h":      true,
  "show_reset":   true,
  "show_week":    true,
  "show_cost":    true,
  "show_model":   true
}
'@ | Out-File $cfgFile -Encoding UTF8
    Write-Host "[OK] .claude/monitor-config.json created with defaults" -ForegroundColor Green
} else {
    Write-Host "[OK] .claude/monitor-config.json kept (already exists)" -ForegroundColor Green
}

# -----------------------------------------------------------------------
# STEP 3: Hook scripts
# -----------------------------------------------------------------------
Write-Host "[3/6] Writing hook scripts..." -ForegroundColor Yellow

# ---- statusline-monitor.ps1 ----
# Reads JSON from stdin, prints one status line.
# Shows: repo (branch) | level [bar] pct% (tokens used) | 5h: Xtok (Y%) | Week: Xtok (Z%) | $cost | model
@'
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

# ── Rate limits (directly from payload) ───────────────────────────────────
$pct5h      = if ($null -ne $json.rate_limits.five_hour.used_percentage) { [int]$json.rate_limits.five_hour.used_percentage } else { 0 }
$pctWeek    = if ($null -ne $json.rate_limits.seven_day.used_percentage) { [int]$json.rate_limits.seven_day.used_percentage } else { 0 }
$resetsAt   = if ($null -ne $json.rate_limits.five_hour.resets_at)       { [long]$json.rate_limits.five_hour.resets_at }       else { 0 }

$resetStr = "?"
if ($resetsAt -gt 0) {
    try { $resetStr = [DateTimeOffset]::FromUnixTimeSeconds($resetsAt).ToLocalTime().ToString("HH:mm") } catch {}
}

# ── Git info ───────────────────────────────────────────────────────────────
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

$saveDoneFile = Join-Path $claudeDir "save-done.txt"
$saveNotify = ""
if (Test-Path $saveDoneFile) {
    try {
        $saveNotify = "CONTEXT.md saved at " + (Get-Content $saveDoneFile -Raw).Trim()
        Remove-Item $saveDoneFile -Force -ErrorAction SilentlyContinue
    } catch {}
}

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

# -- Display config --
$cfgFile = Join-Path $claudeDir "monitor-config.json"
$cfg = @{ show_repo=$true; show_branch=$true; show_context=$true; show_5h=$true; show_reset=$true; show_week=$true; show_cost=$true; show_model=$true }
if (Test-Path $cfgFile) {
    try {
        $c = Get-Content $cfgFile -Raw | ConvertFrom-Json
        foreach ($k in @('show_repo','show_branch','show_context','show_5h','show_reset','show_week','show_cost','show_model')) {
            if ($null -ne $c.$k) { $cfg[$k] = [bool]$c.$k }
        }
    } catch {}
}

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

# ── Helpers ────────────────────────────────────────────────────────────────
function Format-Tokens($t) {
    if ($t -ge 1000000) { return "$([math]::Round($t/1000000,1))M" }
    if ($t -ge 1000)    { return "$([int]($t/1000))k" }
    return "$t"
}

# ── Progress bar ───────────────────────────────────────────────────────────
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
'@ | Out-File (Join-Path $hooksDir "statusline-monitor.ps1") -Encoding UTF8

Write-Host "      statusline-monitor.ps1" -ForegroundColor Gray

# ---- save-context.ps1 ----
@'
# Shared save-context logic - called by pre-compact.ps1 and stop-hook.ps1
param(
    [string]$Trigger     = "manual",
    [string]$ProjectRoot = ""
)

if (-not $ProjectRoot) {
    $ProjectRoot = if ($env:CLAUDE_PROJECT_DIR) { $env:CLAUDE_PROJECT_DIR } else { (Get-Location).Path }
}

$timestamp   = Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ"
$projectName = Split-Path $ProjectRoot -Leaf

$gitLog = ""; $gitDiff = ""; $gitStatus = ""
try {
    $gitLog    = (git -C $ProjectRoot log --oneline -15 2>$null) -join "`n"
    $gitDiff   = (git -C $ProjectRoot diff HEAD --stat 2>$null) -join "`n"
    $gitStatus = (git -C $ProjectRoot status --short 2>$null) -join "`n"
} catch {}

@"
---
trigger: $Trigger
saved_at: $timestamp
---

# Context -- $projectName

> Saved at: $timestamp
> Trigger: $Trigger

## Git Log (last 15)
``````
$gitLog
``````

## Pending Changes
``````
$gitDiff
``````

## Git Status
``````
$gitStatus
``````

## Current Status
[What is working and completed this session]

## In Progress
[What was being developed - be specific: which file, which feature, where you stopped]

## Technical Decisions
[Architecture choices and WHY - not just conclusions]

## Next Steps
1. [Most urgent - be concrete, e.g. "Implement email validation in src/forms/UserForm.tsx"]
2. [Second priority]
3. [Third priority]

## Known Issues
[Bugs, technical debt, limitations]

---
Last updated: $timestamp
Generated by Claude Code Token Monitor ($Trigger)
"@ | Out-File (Join-Path $ProjectRoot "CONTEXT.md") -Encoding UTF8 -Force

$logDir = Join-Path $ProjectRoot ".claude"
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
"[$timestamp] CONTEXT.md saved | trigger: $Trigger" | Add-Content (Join-Path $logDir "context-saves.log")

# Write completion marker so statusline-monitor can display a notification
(Get-Date -Format "HH:mm:ss") | Out-File (Join-Path $logDir "save-done.txt") -Encoding UTF8 -Force

Write-Host "CONTEXT.md saved at $timestamp (trigger: $Trigger)"
'@ | Out-File (Join-Path $hooksDir "save-context.ps1") -Encoding UTF8

Write-Host "      save-context.ps1" -ForegroundColor Gray

# ---- pre-compact.ps1 ----
@'
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$raw         = [Console]::In.ReadToEnd()
$projectRoot = if ($env:CLAUDE_PROJECT_DIR) { $env:CLAUDE_PROJECT_DIR } else { (Get-Location).Path }

$trigger = "pre_compact"
try { $json = $raw | ConvertFrom-Json; if ($json.trigger) { $trigger = $json.trigger } } catch {}

& (Join-Path $PSScriptRoot "save-context.ps1") -Trigger $trigger -ProjectRoot $projectRoot
'@ | Out-File (Join-Path $hooksDir "pre-compact.ps1") -Encoding UTF8

Write-Host "      pre-compact.ps1" -ForegroundColor Gray

# ---- stop-hook.ps1 ----
# Note: stop-hook JSON does NOT include context_window data.
# Threshold checking and save-context are handled by statusline-monitor.ps1.
# This hook is kept only for pre-compact compatibility.
@'
exit 0
'@ | Out-File (Join-Path $hooksDir "stop-hook.ps1") -Encoding UTF8

Write-Host "      stop-hook.ps1" -ForegroundColor Gray
Write-Host "[OK] All hook scripts created" -ForegroundColor Green

# -----------------------------------------------------------------------
# STEP 4: save-context slash command (local)
# -----------------------------------------------------------------------
Write-Host "[4/6] Installing /save-context slash command..." -ForegroundColor Yellow

@'
---
description: Salva o estado atual do desenvolvimento em CONTEXT.md
---

Analise o estado atual do projeto e gere/atualize o arquivo `CONTEXT.md` na raiz.

## Passos obrigatórios

1. Execute `git log --oneline -15` para ver os commits recentes
2. Execute `git diff HEAD --stat` para ver arquivos com mudanças pendentes
3. Execute `git status` para ver arquivos novos ou não rastreados
4. Leia os arquivos principais que foram modificados recentemente
5. Gere o CONTEXT.md com a estrutura abaixo

## Estrutura do CONTEXT.md

# Context — [nome do projeto]
> Salvo em: [data e hora atual]
> Trigger: [manual | threshold_70pct | threshold_85pct | threshold_95pct | pre_compact]

## Status atual
[O que está funcionando e foi concluído]

## Em andamento
[O que estava sendo desenvolvido nesta sessão — seja específico]

## Decisões técnicas
[Escolhas de arquitetura, libs escolhidas e POR QUÊ, abordagens descartadas]

## Arquivos relevantes
[Lista dos arquivos mais importantes com uma linha de descrição cada]

## Próximos passos
[Lista ordenada do que falta fazer, do mais urgente ao menos urgente]

## Problemas conhecidos
[Bugs identificados, débitos técnicos, limitações]

## Instruções importantes

- Seja específico e direto — este arquivo será lido no início de uma nova sessão
- Na seção "Decisões técnicas", documente o raciocínio, não apenas a conclusão
- Na seção "Próximos passos", escreva ações concretas (ex: "Implementar validação do campo email em src/forms/UserForm.tsx"), não vagas ("melhorar formulário")
- Se o CONTEXT.md já existir, substitua o conteúdo completamente com as informações atualizadas
- Confirme ao final: "✅ CONTEXT.md atualizado em [timestamp]"
'@ | Out-File (Join-Path $cmdsDir "save-context.md") -Encoding UTF8

Write-Host "[OK] .claude/commands/save-context.md created" -ForegroundColor Green

# -----------------------------------------------------------------------
# STEP 5: Write .claude/settings.json
# -----------------------------------------------------------------------
Write-Host "[5/6] Writing .claude/settings.json..." -ForegroundColor Yellow

$newSettings = [ordered]@{
    statusLine = [ordered]@{
        type    = "command"
        command = 'powershell -NoProfile -NonInteractive -File ".claude\hooks\statusline-monitor.ps1"'
    }
    hooks = [ordered]@{
        PreCompact = @(
            [ordered]@{
                hooks = @(
                    [ordered]@{
                        type    = "command"
                        command = 'powershell -NoProfile -NonInteractive -File ".claude\hooks\pre-compact.ps1"'
                    }
                )
            }
        )
        Stop = @(
            [ordered]@{
                hooks = @(
                    [ordered]@{
                        type    = "command"
                        command = 'powershell -NoProfile -NonInteractive -File ".claude\hooks\stop-hook.ps1"'
                    }
                )
            }
        )
    }
}

if (Test-Path $settings) {
    try {
        $existing = Get-Content $settings -Raw | ConvertFrom-Json
        $existing | Add-Member -MemberType NoteProperty -Name "statusLine" -Value $newSettings.statusLine -Force
        $existing | Add-Member -MemberType NoteProperty -Name "hooks"      -Value $newSettings.hooks      -Force
        $existing | ConvertTo-Json -Depth 10 | Out-File $settings -Encoding UTF8
        Write-Host "[OK] Merged into existing settings.json" -ForegroundColor Green
    } catch {
        $newSettings | ConvertTo-Json -Depth 10 | Out-File $settings -Encoding UTF8
        Write-Host "[OK] Replaced settings.json" -ForegroundColor Green
    }
} else {
    $newSettings | ConvertTo-Json -Depth 10 | Out-File $settings -Encoding UTF8
    Write-Host "[OK] Created settings.json" -ForegroundColor Green
}

# -----------------------------------------------------------------------
# STEP 6: .gitignore
# -----------------------------------------------------------------------
Write-Host "[6/6] Updating .gitignore..." -ForegroundColor Yellow
$gitignore = Join-Path $root ".gitignore"
$entries   = @(".claude/context-saves.log", ".claude/threshold-state.json", ".claude/usage-log.json")
if (Test-Path $gitignore) {
    $content = Get-Content $gitignore -Raw
    $toAdd   = $entries | Where-Object { $content -notlike "*$_*" }
    if ($toAdd) {
        "`n# Claude Code Token Monitor" | Add-Content $gitignore
        $toAdd | Add-Content $gitignore
        Write-Host "[OK] .gitignore updated" -ForegroundColor Green
    } else {
        Write-Host "[--] .gitignore already ok" -ForegroundColor Gray
    }
} else {
    Write-Host "[--] No .gitignore found, skipping" -ForegroundColor Gray
}

# -----------------------------------------------------------------------
# DONE
# -----------------------------------------------------------------------
Write-Host ""
Write-Host "====================================================" -ForegroundColor Green
Write-Host "  DONE - Close and reopen Claude Code to apply     " -ForegroundColor Green
Write-Host "====================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Created:"
Write-Host "  .claude/settings.json"
Write-Host "  .claude/hooks/statusline-monitor.ps1   <- status bar"
Write-Host "  .claude/hooks/stop-hook.ps1             <- saves at 70/85/95% used"
Write-Host "  .claude/hooks/pre-compact.ps1           <- saves before compaction"
Write-Host "  .claude/hooks/save-context.ps1          <- shared save logic"
Write-Host "  .claude/commands/save-context.md        <- /save-context slash command"
Write-Host ""
Write-Host "Status bar format:"
Write-Host "  repo (branch) | level [bar] pct% (Xtok) | 5h: Xtok (Y%) | Week: Xtok (Z%) | cost | model"
Write-Host ""
Write-Host "Thresholds: CONTEXT.md auto-saved when 70%, 85%, 95% of context is used"
Write-Host "Manual save: /save-context"
Write-Host ""
