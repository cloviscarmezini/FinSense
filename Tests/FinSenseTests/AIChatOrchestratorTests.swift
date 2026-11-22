// Tests/FinSenseTests/AIChatOrchestratorTests.swift
import XCTest
@testable import FinSense

@MainActor
final class AIChatOrchestratorTests: XCTestCase {

    private func createTestStore() -> (FinancialDataStore, URL) {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let store = FinancialDataStore(customDirectory: tempDir)
        return (store, tempDir)
    }

    // MARK: - 1. AIToolRegistry Registration, Schema & Execution Tests

    func testToolRegistrySingleLineRegistrationAndExecution() async throws {
        let (store, tempDir) = createTestStore()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let registry = AIToolRegistry()
        registry.removeAll()

        // Registro em 1 linha de cada ferramenta nativa
        registry.register(GetContractDetailsTool(store: store))
        registry.register(SimulateAmortizationTool(store: store))
        registry.register(GetMonthlyCashFlowTool(store: store))
        registry.register(GetProjectedCashFlowRangeTool(store: store))
        registry.register(AnalyzeDiscretionarySpendingTool(store: store))
        registry.register(GetBudgetCapsStatusTool(store: store))
        registry.register(QueryTransactionsTool(store: store))
        registry.register(UnsupportedCapabilityTool(registry: registry))

        XCTAssertEqual(registry.allTools.count, 8, "Devem haver rigorosamente 8 ferramentas registradas")

        // Validação da documentação dinâmica gerada para o System Prompt
        let docs = registry.generateToolsDocumentation()
        XCTAssertTrue(docs.contains("get_contract_details"))
        XCTAssertTrue(docs.contains("simulate_amortization"))
        XCTAssertTrue(docs.contains("get_monthly_cash_flow"))
        XCTAssertTrue(docs.contains("get_projected_cash_flow_range"))
        XCTAssertTrue(docs.contains("analyze_discretionary_spending"))
        XCTAssertTrue(docs.contains("get_budget_caps_status"))
        XCTAssertTrue(docs.contains("query_transactions"))
        XCTAssertTrue(docs.contains("unsupported_capability"))
        XCTAssertTrue(docs.contains("FALLBACK OBRIGATÓRIO"))

        // Teste de execução direta via registry de get_monthly_cash_flow
        let cashFlowResult = try await registry.execute(name: "get_monthly_cash_flow", parameters: [:])
        XCTAssertEqual(cashFlowResult["status"] as? String, "success")
        XCTAssertNotNil(cashFlowResult["operationalBalance"])

        // Teste de chamada de ferramenta inexistente (ativa o log de fallback)
        let missingToolResult = try await registry.execute(name: "investir_em_cripto", parameters: [:])
        XCTAssertEqual(missingToolResult["status"] as? String, "unsupported")
        XCTAssertEqual(registry.unsupportedCapabilityLogs.count, 1)
        XCTAssertEqual(registry.unsupportedCapabilityLogs.first?.requestedCapability, "investir_em_cripto")
    }

    // MARK: - 2. Multi-Turn Turno 1: Plano de Ação para Financiamento Imobiliário Caixa

    func testTurn1FinancingActionPlanWithCaixaContract() async throws {
        let (store, tempDir) = createTestStore()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Cria contrato habitacional Caixa (Tabela Price padrão SFH/SFI)
        let acc = BankAccount(id: UUID(), name: "Caixa Econômica Federal", initialBalance: 5000.0)
        let cat = CategoryItem(id: UUID(), name: "Habitação", type: .expense, iconSymbol: "house", colorHex: "#0066CC")
        store.accounts.append(acc)
        store.categories.append(cat)

        let contract = CreditContract(
            id: UUID(),
            kind: .financing,
            name: "Financiamento Imobiliário Caixa",
            contractNumber: "1.4444.0674063-2",
            financingSubtype: .imovel,
            amortizationSystem: .price,
            totalContractedAmount: 324737.86,
            outstandingBalance: 324737.86,
            installmentAmount: 2658.04,
            billingDay: 15,
            totalInstallments: 360,
            originalTotalInstallments: 360,
            monthlyInterestRate: 0.7091667,
            startDate: Date(),
            accountId: acc.id,
            categoryId: cat.id,
            pastInstallmentsElapsedAtCreation: 28,
            annualNominalInterestRate: 8.51,
            indexationRate: .tr,
            adminFee: 25.0,
            insuranceFee: 86.27,
            baseInstallmentAmount: 2546.77
        )
        store.contracts.append(contract)

        let orchestrator = AIChatOrchestrator(registry: AIToolRegistry.shared)

        // Usuário inicia Turno 1
        let promptTurn1 = "Monte um plano de ação para eu quitar meu financiamento Caixa no menor prazo possível"
        let outputTurn1 = await orchestrator.processTurn(
            userPrompt: promptTurn1,
            store: store,
            modelLabel: "Qwen 2.5 3B (Local Tool Calling)"
        )

        // 1. Verifica etapas e resposta gerada
        XCTAssertFalse(outputTurn1.executedSteps.isEmpty)
        XCTAssertTrue(outputTurn1.responseMarkdown.contains("Plano de Ação para Quitação no Menor Prazo"))
        XCTAssertTrue(outputTurn1.responseMarkdown.contains("Financiamento Imobiliário Caixa"))
        XCTAssertTrue(outputTurn1.responseMarkdown.contains("Cenário (+ R$ 500,00/mês)"))
        XCTAssertTrue(outputTurn1.responseMarkdown.contains("Cenário (+ R$ 1.000,00/mês)"))
        XCTAssertTrue(outputTurn1.responseMarkdown.contains("Cenário (+ R$ 2.000,00/mês)"))

        // 2. Verifica se as chamadas .tool foram adicionadas ao histórico de mensagens
        let toolMessages = store.chatHistory.filter { $0.role == .tool }
        XCTAssertGreaterThanOrEqual(toolMessages.count, 2, "Histórico deve conter as mensagens das ferramentas com role .tool")
        XCTAssertTrue(toolMessages.contains { $0.toolName == "get_contract_details" })
        XCTAssertTrue(toolMessages.contains { $0.toolName == "simulate_amortization" })

        // 3. Sugestões de follow-up devem conter continuidade para o Turno 2
        XCTAssertTrue(outputTurn1.followUps.contains { $0.contains("2 mil por mês") })
    }

