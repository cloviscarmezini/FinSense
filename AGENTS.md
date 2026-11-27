# Manifesto do Agente Antigravity — FinSense Desktop

> **Documento Canônico de Arquitetura, Regras de Negócio e Diretrizes de Engenharia para Agentes Autônomos**  
> **Escopo:** Aplicativo Desktop macOS (`FinSense`)  
> **Linguagem / Stack:** Swift 5.9+ / SwiftUI (macOS 14.0+) / AppKit / Apple Silicon Metal  
> **Repositório:** `FinSense` (Desktop App)

---

## ⚠️ Instruções Obrigatórias e Inegociáveis para Qualquer Agente

1. **Revisão e Manutenção Contínua deste Manifesto:**  
   Sempre que implementar uma nova funcionalidade, refatorar um módulo, alterar a modelagem de dados ou modificar regras de negócio, você **DEVE** revisar e atualizar este manifesto (`AGENTS.md`), mantendo-o 100% fidedigno ao código-fonte.
2. **Commits Semânticos Obrigatórios & Proibição de `git push`:**  
   Toda e qualquer alteração no código deve ser finalizada com um commit semântico seguindo a convenção *Conventional Commits* (ex.: `feat:`, `fix:`, `refactor:`, `test:`, `docs:`, `perf:`). **NUNCA execute `git push`** sob hipótese alguma para branches remotas; os commits devem permanecer estritamente no repositório local.
3. **Garantia de Qualidade e Validação de Testes:**  
   Antes de considerar uma tarefa concluída, compile o projeto (`swift build`) e execute a suíte de testes unitários relevante (`swift test`). Não introduza regressões em funcionalidades existentes.
4. **Respeito aos Padrões de Design e UX do macOS:**  
   O FinSense Desktop adota design nativo macOS com `NavigationSplitView`, cartões com altura padronizada (`MetricCardView`), sparklines nativos (`Charts`), formatação monetária brasileira rigorosa (`BRLFormatters`), acessibilidade e suporte completo a dark/light mode.
5. **Paridade Obrigatória de Exportação, Importação e Sincronização na API:**  
   Toda e qualquer implementação de nova feature, alteração arquitetural, adição ou modificação de entidades, campos ou modelos de dados **DEVE** obrigatoriamente refletir de ponta a ponta na funcionalidade de exportação e importação de dados (assegurando persistência completa e compatibilidade retroativa com backups legados) e na camada de sincronização com a API (adaptando esquemas, mutações e endpoints no `FinSense-api`).

---

## 1. Visão Geral da Arquitetura do App Desktop

```
FinSense (macOS App)
├── Models/
│   ├── DomainModels.swift               # Contas, Categorias, Transações, Investimentos, Dívidas
│   ├── PlanningAndInsightsModels.swift  # Vale Intramês, Sinking Funds, Cenários E-Se, Insights ML, Review Mensal
│   ├── LoanModel.swift & FinancingModel # Contratos de Empréstimo/Financiamento, SAC, PRICE
│   ├── CloudSyncModels.swift            # Mutações locais, DTOs de Push-Pull e Status Check
│   └── PresetsAndCatalogs.swift         # Presets de bancos, categorias padrão, ícones
├── Services/
│   ├── FinancialDataStore.swift         # Store central (@MainActor ObservableObject) e persistência
│   ├── FinancialDataStore+PlanningAndInsights.swift # Extensão de provisões, simulações, sinking funds e ML
│   ├── IntraMonthCashFlowEngine.swift   # Motor cronológico puro do Vale Intramês (Dois Níveis)
│   ├── DecisionAndScenarioEngine.swift  # Motor de decisões read-only (Amortizar vs Investir, Stress Test)
│   ├── BehavioralMLInsightsEngine.swift # Motor de ML comportamental e detectores contextuais
│   ├── CreditCardEngine.swift           # Ciclo de faturas, rateio de parcelas e limite
│   ├── CloudSyncService.swift           # Sincronização delta two-way offline-first e status leve
│   ├── AIChatOrchestrator.swift         # Super Agente local (Llama.cpp Metal / Apple Intelligence)
│   ├── StatementImportService.swift     # Importação inteligente de extratos PDF/CSV via LLM local
│   ├── AmortizationEngine.swift         # Cálculos de juros, parcelas e recálculo SAC/PRICE
│   └── KeychainHelper.swift             # Armazenamento seguro de tokens JWT
└── Views/
    ├── DashboardView.swift              # KPIs, Gráficos, Alertas Intramês, Fechamento Mensal
    ├── TransactionsView.swift           # Extrato do mês, filtros, linha de corte, reconciliação em massa
    ├── CreditCardsView.swift            # Gestão de cartões, faturas abertas/fechadas, pagamento
    ├── LoansAndFinancingsView.swift     # Empréstimos, financiamentos, amortização extraordinária
    ├── DebtsView.swift                  # Gestão de dívidas negociadas/abertas
    ├── InvestmentsView.swift            # Portfólio de investimentos, consolidados vs privados
    ├── DecisionsAndScenariosView.swift  # Comparador de amortização vs investimentos e teste de estresse
    ├── InsightsCenterView.swift         # Central de Insights ML e fechamento guiado do mês
    └── SharedComponents.swift           # MetricCardView, IntraMonthSparklineView, BRLFormatters
```

