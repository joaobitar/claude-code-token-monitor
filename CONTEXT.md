---
trigger: manual
saved_at: 2026-07-21T19:10:00Z
---

# Context -- token_monitor

> Saved at: 2026-07-21T19:10:00Z
> Trigger: manual

## Git Log (last 15)
```
dd67511 chore: ignore runtime artifacts and commit dump-statusline diagnostic tool
43f608e feat: v3.3 — configurable display fields via monitor-config.json
3f2fdb1 fix: correct payload field names for context window calculation
9ac6976 feat: v3.2 — accurate pct (Max formula), save-context notification, cleanup
e45f864 test: add Pester v5 test suite (54 tests) and project docs
ce092e0 docs: rewrite README to reflect v3.1 implementation
126a0e6 fix: accurate token percentage and improved cleanup on reinstall
e6a56ea fix: reliable path resolution and threshold trigger logic
87668f5 Initial release: Claude Code Token Monitor v3
```

## Pending Changes
```
 .claude/commands/save-context.md     |   2 +-
 .claude/hooks/statusline-monitor.ps1 |  74 +++++++--
 .claude/hooks/stop-hook.ps1          |  27 +++-
 .claude/monitor-config.json          |   6 +-
 .claude/settings.json                |  11 ++
 .gitignore                           |   1 +
 CLAUDE.md                            |  56 ++++++--
 CONTEXT.md                           |  46 +++---
 README.md                            | 250 +++++++++++++++++++++++++++++++---
 install-v3.ps1                       | 220 +++++++++++++++++++++++++++++++++++-
 install-v3.sh                        | 200 +++++++++++++++++++++++++++++++++
```

## Git Status
```
 M .claude/commands/save-context.md
 M .claude/hooks/statusline-monitor.ps1
 M .claude/hooks/stop-hook.ps1
 M .claude/monitor-config.json
 M .claude/settings.json
 M .gitignore
 M CLAUDE.md
 M CONTEXT.md
 M README.md
 M install-v3.ps1
 M install-v3.sh
?? .claude/hooks/post-worktree-sync.ps1
?? .claude/worktrees/
```

## Current Status

v3.4 implementada e testada end-to-end em sessão real: alerta de rate limit de 5h.

- Threshold de contexto (70/85/95%) e save-context automático: inalterados, funcionando desde v3.3.
- Nova feature: quando o rate limit de 5h cruza um limite configurável (default 96%), o sistema salva `CONTEXT.md` e força Claude a avisar o usuário e perguntar sobre agendar reinício automático.
- Teste ao vivo feito baixando `rate_limit_5h_threshold_pct` para 1% temporariamente: confirmado que `statusline-monitor.ps1` detectou, salvou CONTEXT.md, escreveu `pending-5h-alert.json`, e `stop-hook.ps1` interceptou o fim do turno com `{"decision":"block","reason":"..."}` — a mensagem chegou ao modelo e foi relaiada ao usuário corretamente. Config e state restaurados aos valores reais (96%, `t5h: false`) depois do teste.
- Documentação atualizada: `CLAUDE.md` (arquitetura completa da feature) e `README.md` (reescrito a partir do HEAD — o README que estava no working tree tinha regressado pra uma versão v1.0 obsoleta, não commitada; a versão nova parte do conteúdo real do último commit, não do lixo que estava em disco).

## In Progress

Nada em andamento — feature completa, testada, documentada. Prestes a commitar.

## Technical Decisions

**Por que o alerta de 5h passa pelo `Stop` hook em vez do `statusLine`:** `statusLine` é a única invocação com acesso a `rate_limits` no payload, mas seu stdout só é renderizado no terminal — nunca chega ao modelo. `Stop` é o hook cujo stdout É lido de volta pelo Claude Code. Por isso a arquitetura ficou dividida: `statusline-monitor.ps1`/`.sh` detecta e escreve um arquivo-ponte (`.claude/pending-5h-alert.json`); `stop-hook.ps1`/`.sh` consome esse arquivo e responde `{"decision":"block","reason":"..."}`, o que impede Claude de encerrar o turno normalmente e força a relay da mensagem para o usuário.

**Por que o rearme do alerta usa `resets_at` e não a queda de `pct5h`:** `pct5h` pode oscilar (cache, requests concorrentes) sem que a janela de 5h realmente tenha resetado. Usar a mudança do timestamp `resets_at` como sinal de "nova janela" é mais confiável e evita disparar o mesmo alerta várias vezes dentro da mesma janela.

**Por que "agendar reinício automático" não é implementado em PowerShell:** os hooks rodam como scripts sem acesso às ferramentas de agendamento do Claude Code (`/schedule`, `ScheduleWakeup`, etc.) — essas só existem no lado do modelo/agente. A decisão foi deixar o agendamento em si como responsabilidade conversacional: o hook só garante que a pergunta certa seja feita no momento certo; se o usuário confirmar, é Claude quem aciona o agendamento na sessão.

**Por que o README foi reescrito do zero ao invés de editado incrementalmente:** o arquivo no working tree (antes desta sessão) continha documentação de v1.0 (`.claude-code/`, budget fixo de 200k, thresholds 30/15/5) completamente desatualizada e nunca commitada — uma regressão silenciosa. O HEAD do git (commit `43f608e`) tinha a doc correta de v3.3. A reescrita partiu do HEAD, não do que estava em disco.

## Next Steps

1. Commitar as mudanças (hooks, installers, monitor-config.json, settings.json, CLAUDE.md, README.md, .gitignore, save-context.md)
2. Push para o GitHub (`origin/master`, `https://github.com/joaobitar/claude-code-token-monitor`)
3. (Futuro, não pedido ainda) Avaliar alerta equivalente para o rate limit semanal (7 dias) — usuário ainda não confirmou interesse

## Known Issues

- `install-v3.sh` (Linux/macOS) nunca cria `monitor-config.json` com defaults — só `install-v3.ps1` faz isso. Pré-existente, não introduzido nesta sessão. Bash statusline também nunca leu `show_*` toggles do config (só a nova feature de 5h passou a ler `monitor-config.json` no lado bash).
- Formatação de custo (`$X.XXX`) usa separador decimal dependente da locale do PowerShell (aparência tipo `$1,234` em locale pt-BR) — bug pré-existente, não relacionado a esta feature.
- `.claude/commands/save-context.md` tem mojibake de encoding em várias linhas (acentos corrompidos tipo `Ã©`) — bug pré-existente no arquivo runtime, não corrigido nesta sessão (fora de escopo).

---
Last updated: 2026-07-21T19:10:00Z
Generated by Claude Code Token Monitor (manual)
