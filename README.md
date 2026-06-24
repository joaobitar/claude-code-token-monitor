# 🚀 Claude Code Token Monitor

Sistema automatizado de monitoramento de tokens para Claude Code CLI com save-context inteligente.

> **Mantém seu projeto sincronizado automaticamente, salvando contexto em 30%, 15% e 5% do orçamento de tokens.**

---

## ✨ Funcionalidades

✅ **Monitoramento em Tempo Real**
- Barra de progresso colorida no rodapé (verde → amarelo → vermelho)
- Exibe porcentagem e quantidade de tokens usados vs. orçamento (200k)
- Exibe tokens e % usados nas últimas 5h e na semana atual
- Atualização a cada mensagem

✅ **Save-Context Automático**
- Triggers em 70%, 85% e 95% de tokens usados
- Antes de compactação de sessão (pre-compact hook)
- Manualmente via comando `/save-context`

✅ **CONTEXT.md Inteligente**
- Coleta automática de: git log, diffs, status, arquivos modificados
- Estrutura padronizada com 8 seções principais
- Detecta tipo de projeto (Node.js, Python, Go, Rust, Java, etc.)
- Fácil de ler e atualizar

✅ **Sem Dependências Externas**
- Apenas bash, git e jq (opcional)
- Funciona em qualquer máquina com CLI do Claude Code
- Estado persistido em JSON simples

✅ **Logging Completo**
- Registra todos os saves em `.claude-code/context-saves.log`
- Monitora uso de tokens em `.claude-code/token-monitor.log`
- Fácil debugging e auditoria

---

## 🎯 Por que usar?

### Problema

Claude Code CLI compacta a sessão automaticamente em ~200k tokens. Isso pode causar:
- **Perda de contexto**: Detalhes importantes são esquecidos
- **Recomeço**: Cada nova sessão começa "do zero"
- **Fragmentação**: Informações espalhadas em múltiplos arquivos
- **Retrabalho**: Refazer análises já feitas

### Solução

**CONTEXT.md sincronizado** com histórico de desenvolvimento:
- ✅ Retoma exatamente de onde parou
- ✅ Sabe quais arquivos foram modificados
- ✅ Lembra decisões técnicas tomadas
- ✅ Tracks problemas conhecidos e débitos

**Exemplo real:**
```
Sessão 1: 57,000 tokens → Save em 30% → CONTEXT.md criado
Sessão 2: 95,000 tokens → Save em 15% → CONTEXT.md atualizado
Sessão 3: Compacta      → Pre-compact   → CONTEXT.md finalizado
```

---

## 🚀 Instalação Rápida (2 minutos)

### Opção 1: One-liner

**Windows (PowerShell):**
```powershell
cd C:\seu\projeto
powershell -File install-v3.ps1
```

**Linux / macOS (bash):**
```bash
cd /seu/projeto
bash install-v3.sh
```

### Opção 2: Manual

```bash
# Criar estrutura
mkdir -p .claude-code/hooks

# Copiar arquivos
cp token-monitor-hook.md .claude-code/
cp save-context-automation.md .claude-code/

# Extrair scripts
sed -n '/^```bash/,/^```$/p' .claude-code/token-monitor-hook.md | sed '1d;$d' > .claude-code/hooks/statusline-monitor.sh
chmod +x .claude-code/hooks/*.sh

# Criar config
cat > .claude-code/config.json <<'EOF'
{
  "monitors": {
    "token_monitor": {
      "enabled": true,
      "budget_limit": 190000,
      "thresholds": [30, 15, 5]
    }
  }
}
EOF

# Testar
bash .claude-code/hooks/statusline-monitor.sh
```

---

## 📊 Uso

### Automático (padrão)

```bash
# Nada a fazer! O sistema funciona sozinho
# Simples iniciar uma sessão de Claude Code:

claude-code  # Começa a monitorar automaticamente
```

**O que acontece automaticamente:**
1. Cada mensagem → Token monitor atualiza rodapé (uso atual + 5h + semana)
2. 70% usados → Save-context #1
3. 85% usados → Save-context #2
4. 95% usados → Save-context #3
5. Compactação → Pre-compact hook → Save final

### Manual

```bash
# A qualquer momento, salvar contexto manualmente
claude-code /save-context

# Resultado:
# ✅ CONTEXT.md atualizado em 2024-06-23T10:35:22Z
```

### Monitorar em Tempo Real

```bash
# Terminal 1: Ver monitor
tail -f .claude-code/logs/token-monitor.log

# Terminal 2: Ver saves
tail -f .claude-code/logs/context-saves.log

# Terminal 3: Ver estado
watch -n 1 'cat .claude-code/token-state.json | jq'
```

---

## 📁 Estrutura do Projeto

