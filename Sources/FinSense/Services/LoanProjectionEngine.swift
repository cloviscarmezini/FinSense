import Foundation

// MARK: - Camada 3: Read Model & Estruturas Imutáveis do Motor de Projeção (Decimal Puro)

/// Tipo de evento na linha do tempo cronológica de evolução da dívida
public enum LoanProjectionEventKind: String, Codable, Hashable {
    case regularInstallment = "Parcela Normal"
    case extraAmortization = "Amortização Extra (Dinheiro)"
    case fgtsAmortization = "Amortização Extra (FGTS)"
}

/// Linha individual da evolução cronológica mês a mês / evento a evento (Saída Obrigatória da Simulação)
public struct LoanProjectionTimelineRow: Identifiable, Hashable {
    public let id: UUID
    public let date: Date
    public let yearMonthKey: Int
    public let eventKind: LoanProjectionEventKind
    public let title: String
    public let installmentIndex: Int?
    public let linkedTransactionId: UUID?
    public let linkedPlannedAmortizationId: UUID?
    public let initialBalance: Decimal
    public let trCorrection: Decimal
    public let correctedBalance: Decimal
    public let interestAmount: Decimal
    public let normalAmortization: Decimal
    public let extraAmortization: Decimal
    public let changeLeftover: Decimal
    public let baseInstallment: Decimal
    public let insuranceFee: Decimal
    public let adminFee: Decimal
    public let totalBudgetOutflow: Decimal
    public let finalBalance: Decimal
    public let remainingTermMonthsAfter: Int
    public let status: ProjectedInstallmentStatus
    public let fgtsValidationWarning: String?
    public let isFGTSFullPayoffExempt: Bool

    public init(
        id: UUID = UUID(),
        date: Date,
        yearMonthKey: Int,
        eventKind: LoanProjectionEventKind,
        title: String,
        installmentIndex: Int? = nil,
        linkedTransactionId: UUID? = nil,
        linkedPlannedAmortizationId: UUID? = nil,
        initialBalance: Decimal,
        trCorrection: Decimal = .zero,
        correctedBalance: Decimal,
        interestAmount: Decimal = .zero,
        normalAmortization: Decimal = .zero,
        extraAmortization: Decimal = .zero,
        changeLeftover: Decimal = .zero,
        baseInstallment: Decimal = .zero,
        insuranceFee: Decimal = .zero,
        adminFee: Decimal = .zero,
        totalBudgetOutflow: Decimal,
        finalBalance: Decimal,
        remainingTermMonthsAfter: Int,
        status: ProjectedInstallmentStatus,
        fgtsValidationWarning: String? = nil,
        isFGTSFullPayoffExempt: Bool = false
    ) {
        self.id = id
        self.date = date
        self.yearMonthKey = yearMonthKey
        self.eventKind = eventKind
        self.title = title
        self.installmentIndex = installmentIndex
        self.linkedTransactionId = linkedTransactionId
        self.linkedPlannedAmortizationId = linkedPlannedAmortizationId
        self.initialBalance = initialBalance
        self.trCorrection = trCorrection
        self.correctedBalance = correctedBalance
        self.interestAmount = interestAmount
        self.normalAmortization = normalAmortization
        self.extraAmortization = extraAmortization
        self.changeLeftover = changeLeftover
        self.baseInstallment = baseInstallment
        self.insuranceFee = insuranceFee
        self.adminFee = adminFee
        self.totalBudgetOutflow = totalBudgetOutflow
        self.finalBalance = finalBalance
        self.remainingTermMonthsAfter = remainingTermMonthsAfter
        self.status = status
        self.fgtsValidationWarning = fgtsValidationWarning
        self.isFGTSFullPayoffExempt = isFGTSFullPayoffExempt
    }
}

/// Resultado calculado dinamicamente para cada aporte planejado (`PlannedAmortization`) na lista do usuário
public struct PlannedItemProjectionOutcome: Identifiable, Hashable {
    public let id: UUID // PlannedAmortization.id
    public let date: Date
    public let requestedAmount: Decimal
    public let proRataInterest: Decimal
    public let effectiveAmortization: Decimal
    public let changeLeftover: Decimal
    public let balanceBefore: Decimal
    public let remainingBalanceAfter: Decimal
    public let remainingTermMonthsAfter: Int
    public let newProjectedInstallment: Decimal
    public let isFullPayoffStep: Bool
    public let fgtsValidationWarning: String?
    public let isFGTSFullPayoffExempt: Bool

    public init(
        id: UUID,
        date: Date,
        requestedAmount: Decimal,
        proRataInterest: Decimal = .zero,
        effectiveAmortization: Decimal,
        changeLeftover: Decimal = .zero,
        balanceBefore: Decimal,
        remainingBalanceAfter: Decimal,
        remainingTermMonthsAfter: Int,
        newProjectedInstallment: Decimal,
        isFullPayoffStep: Bool,
        fgtsValidationWarning: String? = nil,
        isFGTSFullPayoffExempt: Bool = false
    ) {
        self.id = id
        self.date = date
        self.requestedAmount = requestedAmount
        self.proRataInterest = proRataInterest
        self.effectiveAmortization = effectiveAmortization
        self.changeLeftover = changeLeftover
        self.balanceBefore = balanceBefore
        self.remainingBalanceAfter = remainingBalanceAfter
        self.remainingTermMonthsAfter = remainingTermMonthsAfter
        self.newProjectedInstallment = newProjectedInstallment
        self.isFullPayoffStep = isFullPayoffStep
        self.fgtsValidationWarning = fgtsValidationWarning
        self.isFGTSFullPayoffExempt = isFGTSFullPayoffExempt
    }
}