---

## 2. Catálogo Completo de Regras de Negócio e Funcionalidades

### 2.1. Cartão de Crédito: Regra de Ouro (Competência vs. Caixa)
- **Regime de Competência (Quando o gasto acontece):**
  - Todas as despesas efetuadas com Cartão de Crédito são contabilizadas na data da compra para gráficos de consumo por categoria, tetos orçamentários (`CategoryProvision`), cotas específicas (`CategoryQuotaRule`) e relatórios mensais.
- **Regime de Caixa (Quando o dinheiro sai da conta):**
  - Compras no cartão **NÃO debitam** o saldo consolidado bancário nem a conta bancária no momento da compra.
  - A saída real de caixa ocorre **estritamente na data do pagamento da fatura** (`isCreditCardInvoicePayment = true`).
  - O pagamento da fatura reduz o saldo da conta bancária pagadora e **recompõe imediatamente o limite disponível do cartão** (`usedLimit`).
  - O pagamento da fatura é categorizado internamente para **NÃO causar contagem dupla** nos relatórios de despesas por categoria.
- **Ciclo e Fechamento de Faturas:**
  - O cartão possui `closingDay` (fechamento), `bestPurchaseDay` (melhor dia de compra) e `dueDay` (vencimento).
  - Compras efetuadas a partir do melhor dia de compra caem automaticamente na fatura do mês subsequente.
  - O usuário pode selecionar manualmente outra fatura de cobrança ao cadastrar ou editar uma despesa no cartão (`creditCardInvoiceYearMonthKey`), vindo selecionada por padrão a próxima fatura não paga.
  - Compras parceladas (1x até 24x) são divididas com **precisão exata de centavos** entre as faturas mensais subsequentes; eventuais resíduos de arredondamento são absorvidos na 1ª parcela.

### 2.2. Visibilidade de Descasamento de Fluxo de Caixa (Vale Intramês)
- **Ponto de Partida Acumulado:**
  - Para qualquer mês selecionado (passado, presente ou futuro), o saldo inicial do mês (`openingBalance`) é o **saldo consolidado acumulado do mês anterior** (`accumulatedConsolidatedBalance(throughMonth: prevMonthEnd, includeProjectedUnpaid: !isClosed)`), que já incorpora todas as previsões acumuladas anteriores.
- **Previsões do Mês Selecionado:**
  - As previsões remanescentes do próprio mês selecionado **não entram** no cálculo cronológico dia a dia das transações. Elas afetam apenas a projeção de fechamento (`closingBalanceWithProvisions = closingBalance - cleanProvisions`).
- **Dois Níveis de Alerta no Card de Saldo Previsto:**
  1. **`.confirmedDeficit` (Criticidade Alta, Vermelho `#EF4444`):**
     - Ocorre quando transações reais ou agendadas levam o saldo acumulado para `< 0` em datas futuras ou datas passadas que ainda não foram normalizadas até a data atual (`!isResolvedByToday`), ou quando o mês abre e fecha no negativo.
     - Texto de alerta detalhado: `"Faltarão R$ X no dia dd/MM"` ou `"Faltarão R$ X no dia dd/MM e R$ Y no dia dd/MM"`.
  2. **`.possibleRisk` (Criticidade Menor / Atenção, Laranja `#F59E0B`):**
     - Ocorre quando as transações agendadas mantêm o saldo positivo ao longo do mês, porém as previsões de gastos sem data (`currentMonthRemainingProvisions`) podem fazer o caixa final fechar negativo.
     - Texto de alerta: `"Possibilidade de caixa negativo (até R$ X c/ previsões)"`.
  3. **`.none`:**
     - Saldo positivo em todo o período ou quando episódios negativos ocorreram no passado e já foram normalizados por uma receita antes ou até a data de hoje.
