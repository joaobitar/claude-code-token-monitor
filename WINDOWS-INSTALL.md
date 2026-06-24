# 🪟 Instalação para Windows — Claude Code Token Monitor

Guia específico para Windows (PowerShell, sem dependências).

---

## ✅ Instalação (2 minutos)

### **Passo 1: Baixar o script**

Coloque o arquivo `install.ps1` na raiz do seu projeto:

```
C:\Users\joaob\Documents\claude_code\clin-app\
├── install.ps1        ← Coloque aqui
├── src/
├── package.json
└── ...
```

### **Passo 2: Executar PowerShell**

Abra **PowerShell** (NÃO precisa ser Admin) na pasta do projeto:

```powershell
cd C:\Users\joaob\Documents\claude_code\clin-app
```

### **Passo 3: Executar o script**

```powershell
powershell -ExecutionPolicy Bypass -File install.ps1
```

**Pronto!** ✅ Sistema está instalado e ativo.

---

## 📁 O que foi criado

```
.claude-code/
├── config.json              ← Customize aqui se precisar
├── .env                     ← Variáveis de ambiente
├── hooks/
│   ├── statusline-monitor.ps1
│   ├── pre-compact.ps1
│   └── save-context.ps1
└── logs/
    ├── token-monitor.log
    └── context-saves.log

CONTEXT.md                   ← Gerado automaticamente
docs/
└── INSTALL.md
```

---

## 🚀 Próximos Passos

1. ✅ Instalação completa — nada mais a fazer
2. Abra Claude Code normalmente
3. Use seu projeto como sempre
4. Sistema monitora e salva automaticamente!

---

## 🎮 Como usar

### **Automático (padrão)**

Nada a fazer! Apenas abra Claude Code:

```bash
claude-code
```

Sistema monitora e salva automaticamente em:
- 30% tokens → CONTEXT.md salvo
- 15% tokens → CONTEXT.md atualizado
- 5% tokens → CONTEXT.md finalizado
- Pré-compactação → Save final + reset

### **Manual (qualquer momento)**

```bash
claude-code /save-context
```

### **Ver logs**

```powershell
# Ver últimas saves
cat .claude-code\logs\context-saves.log

# Ver monitor log
cat .claude-code\logs\token-monitor.log

# Ver estado atual
cat .claude-code\token-state.json | ConvertFrom-Json
```

---

## ⚙️ Customizar

### **Mudar thresholds (30%, 15%, 5%)**

Edite `.claude-code\config.json`:

```json
{
  "monitors": {
    "token_monitor": {
      "thresholds": [40, 20, 10]  // Altere aqui
    }
  }
}
```

### **Alterar orçamento de tokens (190000)**

```json
{
  "monitors": {
    "token_monitor": {
      "budget_limit": 250000  // Altere aqui
    }
  }
}
```

---

## 🐛 Troubleshooting

### **Erro: "ExecutionPolicy"**

Rode com o comando completo:

```powershell
powershell -ExecutionPolicy Bypass -File install.ps1
```

Ou defina permanentemente:

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### **Erro: "git não encontrado"**

Você pode continuar instalação mesmo sem git, mas:

```
⚠️ Git não encontrado (altamente recomendado)
Instale de: https://git-scm.com/download/win
Continuar mesmo assim? (s/n): s
```

Sem git, o CONTEXT.md não terá:
- Commits recentes
- Mudanças pendentes
- Status git completo

**Recomendação**: Instale Git depois.

### **Problema: Monitor não aparece**

Verifique se CONTEXT.md foi criado:

```powershell
cat CONTEXT.md
```

Se existir → Sistema funcionando! ✅

### **Problema: Limpar tudo**

```powershell
# Remover instalação
Remove-Item -Recurse -Force .claude-code

# Remover CONTEXT.md
Remove-Item CONTEXT.md

# Reinstalar
powershell -ExecutionPolicy Bypass -File install.ps1
```

---

## 📊 Exemplo de CONTEXT.md

Após primeira sessão, seu `CONTEXT.md` terá:

```markdown
# Context — clin-app

> Salvo em: 2024-06-23T10:35:22Z
> Trigger: threshold-30
> Tipo do Projeto: Node.js, Claude Code

## Status Git

### Commits Recentes (últimos 15)
- a1b2c3d Refactor: Simplify token monitor logic
- e4f5g6h Feat: Add pre-compact hook integration
- ...

## Status Atual
✅ Implementado feature X
✅ Corrigido bug Y

## Em Andamento
🔄 Refatorando componente Z
🔄 Adicionando testes

## Próximos Passos
1. 🔴 CRÍTICO: Integração com parsing (2h)
2. 🟠 IMPORTANTE: Testes unitários (2h)
3. 🟡 MÉDIO: Documentação (1h)

---
```

---

## 💡 Dicas Windows

### **Abrir diretório no PowerShell**

```powershell
# Na pasta, abrir PowerShell:
# - Botão direito → Open PowerShell here
# - Ou: Shift + Click direito

# Navegar para pasta
cd C:\seu\caminho
```

### **Integração com VS Code**

```powershell
# Abrir VS Code na pasta
code .

# Terminal do VS Code também roda os hooks
```

### **Git Bash (alternativa)**

Se tiver Git instalado, pode usar Git Bash também:

```bash
bash install.sh
```

Mas PowerShell é mais simples — nenhuma instalação extra.

---

## ✅ Checklist

- [ ] `install.ps1` está na raiz do projeto
- [ ] Executado: `powershell -ExecutionPolicy Bypass -File install.ps1`
- [ ] Viu mensagens de sucesso (✅)
- [ ] `.claude-code/` foi criado
- [ ] `CONTEXT.md` foi criado
- [ ] Abriu Claude Code normalmente
- [ ] Sistema está ativo e monitorando

---

## 🎯 Resumo

```powershell
# Tudo que você precisa:
cd seu-projeto
powershell -ExecutionPolicy Bypass -File install.ps1

# ✅ Sistema está ativo
# ✅ Monitora tokens automaticamente
# ✅ Salva CONTEXT.md em 30%, 15%, 5%
# ✅ Nenhuma dependência extra
```

---

**Pronto! Sistema instalado e funcionando.** 🎉

Qualquer dúvida, veja `docs\INSTALL.md` ou `CONTEXT.md` depois da primeira sessão.