/// Resultado consolidado da simulação dinâmica (Camada 3 — Read Model em Memória)
public struct LoanProjectionResult: Hashable {
    public let contractId: UUID
    public let currentRealBalance: Decimal
    public let projectedFinalBalanceAfterPlan: Decimal
    public let timeline: [LoanProjectionTimelineRow]
    public let baselineTimeline: [LoanProjectionTimelineRow]
    public let plannedItemOutcomes: [UUID: PlannedItemProjectionOutcome]

    // Comparativo Original vs Projetado
    public let originalMaturityDate: Date
    public let projectedMaturityDate: Date
    public let originalRemainingMonths: Int
    public let projectedActiveMonths: Int
    public let monthsSaved: Int

    // Juros e Economia
    public let originalTotalInterest: Decimal
    public let projectedTotalInterest: Decimal
    public let totalInterestSaved: Decimal
    public let totalExtraAmortized: Decimal
    public let totalChangeLeftover: Decimal
    public let doesPlanAchieveFullPayoff: Bool

    // Mapeamento para Orçamento e Transações (Shadowing & Redução de Prestação)
    public let shadowedInstallmentTransactionIds: Set<UUID>
    public let activeInstallmentProjectedAmounts: [UUID: Decimal]
    public let fgtsWarnings: [String]
    public let payrollOperationalTip: String?

    public init(
        contractId: UUID,
        currentRealBalance: Decimal,
        projectedFinalBalanceAfterPlan: Decimal,
        timeline: [LoanProjectionTimelineRow],
        baselineTimeline: [LoanProjectionTimelineRow],
        plannedItemOutcomes: [UUID: PlannedItemProjectionOutcome],
        originalMaturityDate: Date,
        projectedMaturityDate: Date,
        originalRemainingMonths: Int,
        projectedActiveMonths: Int,
        monthsSaved: Int,
        originalTotalInterest: Decimal,
        projectedTotalInterest: Decimal,
        totalInterestSaved: Decimal,
        totalExtraAmortized: Decimal,
        totalChangeLeftover: Decimal,
        doesPlanAchieveFullPayoff: Bool,
        shadowedInstallmentTransactionIds: Set<UUID>,
        activeInstallmentProjectedAmounts: [UUID: Decimal],
        fgtsWarnings: [String],
        payrollOperationalTip: String?
    ) {
        self.contractId = contractId
        self.currentRealBalance = currentRealBalance
        self.projectedFinalBalanceAfterPlan = projectedFinalBalanceAfterPlan
        self.timeline = timeline
        self.baselineTimeline = baselineTimeline
        self.plannedItemOutcomes = plannedItemOutcomes
        self.originalMaturityDate = originalMaturityDate
        self.projectedMaturityDate = projectedMaturityDate
        self.originalRemainingMonths = originalRemainingMonths
        self.projectedActiveMonths = projectedActiveMonths
        self.monthsSaved = monthsSaved
        self.originalTotalInterest = originalTotalInterest
        self.projectedTotalInterest = projectedTotalInterest
        self.totalInterestSaved = totalInterestSaved
        self.totalExtraAmortized = totalExtraAmortized
        self.totalChangeLeftover = totalChangeLeftover
        self.doesPlanAchieveFullPayoff = doesPlanAchieveFullPayoff
        self.shadowedInstallmentTransactionIds = shadowedInstallmentTransactionIds
        self.activeInstallmentProjectedAmounts = activeInstallmentProjectedAmounts
        self.fgtsWarnings = fgtsWarnings
        self.payrollOperationalTip = payrollOperationalTip
    }
}

// MARK: - Motor de Projeção em Tempo Real (Decimal Estrito)

public enum LoanProjectionEngine {

    // MARK: - Funções Utilitárias de Precisão Decimal

    public static func toDecimal(_ value: Double) -> Decimal {
        let roundedCents = (value * 10000.0).rounded() / 10000.0
        return Decimal(string: String(format: "%.4f", roundedCents)) ?? Decimal(roundedCents)
    }

    public static func toDouble(_ value: Decimal) -> Double {
        NSDecimalNumber(decimal: value).doubleValue
    }

    public static func roundCurrency(_ value: Decimal) -> Decimal {
        var input = value
        var result = Decimal.zero
        NSDecimalRound(&result, &input, 2, .plain)
        return result
    }

    /// Calcula juros pro-rata die para Santander Consignado entre dois eventos separados por `d` dias corridos:
    /// $$J = \text{Saldo} \times \left((1 + i_m)^{\frac{d}{30}} - 1\right)$$
    public static func calculateSantanderProRataInterest(
        balance: Decimal,
        monthlyRateDecimal: Decimal,
        daysElapsed: Int
    ) -> Decimal {
        guard balance > .zero, monthlyRateDecimal > .zero, daysElapsed > 0 else {
            return .zero
        }
        if daysElapsed == 30 {
            return roundCurrency(balance * monthlyRateDecimal)
        }
        let imDouble = toDouble(monthlyRateDecimal)
        let exponent = Double(daysElapsed) / 30.0
        let factorDouble = pow(1.0 + imDouble, exponent) - 1.0
        let factorDecimal = Decimal(string: String(format: "%.10f", factorDouble)) ?? Decimal(factorDouble)
        return roundCurrency(balance * factorDecimal)
    }

