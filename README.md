# Claude Code Token Monitor

Sistema de monitoramento de tokens para Claude Code CLI com save-context automático.

> Salva `CONTEXT.md` automaticamente em 70%, 85% e 95% de uso da janela de contexto — usando o mesmo cálculo interno do Claude Code (inclui tokens de cache).

---

## Funcionalidades

**Barra de status em tempo real**
- Exibe porcentagem de uso da janela de contexto (idêntica ao indicador interno do Claude Code)
- Barra de progresso colorida: verde → amarelo → vermelho
- Uso de tokens nas últimas 5h e na semana, horário de reset, custo e modelo

**Save-context automático**
- Dispara em 70%, 85% e 95% de uso — a partir do threshold (ex: se pular de 60% para 87%, dispara em 85%)
- Antes de compactação automática de sessão (pre-compact hook)
- Manualmente via `/save-context`

**Porcentagem precisa**
- Calcula `ceil((input + output + cache_write + cache_read) / budget_tokens × 100)`
- Sem distorção por omissão de tokens de cache (o campo `used_percentage` do payload omite cache)
- Fallback para `used_percentage` se `budget_tokens` não estiver disponível no payload

**Sem dependências extras**
- Windows: PowerShell 5.1+ (nativo)
- Linux/macOS: bash + python3 (padrão em qualquer distro) ou jq

---

## Instalação

Execute na raiz do projeto onde o Claude Code é usado:

**Windows (PowerShell):**
```powershell
powershell -ExecutionPolicy Bypass -File install-v3.ps1
```

**Linux / macOS:**
```bash
bash install-v3.sh
```

O installer:
1. Remove versões anteriores (arquivos antigos de hooks, state file)
2. Cria `.claude/hooks/` e `.claude/commands/`
3. Escreve os scripts de hook
4. Instala o slash command `/save-context`
5. Escreve `.claude/settings.json`

Reiniciar o Claude Code após instalar.

---

## Estrutura instalada

```
seu-projeto/
├── CONTEXT.md                      ← Gerado/atualizado automaticamente
├── .claude/
│   ├── settings.json               ← statusLine + hooks (versionado)
│   ├── threshold-state.json        ← Estado dos thresholds (runtime, gitignore)
│   ├── context-saves.log           ← Log de saves (runtime, gitignore)
│   ├── commands/
│   │   └── save-context.md         ← Slash command /save-context
│   └── hooks/
│       ├── statusline-monitor.ps1  ← Status bar + threshold check (Windows)
│       ├── statusline-monitor.sh   ← Status bar + threshold check (Unix)
│       ├── save-context.ps1/.sh    ← Lógica de geração do CONTEXT.md
│       ├── pre-compact.ps1/.sh     ← Hook pré-compactação
│       └── stop-hook.ps1/.sh       ← Hook de stop (mínimo)
```

---

## Display

```
token_monitor (master) | ATN [##########----------] 73% (180k) | 5h: 45%  reset 14:30 | Week: 12% | $0.042 | Claude Sonnet 4.6
```

| Campo | Descrição |
|-------|-----------|
| `repo (branch)` | Nome do repositório e branch git |
| `FREE/OK/ATN/WARN/CRIT` | Nível de alerta (0–19% / 20–69% / 70–84% / 85–94% / 95%+) |
| `[bar] pct% (Xtok)` | % da janela de contexto usada + total de tokens (inclui cache) |
| `5h: X%  reset HH:MM` | Uso do rate limit de 5h e horário de reset |
| `Week: X%` | Uso do rate limit semanal |
| `$X.XXX` | Custo total da sessão |
| `model` | Modelo em uso |

---

## Como o threshold funciona

O estado dos thresholds é persistido em `.claude/threshold-state.json`. A cada mensagem:

1. Calcula `pct` a partir de todos os tokens + `budget_tokens`
2. Verifica se algum threshold novo foi ultrapassado (≥ não apenas =)
3. Dispara o threshold mais alto atingido e marca os menores como feitos
4. Se `pct` volta abaixo de 5% após ter sido > 20%, considera nova sessão e reseta o estado

**Exemplo de pulo de boundary:**
```
lastPct=65%  →  pct=87%
→ Dispara threshold_85pct_used
→ Marca t85=true e t70=true (70% não dispara separadamente)
```

---

## CONTEXT.md gerado

```markdown
---
trigger: threshold_85pct_used
saved_at: 2026-06-24T14:22:10Z
---

# Context -- meu-projeto

> Saved at: 2026-06-24T14:22:10Z
> Trigger: threshold_85pct_used

## Git Log (last 15)
...

## Pending Changes
...

## Git Status
...

## Current Status
[O que está funcionando e concluído nesta sessão]

## In Progress
[O que estava sendo desenvolvido — arquivo, feature, onde parou]

## Technical Decisions
[Escolhas de arquitetura e POR QUÊ]

## Next Steps
1. [Ação concreta e específica]
2. ...

## Known Issues
[Bugs, débitos técnicos, limitações]
```

---

## Diagnóstico

Para inspecionar o payload bruto que o Claude Code envia ao hook:

```powershell
# Windows: copie dump-statusline.ps1 para .claude/hooks/ e configure temporariamente em settings.json:
# "statusLine": { "type": "command", "command": "powershell -NoProfile -File \".claude\\hooks\\dump-statusline.ps1\"" }
# O payload fica salvo em .claude/statusline-dump.json
```

```bash
# Unix: equivalente com dump-hook.sh
```

O dump é útil para verificar os campos disponíveis no payload (`budget_tokens`, `cache_creation_input_tokens`, etc.) e confirmar que o cálculo de porcentagem está correto.

---

## Troubleshooting

**Monitor não aparece no rodapé**
- Confirme que `.claude/settings.json` tem a chave `statusLine`
- Reinicie o Claude Code após instalar

**CONTEXT.md não é gerado ao atingir threshold**
- Verifique `.claude/context-saves.log` para confirmar se o save foi executado
- Certifique-se de que o projeto tem um diretório `.git` (o hook resolve os paths via `$PSScriptRoot`)
- No Windows, confira se a ExecutionPolicy permite executar scripts PowerShell

**Porcentagem diferente do indicador interno do Claude Code**
- Certifique-se de estar usando a versão v3 mais recente (o campo `budget_tokens` do payload precisa estar presente)
- Execute o dump-statusline para ver os campos disponíveis no payload da sua versão do Claude Code

**Reinstalar / atualizar**
```powershell
# Windows
powershell -ExecutionPolicy Bypass -File install-v3.ps1
```
O installer remove o `threshold-state.json` existente, então os thresholds disparam do zero após reinstalar.

---

## Plataformas

| Plataforma | Requisitos |
|------------|------------|
| Windows | PowerShell 5.1+ (nativo no Windows 10/11) |
| Linux / macOS | bash + python3 **ou** bash + jq |
| Claude Code | Qualquer versão com suporte a `statusLine` e hooks `PreCompact`/`Stop` |

---

**Versão**: 3.1  
**Plataformas**: Windows (PowerShell), Linux/macOS (bash)
