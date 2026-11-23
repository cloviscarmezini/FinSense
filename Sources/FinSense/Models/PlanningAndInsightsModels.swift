import Foundation

// MARK: - 1. Análise Cronológica Intramês (Vale de Caixa)

public struct DailyCashFlowPoint: Identifiable, Hashable, Sendable {
    public var id: Int { day }
    public let day: Int
    public let date: Date
    public let openingBalance: Double
    public let dayIncome: Double
    public let dayExpense: Double
    public let closingBalance: Double

    public var isNegative: Bool {
        closingBalance < -0.005
    }

    public init(
        day: Int,
        date: Date,
        openingBalance: Double,
        dayIncome: Double,
        dayExpense: Double,
        closingBalance: Double
    ) {
        self.day = day
        self.date = date
        self.openingBalance = openingBalance
        self.dayIncome = dayIncome
        self.dayExpense = dayExpense
        self.closingBalance = closingBalance
    }
}

public enum IntraMonthAlertLevel: String, Codable, Hashable, Sendable {
    case none
    case possibleRisk   // Criticidade menor: transações ficam positivas, mas previsões do mês podem negativar o fechamento
    case confirmedDeficit // Criticidade maior: transações reais/agendadas levam o caixa acumulado para < 0
}

public struct IntraMonthDeficitOccasion: Identifiable, Hashable, Sendable {
    public var id: UUID { transactionId }
    public let transactionId: UUID
    public let date: Date
    public let day: Int
    public let month: Int
    public let deficitAmount: Double // Quanto faltou nesta ocasião (transição >=0 -> <0 ou aprofundamento)
    public let resultingBalance: Double
    public let isRecoveredLater: Bool
    public let recoveredDate: Date?
    public let isResolvedByToday: Bool

    public var dayMonthLabel: String {
        String(format: "%02d/%02d", day, month)
    }

    public init(
        transactionId: UUID,
        date: Date,
        day: Int,
        month: Int,
        deficitAmount: Double,
        resultingBalance: Double,
        isRecoveredLater: Bool,
        recoveredDate: Date?,
        isResolvedByToday: Bool
    ) {
        self.transactionId = transactionId
        self.date = date
        self.day = day
        self.month = month
        self.deficitAmount = deficitAmount
        self.resultingBalance = resultingBalance
        self.isRecoveredLater = isRecoveredLater
        self.recoveredDate = recoveredDate
        self.isResolvedByToday = isResolvedByToday
    }
}

public struct IntraMonthCashFlowAnalysis: Hashable, Sendable {
    public let monthStart: Date
    public let monthEnd: Date
    public let openingBalance: Double
    public let closingBalance: Double // Saldo final considerando transações do mês (sem subtrair previsões ainda não ocorridas do próprio mês)
    public let currentMonthProvisionsTotal: Double
    public let closingBalanceWithProvisions: Double // Saldo final após subtrair previsões do mês selecionado
    public let minimumBalance: Double
    public let minimumBalanceDate: Date?
    public let minimumBalanceDay: Int?
    public let alertLevel: IntraMonthAlertLevel
    public let hasIntraMonthDeficit: Bool // true quando há alerta ativo no card (.confirmedDeficit ou .possibleRisk)
    public let isTemporaryTrough: Bool // Mínimo < 0 durante o mês por transações, porém fechamento >= 0
    public let riskStartDay: Int?
    public let riskEndDay: Int?
    public let cutoffTransactionId: UUID?
    public let recoveryTransactionId: UUID?
    public let cutoffTransactionIds: Set<UUID>
    public let deepeningDeficitTransactionIds: Set<UUID>
    public let recoveryTransactionIds: Set<UUID>
    public let deficitZoneTransactionIds: Set<UUID>
    public let deficitOccasions: [IntraMonthDeficitOccasion]
    public let alertableOccasions: [IntraMonthDeficitOccasion]
    public let runningBalanceByTransactionId: [UUID: Double]
    public let dailyPoints: [DailyCashFlowPoint]

    public var shortfallAmount: Double {
        if !alertableOccasions.isEmpty {
            return max(0.0, alertableOccasions.reduce(0.0) { $0 + $1.deficitAmount })
        }
        if alertLevel == .possibleRisk {
            return max(0.0, -closingBalanceWithProvisions)
        }
        return max(0.0, -minimumBalance)
    }

    public var alertSummaryText: String? {
        switch alertLevel {
        case .none:
            return nil
        case .possibleRisk:
            let missingStr = BRLFormatters.currency(max(0.0, -closingBalanceWithProvisions))
            return "Possibilidade de caixa negativo (até \(missingStr) c/ previsões)"
        case .confirmedDeficit:
            if alertableOccasions.isEmpty {
                let missingStr = BRLFormatters.currency(max(0.0, -minimumBalance))
                if let start = riskStartDay, let end = riskEndDay {
                    return start == end
                        ? "Faltarão \(missingStr) no dia \(start)"
                        : "Faltarão \(missingStr) entre os dias \(start) e \(end)"
                }
                return "Faltarão \(missingStr) durante o mês"
            }
            let parts = alertableOccasions.map { occ in
                "\(BRLFormatters.currency(occ.deficitAmount)) no dia \(occ.dayMonthLabel)"
            }
            if parts.count == 1 {
                return "Faltarão \(parts[0])"
            } else if parts.count == 2 {
                return "Faltarão \(parts[0]) e \(parts[1])"
            } else {
                let head = parts.dropLast().joined(separator: ", ")
                return "Faltarão \(head) e \(parts.last!)"
            }
        }
    }