    // MARK: - 3. Multi-Turn Turno 2: Resolução Anafórica e Otimização Orçamentária

    func testTurn2MultiTurnContinuityAndBudgetOptimization() async throws {
        let (store, tempDir) = createTestStore()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Setup de contas e despesas
        let acc = BankAccount(id: UUID(), name: "Conta Corrente", initialBalance: 12000.0)
        let catSalary = CategoryItem(id: UUID(), name: "Salário", type: .income, iconSymbol: "banknote", colorHex: "#00CC00")
        let catMarket = CategoryItem(id: UUID(), name: "Supermercado e Alimentos", type: .expense, iconSymbol: "cart", colorHex: "#FF9900")
        let catDining = CategoryItem(id: UUID(), name: "Restaurantes e Delivery", type: .expense, iconSymbol: "fork.knife", colorHex: "#FF3300")
        let catLeisure = CategoryItem(id: UUID(), name: "Lazer e Assinaturas", type: .expense, iconSymbol: "tv", colorHex: "#9900FF")

        store.accounts.append(acc)
        store.categories.append(contentsOf: [catSalary, catMarket, catDining, catLeisure])

        let curMonth = store.selectedMonth
        store.transactions.append(contentsOf: [
            FinancialTransaction(id: UUID(), name: "Salário Empresa", amount: 16000.0, date: curMonth, type: .income, isPaid: true, categoryId: catSalary.id, accountId: acc.id),
            FinancialTransaction(id: UUID(), name: "Compras Mensais Hipermercado", amount: 3500.0, date: curMonth, type: .expense, isPaid: true, categoryId: catMarket.id, accountId: acc.id),
            FinancialTransaction(id: UUID(), name: "Jantares e Delivery iFood", amount: 1800.0, date: curMonth, type: .expense, isPaid: true, categoryId: catDining.id, accountId: acc.id),
            FinancialTransaction(id: UUID(), name: "Cinema, Streaming e Jogos", amount: 1200.0, date: curMonth, type: .expense, isPaid: true, categoryId: catLeisure.id, accountId: acc.id)
        ])

        // Simula histórico pré-existente do Turno 1 no store
        store.chatHistory.append(ChatMessage(role: .system, content: "FinSense Local System Prompt"))
        store.chatHistory.append(ChatMessage(role: .user, content: "Monte um plano de ação para amortizar meu financiamento"))
        store.chatHistory.append(ChatMessage(role: .assistant, content: "No cenário agressivo de +R$ 2.000,00/mês você elimina 15 anos de dívida."))

        let orchestrator = AIChatOrchestrator(registry: AIToolRegistry.shared)

        // Turno 2 com continuidade anafórica sem repetir dados cadastrais
        let promptTurn2 = "No plano onde amortizo 2 mil por mês, como consigo esse valor?"
        let outputTurn2 = await orchestrator.processTurn(
            userPrompt: promptTurn2,
            store: store,
            modelLabel: "Qwen 2.5 3B"
        )

        // 1. Resposta deve orientar cortes nas categorias discricionárias
        XCTAssertTrue(outputTurn2.responseMarkdown.contains("Como Liberar R$ 2.000,00 por Mês"))
        XCTAssertTrue(outputTurn2.responseMarkdown.contains("Gastos Discricionários"))
        XCTAssertTrue(outputTurn2.responseMarkdown.contains("Plano de Corte Recomendado"))

        // 2. Histórico deve conter chamada a analyze_discretionary_spending
        let discToolMsg = store.chatHistory.first(where: { $0.role == .tool && $0.toolName == "analyze_discretionary_spending" })
        XCTAssertNotNil(discToolMsg, "analyze_discretionary_spending deve ter sido executada no Turno 2")
    }

    // MARK: - 4. Multi-Turn Turno 3: Fallback Obrigatório & Feedback Loop de Capacidades

    func testTurn3MandatoryFallbackUnsupportedCapabilityAndFeedbackLoop() async throws {
        let (store, tempDir) = createTestStore()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let registry = AIToolRegistry.shared
        registry.clearUnsupportedCapabilityLogs()

        let orchestrator = AIChatOrchestrator(registry: registry)

        // Solicitação fora de escopo (compra de ações na B3)
        let promptUnsupported = "Compre 100 ações da Petrobras PETR4 para a minha carteira agora"
        let outputUnsupported = await orchestrator.processTurn(
            userPrompt: promptUnsupported,
            store: store,
            modelLabel: "Qwen 2.5 3B"
        )

        // 1. Resposta NÃO pode alucinar sucesso na compra nem inventar saldo
        XCTAssertTrue(outputUnsupported.responseMarkdown.contains("Funcionalidade Não Suportada Nativamente"))
        XCTAssertTrue(outputUnsupported.responseMarkdown.contains("corretora de valores"))
        XCTAssertTrue(outputUnsupported.responseMarkdown.contains("Feedback Registrado"))

        // 2. Verifica se a ferramenta unsupported_capability foi invocada e registrada no histórico
        let toolFallbackMsg = store.chatHistory.first(where: { $0.role == .tool && $0.toolName == "unsupported_capability" })
        XCTAssertNotNil(toolFallbackMsg, "A tool unsupported_capability deve ter sido invocada")

        // 3. Verifica se o evento foi gravado no feedback loop do registro
        let logs = registry.unsupportedCapabilityLogs
        XCTAssertFalse(logs.isEmpty, "O registro deve conter o log de capacidade faltante")
        let lastLog = logs.last!
        XCTAssertTrue(lastLog.requestedCapability.contains("ordens de compra") || lastLog.requestedCapability.contains("ações"))
        XCTAssertTrue(lastLog.reason.contains("corretora") || lastLog.reason.contains("CVM"))
    }

    // MARK: - 5. Sliding Window Context Optimization

