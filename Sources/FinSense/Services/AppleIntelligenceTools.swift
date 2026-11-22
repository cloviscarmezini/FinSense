import Foundation
#if canImport(FoundationModels)
import FoundationModels

@available(macOS 26.0, *)
public typealias AppleToolActivityHandler = @Sendable (_ stepLabel: String, _ thinkingLine: String) -> Void

// MARK: - Helper Compartilhado para Respostas Compactas

@available(macOS 26.0, *)
private func encodeCompactResult(_ dict: [String: Any], maxLength: Int = 1500) -> String {
    guard let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]),
          let str = String(data: data, encoding: .utf8) else {
        return "{}"
    }
    if str.count <= maxLength { return str }
    return String(str.prefix(maxLength)) + "...}"
}

@available(macOS 26.0, *)
@MainActor
public enum AppleIntelligenceToolFactory {
    public static func buildAllTools(
        store: FinancialDataStore,
        onActivity: AppleToolActivityHandler?
    ) -> [any FoundationModels.Tool] {
        return [
            AppleOverviewTool(store: store, onActivity: onActivity),
            AppleCashFlowAndProjectionTool(store: store, onActivity: onActivity),
            AppleContractAndPlanTool(store: store, onActivity: onActivity),
            AppleSimulateAmortizationTool(store: store, onActivity: onActivity),
            AppleTransactionsTool(store: store, onActivity: onActivity),
            AppleBudgetsAndCutsTool(store: store, onActivity: onActivity),
            AppleDebtsAndInvestmentsTool(store: store, onActivity: onActivity),
            AppleUnsupportedCapabilityTool(onActivity: onActivity)
        ]
    }
}

// MARK: - 1. Overview Global do Banco Local

@available(macOS 26.0, *)
public struct AppleOverviewTool: FoundationModels.Tool, @unchecked Sendable {
    public let name = "get_financial_overview"
    public let description = "Consulta contas bancárias com saldos atuais, investimentos, todos os contratos ativos, dívidas em aberto e categorias do banco local."

    @Generable
    public struct Arguments {
        @Guide(description: "Escopo opcional: all, accounts, contracts, debts ou investments")
        public var scope: String?
    }

    private let store: FinancialDataStore
    private let onActivity: AppleToolActivityHandler?

    public init(store: FinancialDataStore, onActivity: AppleToolActivityHandler?) {
        self.store = store
        self.onActivity = onActivity
    }

    public func call(arguments: Arguments) async throws -> String {
        onActivity?("🔧 Consultando panorama global do banco de dados...", "Consultando contas, saldos, contratos ativos, dívidas e investimentos em tempo real.")
        let tool = await MainActor.run { GetFinancialOverviewTool(store: store) }
        let result = try await tool.execute(parameters: [:])
        return encodeCompactResult(result, maxLength: 1650)
    }
}

// MARK: - 2. Fluxo de Caixa Mensal & Projeções Futuras

@available(macOS 26.0, *)
public struct AppleCashFlowAndProjectionTool: FoundationModels.Tool, @unchecked Sendable {
    public let name = "get_cash_flow_and_projection"
    public let description = "Consulta receitas, despesas, contas pendentes, sobra líquida do mês (YYYY-MM) ou projeta meses futuros (2 a 36 meses)."

    @Generable
    public struct Arguments {
        @Guide(description: "Modo: 'month' para um mês específico ou 'range' para projeção multi-mês")
        public var mode: String?
        @Guide(description: "Mês de referência no formato YYYY-MM (ex: 2026-11)")
        public var month: String?
        @Guide(description: "Quantidade de meses para projeção futura (ex: 6 ou 12)")
        public var monthsCount: Int?
    }

    private let store: FinancialDataStore
    private let onActivity: AppleToolActivityHandler?

    public init(store: FinancialDataStore, onActivity: AppleToolActivityHandler?) {
        self.store = store
        self.onActivity = onActivity
    }

    public func call(arguments: Arguments) async throws -> String {
        let mode = (arguments.mode ?? (arguments.monthsCount != nil ? "range" : "month")).lowercased()
        if mode == "range" {
            let count = arguments.monthsCount ?? 12
            onActivity?("📈 Projetando fluxo de caixa dos próximos \(count) meses...", "Executando projeção de receitas, despesas e saldo acumulado para \(count) meses.")
            var params: [String: Any] = ["numberOfMonths": count]
            if let m = arguments.month, !m.isEmpty { params["startMonth"] = m }
            let tool = await MainActor.run { GetProjectedCashFlowRangeTool(store: store) }
            let res = try await tool.execute(parameters: params)
            return encodeCompactResult(res, maxLength: 1550)
        } else {
            let label = arguments.month ?? "mês ativo"
            onActivity?("💵 Consultando fluxo de caixa (\(label))...", "Verificando receitas, despesas pagas/pendentes, tetos e sobra operacional.")
            var params: [String: Any] = [:]
            if let m = arguments.month, !m.isEmpty { params["referenceDate"] = m }
            let tool = await MainActor.run { GetMonthlyCashFlowTool(store: store) }
            let res = try await tool.execute(parameters: params)
            return encodeCompactResult(res, maxLength: 1550)
        }
    }
}

