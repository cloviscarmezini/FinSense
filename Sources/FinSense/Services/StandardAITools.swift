import Foundation

// MARK: - Helpers de Formatação e Normalização

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

private func normalizeSearchToken(_ text: String) -> String {
    text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR"))
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

private func parseISODate(_ raw: String?) -> Date? {
    guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
    let parts = raw.split(separator: "-").compactMap { Int($0) }
    guard parts.count >= 2 else { return nil }
    var comp = DateComponents()
    comp.year = parts[0]
    comp.month = parts[1]
    comp.day = parts.count >= 3 ? parts[2] : 1
    return Calendar(identifier: .gregorian).date(from: comp)
}

private func extractDouble(_ value: Any?) -> Double? {
    if let d = value as? Double { return d }
    if let i = value as? Int { return Double(i) }
    if let n = value as? NSNumber { return n.doubleValue }
    if let s = value as? String {
        let cleaned = s.replacingOccurrences(of: "R$", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ",", with: ".")
        return Double(cleaned)
    }
    return nil
}

private func extractInt(_ value: Any?) -> Int? {
    if let i = value as? Int { return i }
    if let d = value as? Double { return Int(d) }
    if let n = value as? NSNumber { return n.intValue }
    if let s = value as? String { return Int(s.trimmingCharacters(in: .whitespacesAndNewlines)) }
    return nil
}

// MARK: - 1. Tool: get_contract_details

@MainActor
public struct GetContractDetailsTool: AIToolProtocol {
    public let name: String = "get_contract_details"
    public let description: String = "Consulta dados cadastrais, financeiros e técnicos de contratos ativos (financiamento imobiliário, empréstimo convencional/consignado ou dívidas), incluindo parcelas pagas pela referência salarial, cronograma decrescente (DDC), taxa de crescimento TP e plano salvo."

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
        let rawQuery = (parameters["nameOrQuery"] as? String) ?? ""
        let normQuery = normalizeSearchToken(rawQuery)
        let kind = ((parameters["kind"] as? String) ?? "any").lowercased()

        // Busca em Contratos de Financiamento e Empréstimo
        var matchedContracts = store.contracts.filter { !$0.isSettled }
        if kind == "financing" {
            matchedContracts = matchedContracts.filter { $0.kind == .financing }
        } else if kind == "loan" {
            matchedContracts = matchedContracts.filter { $0.kind == .loan }
        } else if kind == "debt" {
            matchedContracts = []
        }

        if let contractIdStr, let uuid = UUID(uuidString: contractIdStr) {
            matchedContracts = matchedContracts.filter { $0.id == uuid }
        } else if !normQuery.isEmpty {
            let exactOrPartial = matchedContracts.filter {
                normalizeSearchToken($0.name).contains(normQuery) ||
                normalizeSearchToken($0.contractNumber ?? "").contains(normQuery) ||
                normalizeSearchToken($0.subtypeDisplayName).contains(normQuery)
            }
            if !exactOrPartial.isEmpty {
                matchedContracts = exactOrPartial
            } else {
                // Tentativa por palavras individuais (match flexível para prompts compostos)
                let tokens = normQuery.split(separator: " ").map(String.init).filter { $0.count >= 3 }
                let byTokens = matchedContracts.filter { c in
                    let hay = normalizeSearchToken("\(c.name) \(c.contractNumber ?? "") \(c.subtypeDisplayName)")
                    return tokens.contains { hay.contains($0) }
                }
                matchedContracts = byTokens
            }
        }

        // Busca em Dívidas se aplicável
        var matchedDebts = store.activeDebts
        if kind == "financing" || kind == "loan" {
            matchedDebts = []
        } else if let contractIdStr, let uuid = UUID(uuidString: contractIdStr) {
            matchedDebts = matchedDebts.filter { $0.id == uuid }
        } else if !normQuery.isEmpty {
            let filtered = matchedDebts.filter { normalizeSearchToken($0.name).contains(normQuery) }
            if !filtered.isEmpty {
                matchedDebts = filtered
            } else {
                let tokens = normQuery.split(separator: " ").map(String.init).filter { $0.count >= 3 }
                matchedDebts = matchedDebts.filter { d in
                    let hay = normalizeSearchToken(d.name)
                    return tokens.contains { hay.contains($0) }
                }
            }
        }

        var resultsList: [[String: Any]] = []

        for c in matchedContracts {
            let payoff = store.projectedPayoffAmount(for: c)
            let currentBal = store.currentOutstandingBalance(for: c)
            let remainingCount = store.remainingInstallmentsCount(for: c)
            let paidCount = store.paidTransactionsCount(forContract: c)
            let hasPlan = store.hasSavedAmortizationPlan(for: c.id)

            var dict: [String: Any] = [
                "id": c.id.uuidString,
                "name": c.name,
                "kind": c.kind.rawValue,
                "subtype": c.subtypeDisplayName,
                "contractNumber": c.contractNumber as Any,
                "outstandingBalance": currentBal,
                "totalContractedAmount": c.totalContractedAmount,
                "installmentAmount": c.installmentAmount,
                "billingDaySalaryDebit": c.billingDay,
                "bankDueDay": c.effectiveBankDueDay,
                "paidInstallmentsCount": paidCount,
                "remainingInstallments": remainingCount,
                "totalInstallments": c.totalInstallments,
                "projectedPayoffToday": payoff,
                "estimatedDiscountOnPayoff": max(0.0, store.remainingNominalAmount(for: c) - payoff),
                "hasSavedAmortizationPlan": hasPlan,
                "extraAmortizedTotal": c.extraAmortizedTotal,
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
                dict["originalTotalInstallments"] = c.originalTotalInstallments as Any
                if let growth = c.averageMonthlyInstallmentGrowth, growth > 0 {
                    dict["speculativeMonthlyInstallmentGrowth"] = growth
                }
            } else {
                dict["monthlyInterestRatePercent"] = c.monthlyInterestRate
                dict["isPayrollDeductible"] = c.effectiveLoanModel?.isPayrollDeductible ?? false
                if let sched = c.scheduledInstallments, !sched.isEmpty {
                    dict["hasDecreasingInstallmentSchedule"] = true
                    dict["scheduledItemsCount"] = sched.count
                }
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
            let availableContracts = store.contracts.filter { !$0.isSettled }.map { [
                "id": $0.id.uuidString,
                "name": $0.name,
                "kind": $0.kind.rawValue,
                "subtype": $0.subtypeDisplayName,
                "outstandingBalance": store.currentOutstandingBalance(for: $0),
                "installmentAmount": $0.installmentAmount
            ] as [String: Any] }
            let availableDebts = store.activeDebts.map { [
                "id": $0.id.uuidString,
                "name": $0.name,
                "originalAmount": $0.originalAmount
            ] as [String: Any] }
            return [
                "status": "not_found",
                "message": "Nenhum contrato ou dívida encontrado para '\(rawQuery)'. Veja a lista completa disponível abaixo.",
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
    public let description: String = "Aciona a engine de amortização em modo simulação (dry-run) para testar pagamentos extraordinários em QUALQUER contrato (Financiamento Tabela Price ou Empréstimo Consignado/Pessoal) com redução de prazo ou de parcela, sem alterar os dados reais."

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
                "description": "Nome ou termo para identificar o contrato (ex: 'caixa', 'habitação', 'santander', 'consignado')"
            ],
            "mode": [
                "type": "string",
                "enum": ["reduce_term", "reduce_installment"],
                "description": "Modo de recálculo: 'reduce_term' para reduzir prazo (padrão) ou 'reduce_installment' para reduzir o valor da parcela mensal"
            ],
            "proRataInterest": [
                "type": "number",
                "description": "Juros pro-rata opcionais decorridos entre o vencimento e o pagamento (padrão 0.0)"
            ],
            "recurringMonthly": [
                "type": "boolean",
                "description": "Se true, projeta usando o motor completo LoanProjectionEngine considerando esse aporte TODOS os meses até quitar"
            ]
        ]
    ]

    private let store: FinancialDataStore

    public init(store: FinancialDataStore) {
        self.store = store
    }

    public func execute(parameters: [String: Any]) async throws -> [String: Any] {
        guard let extraPayment = extractDouble(parameters["extraPayment"]),
              extraPayment > 0 else {
            return [
                "status": "error",
                "error": "O parâmetro 'extraPayment' deve ser um número positivo maior que zero."
            ]
        }

        let modeStr = (parameters["mode"] as? String)?.lowercased() ?? "reduce_term"
        let recalcMode: AmortizationRecalculationMode = (modeStr == "reduce_installment") ? .reduceInstallment : .reduceTerm
        let proRata = extractDouble(parameters["proRataInterest"]) ?? 0.0
        let recurringMonthly = (parameters["recurringMonthly"] as? Bool) ?? false
        let contractIdStr = parameters["contractId"] as? String
        let query = normalizeSearchToken((parameters["nameOrQuery"] as? String) ?? "")

        // Localiza contrato ativo com busca inteligente
        let activeContracts = store.contracts.filter { !$0.isSettled }
        var candidates = activeContracts

        if let contractIdStr, let uuid = UUID(uuidString: contractIdStr) {
            candidates = activeContracts.filter { $0.id == uuid }
        } else if !query.isEmpty {
            let direct = activeContracts.filter {
                normalizeSearchToken($0.name).contains(query) ||
                normalizeSearchToken($0.subtypeDisplayName).contains(query) ||
                normalizeSearchToken($0.contractNumber ?? "").contains(query)
            }
            if !direct.isEmpty {
                candidates = direct
            } else {
                let tokens = query.split(separator: " ").map(String.init).filter { $0.count >= 3 }
                candidates = activeContracts.filter { c in
                    let hay = normalizeSearchToken("\(c.name) \(c.subtypeDisplayName) \(c.contractNumber ?? "")")
                    return tokens.contains { hay.contains($0) }
                }
            }
        }

        guard let contract = candidates.first else {
            let activeList = activeContracts.map { ["id": $0.id.uuidString, "name": $0.name, "kind": $0.kind.rawValue] }
            return [
                "status": "contract_not_found",
                "error": "Não foi possível identificar o contrato '\(query)' para simulação.",
                "availableContracts": activeList
            ]
        }

        let prevRem = store.remainingInstallmentsCount(for: contract)
        let currentPV = store.currentOutstandingBalance(for: contract)

        // Simulação de aporte único (dry-run instantâneo)
        var baseResult: [String: Any]
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
            baseResult = [
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
            baseResult = [
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

        // Se solicitado recurringMonthly == true (ou sempre adiciona projeção multi-mês se possível), simula também plano mensal contínuo
        if recurringMonthly {
            let cal = store.calendar
            let today = store.effectiveCurrentDate
            var items: [PlannedAmortization] = []
            let maxMonthsToSeed = min(max(prevRem, 12), 120)
            for offset in 0..<maxMonthsToSeed {
                if let dt = cal.date(byAdding: .month, value: offset, to: today) {
                    items.append(
                        PlannedAmortization(
                            contractId: contract.id,
                            date: dt,
                            amount: LoanProjectionEngine.toDecimal(extraPayment),
                            source: .cash,
                            mode: recalcMode,
                            status: .pending,
                            notes: "Simulação IA"
                        )
                    )
                }
            }
            let draftPlan = AmortizationPlan(
                contractId: contract.id,
                generationMode: .manual,
                defaultRecalculationMode: recalcMode,
                items: items
            )
            if let proj = store.simulateAmortizationPlanPreview(for: contract.id, draftPlan: draftPlan) {
                baseResult["recurringMonthlyProjection"] = [
                    "monthlyExtraPayment": extraPayment,
                    "originalRemainingMonths": proj.originalRemainingMonths,
                    "projectedMonthsWithPlan": proj.projectedActiveMonths,
                    "monthsSavedWithPlan": proj.monthsSaved,
                    "savedTimeWithPlan": formatEliminatedMonthsString(proj.monthsSaved),
                    "projectedPayoffDate": BRLFormatters.shortDate(proj.projectedMaturityDate),
                    "originalMaturityDate": BRLFormatters.shortDate(proj.originalMaturityDate),
                    "totalInterestSaved": LoanProjectionEngine.toDouble(proj.totalInterestSaved),
                    "doesAchieveFullPayoff": proj.doesPlanAchieveFullPayoff
                ]
            }
        }

        return baseResult
    }
}

// MARK: - 3. Tool: get_monthly_cash_flow

@MainActor
public struct GetMonthlyCashFlowTool: AIToolProtocol {
    public let name: String = "get_monthly_cash_flow"
    public let description: String = "Consulta receitas, despesas, contas a pagar pendentes, balanço operacional, sobra líquida real, cenário ativo (Real Base vs Com Planejamento) e saldo livre em contas para determinado mês ou mês ativo."

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

        if let refStr = parameters["referenceDate"] as? String, let d = parseISODate(refStr) {
            targetDate = d
        } else if let m = extractInt(parameters["month"]),
                  let y = extractInt(parameters["year"]) {
            var comp = DateComponents()
            comp.year = y
            comp.month = m
            comp.day = 1
            if let d = cal.date(from: comp) {
                targetDate = d
            }
        }

        if let horizon = cal.date(byAdding: .month, value: 1, to: targetDate) {
            store.ensureRecurringTransactionsMaterialized(upTo: horizon)
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

        // Lista top contas pendentes do mês para dar ação prática à IA
        let pendingExpenses = store.transactionsForMonth(targetDate)
            .filter { $0.type == .expense && !$0.isPaid && !$0.ignoreInConsolidated && store.isTransactionVisibleInCurrentScenario($0) }
            .sorted { store.effectiveTransactionAmount(for: $0) > store.effectiveTransactionAmount(for: $1) }
            .prefix(8)
            .map { tx -> [String: Any] in
                [
                    "name": tx.name,
                    "amount": store.effectiveTransactionAmount(for: tx),
                    "date": BRLFormatters.shortDate(tx.date),
                    "category": store.category(for: tx.categoryId)?.name ?? "Geral"
                ]
            }

        return [
            "status": "success",
            "monthReference": BRLFormatters.monthYear(targetDate),
            "activeScenario": store.budgetProjectionScenario.rawValue,
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
            "projectedMonthEndCash": store.accumulatedConsolidatedBalance(throughMonth: targetDate),
            "topPendingExpenses": pendingExpenses
        ]
    }
}

// MARK: - 4. Tool: get_projected_cash_flow_range

@MainActor
public struct GetProjectedCashFlowRangeTool: AIToolProtocol {
    public let name: String = "get_projected_cash_flow_range"
    public let description: String = "Consulta a projeção mês a mês de fluxo de caixa para horizontes futuros (receitas projetadas, despesas, parcelas de contratos com cenário Real ou Planejado, balanço mensal e saldo acumulado)."

    public let parametersSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "startMonth": [
                "type": "string",
                "description": "Mês inicial no formato 'YYYY-MM' (opcional, padrão: mês ativo)"
            ],
            "numberOfMonths": [
                "type": "integer",
                "description": "Quantidade de meses a projetar (mínimo 2, máximo 60, padrão 12)"
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

        if let startStr = parameters["startMonth"] as? String, let d = parseISODate(startStr) {
            startDate = d
        }

        let rawMonths = extractInt(parameters["numberOfMonths"]) ?? 12
        let count = max(2, min(rawMonths, 60))

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
            "activeScenario": store.budgetProjectionScenario.rawValue,
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
        var targetDate = store.selectedMonth

        if let refStr = parameters["referenceMonth"] as? String, let d = parseISODate(refStr) {
            targetDate = d
        }

        let targetExtra = extractDouble(parameters["targetExtraPayment"]) ?? 0.0

        let monthTxs = store.transactionsForMonth(targetDate)
            .filter { $0.type == .expense && !$0.ignoreInConsolidated && store.isTransactionVisibleInCurrentScenario($0) }
        let totalExpense = monthTxs.reduce(0.0) { $0 + store.effectiveTransactionAmount(for: $1) }

        let essentialKeywords: Set<String> = [
            "moradia", "aluguel", "condominio", "iptu", "financiamento", "habitacao",
            "saude", "medico", "farmacia", "convenio", "educacao", "faculdade", "escola"
        ]

        var categoryTotals: [UUID: Double] = [:]
        for tx in monthTxs {
            categoryTotals[tx.categoryId, default: 0.0] += store.effectiveTransactionAmount(for: tx)
        }

        var discretionaryList: [(cat: CategoryItem, total: Double)] = []
        var essentialTotal: Double = 0.0

        for (catId, sumAmount) in categoryTotals {
            guard let cat = store.category(for: catId) else { continue }
            let nameNorm = normalizeSearchToken(cat.name)
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
    public let description: String = "Consulta o consumo real de tetos orçamentários por categoria (envelopes de verba livre) e cotas específicas de consumo no mês ativo ou informado."

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
        var targetDate = store.selectedMonth

        if let refStr = parameters["month"] as? String, let d = parseISODate(refStr) {
            targetDate = d
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
    public let description: String = "Filtra e consulta lançamentos financeiros individuais da base de dados por intervalo de datas, mês, categoria, conta, busca textual, tipo ou status de pagamento."

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
            "accountName": [
                "type": "string",
                "description": "Nome da conta bancária para filtrar (opcional)"
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
                "description": "Mês específico no formato 'YYYY-MM' (opcional)"
            ],
            "startDate": [
                "type": "string",
                "description": "Data inicial inclusiva no formato 'YYYY-MM-DD' (opcional)"
            ],
            "endDate": [
                "type": "string",
                "description": "Data final inclusiva no formato 'YYYY-MM-DD' (opcional)"
            ],
            "sortBy": [
                "type": "string",
                "enum": ["date_desc", "date_asc", "amount_desc"],
                "description": "Ordenação: 'date_desc' (padrão), 'date_asc' ou 'amount_desc' (maiores valores)"
            ],
            "limit": [
                "type": "integer",
                "description": "Limite máximo de registros a retornar (padrão 15, máximo 100)"
            ]
        ]
    ]

    private let store: FinancialDataStore

    public init(store: FinancialDataStore) {
        self.store = store
    }

    public func execute(parameters: [String: Any]) async throws -> [String: Any] {
        let cal = store.calendar

        if let endD = parseISODate(parameters["endDate"] as? String) {
            store.ensureRecurringTransactionsMaterialized(upTo: endD)
        } else if let monthD = parseISODate(parameters["month"] as? String),
                  let horizon = cal.date(byAdding: .month, value: 1, to: monthD) {
            store.ensureRecurringTransactionsMaterialized(upTo: horizon)
        }

        var txs = store.transactions.filter {
            !$0.ignoreInConsolidated && store.isTransactionVisibleInCurrentScenario($0)
        }

        if let typeStr = (parameters["type"] as? String)?.lowercased() {
            if typeStr == "expense" {
                txs = txs.filter { $0.type == .expense }
            } else if typeStr == "income" {
                txs = txs.filter { $0.type == .income }
            }
        }

        if let isPaid = parameters["isPaid"] as? Bool {
            txs = txs.filter { $0.isPaid == isPaid }
        }

        if let catRaw = parameters["categoryName"] as? String {
            let catNorm = normalizeSearchToken(catRaw)
            if !catNorm.isEmpty {
                txs = txs.filter { tx in
                    guard let cat = store.category(for: tx.categoryId) else { return false }
                    return normalizeSearchToken(cat.name).contains(catNorm)
                }
            }
        }

        if let accRaw = parameters["accountName"] as? String {
            let accNorm = normalizeSearchToken(accRaw)
            if !accNorm.isEmpty {
                txs = txs.filter { tx in
                    guard let acc = store.account(for: tx.accountId) else { return false }
                    return normalizeSearchToken(acc.name).contains(accNorm)
                }
            }
        }

        if let qRaw = parameters["searchQuery"] as? String {
            let q = normalizeSearchToken(qRaw)
            if !q.isEmpty {
                txs = txs.filter {
                    normalizeSearchToken($0.name).contains(q) ||
                    normalizeSearchToken($0.details).contains(q)
                }
            }
        }

        if let monthStr = parameters["month"] as? String {
            let parts = monthStr.split(separator: "-").compactMap { Int($0) }
            if parts.count >= 2 {
                txs = txs.filter {
                    let cYear = cal.component(.year, from: $0.date)
                    let cMonth = cal.component(.month, from: $0.date)
                    return cYear == parts[0] && cMonth == parts[1]
                }
            }
        }

        if let startD = parseISODate(parameters["startDate"] as? String) {
            let startDay = cal.startOfDay(for: startD)
            txs = txs.filter { $0.date >= startDay }
        }

        if let endD = parseISODate(parameters["endDate"] as? String) {
            let endDay = cal.date(bySettingHour: 23, minute: 59, second: 59, of: endD) ?? endD
            txs = txs.filter { $0.date <= endDay }
        }

        let sortBy = (parameters["sortBy"] as? String)?.lowercased() ?? "date_desc"
        switch sortBy {
        case "date_asc":
            txs.sort { $0.date < $1.date }
        case "amount_desc":
            txs.sort { store.effectiveTransactionAmount(for: $0) > store.effectiveTransactionAmount(for: $1) }
        default:
            txs.sort { $0.date > $1.date }
        }

        let limit = min(max(extractInt(parameters["limit"]) ?? 15, 1), 100)
        let totalCount = txs.count
        let sumAmount = txs.reduce(0.0) { $0 + store.effectiveTransactionAmount(for: $1) }

        let sliced = txs.prefix(limit).map { tx -> [String: Any] in
            let catName = store.category(for: tx.categoryId)?.name ?? "Sem Categoria"
            let accName = store.account(for: tx.accountId)?.name ?? "Conta"
            return [
                "id": tx.id.uuidString,
                "date": BRLFormatters.shortDate(tx.date),
                "description": tx.name,
                "details": tx.details,
                "amount": store.effectiveTransactionAmount(for: tx),
                "type": tx.type.rawValue,
                "category": catName,
                "account": accName,
                "isPaid": tx.isPaid,
                "recurrenceMode": tx.recurrenceMode.rawValue,
                "isRecurring": tx.recurrenceMode == .recurring
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
    public let description: String = "Ferramenta mandatória de fallback. DEVE ser chamada quando o usuário solicitar uma análise ou ação externa impossível (ex: executar compra de ações na B3, fazer PIX bancário real). Evita alucinações e registra o pedido."

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

// MARK: - 9. Tool: get_financial_overview (Acesso Global Ilimitado ao Banco)

@MainActor
public struct GetFinancialOverviewTool: AIToolProtocol {
    public let name: String = "get_financial_overview"
    public let description: String = "Retorna o panorama completo de todo o banco de dados local: todas as contas bancárias com saldos atuais, investimentos, todos os contratos ativos/quitados, todas as dívidas, categorias e cenário ativo."

    public let parametersSchema: [String: Any] = [
        "type": "object",
        "properties": [:]
    ]

    private let store: FinancialDataStore

    public init(store: FinancialDataStore) {
        self.store = store
    }

    public func execute(parameters: [String: Any]) async throws -> [String: Any] {
        let accountsJson: [[String: Any]] = store.accounts.map { acc in
            [
                "id": acc.id.uuidString,
                "name": acc.name,
                "currentBalanceNow": store.currentBalance(forAccount: acc.id),
                "projectedMonthEndBalance": store.currentBalance(forAccount: acc.id, upTo: store.selectedMonth),
                "initialBalance": acc.initialBalance
            ]
        }

        let contractsJson: [[String: Any]] = store.contracts.map { c in
            [
                "id": c.id.uuidString,
                "name": c.name,
                "kind": c.kind.rawValue,
                "subtype": c.subtypeDisplayName,
                "isSettled": c.isSettled,
                "outstandingBalance": store.currentOutstandingBalance(for: c),
                "projectedPayoffToday": store.projectedPayoffAmount(for: c),
                "installmentAmount": c.installmentAmount,
                "remainingInstallments": store.remainingInstallmentsCount(for: c),
                "hasSavedAmortizationPlan": store.hasSavedAmortizationPlan(for: c.id)
            ]
        }

        let debtsJson: [[String: Any]] = store.debts.map { d in
            [
                "id": d.id.uuidString,
                "name": d.name,
                "originalAmount": d.originalAmount,
                "isPaid": d.isPaid,
                "negotiatedAmount": d.negotiatedAmount as Any,
                "notes": d.notes
            ]
        }

        let investmentsJson: [[String: Any]] = store.investments.map { inv in
            [
                "id": inv.id.uuidString,
                "name": inv.name,
                "groupName": inv.groupName,
                "balance": inv.balance,
                "showInConsolidated": inv.showInConsolidated
            ]
        }

        let categoriesJson: [[String: Any]] = store.categories.map { cat in
            ["name": cat.name, "type": cat.type.rawValue]
        }

        let activeContracts = store.contracts.filter { !$0.isSettled }
        let totalLiabilities = activeContracts.reduce(0.0) { $0 + store.currentOutstandingBalance(for: $1) }
        let totalOpenDebts = store.activeDebts.reduce(0.0) { $0 + $1.originalAmount }

        return [
            "status": "success",
            "referenceDateToday": BRLFormatters.shortDate(store.effectiveCurrentDate),
            "selectedMonth": BRLFormatters.monthYear(store.selectedMonth),
            "activeScenario": store.budgetProjectionScenario.rawValue,
            "summary": [
                "totalCheckingBalanceNow": store.totalCheckingBalanceNow,
                "totalInvestmentsConsolidated": store.totalInvestmentsBalance,
                "totalPatrimonyNow": store.totalConsolidatedPatrimonyNow,
                "totalActiveCreditContractsBalance": totalLiabilities,
                "totalOpenDebtsAmount": totalOpenDebts,
                "transactionsCount": store.transactions.count
            ],
            "accounts": accountsJson,
            "contracts": contractsJson,
            "debts": debtsJson,
            "investments": investmentsJson,
            "categories": categoriesJson
        ]
    }
}

// MARK: - 10. Tool: get_loan_projection_and_plan (Engine de Projeção Real + Planejamento de Amortização)

@MainActor
public struct GetLoanProjectionAndPlanTool: AIToolProtocol {
    public let name: String = "get_loan_projection_and_plan"
    public let description: String = "Consulta o planejamento de amortização salvo e a linha do tempo real do LoanProjectionEngine para um contrato (ou simula um rascunho com aportes mensais ou avulsos em Dinheiro/FGTS), verificando quando ocorre quitação, economia de juros, regras de FGTS e impacto no saldo mensal em caixa."

    public let parametersSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "contractId": [
                "type": "string",
                "description": "UUID do contrato (opcional se nameOrQuery for informado)"
            ],
            "nameOrQuery": [
                "type": "string",
                "description": "Nome do contrato (ex: 'caixa', 'santander', 'habitacao')"
            ],
            "simulateMonthlyExtraAmount": [
                "type": "number",
                "description": "Opcional: simula em memória um aporte mensal recorrente deste valor (ex: 1500.0) ao invés de ler apenas o plano salvo"
            ],
            "simulateSource": [
                "type": "string",
                "enum": ["cash", "fgts"],
                "description": "Origem para simulação em rascunho: 'cash' (Dinheiro, padrão) ou 'fgts'"
            ],
            "simulateMode": [
                "type": "string",
                "enum": ["reduce_term", "reduce_installment"],
                "description": "Modalidade: 'reduce_term' (padrão) ou 'reduce_installment'"
            ]
        ]
    ]

    private let store: FinancialDataStore

    public init(store: FinancialDataStore) {
        self.store = store
    }

    public func execute(parameters: [String: Any]) async throws -> [String: Any] {
        let activeContracts = store.contracts.filter { !$0.isSettled }
        let query = normalizeSearchToken((parameters["nameOrQuery"] as? String) ?? "")
        let contractIdStr = parameters["contractId"] as? String

        var selected: CreditContract?
        if let contractIdStr, let uuid = UUID(uuidString: contractIdStr) {
            selected = activeContracts.first(where: { $0.id == uuid })
        } else if !query.isEmpty {
            selected = activeContracts.first(where: {
                normalizeSearchToken($0.name).contains(query) ||
                normalizeSearchToken($0.subtypeDisplayName).contains(query)
            })
            if selected == nil {
                let tokens = query.split(separator: " ").map(String.init).filter { $0.count >= 3 }
                selected = activeContracts.first { c in
                    let hay = normalizeSearchToken("\(c.name) \(c.subtypeDisplayName)")
                    return tokens.contains { hay.contains($0) }
                }
            }
        } else if activeContracts.count == 1 {
            selected = activeContracts.first
        }

        guard let contract = selected else {
            return [
                "status": "needs_clarification",
                "message": "Há \(activeContracts.count) contrato(s) ativo(s). Especifique qual contrato deseja simular ou inspecionar.",
                "availableContracts": activeContracts.map { ["id": $0.id.uuidString, "name": $0.name, "kind": $0.kind.rawValue] }
            ]
        }

        let simMonthly = extractDouble(parameters["simulateMonthlyExtraAmount"])
        let source: AmortizationFundingSource = ((parameters["simulateSource"] as? String)?.lowercased() == "fgts") ? .fgts : .cash
        let mode: AmortizationRecalculationMode = ((parameters["simulateMode"] as? String)?.lowercased() == "reduce_installment") ? .reduceInstallment : .reduceTerm

        let usedPlan: AmortizationPlan?
        let projection: LoanProjectionResult?
        let isSimulatedDraft: Bool

        if let simMonthly, simMonthly > 0 {
            isSimulatedDraft = true
            var items: [PlannedAmortization] = []
            let rem = max(store.remainingInstallmentsCount(for: contract), 12)
            let monthsCount = min(rem, 120)
            for idx in 0..<monthsCount {
                if let dt = store.calendar.date(byAdding: .month, value: idx, to: store.effectiveCurrentDate) {
                    items.append(
                        PlannedAmortization(
                            contractId: contract.id,
                            date: dt,
                            amount: LoanProjectionEngine.toDecimal(simMonthly),
                            source: source,
                            mode: mode,
                            status: .pending,
                            notes: "Simulação rascunho IA"
                        )
                    )
                }
            }
            let draft = AmortizationPlan(
                contractId: contract.id,
                generationMode: .manual,
                defaultRecalculationMode: mode,
                items: items
            )
            usedPlan = draft
            projection = store.simulateAmortizationPlanPreview(for: contract.id, draftPlan: draft)
        } else {
            isSimulatedDraft = false
            usedPlan = store.amortizationPlan(for: contract.id)
            projection = store.loanProjection(for: contract.id)
        }

        guard let proj = projection else {
            return [
                "status": "error",
                "error": "Não foi possível gerar projeção para o contrato \(contract.name)."
            ]
        }

        // Resumo dos aportes planejados e impacto no caixa
        let plannedOutcomes: [[String: Any]] = (usedPlan?.items ?? [])
            .filter { $0.status == .pending }
            .sorted { $0.date < $1.date }
            .prefix(24)
            .map { item in
                let outcome = proj.plannedItemOutcomes[item.id]
                let expectedMonthCash = store.expectedMonthEndCashBalance(
                    for: item.date,
                    contractId: contract.id,
                    draftPlan: isSimulatedDraft ? usedPlan : nil,
                    draftProjection: isSimulatedDraft ? proj : nil
                )
                return [
                    "date": BRLFormatters.shortDate(item.date),
                    "requestedAmount": item.amountDouble,
                    "source": item.source.shortTitle,
                    "effectiveAmortization": outcome.map { LoanProjectionEngine.toDouble($0.effectiveAmortization) } ?? item.amountDouble,
                    "remainingBalanceAfter": outcome.map { LoanProjectionEngine.toDouble($0.remainingBalanceAfter) } ?? 0.0,
                    "isFullPayoffStep": outcome?.isFullPayoffStep ?? false,
                    "expectedMonthEndCashBalance": expectedMonthCash,
                    "fgtsWarning": outcome?.fgtsValidationWarning as Any
                ]
            }

        return [
            "status": "success",
            "contractId": contract.id.uuidString,
            "contractName": contract.name,
            "contractKind": contract.kind.rawValue,
            "isSimulatedDraft": isSimulatedDraft,
            "hasSavedPlanOnDatabase": store.hasSavedAmortizationPlan(for: contract.id),
            "currentRealBalance": LoanProjectionEngine.toDouble(proj.currentRealBalance),
            "projectedFinalBalanceAfterPlan": LoanProjectionEngine.toDouble(proj.projectedFinalBalanceAfterPlan),
            "doesPlanAchieveFullPayoff": proj.doesPlanAchieveFullPayoff,
            "originalRemainingMonths": proj.originalRemainingMonths,
            "projectedActiveMonths": proj.projectedActiveMonths,
            "monthsSaved": proj.monthsSaved,
            "originalMaturityDate": BRLFormatters.shortDate(proj.originalMaturityDate),
            "projectedMaturityDate": BRLFormatters.shortDate(proj.projectedMaturityDate),
            "originalTotalInterest": LoanProjectionEngine.toDouble(proj.originalTotalInterest),
            "projectedTotalInterest": LoanProjectionEngine.toDouble(proj.projectedTotalInterest),
            "totalInterestSaved": LoanProjectionEngine.toDouble(proj.totalInterestSaved),
            "totalExtraAmortized": LoanProjectionEngine.toDouble(proj.totalExtraAmortized),
            "fgtsWarnings": proj.fgtsWarnings,
            "plannedItemsCount": plannedOutcomes.count,
            "plannedItemsPreview": plannedOutcomes
        ]
    }
}

// MARK: - 11. Tool: aggregate_transactions (Analítica SQL-like sobre toda a tabela de transações)

@MainActor
public struct AggregateTransactionsTool: AIToolProtocol {
    public let name: String = "aggregate_transactions"
    public let description: String = "Agrupa, soma, conta e calcula médias de transações em QUALQUER período (incluindo recorrentes futuras até 2028) por categoria, mês, conta bancária, descrição ou status de pagamento. Ideal para responder 'quanto gastei com X', 'maiores categorias de 2026', 'média mensal de despesas/receitas', etc."

    public let parametersSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "startDate": [
                "type": "string",
                "description": "Data inicial YYYY-MM-DD (opcional; padrão: 12 meses atrás)"
            ],
            "endDate": [
                "type": "string",
                "description": "Data final YYYY-MM-DD (opcional; padrão: final do mês selecionado)"
            ],
            "type": [
                "type": "string",
                "enum": ["expense", "income", "all"],
                "description": "Tipo: 'expense' (padrão), 'income' ou 'all'"
            ],
            "groupBy": [
                "type": "string",
                "enum": ["category", "month", "account", "description", "payment_status"],
                "description": "Dimensão de agrupamento: 'category' (padrão), 'month', 'account', 'description' ou 'payment_status'"
            ],
            "searchQuery": [
                "type": "string",
                "description": "Filtro textual na descrição/detalhes (opcional)"
            ],
            "categoryName": [
                "type": "string",
                "description": "Filtrar por nome de categoria específico (opcional)"
            ],
            "onlyPaid": [
                "type": "boolean",
                "description": "Se true considera apenas pagas/recebidas; se omitido inclui pagas e previstas"
            ]
        ]
    ]

    private let store: FinancialDataStore

    public init(store: FinancialDataStore) {
        self.store = store
    }

    public func execute(parameters: [String: Any]) async throws -> [String: Any] {
        let cal = store.calendar
        let startD = parseISODate(parameters["startDate"] as? String)
            ?? cal.date(byAdding: .month, value: -12, to: store.startOfMonth(for: store.selectedMonth))
            ?? store.startOfMonth(for: store.selectedMonth)
        let endD = parseISODate(parameters["endDate"] as? String)
            ?? store.endOfMonth(for: store.selectedMonth)

        let endInclusive = cal.date(bySettingHour: 23, minute: 59, second: 59, of: endD) ?? endD
        store.ensureRecurringTransactionsMaterialized(upTo: endInclusive)

        var txs = store.transactions.filter {
            !$0.ignoreInConsolidated &&
            store.isTransactionVisibleInCurrentScenario($0) &&
            $0.date >= cal.startOfDay(for: startD) &&
            $0.date <= endInclusive
        }

        let typeFilter = ((parameters["type"] as? String) ?? "expense").lowercased()
        if typeFilter == "expense" {
            txs = txs.filter { $0.type == .expense }
        } else if typeFilter == "income" {
            txs = txs.filter { $0.type == .income }
        }

        if let onlyPaid = parameters["onlyPaid"] as? Bool {
            txs = txs.filter { $0.isPaid == onlyPaid }
        }

        if let catRaw = parameters["categoryName"] as? String {
            let normCat = normalizeSearchToken(catRaw)
            if !normCat.isEmpty {
                txs = txs.filter { tx in
                    guard let cat = store.category(for: tx.categoryId) else { return false }
                    return normalizeSearchToken(cat.name).contains(normCat)
                }
            }
        }

        if let qRaw = parameters["searchQuery"] as? String {
            let q = normalizeSearchToken(qRaw)
            if !q.isEmpty {
                txs = txs.filter {
                    normalizeSearchToken($0.name).contains(q) ||
                    normalizeSearchToken($0.details).contains(q)
                }
            }
        }

        let groupBy = ((parameters["groupBy"] as? String) ?? "category").lowercased()
        var buckets: [String: (sum: Double, count: Int)] = [:]
        var grandTotal: Double = 0.0

        for tx in txs {
            let val = store.effectiveTransactionAmount(for: tx)
            let signed = (typeFilter == "all") ? (tx.type == .income ? val : -val) : val
            grandTotal += signed

            let key: String
            switch groupBy {
            case "month":
                let comps = cal.dateComponents([.year, .month], from: tx.date)
                key = String(format: "%04d-%02d (%@)", comps.year ?? 2026, comps.month ?? 1, BRLFormatters.monthYear(tx.date))
            case "account":
                key = store.account(for: tx.accountId)?.name ?? "Conta Desconhecida"
            case "description":
                key = tx.name
            case "payment_status":
                key = tx.isPaid ? "Realizada (Paga/Recebida)" : "Pendente/Prevista"
            default:
                key = store.category(for: tx.categoryId)?.name ?? "Sem Categoria"
            }

            var entry = buckets[key] ?? (0.0, 0)
            entry.sum += signed
            entry.count += 1
            buckets[key] = entry
        }

        let sortedGroups: [[String: Any]] = buckets
            .sorted { abs($0.value.sum) > abs($1.value.sum) }
            .prefix(40)
            .map { key, stats in
                [
                    "group": key,
                    "totalAmount": stats.sum,
                    "count": stats.count,
                    "averagePerTransaction": stats.count > 0 ? stats.sum / Double(stats.count) : 0.0,
                    "sharePercent": abs(grandTotal) > 0 ? (abs(stats.sum) / abs(grandTotal)) * 100.0 : 0.0
                ]
            }

        return [
            "status": "success",
            "periodStart": BRLFormatters.shortDate(startD),
            "periodEnd": BRLFormatters.shortDate(endD),
            "typeFilter": typeFilter,
            "groupBy": groupBy,
            "totalTransactionsMatched": txs.count,
            "grandTotalAmount": grandTotal,
            "groups": sortedGroups
        ]
    }
}

// MARK: - 12. Tool: get_investments_summary

@MainActor
public struct GetInvestmentsSummaryTool: AIToolProtocol {
    public let name: String = "get_investments_summary"
    public let description: String = "Consulta detalhadamente todos os investimentos, cofrinhos, caixinhas, reserva de emergência e histórico de aportes/resgates/rendimentos."

    public let parametersSchema: [String: Any] = [
        "type": "object",
        "properties": [:]
    ]

    private let store: FinancialDataStore

    public init(store: FinancialDataStore) {
        self.store = store
    }

    public func execute(parameters: [String: Any]) async throws -> [String: Any] {
        var byGroup: [String: Double] = [:]
        let itemsJson: [[String: Any]] = store.investments.map { inv in
            byGroup[inv.groupName, default: 0.0] += inv.balance
            let recentMovements = inv.movements
                .sorted { $0.date > $1.date }
                .prefix(5)
                .map { mov -> [String: Any] in
                    [
                        "date": BRLFormatters.shortDate(mov.date),
                        "type": mov.type.title,
                        "amount": mov.amount,
                        "notes": mov.notes
                    ]
                }
            return [
                "id": inv.id.uuidString,
                "name": inv.name,
                "groupName": inv.groupName,
                "account": store.account(for: inv.investmentAccountId)?.name ?? "Conta",
                "balance": inv.balance,
                "showInConsolidated": inv.showInConsolidated,
                "notes": inv.notes,
                "recentMovements": recentMovements
            ]
        }

        let totalAll = store.investments.reduce(0.0) { $0 + $1.balance }

        return [
            "status": "success",
            "totalInvestmentsConsolidated": store.totalInvestmentsBalance,
            "totalAllInvestmentsIncludingNonConsolidated": totalAll,
            "byGroupTotals": byGroup,
            "investments": itemsJson
        ]
    }
}

// MARK: - 13. Tool: analyze_debt_payoff_strategy (Simulação Real para Dívidas / Acordos)

@MainActor
public struct AnalyzeDebtPayoffStrategyTool: AIToolProtocol {
    public let name: String = "analyze_debt_payoff_strategy"
    public let description: String = "Analisa em quanto tempo o usuário consegue quitar uma dívida específica ou todas as dívidas em aberto usando a média real de receitas, despesas recorrentes, sobra mensal líquida e reservas em conta/investimentos."

    public let parametersSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "debtId": [
                "type": "string",
                "description": "UUID opcional da dívida específica"
            ],
            "nameOrQuery": [
                "type": "string",
                "description": "Nome ou parte do nome da dívida (ex: 'Mercado Pago', 'Sam', 'Nubank')"
            ]
        ]
    ]

    private let store: FinancialDataStore

    public init(store: FinancialDataStore) {
        self.store = store
    }

    public func execute(parameters: [String: Any]) async throws -> [String: Any] {
        let openDebts = store.activeDebts
        let debtIdStr = parameters["debtId"] as? String
        let query = normalizeSearchToken((parameters["nameOrQuery"] as? String) ?? "")

        let matchedDebts: [DebtItem]
        if let debtIdStr, let uuid = UUID(uuidString: debtIdStr) {
            matchedDebts = openDebts.filter { $0.id == uuid }
        } else if !query.isEmpty {
            let direct = openDebts.filter { normalizeSearchToken($0.name).contains(query) }
            if !direct.isEmpty {
                matchedDebts = direct
            } else {
                let tokens = query.split(separator: " ").map(String.init).filter { $0.count >= 3 }
                matchedDebts = openDebts.filter { d in
                    let hay = normalizeSearchToken(d.name)
                    return tokens.contains { hay.contains($0) }
                }
            }
        } else {
            matchedDebts = openDebts
        }

        if openDebts.isEmpty {
            return [
                "status": "success",
                "message": "O usuário não possui nenhuma dívida em aberto cadastrada no momento.",
                "openDebts": []
            ]
        }

        // Calcula capacidade real de pagamento nos últimos/próximos 3 meses
        let cal = store.calendar
        if let horizon = cal.date(byAdding: .month, value: 6, to: store.selectedMonth) {
            store.ensureRecurringTransactionsMaterialized(upTo: horizon)
        }

        var monthlyNets: [Double] = []
        for offset in 0..<4 {
            if let m = cal.date(byAdding: .month, value: offset, to: store.selectedMonth) {
                monthlyNets.append(store.projectedMonthlyNetBalance(for: m))
            }
        }
        let averageSurplus = monthlyNets.isEmpty ? 0.0 : (monthlyNets.reduce(0.0, +) / Double(monthlyNets.count))
        let currentMonthNet = store.projectedMonthlyNetBalance(for: store.selectedMonth)
        let checkingNow = store.totalCheckingBalanceNow
        let investedNow = store.totalInvestmentsBalance

        let targetDebts = matchedDebts.isEmpty ? openDebts : matchedDebts
        let analysisList: [[String: Any]] = targetDebts.map { d in
            let amount = d.originalAmount
            let canPayCashNow = checkingNow >= amount
            let canPayWithInvestments = (checkingNow + investedNow) >= amount
            let monthsWithAverageSurplus: Any = averageSurplus > 0
                ? Int(ceil(amount / averageSurplus))
                : "Inviável sem corte de gastos (sobra média mensal não positiva)"
            return [
                "id": d.id.uuidString,
                "name": d.name,
                "amount": amount,
                "contractedDate": d.contractedDate.map { BRLFormatters.shortDate($0) } ?? "Não informada",
                "notes": d.notes,
                "canPayImmediatelyFromChecking": canPayCashNow,
                "canPayIncludingInvestments": canPayWithInvestments,
                "estimatedMonthsToSaveFromMonthlySurplus": monthsWithAverageSurplus
            ]
        }

        return [
            "status": "success",
            "matchedSpecifically": !matchedDebts.isEmpty,
            "currentMonthProjectedNet": currentMonthNet,
            "averageProjectedMonthlySurplusNext4Months": averageSurplus,
            "liquidCheckingBalanceNow": checkingNow,
            "investmentsBalanceNow": investedNow,
            "debtsAnalysis": analysisList
        ]
    }
}