    func testSlidingWindowPreservesSystemPromptAndCompressesHistory() {
        let (store, tempDir) = createTestStore()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let orchestrator = AIChatOrchestrator()
        orchestrator.maxSlidingWindowMessages = 10

        // Injeta 25 mensagens simulando conversa longa
        store.chatHistory.removeAll()
        store.chatHistory.append(ChatMessage(role: .system, content: "SYSTEM PROMPT MESTRE"))
        for i in 1...24 {
            let role: ChatMessageRole = (i % 3 == 0) ? .tool : ((i % 2 == 0) ? .assistant : .user)
            let toolName = (role == .tool) ? "simulate_amortization" : nil
            let content = (role == .tool) ? String(repeating: "DADOS EXTENSOS EM JSON ", count: 50) : "Mensagem \(i)"
            store.chatHistory.append(
                ChatMessage(
                    role: role,
                    content: content,
                    timestamp: Date(),
                    toolName: toolName
                )
            )
        }

        XCTAssertEqual(store.chatHistory.count, 25)

        // Aplica janela deslizante
        orchestrator.applySlidingWindow(store: store)

        // 1. Mensagem de sistema DEVE estar intacta no index 0
        XCTAssertEqual(store.chatHistory.first?.role, .system)
        XCTAssertEqual(store.chatHistory.first?.content, "SYSTEM PROMPT MESTRE")

        // 2. O tamanho final não deve exceder maxSlidingWindowMessages + 1 (system prompt)
        XCTAssertLessThanOrEqual(store.chatHistory.count, orchestrator.maxSlidingWindowMessages + 1)

        // 3. Mensagens de tool históricas mantidas no histórico (exceto as últimas 2 mais recentes) devem ter sido sumarizadas
        let historicalTools = store.chatHistory.dropLast(2).filter { $0.role == .tool }
        XCTAssertFalse(historicalTools.isEmpty)
        for msg in historicalTools {
            XCTAssertLessThanOrEqual(msg.content.count, 350, "Saídas de ferramentas históricas devem ser sumarizadas")
            XCTAssertTrue(msg.content.contains("summarized_historical_context"))
        }
    }

    // MARK: - 6. Resilient Tool Call Parsing

    func testResilientToolCallParsing() {
        // Caso A: Bloco ```json ... ```
        let block1 = """
        Vou simular a amortização para você:
        ```json
        {
            "tool": "simulate_amortization",
            "parameters": {
                "extraPayment": 2000.0,
                "mode": "reduce_term"
            }
        }
        ```
        """
        let call1 = AIChatOrchestrator.parseToolCall(from: block1)
        XCTAssertNotNil(call1)
        XCTAssertEqual(call1?.name, "simulate_amortization")
        XCTAssertEqual(call1?.parsedArguments["extraPayment"] as? Double, 2000.0)

        // Caso B: JSON puro no texto
        let block2 = """
        {"name": "get_contract_details", "arguments": {"nameOrQuery": "caixa"}}
        """
        let call2 = AIChatOrchestrator.parseToolCall(from: block2)
        XCTAssertNotNil(call2)
        XCTAssertEqual(call2?.name, "get_contract_details")
        XCTAssertEqual(call2?.parsedArguments["nameOrQuery"] as? String, "caixa")

        // Caso C: Bloco ``` genérico
        let block3 = """
        ```
        {
            "tool": "get_monthly_cash_flow",
            "parameters": {
                "month": 11,
                "year": 2026
            }
        }
        ```
        """
        let call3 = AIChatOrchestrator.parseToolCall(from: block3)
        XCTAssertNotNil(call3)
        XCTAssertEqual(call3?.name, "get_monthly_cash_flow")
        XCTAssertEqual(call3?.parsedArguments["month"] as? Int, 11)

        // Caso D: Texto normal sem tool call
        let block4 = "Olá, quanto dinheiro eu tenho guardado na minha poupança?"
        let call4 = AIChatOrchestrator.parseToolCall(from: block4)
        XCTAssertNil(call4)
    }

    // MARK: - 7. Super AI Tools & Loan/Simulation Fixes

    func testSimularPrazoComIAWorksForArbitraryLoanNotJustCaixa() async throws {
        let (store, tempDir) = createTestStore()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let acc = BankAccount(id: UUID(), name: "Banco Santander", initialBalance: 8500.0)
        let cat = CategoryItem(id: UUID(), name: "Empréstimos", type: .expense, iconSymbol: "banknote", colorHex: "#DC2626")
        store.accounts.append(acc)
        store.categories.append(cat)

        // Cria um EMPRÉSTIMO consignado (não Caixa / não financing)
        let loan = CreditContract(
            id: UUID(),
            kind: .loan,
            name: "Consignado Folha Banco Pan",
            contractNumber: "998877",
            loanSubtype: .consignado,
            amortizationSystem: .price,
            totalContractedAmount: 42000.0,
            outstandingBalance: 35000.0,
            installmentAmount: 1350.0,
            billingDay: 2,
            totalInstallments: 48,
            originalTotalInstallments: 48,
            monthlyInterestRate: 1.45,
            startDate: Date(),
            accountId: acc.id,
            categoryId: cat.id,
            pastInstallmentsElapsedAtCreation: 12
        )
        store.contracts.append(loan)

        let orchestrator = AIChatOrchestrator(registry: AIToolRegistry.shared)
        orchestrator.forceDeterministicFallbackForTesting = true

        let prompt = "[NOVA SIMULAÇÃO DO SISTEMA] Monte um plano de ação completo para eu quitar meu empréstimo \"Consignado Folha Banco Pan\" (ID \(loan.id.uuidString)) no menor prazo possível"
        let out = await orchestrator.processTurnWithThinking(
            userPrompt: prompt,
            store: store,
            modelLabel: "Qwen 3 8B",
            isThinkingEnabled: true
        )

        XCTAssertTrue(out.responseMarkdown.contains("Consignado Folha Banco Pan"))
        XCTAssertTrue(out.responseMarkdown.contains("Empréstimo"))
        XCTAssertNotNil(out.thinkingContent)

        let toolMsgs = store.chatHistory.filter { $0.role == .tool }
        XCTAssertTrue(toolMsgs.contains { $0.toolName == "get_contract_details" && $0.content.contains("Consignado Folha Banco Pan") })
        XCTAssertTrue(toolMsgs.contains { $0.toolName == "simulate_amortization" && $0.content.contains("\"contractKind\":\"loan\"") })
    }