    public init(
        monthStart: Date,
        monthEnd: Date,
        openingBalance: Double,
        closingBalance: Double,
        currentMonthProvisionsTotal: Double = 0.0,
        closingBalanceWithProvisions: Double? = nil,
        minimumBalance: Double,
        minimumBalanceDate: Date?,
        minimumBalanceDay: Int?,
        alertLevel: IntraMonthAlertLevel? = nil,
        hasIntraMonthDeficit: Bool,
        isTemporaryTrough: Bool,
        riskStartDay: Int?,
        riskEndDay: Int?,
        cutoffTransactionId: UUID?,
        recoveryTransactionId: UUID?,
        cutoffTransactionIds: Set<UUID> = [],
        deepeningDeficitTransactionIds: Set<UUID> = [],
        recoveryTransactionIds: Set<UUID> = [],
        deficitZoneTransactionIds: Set<UUID>,
        deficitOccasions: [IntraMonthDeficitOccasion] = [],
        alertableOccasions: [IntraMonthDeficitOccasion] = [],
        runningBalanceByTransactionId: [UUID: Double],
        dailyPoints: [DailyCashFlowPoint]
    ) {
        self.monthStart = monthStart
        self.monthEnd = monthEnd
        self.openingBalance = openingBalance
        self.closingBalance = closingBalance
        self.currentMonthProvisionsTotal = currentMonthProvisionsTotal
        self.closingBalanceWithProvisions = closingBalanceWithProvisions ?? (closingBalance - currentMonthProvisionsTotal)
        self.minimumBalance = minimumBalance
        self.minimumBalanceDate = minimumBalanceDate
        self.minimumBalanceDay = minimumBalanceDay
        self.alertLevel = alertLevel ?? (hasIntraMonthDeficit ? .confirmedDeficit : .none)
        self.hasIntraMonthDeficit = hasIntraMonthDeficit
        self.isTemporaryTrough = isTemporaryTrough
        self.riskStartDay = riskStartDay
        self.riskEndDay = riskEndDay
        self.cutoffTransactionId = cutoffTransactionId
        self.recoveryTransactionId = recoveryTransactionId
        self.cutoffTransactionIds = cutoffTransactionIds
        self.deepeningDeficitTransactionIds = deepeningDeficitTransactionIds
        self.recoveryTransactionIds = recoveryTransactionIds
        self.deficitZoneTransactionIds = deficitZoneTransactionIds
        self.deficitOccasions = deficitOccasions
        self.alertableOccasions = alertableOccasions
        self.runningBalanceByTransactionId = runningBalanceByTransactionId
        self.dailyPoints = dailyPoints
    }
}

// MARK: - 2. Sinking Funds (Caixinhas de Provisão Anual / Sazonal)

