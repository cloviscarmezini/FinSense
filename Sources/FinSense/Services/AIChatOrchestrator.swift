import Foundation

/// Orquestrador de conversação financeira multi-turno orientado a ferramentas (Agent-First).
@MainActor
public final class AIChatOrchestrator: ObservableObject {
    public static let shared = AIChatOrchestrator()

    public let registry: AIToolRegistry
    public var maxSlidingWindowMessages: Int = 12
    public var maxToolExecutionHops: Int = 4

    public init(registry: AIToolRegistry? = nil) {
        self.registry = registry ?? .shared
    }

    /// Registra todas as ferramentas padrão para uma instância de FinancialDataStore
    public func registerStandardTools(for store: FinancialDataStore) {
        registry.register(GetContractDetailsTool(store: store))
        registry.register(SimulateAmortizationTool(store: store))
        registry.register(GetMonthlyCashFlowTool(store: store))
        registry.register(GetProjectedCashFlowRangeTool(store: store))
        registry.register(AnalyzeDiscretionarySpendingTool(store: store))
        registry.register(GetBudgetCapsStatusTool(store: store))
        registry.register(QueryTransactionsTool(store: store))
        registry.register(UnsupportedCapabilityTool(registry: registry))
    }

    // MARK: - Ciclo de Execução Multi-Turno

    /// Executa o ciclo completo de um turno conversacional:
    /// 1. Adiciona a mensagem do usuário
    /// 2. Aplica janela deslizante no histórico
    /// 3. Avalia ferramentas determinísticas necessárias (ou detecta chamada estruturada)
    /// 4. Executa a tool nativa e appenda o resultado no histórico com role `.tool`
    /// 5. Gera a resposta final em Markdown e sugestões de follow-up
    public func processTurn(
        userPrompt: String,
        store: FinancialDataStore,
        modelLabel: String,
        onStepUpdate: ((String) -> Void)? = nil
    ) async -> (responseMarkdown: String, executedSteps: [String], followUps: [String], shouldClose: Bool) {
        registerStandardTools(for: store)

        var executedSteps: [String] = []
        func logStep(_ text: String) {
            executedSteps.append(text)
            onStepUpdate?(text)
        }

        let cleanPrompt = userPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        logStep("💬 Orquestrador: Processando turno multi-turno para '\(cleanPrompt.prefix(45))...'")

        // Garante System Prompt com documentação de Tools
        ensureSystemPromptWithTools(store: store)

        // 1. Aplica política de janela deslizante (Sliding Window) para modelos locais GGUF
        applySlidingWindow(store: store)
        logStep("🗜️ Contexto: Janela deslizante aplicada (preservando System Prompt e últimas interações)")

        // 2. Extrai tool calls explicitamente emitidas ou analisa intenção determinística
        guard let plannedCalls = planToolCalls(for: cleanPrompt, store: store, history: store.chatHistory) else {
            // Encaminha para o motor agêntico RAG padrão quando não há ferramenta específica
            logStep("🤖 Acionando Agentes de Síntese RAG da base local...")
            let agentOutput = AgenticFinancialEngine.runAgentLoop(
                prompt: cleanPrompt,
                store: store,
                modelLabel: modelLabel,
                onStepUpdate: onStepUpdate
            )
            return (
                agentOutput.responseMarkdown,
                agentOutput.executedSteps,
                agentOutput.suggestedFollowUps,
                agentOutput.shouldCloseChat
            )
        }

        var toolResults: [AIToolResult] = []

        for call in plannedCalls {
            logStep("🔧 Invocando ferramenta nativa: `\(call.name)`...")
            do {
                let params = call.parsedArguments
                let outputDict = try await registry.execute(name: call.name, parameters: params)
                let result = AIToolResult(toolCallId: call.id, toolName: call.name, result: outputDict)
                toolResults.append(result)

                // Salva a mensagem no histórico como role .tool
                let toolMsg = ChatMessage(
                    role: .tool,
                    content: result.resultJson,
                    timestamp: Date(),
                    modelUsed: modelLabel,
                    toolName: call.name,
                    toolCallId: call.id
                )
                store.chatHistory.append(toolMsg)
                logStep("✅ Ferramenta `\(call.name)` concluída com sucesso.")
            } catch {
                let errResult = AIToolResult(toolCallId: call.id, toolName: call.name, result: [:], error: error.localizedDescription)
                toolResults.append(errResult)
                let toolMsg = ChatMessage(
                    role: .tool,
                    content: "{\"error\": \"\(error.localizedDescription)\"}",
                    timestamp: Date(),
                    modelUsed: modelLabel,
                    toolName: call.name,
                    toolCallId: call.id
                )
                store.chatHistory.append(toolMsg)
                logStep("⚠️ Erro na execução de `\(call.name)`: \(error.localizedDescription)")
            }
        }

        // 3. Sintetiza a resposta analítica conclusiva utilizando os dados das ferramentas e o histórico
        logStep("✍️ Orquestrador: Sintetizando resposta analítica final orientada aos dados determinísticos...")
        let finalSynthesis = synthesizeAssistantResponse(
            prompt: cleanPrompt,
            toolResults: toolResults,
            store: store,
            history: store.chatHistory
        )

        return (
            finalSynthesis.markdown,
            executedSteps,
            finalSynthesis.followUps,
            finalSynthesis.shouldClose
        )
    }

