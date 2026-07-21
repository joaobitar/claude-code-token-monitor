# Claude Code Token Monitor

Sistema de monitoramento de tokens para Claude Code CLI com save-context automático.

---

## Funcionalidades

**Barra de status em tempo real**
- Porcentagem de uso da janela de contexto, alinhada ao indicador interno do Claude Code
- Barra de progresso colorida: verde → amarelo → vermelho
- Uso de rate limit nas últimas 5h e na semana, horário de reset, custo e modelo

**Save-context automático**
- Dispara em 70%, 85% e 95% de uso da janela de contexto
- Se o uso pular de 60% para 87%, dispara apenas em 85% (evita duplicatas)
- Antes de compactação automática de sessão (pre-compact hook)
- Manualmente via `/save-context`
- Notificação visível no status bar quando o save é acionado e quando conclui

**Alerta de rate limit de 5h**
- Ao atingir um limite configurável (default **96%**) do rate limit de 5h, salva o `CONTEXT.md` automaticamente e força Claude a avisar você e perguntar se quer agendar um reinício automático, sugerindo o horário do próximo reset
- Configurável via `monitor-config.json` (liga/desliga e ajusta o percentual)
- Não repete dentro da mesma janela de 5h — só rearma quando uma nova janela realmente começa

**Porcentagem precisa**
- Usa `Max(calcPct, apiPct)`:
  - `calcPct = ceil((input + output + cache_write + cache_read) / budget_tokens × 100)`
  - `apiPct = used_percentage` do payload (calculado pelo próprio Claude Code)