- **Marcações na Lista de Transações (`TransactionsView`):**
  - `LINHA DE CORTE` (`cutoffTransactionIds`): Transação exata onde o caixa acumulado virou negativo.
  - `CAIXA NEGATIVO` (`deepeningDeficitTransactionIds`): Transações subsequentes que aprofundam o saldo negativo.
  - `CAIXA NORMALIZADO` (`recoveryTransactionIds`): Receita que restaura o saldo acumulado para `>= 0`.
  - Coluna de saldo acumulado (*Running Balance*) em cada linha da transação.
  - Sparkline diário destacando a zona vermelha abaixo de zero.

### 2.3. Caixinhas de Provisão Anual e Sazonal (Sinking Funds)
- Permite provisionar despesas periódicas (IPVA, IPTU, Seguros, Manutenções, Natal).
- Cada fundo possui: `targetAmount`, `recurrenceMonths` (ex: 12 meses para anuais), `dueMonth` e `dueYear`.
- **Rateio Proporcional Automático:** `monthlyContribution = targetAmount / recurrenceMonths`.
- A soma mensal de todas as caixinhas ativas é incorporada automaticamente à provisão restante do mês no cálculo do orçamento consolidado.

### 2.4. Empréstimos, Financiamentos e Amortizações Extraordinárias
- **Sistemas de Amortização Suportados:**
  - **SAC:** Amortização do principal constante, juros e parcelas decrescentes.
  - **PRICE:** Parcelas fixas constantes, juros decrescentes e amortização crescente.
- **Marco Inicial Retroativo Sem Poluição de Histórico:**
  - O contrato armazena `startDate` e `pastInstallmentsElapsedAtCreation`.
  - Parcelas passadas **não** são geradas como transações no extrato histórico; são criadas transações agendadas apenas a partir da data de criação/referência no sistema.
- **Planejamento de Amortização em 3 Camadas:**
  - *Camada 1 (Contratual):* Parcelas normais do contrato.
  - *Camada 2 (Projetada / Simulação Ativa):* `AmortizationPlan` com aportes extraordinários planejados, reduzindo prazo ou valor de prestação e sombreando parcelas projetadas expiradas.
  - *Camada 3 (Efetivada):* `AmortizationRecord` — quitação parcial ou total com saída real de caixa da conta bancária selecionada.

### 2.5. Motor de Decisão e Cenários "E Se?" (Read-Only)
- Localizado em `DecisionAndScenarioEngine.swift`.
- **Garantia de Não Mutação:** Toda simulação opera sobre cópias em memória ou projeções matemáticas puras; nunca altera contas, transações ou contratos do usuário.
- **Comparador Amortizar vs. Investir:**
  - Confronta o custo efetivo total da dívida contra o rendimento líquido de investimentos referenciados ao CDI/Selic (descontando imposto de renda regressivo).
- **Teste de Estresse de Caixa:**
  - Simula redução percentual de receitas variáveis e impacto de despesas extraordinárias em meses futuros.
  - Mapeia meses deficitários e lista mitigações práticas automáticas.

### 2.6. Central de Insights e Motor de Machine Learning Comportamental
- Localizado em `BehavioralMLInsightsEngine.swift` e `InsightsCenterView.swift`.
- **Treinamento 100% Local:** Sem envio de dados confidenciais para servidores externos.
- **Quatro Detectores Inteligentes:**
  1. *Inflação Pessoal:* Compara os gastos médios dos últimos 3 meses fechados contra os 2 meses anteriores em cada categoria.
  2. *Assinaturas e Recorrências Ocultas:* Identifica desvios e reajustes silenciosos de serviços recorrentes.
  3. *Anomalias de Consumo:* Detecta compras fora da curva usando cálculo de Z-score sobre a mediana/IQR do usuário.
  4. *Risco de Caixa Intramês Contextual:* Varre o mês corrente e os 2 meses futuros emitindo alertas `.critical` (para `.confirmedDeficit`) e `.warning` (para `.possibleRisk`), limpando alertas pendentes obsoletos caso o usuário regularize o caixa.
