import Foundation
#if canImport(FoundationModels)
import FoundationModels

@available(macOS 26.0, *)
public typealias AppleToolActivityHandler = @Sendable (_ stepLabel: String, _ thinkingLine: String) -> Void

// MARK: - Helper Compartilhado para Respostas Compactas na Janela de 4K

@available(macOS 26.0, *)
private func encodeCompactResult(_ dict: [String: Any], maxLength: Int = 2200) -> String {
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
            AppleQueryDatabaseTool(store: store, onActivity: onActivity),
            AppleCashFlowAndProjectionTool(store: store, onActivity: onActivity),
            AppleSimulateContractPlanTool(store: store, onActivity: onActivity),
            AppleTransactionsTool(store: store, onActivity: onActivity),
            AppleBudgetsDebtsAndCutsTool(store: store, onActivity: onActivity),
            AppleWebLookupTool(store: store, onActivity: onActivity),
            AppleUnsupportedCapabilityTool(onActivity: onActivity)
        ]
    }
}

// MARK: - 1. Acesso Completo ao Banco de Dados Local (10 Tabelas)

@available(macOS 26.0, *)
public struct AppleQueryDatabaseTool: FoundationModels.Tool, @unchecked Sendable {
    public let name = "query_database"
    public let description = "Lê qualquer tabela do FinSense: overview, kpi_summary (Saldo Previsto), accounts, contracts, amortization_plans, debts (abertas vs pagas), investments, transactions, provisions_and_quotas, categories."

    @Generable
    public struct Arguments {
        @Guide(description: "Tabela: overview, kpi_summary, accounts, contracts, amortization_plans, debts, investments, transactions, provisions_and_quotas ou categories")
        public var table: String
        @Guide(description: "Filtro textual opcional (ex: 'santander', 'emprestimos', 'caixa')")
        public var query: String?
        @Guide(description: "Mês YYYY-MM opcional (ex: '2026-11')")
        public var month: String?
    }

    private let store: FinancialDataStore
    private let onActivity: AppleToolActivityHandler?

    public init(store: FinancialDataStore, onActivity: AppleToolActivityHandler?) {
        self.store = store
        self.onActivity = onActivity
    }

    public func call(arguments: Arguments) async throws -> String {
        let tbl = arguments.table.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        onActivity?(
            "🗄️ Consultando tabela '\(tbl)' no banco FinSense...",
            "Lendo registros reais da tabela '\(tbl)'\(arguments.query.map { " (filtro: '\($0)')" } ?? "")."
        )
        var params: [String: Any] = ["table": tbl]
        if let q = arguments.query, !q.isEmpty { params["query"] = q }
        if let m = arguments.month, !m.isEmpty { params["month"] = m }

        let tool = await MainActor.run { QueryDatabaseTool(store: store) }
        let result = try await tool.execute(parameters: params)
        return encodeCompactResult(result, maxLength: 2300)
    }
}

// MARK: - 2. Fluxo de Caixa Mensal (com Saldo Previsto) & Projeções Futuras

@available(macOS 26.0, *)
public struct AppleCashFlowAndProjectionTool: FoundationModels.Tool, @unchecked Sendable {
    public let name = "get_cash_flow_and_projection"
    public let description = "Consulta Saldo Previsto, sobra após planejamento e fluxo de caixa do mês (YYYY-MM), ou projeta meses futuros (2 a 36 meses)."

    @Generable
    public struct Arguments {
        @Guide(description: "Modo: 'month' para fluxo e Saldo Previsto de um mês ou 'range' para projeção multi-mês")
        public var mode: String
        @Guide(description: "Mês YYYY-MM opcional")
        public var month: String?
        @Guide(description: "Número de meses futuros se mode='range'")
        public var monthsCount: Int?
    }

    private let store: FinancialDataStore
    private let onActivity: AppleToolActivityHandler?

    public init(store: FinancialDataStore, onActivity: AppleToolActivityHandler?) {
        self.store = store
        self.onActivity = onActivity
    }