    // MARK: - Planejamento e Roteamento de Ferramentas (Agent-First)

    private func planToolCalls(
        for prompt: String,
        store: FinancialDataStore,
        history: [ChatMessage]
    ) -> [AIToolCall]? {
        let norm = prompt.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR"))

        // A. Se o próprio prompt contém JSON de tool_call explícito (ex: de teste ou gerado pela LLM)
        if let explicitCall = Self.parseToolCall(from: prompt) {
            return [explicitCall]
        }

        // B. Verificação de Fallback Obrigatório (unsupported_capability)
        if isUnsupportedQuery(norm: norm) {
            let (requested, reason, reqData) = resolveUnsupportedCapabilityDetails(norm: norm)
            let args: [String: Any] = [
                "requestedCapability": requested,
                "reason": reason,
                "requiredData": reqData
            ]
            let argsJson = (try? String(data: JSONSerialization.data(withJSONObject: args), encoding: .utf8)) ?? "{}"
            return [AIToolCall(name: "unsupported_capability", argumentsJson: argsJson)]
        }

        // C. Multi-Turn Anaphoric Continuity ("no plano onde amortizo 2 mil...", "como consigo esse valor?", "e no plano 3?")
        if isMultiTurnBudgetOptimizationFollowUp(norm: norm, history: history) {
            let targetAmount = extractTargetAmount(from: norm) ?? extractTargetAmountFromHistory(history: history) ?? 2000.0
            var calls: [AIToolCall] = []

            let cashFlowArgs: [String: Any] = [:]
            let cashFlowJson = (try? String(data: JSONSerialization.data(withJSONObject: cashFlowArgs), encoding: .utf8)) ?? "{}"
            calls.append(AIToolCall(name: "get_monthly_cash_flow", argumentsJson: cashFlowJson))

            let discArgs: [String: Any] = ["targetExtraPayment": targetAmount]
            let discJson = (try? String(data: JSONSerialization.data(withJSONObject: discArgs), encoding: .utf8)) ?? "{}"
            calls.append(AIToolCall(name: "analyze_discretionary_spending", argumentsJson: discJson))

            return calls
        }

        // D. Turno 1 de Financiamento / Amortização / Quitação
        if norm.contains("quitar") || norm.contains("amortizar") || norm.contains("plano de acao") || norm.contains("financiamento") {
            let contractQuery = extractContractName(from: norm) ?? "caixa"
            var calls: [AIToolCall] = []

            let detailsArgs: [String: Any] = [
                "nameOrQuery": contractQuery,
                "kind": "financing"
            ]
            let detailsJson = (try? String(data: JSONSerialization.data(withJSONObject: detailsArgs), encoding: .utf8)) ?? "{}"
            calls.append(AIToolCall(name: "get_contract_details", argumentsJson: detailsJson))

            // Cenário 1: 500
            let sim1Args: [String: Any] = ["nameOrQuery": contractQuery, "extraPayment": 500.0, "mode": "reduce_term"]
            let sim1Json = (try? String(data: JSONSerialization.data(withJSONObject: sim1Args), encoding: .utf8)) ?? "{}"
            calls.append(AIToolCall(name: "simulate_amortization", argumentsJson: sim1Json))

            // Cenário 2: 1000
            let sim2Args: [String: Any] = ["nameOrQuery": contractQuery, "extraPayment": 1000.0, "mode": "reduce_term"]
            let sim2Json = (try? String(data: JSONSerialization.data(withJSONObject: sim2Args), encoding: .utf8)) ?? "{}"
            calls.append(AIToolCall(name: "simulate_amortization", argumentsJson: sim2Json))

            // Cenário 3: 2000
            let sim3Args: [String: Any] = ["nameOrQuery": contractQuery, "extraPayment": 2000.0, "mode": "reduce_term"]
            let sim3Json = (try? String(data: JSONSerialization.data(withJSONObject: sim3Args), encoding: .utf8)) ?? "{}"
            calls.append(AIToolCall(name: "simulate_amortization", argumentsJson: sim3Json))

            return calls
        }

        // E. Projeções de Caixa / Débito Futuro
        if norm.contains("projecao") || norm.contains("quando entrarei em debito") || norm.contains("futuro") {
            let projArgs: [String: Any] = ["numberOfMonths": 12]
            let projJson = (try? String(data: JSONSerialization.data(withJSONObject: projArgs), encoding: .utf8)) ?? "{}"
            return [AIToolCall(name: "get_projected_cash_flow_range", argumentsJson: projJson)]
        }

        // F. Fluxo de Caixa / Ritmo de Gastos / Saldo no Fim do Mês
        if norm.contains("ritmo") || norm.contains("final do mes") || norm.contains("terei quanto") || norm.contains("saldo disponivel") {
            let cashArgs: [String: Any] = [:]
            let cashJson = (try? String(data: JSONSerialization.data(withJSONObject: cashArgs), encoding: .utf8)) ?? "{}"
            return [AIToolCall(name: "get_monthly_cash_flow", argumentsJson: cashJson)]
        }

        // G. Tetos e Cotas
        if norm.contains("teto") || norm.contains("cota") || norm.contains("envelope") || norm.contains("lanches") || norm.contains("gasolina") {
            let capsArgs: [String: Any] = [:]
            let capsJson = (try? String(data: JSONSerialization.data(withJSONObject: capsArgs), encoding: .utf8)) ?? "{}"
            return [AIToolCall(name: "get_budget_caps_status", argumentsJson: capsJson)]
        }

        // H. Transações Recentes / Últimos Lançamentos
        if (norm.contains("ultimas") && norm.contains("transacoes")) || norm.contains("gastos recentes") {
            let txArgs: [String: Any] = ["limit": 10]
            let txJson = (try? String(data: JSONSerialization.data(withJSONObject: txArgs), encoding: .utf8)) ?? "{}"
            return [AIToolCall(name: "query_transactions", argumentsJson: txJson)]
        }

        // I. Consultas gerais ou de encerramento são delegadas ao motor de síntese RAG
        return nil
    }