- `budget_tokens` representa o context window completo, mas o Claude Code compacta antes de esgotá-lo; `used_percentage` reflete o budget efetivo — tomamos o maior dos dois para nunca subestimar

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
│   ├── monitor-config.json         ← Campos do display + flags da feature de 5h (editável)
│   ├── threshold-state.json        ← Estado dos thresholds (runtime, gitignore)
│   ├── context-saves.log           ← Log de saves (runtime, gitignore)
│   ├── save-done.txt               ← Marcador temporário de conclusão de save (runtime)
│   ├── pending-5h-alert.json       ← Marcador do alerta de 5h pendente (runtime, gitignore)
│   ├── commands/
│   │   └── save-context.md         ← Slash command /save-context
│   └── hooks/
│       ├── statusline-monitor.ps1  ← Status bar + threshold check 70/85/95 + 5h (Windows)
│       ├── statusline-monitor.sh   ← Status bar + threshold check 70/85/95 + 5h (Unix)
│       ├── save-context.ps1/.sh    ← Lógica de geração do CONTEXT.md
│       ├── pre-compact.ps1/.sh     ← Hook pré-compactação
│       └── stop-hook.ps1/.sh       ← Relaia o alerta de 5h para o modelo (decision:block)
```

---

## Display

```
token_monitor (master) | ATN [##########----------] 73% (180k) | 5h: 45%  reset 14:30 | Week: 12% | $0.042 | Claude Sonnet 4.6
```

| Campo | Chave config | Descrição |
|-------|-------------|-----------|
| `repo` | `show_repo` | Nome do repositório git |
| `(branch)` | `show_branch` | Branch atual |
| `FREE/OK/ATN/WARN/CRIT [bar] pct% (Xtok)` | `show_context` | Nível de alerta, barra e % da janela de contexto |
| `5h: X%` | `show_5h` | Uso do rate limit de 5h |
| `reset HH:MM` | `show_reset` | Horário de reset do rate limit |
| `Week: X%` | `show_week` | Uso do rate limit semanal |
| `$X.XXX` | `show_cost` | Custo total da sessão (relevante para planos de API) |
| `model` | `show_model` | Modelo em uso |

---

## Configuração do display

O arquivo `.claude/monitor-config.json` controla quais campos aparecem na barra de status e as flags da feature de alerta de 5h. É criado automaticamente pelo instalador com todos os campos habilitados.

```json
{
  "show_repo":    true,
  "show_branch":  true,
  "show_context": true,
  "show_5h":      true,
  "show_reset":   true,
  "show_week":    true,
  "show_cost":    true,
  "show_model":   true,
  "save_on_5h_threshold":        true,
  "rate_limit_5h_threshold_pct": 96
}
```

Basta editar o arquivo e salvar — a mudança entra em vigor na próxima mensagem, sem reiniciar o Claude Code. Reinstalar não sobrescreve o arquivo se ele já existir.

Quando um save é acionado, uma linha extra aparece acima da barra:

```
Saving CONTEXT.md (85% used, trigger: threshold_85pct_used)...
```

Na mensagem seguinte, após a conclusão:

```
CONTEXT.md saved at 14:22:07
```

---

## Como o threshold funciona

O estado dos thresholds é persistido em `.claude/threshold-state.json`. A cada mensagem:

1. Calcula `pct = Max(calcPct, apiPct)`
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

## Alerta de rate limit de 5h

Diferente dos thresholds de contexto, o rate limit de 5h não é apenas exibido — quando cruza o limite configurado, ele **interrompe o fluxo normal** para avisar você.

**Como funciona:**

1. `statusline-monitor.ps1`/`.sh` (o único ponto com acesso aos dados de `rate_limits` do payload) detecta `5h% >= rate_limit_5h_threshold_pct`, salva o `CONTEXT.md` (trigger `threshold_5h_ratelimit`) e escreve `.claude/pending-5h-alert.json`
2. No fim do turno atual, o hook `Stop` (`stop-hook.ps1`/`.sh`) lê esse marcador e responde ao Claude Code com `{"decision": "block", "reason": "..."}` — isso é o que força Claude a continuar em vez de encerrar normalmente
3. Claude relaia o aviso para você e pergunta se quer agendar um reinício automático, sugerindo o horário do próximo reset
4. O marcador é apagado no consumo — o alerta não se repete dentro da mesma janela de 5h. Uma nova janela (detectada pela mudança do horário de reset) rearma o alerta

**Por que via `Stop` hook e não pela barra de status?** A barra de status (`statusLine`) só é renderizada no terminal — o texto nunca chega ao modelo. O hook `Stop` é o oposto: seu stdout é lido de volta pelo Claude Code e injetado na conversa. Por isso a detecção acontece num hook e o aviso é entregue pelo outro.

**Agendar o reinício** é conversacional — não é automatizado por script. Se você confirmar, é o próprio Claude quem cuida disso na hora (por exemplo com `/schedule` ou lembrando você de rodar `claude remote-control` no horário sugerido).

---

## CONTEXT.md gerado

```markdown
---
trigger: threshold_85pct_used
saved_at: 2026-06-25T14:22:10Z
---

# Context -- meu-projeto

> Saved at: 2026-06-25T14:22:10Z
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

Triggers possíveis: `threshold_70pct_used`, `threshold_85pct_used`, `threshold_95pct_used`, `threshold_5h_ratelimit`, `pre_compact`, `manual`.

---

## Diagnóstico

Para inspecionar o payload bruto que o Claude Code envia ao hook:

```powershell
# Windows: copie dump-statusline.ps1 para .claude/hooks/ e configure temporariamente em settings.json:
# "statusLine": { "type": "command", "command": "powershell -NoProfile -File \".claude\\hooks\\dump-statusline.ps1\"" }
# O payload fica salvo em .claude/statusline-dump.json
```

Útil para verificar os campos disponíveis (`budget_tokens`, `used_percentage`, `cache_creation_input_tokens`, etc.) e confirmar que o cálculo está correto.

Para testar o alerta de 5h isoladamente, sem esperar o rate limit real subir: crie `.claude/pending-5h-alert.json` com `{"pct5h":97,"threshold":96,"resetsAt":0,"resetStr":"HH:MM"}` e rode `stop-hook.ps1`/`.sh` manualmente — deve imprimir `{"decision":"block","reason":"..."}` e apagar o arquivo.

---

## Troubleshooting

**Monitor não aparece no rodapé**
- Confirme que `.claude/settings.json` tem a chave `statusLine`
- Reinicie o Claude Code após instalar

**CONTEXT.md não é gerado ao atingir threshold**
- Verifique `.claude/context-saves.log` para confirmar se o save foi executado
- No Windows, confirme que a ExecutionPolicy permite executar scripts PowerShell

**Porcentagem diferente do indicador interno do Claude Code**
- A partir da v3.2, o monitor usa `Max(calcPct, used_percentage)` para nunca subestimar
- Se ainda houver discrepância, execute o dump-statusline para ver os campos do payload

**Alerta de 5h não dispara**
- Confirme `save_on_5h_threshold: true` em `monitor-config.json`
- Confirme que `rate_limit_5h_threshold_pct` está de fato abaixo do uso atual de 5h
- Se já disparou nesta janela, `threshold-state.json` tem `t5h: true` — só rearma quando o horário de reset muda

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

**Versão**: 3.4
**Plataformas**: Windows (PowerShell), Linux/macOS (bash)