    public func call(arguments: Arguments) async throws -> String {
        let mode = arguments.mode.lowercased()
        if mode == "range" {
            let count = arguments.monthsCount ?? 12
            onActivity?("📈 Projetando fluxo de caixa dos próximos \(count) meses...", "Executando projeção de receitas, despesas, Saldo Previsto e saldo acumulado para \(count) meses.")
            var params: [String: Any] = ["numberOfMonths": count]
            if let m = arguments.month, !m.isEmpty { params["startMonth"] = m }
            let tool = await MainActor.run { GetProjectedCashFlowRangeTool(store: store) }
            let res = try await tool.execute(parameters: params)
            return encodeCompactResult(res, maxLength: 2100)
        } else {
            let label = arguments.month ?? "mês ativo"
            onActivity?("💵 Consultando Saldo Previsto e fluxo de caixa (\(label))...", "Calculando receitas, despesas, provisões restantes, Sobra Após Planejamento e Saldo Previsto no fim do mês.")
            var params: [String: Any] = [:]
            if let m = arguments.month, !m.isEmpty { params["referenceDate"] = m }
            let tool = await MainActor.run { GetMonthlyCashFlowTool(store: store) }
            let res = try await tool.execute(parameters: params)
            return encodeCompactResult(res, maxLength: 2100)
        }
    }
}

// MARK: - 3. Simulação Completa via LoanProjectionEngine + Viabilidade no Saldo Previsto

@available(macOS 26.0, *)
public struct AppleSimulateContractPlanTool: FoundationModels.Tool, @unchecked Sendable {
    public let name = "simulate_contract_plan"
    public let description = "Consulta dados reais de um empréstimo/financiamento, verifica plano salvo e simula amortizações (cenários +500/mês, +1.000/mês, +2.000/mês ou valor customizado) validando Saldo Previsto."

    @Generable
    public struct Arguments {
        @Guide(description: "Nome, banco ou número do contrato (ex: 'Santander', 'Caixa', 'emprestimos')")
        public var contractQuery: String
        @Guide(description: "Valor extra mensal opcional em reais (omita para simular +500, +1.000 e +2.000/mês)")
        public var extraPayment: Double?
        @Guide(description: "Origem opcional: 'cash' ou 'fgts'")
        public var source: String?
    }

    private let store: FinancialDataStore
    private let onActivity: AppleToolActivityHandler?

    public init(store: FinancialDataStore, onActivity: AppleToolActivityHandler?) {
        self.store = store
        self.onActivity = onActivity
    }

