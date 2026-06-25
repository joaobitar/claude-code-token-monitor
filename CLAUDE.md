# Claude Code Token Monitor — CLAUDE.md

## O que é este projeto

Sistema de monitoramento de tokens para Claude Code CLI. Instala hooks que:
1. Exibem uma barra de status em tempo real no rodapé do Claude Code
2. Salvam `CONTEXT.md` automaticamente em 70%, 85% e 95% de uso da janela de contexto
3. Salvam `CONTEXT.md` antes de compactação automática de sessão (pre-compact hook)
4. Disponibilizam o slash command `/save-context` para save manual

**Versão atual**: 3.1 — estável, publicada, sem mudanças pendentes.

---

## Estrutura do projeto

```
token_monitor/
├── install-v3.ps1                    ← Instalador Windows (escreve todos os arquivos abaixo)
├── install-v3.sh                     ← Instalador Linux/macOS
├── README.md                         ← Documentação completa
├── QUICKSTART.md                     ← Guia rápido
├── WINDOWS-INSTALL.md                ← Instruções Windows
├── CONTEXT.md                        ← Estado atual do projeto (gerado/atualizado)
├── dump-statusline.ps1               ← Diagnóstico: despeja payload bruto
└── .claude/
    ├── settings.json                 ← statusLine + hooks (versionado)
    ├── threshold-state.json          ← Estado runtime dos thresholds (gitignored)
    ├── context-saves.log             ← Log de saves (gitignored)
    ├── hooks/
    │   ├── statusline-monitor.ps1   ← Status bar + threshold check (ponto central)
    │   ├── save-context.ps1         ← Lógica compartilhada de geração do CONTEXT.md
    │   ├── pre-compact.ps1          ← Hook PreCompact
    │   └── stop-hook.ps1            ← Hook Stop (mínimo — exit 0)
    └── commands/
        └── save-context.md          ← Slash command /save-context
```

**Importante**: os arquivos em `.claude/hooks/` e `.claude/commands/` são gerados pelos instaladores (`install-v3.ps1` / `install-v3.sh`). A fonte-da-verdade é o instalador — ao editar hooks, edite o instalador E o arquivo de hook simultaneamente.

---

## Arquitetura e decisões técnicas

### Fluxo de execução

```
Claude Code (a cada mensagem)
  → statusline-monitor.ps1 (stdin: JSON payload)
      ├── Calcula pct = ceil((input+output+cache_write+cache_read) / budget_tokens × 100)
      ├── Verifica thresholds (70/85/95%) vs threshold-state.json
      ├── Se threshold cruzado → Start-Process save-context.ps1 (background)
      └── Imprime status bar no stdout

Claude Code (PreCompact)
  → pre-compact.ps1
      └── Chama save-context.ps1 diretamente

Claude Code (/save-context)
  → Claude executa o slash command (salvo em .claude/commands/save-context.md)
      └── Claude gera CONTEXT.md com conteúdo real (não apenas placeholders)
```

### Regras de threshold

- Estado persistido em `.claude/threshold-state.json` (reseta se `pct < 5%` após `pct > 20%` = nova sessão)
- Dispara o threshold mais alto cruzado; marca todos os menores como feitos (evita duplicatas em jumps, ex: 60% → 87% dispara apenas o 85%)
- Em reinstall, o state file é deletado → todos os thresholds disparam do zero

### Cálculo de porcentagem

```
pct = ceil((total_input_tokens + total_output_tokens + cache_creation_input_tokens + cache_read_input_tokens) / budget_tokens × 100)
```

Fallback para `used_percentage` quando `budget_tokens` não está no payload. O campo `used_percentage` omite cache tokens e daria leitura menor que o indicador interno do Claude Code.

### Resolução de paths

Todos os paths são derivados de `$PSScriptRoot` (path absoluto do script em execução):
```powershell
$hooksDir    = $PSScriptRoot                     # .claude/hooks/
$claudeDir   = Split-Path $PSScriptRoot -Parent  # .claude/
$projectRoot = Split-Path $claudeDir -Parent     # raiz do projeto
```

Nunca use `Get-Location` ou paths do payload JSON para escrever arquivos — são não-confiáveis.

### Stop hook é mínimo

O payload do `Stop` hook não inclui `context_window`. O threshold check e save-context acontecem no `statusline-monitor.ps1`. O `stop-hook.ps1` só existe para satisfazer a configuração e faz `exit 0`.

---

## Como testar mudanças

1. Edite o hook relevante em `.claude/hooks/`
2. **Se a mudança for permanente**, replique no instalador (`install-v3.ps1` e/ou `install-v3.sh`)
3. Para testar o status bar manualmente, use `dump-statusline.ps1` para ver o payload real
4. Para testar o threshold, edite temporariamente `threshold-state.json` para forçar um threshold a disparar

### Diagnóstico do payload

```powershell
# Copie dump-statusline.ps1 para .claude/hooks/ e configure em settings.json:
# "statusLine": { "type": "command", "command": "powershell -NoProfile -File \".claude\\hooks\\dump-statusline.ps1\"" }
# O payload fica salvo em .claude/statusline-dump.json
```

---

## Convenções de código

- **PowerShell 5.1** (Windows nativo) — sem dependências extras
- Sempre use `[Console]::InputEncoding = [System.Text.Encoding]::UTF8` no topo de scripts que leem stdin
- Tratamento de erro silencioso com `try {} catch {}` — os hooks não devem quebrar o Claude Code
- `Start-Process powershell -WindowStyle Hidden` para rodar save-context em background (não bloqueia o status bar)
- Encoding de arquivos: sempre `-Encoding UTF8` no `Out-File`

---

## O que NÃO fazer

- Não use `Get-Location` ou `$env:CLAUDE_PROJECT_DIR` para resolver o path do projeto dentro dos hooks — use `$PSScriptRoot`
- Não edite apenas os arquivos de hook sem replicar no instalador — o instalador sobrescreve os hooks no próximo `install-v3.ps1`
- Não adicione lógica pesada no status bar — ele é chamado a cada mensagem e atrasos são perceptíveis
- Não commite `threshold-state.json` ou `context-saves.log` — estão no `.gitignore`

---

## Referências

- `README.md` — documentação completa com exemplos de output e troubleshooting
- `CONTEXT.md` — estado atual do desenvolvimento (leia no início de uma nova sessão)
- Claude Code hooks: `statusLine`, `PreCompact`, `Stop`
- Payload do statusLine contém: `context_window`, `cost`, `model`, `rate_limits`, `workspace`