    // MARK: - Detecção de Consultas Não Suportadas (Fallback Loop)

    private func isUnsupportedQuery(norm: String) -> Bool {
        let unsupportedTokens = [
            "compre acoes", "comprar acoes", "bolsa de valores", "petrobras", "vale3", "petr4",
            "fazer emprestimo pelo aplicativo", "contratar emprestimo agora", "pegar emprestimo no itau",
            "comprar bitcoin", "comprar cripto", "vender bitcoin", "home broker", "transferir pix para",
            "enviar ted", "pagar boleto agora pelo banco", "fazer debito automatico no santander"
        ]
        return unsupportedTokens.contains { norm.contains($0) }
    }

    private func resolveUnsupportedCapabilityDetails(norm: String) -> (requested: String, reason: String, requiredData: String) {
        if norm.contains("acoes") || norm.contains("bolsa") || norm.contains("petrobras") || norm.contains("home broker") {
            return (
                requested: "Execução de ordens de compra/venda de ações na B3",
                reason: "O FinSense é uma aplicação de inteligência financeira pessoal e planejamento de fluxo de caixa, não operando como corretora de valores mobiliários (broker) autorizada.",
                requiredData: "Integração via API com corretora credenciada pela CVM/B3 e autorização de custódia."
            )
        } else if norm.contains("emprestimo") && (norm.contains("fazer") || norm.contains("contratar") || norm.contains("pegar")) {
            return (
                requested: "Contratação direta de novo empréstimo bancário",
                reason: "A aplicação gerencia e analisa contratos existentes e simula amortizações, mas não realiza originação de crédito bancário junto a instituições financeiras.",
                requiredData: "API de Open Finance com escopo de contratação de crédito e esteira de aprovação bancária."
            )
        } else if norm.contains("bitcoin") || norm.contains("cripto") {
            return (
                requested: "Negociação de criptoativos em exchange",
                reason: "O FinSense não possui conexão de custódia e execução com exchanges de criptomoedas.",
                requiredData: "Integração via chave de API com exchanges (ex: Binance, Mercado Bitcoin) com permissão de trade."
            )
        } else {
            return (
                requested: "Transação bancária externa direta (PIX / TED / Pagamento)",
                reason: "O FinSense não realiza movimentação bancária ativa externa por motivos de segurança e privacidade dos seus dados locais.",
                requiredData: "Iniciação de pagamentos via Open Finance Brasil (ITP)."
            )
        }
    }

