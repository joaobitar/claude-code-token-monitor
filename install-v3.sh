#!/usr/bin/env bash
# Claude Code Token Monitor - Install v3 (Unix)
# - Budget: 200k tokens
# - Thresholds: 70%, 85%, 95% used (saves CONTEXT.md at each)
# - Status line: tokens used, 5h window stats, weekly stats
# - Installs /save-context slash command locally
# - Pre-compact hook saves before compaction

set -euo pipefail

ROOT="$(pwd)"
CLAUDE_DIR="$ROOT/.claude"
HOOKS_DIR="$CLAUDE_DIR/hooks"
CMDS_DIR="$CLAUDE_DIR/commands"
SETTINGS="$CLAUDE_DIR/settings.json"

echo ""
echo "Claude Code Token Monitor v3 (Unix)"
echo "===================================="
echo "Project: $ROOT"
echo ""

# -----------------------------------------------------------------------
# STEP 1: Clean up previous install
# -----------------------------------------------------------------------
echo "[1/6] Cleaning up previous install..."
OLD_DIR="$ROOT/.claude-code"
if [ -d "$OLD_DIR" ]; then
    rm -rf "$OLD_DIR"
    echo "      Removed .claude-code/"
else
    echo "      Nothing to clean"
fi
echo "[OK] Cleanup done"

# -----------------------------------------------------------------------
# STEP 2: Create directories
# -----------------------------------------------------------------------
echo "[2/6] Creating .claude/hooks/ and .claude/commands/..."
mkdir -p "$HOOKS_DIR" "$CMDS_DIR"
echo "[OK] Directories ready"

# -----------------------------------------------------------------------
# STEP 3: Hook scripts
# -----------------------------------------------------------------------
echo "[3/6] Writing hook scripts..."

# ---- statusline-monitor.sh ----
cat > "$HOOKS_DIR/statusline-monitor.sh" << 'HOOK_EOF'
#!/usr/bin/env bash
# Reads JSON from stdin, prints one status line.
# All usage data (5h, weekly, reset time) comes directly from rate_limits in the payload.

raw=$(cat)
[ -z "$raw" ] && exit 0

# Parse all fields in one python3 pass (avoids multiple subshells)
if command -v python3 &>/dev/null; then
    eval "$(echo "$raw" | python3 - <<'PY'
import sys, json, datetime

try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)

cw      = d.get("context_window", {})
rl      = d.get("rate_limits", {})
fh      = rl.get("five_hour", {})
sd      = rl.get("seven_day", {})
cu      = cw.get("current_usage", {})
ws      = d.get("workspace", {})
cost_d  = d.get("cost", {})
model_d = d.get("model", {})

pct        = int(cw.get("used_percentage", 0))
tok_in     = int(cw.get("total_input_tokens", 0))
tok_out    = int(cw.get("total_output_tokens", 0))
tokens_used = tok_in + tok_out
cost       = float(cost_d.get("total_cost_usd", 0))
model      = model_d.get("display_name", "Claude")
project_dir = ws.get("project_dir", ws.get("current_dir", d.get("cwd", "")))

pct_5h   = int(fh.get("used_percentage", 0))
pct_week = int(sd.get("used_percentage", 0))
resets_at = int(fh.get("resets_at", 0))

reset_str = "?"
if resets_at:
    try:
        dt = datetime.datetime.fromtimestamp(resets_at, tz=datetime.timezone.utc).astimezone()
        reset_str = dt.strftime("%H:%M")
    except Exception:
        pass

def fmt(t):
    if t >= 1000000: return f"{t/1000000:.1f}M"
    if t >= 1000:    return f"{t//1000}k"
    return str(t)

print(f"PCT={pct}")
print(f"TOKENS_USED={tokens_used}")
print(f"COST={cost:.3f}")
print(f"MODEL={model}")
print(f"PROJECT_DIR={project_dir}")
print(f"PCT_5H={pct_5h}")
print(f"PCT_WEEK={pct_week}")
print(f"RESET_STR={reset_str}")
print(f"TOK_STR={fmt(tokens_used)}")
PY
    )"