```
seu-projeto/
├── CONTEXT.md                        ← Gerado/atualizado automaticamente
├── .claude/
│   ├── settings.json                 ← Configuração de hooks e statusLine
│   ├── context-saves.log             ← Log de saves (gerado, no .gitignore)
│   ├── threshold-state.json          ← Estado de thresholds (gerado, no .gitignore)
│   ├── usage-log.json                ← Histórico 5h/semanal (gerado, no .gitignore)
│   ├── commands/
│   │   └── save-context.md           ← /save-context slash command
│   └── hooks/
│       ├── statusline-monitor.ps1    ← Status bar (Windows)
│       ├── statusline-monitor.sh     ← Status bar (Unix)
│       ├── stop-hook.ps1/.sh         ← Thresholds 70/85/95%
│       ├── pre-compact.ps1/.sh       ← Hook pré-compactação
│       └── save-context.ps1/.sh      ← Lógica compartilhada de save
└── src/
    └── ...                           ← Seu código
```

---

## 📋 Exemplo de CONTEXT.md

```markdown
# Context — meu-projeto

> Salvo em: 2024-06-23T10:35:22Z
> Trigger: threshold-30
> Tipo: Node.js, Claude Code

## Status Atual
✅ Sistema de monitoramento implementado
✅ Hooks funcionando
✅ CONTEXT.md auto-gerado

## Em Andamento
🔄 Melhorar parsing de arquivos modificados
🔄 Adicionar testes unitários

## Decisões Técnicas
- **Node.js + TypeScript**: Type safety, melhor integração
- **Hooks em Bash**: Máxima compatibilidade, sem dependências

## Próximos Passos
1. 🔴 CRÍTICO: Completar integração de parsing (2h)
2. 🟠 IMPORTANTE: Adicionar validação e error handling (45m)
3. 🟡 MÉDIO: Testes unitários completos (2h)

## Problemas Conhecidos
1. Porcentagem pode inverter após reset (~2s)
2. Arquivo .env não é sourced automaticamente

---

Última atualização: 2024-06-23T10:35:22Z
```

---

## ⚙️ Configuração

### config.json

```json
{
  "monitors": {
    "token_monitor": {
      "enabled": true,
      "budget_limit": 200000,        // ← 200k tokens
      "thresholds": [70, 85, 95],    // ← % usados para acionar save
      "statusline": true              // ← Mostrar barra no rodapé
    }
  },
  "save_context": {
    "enabled": true,
    "output_file": "./CONTEXT.md"
  }
}
```

### .env

```bash
export TOKEN_BUDGET_LIMIT=200000
export TOKEN_SAVE_CONTEXT_THRESHOLDS="70 85 95"
export TOKEN_MONITOR_ENABLED=true
export PROJECT_ROOT="."
```

---

## 🔍 Monitoramento

### Rodapé do Claude Code

```
repo (main) | OK [########------------] 42% (84k) | 5h: 210k (105%) | Week: 650k (325%) | $0.042 | Claude Sonnet
```

**Colunas:**
- `[bar] pct% (Xtok)` — uso atual da janela de contexto (orçamento: 200k)
- `5h: Xtok (Y%)` — total de tokens usados nas últimas 5 horas
- `Week: Xtok (Z%)` — total de tokens usados nos últimos 7 dias
- `$cost` — custo total da sessão
- `model` — modelo em uso

**Cores da barra:**
- Verde (0–69%): Zona segura
- Amarelo (70–84%): Atenção
- Vermelho (85%+): Crítico

### Logs

**token-monitor.log:**
```
2024-06-23T10:30:00Z [INIT] Session started | Budget: 190000
2024-06-23T10:35:22Z [30%] Threshold reached | Tokens: 57000
```

**context-saves.log:**
```
[2024-06-23T10:35:23Z] [SUCCESS] CONTEXT.md gerado
[2024-06-23T10:42:18Z] [SUCCESS] CONTEXT.md atualizado
```

---

## 🐛 Troubleshooting

### Monitor não aparece

```bash
# Verificar se está ativado
cat .claude-code/config.json | jq '.monitors.token_monitor.statusline'

# Testar manualmente
bash .claude-code/hooks/statusline-monitor.sh

# Verificar permissões
chmod +x .claude-code/hooks/statusline-monitor.sh
```

### Save-context não executa

```bash
# Testar script
bash .claude-code/hooks/save-context.sh . manual

# Ver log
tail .claude-code/logs/context-saves.log

# Ver estado
cat .claude-code/token-state.json | jq
```

### JSON corrompido

```bash
# Limpar e recriar
rm .claude-code/token-state.json
bash .claude-code/hooks/statusline-monitor.sh
```

---

## 📚 Documentação

| Documento | Descrição |
|-----------|-----------|
| `token-monitor-hook.md` | Especificação técnica do monitor |
| `save-context-automation.md` | Especificação técnica do save |
| `claude-code-setup.md` | Guia detalhado de instalação |
| `docs/INSTALL.md` | Quick start |
| `CONTEXT.md` | Template do arquivo de contexto |
| `install.sh` | Script de instalação automática |