public struct SinkingFund: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var categoryId: UUID?
    public var iconSymbol: String
    public var colorHex: String
    public var targetAmount: Double
    public var recurrenceMonths: Int // Ex: 12 = anual (1/12 por mês)
    public var dueMonth: Int // 1...12
    public var dueYear: Int
    public var accumulatedReserve: Double
    public var isEnabled: Bool
    public var notes: String
    public var createdAt: Date
    public var updatedAt: Date

    public var monthlyContribution: Double {
        let months = max(1, recurrenceMonths)
        return (max(0.0, targetAmount) / Double(months))
    }

    public var remainingToTarget: Double {
        max(0.0, targetAmount - accumulatedReserve)
    }

    public var progressRatio: Double {
        guard targetAmount > 0 else { return 1.0 }
        return min(1.0, max(0.0, accumulatedReserve / targetAmount))
    }

    public init(
        id: UUID = UUID(),
        name: String,
        categoryId: UUID? = nil,
        iconSymbol: String = "tray.and.arrow.down.fill",
        colorHex: String = "#0EA5E9",
        targetAmount: Double,
        recurrenceMonths: Int = 12,
        dueMonth: Int = 1,
        dueYear: Int = Calendar.current.component(.year, from: Date()) + 1,
        accumulatedReserve: Double = 0.0,
        isEnabled: Bool = true,
        notes: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.categoryId = categoryId
        self.iconSymbol = iconSymbol
        self.colorHex = colorHex
        self.targetAmount = max(0.0, targetAmount)
        self.recurrenceMonths = max(1, min(60, recurrenceMonths))
        self.dueMonth = max(1, min(12, dueMonth))
        self.dueYear = max(2020, dueYear)
        self.accumulatedReserve = max(0.0, accumulatedReserve)
        self.isEnabled = isEnabled
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, name, categoryId, iconSymbol, colorHex, targetAmount
        case recurrenceMonths, dueMonth, dueYear, accumulatedReserve
        case isEnabled, notes, createdAt, updatedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        self.id = (try? c.decode(UUID.self, forKey: AnyKey("id"))) ?? UUID()
        self.name = (try? c.decodeIfPresent(String.self, forKey: AnyKey("name"))) ?? ""
        self.categoryId = (try? c.decodeIfPresent(UUID.self, forKey: AnyKey("categoryId")))
            ?? (try? c.decodeIfPresent(UUID.self, forKey: AnyKey("category_id")))
        self.iconSymbol = (try? c.decodeIfPresent(String.self, forKey: AnyKey("iconSymbol")))
            ?? (try? c.decodeIfPresent(String.self, forKey: AnyKey("icon_symbol"))) ?? "tray.and.arrow.down.fill"
        self.colorHex = (try? c.decodeIfPresent(String.self, forKey: AnyKey("colorHex")))
            ?? (try? c.decodeIfPresent(String.self, forKey: AnyKey("color_hex"))) ?? "#0EA5E9"
        self.targetAmount = max(0.0, (try? c.decodeIfPresent(Double.self, forKey: AnyKey("targetAmount")))
            ?? (try? c.decodeIfPresent(Double.self, forKey: AnyKey("target_amount"))) ?? 0.0)
        self.recurrenceMonths = max(1, (try? c.decodeIfPresent(Int.self, forKey: AnyKey("recurrenceMonths")))
            ?? (try? c.decodeIfPresent(Int.self, forKey: AnyKey("recurrence_months"))) ?? 12)
        self.dueMonth = max(1, min(12, (try? c.decodeIfPresent(Int.self, forKey: AnyKey("dueMonth")))
            ?? (try? c.decodeIfPresent(Int.self, forKey: AnyKey("due_month"))) ?? 1))
        self.dueYear = max(2020, (try? c.decodeIfPresent(Int.self, forKey: AnyKey("dueYear")))
            ?? (try? c.decodeIfPresent(Int.self, forKey: AnyKey("due_year"))) ?? 2027)
        self.accumulatedReserve = max(0.0, (try? c.decodeIfPresent(Double.self, forKey: AnyKey("accumulatedReserve")))
            ?? (try? c.decodeIfPresent(Double.self, forKey: AnyKey("accumulated_reserve"))) ?? 0.0)
        self.isEnabled = (try? c.decodeIfPresent(Bool.self, forKey: AnyKey("isEnabled")))
            ?? (try? c.decodeIfPresent(Bool.self, forKey: AnyKey("is_enabled"))) ?? true
        self.notes = (try? c.decodeIfPresent(String.self, forKey: AnyKey("notes"))) ?? ""
        self.createdAt = (try? c.decodeIfPresent(Date.self, forKey: AnyKey("createdAt")))
            ?? (try? c.decodeIfPresent(Date.self, forKey: AnyKey("created_at"))) ?? Date()
        self.updatedAt = (try? c.decodeIfPresent(Date.self, forKey: AnyKey("updatedAt")))
            ?? (try? c.decodeIfPresent(Date.self, forKey: AnyKey("updated_at"))) ?? self.createdAt
    }
}

// MARK: - 3. Cenários "E se?" (What-If) & Comparador Amortizar vs Investir