- **Fechamento Mensal Guiado (`MonthlyReview`):** Gera diagnóstico de aderência ao orçamento do mês anterior, com desvios e notas personalizadas.
- **Ciclo de Retroalimentação (Feedback Loop):** O usuário pode classificar o insight como `useful`, `irrelevant`, etc., ajustando a sensibilidade do perfil ML.

### 2.7. Assistente de IA Local e Ferramentas (Tool Calling)
- Opera via `LocalLLMService.swift` e `AIChatOrchestrator.swift`.
- Suporta modelos GGUF locais via Metal (`llama.cpp`) e integração com Apple Intelligence nativa no macOS 14+ em Apple Silicon.
- **Ferramentas Registradas no `AIToolRegistry`:**
  - `query_database`: Consulta estruturada e irrestrita à base financeira.
  - `saldo_previsto`: Cálculo em tempo real do saldo ao fim do mês ou ano.
  - `simular_prazo_amortizacao`: Projeção de impacto de amortizações extraordinárias em contratos reais.
  - `procurar_taxas_e_noticias_web`: Consulta web sanitizada para indicadores econômicos (Selic, IPCA, TR).
- **Importação de Extratos com IA Local:**
  - `StatementImportService.swift` lê PDFs e extratos bancários, aplicando LLM local com prompt estruturado para extrair transações sem enviar dados à nuvem.

### 2.8. Sincronização Cloud Two-Way e Offline-First
- Localizado em `CloudSyncService.swift`.
- Mutações locais são gravadas atomicamente numa fila de mutações (`MutationJournal`).
- Resolução de conflitos *Last-Write-Wins* (LWW) com controle de versão monótona do usuário.
- **Verificação Leve de Status (`/api/v1/sync/status`):** Consulta ultra-rápida (<5ms) com ETag e revisão de servidor para saber se há atualizações na nuvem sem onerar a rede ou travar o app, atualizando o ícone de sincronização na barra superior.
- **Exportação e Importação de Dados:** Suporta backup completo em JSON (`.json`) e pacotes comprimidos (`.fcbackup`), incluindo `reconciliationRules`, `assetItems`, `incomeSources`, `netWorthSnapshots` e `fireScenarios`, mantendo 100% de compatibilidade retroativa com backups legados.

### 2.9. Quick-Add Global, Regras Determinísticas & Revisão Apple Pay
- **Barra Rápida Global (Feature 2):** `MenuBarExtra` + atalho global (`Ctrl+Espaço` / `⌃Space` via `GlobalHotKeyManager.swift`) exibem painel flutuante `QuickAddBarView` interpretado pelo `QuickAddParserService` (suporte a parcelas `Nx`, cartão/conta destino, moeda e reembolsável).
- **Ícones Personalizados de Alta Nitidez (`AccountAvatarImageCache`):** Em [`SharedComponents.swift`](Sources/FinSense/Views/SharedComponents.swift), imagens anexadas de contas/cartões/dívidas são reamostradas com `CILanczosScaleTransform` + cache Retina (`NSCache`) e interpolação `.high` em `AccountAvatarView`, evitando pixelização em avatars pequenos.
- **Motor de Regras Determinístico (Feature 3):** `ReconciliationRulesEngine` avalia regras ativas por prioridade crescente (`contains`, `startsWith`, `equals`, `regex`, faixa de valor e origem) antes do fallback para `LocalLLMService` na importação (`StatementImportService`) e em transações sincronizadas via Apple Pay com `needsReview = true`.
- **Gestão em UI:** Tab `Regras` em Configurações (`ReconciliationRulesView`), filtro `A Revisar` + botão `Aprovar` em `TransactionsView`, e criação de regra em 1 clique a partir de qualquer transação ou linha de extrato.