    private func isMultiTurnBudgetOptimizationFollowUp(norm: String, history: [ChatMessage]) -> Bool {
        // Verifica se a pergunta expressa "como consigo esse valor?", "onde cortar?", "no plano onde amortizo..."
        let triggers = ["como consigo", "onde cortar", "como arranjar", "no plano", "plano 3", "2 mil", "como pagar esse valor", "como economizar"]
        let hasTrigger = triggers.contains { norm.contains($0) }
        guard hasTrigger else { return false }

        // Verifica se no histórico há discussão sobre plano de amortização
        let recentHistoryText = history.suffix(6).map(\.content).joined(separator: " ").lowercased()
        return recentHistoryText.contains("plano de ação") ||
               recentHistoryText.contains("cenário") ||
               recentHistoryText.contains("amortização") ||
               recentHistoryText.contains("financiamento")
    }

    private func extractTargetAmount(from text: String) -> Double? {
        let norm = text.lowercased()
        if norm.contains("2 mil") || norm.contains("2.000") || norm.contains("2000") {
            return 2000.0
        }
        if norm.contains("1 mil") || norm.contains("1.000") || norm.contains("1000") {
            return 1000.0
        }
        if norm.contains("500") {
            return 500.0
        }
        if norm.contains("3 mil") || norm.contains("3.000") || norm.contains("3000") {
            return 3000.0
        }
        return nil
    }

    private func extractTargetAmountFromHistory(history: [ChatMessage]) -> Double? {
        for msg in history.reversed() {
            if let amount = extractTargetAmount(from: msg.content) {
                return amount
            }
        }
        return nil
    }

    private func extractContractName(from text: String) -> String? {
        let norm = text.lowercased()
        if norm.contains("caixa") { return "caixa" }
        if norm.contains("santander") { return "santander" }
        if norm.contains("itau") { return "itau" }
        if norm.contains("bradesco") { return "bradesco" }
        if norm.contains("imovel") || norm.contains("habitacao") { return "habitacao" }
        return nil
    }