public struct WhatIfScenario: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var variableIncomeReductionPercent: Double // 0...100
    public var unexpectedExpenseAmount: Double
    public var unexpectedExpenseMonthOffset: Int // 0 = mês atual da simulação, 1 = próximo, etc.
    public var benchmarkAnnualRatePercent: Double // Ex: 11.25% CDI/Selic
    public var netYieldTaxRatePercent: Double // Ex: 15.0% IR (ou 0% LCI/LCA)
    public var notes: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        variableIncomeReductionPercent: Double = 25.0,
        unexpectedExpenseAmount: Double = 0.0,
        unexpectedExpenseMonthOffset: Int = 1,
        benchmarkAnnualRatePercent: Double = 11.25,
        netYieldTaxRatePercent: Double = 15.0,
        notes: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.variableIncomeReductionPercent = max(0.0, min(100.0, variableIncomeReductionPercent))
        self.unexpectedExpenseAmount = max(0.0, unexpectedExpenseAmount)
        self.unexpectedExpenseMonthOffset = max(0, min(24, unexpectedExpenseMonthOffset))
        self.benchmarkAnnualRatePercent = max(0.0, benchmarkAnnualRatePercent)
        self.netYieldTaxRatePercent = max(0.0, min(50.0, netYieldTaxRatePercent))
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, name, variableIncomeReductionPercent, unexpectedExpenseAmount
        case unexpectedExpenseMonthOffset, benchmarkAnnualRatePercent, netYieldTaxRatePercent
        case notes, createdAt, updatedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        self.id = (try? c.decode(UUID.self, forKey: AnyKey("id"))) ?? UUID()
        self.name = (try? c.decodeIfPresent(String.self, forKey: AnyKey("name"))) ?? "Cenário Simulado"
        self.variableIncomeReductionPercent = max(0.0, (try? c.decodeIfPresent(Double.self, forKey: AnyKey("variableIncomeReductionPercent")))
            ?? (try? c.decodeIfPresent(Double.self, forKey: AnyKey("variable_income_reduction_percent"))) ?? 0.0)
        self.unexpectedExpenseAmount = max(0.0, (try? c.decodeIfPresent(Double.self, forKey: AnyKey("unexpectedExpenseAmount")))
            ?? (try? c.decodeIfPresent(Double.self, forKey: AnyKey("unexpected_expense_amount"))) ?? 0.0)
        self.unexpectedExpenseMonthOffset = max(0, (try? c.decodeIfPresent(Int.self, forKey: AnyKey("unexpectedExpenseMonthOffset")))
            ?? (try? c.decodeIfPresent(Int.self, forKey: AnyKey("unexpected_expense_month_offset"))) ?? 0)
        self.benchmarkAnnualRatePercent = max(0.0, (try? c.decodeIfPresent(Double.self, forKey: AnyKey("benchmarkAnnualRatePercent")))
            ?? (try? c.decodeIfPresent(Double.self, forKey: AnyKey("benchmark_annual_rate_percent"))) ?? 11.25)
        self.netYieldTaxRatePercent = max(0.0, (try? c.decodeIfPresent(Double.self, forKey: AnyKey("netYieldTaxRatePercent")))
            ?? (try? c.decodeIfPresent(Double.self, forKey: AnyKey("net_yield_tax_rate_percent"))) ?? 15.0)
        self.notes = (try? c.decodeIfPresent(String.self, forKey: AnyKey("notes"))) ?? ""
        self.createdAt = (try? c.decodeIfPresent(Date.self, forKey: AnyKey("createdAt")))
            ?? (try? c.decodeIfPresent(Date.self, forKey: AnyKey("created_at"))) ?? Date()
        self.updatedAt = (try? c.decodeIfPresent(Date.self, forKey: AnyKey("updatedAt")))
            ?? (try? c.decodeIfPresent(Date.self, forKey: AnyKey("updated_at"))) ?? self.createdAt
    }
}

public enum DecisionRecommendation: String, Codable, Hashable, Sendable {
    case amortize = "Compensa Amortizar"
    case invest = "Compensa Investir"
    case neutral = "Equilíbrio Financeiro"
}

public struct AmortizeVsInvestCurvePoint: Identifiable, Hashable, Sendable {
    public var id: Int { monthIndex }
    public let monthIndex: Int
    public let amortizedInterestSavedCumulative: Double
    public let investedNetGainCumulative: Double
}

public struct AmortizeVsInvestComparisonResult: Identifiable, Hashable, Sendable {
    public var id: UUID { contractId }
    public let contractId: UUID
    public let contractName: String
    public let contractKind: CreditContractKind
    public let extraAmount: Double
    public let outstandingBalance: Double
    public let remainingMonths: Int
    public let contractEffectiveMonthlyRatePercent: Double
    public let contractEffectiveAnnualRatePercent: Double
    public let benchmarkGrossAnnualRatePercent: Double
    public let benchmarkNetAnnualRatePercent: Double
    public let benchmarkNetMonthlyRatePercent: Double
    public let breakEvenGrossAnnualRatePercent: Double
    public let breakEvenNetAnnualRatePercent: Double
    public let amortizeInterestSaved: Double
    public let amortizeMonthsEliminated: Int
    public let investProjectedNetGain: Double
    public let investFinalAmount: Double
    public let monthsUntilInvestmentPaysOffContract: Int?
    public let netFinancialAdvantage: Double // > 0 => amortizar vence; < 0 => investir vence
    public let recommendation: DecisionRecommendation
    public let explanation: String
    public let curvePoints: [AmortizeVsInvestCurvePoint]
}

public struct StressTestMonthPoint: Identifiable, Hashable, Sendable {
    public var id: Int { yearMonthKey }
    public let monthOffset: Int
    public let yearMonthKey: Int
    public let monthDate: Date
    public let label: String
    public let baselineIncome: Double
    public let stressedIncome: Double
    public let baselineExpense: Double
    public let stressedExpense: Double
    public let baselineClosingBalance: Double
    public let stressedClosingBalance: Double
    public let minimumIntraMonthStressedBalance: Double
    public let plannedAmortizationInMonth: Double

    public var isNegative: Bool {
        stressedClosingBalance < -0.005 || minimumIntraMonthStressedBalance < -0.005
    }
}

public struct SuggestedStressMitigation: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let title: String
    public let description: String
    public let recoveredAmount: Double
    public let targetYearMonthKey: Int

    public init(id: UUID = UUID(), title: String, description: String, recoveredAmount: Double, targetYearMonthKey: Int) {
        self.id = id
        self.title = title
        self.description = description
        self.recoveredAmount = recoveredAmount
        self.targetYearMonthKey = targetYearMonthKey
    }
}

public struct StressTestResult: Hashable, Sendable {
    public let scenario: WhatIfScenario
    public let months: [StressTestMonthPoint]
    public let negativeMonthKeys: [Int]
    public let lowestStressedBalance: Double
    public let lowestStressedMonthLabel: String?
    public let suggestedMitigations: [SuggestedStressMitigation]
    public let mitigatedLowestBalance: Double
}