    public func call(arguments: Arguments) async throws -> String {
        let q = arguments.contractQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let srcStr = (arguments.source ?? "cash").lowercased()

        onActivity?(
            "⚡ Analisando contrato e simulando cenários em '\(q.isEmpty ? "contratos" : q)'...",
            "Executando LoanProjectionEngine + verificação de Saldo Previsto para '\(q)'."
        )

        var detailsParams: [String: Any] = ["kind": "any"]
        if let uuid = UUID(uuidString: q) {
            detailsParams["contractId"] = uuid.uuidString
        } else if !q.isEmpty {
            detailsParams["nameOrQuery"] = q
        }

        let detailsTool = await MainActor.run { GetContractDetailsTool(store: store) }
        let detailsRes = try await detailsTool.execute(parameters: detailsParams)

        let matchedContracts = (detailsRes["contracts"] as? [[String: Any]]) ?? []
        if matchedContracts.isEmpty {
            return encodeCompactResult(detailsRes, maxLength: 2100)
        }

        let primaryContract = matchedContracts.first!
        let resolvedId = (primaryContract["id"] as? String) ?? ""
        let resolvedName = (primaryContract["name"] as? String) ?? q

        if matchedContracts.count > 1 && UUID(uuidString: q) == nil && (arguments.extraPayment ?? 0) <= 0 {
            let cashFlowTool = await MainActor.run { GetMonthlyCashFlowTool(store: store) }
            let cashRes = try? await cashFlowTool.execute(parameters: [:])
            let payload: [String: Any] = [
                "status": "multiple_contracts_found",
                "message": "Foram encontrados \(matchedContracts.count) contratos correspondentes. Informe os dados reais abaixo ao usuário e pergunte qual contrato deseja simular detalhadamente.",
                "contracts": matchedContracts,
                "cashFlowKPI": [
                    "saldoPrevistoFimDoMes": cashRes?["saldoPrevistoFimDoMes"] ?? 0.0,
                    "sobraAposPlanejamento": cashRes?["sobraAposPlanejamento"] ?? 0.0
                ]
            ]
            return encodeCompactResult(payload, maxLength: 2300)
        }

        let planTool = await MainActor.run { GetLoanProjectionAndPlanTool(store: store) }
        let savedPlanRes = try? await planTool.execute(parameters: ["contractId": resolvedId])

        let simTool = await MainActor.run { SimulateAmortizationTool(store: store) }
        let valuesToSimulate: [Double] = {
            if let custom = arguments.extraPayment, custom > 0 {
                return [custom]
            }
            return [500.0, 1000.0, 2000.0]
        }()

        var scenarios: [[String: Any]] = []
        for extra in valuesToSimulate {
            if srcStr == "fgts" {
                if let fgtsRes = try? await planTool.execute(parameters: [
                    "contractId": resolvedId,
                    "simulateMonthlyExtraAmount": extra,
                    "simulateSource": "fgts",
                    "simulateMode": "reduce_term"
                ]) {
                    scenarios.append([
                        "aporteExtraMensal": BRLFormatters.currency(extra),
                        "origem": "FGTS",
                        "parcelasEliminadasTotal": fgtsRes["monthsSaved"] ?? 0,
                        "novoPrazoRestanteMeses": fgtsRes["projectedActiveMonths"] ?? 0,
                        "prazoOriginalRestanteMeses": fgtsRes["originalRemainingMonths"] ?? 0,
                        "economiaTotalDeJurosNoContrato": BRLFormatters.currency((fgtsRes["totalInterestSaved"] as? Double) ?? 0.0),
                        "novaDataDeQuitacaoTotal": fgtsRes["projectedMaturityDate"] ?? "",
                        "alertasFGTS": fgtsRes["fgtsWarnings"] ?? []
                    ])
                }
            } else {
                let res = try await simTool.execute(parameters: [
                    "contractId": resolvedId,
                    "nameOrQuery": resolvedName,
                    "extraPayment": extra,
                    "mode": "reduce_term",
                    "recurringMonthly": true
                ])
                let rec = (res["recurringMonthlyProjection"] as? [String: Any]) ?? [:]
                let recMonths = (rec["monthsSavedWithPlan"] as? Int) ?? 0
                let recInterest = (rec["totalInterestSaved"] as? Double) ?? 0.0
                let expectedEndCash = (rec["expectedMonthEndCashBalanceAfterExtra"] as? Double) ?? (res["currentSaldoPrevistoFimDoMes"] as? Double) ?? 0.0
                scenarios.append([
                    "aporteExtraMensal": BRLFormatters.currency(extra),
                    "origem": "Dinheiro",
                    "parcelasEliminadasTotal": recMonths,
                    "novoPrazoRestanteMeses": rec["projectedMonthsWithPlan"] ?? res["newRemainingInstallments"] ?? 0,
                    "economiaTotalDeJurosNoContrato": BRLFormatters.currency(recInterest),
                    "novaDataDeQuitacaoTotal": rec["projectedPayoffDate"] ?? "",
                    "saldoPrevistoFimDoMesComEsseAporte": BRLFormatters.currency(expectedEndCash),
                    "viavelNoSaldoPrevisto": expectedEndCash >= 0
                ])
            }
        }

        let cashTool = await MainActor.run { GetMonthlyCashFlowTool(store: store) }
        let cashRes = try? await cashTool.execute(parameters: [:])

        let contractSummary: [String: Any] = [
            "id": resolvedId,
            "nome": resolvedName,
            "tipo": primaryContract["subtype"] ?? primaryContract["kind"] ?? "contrato",
            "numeroContrato": primaryContract["contractNumber"] ?? "",
            "saldoDevedorAtualHoje": BRLFormatters.currency((primaryContract["outstandingBalance"] as? Double) ?? 0.0),
            "valorParaQuitarHoje": BRLFormatters.currency((primaryContract["projectedPayoffToday"] as? Double) ?? (primaryContract["outstandingBalance"] as? Double) ?? 0.0),
            "valorDaParcelaMensal": BRLFormatters.currency((primaryContract["installmentAmount"] as? Double) ?? 0.0),
            "parcelasPagas": primaryContract["paidInstallmentsCount"] ?? 0,
            "parcelasRestantes": primaryContract["remainingInstallments"] ?? 0,
            "totalParcelas": primaryContract["totalInstallments"] ?? 0
        ]

        var combined: [String: Any] = [
            "status": "success",
            "contrato": contractSummary,
            "cenariosSimuladosComAportesMensais": scenarios,
            "viabilidadeCaixa": [
                "saldoEmContasHoje": BRLFormatters.currency((cashRes?["liquidCheckingBalanceNow"] as? Double) ?? 0.0),
                "saldoPrevistoFimDoMesAtual": BRLFormatters.currency((cashRes?["saldoPrevistoFimDoMes"] as? Double) ?? 0.0),
                "saldoPrevistoSemConsumirOrcamentos": BRLFormatters.currency((cashRes?["saldoPrevistoSemConsumirOrcamentos"] as? Double) ?? 0.0),
                "sobraMensalAposPlanejamento": BRLFormatters.currency((cashRes?["sobraAposPlanejamento"] as? Double) ?? 0.0)
            ]
        ]

        if let savedPlan = savedPlanRes, (savedPlan["hasSavedPlanOnDatabase"] as? Bool) == true {
            combined["planoDeAmortizacaoSalvoNoBanco"] = [
                "mesesEconomizados": savedPlan["monthsSaved"] ?? 0,
                "economiaTotalDeJurosNoContrato": BRLFormatters.currency((savedPlan["totalInterestSaved"] as? Double) ?? 0.0),
                "dataQuitacaoPrevista": savedPlan["projectedMaturityDate"] ?? "",
                "aportesPendentesCount": savedPlan["plannedItemsCount"] ?? 0
            ]
        }

        return encodeCompactResult(combined, maxLength: 2350)
    }
}