elif command -v jq &>/dev/null; then
    PCT=$(echo "$raw"   | jq -r '.context_window.used_percentage // 0')
    TOKENS_USED=$(echo "$raw" | jq -r '(.context_window.total_input_tokens // 0) + (.context_window.total_output_tokens // 0)')
    COST=$(echo "$raw"  | jq -r '.cost.total_cost_usd // 0')
    MODEL=$(echo "$raw" | jq -r '.model.display_name // "Claude"')
    PROJECT_DIR=$(echo "$raw" | jq -r '.workspace.project_dir // .workspace.current_dir // .cwd // ""')
    PCT_5H=$(echo "$raw"   | jq -r '.rate_limits.five_hour.used_percentage // 0')
    PCT_WEEK=$(echo "$raw" | jq -r '.rate_limits.seven_day.used_percentage // 0')
    RESETS_AT=$(echo "$raw" | jq -r '.rate_limits.five_hour.resets_at // 0')
    RESET_STR=$(date -d "@$RESETS_AT" +"%H:%M" 2>/dev/null || date -r "$RESETS_AT" +"%H:%M" 2>/dev/null || echo "?")
    TOK_STR="${TOKENS_USED}"
else
    exit 0
fi

PCT=${PCT%.*}

# Threshold check and save-context
CLAUDE_DIR="$PROJECT_DIR/.claude"
STATE_FILE="$CLAUDE_DIR/threshold-state.json"
HOOKS_DIR_LOCAL="$CLAUDE_DIR/hooks"
t70=false; t85=false; t95=false; last_pct=0
if [ -f "$STATE_FILE" ] && command -v python3 &>/dev/null; then
    read -r t70 t85 t95 last_pct <<< "$(python3 - "$STATE_FILE" <<'PY'
import sys, json
try:
    with open(sys.argv[1]) as f: s = json.load(f)
    print(str(s.get("t70","false")).lower(), str(s.get("t85","false")).lower(),
          str(s.get("t95","false")).lower(), int(s.get("lastPct",0)))
except Exception:
    print("false false false 0")
PY
    )"
fi

is_new=false
[ "$last_pct" -gt 20 ] && [ "$PCT" -lt 5 ] && is_new=true && t70=false && t85=false && t95=false

TRIGGER=""
if   [ "$PCT" -ge 95 ] && [ "$t95" = "false" ]; then t95=true;  TRIGGER="threshold_95pct_used"
elif [ "$PCT" -ge 85 ] && [ "$t85" = "false" ]; then t85=true;  TRIGGER="threshold_85pct_used"
elif [ "$PCT" -ge 70 ] && [ "$t70" = "false" ]; then t70=true;  TRIGGER="threshold_70pct_used"
fi

if command -v python3 &>/dev/null; then
    python3 -c "
import json
s = {'t70': $( [ "$t70" = "true" ] && echo 'True' || echo 'False' ), 't85': $( [ "$t85" = "true" ] && echo 'True' || echo 'False' ), 't95': $( [ "$t95" = "true" ] && echo 'True' || echo 'False' ), 'lastPct': $PCT}
import os; os.makedirs('$CLAUDE_DIR', exist_ok=True)
with open('$STATE_FILE','w') as f: json.dump(s, f)
" 2>/dev/null || true
fi

[ -n "$TRIGGER" ] && "$HOOKS_DIR_LOCAL/save-context.sh" "$TRIGGER" "$PROJECT_DIR" &

# ANSI colors
ESC=$'\e'
RST="${ESC}[0m"
BOLD="${ESC}[1m"
DIM="${ESC}[2m"
RED="${ESC}[31m"
YEL="${ESC}[33m"
GRN="${ESC}[32m"
CYN="${ESC}[36m"
MAG="${ESC}[35m"
BLU="${ESC}[34m"

# Progress bar
BAR_WIDTH=20
filled=$(( PCT * BAR_WIDTH / 100 ))
bar=""
for (( i=0; i<BAR_WIDTH; i++ )); do
    if (( i < filled )); then
        if   (( PCT >= 85 )); then bar+="${RED}#${RST}"
        elif (( PCT >= 70 )); then bar+="${YEL}#${RST}"
        else                       bar+="${GRN}#${RST}"; fi
    else
        bar+="${DIM}-${RST}"
    fi
done

if   (( PCT >= 95 )); then alert="${RED}CRIT${RST}"
elif (( PCT >= 85 )); then alert="${YEL}WARN${RST}"
elif (( PCT >= 70 )); then alert="${YEL} ATN${RST}"
elif (( PCT >= 20 )); then alert="${GRN}  OK${RST}"
else                       alert="${CYN}FREE${RST}"; fi