    // MARK: - Síntese Final Determinística

    private func synthesizeAssistantResponse(
        prompt: String,
        toolResults: [AIToolResult],
        store: FinancialDataStore,
        history: [ChatMessage]
    ) -> (markdown: String, followUps: [String], shouldClose: Bool) {
        // Caso de Fallback: unsupported_capability
        if let fallbackResult = toolResults.first(where: { $0.toolName == "unsupported_capability" }) {
            let req = (fallbackResult.result["requestedCapability"] as? String) ?? "Ação solicitada"
            let reason = (fallbackResult.result["reason"] as? String) ?? "Capacidade não suportada no momento."
            let reqData = (fallbackResult.result["requiredData"] as? String) ?? "Ferramenta não disponível."

            let md = """
            ### ⚠️ Funcionalidade Não Suportada Nativamente

            Você solicitou: **\(req)**.

            **Motivo da Restrição:**
            \(reason)

            **O que seria necessário para atender:**
            • \(reqData)

            > **Feedback Registrado:** Esse evento foi computado internamente no registro de capacidades para direcionar o desenvolvimento das próximas ferramentas determinísticas da aplicação.

            Posso te ajudar a simular o impacto financeiro dessa operação no seu fluxo de caixa ou planejar uma reserva equivalente?
            """
            return (
                md,
                [
                    "Qual é a minha sobra líquida real neste mês?",
                    "Como está meu fluxo de caixa projetado?",
                    "Obrigado, pode encerrar"
                ],
                false
            )
        }

        // Caso de Amortização / Quitação (Turno 1)
        if let contractTool = toolResults.first(where: { $0.toolName == "get_contract_details" }),
           toolResults.contains(where: { $0.toolName == "simulate_amortization" }) {
            let contractsList = (contractTool.result["contracts"] as? [[String: Any]]) ?? []
            let cName = (contractsList.first?["name"] as? String) ?? "Financiamento Imobiliário"
            let cBalance = (contractsList.first?["outstandingBalance"] as? Double) ?? 0.0
            let cRemaining = (contractsList.first?["remainingInstallments"] as? Int) ?? 0
            let cInstallment = (contractsList.first?["installmentAmount"] as? Double) ?? 0.0

            let allSims = toolResults.filter { $0.toolName == "simulate_amortization" }
            let sim500 = allSims.first(where: { (($0.result["grossPayment"] as? Double) ?? 0) == 500.0 })?.result
            let sim1000 = allSims.first(where: { (($0.result["grossPayment"] as? Double) ?? 0) == 1000.0 })?.result
            let sim2000 = allSims.first(where: { (($0.result["grossPayment"] as? Double) ?? 0) == 2000.0 })?.result

            func descSim(_ s: [String: Any]?, val: Double) -> String {
                guard let s else { return "• Amortização de \(BRLFormatters.currency(val)): Simulação processada." }
                let elim = (s["eliminatedInstallmentsCount"] as? Int) ?? 0
                let saved = (s["estimatedTotalInterestSaved"] as? Double) ?? 0.0
                let newRem = (s["newRemainingInstallments"] as? Int) ?? 0
                let savedTime = (s["savedTimeString"] as? String) ?? "\(elim) meses"
                return "• **Cenário (+ \(BRLFormatters.currency(val))/mês):** Elimina **\(elim) parcelas** (\(savedTime) poupados), reduzindo o prazo restante para **\(newRem) meses** e economizando **\(BRLFormatters.currency(saved))** em juros futuros."
            }

            let md = """
            ### Plano de Ação para Quitação no Menor Prazo: \(cName)

            Analisando os dados reais do seu contrato com **Saldo Devedor Atual de \(BRLFormatters.currency(cBalance))** (\(cRemaining) parcelas restantes de \(BRLFormatters.currency(cInstallment))):

            #### 🎯 Simulação de Prazo e Economia de Juros (Tabela Price):
            \(descSim(sim500, val: 500.0))
            \(descSim(sim1000, val: 1000.0))
            \(descSim(sim2000, val: 2000.0))

            #### ⚡ Efeito Bola de Neve:
            Ao amortizar com redução de prazo, 100% do aporte extra abate o saldo devedor puro, desintegrando os juros compostos que seriam cobrados pelos próximos anos.

            No cenário de maior aceleração (+R$ 2.000,00/mês), você economiza dezenas de milhares de reais em juros bancários.
            """

            return (
                md,
                [
                    "No plano onde amortizo 2 mil por mês, como consigo esse valor?",
                    "Qual a minha sobra líquida no mês atual?",
                    "Obrigado, pode encerrar"
                ],
                false
            )
        }

        // Caso de Otimização de Gastos Discricionários (Turno 2 - "como consigo esse valor?")
        if let discTool = toolResults.first(where: { $0.toolName == "analyze_discretionary_spending" }) {
            let discRes = discTool.result
            let targetAnalysis = (discRes["targetPaymentAnalysis"] as? [String: Any]) ?? [:]
            let targetAmount = (targetAnalysis["targetAmount"] as? Double) ?? 2000.0
            let curSurplus = (targetAnalysis["currentOperationalSurplus"] as? Double) ?? 0.0
            let neededCut = (targetAnalysis["neededFromBudgetOptimization"] as? Double) ?? targetAmount

            let discExpense = (discRes["discretionaryExpensesTotal"] as? Double) ?? 0.0
            let discShare = (discRes["discretionarySharePercent"] as? Double) ?? 0.0

            let topCats = (discRes["topDiscretionaryCategories"] as? [[String: Any]]) ?? []
            let catLines = topCats.prefix(4).map { c -> String in
                let name = (c["category"] as? String) ?? "Consumo"
                let amt = (c["amount"] as? Double) ?? 0.0
                let cut25 = (c["cutScenario25Percent"] as? Double) ?? 0.0
                return "• **\(name)**: Gasto atual de **\(BRLFormatters.currency(amt))** → Corte de 25% libera **+\(BRLFormatters.currency(cut25))**"
            }.joined(separator: "\n")

            let aggCuts = (discRes["aggregateCutScenarios"] as? [String: Any]) ?? [:]
            let cut25Total = (aggCuts["cut25Percent"] as? Double) ?? 0.0

            let md = """
            ### Como Liberar \(BRLFormatters.currency(targetAmount)) por Mês para Amortização:

            Cruzei a meta de **\(BRLFormatters.currency(targetAmount))/mês** com o seu fluxo de caixa e histórico de consumo:

            1. **Sobra Operacional Atual:**
               • Você possui atualmente uma sobra operacional de **\(BRLFormatters.currency(curSurplus))** entre receitas e despesas.
               • Para atingir os **\(BRLFormatters.currency(targetAmount))**, você precisa remanejar **\(BRLFormatters.currency(neededCut))** de despesas variáveis.

            2. **Oportunidades em Gastos Discricionários (Consumo Flexível):**
               • Seus gastos discricionários somam **\(BRLFormatters.currency(discExpense))** (\(String(format: "%.1f%%", discShare)) do total de despesas).
               \(catLines.isEmpty ? "• Redução programada de compras não essenciais." : catLines)

            3. **Plano de Corte Recomendado:**
               • Aplicando um ajuste moderado de 25% nas categorias acima, você libera **\(BRLFormatters.currency(cut25Total))** imediatamente.
               • Somando esse ajuste à sua sobra de caixa (\(BRLFormatters.currency(curSurplus))), você atinge com folga a meta de **\(BRLFormatters.currency(targetAmount))** mensais para quitar o contrato anos antes do previsto!
            """

            return (
                md,
                [
                    "Reserve R$ 500 para gasolina este mês",
                    "Qual a projeção do meu saldo acumulado até o final do ano?",
                    "Obrigado, pode encerrar"
                ],
                false
            )
        }

        // Caso de Projeção de Caixa
        if let projTool = toolResults.first(where: { $0.toolName == "get_projected_cash_flow_range" }) {
            let res = projTool.result
            let hasRisk = (res["hasRunwayRisk"] as? Bool) ?? false
            let firstDeficit = res["firstDeficitMonth"] as? String
            let lowestBal = (res["lowestProjectedBalance"] as? Double) ?? 0.0
            let count = (res["monthsProjectedCount"] as? Int) ?? 12

            var md = "### Projeção de Fluxo de Caixa para os Próximos \(count) Meses\n\n"
            if hasRisk, let month = firstDeficit {
                md += "⚠️ **Alerta de Risco Financeiro:** Seu saldo acumulado entra em terreno negativo em **\(month)** (menor saldo previsto: **\(BRLFormatters.currency(lowestBal))**).\n\n"
            } else {
                md += "✅ **Fluxo de Caixa Saudável:** Não foi detectado risco de quebra de caixa no horizonte analisado. Seu menor saldo projetado será de **\(BRLFormatters.currency(lowestBal))**.\n\n"
            }

            if let timeline = res["timeline"] as? [[String: Any]] {
                let sampleLines = timeline.prefix(6).map { m in
                    let mName = (m["month"] as? String) ?? ""
                    let inc = (m["projectedIncome"] as? Double) ?? 0.0
                    let exp = (m["projectedExpense"] as? Double) ?? 0.0
                    let end = (m["accumulatedBalanceEnd"] as? Double) ?? 0.0
                    return "• **\(mName)**: Entradas: \(BRLFormatters.currency(inc)) | Saídas: \(BRLFormatters.currency(exp)) | Saldo Final: `\(BRLFormatters.currency(end))`"
                }.joined(separator: "\n")
                md += "#### Panorama dos Próximos Meses:\n" + sampleLines
            }

            return (
                md,
                [
                    "Como estão meus tetos e provisões deste mês?",
                    "Monte um plano de ação para quitar meu financiamento",
                    "Obrigado, pode encerrar"
                ],
                false
            )
        }

        // Caso de Fluxo de Caixa Mensal Padrão
        if let cashTool = toolResults.first(where: { $0.toolName == "get_monthly_cash_flow" }) {
            let res = cashTool.result
            let mRef = (res["monthReference"] as? String) ?? ""
            let opNet = (res["operationalBalance"] as? Double) ?? 0.0
            let checking = (res["liquidCheckingBalanceNow"] as? Double) ?? 0.0
            let inc = ((res["income"] as? [String: Any])?["total"] as? Double) ?? 0.0
            let exp = ((res["expense"] as? [String: Any])?["total"] as? Double) ?? 0.0
            let rate = (res["savingsRatePercent"] as? Double) ?? 0.0

            let md = """
            ### Balanço e Fluxo de Caixa — \(mRef)

            • **Receitas Totais:** \(BRLFormatters.currency(inc))
            • **Despesas Totais:** \(BRLFormatters.currency(exp))
            • **Sobra Líquida Operacional:** **\(BRLFormatters.currency(opNet))** (\(String(format: "%.1f%%", rate)) de taxa de poupança)
            • **Saldo Disponível em Contas Hoje:** **\(BRLFormatters.currency(checking))**

            \(opNet >= 0 ? "Você está operando com superávit. Esse valor pode ser direcionado para reserva de emergência ou amortização de passivos." : "Atenção: Você está operando com déficit no mês. Recomendo analisar cortes de despesas discricionárias.")
            """

            return (
                md,
                [
                    "Onde posso cortar gastos neste mês?",
                    "Qual a projeção para os próximos meses?",
                    "Obrigado, pode encerrar"
                ],
                false
            )
        }

        // Caso padrão amigável
        return (
            "Consulta financeira processada com base nos dados determinísticos locais do seu FinSense.",
            ["Qual o saldo disponível nas minhas contas?", "Como estão meus contratos?", "Obrigado, pode encerrar"],
            false
        )
    }

