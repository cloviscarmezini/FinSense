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

/// Resolve contratos com tratamento inteligente para termos genéricos ("emprestimos", "financiamentos", "todos")
/// além de correspondência direta ou por tokens específicos (banco, número de contrato, modalidade).
@MainActor
private func resolveContractsMatching(
    in store: FinancialDataStore,
    contractIdStr: String?,
    rawQuery: String,
    kind: String = "any",
    includeSettled: Bool = false
) -> [CreditContract] {
    var pool = store.contracts.filter { includeSettled || !$0.isSettled }
    let normKind = kind.lowercased()
    if normKind == "financing" {
        pool = pool.filter { $0.kind == .financing }
    } else if normKind == "loan" {
        pool = pool.filter { $0.kind == .loan }
    } else if normKind == "debt" {
        return []
    }

    if let contractIdStr, let uuid = UUID(uuidString: contractIdStr) {
        return pool.filter { $0.id == uuid }
    }

    if let uuidInQuery = UUID(uuidString: rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)) {
        return pool.filter { $0.id == uuidInQuery }
    }

    let normQuery = normalizeSearchToken(rawQuery)
    if normQuery.isEmpty {
        return pool
    }

    let genericLoanWords: Set<String> = ["emprestimo", "emprestimos", "loan", "loans", "consignado"]
    let genericFinancingWords: Set<String> = ["financiamento", "financiamentos", "financing", "financings", "imovel", "imobiliario", "habitacao", "habitacional"]
    let genericAllWords: Set<String> = ["contrato", "contratos", "todos", "todas", "all", "any"]
    let stopWords: Set<String> = [
        "meu", "meus", "minha", "minhas", "os", "as", "o", "a", "de", "do", "da", "dos", "das",
        "no", "na", "nos", "nas", "em", "com", "para", "por", "pelo", "pela", "que", "quais",
        "qual", "sao", "sobre", "ver", "listar", "mostrar", "simular", "simulacao", "prazo",
        "quitar", "amortizar", "plano", "acao", "completo", "saldo", "valor", "parcela",
        "taxa", "menor", "possivel", "atual"
    ]

    // 1. Correspondência direta exata / substring nos campos principais
    let directMatches = pool.filter { c in
        normalizeSearchToken(c.name).contains(normQuery) ||
        normalizeSearchToken(c.contractNumber ?? "").contains(normQuery) ||
        normalizeSearchToken(c.subtypeDisplayName).contains(normQuery)
    }
    if !directMatches.isEmpty {
        return directMatches
    }

    // 2. Separa tokens específicos vs categorias genéricas
    let rawTokens = normQuery
        .split { !$0.isLetter && !$0.isNumber }
        .map(String.init)
        .filter { $0.count >= 2 }

    let nonStopTokens = rawTokens.filter { !stopWords.contains($0) }
    let specificTokens = nonStopTokens.filter {
        !genericLoanWords.contains($0) && !genericFinancingWords.contains($0) && !genericAllWords.contains($0)
    }

    if !specificTokens.isEmpty {
        let scored = pool.compactMap { c -> (contract: CreditContract, score: Int)? in
            let hay = normalizeSearchToken("\(c.name) \(c.contractNumber ?? "") \(c.subtypeDisplayName)")
            let score = specificTokens.filter { hay.contains($0) }.count
            return score > 0 ? (c, score) : nil
        }
        .sorted { $0.score > $1.score }
        if !scored.isEmpty {
            return scored.map(\.contract)
        }
        return []
    }

    // 3. Apenas palavras genéricas permaneceram (ex: "meus emprestimos", "quais financiamentos")
    let hasLoanWord = nonStopTokens.contains { genericLoanWords.contains($0) }
    let hasFinancingWord = nonStopTokens.contains { genericFinancingWords.contains($0) }
    let hasAllWord = nonStopTokens.contains { genericAllWords.contains($0) }

    if hasLoanWord && !hasFinancingWord {
        return pool.filter { $0.kind == .loan }
    }
    if hasFinancingWord && !hasLoanWord {
        return pool.filter { $0.kind == .financing }
    }
    if hasAllWord || (hasLoanWord && hasFinancingWord) {
        return pool
    }
    return []
}