    /// Calcula a nova prestação base na Tabela Price (PMT) em Decimal:
    /// $$\text{PMT} = \frac{PV \times i_m}{1 - (1 + i_m)^{-n}}$$
    public static func calculatePriceBaseInstallment(
        balance: Decimal,
        monthlyRateDecimal: Decimal,
        remainingMonths: Int
    ) -> Decimal {
        guard balance > .zero, remainingMonths > 0 else { return .zero }
        guard monthlyRateDecimal > Decimal(string: "0.0000001")! else {
            return roundCurrency(balance / Decimal(remainingMonths))
        }
        let iDouble = toDouble(monthlyRateDecimal)
        let denomDouble = 1.0 - pow(1.0 + iDouble, -Double(remainingMonths))
        guard denomDouble > 0.0000001 else {
            return roundCurrency(balance / Decimal(remainingMonths))
        }
        let denomDecimal = Decimal(string: String(format: "%.10f", denomDouble)) ?? Decimal(denomDouble)
        return roundCurrency((balance * monthlyRateDecimal) / denomDecimal)
    }

    /// Calcula o novo prazo restante (N) na Tabela Price mantendo a prestação base:
    /// $$N = \left\lceil \frac{-\ln(1 - (PV \times i_m) / \text{PMT})}{\ln(1 + i_m)} \right\rceil$$
    public static func calculatePriceRemainingMonths(
        balance: Decimal,
        monthlyRateDecimal: Decimal,
        baseInstallment: Decimal,
        fallbackMaxMonths: Int
    ) -> Int {
        guard balance > Decimal(string: "0.01")!, baseInstallment > .zero else { return 0 }
        guard monthlyRateDecimal > Decimal(string: "0.0000001")! else {
            let ratio = toDouble(balance / baseInstallment)
            return max(1, Int(ceil(ratio - 1e-9)))
        }
        let pvDouble = toDouble(balance)
        let iDouble = toDouble(monthlyRateDecimal)
        let pmtDouble = toDouble(baseInstallment)
        guard pmtDouble > pvDouble * iDouble else {
            return max(fallbackMaxMonths, 1)
        }
        let ratio = 1.0 - (pvDouble * iDouble) / pmtDouble
        let calcN = -log(max(ratio, 0.0000001)) / log(1.0 + iDouble)
        return max(1, min(Int(ceil(calcN - 1e-9)), max(fallbackMaxMonths, 1)))
    }

    /// Gera a recomendação operacional para folha de pagamento (Santander Consignado)
    public static func buildPayrollOperationalTip(for contract: CreditContract) -> String? {
        guard contract.kind == .loan else { return nil }
        let salaryDay = contract.billingDay
        let bankDay = contract.effectiveBankDueDay
        let bestDay = bankDay >= 28 ? 1 : (bankDay + 1)
        if salaryDay != bankDay {
            return "Janela operacional de folha: o desconto no salário ocorre no dia \(salaryDay) e a liquidação no banco ocorre no dia \(bankDay). O melhor dia para amortizar é o 1º dia útil após o vencimento (dia \(bestDay)), garantindo que a parcela do mês já foi baixada."
        } else {
            return "Regra operacional de consignado: a liquidação no banco ocorre no dia \(bankDay). O melhor dia para amortizar é o 1º dia útil após o vencimento (dia \(bestDay)), garantindo que a parcela do mês já foi baixada."
        }
    }

    // MARK: - Simulação Cronológica Orientada a Eventos (Camada 1 + Camada 2 -> Camada 3)

    private enum InternalChronologicalEvent {
        case regularInstallment(tx: FinancialTransaction)
        case plannedAmortization(item: PlannedAmortization)

        var date: Date {
            switch self {
            case .regularInstallment(let tx): return tx.date
            case .plannedAmortization(let item): return item.date
            }
        }

        /// Ordenação no mesmo dia: Parcela normal primeiro (0), Amortização extra em seguida (1)
        var sameDayPriority: Int {
            switch self {
            case .regularInstallment: return 0
            case .plannedAmortization: return 1
            }
        }
    }

