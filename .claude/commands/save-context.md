---
description: Salva o estado atual do desenvolvimento em CONTEXT.md
---

Analise o estado atual do projeto e gere/atualize o arquivo `CONTEXT.md` na raiz.

## Passos obrigatÃ³rios

1. Execute `git log --oneline -15` para ver os commits recentes
2. Execute `git diff HEAD --stat` para ver arquivos com mudanÃ§as pendentes
3. Execute `git status` para ver arquivos novos ou nÃ£o rastreados
4. Leia os arquivos principais que foram modificados recentemente
5. Gere o CONTEXT.md com a estrutura abaixo

## Estrutura do CONTEXT.md

# Context â€” [nome do projeto]
> Salvo em: [data e hora atual]
> Trigger: [manual | threshold_70pct | threshold_85pct | threshold_95pct | pre_compact]

## Status atual
[O que estÃ¡ funcionando e foi concluÃ­do]

## Em andamento
[O que estava sendo desenvolvido nesta sessÃ£o â€” seja especÃ­fico]

## DecisÃµes tÃ©cnicas
[Escolhas de arquitetura, libs escolhidas e POR QUÃŠ, abordagens descartadas]

## Arquivos relevantes
[Lista dos arquivos mais importantes com uma linha de descriÃ§Ã£o cada]

## PrÃ³ximos passos
[Lista ordenada do que falta fazer, do mais urgente ao menos urgente]

## Problemas conhecidos
[Bugs identificados, dÃ©bitos tÃ©cnicos, limitaÃ§Ãµes]

## InstruÃ§Ãµes importantes

- Seja especÃ­fico e direto â€” este arquivo serÃ¡ lido no inÃ­cio de uma nova sessÃ£o
- Na seÃ§Ã£o "DecisÃµes tÃ©cnicas", documente o raciocÃ­nio, nÃ£o apenas a conclusÃ£o
- Na seÃ§Ã£o "PrÃ³ximos passos", escreva aÃ§Ãµes concretas (ex: "Implementar validaÃ§Ã£o do campo email em src/forms/UserForm.tsx"), nÃ£o vagas ("melhorar formulÃ¡rio")
- Se o CONTEXT.md jÃ¡ existir, substitua o conteÃºdo completamente com as informaÃ§Ãµes atualizadas
- Confirme ao final: "âœ… CONTEXT.md atualizado em [timestamp]"