// MARK: - 3. Detalhes de Contrato & Planejamento de Amortização (LoanProjectionEngine)

@available(macOS 26.0, *)
public struct AppleContractAndPlanTool: FoundationModels.Tool, @unchecked Sendable {
    public let name = "get_contract_and_plan"
    public let description = "Consulta detalhes completos de empréstimo/financiamento (parcelas pagas pelo salário, saldo devedor, quitação hoje) e analisa o plano salvo ou simula plano mensal."

    @Generable
    public struct Arguments {
        @Guide(description: "Nome ou termo do contrato (ex: 'Caixa', 'Santander', 'Pan'). Deixe vazio para listar todos.")
        public var query: String?
        @Guide(description: "Opcional: valor de aporte mensal extra para simular no plano de longo prazo")
        public var simulateMonthlyExtra: Double?
        @Guide(description: "Origem opcional da simulação: 'cash' (Dinheiro) ou 'fgts'")
        public var source: String?
    }

    private let store: FinancialDataStore
    private let onActivity: AppleToolActivityHandler?

    public init(store: FinancialDataStore, onActivity: AppleToolActivityHandler?) {
        self.store = store
        self.onActivity = onActivity
    }

    public func call(arguments: Arguments) async throws -> String {
        let q = arguments.query?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let monthlyExtra = arguments.simulateMonthlyExtra, monthlyExtra > 0 {
            onActivity?("📊 Projetando plano com aporte mensal em '\(q.isEmpty ? "contrato" : q)'...", "Rodando LoanProjectionEngine com aportes mensais de R$ \(Int(monthlyExtra)) (\(arguments.source ?? "cash")).")
            var params: [String: Any] = ["simulateMonthlyExtraAmount": monthlyExtra]
            if !q.isEmpty { params["nameOrQuery"] = q }
            if let src = arguments.source { params["simulateSource"] = src }
            let tool = await MainActor.run { GetLoanProjectionAndPlanTool(store: store) }
            let res = try await tool.execute(parameters: params)
            return encodeCompactResult(res, maxLength: 1650)
        } else {
            onActivity?("🏦 Consultando contrato '\(q.isEmpty ? "todos" : q)'...", "Lendo saldo devedor real, quitação presente e planejamento de amortização.")
            let detailsTool = await MainActor.run { GetContractDetailsTool(store: store) }
            let detailsRes = try await detailsTool.execute(parameters: q.isEmpty ? [:] : ["nameOrQuery": q])
            var combined: [String: Any] = ["details": detailsRes]
            if let contracts = detailsRes["contracts"] as? [[String: Any]],
               contracts.count == 1,
               let cid = contracts.first?["id"] as? String {
                let planTool = await MainActor.run { GetLoanProjectionAndPlanTool(store: store) }
                if let planRes = try? await planTool.execute(parameters: ["contractId": cid]),
                   (planRes["hasSavedPlanOnDatabase"] as? Bool) == true {
                    combined["savedPlanProjection"] = planRes
                }
            }
            return encodeCompactResult(combined, maxLength: 1700)
        }
    }
}

// MARK: - 4. Simulação Direta de Amortização (Empréstimos e Financiamentos)

@available(macOS 26.0, *)
public struct AppleSimulateAmortizationTool: FoundationModels.Tool, @unchecked Sendable {
    public let name = "simulate_amortization"
    public let description = "Simula amortização extra em empréstimo ou financiamento (redução de prazo ou parcela) sem alterar os dados reais."

    @Generable
    public struct Arguments {
        @Guide(description: "Nome do contrato (ex: 'Caixa', 'Santander', 'Habitacao')")
        public var contractQuery: String
        @Guide(description: "Valor do aporte extra em reais (ex: 500, 1000, 2000)")
        public var extraPayment: Double
        @Guide(description: "Modo: 'reduce_term' (padrão) ou 'reduce_installment'")
        public var mode: String?
        @Guide(description: "Se true, projeta esse aporte mensalmente até quitar via LoanProjectionEngine")
        public var recurringMonthly: Bool?
    }

    private let store: FinancialDataStore
    private let onActivity: AppleToolActivityHandler?