// MARK: - 4. Central de Insights & Machine Learning Comportamental

public enum InsightKind: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case personalInflation = "Inflação Pessoal"
    case subscriptionDriftOrForgotten = "Assinaturas & Reajustes"
    case consumptionAnomaly = "Anomalia de Consumo"
    case cashMismatchRisk = "Descasamento de Caixa"
    case monthlyClosing = "Fechamento Mensal"

    public var id: String { rawValue }

    public var iconSymbol: String {
        switch self {
        case .personalInflation: return "chart.line.uptrend.xyaxis"
        case .subscriptionDriftOrForgotten: return "repeat.badge.exclamationmark"
        case .consumptionAnomaly: return "exclamationmark.triangle.fill"
        case .cashMismatchRisk: return "calendar.badge.exclamationmark"
        case .monthlyClosing: return "checklist.checked"
        }
    }

    public var colorHex: String {
        switch self {
        case .personalInflation: return "#F59E0B"
        case .subscriptionDriftOrForgotten: return "#8B5CF6"
        case .consumptionAnomaly: return "#EF4444"
        case .cashMismatchRisk: return "#F97316"
        case .monthlyClosing: return "#10B981"
        }
    }
}

public enum InsightSeverity: String, Codable, CaseIterable, Hashable, Sendable {
    case info = "info"
    case warning = "warning"
    case critical = "critical"

    public var title: String {
        switch self {
        case .info: return "Informativo"
        case .warning: return "Atenção"
        case .critical: return "Crítico"
        }
    }

    public var colorHex: String {
        switch self {
        case .info: return "#3B82F6"
        case .warning: return "#F59E0B"
        case .critical: return "#EF4444"
        }
    }
}

public enum InsightFeedback: String, Codable, CaseIterable, Hashable, Sendable {
    case pending = "pending"
    case useful = "useful"
    case ignored = "ignored"
    case dismissed = "dismissed"

    public var title: String {
        switch self {
        case .pending: return "Pendente"
        case .useful: return "Útil"
        case .ignored: return "Ignorado"
        case .dismissed: return "Dispensado"
        }
    }
}

public struct FinancialInsight: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var fingerprint: String // Identificador determinístico para evitar duplicatas no treino diário
    public var kind: InsightKind
    public var severity: InsightSeverity
    public var title: String
    public var message: String
    public var recommendation: String
    public var impactAmount: Double
    public var confidenceScore: Double // 0.0...1.0
    public var yearMonthKey: Int
    public var relatedCategoryId: UUID?
    public var relatedTransactionId: UUID?
    public var feedback: InsightFeedback
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        fingerprint: String,
        kind: InsightKind,
        severity: InsightSeverity,
        title: String,
        message: String,
        recommendation: String,
        impactAmount: Double = 0.0,
        confidenceScore: Double = 0.8,
        yearMonthKey: Int,
        relatedCategoryId: UUID? = nil,
        relatedTransactionId: UUID? = nil,
        feedback: InsightFeedback = .pending,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.fingerprint = fingerprint
        self.kind = kind
        self.severity = severity
        self.title = title
        self.message = message
        self.recommendation = recommendation
        self.impactAmount = impactAmount
        self.confidenceScore = max(0.0, min(1.0, confidenceScore))
        self.yearMonthKey = yearMonthKey
        self.relatedCategoryId = relatedCategoryId
        self.relatedTransactionId = relatedTransactionId
        self.feedback = feedback
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, fingerprint, kind, severity, title, message, recommendation
        case impactAmount, confidenceScore, yearMonthKey, relatedCategoryId
        case relatedTransactionId, feedback, createdAt, updatedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        self.id = (try? c.decode(UUID.self, forKey: AnyKey("id"))) ?? UUID()
        self.fingerprint = (try? c.decodeIfPresent(String.self, forKey: AnyKey("fingerprint"))) ?? self.id.uuidString
        self.kind = (try? c.decodeIfPresent(InsightKind.self, forKey: AnyKey("kind"))) ?? .consumptionAnomaly
        self.severity = (try? c.decodeIfPresent(InsightSeverity.self, forKey: AnyKey("severity"))) ?? .warning
        self.title = (try? c.decodeIfPresent(String.self, forKey: AnyKey("title"))) ?? ""
        self.message = (try? c.decodeIfPresent(String.self, forKey: AnyKey("message"))) ?? ""
        self.recommendation = (try? c.decodeIfPresent(String.self, forKey: AnyKey("recommendation"))) ?? ""
        self.impactAmount = (try? c.decodeIfPresent(Double.self, forKey: AnyKey("impactAmount")))
            ?? (try? c.decodeIfPresent(Double.self, forKey: AnyKey("impact_amount"))) ?? 0.0
        self.confidenceScore = (try? c.decodeIfPresent(Double.self, forKey: AnyKey("confidenceScore")))
            ?? (try? c.decodeIfPresent(Double.self, forKey: AnyKey("confidence_score"))) ?? 0.8
        self.yearMonthKey = (try? c.decodeIfPresent(Int.self, forKey: AnyKey("yearMonthKey")))
            ?? (try? c.decodeIfPresent(Int.self, forKey: AnyKey("year_month_key"))) ?? 202601
        self.relatedCategoryId = (try? c.decodeIfPresent(UUID.self, forKey: AnyKey("relatedCategoryId")))
            ?? (try? c.decodeIfPresent(UUID.self, forKey: AnyKey("related_category_id")))
        self.relatedTransactionId = (try? c.decodeIfPresent(UUID.self, forKey: AnyKey("relatedTransactionId")))
            ?? (try? c.decodeIfPresent(UUID.self, forKey: AnyKey("related_transaction_id")))
        self.feedback = (try? c.decodeIfPresent(InsightFeedback.self, forKey: AnyKey("feedback"))) ?? .pending
        self.createdAt = (try? c.decodeIfPresent(Date.self, forKey: AnyKey("createdAt")))
            ?? (try? c.decodeIfPresent(Date.self, forKey: AnyKey("created_at"))) ?? Date()
        self.updatedAt = (try? c.decodeIfPresent(Date.self, forKey: AnyKey("updatedAt")))
            ?? (try? c.decodeIfPresent(Date.self, forKey: AnyKey("updated_at"))) ?? self.createdAt
    }
}