# Git info
repo=""; branch=""
if [ -n "$PROJECT_DIR" ] && [ -d "$PROJECT_DIR/.git" ]; then
    branch=$(git -C "$PROJECT_DIR" symbolic-ref --short HEAD 2>/dev/null || echo "")
    repo=$(basename "$(git -C "$PROJECT_DIR" rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null || echo "")
fi

cost_str=$(printf '%.3f' "$COST")
sep="${DIM}|${RST}"

parts=()
[ -n "$repo" ]   && parts+=("${BOLD}${YEL}${repo}${RST}")
[ -n "$branch" ] && parts+=("${BOLD}${CYN}(${branch})${RST}")
parts+=("${alert} [${bar}] ${PCT}% (${TOK_STR})")
parts+=("${MAG}5h: ${PCT_5H}%${RST}  reset ${RESET_STR}")
parts+=("${BLU}Week: ${PCT_WEEK}%${RST}")
parts+=("${YEL}\$${cost_str}${RST}")
parts+=("${CYN}${MODEL}${RST}")

out=""
for i in "${!parts[@]}"; do
    [ $i -gt 0 ] && out+=" $sep "
    out+="${parts[$i]}"
done
echo -e "$out"
HOOK_EOF
chmod +x "$HOOKS_DIR/statusline-monitor.sh"
echo "      statusline-monitor.sh"

# ---- save-context.sh ----
cat > "$HOOKS_DIR/save-context.sh" << 'HOOK_EOF'
#!/usr/bin/env bash
# Shared save-context logic
TRIGGER="${1:-manual}"
PROJECT_ROOT="${2:-${CLAUDE_PROJECT_DIR:-$(pwd)}}"

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +"%Y-%m-%dT%H:%M:%SZ")
PROJECT_NAME=$(basename "$PROJECT_ROOT")

GIT_LOG=""
GIT_DIFF=""
GIT_STATUS=""
if command -v git &>/dev/null && git -C "$PROJECT_ROOT" rev-parse --git-dir &>/dev/null 2>&1; then
    GIT_LOG=$(git -C "$PROJECT_ROOT" log --oneline -15 2>/dev/null || echo "")
    GIT_DIFF=$(git -C "$PROJECT_ROOT" diff HEAD --stat 2>/dev/null || echo "")
    GIT_STATUS=$(git -C "$PROJECT_ROOT" status --short 2>/dev/null || echo "")
fi

cat > "$PROJECT_ROOT/CONTEXT.md" << CONTEXT_EOF
---
trigger: $TRIGGER
saved_at: $TIMESTAMP
---

# Context -- $PROJECT_NAME

> Saved at: $TIMESTAMP
> Trigger: $TRIGGER