    /// Executa a simulação completa combinando a Camada 1 (Contrato e Parcelas Reais não pagas)
    /// com a Camada 2 (apenas `PlannedAmortization` com status `.pending`).
    public static func simulate(
        contract: CreditContract,
        unpaidInstallmentTransactions: [FinancialTransaction],
        currentRealBalanceDouble: Double,
        plan: AmortizationPlan?,
        calendar: Calendar = Calendar.current
    ) -> LoanProjectionResult {
        let initialBalance = roundCurrency(max(.zero, toDecimal(currentRealBalanceDouble)))
        let sortedInstallments = unpaidInstallmentTransactions
            .filter { $0.installmentIndex != nil && !$0.isPaid }
            .sorted { a, b in
                if a.date == b.date {
                    return (a.installmentIndex ?? 0) < (b.installmentIndex ?? 0)
                }
                return a.date < b.date
            }

        let pendingAmortizations = (plan?.items ?? [])
            .filter { $0.status == .pending && $0.amount > .zero }
            .sorted { a, b in
                if a.date == b.date {
                    return a.createdAt < b.createdAt
                }
                return a.date < b.date
            }

        // Parâmetros matemáticos do contrato em Decimal estrito
        let isLoan = contract.kind == .loan
        let monthlyRateDecimal: Decimal = {
            if isLoan {
                return toDecimal(contract.monthlyInterestRate) / Decimal(100)
            } else {
                // Caixa: conversão linear da taxa nominal anual i_m = annual_nominal_rate / 12 / 100
                let annualNominal = toDecimal(contract.effectiveAnnualNominalRate)
                return annualNominal / Decimal(1200)
            }
        }()

        let monthlyTRRateDecimal: Decimal = {
            guard !isLoan, (contract.indexationRate ?? .tr) == .tr else { return .zero }
            if let planTR = plan?.estimatedMonthlyTR, planTR > .zero {
                // Se o valor for armazenado como percentual (ex: 0.1 para 0,1%), converte para taxa decimal (0.001)
                return planTR >= Decimal(string: "0.01")! ? (planTR / Decimal(100)) : planTR
            }
            if let contractTR = contract.estimatedMonthlyTR, contractTR > 0 {
                let dec = toDecimal(contractTR)
                return dec >= Decimal(string: "0.01")! ? (dec / Decimal(100)) : dec
            }
            return .zero
        }()

        let initialBaseInstallment: Decimal = {
            if isLoan {
                return roundCurrency(toDecimal(contract.installmentAmount))
            } else {
                return roundCurrency(toDecimal(contract.effectiveBaseInstallmentPrice))
            }
        }()

        let initialInsuranceFee: Decimal = isLoan ? .zero : roundCurrency(toDecimal(contract.effectiveInsuranceFee))
        let fixedAdminFee: Decimal = isLoan ? .zero : roundCurrency(toDecimal(contract.effectiveAdminFee))
        let initialRemainingMonths = max(sortedInstallments.count, 1)

        // 1. Rodar Simulação Base (Camada 1 pura, sem amortizações extras) para obter Juros Originais e Data Original
        let baselineRun = runEventSimulation(
            contract: contract,
            initialBalance: initialBalance,
            monthlyRateDecimal: monthlyRateDecimal,
            monthlyTRRateDecimal: monthlyTRRateDecimal,
            initialBaseInstallment: initialBaseInstallment,
            initialInsuranceFee: initialInsuranceFee,
            fixedAdminFee: fixedAdminFee,
            initialRemainingMonths: initialRemainingMonths,
            installments: sortedInstallments,
            plannedItems: [],
            calendar: calendar
        )

        // 2. Rodar Simulação Projetada (Camada 1 + Camada 2 `.pending`)
        let projectedRun = runEventSimulation(
            contract: contract,
            initialBalance: initialBalance,
            monthlyRateDecimal: monthlyRateDecimal,
            monthlyTRRateDecimal: monthlyTRRateDecimal,
            initialBaseInstallment: initialBaseInstallment,
            initialInsuranceFee: initialInsuranceFee,
            fixedAdminFee: fixedAdminFee,
            initialRemainingMonths: initialRemainingMonths,
            installments: sortedInstallments,
            plannedItems: pendingAmortizations,
            calendar: calendar
        )

        let originalMaturityDate = contract.maturityDate
            ?? baselineRun.payoffDate
            ?? sortedInstallments.last?.date
            ?? Date()

        let projectedMaturityDate = projectedRun.payoffDate
            ?? sortedInstallments.last?.date
            ?? originalMaturityDate

        let originalRemainingMonths = baselineRun.activeInstallmentsCount
        let projectedActiveMonths = projectedRun.activeInstallmentsCount
        let monthsSaved = max(0, originalRemainingMonths - projectedActiveMonths)
        let interestSaved = max(.zero, roundCurrency(baselineRun.totalInterest - projectedRun.totalInterest))

        return LoanProjectionResult(
            contractId: contract.id,
            currentRealBalance: initialBalance,
            projectedFinalBalanceAfterPlan: projectedRun.balanceAfterLastPlannedItem,
            timeline: projectedRun.rows,
            baselineTimeline: baselineRun.rows,
            plannedItemOutcomes: projectedRun.plannedOutcomes,
            originalMaturityDate: originalMaturityDate,
            projectedMaturityDate: projectedMaturityDate,
            originalRemainingMonths: originalRemainingMonths,
            projectedActiveMonths: projectedActiveMonths,
            monthsSaved: monthsSaved,
            originalTotalInterest: baselineRun.totalInterest,
            projectedTotalInterest: projectedRun.totalInterest,
            totalInterestSaved: interestSaved,
            totalExtraAmortized: projectedRun.totalExtraAmortized,
            totalChangeLeftover: projectedRun.totalChangeLeftover,
            doesPlanAchieveFullPayoff: projectedRun.finalBalance <= Decimal(string: "0.01")!,
            shadowedInstallmentTransactionIds: projectedRun.shadowedTxIds,
            activeInstallmentProjectedAmounts: projectedRun.activeTxProjectedAmounts,
            fgtsWarnings: projectedRun.fgtsWarnings,
            payrollOperationalTip: buildPayrollOperationalTip(for: contract)
        )
    }

    // MARK: - Núcleo de Simulação Cronológica

    private struct SimulationRunOutput {
        let rows: [LoanProjectionTimelineRow]
        let plannedOutcomes: [UUID: PlannedItemProjectionOutcome]
        let totalInterest: Decimal
        let totalExtraAmortized: Decimal
        let totalChangeLeftover: Decimal
        let finalBalance: Decimal
        let balanceAfterLastPlannedItem: Decimal
        let activeInstallmentsCount: Int
        let payoffDate: Date?
        let shadowedTxIds: Set<UUID>
        let activeTxProjectedAmounts: [UUID: Decimal]
        let fgtsWarnings: [String]
    }