public struct MonthlyReviewRecord: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var year: Int
    public var month: Int
    public var plannedIncome: Double
    public var realizedIncome: Double
    public var plannedExpense: Double
    public var realizedExpense: Double
    public var plannedEndBalance: Double
    public var realizedEndBalance: Double
    public var previousMonthEndBalance: Double
    public var pendingAmortizationsCount: Int
    public var pendingAmortizationsAmount: Double
    public var deviationHighlights: [String]
    public var isCompleted: Bool
    public var completedAt: Date?
    public var notes: String
    public var createdAt: Date
    public var updatedAt: Date

    public var yearMonthKey: Int { year * 100 + month }

    public var cashEvolutionDelta: Double {
        realizedEndBalance - previousMonthEndBalance
    }

    public init(
        id: UUID = UUID(),
        year: Int,
        month: Int,
        plannedIncome: Double,
        realizedIncome: Double,
        plannedExpense: Double,
        realizedExpense: Double,
        plannedEndBalance: Double,
        realizedEndBalance: Double,
        previousMonthEndBalance: Double,
        pendingAmortizationsCount: Int,
        pendingAmortizationsAmount: Double,
        deviationHighlights: [String],
        isCompleted: Bool = false,
        completedAt: Date? = nil,
        notes: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.year = year
        self.month = month
        self.plannedIncome = plannedIncome
        self.realizedIncome = realizedIncome
        self.plannedExpense = plannedExpense
        self.realizedExpense = realizedExpense
        self.plannedEndBalance = plannedEndBalance
        self.realizedEndBalance = realizedEndBalance
        self.previousMonthEndBalance = previousMonthEndBalance
        self.pendingAmortizationsCount = pendingAmortizationsCount
        self.pendingAmortizationsAmount = pendingAmortizationsAmount
        self.deviationHighlights = deviationHighlights
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, year, month, plannedIncome, realizedIncome, plannedExpense, realizedExpense
        case plannedEndBalance, realizedEndBalance, previousMonthEndBalance
        case pendingAmortizationsCount, pendingAmortizationsAmount, deviationHighlights
        case isCompleted, completedAt, notes, createdAt, updatedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        self.id = (try? c.decode(UUID.self, forKey: AnyKey("id"))) ?? UUID()
        self.year = (try? c.decodeIfPresent(Int.self, forKey: AnyKey("year"))) ?? 2026
        self.month = (try? c.decodeIfPresent(Int.self, forKey: AnyKey("month"))) ?? 1
        self.plannedIncome = (try? c.decodeIfPresent(Double.self, forKey: AnyKey("plannedIncome")))
            ?? (try? c.decodeIfPresent(Double.self, forKey: AnyKey("planned_income"))) ?? 0.0
        self.realizedIncome = (try? c.decodeIfPresent(Double.self, forKey: AnyKey("realizedIncome")))
            ?? (try? c.decodeIfPresent(Double.self, forKey: AnyKey("realized_income"))) ?? 0.0
        self.plannedExpense = (try? c.decodeIfPresent(Double.self, forKey: AnyKey("plannedExpense")))
            ?? (try? c.decodeIfPresent(Double.self, forKey: AnyKey("planned_expense"))) ?? 0.0
        self.realizedExpense = (try? c.decodeIfPresent(Double.self, forKey: AnyKey("realizedExpense")))
            ?? (try? c.decodeIfPresent(Double.self, forKey: AnyKey("realized_expense"))) ?? 0.0
        self.plannedEndBalance = (try? c.decodeIfPresent(Double.self, forKey: AnyKey("plannedEndBalance")))
            ?? (try? c.decodeIfPresent(Double.self, forKey: AnyKey("planned_end_balance"))) ?? 0.0
        self.realizedEndBalance = (try? c.decodeIfPresent(Double.self, forKey: AnyKey("realizedEndBalance")))
            ?? (try? c.decodeIfPresent(Double.self, forKey: AnyKey("realized_end_balance"))) ?? 0.0
        self.previousMonthEndBalance = (try? c.decodeIfPresent(Double.self, forKey: AnyKey("previousMonthEndBalance")))
            ?? (try? c.decodeIfPresent(Double.self, forKey: AnyKey("previous_month_end_balance"))) ?? 0.0
        self.pendingAmortizationsCount = (try? c.decodeIfPresent(Int.self, forKey: AnyKey("pendingAmortizationsCount")))
            ?? (try? c.decodeIfPresent(Int.self, forKey: AnyKey("pending_amortizations_count"))) ?? 0
        self.pendingAmortizationsAmount = (try? c.decodeIfPresent(Double.self, forKey: AnyKey("pendingAmortizationsAmount")))
            ?? (try? c.decodeIfPresent(Double.self, forKey: AnyKey("pending_amortizations_amount"))) ?? 0.0
        self.deviationHighlights = (try? c.decodeIfPresent([String].self, forKey: AnyKey("deviationHighlights")))
            ?? (try? c.decodeIfPresent([String].self, forKey: AnyKey("deviation_highlights"))) ?? []
        self.isCompleted = (try? c.decodeIfPresent(Bool.self, forKey: AnyKey("isCompleted")))
            ?? (try? c.decodeIfPresent(Bool.self, forKey: AnyKey("is_completed"))) ?? false
        self.completedAt = (try? c.decodeIfPresent(Date.self, forKey: AnyKey("completedAt")))
            ?? (try? c.decodeIfPresent(Date.self, forKey: AnyKey("completed_at")))
        self.notes = (try? c.decodeIfPresent(String.self, forKey: AnyKey("notes"))) ?? ""
        self.createdAt = (try? c.decodeIfPresent(Date.self, forKey: AnyKey("createdAt")))
            ?? (try? c.decodeIfPresent(Date.self, forKey: AnyKey("created_at"))) ?? Date()
        self.updatedAt = (try? c.decodeIfPresent(Date.self, forKey: AnyKey("updatedAt")))
            ?? (try? c.decodeIfPresent(Date.self, forKey: AnyKey("updated_at"))) ?? self.createdAt
    }
}