    func testNewFullDatabaseAccessToolsAndProjectionEngineTool() async throws {
        let (store, tempDir) = createTestStore()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let acc = BankAccount(id: UUID(), name: "Nubank", initialBalance: 15000.0)
        let catSal = CategoryItem(id: UUID(), name: "Salário", type: .income, iconSymbol: "banknote", colorHex: "#10B981")
        let catMarket = CategoryItem(id: UUID(), name: "Mercado", type: .expense, iconSymbol: "cart", colorHex: "#F59E0B")
        store.accounts.append(acc)
        store.categories.append(contentsOf: [catSal, catMarket])

        let now = store.selectedMonth
        store.transactions.append(contentsOf: [
            FinancialTransaction(name: "Salário", amount: 14000.0, date: now, type: .income, isPaid: true, categoryId: catSal.id, accountId: acc.id),
            FinancialTransaction(name: "Supermercado", amount: 2200.0, date: now, type: .expense, isPaid: true, categoryId: catMarket.id, accountId: acc.id)
        ])
        store.investments.append(InvestmentItem(name: "Reserva Liquidez", groupName: "Renda Fixa", investmentAccountId: acc.id, balance: 45000.0, showInConsolidated: true))
        store.debts.append(DebtItem(name: "Cartão Acordo", originalAmount: 6000.0))

        let registry = AIToolRegistry()
        registry.register(GetFinancialOverviewTool(store: store))
        registry.register(AggregateTransactionsTool(store: store))
        registry.register(GetInvestmentsSummaryTool(store: store))
        registry.register(AnalyzeDebtPayoffStrategyTool(store: store))

        let overview = try await registry.execute(name: "get_financial_overview", parameters: [:])
        XCTAssertEqual(overview["status"] as? String, "success")
        let summary = overview["summary"] as? [String: Any]
        XCTAssertEqual(summary?["totalInvestmentsConsolidated"] as? Double, 45000.0)

        let agg = try await registry.execute(name: "aggregate_transactions", parameters: ["type": "expense", "groupBy": "category"])
        XCTAssertEqual(agg["status"] as? String, "success")
        XCTAssertEqual(agg["grandTotalAmount"] as? Double, 2200.0)

        let inv = try await registry.execute(name: "get_investments_summary", parameters: [:])
        XCTAssertEqual(inv["totalInvestmentsConsolidated"] as? Double, 45000.0)

        let debtPlan = try await registry.execute(name: "analyze_debt_payoff_strategy", parameters: ["nameOrQuery": "Acordo"])
        XCTAssertEqual(debtPlan["status"] as? String, "success")
        XCTAssertEqual(debtPlan["matchedSpecifically"] as? Bool, true)
    }

    func testThinkTagStreamExtractorAndGGUFValidationAndConfigCompatibility() throws {
        // 1. Streaming de tags <think> fragmentadas em chunks pequenos
        var extractor = ThinkTagStreamExtractor()
        var collectedThink = ""
        var collectedContent = ""
        let chunks = ["<thi", "nk>Analisando saldo ", "real em caixa...", "</thi", "nk>\n\nAqui está ", "sua resposta."]
        for chunk in chunks {
            let (t, c) = extractor.feedContentDelta(chunk)
            collectedThink += t
            collectedContent += c
        }
        let (tTail, cTail) = extractor.finish()
        collectedThink += tTail
        collectedContent += cTail

        XCTAssertEqual(collectedThink, "Analisando saldo real em caixa...")
        XCTAssertEqual(collectedContent, "\n\nAqui está sua resposta.")

        // 2. Rejeição de manifesto antigo fake vs arquivo GGUF válido
        let fakeURL = FileManager.default.temporaryDirectory.appendingPathComponent("fake_\(UUID().uuidString).gguf")
        try "{\"repoId\":\"test\"}".write(to: fakeURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: fakeURL) }

        let fakeModel = LocalLLMModelInfo(id: "test/fake", displayName: "Fake", fileName: "fake.gguf", localPath: fakeURL.path, sizeBytes: 1_800_000_000)
        XCTAssertFalse(fakeModel.hasValidGGUFBinary, "Arquivo apenas manifesto < 10MB nunca deve ser aceito como binário GGUF válido")

        // 3. Decodificação retrocompatível de LLMConfiguration antigo sem campos isThinkingModeEnabled/contextWindowSize
        let legacyJson = """
        {"huggingFaceToken":"hf_123","selectedModelId":"qwen","downloadedModels":[],"localEndpointURL":""}
        """
        let decodedConfig = try JSONDecoder().decode(LLMConfiguration.self, from: Data(legacyJson.utf8))
        XCTAssertTrue(decodedConfig.isThinkingModeEnabled)
        XCTAssertEqual(decodedConfig.contextWindowSize, 16384)
        XCTAssertEqual(decodedConfig.appleIntelligenceTemperature, 0.25)
        XCTAssertEqual(decodedConfig.appleIntelligenceMaxResponseTokens, 1600)

        // 4. Sanitização rigorosa contra vazamento de tags <tool_call> XML/JSON na resposta final
        let dirtyOutput = """
        <think>Pensando no saldo</think>
        <tool_call name="get_monthly_cash_flow"></tool_call>
        Seu saldo disponível em conta hoje é de R$ 12.500,00.
        <tool_call>{"tool":"get_financial_overview"}</tool_call>
        """
        let clean = LocalLLMRuntime.sanitizeAssistantOutput(dirtyOutput)
        XCTAssertFalse(clean.contains("<tool_call"))
        XCTAssertFalse(clean.contains("</tool_call>"))
        XCTAssertFalse(clean.contains("<think>"))
        XCTAssertEqual(clean, "Seu saldo disponível em conta hoje é de R$ 12.500,00.")