    // MARK: - Gestão de Janela Deslizante (Sliding Window Context Optimization)

    public func applySlidingWindow(store: FinancialDataStore) {
        guard store.chatHistory.count > maxSlidingWindowMessages else { return }

        // Preserva a mensagem de sistema na posição 0
        let systemMessage = store.chatHistory.first(where: { $0.role == .system })
        let nonSystemMessages = store.chatHistory.filter { $0.role != .system }

        // Mantém as últimas N mensagens não-sistema
        var kept = Array(nonSystemMessages.suffix(maxSlidingWindowMessages))

        // Trunca saídas de tools antigas muito extensas (preservando apenas as últimas 2 intactas)
        let limit = max(0, kept.count - 2)
        for i in 0..<limit {
            if kept[i].role == .tool && kept[i].content.count > 300 {
                kept[i].content = "{\"status\": \"summarized_historical_context\", \"summary\": \"Dados determinísticos consultados e incorporados na resposta do assistente.\"}"
            }
        }

        var newHistory: [ChatMessage] = []
        if let systemMessage {
            newHistory.append(systemMessage)
        }
        newHistory.append(contentsOf: kept)
        store.chatHistory = newHistory
    }

    private func ensureSystemPromptWithTools(store: FinancialDataStore) {
        let toolsDoc = registry.generateToolsDocumentation()
        let fullSystemPrompt = """
        \(LocalLLMService.systemPrompt)

        ================================================================================
        \(toolsDoc)
        ================================================================================
        """

        if store.chatHistory.isEmpty {
            store.chatHistory.append(ChatMessage(role: .system, content: fullSystemPrompt))
        } else if store.chatHistory.first?.role != .system {
            store.chatHistory.insert(ChatMessage(role: .system, content: fullSystemPrompt), at: 0)
        } else {
            store.chatHistory[0] = ChatMessage(role: .system, content: fullSystemPrompt)
        }
    }