## Git Log (last 15)
\`\`\`
$GIT_LOG
\`\`\`

## Pending Changes
\`\`\`
$GIT_DIFF
\`\`\`

## Git Status
\`\`\`
$GIT_STATUS
\`\`\`

## Current Status
[What is working and completed this session]

## In Progress
[What was being developed - be specific: which file, which feature, where you stopped]

## Technical Decisions
[Architecture choices and WHY - not just conclusions]

## Next Steps
1. [Most urgent - be concrete]
2. [Second priority]
3. [Third priority]

## Known Issues
[Bugs, technical debt, limitations]

---
Last updated: $TIMESTAMP
Generated by Claude Code Token Monitor ($TRIGGER)
CONTEXT_EOF

LOG_DIR="$PROJECT_ROOT/.claude"
mkdir -p "$LOG_DIR"
echo "[$TIMESTAMP] CONTEXT.md saved | trigger: $TRIGGER" >> "$LOG_DIR/context-saves.log"
echo "CONTEXT.md saved at $TIMESTAMP (trigger: $TRIGGER)"
HOOK_EOF
chmod +x "$HOOKS_DIR/save-context.sh"
echo "      save-context.sh"

# ---- pre-compact.sh ----
cat > "$HOOKS_DIR/pre-compact.sh" << 'HOOK_EOF'
#!/usr/bin/env bash
raw=$(cat)
PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
TRIGGER="pre_compact"

if command -v jq &>/dev/null; then
    t=$(echo "$raw" | jq -r '.trigger // empty' 2>/dev/null)
    [ -n "$t" ] && TRIGGER="$t"
fi

"$(dirname "$0")/save-context.sh" "$TRIGGER" "$PROJECT_ROOT"
HOOK_EOF
chmod +x "$HOOKS_DIR/pre-compact.sh"
echo "      pre-compact.sh"

# ---- stop-hook.sh ----
# Note: stop-hook JSON does NOT include context_window data.
# Threshold checking and save-context are handled by statusline-monitor.sh.
cat > "$HOOKS_DIR/stop-hook.sh" << 'HOOK_EOF'
#!/usr/bin/env bash
exit 0
HOOK_EOF
chmod +x "$HOOKS_DIR/stop-hook.sh"
echo "      stop-hook.sh"
echo "[OK] All hook scripts created"

# -----------------------------------------------------------------------
# STEP 4: save-context slash command (local)
# -----------------------------------------------------------------------
echo "[4/6] Installing /save-context slash command..."

cat > "$CMDS_DIR/save-context.md" << 'CMD_EOF'
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
CMD_EOF

echo "[OK] .claude/commands/save-context.md created"

# -----------------------------------------------------------------------
# STEP 5: Write .claude/settings.json
# -----------------------------------------------------------------------
echo "[5/6] Writing .claude/settings.json..."

NEW_STATUSLINE='"statusLine":{"type":"command","command":"bash .claude/hooks/statusline-monitor.sh"}'
NEW_PRECOMPACT='"PreCompact":[{"hooks":[{"type":"command","command":"bash .claude/hooks/pre-compact.sh"}]}]'
NEW_STOP='"Stop":[{"hooks":[{"type":"command","command":"bash .claude/hooks/stop-hook.sh"}]}]'

if [ -f "$SETTINGS" ] && command -v python3 &>/dev/null; then
    python3 - "$SETTINGS" <<PY
import json, sys

with open(sys.argv[1]) as f:
    s = json.load(f)

s["statusLine"] = {"type": "command", "command": "bash .claude/hooks/statusline-monitor.sh"}
s.setdefault("hooks", {})
s["hooks"]["PreCompact"] = [{"hooks": [{"type": "command", "command": "bash .claude/hooks/pre-compact.sh"}]}]
s["hooks"]["Stop"]       = [{"hooks": [{"type": "command", "command": "bash .claude/hooks/stop-hook.sh"}]}]

with open(sys.argv[1], "w") as f:
    json.dump(s, f, indent=2)

print("[OK] Merged into existing settings.json")
PY
else
    cat > "$SETTINGS" << JSON_EOF
{
  "statusLine": {
    "type": "command",
    "command": "bash .claude/hooks/statusline-monitor.sh"
  },
  "hooks": {
    "PreCompact": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash .claude/hooks/pre-compact.sh"
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash .claude/hooks/stop-hook.sh"
          }
        ]
      }
    ]
  }
}
JSON_EOF
    echo "[OK] Created settings.json"
fi

# -----------------------------------------------------------------------
# STEP 6: .gitignore
# -----------------------------------------------------------------------
echo "[6/6] Updating .gitignore..."
GITIGNORE="$ROOT/.gitignore"
ENTRIES=(".claude/context-saves.log" ".claude/threshold-state.json" ".claude/usage-log.json")
if [ -f "$GITIGNORE" ]; then
    ADDED=0
    for entry in "${ENTRIES[@]}"; do
        if ! grep -qF "$entry" "$GITIGNORE"; then
            if [ $ADDED -eq 0 ]; then
                echo "" >> "$GITIGNORE"
                echo "# Claude Code Token Monitor" >> "$GITIGNORE"
                ADDED=1
            fi
            echo "$entry" >> "$GITIGNORE"
        fi
    done
    [ $ADDED -gt 0 ] && echo "[OK] .gitignore updated" || echo "[--] .gitignore already ok"
else
    echo "[--] No .gitignore found, skipping"
fi

# -----------------------------------------------------------------------
# DONE
# -----------------------------------------------------------------------
echo ""
echo "===================================================="
echo "  DONE - Close and reopen Claude Code to apply     "
echo "===================================================="
echo ""
echo "Created:"
echo "  .claude/settings.json"
echo "  .claude/hooks/statusline-monitor.sh   <- status bar"
echo "  .claude/hooks/stop-hook.sh             <- saves at 70/85/95% used"
echo "  .claude/hooks/pre-compact.sh           <- saves before compaction"
echo "  .claude/hooks/save-context.sh          <- shared save logic"
echo "  .claude/commands/save-context.md       <- /save-context slash command"
echo ""
echo "Status bar format:"
echo "  repo (branch) | level [bar] pct% (Xtok) | 5h: Xtok (Y%) | Week: Xtok (Z%) | cost | model"
echo ""
echo "Thresholds: CONTEXT.md auto-saved when 70%, 85%, 95% of context is used"
echo "Manual save: /save-context"
echo ""
echo "Requirements: bash, git, jq or python3"
echo ""
