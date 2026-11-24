# Antigravity Rules — FinSense Desktop

Consulte o manifesto e regras canônicas completas para agentes em:
- [AGENTS.md](./AGENTS.md)

### Diretrizes Obrigatórias:
1. Todas as alterações ou novas features devem atualizar o manifesto `AGENTS.md`.
2. Toda alteração deve ser finalizada com um commit semântico (Conventional Commits).
3. **NUNCA execute `git push`** sob hipótese alguma.
4. Toda nova feature, alteração de campos, novas entidades ou mudanças de arquitetura **deve obrigatoriamente** atualizar os fluxos de exportação e importação de dados e a sincronização na API (`FinSense-api`).
5. Respeite a Regra de Ouro (Competência vs Caixa) para cartões de crédito e o cálculo do Vale Intramês baseado no acumulado do mês anterior.