// MARK: - 4. Consulta & Analítica de Transações (Qualquer Período / Agrupamento)

@available(macOS 26.0, *)
public struct AppleTransactionsTool: FoundationModels.Tool, @unchecked Sendable {
    public let name = "query_and_aggregate_transactions"
    public let description = "Soma/agrupa transações por categoria, mês ou descrição, ou lista lançamentos individuais."

    @Generable
    public struct Arguments {
        @Guide(description: "Modo: 'summary' para totais agrupados ou 'list' para lançamentos")
        public var mode: String
        @Guide(description: "Mês específico YYYY-MM opcional")
        public var month: String?
        @Guide(description: "Texto de busca em descrição/categoria")
        public var query: String?
        @Guide(description: "Agrupamento para summary: category, month, account ou description")
        public var groupBy: String?
    }

    private let store: FinancialDataStore
    private let onActivity: AppleToolActivityHandler?

    public init(store: FinancialDataStore, onActivity: AppleToolActivityHandler?) {
        self.store = store
        self.onActivity = onActivity
    }

    public func call(arguments: Arguments) async throws -> String {
        let mode = arguments.mode.lowercased()
        var params: [String: Any] = [:]
        if let m = arguments.month, !m.isEmpty { params["month"] = m }
        if let q = arguments.query, !q.isEmpty { params["searchQuery"] = q }

        if mode == "list" {
            onActivity?("🧾 Listando lançamentos financeiros...", "Filtrando transações locais.")
            params["limit"] = 20
            let tool = await MainActor.run { QueryTransactionsTool(store: store) }
            let res = try await tool.execute(parameters: params)
            return encodeCompactResult(res, maxLength: 2100)
        } else {
            onActivity?("🔍 Agregando e somando transações...", "Consolidando transações agrupadas por \(arguments.groupBy ?? "category").")
            if let g = arguments.groupBy, !g.isEmpty { params["groupBy"] = g }
            let tool = await MainActor.run { AggregateTransactionsTool(store: store) }
            let res = try await tool.execute(parameters: params)
            return encodeCompactResult(res, maxLength: 2100)
        }
    }
}

// MARK: - 5. Orçamentos, Cortes Discricionários, Dívidas em Aberto e Investimentos

@available(macOS 26.0, *)
public struct AppleBudgetsDebtsAndCutsTool: FoundationModels.Tool, @unchecked Sendable {
    public let name = "analyze_budgets_debts_and_cuts"
    public let description = "Consulta dívidas em aberto reais (somente isPaid == false), investimentos, tetos/cotas e sugestões de corte considerando o Saldo Previsto."

    @Generable
    public struct Arguments {
        @Guide(description: "Foco: 'debts', 'budgets', 'cuts' ou 'all'")
        public var focus: String
        @Guide(description: "Nome da dívida específica opcional")
        public var debtQuery: String?
        @Guide(description: "Meta mensal opcional em reais para cortes")
        public var targetMonthlyAmount: Double?
    }