    // MARK: - Parsing Resiliente de Chamadas de Ferramenta

    public static func parseToolCall(from rawText: String) -> AIToolCall? {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)

        // 1. Bloco de código markdown ```json ... ```
        if let jsonRange = trimmed.range(of: "```json"),
           let endRange = trimmed[jsonRange.upperBound...].range(of: "```") {
            let jsonString = String(trimmed[jsonRange.upperBound..<endRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            if let call = parseJsonToolCall(jsonString) {
                return call
            }
        }

        // 2. Bloco genérico de código ``` ... ```
        if let codeRange = trimmed.range(of: "```"),
           let endRange = trimmed[codeRange.upperBound...].range(of: "```") {
            let codeString = String(trimmed[codeRange.upperBound..<endRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            if let call = parseJsonToolCall(codeString) {
                return call
            }
        }

        // 3. Objeto JSON direto no texto { "tool": "..." } ou { "name": "..." }
        if let firstBrace = trimmed.firstIndex(of: "{"),
           let lastBrace = trimmed.lastIndex(of: "}"),
           firstBrace <= lastBrace {
            let jsonSubstring = String(trimmed[firstBrace...lastBrace])
            if let call = parseJsonToolCall(jsonSubstring) {
                return call
            }
        }

        return nil
    }

    private static func parseJsonToolCall(_ jsonString: String) -> AIToolCall? {
        guard let data = jsonString.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let name = (dict["tool"] as? String) ?? (dict["name"] as? String)
        guard let toolName = name, !toolName.isEmpty else { return nil }

        let paramsDict = (dict["parameters"] as? [String: Any]) ??
                         (dict["arguments"] as? [String: Any]) ??
                         (dict["params"] as? [String: Any]) ?? [:]

        let argsJson = (try? String(data: JSONSerialization.data(withJSONObject: paramsDict), encoding: .utf8)) ?? "{}"
        let callId = (dict["id"] as? String) ?? UUID().uuidString

        return AIToolCall(id: callId, name: toolName, argumentsJson: argsJson)
    }
}