### 2.10. Patrimônio Líquido (Net Worth), Fontes de Renda & Simulador FIRE
- **Tela Isolada de Patrimônio & Renda (`NetWorthDashboardView`, Sidebar `.netWorth`):** Separada do fluxo de caixa operacional. Consolida liquidez, investimentos, bens não-bancários (`AssetItem`: imóveis com cálculo automático de equity via financiamento vinculado, veículos, FGTS, previdência), passivos e fontes de renda (`IncomeSource`), com snapshots mensais históricos (`NetWorthSnapshot`).
- **Simulador FIRE (`FIRESimulatorView`, em `Decisões & Cenários`):** Read-only usando custo de vida real médio de 6 meses (excluindo amortizações extraordinárias/transferências/parcelas reembolsáveis), consulta BCB Selic/IPCA com equação real de Fisher `(1+nom)/(1+inf)-1`, SWR configurável (default 4%), aceleração por quitação de dívidas e cenários salváveis (`FIREPlanScenario`).

### 2.11. Gestão de Reembolsos ("A Receber") & Multimoeda (Câmbio)
- **Contabilização de Reembolsos (`TransactionOrigin.reimbursementReceipt`):** Despesas marcadas com `isReimbursable = true` debitam **valor integral** da conta bancária ou fatura de cartão, porém tetos orçamentários, `categoryBreakdown`, `monthlyExpense` e KPIs computam **apenas a parcela pessoal não reembolsável**. O submenu `A Receber` (`ReceivablesManagementView`) agrupa valores por devedor e registra recebimentos totais, parciais ou superiores ao previsto sem inflar categorias de Salário/Receita em gráficos; ao finalizar um reembolso com valor menor que o previsto, `reimbursableAmount` é ajustado ao montante efetivamente recebido para que a diferença permaneça contabilizada como gasto próprio do usuário.
- **Multimoeda (`ExchangeRateService`):** `BankAccount`, `InvestmentItem`, `SinkingFund`, `AssetItem`, `IncomeSource` e `FinancialTransaction` suportam moedas estrangeiras (`USD`, `EUR`, `GBP`, `CAD`, `CHF`, `AUD`, `JPY`). Saldos nativos por conta são preservados enquanto consolidações, KPIs e Net Worth convertem automaticamente para BRL com cache em disco (`fx_rates_cache.json`), atualização pública e suporte a taxa manual offline.

### 2.12. Design System & Interface FinSense 2.0 (Bento UI — macOS)
- **Hierarquia de Profundidade & Tokens (`FinSenseTheme` em `SharedComponents.swift`):**
  - Inversão de profundidade no Dark Mode: fundo base da janela/toolbar em Obsidian Profundo (`#0D0D0F`, com `titlebarAppearsTransparent = true` e `.toolbarBackground`), sidebar mais escura (`#0F0F12`, borda divisória `Color.white.opacity(0.06)`), canvas central (`#161618`), cards Bento elevados (`#1E1E22`, borda *hairline* `0.75pt` `Color.white.opacity(0.08)` via `.bentoCard(...)`) e sub-cards neutros (`#18181B`, borda `Color.white.opacity(0.07)`). Light Mode preserva paleta clara equivalente (`#EBEBEF` / `#ECECF0` / `#F5F5F7` / branco).
  - **Regra de Cor 90/10:** 90% neutra; cores semânticas suaves apenas para status (`emerald` `#10B981`, `coral` `#EF4444`, `amber` `#F59E0B`, `indigo` `#6366F1`, `cyan` `#38BDF8`, `slateLight` `#94A3B8`) e 1 CTA primário por tela (`BentoPrimaryButtonStyle`), com botões secundários translúcidos (`BentoGlassButtonStyle`).
  - **Sidebar & Toolbar (`FinSenseApp.swift`):** Menu lateral limpo com grupos espaçados (`18pt` entre grupos, `6pt` entre itens), sem sub-itens fixos abaixo de *Transações* e *Configurações* (que já possuem navegação interna via segmented bar), item ativo em pílula translúcida (`Color.white.opacity(0.08)` + borda `0.5pt`), ícones monocromáticos sutis em inativos (`Color.white.opacity(0.55)`), rodapé compacto com card *Saldo Consolidado* (`#161618`) e botão `Chat IA Local` em índigo escuro/glass (`#4F46E5`), além do indicador `AppleIntelligenceStatusDot` na toolbar.
  - **Tipografia Numérica:** Valores monetários principais usam `SF Pro Rounded` + `.monospacedDigit()` + `.contentTransition(.numericText())` (`.numericCurrencyTransition`).