    private static func runEventSimulation(
        contract: CreditContract,
        initialBalance: Decimal,
        monthlyRateDecimal: Decimal,
        monthlyTRRateDecimal: Decimal,
        initialBaseInstallment: Decimal,
        initialInsuranceFee: Decimal,
        fixedAdminFee: Decimal,
        initialRemainingMonths: Int,
        installments: [FinancialTransaction],
        plannedItems: [PlannedAmortization],
        calendar: Calendar
    ) -> SimulationRunOutput {
        let isLoan = contract.kind == .loan
        var events: [InternalChronologicalEvent] = []
        events.append(contentsOf: installments.map { .regularInstallment(tx: $0) })
        events.append(contentsOf: plannedItems.map { .plannedAmortization(item: $0) })

        // Ordena por data; se no mesmo dia, processa a parcela normal primeiro e a amortização extra em seguida
        events.sort { a, b in
            let dayA = calendar.startOfDay(for: a.date)
            let dayB = calendar.startOfDay(for: b.date)
            if dayA == dayB {
                return a.sameDayPriority < b.sameDayPriority
            }
            return dayA < dayB
        }

        var runningBalance = initialBalance
        var currentBaseInstallment = initialBaseInstallment
        var currentInsuranceFee = initialInsuranceFee
        var remainingTermMonths = max(initialRemainingMonths, 1)
        var currentSACAmortizationQuota: Decimal = {
            if !isLoan && contract.amortizationSystem == .sac && remainingTermMonths > 0 {
                return roundCurrency(initialBalance / Decimal(remainingTermMonths))
            }
            return .zero
        }()

        var rows: [LoanProjectionTimelineRow] = []
        var plannedOutcomes: [UUID: PlannedItemProjectionOutcome] = [:]
        var totalInterest: Decimal = .zero
        var totalExtraAmortized: Decimal = .zero
        var totalChangeLeftover: Decimal = .zero
        var balanceAfterLastPlannedItem: Decimal = initialBalance
        var activeInstallmentsCount = 0
        var payoffDate: Date? = nil
        var shadowedTxIds: Set<UUID> = []
        var activeTxProjectedAmounts: [UUID: Decimal] = [:]
        var fgtsWarnings: [String] = []
        var lastFGTSDate: Date? = contract.lastFGTSUsageDate

        for event in events {
            let ymKey = calendar.component(.year, from: event.date) * 100 + calendar.component(.month, from: event.date)

            switch event {
            case .regularInstallment(let tx):
                // Se o saldo já zerou, esta parcela e todas as seguintes ficam `.shadowed` (R$ 0,00 no orçamento)
                if runningBalance <= Decimal(string: "0.01")! {
                    shadowedTxIds.insert(tx.id)
                    rows.append(
                        LoanProjectionTimelineRow(
                            date: tx.date,
                            yearMonthKey: ymKey,
                            eventKind: .regularInstallment,
                            title: tx.name,
                            installmentIndex: tx.installmentIndex,
                            linkedTransactionId: tx.id,
                            initialBalance: .zero,
                            trCorrection: .zero,
                            correctedBalance: .zero,
                            interestAmount: .zero,
                            normalAmortization: .zero,
                            extraAmortization: .zero,
                            changeLeftover: .zero,
                            baseInstallment: .zero,
                            insuranceFee: .zero,
                            adminFee: .zero,
                            totalBudgetOutflow: .zero,
                            finalBalance: .zero,
                            remainingTermMonthsAfter: 0,
                            status: .shadowed
                        )
                    )
                    continue
                }

                let balanceBefore = runningBalance
                let trCorrection: Decimal
                let correctedBalance: Decimal

                if !isLoan && monthlyTRRateDecimal > .zero {
                    trCorrection = roundCurrency(balanceBefore * monthlyTRRateDecimal)
                    correctedBalance = balanceBefore + trCorrection
                    if contract.amortizationSystem == .price {
                        currentBaseInstallment = roundCurrency(currentBaseInstallment * (Decimal(1) + monthlyTRRateDecimal))
                    } else if remainingTermMonths > 0 {
                        currentSACAmortizationQuota = roundCurrency(correctedBalance / Decimal(remainingTermMonths))
                    }
                } else {
                    trCorrection = .zero
                    correctedBalance = balanceBefore
                }

                let interest = roundCurrency(correctedBalance * monthlyRateDecimal)
                let rawNormalAmortization: Decimal
                let rawBaseInstallment: Decimal

                if isLoan || contract.amortizationSystem == .price {
                    rawBaseInstallment = currentBaseInstallment
                    rawNormalAmortization = max(.zero, rawBaseInstallment - interest)
                } else {
                    // SAC: Amortização normal constante = Saldo Corrigido / remaining_term_months
                    let sacAmort = remainingTermMonths > 0
                        ? roundCurrency(correctedBalance / Decimal(remainingTermMonths))
                        : correctedBalance
                    rawNormalAmortization = max(currentSACAmortizationQuota, sacAmort)
                    rawBaseInstallment = rawNormalAmortization + interest
                }

                // Zero-Balance Clamping na parcela normal caso o saldo restante seja menor que a amortização normal
                let effectiveNormalAmortization: Decimal
                let effectiveBaseInstallment: Decimal
                if rawNormalAmortization >= correctedBalance {
                    effectiveNormalAmortization = correctedBalance
                    effectiveBaseInstallment = effectiveNormalAmortization + interest
                } else {
                    effectiveNormalAmortization = rawNormalAmortization
                    effectiveBaseInstallment = rawBaseInstallment
                }

                let newBalance = max(.zero, roundCurrency(correctedBalance - effectiveNormalAmortization))

                // Seguros e Taxa de Administração compõem o fluxo de caixa (orçamento), mas NÃO entram na amortização do saldo
                let totalOutflow = roundCurrency(effectiveBaseInstallment + currentInsuranceFee + fixedAdminFee)

                // Atualiza seguro proporcionalmente para os próximos meses caso financiamento
                if !isLoan && initialBalance > Decimal(string: "0.01")! && initialInsuranceFee > .zero {
                    let ratio = max(.zero, min(Decimal(1), newBalance / initialBalance))
                    currentInsuranceFee = roundCurrency(initialInsuranceFee * ratio)
                }

                runningBalance = newBalance
                remainingTermMonths = newBalance <= Decimal(string: "0.01")! ? 0 : max(0, remainingTermMonths - 1)
                totalInterest += interest
                activeInstallmentsCount += 1
                activeTxProjectedAmounts[tx.id] = totalOutflow

                if newBalance <= Decimal(string: "0.01")! && payoffDate == nil {
                    payoffDate = tx.date
                }

                rows.append(
                    LoanProjectionTimelineRow(
                        date: tx.date,
                        yearMonthKey: ymKey,
                        eventKind: .regularInstallment,
                        title: tx.name,
                        installmentIndex: tx.installmentIndex,
                        linkedTransactionId: tx.id,
                        initialBalance: balanceBefore,
                        trCorrection: trCorrection,
                        correctedBalance: correctedBalance,
                        interestAmount: interest,
                        normalAmortization: effectiveNormalAmortization,
                        extraAmortization: .zero,
                        changeLeftover: .zero,
                        baseInstallment: effectiveBaseInstallment,
                        insuranceFee: isLoan ? .zero : currentInsuranceFee,
                        adminFee: isLoan ? .zero : fixedAdminFee,
                        totalBudgetOutflow: totalOutflow,
                        finalBalance: newBalance,
                        remainingTermMonthsAfter: remainingTermMonths,
                        status: .active
                    )
                )

            case .plannedAmortization(let item):
                let balanceBefore = runningBalance
                let requested = roundCurrency(item.amount)

                // Se a dívida já estava quitada antes deste aporte planejado:
                if balanceBefore <= Decimal(string: "0.01")! {
                    let outcome = PlannedItemProjectionOutcome(
                        id: item.id,
                        date: item.date,
                        requestedAmount: requested,
                        proRataInterest: .zero,
                        effectiveAmortization: .zero,
                        changeLeftover: requested,
                        balanceBefore: .zero,
                        remainingBalanceAfter: .zero,
                        remainingTermMonthsAfter: 0,
                        newProjectedInstallment: .zero,
                        isFullPayoffStep: false
                    )
                    plannedOutcomes[item.id] = outcome
                    totalChangeLeftover += requested
                    balanceAfterLastPlannedItem = .zero
                    continue
                }

                // Validação Legal do FGTS (Interstício mínimo de 24 meses para amortização parcial; dispensado para quitação total)
                var fgtsWarning: String? = nil
                var isFGTSExempt = false
                if item.source == .fgts {
                    if requested >= balanceBefore {
                        // Liquidação Total (Quitação): carência de 24 meses dispensada por lei!
                        isFGTSExempt = true
                    } else if let prevFGTS = lastFGTSDate {
                        let monthsDiff = calendar.dateComponents([.month], from: calendar.startOfDay(for: prevFGTS), to: calendar.startOfDay(for: item.date)).month ?? 0
                        if monthsDiff < 24 {
                            let allowedDate = calendar.date(byAdding: .month, value: 24, to: prevFGTS) ?? item.date
                            let msg = "Interstício legal do FGTS: amortização parcial exige 24 meses desde o último uso (\(BRLFormatters.shortDate(prevFGTS))). Liberado a partir de \(BRLFormatters.shortDate(allowedDate)) (ou permitido agora apenas para quitação total)."
                            fgtsWarning = msg
                            fgtsWarnings.append(msg)
                        }
                    }
                    lastFGTSDate = item.date
                }

                // Zero-Balance Clamping: o aporte abate 100% diretamente do Saldo Devedor
                let effectiveAmortization: Decimal
                let changeLeftover: Decimal
                let newBalance: Decimal
                let isFullPayoffStep: Bool

                if requested >= balanceBefore {
                    effectiveAmortization = balanceBefore
                    changeLeftover = roundCurrency(requested - balanceBefore)
                    newBalance = .zero
                    isFullPayoffStep = true
                } else {
                    effectiveAmortization = requested
                    changeLeftover = .zero
                    newBalance = roundCurrency(balanceBefore - effectiveAmortization)
                    isFullPayoffStep = newBalance <= Decimal(string: "0.01")!
                }

                // Efeito no Contrato:
                // - Santander Consignado: parcela fixa em folha permanece inalterada, logo toda amortização reduz o prazo.
                // - Caixa Financiamento: respeita o modo escolhido (.reduceTerm ou .reduceInstallment).
                let effectiveMode: AmortizationRecalculationMode = isLoan ? .reduceTerm : item.mode

                if isFullPayoffStep {
                    remainingTermMonths = 0
                    if payoffDate == nil {
                        payoffDate = item.date
                    }
                } else {
                    switch effectiveMode {
                    case .reduceTerm:
                        if isLoan || contract.amortizationSystem == .price {
                            remainingTermMonths = calculatePriceRemainingMonths(
                                balance: newBalance,
                                monthlyRateDecimal: monthlyRateDecimal,
                                baseInstallment: currentBaseInstallment,
                                fallbackMaxMonths: remainingTermMonths
                            )
                        } else {
                            // SAC: mantém a cota de amortização normal constante e recalcula os meses restantes
                            if currentSACAmortizationQuota > .zero {
                                let ratio = toDouble(newBalance / currentSACAmortizationQuota)
                                remainingTermMonths = max(1, Int(ceil(ratio - 1e-9)))
                            }
                        }

                    case .reduceInstallment:
                        if contract.amortizationSystem == .price {
                            currentBaseInstallment = calculatePriceBaseInstallment(
                                balance: newBalance,
                                monthlyRateDecimal: monthlyRateDecimal,
                                remainingMonths: max(remainingTermMonths, 1)
                            )
                        } else {
                            // SAC: divide o novo saldo pelo prazo restante
                            currentSACAmortizationQuota = roundCurrency(newBalance / Decimal(max(remainingTermMonths, 1)))
                            let nextInterest = roundCurrency(newBalance * monthlyRateDecimal)
                            currentBaseInstallment = currentSACAmortizationQuota + nextInterest
                        }
                    }

                    if !isLoan && initialBalance > Decimal(string: "0.01")! && initialInsuranceFee > .zero {
                        let ratio = max(.zero, min(Decimal(1), newBalance / initialBalance))
                        currentInsuranceFee = roundCurrency(initialInsuranceFee * ratio)
                    }
                }

                let projectedNextTotalInstallment: Decimal = isFullPayoffStep
                    ? .zero
                    : roundCurrency(currentBaseInstallment + (isLoan ? .zero : (currentInsuranceFee + fixedAdminFee)))

                runningBalance = newBalance
                totalExtraAmortized += effectiveAmortization
                totalChangeLeftover += changeLeftover
                balanceAfterLastPlannedItem = newBalance

                let outcome = PlannedItemProjectionOutcome(
                    id: item.id,
                    date: item.date,
                    requestedAmount: requested,
                    proRataInterest: .zero,
                    effectiveAmortization: effectiveAmortization,
                    changeLeftover: changeLeftover,
                    balanceBefore: balanceBefore,
                    remainingBalanceAfter: newBalance,
                    remainingTermMonthsAfter: remainingTermMonths,
                    newProjectedInstallment: projectedNextTotalInstallment,
                    isFullPayoffStep: isFullPayoffStep,
                    fgtsValidationWarning: fgtsWarning,
                    isFGTSFullPayoffExempt: isFGTSExempt
                )
                plannedOutcomes[item.id] = outcome

                rows.append(
                    LoanProjectionTimelineRow(
                        date: item.date,
                        yearMonthKey: ymKey,
                        eventKind: item.source == .fgts ? .fgtsAmortization : .extraAmortization,
                        title: item.source == .fgts ? "Amortização Extra (FGTS)" : "Amortização Extraordinária",
                        installmentIndex: nil,
                        linkedTransactionId: item.linkedTransactionId,
                        linkedPlannedAmortizationId: item.id,
                        initialBalance: balanceBefore,
                        trCorrection: .zero,
                        correctedBalance: balanceBefore,
                        interestAmount: .zero,
                        normalAmortization: .zero,
                        extraAmortization: effectiveAmortization,
                        changeLeftover: changeLeftover,
                        baseInstallment: .zero,
                        insuranceFee: .zero,
                        adminFee: .zero,
                        totalBudgetOutflow: effectiveAmortization,
                        finalBalance: newBalance,
                        remainingTermMonthsAfter: remainingTermMonths,
                        status: .pendingAmortization,
                        fgtsValidationWarning: fgtsWarning,
                        isFGTSFullPayoffExempt: isFGTSExempt
                    )
                )
            }
        }

        // Caso o plano tenha reduzido o prazo no modo .reduceTerm mas ainda restem parcelas reais excedentes no final,
        // qualquer parcela ativa após o saldo ter atingido zero já foi marcada como `.shadowed` durante o loop.
        return SimulationRunOutput(
            rows: rows,
            plannedOutcomes: plannedOutcomes,
            totalInterest: roundCurrency(totalInterest),
            totalExtraAmortized: roundCurrency(totalExtraAmortized),
            totalChangeLeftover: roundCurrency(totalChangeLeftover),
            finalBalance: runningBalance,
            balanceAfterLastPlannedItem: balanceAfterLastPlannedItem,
            activeInstallmentsCount: activeInstallmentsCount,
            payoffDate: payoffDate,
            shadowedTxIds: shadowedTxIds,
            activeTxProjectedAmounts: activeTxProjectedAmounts,
            fgtsWarnings: fgtsWarnings
        )
    }

