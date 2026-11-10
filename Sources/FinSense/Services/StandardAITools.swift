import Foundation

// MARK: - Helper de Formatação de Prazo

private func formatEliminatedMonthsString(_ count: Int) -> String {
    let y = count / 12
    let m = count % 12
    if y > 0 && m > 0 {
        return "\(count) meses (\(y) \(y == 1 ? "ano" : "anos") e \(m) \(m == 1 ? "mês" : "meses"))"
    } else if y > 0 {
        return "\(count) meses (\(y) \(y == 1 ? "ano" : "anos"))"
    } else {
        return "\(count) \(count == 1 ? "mês" : "meses")"
    }
}

// MARK: - 1. Tool: get_contract_details

@MainActor
public struct GetContractDetailsTool: AIToolProtocol {
    public let name: String = "get_contract_details"
    public let description: String = "Consulta dados cadastrais, financeiros e técnicos de contratos ativos (financiamento imobiliário, empréstimo convencional/consignado ou dívidas)."

    public let parametersSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "contractId": [
                "type": "string",
                "description": "ID UUID opcional do contrato ou dívida específica"
            ],
            "nameOrQuery": [
                "type": "string",
                "description": "Nome ou termo de busca do contrato (ex: 'caixa', 'habitação', 'santander', 'consignado', 'mercado pago')"
            ],
            "kind": [
                "type": "string",
                "enum": ["financing", "loan", "debt", "any"],
                "description": "Filtro pelo tipo de contrato: financing, loan, debt ou any"
            ]
        ]
    ]

    private let store: FinancialDataStore

    public init(store: FinancialDataStore) {
        self.store = store
    }

    public func execute(parameters: [String: Any]) async throws -> [String: Any] {
        let contractIdStr = parameters["contractId"] as? String
        let query = (parameters["nameOrQuery"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let kind = (parameters["kind"] as? String)?.lowercased() ?? "any"

        // Busca em Contratos de Financiamento e Empréstimo
        var matchedContracts = store.contracts.filter { !$0.isSettled }
        if kind == "financing" {
            matchedContracts = matchedContracts.filter { $0.kind == .financing }
        } else if kind == "loan" {
            matchedContracts = matchedContracts.filter { $0.kind == .loan }
        }

        if let contractIdStr, let uuid = UUID(uuidString: contractIdStr) {
            matchedContracts = matchedContracts.filter { $0.id == uuid }
        } else if let q = query, !q.isEmpty {
            matchedContracts = matchedContracts.filter {
                $0.name.lowercased().contains(q) ||
                ($0.contractNumber?.lowercased().contains(q) ?? false) ||
                $0.subtypeDisplayName.lowercased().contains(q)
            }
        }

        // Busca em Dívidas se aplicável
        var matchedDebts = store.activeDebts
        if kind == "financing" || kind == "loan" {
            matchedDebts = []
        } else if let contractIdStr, let uuid = UUID(uuidString: contractIdStr) {
            matchedDebts = matchedDebts.filter { $0.id == uuid }
        } else if let q = query, !q.isEmpty {
            matchedDebts = matchedDebts.filter { $0.name.lowercased().contains(q) }
        }

        var resultsList: [[String: Any]] = []

        for c in matchedContracts {
            let payoff = store.projectedPayoffAmount(for: c)
            let remainingCount = store.remainingInstallmentsCount(for: c)
            var dict: [String: Any] = [
                "id": c.id.uuidString,
                "name": c.name,
                "kind": c.kind.rawValue,
                "subtype": c.subtypeDisplayName,
                "contractNumber": c.contractNumber as Any,
                "outstandingBalance": c.outstandingBalance as Any,
                "totalContractedAmount": c.totalContractedAmount,
                "installmentAmount": c.installmentAmount,
                "remainingInstallments": remainingCount,
                "totalInstallments": c.totalInstallments,
                "projectedPayoffToday": payoff,
                "estimatedDiscountOnPayoff": max(0.0, (Double(remainingCount) * c.installmentAmount) - payoff),
                "isSettled": c.isSettled
            ]

            if c.kind == .financing {
                dict["amortizationSystem"] = c.amortizationSystem.rawValue
                dict["indexationRate"] = c.indexationRate?.rawValue ?? "TR"
                dict["annualNominalRate"] = c.effectiveAnnualNominalRate
                dict["monthlyNominalRatePercent"] = c.effectiveMonthlyNominalRateDecimal * 100.0
                dict["basePriceInstallment"] = c.effectiveBaseInstallmentPrice
                dict["adminFee"] = c.effectiveAdminFee
                dict["insuranceFee"] = c.effectiveInsuranceFee
                dict["extraAmortizedTotal"] = c.extraAmortizedTotal
                dict["originalTotalInstallments"] = c.originalTotalInstallments as Any
            } else {
                dict["monthlyInterestRatePercent"] = c.monthlyInterestRate
                dict["isPayrollDeductible"] = c.effectiveLoanModel?.isPayrollDeductible ?? false
                dict["paidInstallmentsCount"] = store.paidTransactionsCount(forContract: c)
            }
            resultsList.append(dict)
        }

        for d in matchedDebts {
            resultsList.append([
                "id": d.id.uuidString,
                "name": d.name,
                "kind": "debt",
                "subtype": "Dívida em Aberto / Acordo",
                "outstandingBalance": d.originalAmount,
                "originalAmount": d.originalAmount,
                "contractedDate": d.contractedDate.map { BRLFormatters.shortDate($0) } ?? "Não informada",
                "notes": d.notes,
                "isPaid": d.isPaid
            ])
        }

        if resultsList.isEmpty {
            let availableContracts = store.contracts.filter { !$0.isSettled }.map { "\($0.name) (\($0.subtypeDisplayName))" }
            let availableDebts = store.activeDebts.map { $0.name }
            return [
                "status": "not_found",
                "message": "Nenhum contrato ou dívida encontrado para a busca especificada.",
                "availableContracts": availableContracts,
                "availableDebts": availableDebts
            ]
        }

        return [
            "status": "success",
            "count": resultsList.count,
            "contracts": resultsList
        ]
    }
}

// MARK: - 2. Tool: simulate_amortization

@MainActor
public struct SimulateAmortizationTool: AIToolProtocol {
    public let name: String = "simulate_amortization"
    public let description: String = "Aciona a engine de amortização em modo simulação (dry-run) para testar pagamentos extraordinários na Tabela Price com redução de prazo ou de parcela, sem alterar os dados reais."

    public let parametersSchema: [String: Any] = [
        "type": "object",
        "required": ["extraPayment"],
        "properties": [
            "extraPayment": [
                "type": "number",
                "description": "Valor monetário a ser amortizado extraordinariamente (ex: 2000.0, 5000.0, 10000.0)"
            ],
            "contractId": [
                "type": "string",
                "description": "ID UUID opcional do contrato a amortizar"
            ],
            "nameOrQuery": [
                "type": "string",
                "description": "Nome ou termo para identificar o contrato (ex: 'caixa', 'habitação', 'empréstimo')"
            ],
            "mode": [
                "type": "string",
                "enum": ["reduce_term", "reduce_installment"],
                "description": "Modo de recálculo: 'reduce_term' para reduzir prazo (padrão) ou 'reduce_installment' para reduzir o valor da parcela mensal"
            ],
            "proRataInterest": [
                "type": "number",
                "description": "Juros pro-rata opcionais decorridos entre o vencimento e o pagamento (padrão 0.0)"
            ]
        ]
    ]

    private let store: FinancialDataStore

    public init(store: FinancialDataStore) {
        self.store = store
    }

    public func execute(parameters: [String: Any]) async throws -> [String: Any] {
        guard let extraPayment = parameters["extraPayment"] as? Double ?? (parameters["extraPayment"] as? NSNumber)?.doubleValue,
              extraPayment > 0 else {
            return [
                "status": "error",
                "error": "O parâmetro 'extraPayment' deve ser um número positivo maior que zero."
            ]
        }

        let modeStr = (parameters["mode"] as? String)?.lowercased() ?? "reduce_term"
        let recalcMode: AmortizationRecalculationMode = (modeStr == "reduce_installment") ? .reduceInstallment : .reduceTerm
        let proRata = (parameters["proRataInterest"] as? Double) ?? (parameters["proRataInterest"] as? NSNumber)?.doubleValue ?? 0.0
        let contractIdStr = parameters["contractId"] as? String
        let query = (parameters["nameOrQuery"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // Localiza contrato ativo
        var candidates = store.contracts.filter { !$0.isSettled }
        if let contractIdStr, let uuid = UUID(uuidString: contractIdStr) {
            candidates = candidates.filter { $0.id == uuid }
        } else if let q = query, !q.isEmpty {
            candidates = candidates.filter {
                $0.name.lowercased().contains(q) || $0.subtypeDisplayName.lowercased().contains(q)
            }
        }

        guard let contract = candidates.first else {
            let activeList = store.contracts.filter { !$0.isSettled }.map { ["id": $0.id.uuidString, "name": $0.name, "kind": $0.kind.rawValue] }
            return [
                "status": "contract_not_found",
                "error": "Não foi possível identificar o contrato para simulação.",
                "availableContracts": activeList
            ]
        }

        let prevRem = store.remainingInstallmentsCount(for: contract)
        let currentPV = store.currentOutstandingBalance(for: contract)

        if contract.kind == .financing {
            let sim = AmortizationEngine.simulateExtraAmortization(
                currentBalance: currentPV,
                annualNominalRate: contract.effectiveAnnualNominalRate,
                basePriceInstallment: contract.effectiveBaseInstallmentPrice,
                totalInstallmentAmount: contract.installmentAmount,
                currentRemainingInstallments: prevRem,
                extraPayment: extraPayment,
                proRataInterest: proRata,
                mode: recalcMode,
                adminFee: contract.effectiveAdminFee,
                insuranceFee: contract.effectiveInsuranceFee
            )
            return [
                "status": "success",
                "contractId": contract.id.uuidString,
                "contractName": contract.name,
                "contractKind": "financing",
                "mode": recalcMode.rawValue,
                "grossPayment": sim.grossPayment,
                "proRataInterest": sim.proRataInterest,
                "effectiveAmortization": sim.effectiveAmortization,
                "previousBalance": sim.previousBalance,
                "newBalance": sim.newBalance,
                "previousRemainingInstallments": sim.previousRemainingInstallments,
                "newRemainingInstallments": sim.newRemainingInstallments,
                "eliminatedInstallmentsCount": sim.eliminatedInstallmentsCount,
                "previousInstallmentAmount": sim.previousInstallmentAmount,
                "newInstallmentAmount": sim.newInstallmentAmount,
                "estimatedTotalInterestSaved": sim.estimatedTotalInterestSaved,
                "savedTimeString": formatEliminatedMonthsString(sim.eliminatedInstallmentsCount)
            ]
        } else {
            let sim = LoanAmortizationEngine.simulateExtraAmortization(
                currentBalance: currentPV,
                monthlyInterestRate: contract.monthlyInterestRate,
                installmentValue: contract.installmentAmount,
                currentRemainingInstallments: prevRem,
                extraPayment: extraPayment,
                proRataInterest: proRata,
                mode: recalcMode
            )
            return [
                "status": "success",
                "contractId": contract.id.uuidString,
                "contractName": contract.name,
                "contractKind": "loan",
                "mode": recalcMode.rawValue,
                "grossPayment": sim.grossPayment,
                "proRataInterest": sim.proRataInterest,
                "effectiveAmortization": sim.effectiveAmortization,
                "previousBalance": sim.previousBalance,
                "newBalance": sim.newBalance,
                "previousRemainingInstallments": sim.previousRemainingInstallments,
                "newRemainingInstallments": sim.newRemainingInstallments,
                "eliminatedInstallmentsCount": sim.eliminatedInstallmentsCount,
                "previousInstallmentAmount": sim.previousInstallmentAmount,
                "newInstallmentAmount": sim.newInstallmentAmount,
                "estimatedTotalInterestSaved": sim.estimatedTotalInterestSaved,
                "savedTimeString": formatEliminatedMonthsString(sim.eliminatedInstallmentsCount)
            ]
        }
    }
}

// MARK: - 3. Tool: get_monthly_cash_flow

@MainActor
public struct GetMonthlyCashFlowTool: AIToolProtocol {
    public let name: String = "get_monthly_cash_flow"
    public let description: String = "Consulta receitas, despesas, balanço operacional, sobra líquida real e saldo livre em contas para determinado mês ou mês ativo."

    public let parametersSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "month": [
                "type": "integer",
                "description": "Número do mês de 1 a 12 (opcional)"
            ],
            "year": [
                "type": "integer",
                "description": "Ano de referência, ex: 2026 (opcional)"
            ],
            "referenceDate": [
                "type": "string",
                "description": "Data no formato 'YYYY-MM' ou 'YYYY-MM-DD' (opcional)"
            ]
        ]
    ]

    private let store: FinancialDataStore

    public init(store: FinancialDataStore) {
        self.store = store
    }

    public func execute(parameters: [String: Any]) async throws -> [String: Any] {
        let cal = Calendar.current
        var targetDate = store.selectedMonth

        if let refStr = parameters["referenceDate"] as? String {
            let parts = refStr.split(separator: "-").compactMap { Int($0) }
            if parts.count >= 2 {
                var comp = DateComponents()
                comp.year = parts[0]
                comp.month = parts[1]
                comp.day = 1
                if let d = cal.date(from: comp) {
                    targetDate = d
                }
            }
        } else if let m = (parameters["month"] as? Int) ?? (parameters["month"] as? NSNumber)?.intValue,
                  let y = (parameters["year"] as? Int) ?? (parameters["year"] as? NSNumber)?.intValue {
            var comp = DateComponents()
            comp.year = y
            comp.month = m
            comp.day = 1
            if let d = cal.date(from: comp) {
                targetDate = d
            }
        }

        let incomeTotal = store.monthlyIncome(for: targetDate, onlyPaid: false)
        let incomeReceived = store.monthlyReceivedIncome(for: targetDate)
        let incomePending = store.monthlyPendingIncome(for: targetDate)

        let expenseTotal = store.monthlyExpense(for: targetDate, onlyPaid: false)
        let expensePaid = store.monthlyPaidExpense(for: targetDate)
        let expensePending = store.monthlyPendingExpense(for: targetDate)

        let operationalNet = incomeTotal - expenseTotal
        let savingsRate = incomeTotal > 0 ? (operationalNet / incomeTotal) * 100.0 : 0.0

        let remainingProvisions = store.totalRemainingProvision(for: targetDate)
        let checkingNow = store.totalCheckingBalanceNow
        let investedNow = store.totalInvestmentsBalance
        let patrimonyNow = store.totalConsolidatedPatrimonyNow
        let isPast = store.isMonthPriorToCurrent(targetDate)

        return [
            "status": "success",
            "monthReference": BRLFormatters.monthYear(targetDate),
            "isClosedMonth": isPast,
            "income": [
                "total": incomeTotal,
                "received": incomeReceived,
                "pending": incomePending
            ],
            "expense": [
                "total": expenseTotal,
                "paid": expensePaid,
                "pending": expensePending
            ],
            "operationalBalance": operationalNet,
            "savingsRatePercent": savingsRate,
            "remainingBudgetCaps": isPast ? 0.0 : remainingProvisions,
            "liquidCheckingBalanceNow": checkingNow,
            "investmentsBalanceNow": investedNow,
            "totalPatrimonyNow": patrimonyNow,
            "projectedMonthEndCash": store.accumulatedConsolidatedBalance(throughMonth: targetDate)
        ]
    }
}

// MARK: - 4. Tool: get_projected_cash_flow_range

@MainActor
public struct GetProjectedCashFlowRangeTool: AIToolProtocol {
    public let name: String = "get_projected_cash_flow_range"
    public let description: String = "Consulta a projeção mês a mês de fluxo de caixa para horizontes futuros (receitas projetadas, despesas, parcelas de contratos, balanço mensal e saldo acumulado)."

    public let parametersSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "startMonth": [
                "type": "string",
                "description": "Mês inicial no formato 'YYYY-MM' (opcional, padrão: mês ativo)"
            ],
            "numberOfMonths": [
                "type": "integer",
                "description": "Quantidade de meses a projetar (mínimo 2, máximo 36, padrão 12)"
            ]
        ]
    ]

    private let store: FinancialDataStore

    public init(store: FinancialDataStore) {
        self.store = store
    }

    public func execute(parameters: [String: Any]) async throws -> [String: Any] {
        let cal = Calendar.current
        var startDate = store.selectedMonth

        if let startStr = parameters["startMonth"] as? String {
            let parts = startStr.split(separator: "-").compactMap { Int($0) }
            if parts.count >= 2 {
                var comp = DateComponents()
                comp.year = parts[0]
                comp.month = parts[1]
                comp.day = 1
                if let d = cal.date(from: comp) {
                    startDate = d
                }
            }
        }

        let rawMonths = (parameters["numberOfMonths"] as? Int) ?? (parameters["numberOfMonths"] as? NSNumber)?.intValue ?? 12
        let count = max(2, min(rawMonths, 36))

        if let horizonDate = cal.date(byAdding: .month, value: count + 1, to: startDate) {
            store.ensureRecurringTransactionsMaterialized(upTo: horizonDate)
        }

        var monthsArray: [[String: Any]] = []
        var firstDeficitMonth: String? = nil
        var minBalance: Double = Double.greatestFiniteMagnitude
        var sumNet: Double = 0.0

        for i in 0..<count {
            guard let cur = cal.date(byAdding: .month, value: i, to: startDate) else { continue }
            let monthLabel = BRLFormatters.monthYear(cur)
            let income = store.monthlyIncome(for: cur)
            let expense = store.projectedMonthlyExpense(for: cur)
            let net = store.projectedMonthlyNetBalance(for: cur)
            let accum = store.accumulatedConsolidatedBalance(throughMonth: cur)

            sumNet += net
            if accum < minBalance {
                minBalance = accum
            }
            if accum < 0 && firstDeficitMonth == nil {
                firstDeficitMonth = monthLabel
            }

            monthsArray.append([
                "month": monthLabel,
                "projectedIncome": income,
                "projectedExpense": expense,
                "projectedNet": net,
                "accumulatedBalanceEnd": accum
            ])
        }

        return [
            "status": "success",
            "monthsProjectedCount": monthsArray.count,
            "firstMonth": monthsArray.first?["month"] ?? "",
            "lastMonth": monthsArray.last?["month"] ?? "",
            "averageMonthlyNet": sumNet / Double(max(monthsArray.count, 1)),
            "lowestProjectedBalance": minBalance == Double.greatestFiniteMagnitude ? 0.0 : minBalance,
            "firstDeficitMonth": firstDeficitMonth as Any,
            "hasRunwayRisk": firstDeficitMonth != nil,
            "timeline": monthsArray
        ]
    }
}