public struct CategoryMLStats: Codable, Hashable, Sendable {
    public var categoryId: UUID
    public var categoryName: String
    public var ewmaMonthlySpend: Double
    public var stdDevMonthlySpend: Double
    public var monthlySlope: Double // Tendência linear R$/mês
    public var averageTransactionAmount: Double
    public var medianTransactionAmount: Double
    public var madTransactionAmount: Double
    public var monthsObserved: Int
    public var sampleCount: Int

    public init(
        categoryId: UUID,
        categoryName: String,
        ewmaMonthlySpend: Double,
        stdDevMonthlySpend: Double,
        monthlySlope: Double,
        averageTransactionAmount: Double,
        medianTransactionAmount: Double,
        madTransactionAmount: Double,
        monthsObserved: Int,
        sampleCount: Int
    ) {
        self.categoryId = categoryId
        self.categoryName = categoryName
        self.ewmaMonthlySpend = ewmaMonthlySpend
        self.stdDevMonthlySpend = stdDevMonthlySpend
        self.monthlySlope = monthlySlope
        self.averageTransactionAmount = averageTransactionAmount
        self.medianTransactionAmount = medianTransactionAmount
        self.madTransactionAmount = madTransactionAmount
        self.monthsObserved = monthsObserved
        self.sampleCount = sampleCount
    }
}