    public init(store: FinancialDataStore, onActivity: AppleToolActivityHandler?) {
        self.store = store
        self.onActivity = onActivity
    }

    public func call(arguments: Arguments) async throws -> String {
        onActivity?(
            "⚡ Simulando amortização de R$ \(Int(arguments.extraPayment)) em '\(arguments.contractQuery)'...",
            "Executando motor de amortização para +\(BRLFormatters.currency(arguments.extraPayment)) em '\(arguments.contractQuery)' (modo: \(arguments.mode ?? "reduce_term"), mensal: \(arguments.recurringMonthly ?? false))."
        )
        let tool = await MainActor.run { SimulateAmortizationTool(store: store) }
        let res = try await tool.execute(parameters: [
            "nameOrQuery": arguments.contractQuery,
            "extraPayment": arguments.extraPayment,
            "mode": arguments.mode ?? "reduce_term",
            "recurringMonthly": arguments.recurringMonthly ?? true
        ])
        return encodeCompactResult(res, maxLength: 1600)
    }
}

// MARK: - 5. Consulta & Analítica de Transações (Qualquer Período / Agrupamento)

@available(macOS 26.0, *)
public struct AppleTransactionsTool: FoundationModels.Tool, @unchecked Sendable {
    public let name = "query_and_aggregate_transactions"
    public let description = "Agrupa/soma transações (por categoria, mês, conta ou descrição) ou lista lançamentos individuais em qualquer período."

    @Generable
    public struct Arguments {
        @Guide(description: "'summary' para totais agrupados ou 'list' para lançamentos individuais")
        public var mode: String?
        @Guide(description: "Data inicial YYYY-MM-DD opcional")
        public var startDate: String?
        @Guide(description: "Data final YYYY-MM-DD opcional")
        public var endDate: String?
        @Guide(description: "Mês específico YYYY-MM opcional")
        public var month: String?
        @Guide(description: "Filtro textual na descrição ou detalhes")
        public var searchQuery: String?
        @Guide(description: "Nome da categoria opcional")
        public var categoryName: String?
        @Guide(description: "Dimensão de agrupamento para summary: category, month, account, description")
        public var groupBy: String?
        @Guide(description: "Tipo: expense, income ou all")
        public var type: String?
    }

    private let store: FinancialDataStore
    private let onActivity: AppleToolActivityHandler?

    public init(store: FinancialDataStore, onActivity: AppleToolActivityHandler?) {
        self.store = store
        self.onActivity = onActivity
    }

    public func call(arguments: Arguments) async throws -> String {
        let mode = (arguments.mode ?? "summary").lowercased()
        var params: [String: Any] = [:]
        if let v = arguments.startDate, !v.isEmpty { params["startDate"] = v }
        if let v = arguments.endDate, !v.isEmpty { params["endDate"] = v }
        if let v = arguments.month, !v.isEmpty { params["month"] = v }
        if let v = arguments.searchQuery, !v.isEmpty { params["searchQuery"] = v }
        if let v = arguments.categoryName, !v.isEmpty { params["categoryName"] = v }
        if let v = arguments.type, !v.isEmpty { params["type"] = v }

        if mode == "list" {
            onActivity?("🧾 Listando lançamentos financeiros...", "Filtrando transações locais (\(arguments.searchQuery ?? arguments.categoryName ?? arguments.month ?? "recentes")).")
            params["limit"] = 20
            let tool = await MainActor.run { QueryTransactionsTool(store: store) }
            let res = try await tool.execute(parameters: params)
            return encodeCompactResult(res, maxLength: 1600)
        } else {
            onActivity?("🔍 Agregando e somando transações...", "Consolidando transações agrupadas por \(arguments.groupBy ?? "category").")
            if let g = arguments.groupBy, !g.isEmpty { params["groupBy"] = g }
            let tool = await MainActor.run { AggregateTransactionsTool(store: store) }
            let res = try await tool.execute(parameters: params)
            return encodeCompactResult(res, maxLength: 1600)
        }
    }
}

// MARK: - 6. Orçamentos (Tetos/Cotas) & Análise de Cortes Discricionários

@available(macOS 26.0, *)
public struct AppleBudgetsAndCutsTool: FoundationModels.Tool, @unchecked Sendable {
    public let name = "analyze_budgets_and_cuts"
    public let description = "Consulta tetos orçamentários (provisões), cotas de itens e analisa onde cortar gastos flexíveis para liberar uma meta mensal."

    @Generable
    public struct Arguments {
        @Guide(description: "Mês YYYY-MM opcional (padrão mês ativo)")
        public var month: String?
        @Guide(description: "Meta mensal em reais que precisa liberar com cortes (opcional, ex: 2000)")
        public var targetMonthlyAmount: Double?
    }