// MARK: - 5. Tool: analyze_discretionary_spending

@MainActor
public struct AnalyzeDiscretionarySpendingTool: AIToolProtocol {
    public let name: String = "analyze_discretionary_spending"
    public let description: String = "Agrupa e analisa gastos de consumo discricionário (supermercado, alimentação, delivery, lazer, compras avulsas) e aponta oportunidades de corte para viabilizar metas de amortização ou reserva."

    public let parametersSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "referenceMonth": [
                "type": "string",
                "description": "Mês no formato 'YYYY-MM' (opcional, padrão: mês ativo)"
            ],
            "targetExtraPayment": [
                "type": "number",
                "description": "Valor monetário alvo que o usuário deseja alcançar para amortizar ou poupar (ex: 2000.0)"
            ]
        ]
    ]

    private let store: FinancialDataStore

    public init(store: FinancialDataStore) {
        self.store = store
    }

    public func execute(parameters: [String: Any]) async throws -> [String: Any] {
        let cal = Calendar.current
        var targetDate = store.selectedMonth

        if let refStr = parameters["referenceMonth"] as? String {
            let parts = refStr.split(separator: "-").compactMap { Int($0) }
            if parts.count >= 2 {
                var comp = DateComponents()
                comp.year = parts[0]
                comp.month = parts[1]
                comp.day = 1
                if let d = cal.date(from: comp) {
                    targetDate = d
                }
            }
        }

        let targetExtra = (parameters["targetExtraPayment"] as? Double) ?? (parameters["targetExtraPayment"] as? NSNumber)?.doubleValue ?? 0.0

        let monthTxs = store.transactionsForMonth(targetDate).filter { $0.type == .expense && !$0.ignoreInConsolidated }
        let totalExpense = monthTxs.reduce(0.0) { $0 + $1.amount }

        let essentialKeywords: Set<String> = [
            "moradia", "aluguel", "condominio", "iptu", "financiamento", "habitacao",
            "saude", "medico", "farmacia", "convenio", "educacao", "faculdade", "escola"
        ]

        var categoryTotals: [UUID: Double] = [:]
        for tx in monthTxs {
            categoryTotals[tx.categoryId, default: 0.0] += tx.amount
        }

        var discretionaryList: [(cat: CategoryItem, total: Double)] = []
        var essentialTotal: Double = 0.0

        for (catId, sumAmount) in categoryTotals {
            guard let cat = store.category(for: catId) else { continue }
            let nameNorm = cat.name.lowercased()
            let isEssential = essentialKeywords.contains { nameNorm.contains($0) }
            if isEssential {
                essentialTotal += sumAmount
            } else {
                discretionaryList.append((cat, sumAmount))
            }
        }

        discretionaryList.sort { $0.total > $1.total }
        let discretionaryTotal = discretionaryList.reduce(0.0) { $0 + $1.total }

        let topCatsJson: [[String: Any]] = discretionaryList.prefix(8).map { item in
            [
                "category": item.cat.name,
                "amount": item.total,
                "percentageOfTotal": totalExpense > 0 ? (item.total / totalExpense) * 100.0 : 0.0,
                "cutScenario15Percent": item.total * 0.15,
                "cutScenario25Percent": item.total * 0.25,
                "cutScenario35Percent": item.total * 0.35
            ]
        }

        let cut15Total = discretionaryTotal * 0.15
        let cut25Total = discretionaryTotal * 0.25
        let cut35Total = discretionaryTotal * 0.35

        let currentIncome = store.monthlyIncome(for: targetDate)
        let currentOperationalSurplus = max(0.0, currentIncome - totalExpense)

        var plansJson: [String: Any] = [:]
        if targetExtra > 0 {
            let neededBeyondSurplus = max(0.0, targetExtra - currentOperationalSurplus)
            plansJson = [
                "targetAmount": targetExtra,
                "currentOperationalSurplus": currentOperationalSurplus,
                "neededFromBudgetOptimization": neededBeyondSurplus,
                "isAlreadyCoveredByCurrentSurplus": currentOperationalSurplus >= targetExtra,
                "coverageWith15PercentCut": (currentOperationalSurplus + cut15Total) >= targetExtra,
                "coverageWith25PercentCut": (currentOperationalSurplus + cut25Total) >= targetExtra,
                "coverageWith35PercentCut": (currentOperationalSurplus + cut35Total) >= targetExtra
            ]
        }

        return [
            "status": "success",
            "monthReference": BRLFormatters.monthYear(targetDate),
            "totalExpenses": totalExpense,
            "essentialExpensesTotal": essentialTotal,
            "discretionaryExpensesTotal": discretionaryTotal,
            "discretionarySharePercent": totalExpense > 0 ? (discretionaryTotal / totalExpense) * 100.0 : 0.0,
            "topDiscretionaryCategories": topCatsJson,
            "aggregateCutScenarios": [
                "cut15Percent": cut15Total,
                "cut25Percent": cut25Total,
                "cut35Percent": cut35Total
            ],
            "targetPaymentAnalysis": plansJson
        ]
    }
}

