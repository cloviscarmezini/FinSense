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
}