    private let store: FinancialDataStore
    private let onActivity: AppleToolActivityHandler?

    public init(store: FinancialDataStore, onActivity: AppleToolActivityHandler?) {
        self.store = store
        self.onActivity = onActivity
    }

    public func call(arguments: Arguments) async throws -> String {
        if let target = arguments.targetMonthlyAmount, target > 0 {
            onActivity?("✂️ Analisando cortes para liberar R$ \(Int(target))/mês...", "Cruzando gastos discricionários com sobra operacional para meta de \(BRLFormatters.currency(target)).")
            var params: [String: Any] = ["targetExtraPayment": target]
            if let m = arguments.month, !m.isEmpty { params["referenceMonth"] = m }
            let tool = await MainActor.run { AnalyzeDiscretionarySpendingTool(store: store) }
            let res = try await tool.execute(parameters: params)
            return encodeCompactResult(res, maxLength: 1600)
        } else {
            onActivity?("📌 Verificando tetos, envelopes e cotas...", "Consultando provisões restantes, tetos de categorias e gastos discricionários.")
            var params: [String: Any] = [:]
            if let m = arguments.month, !m.isEmpty { params["month"] = m }
            let capsTool = await MainActor.run { GetBudgetCapsStatusTool(store: store) }
            let discTool = await MainActor.run { AnalyzeDiscretionarySpendingTool(store: store) }
            let capsRes = try await capsTool.execute(parameters: params)
            let discRes = try await discTool.execute(parameters: arguments.month.map { ["referenceMonth": $0] } ?? [:])
            return encodeCompactResult(["capsAndQuotas": capsRes, "discretionaryTop": discRes], maxLength: 1650)
        }
    }
}

// MARK: - 7. Dívidas em Aberto & Estratégia + Investimentos

@available(macOS 26.0, *)
public struct AppleDebtsAndInvestmentsTool: FoundationModels.Tool, @unchecked Sendable {
    public let name = "get_debts_and_investments"
    public let description = "Analisa prazo e viabilidade para quitar dívidas em aberto e detalha carteira de investimentos / reservas."

    @Generable
    public struct Arguments {
        @Guide(description: "Nome da dívida específica opcional (ex: 'Mercado Pago')")
        public var debtQuery: String?
    }

    private let store: FinancialDataStore
    private let onActivity: AppleToolActivityHandler?

    public init(store: FinancialDataStore, onActivity: AppleToolActivityHandler?) {
        self.store = store
        self.onActivity = onActivity
    }

    public func call(arguments: Arguments) async throws -> String {
        onActivity?("💎 Analisando dívidas e carteira de investimentos...", "Calculando capacidade mensal de quitação e conferindo liquidez em investimentos.")
        let debtTool = await MainActor.run { AnalyzeDebtPayoffStrategyTool(store: store) }
        let invTool = await MainActor.run { GetInvestmentsSummaryTool(store: store) }
        let debtParams: [String: Any] = (arguments.debtQuery?.isEmpty == false) ? ["nameOrQuery": arguments.debtQuery!] : [:]
        let debtRes = try await debtTool.execute(parameters: debtParams)
        let invRes = try await invTool.execute(parameters: [:])
        return encodeCompactResult(["debtsStrategy": debtRes, "investments": invRes], maxLength: 1650)
    }
}

// MARK: - 8. Fallback Mandatório para Ações Externas Não Suportadas

@available(macOS 26.0, *)
public struct AppleUnsupportedCapabilityTool: FoundationModels.Tool, @unchecked Sendable {
    public let name = "unsupported_capability"
    public let description = "Chame quando o usuário pedir ação externa impossível no FinSense (comprar ações B3, fazer PIX, comprar cripto, contratar empréstimo)."

    @Generable
    public struct Arguments {
        @Guide(description: "O que o usuário pediu")
        public var requestedCapability: String
        @Guide(description: "Motivo resumido")
        public var reason: String
    }

    private let onActivity: AppleToolActivityHandler?

    public init(onActivity: AppleToolActivityHandler?) {
        self.onActivity = onActivity
    }

    public func call(arguments: Arguments) async throws -> String {
        onActivity?("⚠️ Registrando capacidade externa não suportada...", "Ação solicitada fora de escopo: \(arguments.requestedCapability)")
        let tool = await MainActor.run { UnsupportedCapabilityTool(registry: .shared) }
        let res = try await tool.execute(parameters: [
            "requestedCapability": arguments.requestedCapability,
            "reason": arguments.reason,
            "requiredData": "Integração financeira externa (B3 / Open Finance)"
        ])
        return encodeCompactResult(res, maxLength: 800)
    }
}
#endif