public struct MLBehavioralProfile: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var lastTrainedAt: Date?
    public var trainingEpochCount: Int
    public var analyzedTransactionsCount: Int
    public var inflationSensitivity: Double // Multiplicador ajustado pelo feedback (padrão 1.0)
    public var anomalyZThreshold: Double // Limiar Z-Score ajustado pelo feedback (padrão 2.2)
    public var subscriptionDriftThresholdPercent: Double // Limiar % aumento assinatura (padrão 3.0)
    public var categoryWeightAdjustments: [String: Double] // categoryId.uuidString -> peso aprendido via feedback
    public var dayOfMonthSpendCurve: [Double] // 31 posições: proporção acumulada esperada até o dia d (1...31)
    public var categoryStats: [String: CategoryMLStats]
    public var usefulFeedbackCount: Int
    public var ignoredFeedbackCount: Int
    public var dismissedFeedbackCount: Int
    public var updatedAt: Date

    public init(
        id: UUID = UUID(uuidString: "11111111-1111-1111-1111-111111111111") ?? UUID(),
        lastTrainedAt: Date? = nil,
        trainingEpochCount: Int = 0,
        analyzedTransactionsCount: Int = 0,
        inflationSensitivity: Double = 1.0,
        anomalyZThreshold: Double = 2.2,
        subscriptionDriftThresholdPercent: Double = 3.0,
        categoryWeightAdjustments: [String: Double] = [:],
        dayOfMonthSpendCurve: [Double] = Array(1...31).map { Double($0) / 31.0 },
        categoryStats: [String: CategoryMLStats] = [:],
        usefulFeedbackCount: Int = 0,
        ignoredFeedbackCount: Int = 0,
        dismissedFeedbackCount: Int = 0,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.lastTrainedAt = lastTrainedAt
        self.trainingEpochCount = trainingEpochCount
        self.analyzedTransactionsCount = analyzedTransactionsCount
        self.inflationSensitivity = inflationSensitivity
        self.anomalyZThreshold = anomalyZThreshold
        self.subscriptionDriftThresholdPercent = subscriptionDriftThresholdPercent
        self.categoryWeightAdjustments = categoryWeightAdjustments
        self.dayOfMonthSpendCurve = dayOfMonthSpendCurve
        self.categoryStats = categoryStats
        self.usefulFeedbackCount = usefulFeedbackCount
        self.ignoredFeedbackCount = ignoredFeedbackCount
        self.dismissedFeedbackCount = dismissedFeedbackCount
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, lastTrainedAt, trainingEpochCount, analyzedTransactionsCount
        case inflationSensitivity, anomalyZThreshold, subscriptionDriftThresholdPercent
        case categoryWeightAdjustments, dayOfMonthSpendCurve, categoryStats
        case usefulFeedbackCount, ignoredFeedbackCount, dismissedFeedbackCount, updatedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        let defaultId = UUID(uuidString: "11111111-1111-1111-1111-111111111111") ?? UUID()
        self.id = (try? c.decodeIfPresent(UUID.self, forKey: AnyKey("id"))) ?? defaultId
        self.lastTrainedAt = (try? c.decodeIfPresent(Date.self, forKey: AnyKey("lastTrainedAt")))
            ?? (try? c.decodeIfPresent(Date.self, forKey: AnyKey("last_trained_at")))
        self.trainingEpochCount = (try? c.decodeIfPresent(Int.self, forKey: AnyKey("trainingEpochCount")))
            ?? (try? c.decodeIfPresent(Int.self, forKey: AnyKey("training_epoch_count"))) ?? 0
        self.analyzedTransactionsCount = (try? c.decodeIfPresent(Int.self, forKey: AnyKey("analyzedTransactionsCount")))
            ?? (try? c.decodeIfPresent(Int.self, forKey: AnyKey("analyzed_transactions_count"))) ?? 0
        self.inflationSensitivity = (try? c.decodeIfPresent(Double.self, forKey: AnyKey("inflationSensitivity")))
            ?? (try? c.decodeIfPresent(Double.self, forKey: AnyKey("inflation_sensitivity"))) ?? 1.0
        self.anomalyZThreshold = (try? c.decodeIfPresent(Double.self, forKey: AnyKey("anomalyZThreshold")))
            ?? (try? c.decodeIfPresent(Double.self, forKey: AnyKey("anomaly_z_threshold"))) ?? 2.2
        self.subscriptionDriftThresholdPercent = (try? c.decodeIfPresent(Double.self, forKey: AnyKey("subscriptionDriftThresholdPercent")))
            ?? (try? c.decodeIfPresent(Double.self, forKey: AnyKey("subscription_drift_threshold_percent"))) ?? 3.0
        self.categoryWeightAdjustments = (try? c.decodeIfPresent([String: Double].self, forKey: AnyKey("categoryWeightAdjustments")))
            ?? (try? c.decodeIfPresent([String: Double].self, forKey: AnyKey("category_weight_adjustments"))) ?? [:]
        self.dayOfMonthSpendCurve = (try? c.decodeIfPresent([Double].self, forKey: AnyKey("dayOfMonthSpendCurve")))
            ?? (try? c.decodeIfPresent([Double].self, forKey: AnyKey("day_of_month_spend_curve")))
            ?? Array(1...31).map { Double($0) / 31.0 }
        self.categoryStats = (try? c.decodeIfPresent([String: CategoryMLStats].self, forKey: AnyKey("categoryStats")))
            ?? (try? c.decodeIfPresent([String: CategoryMLStats].self, forKey: AnyKey("category_stats"))) ?? [:]
        self.usefulFeedbackCount = (try? c.decodeIfPresent(Int.self, forKey: AnyKey("usefulFeedbackCount")))
            ?? (try? c.decodeIfPresent(Int.self, forKey: AnyKey("useful_feedback_count"))) ?? 0
        self.ignoredFeedbackCount = (try? c.decodeIfPresent(Int.self, forKey: AnyKey("ignoredFeedbackCount")))
            ?? (try? c.decodeIfPresent(Int.self, forKey: AnyKey("ignored_feedback_count"))) ?? 0
        self.dismissedFeedbackCount = (try? c.decodeIfPresent(Int.self, forKey: AnyKey("dismissedFeedbackCount")))
            ?? (try? c.decodeIfPresent(Int.self, forKey: AnyKey("dismissed_feedback_count"))) ?? 0
        self.updatedAt = (try? c.decodeIfPresent(Date.self, forKey: AnyKey("updatedAt")))
            ?? (try? c.decodeIfPresent(Date.self, forKey: AnyKey("updated_at"))) ?? Date()
    }
}
