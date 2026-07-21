# Claude Code Token Monitor — CLAUDE.md

## O que é este projeto

Sistema de monitoramento de tokens para Claude Code CLI. Instala hooks que:
1. Exibem uma barra de status em tempo real no rodapé do Claude Code
2. Salvam `CONTEXT.md` automaticamente em 70%, 85% e 95% de uso da janela de contexto
3. Salvam `CONTEXT.md` antes de compactação automática de sessão (pre-compact hook)
4. Disponibilizam o slash command `/save-context` para save manual
5. Ao cruzar um limite configurável (default 96%) do rate limit de 5h, salvam `CONTEXT.md` e forçam Claude a avisar o usuário e perguntar sobre agendar reinício automático (Stop hook)

**Versão atual**: 3.4 — testada em sessão real (Stop hook confirmado disparando `decision:block` de ponta a ponta), publicada.

---

## Estrutura do projeto

```
token_monitor/
├── install-v3.ps1                    ← Instalador Windows (escreve todos os arquivos abaixo)
├── install-v3.sh                     ← Instalador Linux/macOS
├── README.md                         ← Documentação completa
├── CONTEXT.md                        ← Estado atual do projeto (gerado/atualizado)
├── dump-statusline.ps1               ← Diagnóstico: despeja payload bruto do statusLine
├── dump-hook.ps1                     ← Diagnóstico: despeja payload bruto de Stop hook
└── .claude/
    ├── settings.json                 ← statusLine + hooks (versionado)
    ├── threshold-state.json          ← Estado runtime dos thresholds (gitignored)
    ├── context-saves.log             ← Log de saves (gitignored)
    ├── save-done.txt                 ← Marcador temporário de conclusão de save (runtime)
    ├── pending-5h-alert.json         ← Marcador runtime: alerta de 5h pendente pro stop-hook.ps1 consumir (gitignored)
    ├── monitor-config.json           ← Configuração de campos do display (editável pelo usuário)
    ├── hooks/
    │   ├── statusline-monitor.ps1   ← Status bar + threshold check 70/85/95 + 5h (ponto central)
    │   ├── save-context.ps1         ← Lógica compartilhada de geração do CONTEXT.md
    │   ├── pre-compact.ps1          ← Hook PreCompact
    │   └── stop-hook.ps1            ← Hook Stop — relaia o alerta de 5h pro modelo via decision:block
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
      ├── Verifica thresholds de contexto (70/85/95%) vs threshold-state.json
      │     └── Se cruzado → Start-Process save-context.ps1 (background)
      ├── Verifica threshold de rate limit 5h (default 96%, configurável) vs pct5h do payload
      │     └── Se cruzado → Start-Process save-context.ps1 (background) +
      │         escreve .claude/pending-5h-alert.json
      └── Imprime status bar no stdout

Claude Code (PreCompact)
  → pre-compact.ps1
      └── Chama save-context.ps1 diretamente

Claude Code (Stop — a cada vez que Claude terminaria o turno)
  → stop-hook.ps1
      ├── Se .claude/pending-5h-alert.json existe → consome, apaga o arquivo,
      │     e responde {"decision":"block","reason":"..."} no stdout
      │     (isso é o que efetivamente "para" Claude e o faz avisar o usuário
      │     e perguntar sobre agendar reinício — ver seção abaixo)
      └── Senão → exit 0 normal

Claude Code (/save-context)
  → Claude executa o slash command (salvo em .claude/commands/save-context.md)
      └── Claude gera CONTEXT.md com conteúdo real (não apenas placeholders)
```

### Regras de threshold (contexto: 70/85/95%)

- Estado persistido em `.claude/threshold-state.json` (reseta se `pct < 5%` após `pct > 20%` = nova sessão)
- Dispara o threshold mais alto cruzado; marca todos os menores como feitos (evita duplicatas em jumps, ex: 60% → 87% dispara apenas o 85%)
- Em reinstall, o state file é deletado → todos os thresholds disparam do zero

### Regra de threshold (rate limit 5h)

- Campo separado no mesmo `threshold-state.json`: `t5h` (disparado?) e `last5hResetsAt` (janela atual)
- Threshold configurável via `monitor-config.json` → `rate_limit_5h_threshold_pct` (default `96`) e `save_on_5h_threshold` (default `true`, liga/desliga a feature inteira)
- **Rearme por janela, não por queda de porcentagem**: como `pct5h` pode oscilar sem a janela realmente resetar, o rearme (`t5h = false`) só acontece quando `rate_limits.five_hour.resets_at` muda de valor — isto é, quando uma nova janela de 5h realmente começa. Isso evita duplicar o alerta dentro da mesma janela.
- Ao cruzar o threshold: roda `save-context.ps1` em background (trigger `threshold_5h_ratelimit`) e escreve `.claude/pending-5h-alert.json` com `{pct5h, threshold, resetsAt, resetStr}` para o `stop-hook.ps1` consumir

### Cálculo de porcentagem

```
calcPct = ceil((total_input_tokens + total_output_tokens + cache_creation_input_tokens + cache_read_input_tokens) / budget_tokens × 100)
apiPct  = used_percentage  (campo do payload, calculado internamente pelo Claude Code)
pct     = Max(calcPct, apiPct)
```

`budget_tokens` vem de `context_window.context_window_size` no payload — **dinâmico, não fixo**. Varia por modelo/sessão (ex: 200k em modelos padrão, 1M em sessões com contexto estendido como Sonnet 5 long-context). Nunca assuma 200k ao interpretar o pct exibido — sempre confira `context_window_size` do payload real (`dump-statusline.ps1`) antes de comparar tokens consumidos com a porcentagem da barra. Claude Code compacta antes de esgotar o budget; `used_percentage` reflete o budget efetivo — tomamos o maior dos dois (`calcPct`, `apiPct`) para nunca subestimar o uso real. Antes da v3.2, apenas `calcPct` era usado, o que gerava disparidade de ~15pp.