// MARK: - 6. Tool: get_budget_caps_status

@MainActor
public struct GetBudgetCapsStatusTool: AIToolProtocol {
    public let name: String = "get_budget_caps_status"
    public let description: String = "Consulta o consumo real de tetos orçamentários por categoria (envelopes de verba livre) e cotas específicas de consumo no mês ativo."

    public let parametersSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "month": [
                "type": "string",
                "description": "Mês no formato 'YYYY-MM' (opcional, padrão: mês ativo)"
            ]
        ]
    ]

    private let store: FinancialDataStore

    public init(store: FinancialDataStore) {
        self.store = store
    }

    public func execute(parameters: [String: Any]) async throws -> [String: Any] {
        let cal = Calendar.current
        var targetDate = store.selectedMonth

        if let refStr = parameters["month"] as? String {
            let parts = refStr.split(separator: "-").compactMap { Int($0) }
            if parts.count >= 2 {
                var comp = DateComponents()
                comp.year = parts[0]
                comp.month = parts[1]
                comp.day = 1
                if let d = cal.date(from: comp) {
                    targetDate = d
                }
            }
        }

        let envelopes = store.provisionEnvelopes(for: targetDate)
        let quotas = store.allQuotaEnvelopes(for: targetDate)

        let envelopesJson: [[String: Any]] = envelopes.map { env in
            [
                "category": env.category.name,
                "estimatedAmount": env.estimatedAmount,
                "realizedExpense": env.realizedExpense,
                "remainingProvision": env.remainingProvision,
                "progressPercent": env.clampedProgressPercentage,
                "status": env.status.rawValue,
                "isRecurring": env.repeatForFutureMonths
            ]
        }

        let quotasJson: [[String: Any]] = quotas.map { q in
            let catName = store.category(for: q.categoryId)?.name ?? "Geral"
            return [
                "quotaName": q.name,
                "category": catName,
                "plannedQuantity": q.plannedQuantity,
                "consumedUnits": q.consumedUnits,
                "pendingUnits": q.pendingUnits,
                "estimatedUnitPrice": q.estimatedUnitPrice,
                "remainingProvision": q.remainingProvision,
                "totalEstimatedAmount": q.totalEstimatedAmount,
                "status": q.status.rawValue
            ]
        }

        return [
            "status": "success",
            "monthReference": BRLFormatters.monthYear(targetDate),
            "totalCategoryCapsRemaining": store.totalCategoryProvisionsRemaining(for: targetDate),
            "totalCategoryQuotasRemaining": store.totalQuotasRemaining(for: targetDate),
            "grandTotalProvisionsRemaining": store.totalRemainingProvision(for: targetDate),
            "envelopes": envelopesJson,
            "quotas": quotasJson
        ]
    }
}