---

## 🎮 Comandos Úteis

```bash
# Ver histórico de saves
cat .claude-code/logs/context-saves.log

# Ver token usage em tempo real
watch -n 1 'cat .claude-code/token-state.json | jq .last_percentage'

# Forçar save manual
claude-code /save-context

# Limpar logs
rm .claude-code/logs/*.log

# Ver config atual
cat .claude-code/config.json | jq

# Verificar hooks
ls -la .claude-code/hooks/
```

---

## 🔐 Git Integration

Sistema inclui entradas automáticas no `.gitignore`:

```
# Claude Code Token Monitor
.claude-code/logs/
.claude-code/*.log
.claude-code/token-state.json
```

Recomenda-se commitar:
```bash
git add .claude-code/config.json .claude-code/.env .claude-code/hooks/
git add CONTEXT.md
git commit -m "Add Claude Code token monitor"
```

---

## 📊 Exemplo de Sessão Real

```
$ claude-code

[Token Monitor] 0% ░░░░░░░░░░░░░░░░░░░░ [0 / 190000 tokens]

> Ajude-me a implementar autenticação

[Token Monitor] 5% █░░░░░░░░░░░░░░░░░░░ [9500 / 190000 tokens]

> Adicione testes para o login

[Token Monitor] 15% ███░░░░░░░░░░░░░░░░░ [28500 / 190000 tokens]

[Token Monitor] 30% ██████░░░░░░░░░░░░░░ [57000 / 190000 tokens]
⚠️  Token threshold atingido! Executando /save-context...
ℹ️  INFO: Iniciando save-context automático
✅ CONTEXT.md gerado em: ./CONTEXT.md

> Refatore o componente de login

[Token Monitor] 50% ██████████░░░░░░░░░░ [95000 / 190000 tokens]

[Token Monitor] 75% ███████████████░░░░░░ [142500 / 190000 tokens]
⚠️  Token threshold atingido! Executando /save-context...
✅ CONTEXT.md atualizado

[Token Monitor] 95% ███████████████████░░ [180500 / 190000 tokens]
⚠️  Token threshold atingido! Executando /save-context...
✅ CONTEXT.md finalizado

🔄 Iniciando compactação de sessão...
🔄 Executando pre-compact hook...
✅ Context salvo antes da compactação
```

---

## 🚀 Próximos Passos

1. **Instalar**: `bash install.sh`
2. **Customizar**: Edite `.claude-code/config.json`
3. **Usar**: Abra Claude Code normalmente
4. **Monitorar**: Veja `CONTEXT.md` sendo atualizado automaticamente

---

## 💡 Tips & Tricks

### Customizar Thresholds

Para save em 40%, 20%, 10%:

```json
{
  "monitors": {
    "token_monitor": {
      "thresholds": [40, 20, 10]
    }
  }
}
```

### Desabilitar Statusline

Para apenas logging, sem exibição:

```json
{
  "monitors": {
    "token_monitor": {
      "statusline": false
    }
  }
}
```

### Aumentar Budget

Se usar Claude Code com mais tokens:

```json
{
  "monitors": {
    "token_monitor": {
      "budget_limit": 250000
    }
  }
}
```

---

## 🤝 Contribuindo

Sugestões e melhorias são bem-vindas:

1. Customize o `CONTEXT.md` conforme seu projeto
2. Ajuste os thresholds para seu workflow
3. Compartilhe templates específicos do seu tipo de projeto

---

## 📝 Licença

Uso livre para projetos pessoais e comerciais.

---

## 📞 Suporte

Se encontrar problemas:

1. Verifique: `cat .claude-code/logs/*.log`
2. Teste manualmente: `bash .claude-code/hooks/statusline-monitor.sh`
3. Limpe e recomece: `rm .claude-code/token-state.json`

---

## 🎯 Mapa de Funcionalidades

```
✅ Implementado
├── Monitor em tempo real
├── Thresholds de 30%, 15%, 5%
├── Save-context automático
├── Pre-compact hook
├── Geração de CONTEXT.md
├── Logging completo
├── Suporte a múltiplos tipos de projeto
└── Integração git

🔄 Em desenvolvimento
├── Parsing inteligente de arquivos
├── Dashboard de histórico
├── Auto-commit de CONTEXT.md
└── Temas customizáveis

💭 Planejado
├── Análise de commits via LLM
├── Sugestões automáticas
├── Integração com GitHub
└── Sync entre projetos
```

---

**Versão**: 3.0  
**Status**: Production Ready  
**Última atualização**: 2026-06-24  
**Plataformas**: Windows (PowerShell), Linux/macOS (bash + jq ou python3)

---

> 🚀 **Comece agora**: `bash install.sh` em seu projeto Claude Code!