- **Dashboard & Contraste de Gráficos (`DashboardView.swift`):**
  - Card Hero à esquerda (~42%) destacando *Saldo Previsto*, `IntraMonthSparklineView` luminoso e pílula interativa do Vale Intramês (levando à Linha de Corte em Transações), pareado à grade Bento assimétrica de 5 KPIs à direita (~58%).
  - **Gráfico de Despesas por Categoria (`ExpensesByCategoryCardView`):** Rosca de traço fino (`innerRadius: .ratio(0.74)`) com total centralizado no anel e agrupamento estrito em **Top 5 categorias + 6ª fatia `"Outros"`** em Cinza Ardósia Claro (`#94A3B8`) para alto contraste (com popover expansível ao clicar para visualizar todas as categorias restantes sem barras de rolagem).
  - **Fluxo de Caixa Mensal (`MonthlyCashFlowChartView`) & Compromissos (`DebtCommitmentsDonutChartView`):** Rótulos dos eixos X e Y em cinza neutro (`Color.white.opacity(0.55)`), linha e pontos `Saldo Final` em Ciano Luminoso (`#38BDF8`, `2.5pt`), e sub-cards de compromissos separados (`10pt`) em superfície neutra `#18181B` com cor temática restrita ao ícone e à barra de progresso.
- **Cockpits de Contratos & Transações:**
  - `LoansAndFinancingsView` e `DebtsView` utilizam cockpits com destaque de Saldo Presente para Quitação Hoje (PV), barra segmentada com indicador de projeção e *progressive disclosure* (`Detalhes Técnicos & Memória` em popover).
  - `TransactionsView` exibe divisor horizontal fino coral com pílula para a Linha de Corte, faixa lateral sutil na zona de déficit e botões contextuais de linha revelados apenas no `onHover` em slot fixo sem deslocar colunas de valor.

---

## 3. Guia de Arquivos e Estrutura de Código

| Componente | Caminho do Arquivo | Responsabilidade Principal |
| :--- | :--- | :--- |
| Store Principal | `Sources/FinSense/Services/FinancialDataStore.swift` | CRUD de entidades, persistência em disco, cache derivado |
| Insights & Cenários | `Sources/FinSense/Services/FinancialDataStore+PlanningAndInsights.swift` | Orquestração de provisões, caixinhas, insights e cenários |
| Motor Intramês | `Sources/FinSense/Services/IntraMonthCashFlowEngine.swift` | Cálculo cronológico dia a dia e identificação de corte/recuperação |
| Modelos de Planejamento | `Sources/FinSense/Models/PlanningAndInsightsModels.swift` | Structs do Vale Intramês, Sinking Funds, Insights e Cenários |
| Design System FinSense 2.0 | `Sources/FinSense/Views/SharedComponents.swift` | Tokens `FinSenseTheme`, modificador `.bentoCard`, estilos de botão e cards KPI |
| Extrato Desktop | `Sources/FinSense/Views/TransactionsView.swift` | Listagem mensal, filtros nativos, divisor de corte e ações no hover |
| Dashboard Desktop | `Sources/FinSense/Views/DashboardView.swift` | Visão Bento executiva com card Hero, 5 KPIs e rosca Top 5 + Outros |
| Motor de Cartões | `Sources/FinSense/Services/CreditCardEngine.swift` | Distribuição de compras por fatura, melhor dia e parcelamento |

---

## 4. Instruções de Build e Execução de Testes

```bash
# Compilar o aplicativo desktop
swift build

# Rodar a suíte completa de testes de planejamento e vale intramês
swift test --filter PlanningInsightsAndIntraMonthTests

# Rodar testes do Super Agente de IA
swift test --filter AIChatOrchestratorTests

# Rodar testes de Cartão de Crédito
swift test --filter CreditCardTests

# Rodar testes de Sincronização e Autenticação
swift test --filter CloudSyncAndAuthTests

# Rodar testes da Evolução FinSense (Quick-Add, Regras, Net Worth, FIRE, Reembolsos, Multimoeda)
swift test --filter EvolutionFeaturesTests
```