// MARK: - 7. Tool: query_transactions

@MainActor
public struct QueryTransactionsTool: AIToolProtocol {
    public let name: String = "query_transactions"
    public let description: String = "Filtra e consulta lançamentos financeiros da base por período, categoria, conta, tipo ou status de pagamento."

    public let parametersSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "searchQuery": [
                "type": "string",
                "description": "Termo de busca na descrição ou detalhes da transação (opcional)"
            ],
            "categoryName": [
                "type": "string",
                "description": "Nome da categoria para filtrar (opcional)"
            ],
            "type": [
                "type": "string",
                "enum": ["expense", "income", "all"],
                "description": "Filtro de tipo: expense, income ou all"
            ],
            "isPaid": [
                "type": "boolean",
                "description": "Filtro pelo status de pagamento (true = realizada, false = pendente)"
            ],
            "month": [
                "type": "string",
                "description": "Mês no formato 'YYYY-MM' (opcional)"
            ],
            "limit": [
                "type": "integer",
                "description": "Limite máximo de registros a retornar (padrão 10, máximo 50)"
            ]
        ]
    ]

    private let store: FinancialDataStore

    public init(store: FinancialDataStore) {
        self.store = store
    }

    public func execute(parameters: [String: Any]) async throws -> [String: Any] {
        var txs = store.transactions.filter { !$0.ignoreInConsolidated }

        if let typeStr = parameters["type"] as? String {
            if typeStr == "expense" {
                txs = txs.filter { $0.type == .expense }
            } else if typeStr == "income" {
                txs = txs.filter { $0.type == .income }
            }
        }

        if let isPaid = parameters["isPaid"] as? Bool {
            txs = txs.filter { $0.isPaid == isPaid }
        }

        if let catName = (parameters["categoryName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !catName.isEmpty {
            txs = txs.filter { tx in
                guard let cat = store.category(for: tx.categoryId) else { return false }
                return cat.name.lowercased().contains(catName)
            }
        }

        if let q = (parameters["searchQuery"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !q.isEmpty {
            txs = txs.filter {
                $0.name.lowercased().contains(q) || $0.details.lowercased().contains(q)
            }
        }

        if let monthStr = parameters["month"] as? String {
            let cal = Calendar.current
            let parts = monthStr.split(separator: "-").compactMap { Int($0) }
            if parts.count >= 2 {
                txs = txs.filter {
                    let cYear = cal.component(.year, from: $0.date)
                    let cMonth = cal.component(.month, from: $0.date)
                    return cYear == parts[0] && cMonth == parts[1]
                }
            }
        }

        txs.sort { $0.date > $1.date }

        let limit = min(max((parameters["limit"] as? Int) ?? (parameters["limit"] as? NSNumber)?.intValue ?? 10, 1), 50)
        let totalCount = txs.count
        let sumAmount = txs.reduce(0.0) { $0 + $1.amount }

        let sliced = txs.prefix(limit).map { tx -> [String: Any] in
            let catName = store.category(for: tx.categoryId)?.name ?? "Sem Categoria"
            let accName = store.account(for: tx.accountId)?.name ?? "Conta"
            return [
                "id": tx.id.uuidString,
                "date": BRLFormatters.shortDate(tx.date),
                "description": tx.name,
                "amount": tx.amount,
                "type": tx.type.rawValue,
                "category": catName,
                "account": accName,
                "isPaid": tx.isPaid
            ]
        }

        return [
            "status": "success",
            "totalCount": totalCount,
            "returnedCount": sliced.count,
            "totalAmountSum": sumAmount,
            "transactions": sliced
        ]
    }
}

// MARK: - 8. Tool: unsupported_capability (Mandatory Fallback)

@MainActor
public struct UnsupportedCapabilityTool: AIToolProtocol {
    public let name: String = "unsupported_capability"
    public let description: String = "Ferramenta mandatória de fallback. DEVE ser chamada quando o usuário solicitar uma análise ou ação para a qual NÃO existe ferramenta implementada no registro. Evita alucinações e registra o pedido."

    public let parametersSchema: [String: Any] = [
        "type": "object",
        "required": ["requestedCapability", "reason", "requiredData"],
        "properties": [
            "requestedCapability": [
                "type": "string",
                "description": "Descrição sucinta do que o usuário solicitou"
            ],
            "reason": [
                "type": "string",
                "description": "Explicação técnica clara de por que a ação não pode ser atendida com as ferramentas nativas atuais"
            ],
            "requiredData": [
                "type": "string",
                "description": "Dados, integrações ou ferramentas que precisariam ser implementados para viabilizar o pedido"
            ]
        ]
    ]

    private let registry: AIToolRegistry

    public init(registry: AIToolRegistry? = nil) {
        self.registry = registry ?? .shared
    }

    public func execute(parameters: [String: Any]) async throws -> [String: Any] {
        let requested = (parameters["requestedCapability"] as? String) ?? "Ação não especificada"
        let reason = (parameters["reason"] as? String) ?? "Não há ferramenta nativa registrada para processar esta solicitação."
        let requiredData = (parameters["requiredData"] as? String) ?? "Definição de nova ferramenta e mapeamento de dados."

        registry.recordUnsupportedCapability(
            requestedCapability: requested,
            reason: reason,
            requiredData: requiredData
        )

        return [
            "status": "unsupported",
            "message": "Esta capacidade ainda não está disponível nativamente no FinSense.",
            "requestedCapability": requested,
            "reason": reason,
            "requiredData": requiredData,
            "loggedForDevelopment": true
        ]
    }
}