    private let store: FinancialDataStore
    private let onActivity: AppleToolActivityHandler?

    public init(store: FinancialDataStore, onActivity: AppleToolActivityHandler?) {
        self.store = store
        self.onActivity = onActivity
    }

    public func call(arguments: Arguments) async throws -> String {
        let focus = arguments.focus.lowercased()
        var output: [String: Any] = [:]

        if focus == "cuts" || (arguments.targetMonthlyAmount ?? 0) > 0 {
            let target = arguments.targetMonthlyAmount ?? 0
            onActivity?("✂️ Analisando cortes de gastos...", "Avaliando gastos discricionários e impacto no Saldo Previsto.")
            let discTool = await MainActor.run { AnalyzeDiscretionarySpendingTool(store: store) }
            output["discretionaryCuts"] = try await discTool.execute(parameters: ["targetExtraPayment": target])
        }

        if focus == "all" || focus == "budgets" {
            onActivity?("📌 Consultando tetos e cotas de orçamento...", "Lendo envelopes e cotas específicas do mês.")
            let capsTool = await MainActor.run { GetBudgetCapsStatusTool(store: store) }
            output["budgetsAndQuotas"] = try await capsTool.execute(parameters: [:])
        }

        if focus == "all" || focus == "debts" || (arguments.debtQuery?.isEmpty == false) {
            onActivity?("💎 Analisando dívidas em aberto e investimentos...", "Consultando exclusivamente dívidas pendentes (isPaid == false), Saldo Previsto e liquidez em investimentos.")
            let debtTool = await MainActor.run { AnalyzeDebtPayoffStrategyTool(store: store) }
            let invTool = await MainActor.run { GetInvestmentsSummaryTool(store: store) }
            let debtParams: [String: Any] = (arguments.debtQuery?.isEmpty == false) ? ["nameOrQuery": arguments.debtQuery!] : [:]
            output["debtsAnalysis"] = try await debtTool.execute(parameters: debtParams)
            output["investmentsSummary"] = try await invTool.execute(parameters: [:])
        }

        return encodeCompactResult(output, maxLength: 2300)
    }
}

// MARK: - 6. Consultas Web (Somente Leitura) & Fallback Mandatório

@available(macOS 26.0, *)
public struct AppleWebLookupTool: FoundationModels.Tool, @unchecked Sendable {
    public let name = "internet_lookup"
    public let description = "Busca informações públicas na internet (Dólar, Euro, Bitcoin, Selic, CDI, IPCA e conceitos de investimento). Somente leitura: não envia nenhum dado pessoal ou valor financeiro."

    @Generable
    public struct Arguments {
        @Guide(description: "Termo público de busca sem valores pessoais (ex: 'dolar hoje', 'selic e cdi', 'tesouro selic vs cdb')")
        public var query: String
        @Guide(description: "Categoria opcional: currency, economic_rates, investment_info ou general")
        public var topic: String?
    }

    private let store: FinancialDataStore
    private let onActivity: AppleToolActivityHandler?

    public init(store: FinancialDataStore, onActivity: AppleToolActivityHandler?) {
        self.store = store
        self.onActivity = onActivity
    }

    public func call(arguments: Arguments) async throws -> String {
        onActivity?(
            "🌐 Consultando dados públicos na internet (somente leitura)...",
            "Buscando cotação/índice ou referência pública para '\(InternetLookupService.sanitizePublicQuery(arguments.query))' sem enviar dados pessoais."
        )
        let tool = await MainActor.run { InternetLookupTool(store: store) }
        var params: [String: Any] = ["query": arguments.query]
        if let t = arguments.topic, !t.isEmpty { params["topic"] = t }
        let res = try await tool.execute(parameters: params)
        return encodeCompactResult(res, maxLength: 2300)
    }
}

@available(macOS 26.0, *)
public struct AppleUnsupportedCapabilityTool: FoundationModels.Tool, @unchecked Sendable {
    public let name = "unsupported_capability"
    public let description = "Registra ação externa impossível no FinSense (comprar ações B3, fazer PIX, comprar cripto, contratar novo empréstimo)."

    @Generable
    public struct Arguments {
        @Guide(description: "Pedido externo do usuário")
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