    // MARK: - Geração Automática de Planejamento (% do Dinheiro Previsto ao Final do Mês)

    /// Gera automaticamente a lista de amortizações planejadas mês a mês até a quitação do contrato,
    /// comprometendo até `incomeCommitmentPercentage`% do dinheiro previsto ao final de cada mês.
    public static func generateAutomaticPlanItems(
        contract: CreditContract,
        unpaidInstallmentTransactions: [FinancialTransaction],
        currentRealBalanceDouble: Double,
        billingDay: Int,
        incomeCommitmentPercentage: Decimal,
        mode: AmortizationRecalculationMode = .reduceTerm,
        estimatedMonthlyTR: Decimal = .zero,
        referenceNow: Date = Date(),
        monthlyAvailableSurplusProvider: (Date) -> Decimal,
        calendar: Calendar = Calendar.current
    ) -> [PlannedAmortization] {
        let clampedDay = min(max(billingDay, 1), 28)
        let pct = min(max(incomeCommitmentPercentage, Decimal(1)), Decimal(100))
        let effectiveMode: AmortizationRecalculationMode = contract.kind == .loan ? .reduceTerm : mode
        let todayStart = calendar.startOfDay(for: referenceNow)

        // Determina a primeira data futura para amortização no dia escolhido
        var startComps = calendar.dateComponents([.year, .month], from: todayStart)
        startComps.day = clampedDay
        var firstCandidateDate = calendar.date(from: startComps) ?? todayStart
        if firstCandidateDate < todayStart {
            firstCandidateDate = calendar.date(byAdding: .month, value: 1, to: firstCandidateDate) ?? firstCandidateDate
        }

        var generatedItems: [PlannedAmortization] = []
        let maxMonthsToSimulate = max(unpaidInstallmentTransactions.count, contract.totalInstallments, 1)

        for monthOffset in 0..<maxMonthsToSimulate {
            guard let candidateDate = calendar.date(byAdding: .month, value: monthOffset, to: firstCandidateDate) else {
                continue
            }

            // Calcula o dinheiro disponível previsto ao final daquele mês
            let availableSurplus = max(.zero, monthlyAvailableSurplusProvider(candidateDate))
            let budgetForAmortization = roundCurrency(availableSurplus * (pct / Decimal(100)))
            guard budgetForAmortization >= Decimal(string: "10.00")! else {
                continue
            }

            // Simula com os itens já gerados + um item sonda de valor alto nesta data para descobrir o saldo exato restante naquele dia
            let probeId = UUID()
            let probeItem = PlannedAmortization(
                id: probeId,
                contractId: contract.id,
                date: candidateDate,
                amount: toDecimal(currentRealBalanceDouble * 2.0 + 1_000_000.0),
                source: .cash,
                mode: effectiveMode,
                status: .pending
            )
            let tempPlan = AmortizationPlan(
                contractId: contract.id,
                generationMode: .automatic,
                billingDay: clampedDay,
                incomeCommitmentPercentage: pct,
                defaultRecalculationMode: effectiveMode,
                estimatedMonthlyTR: estimatedMonthlyTR,
                items: generatedItems + [probeItem]
            )

            let simResult = simulate(
                contract: contract,
                unpaidInstallmentTransactions: unpaidInstallmentTransactions,
                currentRealBalanceDouble: currentRealBalanceDouble,
                plan: tempPlan,
                calendar: calendar
            )

            guard let probeOutcome = simResult.plannedItemOutcomes[probeId] else {
                break
            }

            let balanceAvailableToAmortize = probeOutcome.balanceBefore
            if balanceAvailableToAmortize <= Decimal(string: "0.01")! {
                // Dívida já quitada!
                break
            }

            let actualAmount = min(budgetForAmortization, balanceAvailableToAmortize)
            guard actualAmount > Decimal(string: "0.01")! else {
                break
            }

            let pctInt = NSDecimalNumber(decimal: pct).intValue
            let newItem = PlannedAmortization(
                contractId: contract.id,
                date: candidateDate,
                amount: actualAmount,
                source: .cash,
                mode: effectiveMode,
                status: .pending,
                notes: "Planejamento automático (\(pctInt)% do saldo previsto no mês)"
            )
            generatedItems.append(newItem)

            if actualAmount >= balanceAvailableToAmortize {
                // Este aporte quitou 100% do saldo restante!
                break
            }
        }

        return generatedItems
    }
}