/// Simula projeção via `LoanProjectionEngine`, gerando cronograma sintético fiel caso o contrato ainda
/// não possua transações parceladas materializadas no store (ex.: testes ou cadastros recentes).
@MainActor
private func simulateLoanProjectionSafe(
    for contract: CreditContract,
    draftPlan: AmortizationPlan?,
    in store: FinancialDataStore
) -> LoanProjectionResult? {
    InteractivePayoffPlanner.simulateProjectionSafe(for: contract, draftPlan: draftPlan, in: store)
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
                "description": "Nome, termo genérico ou tipo (ex: 'caixa', 'santander', 'emprestimos', 'financiamento', 'mercado pago')"
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

        // Busca inteligente em Contratos de Financiamento e Empréstimo
        let matchedContracts = resolveContractsMatching(
            in: store,
            contractIdStr: contractIdStr,
            rawQuery: rawQuery,
            kind: kind,
            includeSettled: false
        )

        // Busca em Dívidas se aplicável
        var matchedDebts = store.activeDebts
        if kind == "financing" || kind == "loan" {
            matchedDebts = []
        } else if let contractIdStr, let uuid = UUID(uuidString: contractIdStr) {
            matchedDebts = matchedDebts.filter { $0.id == uuid }
        } else if !normQuery.isEmpty {
            let asksGenericDebt = normQuery.contains("divida") || normQuery.contains("acordo") || normQuery == "todos" || normQuery == "todas"
            if !asksGenericDebt {
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

        // Localiza contrato ativo com busca inteligente (inclui termos genéricos como 'emprestimos' / 'financiamento')
        let activeContracts = store.contracts.filter { !$0.isSettled }
        let candidates = resolveContractsMatching(
            in: store,
            contractIdStr: contractIdStr,
            rawQuery: query,
            kind: "any",
            includeSettled: false
        )

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

        let kpiSummary = store.buildUnifiedFinancialKPISummary(referenceDate: store.selectedMonth, isAnnual: false)
        let saldoPrevistoAtual = kpiSummary.isPast ? kpiSummary.projectedAccountBalance : kpiSummary.balanceIfAllBudgetsConsumed
        baseResult["currentSaldoPrevistoFimDoMes"] = saldoPrevistoAtual
        baseResult["sobraAposPlanejamento"] = kpiSummary.surplusAfterPlanning
        baseResult["liquidCheckingBalanceNow"] = kpiSummary.currentAccountBalanceNow

        // Sempre calcula projeção mensal recorrente via LoanProjectionEngine quando solicitada OU quando aporte único elimina 0 parcelas
        let singleShotElim = (baseResult["eliminatedInstallmentsCount"] as? Int) ?? 0
        if recurringMonthly || singleShotElim == 0 {
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
            if let proj = simulateLoanProjectionSafe(for: contract, draftPlan: draftPlan, in: store) {
                let expectedMonthEndCashAfterExtra = store.expectedMonthEndCashBalance(
                    for: today,
                    contractId: contract.id,
                    draftPlan: draftPlan,
                    draftProjection: proj
                )
                baseResult["recurringMonthlyProjection"] = [
                    "monthlyExtraPayment": extraPayment,
                    "originalRemainingMonths": proj.originalRemainingMonths,
                    "projectedMonthsWithPlan": proj.projectedActiveMonths,
                    "monthsSavedWithPlan": proj.monthsSaved,
                    "savedTimeWithPlan": formatEliminatedMonthsString(proj.monthsSaved),
                    "projectedPayoffDate": BRLFormatters.shortDate(proj.projectedMaturityDate),
                    "originalMaturityDate": BRLFormatters.shortDate(proj.originalMaturityDate),
                    "totalInterestSaved": LoanProjectionEngine.toDouble(proj.totalInterestSaved),
                    "doesAchieveFullPayoff": proj.doesPlanAchieveFullPayoff,
                    "expectedMonthEndCashBalanceAfterExtra": expectedMonthEndCashAfterExtra,
                    "isAffordableInCurrentMonthCash": expectedMonthEndCashAfterExtra >= 0
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

        let kpi = store.buildUnifiedFinancialKPISummary(referenceDate: targetDate, isAnnual: false)
        let saldoPrevisto = kpi.isPast ? kpi.projectedAccountBalance : kpi.balanceIfAllBudgetsConsumed

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
            "sobraAposPlanejamento": kpi.surplusAfterPlanning,
            "savingsRatePercent": savingsRate,
            "remainingBudgetCaps": isPast ? 0.0 : remainingProvisions,
            "remainingCategoryCeilings": kpi.categoryCeilingsRemaining,
            "remainingSpecificQuotas": kpi.specificQuotasRemaining,
            "totalPlannedExpensesWithBudgets": kpi.totalPlannedExpenses,
            "liquidCheckingBalanceNow": checkingNow,
            "investmentsBalanceNow": investedNow,
            "consolidatedInvestmentsBalance": store.consolidatedInvestmentsBalance,
            "totalPatrimonyNow": patrimonyNow,
            "totalPatrimonyDashboard": checkingNow + store.consolidatedInvestmentsBalance,
            "saldoPrevistoFimDoMes": saldoPrevisto,
            "saldoPrevistoSemConsumirOrcamentos": kpi.projectedAccountBalance,
            "projectedMonthEndCash": store.accumulatedConsolidatedBalance(throughMonth: targetDate),
            "topPendingExpenses": pendingExpenses
        ]
    }
}

// MARK: - 4. Tool: get_projected_cash_flow_range

@MainActor
public struct GetProjectedCashFlowRangeTool: AIToolProtocol {
    public let name: String = "get_projected_cash_flow_range"
    public let description: String = "Consulta a projeção mês a mês de fluxo de caixa para horizontes futuros (receitas projetadas, despesas, parcelas de contratos com cenário Real ou Planejado, balanço mensal, Saldo Previsto e saldo acumulado)."

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
        var firstDeficitSaldoPrevistoMonth: String? = nil
        var minBalance: Double = Double.greatestFiniteMagnitude
        var minSaldoPrevisto: Double = Double.greatestFiniteMagnitude
        var sumNet: Double = 0.0

        for i in 0..<count {
            guard let cur = cal.date(byAdding: .month, value: i, to: startDate) else { continue }
            let monthLabel = BRLFormatters.monthYear(cur)
            let income = store.monthlyIncome(for: cur)
            let expense = store.projectedMonthlyExpense(for: cur)
            let net = store.projectedMonthlyNetBalance(for: cur)
            let accum = store.accumulatedConsolidatedBalance(throughMonth: cur)

            let kpi = store.buildUnifiedFinancialKPISummary(referenceDate: cur, isAnnual: false)
            let saldoPrevisto = kpi.isPast ? kpi.projectedAccountBalance : kpi.balanceIfAllBudgetsConsumed

            sumNet += net
            if accum < minBalance {
                minBalance = accum
            }
            if saldoPrevisto < minSaldoPrevisto {
                minSaldoPrevisto = saldoPrevisto
            }
            if accum < 0 && firstDeficitMonth == nil {
                firstDeficitMonth = monthLabel
            }
            if saldoPrevisto < 0 && firstDeficitSaldoPrevistoMonth == nil {
                firstDeficitSaldoPrevistoMonth = monthLabel
            }

            monthsArray.append([
                "month": monthLabel,
                "projectedIncome": income,
                "projectedExpense": expense,
                "projectedNet": net,
                "sobraAposPlanejamento": kpi.surplusAfterPlanning,
                "saldoPrevistoFimDoMes": saldoPrevisto,
                "saldoSemConsumirOrcamentos": kpi.projectedAccountBalance,
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
            "lowestSaldoPrevisto": minSaldoPrevisto == Double.greatestFiniteMagnitude ? 0.0 : minSaldoPrevisto,
            "firstDeficitMonth": firstDeficitMonth as Any,
            "firstDeficitSaldoPrevistoMonth": firstDeficitSaldoPrevistoMonth as Any,
            "hasRunwayRisk": firstDeficitMonth != nil || firstDeficitSaldoPrevistoMonth != nil,
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
            .filter { $0.type == .expense && !$0.ignoreInConsolidated && !$0.isCreditCardInvoicePayment && store.isTransactionVisibleInCurrentScenario($0) }
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

        let creditCardsJson: [[String: Any]] = store.creditCards.map { card in
            let used = store.usedLimit(for: card.id)
            let avail = store.availableLimit(for: card.id)
            let cycle = CreditCardEngine.allocateInvoice(forPurchaseDate: store.selectedMonth, card: card)
            let invSummary = store.invoiceSummary(for: card.id, year: cycle.year, month: cycle.month)
            return [
                "id": card.id.uuidString,
                "name": card.name,
                "brand": card.brand.rawValue,
                "totalLimit": card.totalLimit,
                "usedLimit": used,
                "availableLimit": avail,
                "closingDay": card.closingDay,
                "bestPurchaseDay": card.bestPurchaseDay,
                "dueDay": card.dueDay,
                "currentInvoiceMonth": cycle.month,
                "currentInvoiceYear": cycle.year,
                "currentInvoiceAmount": invSummary?.totalAmount ?? 0.0,
                "currentInvoiceStatus": invSummary?.status.rawValue ?? CreditCardInvoiceStatus.open.rawValue
            ]
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
                "creditCardsCount": store.creditCards.count,
                "totalCreditCardsUsedLimit": store.creditCards.reduce(0.0) { $0 + store.usedLimit(for: $1.id) },
                "transactionsCount": store.transactions.count
            ],
            "accounts": accountsJson,
            "creditCards": creditCardsJson,
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

        let candidates = resolveContractsMatching(
            in: store,
            contractIdStr: contractIdStr,
            rawQuery: query,
            kind: "any",
            includeSettled: false
        )

        let selected: CreditContract?
        if let contractIdStr, UUID(uuidString: contractIdStr) != nil {
            selected = candidates.first
        } else if !query.isEmpty {
            selected = candidates.first
        } else if activeContracts.count == 1 {
            selected = activeContracts.first
        } else {
            selected = nil
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
            projection = simulateLoanProjectionSafe(for: contract, draftPlan: draft, in: store)
        } else {
            isSimulatedDraft = false
            usedPlan = store.amortizationPlan(for: contract.id)
            projection = simulateLoanProjectionSafe(for: contract, draftPlan: nil, in: store)
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
            txs = txs.filter { $0.type == .expense && !$0.isCreditCardInvoicePayment }
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
        let paidDebts = store.debts.filter(\.isPaid)
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

        let kpi = store.buildUnifiedFinancialKPISummary(referenceDate: store.selectedMonth, isAnnual: false)
        let saldoPrevisto = kpi.isPast ? kpi.projectedAccountBalance : kpi.balanceIfAllBudgetsConsumed
        let openDebtsTotal = openDebts.reduce(0.0) { $0 + $1.originalAmount }

        if openDebts.isEmpty {
            return [
                "status": "success",
                "message": "O usuário não possui nenhuma dívida em aberto (isPaid == false) cadastrada no momento.",
                "openDebtsCount": 0,
                "openDebtsTotalAmount": 0.0,
                "paidDebtsCount": paidDebts.count,
                "paidDebtsExcludedNote": "Dívidas já quitadas (isPaid == true) não entram como pendências em aberto.",
                "liquidCheckingBalanceNow": kpi.currentAccountBalanceNow,
                "saldoPrevistoFimDoMes": saldoPrevisto,
                "sobraAposPlanejamento": kpi.surplusAfterPlanning,
                "investmentsConsolidatedBalance": store.consolidatedInvestmentsBalance,
                "openDebts": []
            ]
        }

        // Calcula capacidade real de pagamento nos próximos meses
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
        let investedConsolidated = store.consolidatedInvestmentsBalance

        let targetDebts = matchedDebts.isEmpty ? openDebts : matchedDebts
        let analysisList: [[String: Any]] = targetDebts.map { d in
            let amount = d.originalAmount
            let canPayCashNow = checkingNow >= amount
            let canPayWithinSaldoPrevisto = saldoPrevisto >= amount
            let canPayWithInvestments = (checkingNow + investedConsolidated) >= amount
            let monthsWithAverageSurplus: Any = averageSurplus > 0
                ? Int(ceil(amount / averageSurplus))
                : "Inviável sem corte de gastos (sobra média mensal não positiva)"
            return [
                "id": d.id.uuidString,
                "name": d.name,
                "amount": amount,
                "isPaid": d.isPaid,
                "contractedDate": d.contractedDate.map { BRLFormatters.shortDate($0) } ?? "Não informada",
                "notes": d.notes,
                "canPayImmediatelyFromChecking": canPayCashNow,
                "canPayWithinSaldoPrevisto": canPayWithinSaldoPrevisto,
                "canPayIncludingInvestments": canPayWithInvestments,
                "estimatedMonthsToSaveFromMonthlySurplus": monthsWithAverageSurplus
            ]
        }

        return [
            "status": "success",
            "matchedSpecifically": !matchedDebts.isEmpty,
            "openDebtsCount": openDebts.count,
            "openDebtsTotalAmount": openDebtsTotal,
            "paidDebtsCount": paidDebts.count,
            "paidDebtsExcludedNote": "Consideradas exclusivamente dívidas em aberto (isPaid == false); \(paidDebts.count) quitada(s) excluída(s).",
            "currentMonthProjectedNet": currentMonthNet,
            "averageProjectedMonthlySurplusNext4Months": averageSurplus,
            "liquidCheckingBalanceNow": checkingNow,
            "saldoPrevistoFimDoMes": saldoPrevisto,
            "sobraAposPlanejamento": kpi.surplusAfterPlanning,
            "investmentsBalanceNow": store.totalInvestmentsBalance,
            "investmentsConsolidatedBalance": investedConsolidated,
            "debtsAnalysis": analysisList
        ]
    }
}

// MARK: - 14. Tool: query_database (Acesso SQL-like Completo a Todas as Tabelas do Banco Local)

@MainActor
public struct QueryDatabaseTool: AIToolProtocol {
    public let name: String = "query_database"
    public let description: String = "Consulta estruturada estilo SQL sobre TODAS as tabelas do banco local do FinSense: 'overview', 'kpi_summary' (inclui Saldo Previsto exato do Dashboard), 'accounts', 'contracts' (todos os financiamentos e empréstimos), 'amortization_plans', 'debts' (separa isPaid == false vs true), 'investments', 'transactions', 'provisions_and_quotas' e 'categories'."

    public let parametersSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "table": [
                "type": "string",
                "enum": [
                    "overview", "kpi_summary", "accounts", "credit_cards", "credit_card_invoices", "contracts",
                    "amortization_plans", "debts", "investments",
                    "transactions", "provisions_and_quotas", "categories"
                ],
                "description": "Tabela/coleção alvo no banco local (padrão: overview)"
            ],
            "query": [
                "type": "string",
                "description": "Filtro de busca textual opcional por nome, contrato, banco ou categoria"
            ],
            "month": [
                "type": "string",
                "description": "Mês YYYY-MM opcional para kpi_summary, transactions e provisions_and_quotas"
            ],
            "year": [
                "type": "integer",
                "description": "Ano opcional (ex: 2026) para kpi_summary ou transactions"
            ],
            "isAnnual": [
                "type": "boolean",
                "description": "Se true em kpi_summary, calcula os indicadores consolidados do ano inteiro"
            ],
            "includeSettledOrPaid": [
                "type": "boolean",
                "description": "Se true inclui contratos quitados ou lista dívidas pagas separadamente (padrão false para filtros ativos)"
            ],
            "includeIgnored": [
                "type": "boolean",
                "description": "Se true inclui também transações marcadas como ignoreInConsolidated"
            ],
            "limit": [
                "type": "integer",
                "description": "Limite máximo de linhas retornadas (padrão 25, máximo 100)"
            ]
        ]
    ]

    private let store: FinancialDataStore

    public init(store: FinancialDataStore) {
        self.store = store
    }

    public func execute(parameters: [String: Any]) async throws -> [String: Any] {
        let rawTable = normalizeSearchToken((parameters["table"] as? String) ?? "overview")
        let table = canonicalTableName(rawTable)
        let query = normalizeSearchToken((parameters["query"] as? String) ?? "")
        let isAnnual = (parameters["isAnnual"] as? Bool) ?? false
        let includeSettledOrPaid = (parameters["includeSettledOrPaid"] as? Bool) ?? false
        let includeIgnored = (parameters["includeIgnored"] as? Bool) ?? false
        let limit = min(max(extractInt(parameters["limit"]) ?? 25, 1), 100)

        var targetDate = store.selectedMonth
        if let monthStr = parameters["month"] as? String, let parsed = parseISODate(monthStr) {
            targetDate = parsed
        } else if let yr = extractInt(parameters["year"]) {
            var comps = DateComponents()
            comps.year = yr
            comps.month = store.calendar.component(.month, from: store.selectedMonth)
            comps.day = 1
            if let d = store.calendar.date(from: comps) {
                targetDate = d
            }
        }

        switch table {
        case "kpi_summary":
            let kpi = store.buildUnifiedFinancialKPISummary(referenceDate: targetDate, isAnnual: isAnnual)
            let saldoPrevisto = kpi.isPast ? kpi.projectedAccountBalance : kpi.balanceIfAllBudgetsConsumed
            return [
                "status": "success",
                "table": "kpi_summary",
                "referenceLabel": isAnnual ? BRLFormatters.yearString(targetDate) : BRLFormatters.monthYear(targetDate),
                "isAnnual": isAnnual,
                "isClosedPeriod": kpi.isPast,
                "activeScenario": store.budgetProjectionScenario.rawValue,
                "saldoAtualEmContasHoje": kpi.currentAccountBalanceNow,
                "saldoPrevistoFimDoMes": saldoPrevisto,
                "saldoPrevistoSemConsumirOrcamentos": kpi.projectedAccountBalance,
                "sobraAposPlanejamento": kpi.surplusAfterPlanning,
                "operationalNetBalance": kpi.operationalNetBalance,
                "projectedIncome": kpi.projectedIncome,
                "receivedIncome": kpi.receivedIncome,
                "pendingIncome": kpi.pendingIncome,
                "pendingIncomeOverdue": kpi.pendingIncomeOverdue,
                "recordedExpense": kpi.recordedExpense,
                "paidExpense": kpi.paidExpense,
                "pendingExpense": kpi.pendingExpense,
                "overdueExpenses": kpi.overdueExpenses,
                "remainingBudgetsAndQuotas": kpi.remainingBudgetsAndQuotas,
                "categoryCeilingsRemaining": kpi.categoryCeilingsRemaining,
                "specificQuotasRemaining": kpi.specificQuotasRemaining,
                "totalPlannedExpenses": kpi.totalPlannedExpenses,
                "consolidatedInvestmentsBalance": store.consolidatedInvestmentsBalance,
                "totalConsolidatedPatrimony": kpi.currentAccountBalanceNow + store.consolidatedInvestmentsBalance
            ]

        case "accounts":
            var list = store.accounts
            if !query.isEmpty {
                list = list.filter { normalizeSearchToken($0.name).contains(query) || normalizeSearchToken($0.accountNumber).contains(query) }
            }
            let rows: [[String: Any]] = list.prefix(limit).map { acc in
                [
                    "id": acc.id.uuidString,
                    "name": acc.name,
                    "agency": acc.agency,
                    "accountNumber": acc.accountNumber,
                    "initialBalance": acc.initialBalance,
                    "currentBalanceNow": store.currentBalance(forAccount: acc.id),
                    "projectedMonthEndBalance": store.currentBalance(forAccount: acc.id, upTo: targetDate)
                ]
            }
            return [
                "status": "success",
                "table": "accounts",
                "count": list.count,
                "totalCheckingBalanceNow": store.totalCheckingBalanceNow,
                "rows": rows
            ]

        case "credit_cards":
            var list = store.creditCards
            if !query.isEmpty {
                list = list.filter {
                    normalizeSearchToken($0.name).contains(query) ||
                    normalizeSearchToken($0.brand.rawValue).contains(query) ||
                    $0.lastFourDigits.contains(query)
                }
            }
            let rows: [[String: Any]] = list.prefix(limit).map { card in
                let used = store.usedLimit(for: card.id)
                let avail = store.availableLimit(for: card.id)
                let cycle = CreditCardEngine.allocateInvoice(forPurchaseDate: targetDate, card: card)
                let invSummary = store.invoiceSummary(for: card.id, year: cycle.year, month: cycle.month)
                return [
                    "id": card.id.uuidString,
                    "name": card.name,
                    "brand": card.brand.rawValue,
                    "lastFourDigits": card.lastFourDigits,
                    "totalLimit": card.totalLimit,
                    "usedLimit": used,
                    "availableLimit": avail,
                    "closingDay": card.closingDay,
                    "bestPurchaseDay": card.bestPurchaseDay,
                    "dueDay": card.dueDay,
                    "defaultPaymentAccount": card.defaultPaymentAccountId.flatMap { store.account(for: $0)?.name } ?? "Automática",
                    "referenceInvoiceLabel": invSummary?.monthYearLabel ?? "",
                    "referenceInvoiceAmount": invSummary?.totalAmount ?? 0.0,
                    "referenceInvoiceStatus": invSummary?.status.rawValue ?? CreditCardInvoiceStatus.open.rawValue
                ]
            }
            return [
                "status": "success",
                "table": "credit_cards",
                "count": list.count,
                "rows": rows
            ]

        case "credit_card_invoices":
            let cal = store.calendar
            let refYear = cal.component(.year, from: targetDate)
            let refMonth = cal.component(.month, from: targetDate)
            var invoiceRows: [[String: Any]] = []
            for card in store.creditCards {
                if !query.isEmpty && !normalizeSearchToken(card.name).contains(query) {
                    continue
                }
                if let summary = store.invoiceSummary(for: card.id, year: refYear, month: refMonth) {
                    if !includeSettledOrPaid && summary.status == .paid { continue }
                    invoiceRows.append([
                        "cardId": card.id.uuidString,
                        "cardName": card.name,
                        "monthYear": summary.monthYearLabel,
                        "yearMonthKey": summary.yearMonthKey,
                        "status": summary.status.rawValue,
                        "totalAmount": summary.totalAmount,
                        "closingDate": BRLFormatters.shortDate(summary.closingDate),
                        "dueDate": BRLFormatters.shortDate(summary.dueDate),
                        "transactionsCount": summary.transactions.count
                    ])
                }
            }
            return [
                "status": "success",
                "table": "credit_card_invoices",
                "count": invoiceRows.count,
                "rows": Array(invoiceRows.prefix(limit))
            ]

        case "contracts":
            var list = query.isEmpty
                ? store.contracts.filter { includeSettledOrPaid || !$0.isSettled }
                : resolveContractsMatching(in: store, contractIdStr: nil, rawQuery: query, kind: "any", includeSettled: includeSettledOrPaid)
            if list.isEmpty && query.isEmpty {
                list = store.contracts
            }
            let rows: [[String: Any]] = list.prefix(limit).map { c in
                let bal = store.currentOutstandingBalance(for: c)
                let payoff = store.projectedPayoffAmount(for: c)
                return [
                    "id": c.id.uuidString,
                    "name": c.name,
                    "kind": c.kind.rawValue,
                    "kindTitle": c.kind.title,
                    "subtype": c.subtypeDisplayName,
                    "contractNumber": c.contractNumber as Any,
                    "isSettled": c.isSettled,
                    "outstandingBalance": bal,
                    "projectedPayoffToday": payoff,
                    "estimatedDiscountOnPayoff": max(0.0, store.remainingNominalAmount(for: c) - payoff),
                    "installmentAmount": c.installmentAmount,
                    "paidInstallmentsCount": store.paidTransactionsCount(forContract: c),
                    "remainingInstallments": store.remainingInstallmentsCount(for: c),
                    "totalInstallments": c.totalInstallments,
                    "billingDaySalaryDebit": c.billingDay,
                    "bankDueDay": c.effectiveBankDueDay,
                    "monthlyInterestRatePercent": c.monthlyInterestRate,
                    "hasDecreasingInstallmentSchedule": !(c.scheduledInstallments?.isEmpty ?? true),
                    "speculativeMonthlyInstallmentGrowth": c.averageMonthlyInstallmentGrowth as Any,
                    "hasSavedAmortizationPlan": store.hasSavedAmortizationPlan(for: c.id)
                ]
            }
            let totalOutstanding = list.filter { !$0.isSettled }.reduce(0.0) { $0 + store.currentOutstandingBalance(for: $1) }
            return [
                "status": "success",
                "table": "contracts",
                "count": list.count,
                "totalActiveOutstandingBalance": totalOutstanding,
                "rows": rows
            ]

        case "amortization_plans":
            var plans = store.amortizationPlans
            if !query.isEmpty {
                plans = plans.filter { p in
                    guard let c = store.contracts.first(where: { $0.id == p.contractId }) else { return false }
                    return normalizeSearchToken(c.name).contains(query) || normalizeSearchToken(c.contractNumber ?? "").contains(query)
                }
            }
            let rows: [[String: Any]] = plans.prefix(limit).map { p in
                let cName = store.contracts.first(where: { $0.id == p.contractId })?.name ?? "Contrato"
                let proj = store.loanProjection(for: p.contractId)
                let itemsSample = p.items.sorted { $0.date < $1.date }.prefix(8).map { item -> [String: Any] in
                    [
                        "date": BRLFormatters.shortDate(item.date),
                        "amount": item.amountDouble,
                        "source": item.source.shortTitle,
                        "mode": item.mode.rawValue,
                        "status": item.status.rawValue
                    ]
                }
                var row: [String: Any] = [
                    "planId": p.id.uuidString,
                    "contractId": p.contractId.uuidString,
                    "contractName": cName,
                    "generationMode": p.generationMode.rawValue,
                    "defaultMode": p.defaultRecalculationMode.rawValue,
                    "itemsCount": p.items.count,
                    "pendingItemsCount": p.items.filter { $0.status == .pending }.count,
                    "itemsSample": itemsSample
                ]
                if let proj {
                    row["monthsSaved"] = proj.monthsSaved
                    row["projectedActiveMonths"] = proj.projectedActiveMonths
                    row["projectedMaturityDate"] = BRLFormatters.shortDate(proj.projectedMaturityDate)
                    row["totalInterestSaved"] = LoanProjectionEngine.toDouble(proj.totalInterestSaved)
                    row["doesPlanAchieveFullPayoff"] = proj.doesPlanAchieveFullPayoff
                    row["fgtsWarnings"] = proj.fgtsWarnings
                }
                return row
            }
            return [
                "status": "success",
                "table": "amortization_plans",
                "count": plans.count,
                "rows": rows
            ]

        case "debts":
            var openDebts = store.activeDebts
            var paidDebts = store.debts.filter(\.isPaid)
            if !query.isEmpty && query != "todas" && query != "todos" && query != "dividas" && query != "divida" {
                openDebts = openDebts.filter { normalizeSearchToken($0.name).contains(query) || normalizeSearchToken($0.notes).contains(query) }
                paidDebts = paidDebts.filter { normalizeSearchToken($0.name).contains(query) || normalizeSearchToken($0.notes).contains(query) }
            }
            let openRows: [[String: Any]] = openDebts.prefix(limit).map { d in
                [
                    "id": d.id.uuidString,
                    "name": d.name,
                    "originalAmount": d.originalAmount,
                    "isPaid": false,
                    "contractedDate": d.contractedDate.map { BRLFormatters.shortDate($0) } ?? "Não informada",
                    "notes": d.notes
                ]
            }
            let paidRows: [[String: Any]] = paidDebts.prefix(limit).map { d in
                [
                    "id": d.id.uuidString,
                    "name": d.name,
                    "originalAmount": d.originalAmount,
                    "negotiatedAmount": d.negotiatedAmount as Any,
                    "isPaid": true,
                    "paidDate": d.paidDate.map { BRLFormatters.shortDate($0) } ?? "Informada"
                ]
            }
            return [
                "status": "success",
                "table": "debts",
                "openDebtsCount": openDebts.count,
                "openDebtsTotalAmount": openDebts.reduce(0.0) { $0 + $1.originalAmount },
                "paidDebtsCount": paidDebts.count,
                "paidDebtsTotalAmount": paidDebts.reduce(0.0) { $0 + ($1.negotiatedAmount ?? $1.originalAmount) },
                "openDebts": openRows,
                "paidDebts": paidRows
            ]

        case "investments":
            var res = try await GetInvestmentsSummaryTool(store: store).execute(parameters: [:])
            if !query.isEmpty, let list = res["investments"] as? [[String: Any]] {
                res["investments"] = list.filter {
                    normalizeSearchToken(($0["name"] as? String) ?? "").contains(query) ||
                    normalizeSearchToken(($0["groupName"] as? String) ?? "").contains(query)
                }
            }
            res["table"] = "investments"
            return res

        case "transactions":
            if includeIgnored {
                var txs = store.transactions
                if let mStr = parameters["month"] as? String, let parsed = parseISODate(mStr) {
                    let y = store.calendar.component(.year, from: parsed)
                    let m = store.calendar.component(.month, from: parsed)
                    txs = txs.filter { store.calendar.component(.year, from: $0.date) == y && store.calendar.component(.month, from: $0.date) == m }
                }
                if !query.isEmpty {
                    txs = txs.filter { normalizeSearchToken($0.name).contains(query) || normalizeSearchToken($0.details).contains(query) }
                }
                txs.sort { $0.date > $1.date }
                let rows = txs.prefix(limit).map { tx -> [String: Any] in
                    [
                        "id": tx.id.uuidString,
                        "date": BRLFormatters.shortDate(tx.date),
                        "name": tx.name,
                        "amount": store.effectiveTransactionAmount(for: tx),
                        "type": tx.type.rawValue,
                        "isPaid": tx.isPaid,
                        "ignoreInConsolidated": tx.ignoreInConsolidated,
                        "category": store.category(for: tx.categoryId)?.name ?? "Geral",
                        "account": store.account(for: tx.accountId)?.name ?? "Conta"
                    ]
                }
                return [
                    "status": "success",
                    "table": "transactions",
                    "includeIgnored": true,
                    "totalCount": txs.count,
                    "rows": rows
                ]
            } else {
                var params: [String: Any] = ["limit": limit]
                if !query.isEmpty { params["searchQuery"] = query }
                if let m = parameters["month"] as? String { params["month"] = m }
                var res = try await QueryTransactionsTool(store: store).execute(parameters: params)
                res["table"] = "transactions"
                return res
            }

        case "provisions_and_quotas":
            var params: [String: Any] = [:]
            if let m = parameters["month"] as? String { params["month"] = m }
            var res = try await GetBudgetCapsStatusTool(store: store).execute(parameters: params)
            res["table"] = "provisions_and_quotas"
            return res

        case "categories":
            var cats = store.categories
            if !query.isEmpty {
                cats = cats.filter { normalizeSearchToken($0.name).contains(query) }
            }
            let rows = cats.prefix(limit).map { c -> [String: Any] in
                [
                    "id": c.id.uuidString,
                    "name": c.name,
                    "type": c.type.rawValue,
                    "isSystemDefault": c.isSystemDefault
                ]
            }
            return [
                "status": "success",
                "table": "categories",
                "count": cats.count,
                "rows": rows
            ]

        default:
            var overview = try await GetFinancialOverviewTool(store: store).execute(parameters: [:])
            let kpi = store.buildUnifiedFinancialKPISummary(referenceDate: targetDate, isAnnual: isAnnual)
            let saldoPrevisto = kpi.isPast ? kpi.projectedAccountBalance : kpi.balanceIfAllBudgetsConsumed
            overview["table"] = "overview"
            overview["kpiSummary"] = [
                "saldoAtualEmContasHoje": kpi.currentAccountBalanceNow,
                "saldoPrevistoFimDoMes": saldoPrevisto,
                "saldoPrevistoSemConsumirOrcamentos": kpi.projectedAccountBalance,
                "sobraAposPlanejamento": kpi.surplusAfterPlanning,
                "remainingBudgetsAndQuotas": kpi.remainingBudgetsAndQuotas,
                "consolidatedInvestmentsBalance": store.consolidatedInvestmentsBalance
            ]
            overview["amortizationPlansCount"] = store.amortizationPlans.count
            return overview
        }
    }

    private func canonicalTableName(_ raw: String) -> String {
        switch raw {
        case "kpi", "kpi_summary", "saldo_previsto", "resumo", "dashboard":
            return "kpi_summary"
        case "account", "accounts", "conta", "contas":
            return "accounts"
        case "credit_card", "credit_cards", "cartao", "cartoes", "cartao_credito":
            return "credit_cards"
        case "credit_card_invoice", "credit_card_invoices", "fatura", "faturas":
            return "credit_card_invoices"
        case "contract", "contracts", "contrato", "contratos", "emprestimo", "emprestimos", "financiamento", "financiamentos":
            return "contracts"
        case "amortization_plan", "amortization_plans", "plano", "planos", "amortizacoes":
            return "amortization_plans"
        case "debt", "debts", "divida", "dividas":
            return "debts"
        case "investment", "investments", "investimento", "investimentos":
            return "investments"
        case "transaction", "transactions", "transacao", "transacoes", "lancamentos":
            return "transactions"
        case "provision", "provisions", "provisions_and_quotas", "orcamentos", "tetos", "cotas", "provisoes":
            return "provisions_and_quotas"
        case "category", "categories", "categoria", "categorias":
            return "categories"
        default:
            return "overview"
        }
    }
}

// MARK: - 15. Context Builder Determinístico para Grounding Obrigatório (Zero Alucinação na Apple Intelligence)

@MainActor
public enum FinancialDatabaseContextBuilder {

    public static func shouldGroundPrompt(prompt: String, draftReply: String) -> Bool {
        let p = normalizeSearchToken(prompt)
        let r = normalizeSearchToken(draftReply)

        let draftFailureCues = [
            "posso prosseguir", "preciso verificar", "preciso confirmar",
            "deseja que eu", "gostaria que eu", "precisa ser esclarecida",
            "[consultando", "nao fornece", "nao detectou", "sem acesso",
            "consultar diretamente o banco", "entrar em contato com"
        ]
        if draftFailureCues.contains(where: { r.contains($0) }) {
            return true
        }

        let financialTopics = [
            "emprestim", "financiament", "contrat", "divid", "saldo", "previsto",
            "simul", "amortiz", "quit", "fluxo", "projet", "gast", "despes",
            "receit", "teto", "cota", "provis", "invest", "conta", "parcela",
            "orcament", "caixa", "sobra", "patrimon", "quanto",
            "cartao", "cartoes", "fatura", "limite", "credito", "melhor dia",
            "dolar", "euro", "bitcoin", "btc", "usd", "cambio", "cotacao",
            "selic", "cdi", "ipca", "inflacao", "tesouro", "cdb", "lci", "lca", "fii"
        ]
        return financialTopics.contains { p.contains($0) }
    }

    public static func buildGroundedContextSnapshot(
        for prompt: String,
        store: FinancialDataStore
    ) async -> (steps: [String], compactJson: String) {
        let norm = normalizeSearchToken(prompt)
        var executedSteps: [String] = []
        var bundle: [String: Any] = [:]

        // 1. Contrato específico ou simulação de quitação / amortização
        let matchedContracts = resolveContractsMatching(
            in: store,
            contractIdStr: nil,
            rawQuery: prompt,
            kind: "any",
            includeSettled: false
        )
        let asksSimulation = norm.contains("quitar") || norm.contains("quitacao") || norm.contains("amortiz") ||
            norm.contains("simular") || norm.contains("simulacao") || norm.contains("plano de acao") ||
            norm.contains("menor prazo")

        if asksSimulation, let contract = matchedContracts.first {
            executedSteps.append("⚡ Executando LoanProjectionEngine em '\(contract.name)' + validando Saldo Previsto...")
            if let details = try? await GetContractDetailsTool(store: store).execute(parameters: ["contractId": contract.id.uuidString]),
               let rows = details["contracts"] as? [[String: Any]], let first = rows.first {
                let bal = (first["outstandingBalance"] as? Double) ?? store.currentOutstandingBalance(for: contract)
                let payoff = (first["projectedPayoffToday"] as? Double) ?? store.projectedPayoffAmount(for: contract)
                let inst = (first["installmentAmount"] as? Double) ?? contract.installmentAmount
                bundle["contrato"] = [
                    "id": first["id"] ?? "",
                    "nome": first["name"] ?? contract.name,
                    "tipo": first["subtype"] ?? contract.subtypeDisplayName,
                    "numeroContrato": first["contractNumber"] ?? (contract.contractNumber ?? ""),
                    "saldoDevedorAtualHoje": BRLFormatters.currency(bal),
                    "valorParaQuitarHoje": BRLFormatters.currency(payoff),
                    "valorDaParcelaMensal": BRLFormatters.currency(inst),
                    "parcelasPagas": first["paidInstallmentsCount"] ?? 0,
                    "parcelasRestantes": first["remainingInstallments"] ?? 0,
                    "totalParcelas": first["totalInstallments"] ?? contract.totalInstallments
                ]
            }

            if let planRes = try? await GetLoanProjectionAndPlanTool(store: store).execute(parameters: ["contractId": contract.id.uuidString]),
               (planRes["hasSavedPlanOnDatabase"] as? Bool) == true {
                let savedInt = (planRes["totalInterestSaved"] as? Double) ?? 0.0
                bundle["planoDeAmortizacaoSalvoNoBanco"] = [
                    "mesesEconomizados": planRes["monthsSaved"] ?? 0,
                    "economiaTotalDeJurosNoContrato": BRLFormatters.currency(savedInt),
                    "dataQuitacaoPrevista": planRes["projectedMaturityDate"] ?? "",
                    "aportesPendentesCount": planRes["plannedItemsCount"] ?? 0
                ]
            } else {
                bundle["planoDeAmortizacaoSalvoNoBanco"] = ["possuiPlanoSalvo": false]
            }

            let amounts: [Double]
            if let customExtra = extractCustomMonthlyAmount(from: prompt) {
                amounts = [customExtra]
            } else {
                amounts = [500.0, 1000.0, 2000.0]
            }
            var scenarios: [[String: Any]] = []
            let simTool = SimulateAmortizationTool(store: store)
            for amt in amounts {
                if let res = try? await simTool.execute(parameters: [
                    "contractId": contract.id.uuidString,
                    "extraPayment": amt,
                    "mode": "reduce_term",
                    "recurringMonthly": true
                ]) {
                    let rec = (res["recurringMonthlyProjection"] as? [String: Any]) ?? [:]
                    let monthsSaved = (rec["monthsSavedWithPlan"] as? Int) ?? 0
                    let interestSaved = (rec["totalInterestSaved"] as? Double) ?? 0.0
                    let endCash = (rec["expectedMonthEndCashBalanceAfterExtra"] as? Double) ?? (res["currentSaldoPrevistoFimDoMes"] as? Double) ?? 0.0
                    scenarios.append([
                        "aporteExtraMensal": BRLFormatters.currency(amt),
                        "parcelasEliminadasTotal": monthsSaved,
                        "novoPrazoRestanteMeses": rec["projectedMonthsWithPlan"] ?? res["newRemainingInstallments"] ?? 0,
                        "economiaTotalDeJurosNoContrato": BRLFormatters.currency(interestSaved),
                        "novaDataDeQuitacaoTotal": rec["projectedPayoffDate"] ?? "",
                        "saldoPrevistoFimDoMesComEsseAporte": BRLFormatters.currency(endCash),
                        "viavelNoSaldoPrevisto": endCash >= 0
                    ])
                }
            }
            bundle["cenariosMensaisSimulados"] = scenarios
        } else if norm.contains("emprestim") || norm.contains("financiament") || norm.contains("contrat") {
            executedSteps.append("🗄️ Consultando tabela 'contracts' no banco local FinSense...")
            if let contractsRes = try? await QueryDatabaseTool(store: store).execute(parameters: ["table": "contracts"]) {
                bundle["contracts"] = contractsRes
            }
        }

        // 2. Dívidas em aberto (isPaid == false) vs pagas
        if norm.contains("divid") || norm.contains("acordo") {
            executedSteps.append("💎 Consultando tabela 'debts' e estratégia de quitação (isPaid == false)...")
            if let debtsRes = try? await AnalyzeDebtPayoffStrategyTool(store: store).execute(parameters: [:]) {
                bundle["debtsAnalysis"] = debtsRes
            }
        }

        // 3. Investimentos & Cartões de Crédito
        if norm.contains("cartao") || norm.contains("fatura") || norm.contains("limite") {
            executedSteps.append("💳 Consultando cartões de crédito e faturas no banco FinSense...")
            if let cardsRes = try? await QueryDatabaseTool(store: store).execute(parameters: ["table": "credit_cards"]) {
                bundle["creditCards"] = cardsRes
            }
            if let invsRes = try? await QueryDatabaseTool(store: store).execute(parameters: ["table": "credit_card_invoices"]) {
                bundle["creditCardInvoices"] = invsRes
            }
        }
        if norm.contains("invest") || norm.contains("reserv") || norm.contains("caixinha") || norm.contains("divid") {
            executedSteps.append("🗄️ Consultando tabela 'investments' no banco FinSense...")
            if let invRes = try? await QueryDatabaseTool(store: store).execute(parameters: ["table": "investments"]) {
                bundle["investments"] = invRes
            }
        }

        // 4. Fluxo de caixa mensal + Saldo Previsto + Sobra Após Planejamento
        executedSteps.append("💵 Calculando KPIs e Saldo Previsto exato do mês ativo...")
        if let kpiRes = try? await QueryDatabaseTool(store: store).execute(parameters: ["table": "kpi_summary"]) {
            bundle["kpiDashboard"] = kpiRes
        }

        // 5. Projeção futura, transações ou tetos conforme tema da pergunta
        if norm.contains("projec") || norm.contains("futur") || norm.contains("debito") || norm.contains("meses") {
            executedSteps.append("📈 Projetando fluxo de caixa dos próximos 12 meses...")
            if let projRes = try? await GetProjectedCashFlowRangeTool(store: store).execute(parameters: ["numberOfMonths": 12]) {
                bundle["projectedCashFlow12m"] = projRes
            }
        }
        if norm.contains("gast") || norm.contains("despes") || norm.contains("receit") || norm.contains("transac") || norm.contains("categoria") || norm.contains("mercado") {
            executedSteps.append("🔍 Agregando transações por categoria...")
            if let aggRes = try? await AggregateTransactionsTool(store: store).execute(parameters: ["type": "expense", "groupBy": "category"]) {
                bundle["transactionsAggregated"] = aggRes
            }
        }
        if norm.contains("teto") || norm.contains("cota") || norm.contains("orcament") || norm.contains("provis") {
            executedSteps.append("📌 Consultando tetos e cotas de orçamento...")
            if let capsRes = try? await GetBudgetCapsStatusTool(store: store).execute(parameters: [:]) {
                bundle["budgetsAndQuotas"] = capsRes
            }
        }

        // 6. Consultas públicas na internet (apenas leitura, sem enviar dados financeiros pessoais)
        let wantsWebInfo = InternetLookupService.isCurrencyQuery(norm) ||
            InternetLookupService.isMacroRateQuery(norm) ||
            norm.contains("recomend") ||
            norm.contains("aplicar") ||
            norm.contains("onde investir") ||
            norm.contains("internet")
        if wantsWebInfo {
            executedSteps.append("🌐 Consultando internet (somente leitura) sem enviar dados pessoais...")
            let webRes = try? await InternetLookupTool(store: store).execute(parameters: ["query": prompt])
            if let webRes {
                bundle["webLookup"] = webRes
            }
        }

        let compactJson: String = {
            guard let data = try? JSONSerialization.data(withJSONObject: bundle, options: [.sortedKeys]),
                  let str = String(data: data, encoding: .utf8) else {
                return "{}"
            }
            return str.count > 3600 ? String(str.prefix(3600)) + "...}" : str
        }()

        return (executedSteps, compactJson)
    }

    /// Extrai valor monetário único informado pelo usuário (ex: "R$ 1.500", "2 mil por mês"),
    /// ignorando prompts multi-cenário ou números de contrato longos.
    private static func extractCustomMonthlyAmount(from rawPrompt: String) -> Double? {
        let norm = normalizeSearchToken(rawPrompt)
        if norm.contains("500") && norm.contains("1.000") && norm.contains("2.000") {
            return nil
        }

        var candidates: [Double] = []
        let patterns = [
            "r\\$\\s*([0-9][0-9\\.]*(?:,[0-9]{1,2})?)",
            "([0-9]+(?:[.,][0-9]+)?)\\s*mil\\b",
            "(?:amortizar|amortizasse|aportar|aporte|extra|extras|colocar)\\s+(?:r\\$\\s*)?([0-9][0-9\\.]*(?:,[0-9]{1,2})?)"
        ]

        for (idx, pattern) in patterns.enumerated() {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let ns = norm as NSString
            let matches = regex.matches(in: norm, range: NSRange(location: 0, length: ns.length))
            for m in matches where m.numberOfRanges > 1 {
                let rawToken = ns.substring(with: m.range(at: 1))
                let parsed: Double?
                if idx == 1 {
                    let num = Double(rawToken.replacingOccurrences(of: ",", with: "."))
                    parsed = num.map { $0 * 1000.0 }
                } else {
                    parsed = extractDouble(rawToken)
                }
                if let val = parsed, val >= 50.0, val < 500_000.0 {
                    candidates.append(val)
                }
            }
        }

        let unique = Set(candidates.map { ($0 * 100.0).rounded() / 100.0 })
        return unique.count == 1 ? unique.first : nil
    }
}