### Resolução de paths

Todos os paths são derivados de `$PSScriptRoot` (path absoluto do script em execução):
```powershell
$hooksDir    = $PSScriptRoot                     # .claude/hooks/
$claudeDir   = Split-Path $PSScriptRoot -Parent  # .claude/
$projectRoot = Split-Path $claudeDir -Parent     # raiz do projeto
```

Nunca use `Get-Location` ou paths do payload JSON para escrever arquivos — são não-confiáveis.

### Configuração de display

O arquivo `.claude/monitor-config.json` controla quais campos aparecem na barra. É lido a cada invocação do `statusline-monitor.ps1`; qualquer campo ausente tem `true` como default. O instalador cria o arquivo com todos os campos habilitados, mas **não sobrescreve** se já existir — configuração do usuário é preservada em reinstalls.

Campos disponíveis: `show_repo`, `show_branch`, `show_context`, `show_5h`, `show_reset`, `show_week`, `show_cost`, `show_model`.

Campos de feature (não são de display, mas moram no mesmo arquivo): `save_on_5h_threshold` (bool, default `true`) e `rate_limit_5h_threshold_pct` (int, default `96`) — controlam o alerta de rate limit 5h descrito abaixo.

### Notificação de save-context

Quando um threshold dispara, `statusline-monitor.ps1` imprime uma linha extra acima da barra de status:
```
Saving CONTEXT.md (85% used, trigger: threshold_85pct_used)...
```

Quando `save-context.ps1` conclui, escreve `.claude/save-done.txt` com o horário (`HH:mm:ss`). Na próxima invocação do status bar, o arquivo é lido, exibido como `CONTEXT.md saved at HH:MM:SS`, e deletado.

### Alerta de rate limit 5h (Stop hook + decision:block)

**Problema de arquitetura que essa feature resolve**: `statusLine` é a única invocação com dados de `rate_limits` no payload, mas seu stdout é só renderizado no rodapé do terminal — **invisível pro modelo**. Não existe forma de o statusLine "falar" com Claude. Só hooks como `Stop`, `PreToolUse`, `UserPromptSubmit` etc. têm o stdout lido de volta pelo Claude Code e injetado na conversa.

**Solução adotada**: divisão de responsabilidade entre dois hooks via um arquivo-ponte.

1. `statusline-monitor.ps1` (tem os dados) detecta `pct5h >= rate_limit_5h_threshold_pct`, roda `save-context.ps1` e escreve `.claude/pending-5h-alert.json` com os dados do alerta.
2. `stop-hook.ps1` (é lido pelo modelo) roda no fim de cada turno — exatamente o momento em que Claude tentaria devolver o controle ao usuário. Se o marcador existir, ele responde:
   ```json
   {"decision": "block", "reason": "Uso de tokens do intervalo de 5 horas atingiu X%. CONTEXT.md já foi salvo... pergunte se deseja agendar reinício automático, sugerindo o horário do próximo reset: HH:MM."}
   ```
   `decision:block` impede Claude de encerrar o turno normalmente — o `reason` é injetado como se fosse uma instrução, forçando Claude a avisar o usuário e perguntar sobre o reinício antes de efetivamente parar. Na chamada seguinte (marcador já apagado), o Stop hook volta a `exit 0` sem interferir.
3. **"Agendar reinício automático" é responsabilidade do Claude na conversa, não do hook** — o PowerShell não agenda nada sozinho. Se o usuário responder que sim, é o próprio Claude (usando skills como `/schedule`, `ScheduleWakeup` ou orientando o usuário a rodar `claude remote-control` no horário sugerido) quem cuida disso na sessão. O hook só garante que a pergunta seja feita no momento certo.

Payload do `Stop` hook continua sem `context_window`/`rate_limits` — por isso a detecção em si permanece 100% no `statusline-monitor.ps1`; o `stop-hook.ps1` só consome o marcador, nunca calcula pct sozinho.

---

## Como testar mudanças

1. Edite o hook relevante em `.claude/hooks/`
2. **Se a mudança for permanente**, replique no instalador (`install-v3.ps1` e/ou `install-v3.sh`)
3. Para testar o status bar manualmente, use `dump-statusline.ps1` para ver o payload real
4. Para testar o threshold, edite temporariamente `threshold-state.json` para forçar um threshold a disparar
5. Para testar o alerta de 5h isolado (sem esperar o rate limit real chegar em 96%): crie manualmente `.claude/pending-5h-alert.json` com `{"pct5h":97,"threshold":96,"resetsAt":0,"resetStr":"HH:MM"}` e rode `.claude\hooks\stop-hook.ps1` — deve imprimir o JSON `{"decision":"block","reason":"..."}` e apagar o arquivo

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
- Não commite `threshold-state.json`, `context-saves.log` ou `pending-5h-alert.json` — estão no `.gitignore`
- Não faça o `stop-hook.ps1` calcular pct de rate limit sozinho — ele não tem `rate_limits` no payload; ele só consome o marcador que o `statusline-monitor.ps1` escreveu

---

## Referências

- `README.md` — documentação completa com exemplos de output e troubleshooting
- `CONTEXT.md` — estado atual do desenvolvimento (leia no início de uma nova sessão)
- Claude Code hooks: `statusLine`, `PreCompact`, `Stop`
- Payload do statusLine contém: `context_window`, `cost`, `model`, `rate_limits`, `workspace`