        // 5. Modo exclusivo Apple Intelligence ativo quando disponível
        XCTAssertTrue(LocalLLMRuntime.isAppleIntelligenceExclusiveMode)
    }

    // MARK: - 8. Regressões Críticas: Empréstimo Santander (DDC/Mensal), QueryDatabase & Saldo Previsto

    func testSantanderLoanLookupWithGenericQueryAndNonZeroMonthlyAmortizationPlan() async throws {
        let (store, tempDir) = createTestStore()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let acc = BankAccount(id: UUID(), name: "Santander", initialBalance: 15000.0)
        let catSal = CategoryItem(id: UUID(), name: "Salário", type: .income, iconSymbol: "banknote", colorHex: "#10B981")
        let catLoan = CategoryItem(id: UUID(), name: "Empréstimos", type: .expense, iconSymbol: "creditcard", colorHex: "#EF4444")
        store.accounts.append(acc)
        store.categories.append(contentsOf: [catSal, catLoan])

        let now = store.selectedMonth
        store.transactions.append(
            FinancialTransaction(name: "Salário Mensal", amount: 18000.0, date: now, type: .income, isPaid: true, categoryId: catSal.id, accountId: acc.id)
        )

        let santander = CreditContract(
            id: UUID(),
            kind: .loan,
            name: "Crédito Consignado Santander",
            contractNumber: "783694303",
            loanSubtype: .consignado,
            amortizationSystem: .price,
            totalContractedAmount: 105000.0,
            outstandingBalance: 86873.35,
            installmentAmount: 4380.17,
            billingDay: 2,
            totalInstallments: 36,
            originalTotalInstallments: 36,
            monthlyInterestRate: 1.78,
            startDate: store.calendar.date(byAdding: .month, value: -11, to: now) ?? now,
            accountId: acc.id,
            categoryId: catLoan.id,
            pastInstallmentsElapsedAtCreation: 11
        )
        store.contracts.append(santander)

        // 1. GetContractDetailsTool deve encontrar o contrato Santander mesmo buscando pelo termo genérico 'emprestimos'
        let detailsTool = GetContractDetailsTool(store: store)
        let genericLookup = try await detailsTool.execute(parameters: ["nameOrQuery": "emprestimos"])
        XCTAssertEqual(genericLookup["status"] as? String, "success")
        let foundContracts = genericLookup["contracts"] as? [[String: Any]] ?? []
        XCTAssertEqual(foundContracts.count, 1)
        XCTAssertEqual(foundContracts.first?["name"] as? String, "Crédito Consignado Santander")

        // 2. SimulateAmortizationTool deve calcular projeção mensal real não-nula mesmo quando aporte único isolado elimina 0 parcelas
        let simTool = SimulateAmortizationTool(store: store)
        let sim500 = try await simTool.execute(parameters: [
            "nameOrQuery": "santander",
            "extraPayment": 500.0,
            "mode": "reduce_term"
        ])
        XCTAssertEqual(sim500["status"] as? String, "success")
        let recProj = sim500["recurringMonthlyProjection"] as? [String: Any]
        XCTAssertNotNil(recProj)
        XCTAssertGreaterThan((recProj?["monthsSavedWithPlan"] as? Int) ?? 0, 0, "Cenário mensal +R$ 500/mês deve eliminar parcelas reais")
        XCTAssertGreaterThan((recProj?["totalInterestSaved"] as? Double) ?? 0.0, 0.0, "Cenário mensal +R$ 500/mês deve economizar juros futuros reais")

        // 3. Orquestrador (em modo determinístico) deve exibir parcelas eliminadas > 0 e juros economizados > R$ 0,00 (nunca 'Elimina 0 parcelas')
        let orchestrator = AIChatOrchestrator(registry: AIToolRegistry.shared)
        orchestrator.forceDeterministicFallbackForTesting = true
        let prompt = "[NOVA SIMULAÇÃO DO SISTEMA] Monte um plano de ação completo para eu quitar meu empréstimo \"Crédito Consignado Santander\" — Contrato 783694303 (ID \(santander.id.uuidString)) no menor prazo possível."
        let out = await orchestrator.processTurnWithThinking(
            userPrompt: prompt,
            store: store,
            modelLabel: "Apple Intelligence",
            isThinkingEnabled: true
        )
        XCTAssertTrue(out.responseMarkdown.contains("Crédito Consignado Santander"))
        XCTAssertTrue(out.responseMarkdown.contains("Saldo Previsto ao Fim do Mês"))
        XCTAssertFalse(out.responseMarkdown.contains("Elimina **0 parcelas**"))
        XCTAssertFalse(out.responseMarkdown.contains("economizando **R$ 0,00**"))
    }

    func testQueryDatabaseToolFullAccessAndSaldoPrevistoAndOpenVsPaidDebts() async throws {
        let (store, tempDir) = createTestStore()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let acc = BankAccount(id: UUID(), name: "Conta Principal", initialBalance: 10000.0)
        let catSal = CategoryItem(id: UUID(), name: "Salário", type: .income, iconSymbol: "banknote", colorHex: "#10B981")
        let catFood = CategoryItem(id: UUID(), name: "Alimentação", type: .expense, iconSymbol: "fork.knife", colorHex: "#F59E0B")
        store.accounts.append(acc)
        store.categories.append(contentsOf: [catSal, catFood])

        let now = store.selectedMonth
        store.transactions.append(contentsOf: [
            FinancialTransaction(name: "Salário", amount: 12000.0, date: now, type: .income, isPaid: true, categoryId: catSal.id, accountId: acc.id),
            FinancialTransaction(name: "Restaurante", amount: 500.0, date: now, type: .expense, isPaid: true, categoryId: catFood.id, accountId: acc.id)
        ])
        let curYear = store.calendar.component(.year, from: now)
        let curMonth = store.calendar.component(.month, from: now)
        store.provisions.append(CategoryProvision(categoryId: catFood.id, year: curYear, month: curMonth, estimatedAmount: 1500.0))
        store.investments.append(InvestmentItem(name: "Caixinha CDB", groupName: "Reserva", investmentAccountId: acc.id, balance: 20000.0, showInConsolidated: true))
        store.debts.append(contentsOf: [
            DebtItem(name: "Dívida Aberta Cartão", originalAmount: 3200.0, isPaid: false),
            DebtItem(name: "Dívida Antiga Quitada", originalAmount: 9500.0, isPaid: true, negotiatedAmount: 4000.0, paidDate: now)
        ])

        let queryTool = QueryDatabaseTool(store: store)

        // 1. kpi_summary deve bater rigorosamente com Dashboard Saldo Previsto (Card 6)
        let kpiRes = try await queryTool.execute(parameters: ["table": "kpi_summary"])
        let expectedKPI = store.buildUnifiedFinancialKPISummary(referenceDate: store.selectedMonth, isAnnual: false)
        let expectedSaldoPrevisto = expectedKPI.isPast ? expectedKPI.projectedAccountBalance : expectedKPI.balanceIfAllBudgetsConsumed
        XCTAssertEqual(kpiRes["status"] as? String, "success")
        XCTAssertEqual((kpiRes["saldoPrevistoFimDoMes"] as? Double) ?? -1, expectedSaldoPrevisto, accuracy: 0.01)
        XCTAssertEqual((kpiRes["saldoPrevistoSemConsumirOrcamentos"] as? Double) ?? -1, expectedKPI.projectedAccountBalance, accuracy: 0.01)

        // 2. debts deve separar rigorosamente abertas (3.200) de pagas (9.500/4.000) sem misturar
        let debtsRes = try await queryTool.execute(parameters: ["table": "debts"])
        XCTAssertEqual(debtsRes["openDebtsCount"] as? Int, 1)
        XCTAssertEqual((debtsRes["openDebtsTotalAmount"] as? Double) ?? -1, 3200.0, accuracy: 0.01)
        XCTAssertEqual(debtsRes["paidDebtsCount"] as? Int, 1)

        // 3. AnalyzeDebtPayoffStrategyTool também deve excluir a dívida já quitada e incluir Saldo Previsto
        let debtStrategyTool = AnalyzeDebtPayoffStrategyTool(store: store)
        let stratRes = try await debtStrategyTool.execute(parameters: [:])
        XCTAssertEqual(stratRes["openDebtsCount"] as? Int, 1)
        XCTAssertEqual((stratRes["openDebtsTotalAmount"] as? Double) ?? -1, 3200.0, accuracy: 0.01)
        XCTAssertEqual(stratRes["paidDebtsCount"] as? Int, 1)
        XCTAssertEqual((stratRes["saldoPrevistoFimDoMes"] as? Double) ?? -1, expectedSaldoPrevisto, accuracy: 0.01)

        // 4. get_monthly_cash_flow também deve expor saldoPrevistoFimDoMes
        let cashTool = GetMonthlyCashFlowTool(store: store)
        let cashRes = try await cashTool.execute(parameters: [:])
        XCTAssertEqual((cashRes["saldoPrevistoFimDoMes"] as? Double) ?? -1, expectedSaldoPrevisto, accuracy: 0.01)

        // 5. FinancialDatabaseContextBuilder deve extrair corretamente aporte customizado ("R$ 1.500") sem confundir com multi-cenário
        let finAcc = store.accounts.first!
        let finCat = store.categories.first!
        let caixa = CreditContract(
            id: UUID(),
            kind: .financing,
            name: "Financiamento Caixa Teste",
            contractNumber: "1.4444.0674063-2",
            financingSubtype: .imovel,
            amortizationSystem: .price,
            totalContractedAmount: 324737.86,
            outstandingBalance: 324737.86,
            installmentAmount: 2658.04,
            billingDay: 15,
            totalInstallments: 360,
            originalTotalInstallments: 360,
            monthlyInterestRate: 0.7091667,
            startDate: now,
            accountId: finAcc.id,
            categoryId: finCat.id,
            pastInstallmentsElapsedAtCreation: 28,
            annualNominalInterestRate: 8.51,
            indexationRate: .tr,
            adminFee: 25.0,
            insuranceFee: 86.27,
            baseInstallmentAmount: 2546.77
        )
        store.contracts.append(caixa)
        let grounded = await FinancialDatabaseContextBuilder.buildGroundedContextSnapshot(
            for: "Quanto economizo no financiamento Caixa se amortizar R$ 1.500 por mês?",
            store: store
        )
        XCTAssertFalse(grounded.steps.isEmpty)
        XCTAssertTrue(grounded.compactJson.contains("1.500,00"), "Snapshot determinístico deve simular exatamente R$ 1.500,00/mês quando solicitado")
    }

    // MARK: - 8. Internet Lookup Toggle, Conversão Local, Extrato e Simulação Interativa em 2 Etapas

    func testInternetLookupConfigDefaultAndDisabledGuard() async throws {
        let legacyJson = """
        {
            "isEnabled": true,
            "isThinkingEnabled": true,
            "temperature": 0.25,
            "maxTokens": 1024,
            "appleIntelligenceTemperature": 0.25,
            "appleIntelligenceMaxResponseTokens": 1400,
            "localEndpointURL": ""
        }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(LLMConfiguration.self, from: legacyJson)
        XCTAssertTrue(decoded.isInternetAccessEnabled, "Configurações legadas devem habilitar consultas de internet somente-leitura por padrão")

        // Sanitização deve remover valores em R$, UUIDs e sequências longas
        let dirty = "Se meu patrimonio de R$ 154.320,50 com contrato 123456789 e id \(UUID().uuidString) estivesse em dolar hoje?"
        let sanitized = InternetLookupService.sanitizePublicQuery(dirty)
        XCTAssertFalse(sanitized.contains("154.320,50"))
        XCTAssertFalse(sanitized.contains("123456789"))
        XCTAssertTrue(sanitized.localizedCaseInsensitiveContains("dolar"))

        // Quando desativado nas Configurações, InternetLookupTool deve recusar execução e orientar o usuário
        let (store, tempDir) = createTestStore()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        store.llmConfig.isInternetAccessEnabled = false

        let tool = InternetLookupTool(store: store)
        let res = try await tool.execute(parameters: ["query": "Qual o valor do dolar hoje?"])
        XCTAssertEqual(res["status"] as? String, "disabled")
    }

    func testInteractiveTwoStepSimularPrazoFreshContextAndDebtVsContract() async throws {
        let (store, tempDir) = createTestStore()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let acc = BankAccount(id: UUID(), name: "Conta Itaú", initialBalance: 6000.0)
        let catSal = CategoryItem(id: UUID(), name: "Salário", type: .income, iconSymbol: "banknote", colorHex: "#10B981")
        let catDebt = CategoryItem(id: UUID(), name: "Dívidas", type: .expense, iconSymbol: "creditcard", colorHex: "#EF4444")
        store.accounts.append(acc)
        store.categories.append(contentsOf: [catSal, catDebt])

        let now = store.selectedMonth
        store.transactions.append(contentsOf: [
            FinancialTransaction(name: "Salário Mensal", amount: 10000.0, date: now, type: .income, isPaid: true, categoryId: catSal.id, accountId: acc.id, recurrenceMode: .recurring, recurrenceFrequency: .monthly),
            FinancialTransaction(name: "Aluguel e Contas", amount: 3000.0, date: now, type: .expense, isPaid: true, categoryId: catDebt.id, accountId: acc.id, recurrenceMode: .recurring, recurrenceFrequency: .monthly)
        ])

        let serasa = DebtItem(id: UUID(), name: "Acordo Serasa", originalAmount: 4500.0, isPaid: false)
        store.debts.append(serasa)

        let loan = CreditContract(
            id: UUID(),
            kind: .loan,
            name: "Consignado Teste",
            contractNumber: "554433",
            loanSubtype: .consignado,
            amortizationSystem: .price,
            totalContractedAmount: 24000.0,
            outstandingBalance: 18000.0,
            installmentAmount: 900.0,
            billingDay: 10,
            totalInstallments: 24,
            originalTotalInstallments: 24,
            monthlyInterestRate: 1.5,
            startDate: now,
            accountId: acc.id,
            categoryId: catDebt.id,
            pastInstallmentsElapsedAtCreation: 4
        )
        store.contracts.append(loan)

        let orchestrator = AIChatOrchestrator.shared
        orchestrator.forceDeterministicFallbackForTesting = true
        defer { orchestrator.forceDeterministicFallbackForTesting = false; orchestrator.pendingSimulationTarget = nil; orchestrator.lastSimulatedTarget = nil }

        // Histórico anterior deve ser completamente zerado quando um botão fixo iniciar nova simulação
        store.chatHistory = [ChatMessage(role: .user, content: "Conversa antiga", timestamp: now)]
        orchestrator.pendingSimulationTarget = .debt(id: serasa.id, name: serasa.name)

        let monthEndStr = BRLFormatters.shortDate(store.endOfMonth(for: store.selectedMonth))

        // 1A. Simular Prazo em DÍVIDA (Serasa) -> Etapa 1 deve perguntar Agressivo / Moderado / Leve e citar fim do mês
        let debtPrompt = "[NOVA SIMULAÇÃO DO SISTEMA] [TIPO:DIVIDA] [ID:\(serasa.id.uuidString)] [MODO:PERGUNTAR_RITMO] Quero simular um prazo para quitar minha dívida \"Acordo Serasa\"."
        store.chatHistory.removeAll() // simula comportamento de startFreshSimulationQuestion sem usar backend neural
        orchestrator.pendingSimulationTarget = .debt(id: serasa.id, name: serasa.name)
        let step1Debt = await orchestrator.processTurnWithThinking(
            userPrompt: debtPrompt,
            store: store,
            modelLabel: "Apple Intelligence Nativo",
            isThinkingEnabled: true
        )
        XCTAssertTrue(step1Debt.responseMarkdown.contains("Agressivo"))
        XCTAssertTrue(step1Debt.responseMarkdown.contains("Moderado"))
        XCTAssertTrue(step1Debt.responseMarkdown.contains("Leve"))
        XCTAssertFalse(step1Debt.responseMarkdown.contains("0,00/mês"), "Etapa 1 nunca deve propor valores R$ 0,00/mês prematuramente")
        XCTAssertTrue(step1Debt.responseMarkdown.contains("guardar dinheiro pouco a pouco"))
        XCTAssertTrue(step1Debt.responseMarkdown.contains(monthEndStr))
        XCTAssertEqual(step1Debt.followUps, ["Plano Agressivo", "Plano Moderado", "Plano Leve"])

        // 1B. Resposta do usuário ("Plano Moderado") -> Etapa 2 retorna cronograma de guarda gradual com datas de fechamento e data de quitação
        let step2Debt = await orchestrator.processTurnWithThinking(
            userPrompt: "Plano Moderado",
            store: store,
            modelLabel: "Apple Intelligence Nativo",
            isThinkingEnabled: true
        )
        XCTAssertTrue(step2Debt.responseMarkdown.contains("Plano Moderado para Quitar Dívida"))
        XCTAssertTrue(step2Debt.responseMarkdown.contains("Data prevista para quitação integral"))
        XCTAssertTrue(step2Debt.responseMarkdown.contains(monthEndStr))

        // 2. Simular Prazo em EMPRÉSTIMO -> Etapa 1 pergunta ritmo mencionando amortização parcelada, Etapa 2 amortiza mês a mês
        store.chatHistory.removeAll()
        orchestrator.pendingSimulationTarget = .contract(id: loan.id, name: loan.name, kind: loan.kind)
        let loanPrompt = "[NOVA SIMULAÇÃO DO SISTEMA] [TIPO:CONTRATO] [ID:\(loan.id.uuidString)] [MODO:PERGUNTAR_RITMO] Quero simular um prazo para quitar meu empréstimo \"Consignado Teste\"."
        let step1Loan = await orchestrator.processTurnWithThinking(
            userPrompt: loanPrompt,
            store: store,
            modelLabel: "Apple Intelligence Nativo",
            isThinkingEnabled: true
        )
        XCTAssertTrue(step1Loan.responseMarkdown.contains("plano de amortização mês a mês"))
        XCTAssertTrue(step1Loan.responseMarkdown.contains(monthEndStr))

        let step2Loan = await orchestrator.processTurnWithThinking(
            userPrompt: "Plano Agressivo",
            store: store,
            modelLabel: "Apple Intelligence Nativo",
            isThinkingEnabled: true
        )
        XCTAssertTrue(step2Loan.responseMarkdown.contains("Plano de Amortização Agressivo"))
        XCTAssertTrue(step2Loan.responseMarkdown.contains("Cronograma de Amortização"))
        XCTAssertTrue(step2Loan.responseMarkdown.contains(monthEndStr))
    }

    func testDebtSimulationWithNegativeCurrentMonthAndPositiveFutureMonthsPreservesContextAndFutureSafety() async throws {
        let (store, tempDir) = createTestStore()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let acc = BankAccount(id: UUID(), name: "Conta Principal", initialBalance: 0.0)
        let catSal = CategoryItem(id: UUID(), name: "Salário", type: .income, iconSymbol: "banknote", colorHex: "#10B981")
        let catExp = CategoryItem(id: UUID(), name: "Despesas", type: .expense, iconSymbol: "creditcard", colorHex: "#EF4444")
        store.accounts.append(acc)
        store.categories.append(contentsOf: [catSal, catExp])

        let cal = store.calendar
        let nov = store.selectedMonth
        let dec = cal.date(byAdding: .month, value: 1, to: nov)!
        let jan = cal.date(byAdding: .month, value: 2, to: nov)!
        let feb = cal.date(byAdding: .month, value: 3, to: nov)!
        let mar = cal.date(byAdding: .month, value: 4, to: nov)!

        // Mês atual negativo (-R$ 394,33), Dezembro positivo (+R$ 4.000 líquido -> acumulado +3.605,67),
        // Janeiro com IPVA (-R$ 1.500 líquido -> acumulado cai para +2.105,67!), Fev/Mar positivos (+R$ 3.000/mês)
        store.transactions.append(contentsOf: [
            FinancialTransaction(name: "Salário Nov", amount: 5000.0, date: nov, type: .income, isPaid: true, categoryId: catSal.id, accountId: acc.id),
            FinancialTransaction(name: "Despesas Nov", amount: 5394.33, date: nov, type: .expense, isPaid: true, categoryId: catExp.id, accountId: acc.id),
            FinancialTransaction(name: "Salário Dez", amount: 9000.0, date: dec, type: .income, isPaid: false, categoryId: catSal.id, accountId: acc.id),
            FinancialTransaction(name: "Despesas Dez", amount: 5000.0, date: dec, type: .expense, isPaid: false, categoryId: catExp.id, accountId: acc.id),
            FinancialTransaction(name: "Salário Jan", amount: 5000.0, date: jan, type: .income, isPaid: false, categoryId: catSal.id, accountId: acc.id),
            FinancialTransaction(name: "IPVA + Despesas Jan", amount: 6500.0, date: jan, type: .expense, isPaid: false, categoryId: catExp.id, accountId: acc.id),
            FinancialTransaction(name: "Salário Fev", amount: 8000.0, date: feb, type: .income, isPaid: false, categoryId: catSal.id, accountId: acc.id),
            FinancialTransaction(name: "Despesas Fev", amount: 5000.0, date: feb, type: .expense, isPaid: false, categoryId: catExp.id, accountId: acc.id),
            FinancialTransaction(name: "Salário Mar", amount: 8000.0, date: mar, type: .income, isPaid: false, categoryId: catSal.id, accountId: acc.id),
            FinancialTransaction(name: "Despesas Mar", amount: 5000.0, date: mar, type: .expense, isPaid: false, categoryId: catExp.id, accountId: acc.id)
        ])

        let carrefour = DebtItem(id: UUID(), name: "Cartão de crédito Carrefour", originalAmount: 6196.0, isPaid: false)
        store.debts.append(carrefour)

        let orchestrator = AIChatOrchestrator.shared
        orchestrator.forceDeterministicFallbackForTesting = true
        orchestrator.pendingSimulationTarget = nil
        orchestrator.lastSimulatedTarget = nil
        defer {
            orchestrator.forceDeterministicFallbackForTesting = false
            orchestrator.pendingSimulationTarget = nil
            orchestrator.lastSimulatedTarget = nil
        }

        // Chat livre usando "Simule" (não apenas "simular") deve reconhecer alvo exato, NÃO propor ~R$ 0,00/mês e salvar breadcrumb
        let step1 = await orchestrator.processTurnWithThinking(
            userPrompt: "Simule o prazo para quitar a divida \"Cartão de credito Carrefour\" (R$6.196)",
            store: store,
            modelLabel: "Apple Intelligence Nativo",
            isThinkingEnabled: true
        )
        XCTAssertTrue(step1.responseMarkdown.contains("Cartão de crédito Carrefour"))
        XCTAssertFalse(step1.responseMarkdown.contains("0,00/mês"), "Não deve sugerir valores falsos de R$ 0,00/mês na Etapa 1")
        XCTAssertTrue(step1.responseMarkdown.contains("Agressivo"))
        XCTAssertTrue(step1.responseMarkdown.contains("Moderado"))
        XCTAssertTrue(step1.responseMarkdown.contains("Leve"))

        // Simula perda da variável em RAM antes de responder "Agressivo" — o contexto DEVE ser recuperado pelo breadcrumb do chatHistory!
        orchestrator.pendingSimulationTarget = nil
        orchestrator.lastSimulatedTarget = nil

        let step2 = await orchestrator.processTurnWithThinking(
            userPrompt: "agressivo",
            store: store,
            modelLabel: "Apple Intelligence Nativo",
            isThinkingEnabled: true
        )
        XCTAssertTrue(step2.responseMarkdown.contains("Plano Agressivo para Quitar Dívida: Cartão de crédito Carrefour"))
        XCTAssertFalse(step2.responseMarkdown.localizedCaseInsensitiveContains("empréstimo"))
        XCTAssertTrue(step2.responseMarkdown.contains("Sem reserva possível neste mês"), "Novembro negativo não deve alocar reserva falsa")
        // Em Dezembro (folga +3.605,67), o impacto de Janeiro (-1.500) reduz a margem segura máxima de Dezembro para 2.105,67 (não pode estourar Janeiro nem assumir R$ 6.196 em Dezembro!)
        XCTAssertFalse(step2.responseMarkdown.contains("31/12/2026) _"), "Não deve quitar em Dezembro ignorando impacto em Janeiro")
        XCTAssertFalse(step2.responseMarkdown.contains("|---|"), "Cronograma não deve usar pipe table incompatível com Text(LocalizedStringKey)")
    }

    func testStatementImportProducesNonGenericMerchantTitles() {
        let categories = [
            CategoryItem(name: "Saúde", type: .expense, iconSymbol: "heart.fill", colorHex: "#EF4444"),
            CategoryItem(name: "Compras", type: .expense, iconSymbol: "bag.fill", colorHex: "#8B5CF6"),
            CategoryItem(name: "Transporte", type: .expense, iconSymbol: "car.fill", colorHex: "#3B82F6"),
            CategoryItem(name: "Alimentação", type: .expense, iconSymbol: "fork.knife", colorHex: "#F59E0B"),
            CategoryItem(name: "Outros", type: .expense, iconSymbol: "tag.fill", colorHex: "#64748B")
        ]
        let rawText = """
        05/11/2026 PAG*DROGASIL 123 -145,90
        06/11/2026 PIX QRS MERCADOLIVRE -230,00
        07/11/2026 COMPRA DEBITO UBER -34,50
        08/11/2026 IFD*STARBUCKS BRASIL -28,00
        """
        let parsed = StatementImportService.parseStatementText(rawText, categories: categories)
        XCTAssertEqual(parsed.count, 4)
        XCTAssertEqual(parsed[0].cleanTitle, "Farmácia Drogasil")
        XCTAssertEqual(parsed[0].suggestedCategoryName, "Saúde")
        XCTAssertEqual(parsed[1].cleanTitle, "Mercado Livre")
        XCTAssertEqual(parsed[2].cleanTitle, "Uber Viagens")
        XCTAssertEqual(parsed[3].cleanTitle, "Starbucks Cafeteria")
    }
}