// MARK: - Validador Temporal de Expiração (`PlanExpirationValidator`)

public enum PlanExpirationValidator {

    /// Verifica todos os planos de amortização e marca automaticamente como `.expired`
    /// quaisquer aportes `.pending` cuja data seja estritamente anterior ao início do dia de hoje (`date < startOfToday`).
    /// Retorna a lista de IDs dos itens que expiraram nesta verificação.
    public static func validateAndExpireOverdueItems(
        plans: inout [AmortizationPlan],
        referenceNow: Date = Date(),
        calendar: Calendar = Calendar.current
    ) -> [UUID] {
        let todayStart = calendar.startOfDay(for: referenceNow)
        var newlyExpiredIds: [UUID] = []

        for pIdx in plans.indices {
            var planMutated = false
            for iIdx in plans[pIdx].items.indices {
                if plans[pIdx].items[iIdx].status == .pending {
                    let itemDay = calendar.startOfDay(for: plans[pIdx].items[iIdx].date)
                    if itemDay < todayStart {
                        plans[pIdx].items[iIdx].status = .expired
                        newlyExpiredIds.append(plans[pIdx].items[iIdx].id)
                        planMutated = true
                    }
                }
            }
            if planMutated {
                plans[pIdx].updatedAt = referenceNow
            }
        }

        return newlyExpiredIds
    }
}
