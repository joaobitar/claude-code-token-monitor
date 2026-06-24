# ⚡ Quick Start — Claude Code Token Monitor

Guia rápido de instalação e uso em 5 minutos.

---

## 🎯 O que você precisa saber

**Problema**: Claude Code compacta após ~200k tokens, perdendo contexto.

**Solução**: Monitor automático que:
- Exibe % de tokens no rodapé
- Salva contexto em 30%, 15%, 5%
- Mantém `CONTEXT.md` sempre atualizado
- Nenhuma configuração necessária

---

## ⚡ Instalação (1 minuto)

```bash
cd /seu/projeto/com/claude-code
bash install.sh
```

Pronto! Sistema está ativo.

---

## 📊 Como funciona

### Rodapé do Claude Code

```
[Token Monitor] 30% ██████░░░░░░░░░░░░░░ [57000 / 190000 tokens]
```

Você vê:
- Barra de progresso colorida (verde → amarelo → vermelho)
- Porcentagem de tokens usados
- Tokens atuais / Orçamento total

### Automático

A cada **30%, 15%, 5%**, sistema executa automaticamente:

```
⚠️  Token threshold atingido! Executando /save-context...
✅ CONTEXT.md atualizado em 2024-06-23T10:35:22Z
```

Seu `CONTEXT.md`:
- ✅ Coleta últimos 15 commits
- ✅ Analisa arquivos modificados
- ✅ Lista próximos passos
- ✅ Rastreia problemas conhecidos

### Na próxima sessão

```bash
# Nova sessão lê CONTEXT.md automaticamente
claude-code

# Abre CONTEXT.md para retomar exatamente de onde parou
```

---

## 📁 Arquivos criados

```
.claude-code/
├── config.json              ← Customize aqui
├── .env
├── hooks/
│   ├── statusline-monitor.sh
│   ├── pre-compact.sh
│   └── save-context.sh
└── logs/
    ├── token-monitor.log
    └── context-saves.log

CONTEXT.md                  ← Gerado automaticamente
```

---

## 🎮 Comandos

```bash
# Ver status
cat .claude-code/token-state.json | jq '.last_percentage'

# Forçar save manual (a qualquer momento)
claude-code /save-context

# Ver logs
tail -f .claude-code/logs/token-monitor.log

# Ver histórico de saves
cat .claude-code/logs/context-saves.log

# Limpar
rm .claude-code/logs/*.log .claude-code/token-state.json
```

---

## ⚙️ Customizar

### Alterar quando salvar contexto

Edite `.claude-code/config.json`:

```json
{
  "monitors": {
    "token_monitor": {
      "thresholds": [40, 20, 10]  // ← De 30%, 15%, 5%
    }
  }
}
```

### Mudar orçamento de tokens

```json
{
  "monitors": {
    "token_monitor": {
      "budget_limit": 250000  // ← De 190000
    }
  }
}
```

### Desabilitar barra (apenas logs)

```json
{
  "monitors": {
    "token_monitor": {
      "statusline": false
    }
  }
}
```

---

## 📝 Exemplo de CONTEXT.md

Automaticamente gerado com:

```markdown
# Context — seu-projeto

> Salvo em: 2024-06-23T10:35:22Z
> Trigger: threshold-30

## Status Atual
✅ Implementado feature X
✅ Corrigido bug Y

## Em Andamento
🔄 Refatorando componente Z
🔄 Adicionando testes

## Decisões Técnicas
- Escolhemos TypeScript por type safety
- Alternativa (Go) rejeitada por falta de comunidade

## Próximos Passos
1. 🔴 CRÍTICO: Integração com parsing (2h)
2. 🟠 IMPORTANTE: Testes unitários (2h)
3. 🟡 MÉDIO: Documentação (1h)

## Problemas Conhecidos
- Bug: Porcentagem inverte após reset (~2s)
- Débito: Refatorar parser de git

---
Última atualização: 2024-06-23T10:35:22Z
```

---

## 🐛 Troubleshooting

### Monitor não aparece

```bash
chmod +x .claude-code/hooks/*.sh
bash .claude-code/hooks/statusline-monitor.sh
```

### Save não funciona

```bash
bash .claude-code/hooks/save-context.sh . manual
cat .claude-code/logs/context-saves.log
```

### Resetar tudo

```bash
rm -rf .claude-code/logs/* .claude-code/token-state.json
bash .claude-code/hooks/statusline-monitor.sh
```

---

## 📚 Docs Completa

| Doc | Para |
|-----|------|
| `token-monitor-hook.md` | Entender como funciona |
| `save-context-automation.md` | Spec técnico do save |
| `claude-code-setup.md` | Instalação detalhada |
| `README.md` | Visão geral completa |
| `CONTEXT.md.template` | Exemplo de contexto |

---

## ✅ Checklist

- [ ] Rodar `bash install.sh`
- [ ] Ver `.claude-code/` criado
- [ ] Testar: `bash .claude-code/hooks/statusline-monitor.sh`
- [ ] Editar `.claude-code/config.json` se necessário
- [ ] Commitar: `git add .claude-code/ CONTEXT.md`
- [ ] Começar uma sessão de Claude Code

---

## 🎯 Próximas sessões

1. **Ao retomar**: Abra `CONTEXT.md` primeiro
2. **Leia**: Seção "Em Andamento" — sabe exatamente onde parou
3. **Continue**: Próximas ações já estão listadas
4. **Sistema salva**: Automaticamente a cada threshold

---

## 🚀 Pronto?

```bash
cd seu-projeto
bash install.sh
claude-code
```

Sistema estará monitorando desde agora! 🎉

---

**Dúvidas?** Veja documentação completa em `.claude-code/` ou `docs/`

**Versão**: 1.0  
**Tempo total**: ~5 minutos de setup  
**Valor**: Recupera contexto em TODAS as sessões futuras ✨
