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
    public var currencyCode: String
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
        currencyCode: String = "BRL",
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
        self.currencyCode = currencyCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "BRL" : currencyCode.uppercased()
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, name, categoryId, iconSymbol, colorHex, targetAmount
        case recurrenceMonths, dueMonth, dueYear, accumulatedReserve
        case isEnabled, notes, currencyCode, createdAt, updatedAt
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
        let rawCur = (try? c.decodeIfPresent(String.self, forKey: AnyKey("currencyCode")))
            ?? (try? c.decodeIfPresent(String.self, forKey: AnyKey("currency_code"))) ?? "BRL"
        self.currencyCode = rawCur.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "BRL" : rawCur.uppercased()
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

// MARK: - 7. Moedas Suportadas (Multimoeda / Câmbio)

public enum SupportedCurrency: String, CaseIterable, Codable, Identifiable, Hashable, Sendable {
    case BRL
    case USD
    case EUR
    case GBP
    case CAD
    case CHF
    case AUD
    case JPY

    public var id: String { rawValue }

    public var symbol: String {
        switch self {
        case .BRL: return "R$"
        case .USD: return "US$"
        case .EUR: return "€"
        case .GBP: return "£"
        case .CAD: return "C$"
        case .CHF: return "CHF"
        case .AUD: return "A$"
        case .JPY: return "¥"
        }
    }

    public var displayName: String {
        switch self {
        case .BRL: return "Real Brasileiro (BRL)"
        case .USD: return "Dólar Americano (USD)"
        case .EUR: return "Euro (EUR)"
        case .GBP: return "Libra Esterlina (GBP)"
        case .CAD: return "Dólar Canadense (CAD)"
        case .CHF: return "Franco Suíço (CHF)"
        case .AUD: return "Dólar Australiano (AUD)"
        case .JPY: return "Iene Japonês (JPY)"
        }
    }

    public var defaultFallbackRateToBRL: Double {
        switch self {
        case .BRL: return 1.0
        case .USD: return 5.75
        case .EUR: return 6.10
        case .GBP: return 7.25
        case .CAD: return 4.10
        case .CHF: return 6.45
        case .AUD: return 3.75
        case .JPY: return 0.038
        }
    }
}

// MARK: - 8. Motor de Regras Determinístico de Conciliação

public enum RuleMatchField: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case nameOrDetails
    case nameOnly
    case rawStatementLine

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .nameOrDetails: return "Descrição ou Detalhes"
        case .nameOnly: return "Somente Título/Descrição"
        case .rawStatementLine: return "Linha Original do Extrato"
        }
    }
}

public enum RuleMatchOperator: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case contains
    case startsWith
    case equals
    case regex

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .contains: return "Contém"
        case .startsWith: return "Começa com"
        case .equals: return "É igual a"
        case .regex: return "Expressão Regular (Regex)"
        }
    }
}

public struct ReconciliationRule: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var priority: Int
    public var isEnabled: Bool
    public var matchField: RuleMatchField
    public var matchOperator: RuleMatchOperator
    public var matchPattern: String
    public var minAmount: Double?
    public var maxAmount: Double?
    public var sourceAccountId: UUID?
    public var sourceCreditCardId: UUID?
    public var targetCategoryId: UUID?
    public var cleanName: String?
    public var markRecurring: Bool?
    public var markReimbursable: Bool?
    public var reimbursableDebtor: String?
    public var markIgnoreInConsolidated: Bool?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        priority: Int = 10,
        isEnabled: Bool = true,
        matchField: RuleMatchField = .nameOrDetails,
        matchOperator: RuleMatchOperator = .contains,
        matchPattern: String,
        minAmount: Double? = nil,
        maxAmount: Double? = nil,
        sourceAccountId: UUID? = nil,
        sourceCreditCardId: UUID? = nil,
        targetCategoryId: UUID? = nil,
        cleanName: String? = nil,
        markRecurring: Bool? = nil,
        markReimbursable: Bool? = nil,
        reimbursableDebtor: String? = nil,
        markIgnoreInConsolidated: Bool? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.priority = priority
        self.isEnabled = isEnabled
        self.matchField = matchField
        self.matchOperator = matchOperator
        self.matchPattern = matchPattern
        self.minAmount = minAmount
        self.maxAmount = maxAmount
        self.sourceAccountId = sourceAccountId
        self.sourceCreditCardId = sourceCreditCardId
        self.targetCategoryId = targetCategoryId
        self.cleanName = cleanName
        self.markRecurring = markRecurring
        self.markReimbursable = markReimbursable
        self.reimbursableDebtor = reimbursableDebtor
        self.markIgnoreInConsolidated = markIgnoreInConsolidated
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, name, priority, isEnabled, matchField, matchOperator, matchPattern
        case minAmount, maxAmount, sourceAccountId, sourceCreditCardId, targetCategoryId
        case cleanName, markRecurring, markReimbursable, reimbursableDebtor, markIgnoreInConsolidated
        case createdAt, updatedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        self.id = (try? c.decode(UUID.self, forKey: AnyKey("id"))) ?? UUID()
        self.name = (try? c.decodeIfPresent(String.self, forKey: AnyKey("name"))) ?? "Regra"
        self.priority = (try? c.decodeIfPresent(Int.self, forKey: AnyKey("priority"))) ?? 10
        self.isEnabled = (try? c.decodeIfPresent(Bool.self, forKey: AnyKey("isEnabled")))
            ?? (try? c.decodeIfPresent(Bool.self, forKey: AnyKey("is_enabled"))) ?? true
        self.matchField = (try? c.decodeIfPresent(RuleMatchField.self, forKey: AnyKey("matchField")))
            ?? (try? c.decodeIfPresent(RuleMatchField.self, forKey: AnyKey("match_field"))) ?? .nameOrDetails
        self.matchOperator = (try? c.decodeIfPresent(RuleMatchOperator.self, forKey: AnyKey("matchOperator")))
            ?? (try? c.decodeIfPresent(RuleMatchOperator.self, forKey: AnyKey("match_operator"))) ?? .contains
        self.matchPattern = (try? c.decodeIfPresent(String.self, forKey: AnyKey("matchPattern")))
            ?? (try? c.decodeIfPresent(String.self, forKey: AnyKey("match_pattern"))) ?? ""
        self.minAmount = (try? c.decodeIfPresent(Double.self, forKey: AnyKey("minAmount")))
            ?? (try? c.decodeIfPresent(Double.self, forKey: AnyKey("min_amount")))
        self.maxAmount = (try? c.decodeIfPresent(Double.self, forKey: AnyKey("maxAmount")))
            ?? (try? c.decodeIfPresent(Double.self, forKey: AnyKey("max_amount")))
        self.sourceAccountId = (try? c.decodeIfPresent(UUID.self, forKey: AnyKey("sourceAccountId")))
            ?? (try? c.decodeIfPresent(UUID.self, forKey: AnyKey("source_account_id")))
        self.sourceCreditCardId = (try? c.decodeIfPresent(UUID.self, forKey: AnyKey("sourceCreditCardId")))
            ?? (try? c.decodeIfPresent(UUID.self, forKey: AnyKey("source_credit_card_id")))
        self.targetCategoryId = (try? c.decodeIfPresent(UUID.self, forKey: AnyKey("targetCategoryId")))
            ?? (try? c.decodeIfPresent(UUID.self, forKey: AnyKey("target_category_id")))
        self.cleanName = (try? c.decodeIfPresent(String.self, forKey: AnyKey("cleanName")))
            ?? (try? c.decodeIfPresent(String.self, forKey: AnyKey("clean_name")))
        self.markRecurring = (try? c.decodeIfPresent(Bool.self, forKey: AnyKey("markRecurring")))
            ?? (try? c.decodeIfPresent(Bool.self, forKey: AnyKey("mark_recurring")))
        self.markReimbursable = (try? c.decodeIfPresent(Bool.self, forKey: AnyKey("markReimbursable")))
            ?? (try? c.decodeIfPresent(Bool.self, forKey: AnyKey("mark_reimbursable")))
        self.reimbursableDebtor = (try? c.decodeIfPresent(String.self, forKey: AnyKey("reimbursableDebtor")))
            ?? (try? c.decodeIfPresent(String.self, forKey: AnyKey("reimbursable_debtor")))
        self.markIgnoreInConsolidated = (try? c.decodeIfPresent(Bool.self, forKey: AnyKey("markIgnoreInConsolidated")))
            ?? (try? c.decodeIfPresent(Bool.self, forKey: AnyKey("mark_ignore_in_consolidated")))
        self.createdAt = (try? c.decodeIfPresent(Date.self, forKey: AnyKey("createdAt")))
            ?? (try? c.decodeIfPresent(Date.self, forKey: AnyKey("created_at"))) ?? Date()
        self.updatedAt = (try? c.decodeIfPresent(Date.self, forKey: AnyKey("updatedAt")))
            ?? (try? c.decodeIfPresent(Date.self, forKey: AnyKey("updated_at"))) ?? self.createdAt
    }
}

// MARK: - 9. Patrimônio (Ativos Não-Bancários), Renda & Net Worth Snapshots

public enum AssetClass: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case realEstate
    case vehicle
    case fgts
    case privatePension
    case equity
    case other

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .realEstate: return "Imóveis"
        case .vehicle: return "Veículos"
        case .fgts: return "FGTS"
        case .privatePension: return "Previdência Privada"
        case .equity: return "Participações Societárias"
        case .other: return "Outros Ativos"
        }
    }

    public var iconSymbol: String {
        switch self {
        case .realEstate: return "house.fill"
        case .vehicle: return "car.fill"
        case .fgts: return "building.2.crop.circle.fill"
        case .privatePension: return "shield.lefthalf.filled"
        case .equity: return "briefcase.fill"
        case .other: return "shippingbox.fill"
        }
    }

    public var colorHex: String {
        switch self {
        case .realEstate: return "#6366F1"
        case .vehicle: return "#0EA5E9"
        case .fgts: return "#10B981"
        case .privatePension: return "#8B5CF6"
        case .equity: return "#F59E0B"
        case .other: return "#64748B"
        }
    }
}

public struct AssetValuationEntry: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var date: Date
    public var marketValue: Double
    public var notes: String

    public init(id: UUID = UUID(), date: Date = Date(), marketValue: Double, notes: String = "") {
        self.id = id
        self.date = date
        self.marketValue = max(0.0, marketValue)
        self.notes = notes
    }
}

public struct AssetItem: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var assetClass: AssetClass
    public var purchaseValue: Double
    public var currentMarketValue: Double
    public var acquisitionDate: Date?
    public var linkedFinancingContractId: UUID?
    public var annualDepreciationRatePercent: Double?
    public var monthlyContributionEstimate: Double?
    public var currencyCode: String
    public var valuationHistory: [AssetValuationEntry]
    public var notes: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        assetClass: AssetClass,
        purchaseValue: Double = 0.0,
        currentMarketValue: Double,
        acquisitionDate: Date? = nil,
        linkedFinancingContractId: UUID? = nil,
        annualDepreciationRatePercent: Double? = nil,
        monthlyContributionEstimate: Double? = nil,
        currencyCode: String = "BRL",
        valuationHistory: [AssetValuationEntry] = [],
        notes: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.assetClass = assetClass
        self.purchaseValue = max(0.0, purchaseValue)
        self.currentMarketValue = max(0.0, currentMarketValue)
        self.acquisitionDate = acquisitionDate
        self.linkedFinancingContractId = linkedFinancingContractId
        self.annualDepreciationRatePercent = annualDepreciationRatePercent
        self.monthlyContributionEstimate = monthlyContributionEstimate
        self.currencyCode = currencyCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "BRL" : currencyCode.uppercased()
        self.valuationHistory = valuationHistory
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, name, assetClass, purchaseValue, currentMarketValue, acquisitionDate
        case linkedFinancingContractId, annualDepreciationRatePercent, monthlyContributionEstimate
        case currencyCode, valuationHistory, notes, createdAt, updatedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        self.id = (try? c.decode(UUID.self, forKey: AnyKey("id"))) ?? UUID()
        self.name = (try? c.decodeIfPresent(String.self, forKey: AnyKey("name"))) ?? ""
        self.assetClass = (try? c.decodeIfPresent(AssetClass.self, forKey: AnyKey("assetClass")))
            ?? (try? c.decodeIfPresent(AssetClass.self, forKey: AnyKey("asset_class"))) ?? .realEstate
        self.purchaseValue = max(0.0, (try? c.decodeIfPresent(Double.self, forKey: AnyKey("purchaseValue")))
            ?? (try? c.decodeIfPresent(Double.self, forKey: AnyKey("purchase_value"))) ?? 0.0)
        self.currentMarketValue = max(0.0, (try? c.decodeIfPresent(Double.self, forKey: AnyKey("currentMarketValue")))
            ?? (try? c.decodeIfPresent(Double.self, forKey: AnyKey("current_market_value"))) ?? 0.0)
        self.acquisitionDate = (try? c.decodeIfPresent(Date.self, forKey: AnyKey("acquisitionDate")))
            ?? (try? c.decodeIfPresent(Date.self, forKey: AnyKey("acquisition_date")))
        self.linkedFinancingContractId = (try? c.decodeIfPresent(UUID.self, forKey: AnyKey("linkedFinancingContractId")))
            ?? (try? c.decodeIfPresent(UUID.self, forKey: AnyKey("linked_financing_contract_id")))
        self.annualDepreciationRatePercent = (try? c.decodeIfPresent(Double.self, forKey: AnyKey("annualDepreciationRatePercent")))
            ?? (try? c.decodeIfPresent(Double.self, forKey: AnyKey("annual_depreciation_rate_percent")))
        self.monthlyContributionEstimate = (try? c.decodeIfPresent(Double.self, forKey: AnyKey("monthlyContributionEstimate")))
            ?? (try? c.decodeIfPresent(Double.self, forKey: AnyKey("monthly_contribution_estimate")))
        let rawCur = (try? c.decodeIfPresent(String.self, forKey: AnyKey("currencyCode")))
            ?? (try? c.decodeIfPresent(String.self, forKey: AnyKey("currency_code"))) ?? "BRL"
        self.currencyCode = rawCur.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "BRL" : rawCur.uppercased()
        self.valuationHistory = (try? c.decodeIfPresent([AssetValuationEntry].self, forKey: AnyKey("valuationHistory")))
            ?? (try? c.decodeIfPresent([AssetValuationEntry].self, forKey: AnyKey("valuation_history"))) ?? []
        self.notes = (try? c.decodeIfPresent(String.self, forKey: AnyKey("notes"))) ?? ""
        self.createdAt = (try? c.decodeIfPresent(Date.self, forKey: AnyKey("createdAt")))
            ?? (try? c.decodeIfPresent(Date.self, forKey: AnyKey("created_at"))) ?? Date()
        self.updatedAt = (try? c.decodeIfPresent(Date.self, forKey: AnyKey("updatedAt")))
            ?? (try? c.decodeIfPresent(Date.self, forKey: AnyKey("updated_at"))) ?? self.createdAt
    }
}

public enum IncomeSourceKind: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case fixedSalary
    case variableSeasonal
    case passiveIncome

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .fixedSalary: return "Renda Fixa (Salário / Pró-labore)"
        case .variableSeasonal: return "Renda Variável / Sazonal (Bônus, 13º, Férias)"
        case .passiveIncome: return "Renda Passiva / Extra (Aluguel, Dividendos)"
        }
    }
}

public struct IncomeSource: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var kind: IncomeSourceKind
    public var grossAmount: Double
    public var netAmount: Double
    public var paymentDay: Int?
    public var expectedMonth: Int?
    public var frequency: RecurrenceFrequency
    public var payerName: String
    public var linkedAccountId: UUID?
    public var currencyCode: String
    public var isActive: Bool
    public var notes: String
    public var createdAt: Date
    public var updatedAt: Date

    public var monthlyEquivalentNetAmount: Double {
        guard isActive else { return 0.0 }
        switch frequency {
        case .weekly: return netAmount * 52.0 / 12.0
        case .biweekly: return netAmount * 26.0 / 12.0
        case .monthly: return netAmount
        case .bimonthly: return netAmount / 2.0
        case .quarterly: return netAmount / 3.0
        case .semiannual: return netAmount / 6.0
        case .annual: return netAmount / 12.0
        }
    }

    public init(
        id: UUID = UUID(),
        name: String,
        kind: IncomeSourceKind = .fixedSalary,
        grossAmount: Double,
        netAmount: Double,
        paymentDay: Int? = 5,
        expectedMonth: Int? = nil,
        frequency: RecurrenceFrequency = .monthly,
        payerName: String = "",
        linkedAccountId: UUID? = nil,
        currencyCode: String = "BRL",
        isActive: Bool = true,
        notes: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.grossAmount = max(0.0, grossAmount)
        self.netAmount = max(0.0, netAmount)
        self.paymentDay = paymentDay
        self.expectedMonth = expectedMonth
        self.frequency = frequency
        self.payerName = payerName
        self.linkedAccountId = linkedAccountId
        self.currencyCode = currencyCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "BRL" : currencyCode.uppercased()
        self.isActive = isActive
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, name, kind, grossAmount, netAmount, paymentDay, expectedMonth
        case frequency, payerName, linkedAccountId, currencyCode, isActive, notes, createdAt, updatedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        self.id = (try? c.decode(UUID.self, forKey: AnyKey("id"))) ?? UUID()
        self.name = (try? c.decodeIfPresent(String.self, forKey: AnyKey("name"))) ?? ""
        self.kind = (try? c.decodeIfPresent(IncomeSourceKind.self, forKey: AnyKey("kind"))) ?? .fixedSalary
        self.grossAmount = max(0.0, (try? c.decodeIfPresent(Double.self, forKey: AnyKey("grossAmount")))
            ?? (try? c.decodeIfPresent(Double.self, forKey: AnyKey("gross_amount"))) ?? 0.0)
        self.netAmount = max(0.0, (try? c.decodeIfPresent(Double.self, forKey: AnyKey("netAmount")))
            ?? (try? c.decodeIfPresent(Double.self, forKey: AnyKey("net_amount"))) ?? self.grossAmount)
        self.paymentDay = (try? c.decodeIfPresent(Int.self, forKey: AnyKey("paymentDay")))
            ?? (try? c.decodeIfPresent(Int.self, forKey: AnyKey("payment_day")))
        self.expectedMonth = (try? c.decodeIfPresent(Int.self, forKey: AnyKey("expectedMonth")))
            ?? (try? c.decodeIfPresent(Int.self, forKey: AnyKey("expected_month")))
        self.frequency = (try? c.decodeIfPresent(RecurrenceFrequency.self, forKey: AnyKey("frequency"))) ?? .monthly
        self.payerName = (try? c.decodeIfPresent(String.self, forKey: AnyKey("payerName")))
            ?? (try? c.decodeIfPresent(String.self, forKey: AnyKey("payer_name"))) ?? ""
        self.linkedAccountId = (try? c.decodeIfPresent(UUID.self, forKey: AnyKey("linkedAccountId")))
            ?? (try? c.decodeIfPresent(UUID.self, forKey: AnyKey("linked_account_id")))
        let rawCur = (try? c.decodeIfPresent(String.self, forKey: AnyKey("currencyCode")))
            ?? (try? c.decodeIfPresent(String.self, forKey: AnyKey("currency_code"))) ?? "BRL"
        self.currencyCode = rawCur.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "BRL" : rawCur.uppercased()
        self.isActive = (try? c.decodeIfPresent(Bool.self, forKey: AnyKey("isActive")))
            ?? (try? c.decodeIfPresent(Bool.self, forKey: AnyKey("is_active"))) ?? true
        self.notes = (try? c.decodeIfPresent(String.self, forKey: AnyKey("notes"))) ?? ""
        self.createdAt = (try? c.decodeIfPresent(Date.self, forKey: AnyKey("createdAt")))
            ?? (try? c.decodeIfPresent(Date.self, forKey: AnyKey("created_at"))) ?? Date()
        self.updatedAt = (try? c.decodeIfPresent(Date.self, forKey: AnyKey("updatedAt")))
            ?? (try? c.decodeIfPresent(Date.self, forKey: AnyKey("updated_at"))) ?? self.createdAt
    }
}

public struct NetWorthSnapshot: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var yearMonthKey: Int
    public var snapshotDate: Date
    public var liquidAssetsBRL: Double
    public var investmentsAssetsBRL: Double
    public var realEstateAssetsBRL: Double
    public var vehicleAssetsBRL: Double
    public var fgtsAndOtherAssetsBRL: Double
    public var totalAssetsBRL: Double
    public var loansAndFinancingsLiabilitiesBRL: Double
    public var creditCardsLiabilitiesBRL: Double
    public var debtsLiabilitiesBRL: Double
    public var totalLiabilitiesBRL: Double
    public var netWorthBRL: Double
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        yearMonthKey: Int,
        snapshotDate: Date = Date(),
        liquidAssetsBRL: Double,
        investmentsAssetsBRL: Double,
        realEstateAssetsBRL: Double,
        vehicleAssetsBRL: Double,
        fgtsAndOtherAssetsBRL: Double,
        totalAssetsBRL: Double,
        loansAndFinancingsLiabilitiesBRL: Double,
        creditCardsLiabilitiesBRL: Double,
        debtsLiabilitiesBRL: Double,
        totalLiabilitiesBRL: Double,
        netWorthBRL: Double,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.yearMonthKey = yearMonthKey
        self.snapshotDate = snapshotDate
        self.liquidAssetsBRL = liquidAssetsBRL
        self.investmentsAssetsBRL = investmentsAssetsBRL
        self.realEstateAssetsBRL = realEstateAssetsBRL
        self.vehicleAssetsBRL = vehicleAssetsBRL
        self.fgtsAndOtherAssetsBRL = fgtsAndOtherAssetsBRL
        self.totalAssetsBRL = totalAssetsBRL
        self.loansAndFinancingsLiabilitiesBRL = loansAndFinancingsLiabilitiesBRL
        self.creditCardsLiabilitiesBRL = creditCardsLiabilitiesBRL
        self.debtsLiabilitiesBRL = debtsLiabilitiesBRL
        self.totalLiabilitiesBRL = totalLiabilitiesBRL
        self.netWorthBRL = netWorthBRL
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, yearMonthKey, snapshotDate
        case liquidAssetsBRL, investmentsAssetsBRL, realEstateAssetsBRL, vehicleAssetsBRL, fgtsAndOtherAssetsBRL, totalAssetsBRL
        case loansAndFinancingsLiabilitiesBRL, creditCardsLiabilitiesBRL, debtsLiabilitiesBRL, totalLiabilitiesBRL, netWorthBRL
        case createdAt, updatedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        self.id = (try? c.decode(UUID.self, forKey: AnyKey("id"))) ?? UUID()
        self.yearMonthKey = (try? c.decodeIfPresent(Int.self, forKey: AnyKey("yearMonthKey")))
            ?? (try? c.decodeIfPresent(Int.self, forKey: AnyKey("year_month_key"))) ?? 202601
        self.snapshotDate = (try? c.decodeIfPresent(Date.self, forKey: AnyKey("snapshotDate")))
            ?? (try? c.decodeIfPresent(Date.self, forKey: AnyKey("snapshot_date"))) ?? Date()
        self.liquidAssetsBRL = (try? c.decodeIfPresent(Double.self, forKey: AnyKey("liquidAssetsBRL")))
            ?? (try? c.decodeIfPresent(Double.self, forKey: AnyKey("liquid_assets_brl"))) ?? 0.0
        self.investmentsAssetsBRL = (try? c.decodeIfPresent(Double.self, forKey: AnyKey("investmentsAssetsBRL")))
            ?? (try? c.decodeIfPresent(Double.self, forKey: AnyKey("investments_assets_brl"))) ?? 0.0
        self.realEstateAssetsBRL = (try? c.decodeIfPresent(Double.self, forKey: AnyKey("realEstateAssetsBRL")))
            ?? (try? c.decodeIfPresent(Double.self, forKey: AnyKey("real_estate_assets_brl"))) ?? 0.0
        self.vehicleAssetsBRL = (try? c.decodeIfPresent(Double.self, forKey: AnyKey("vehicleAssetsBRL")))
            ?? (try? c.decodeIfPresent(Double.self, forKey: AnyKey("vehicle_assets_brl"))) ?? 0.0
        self.fgtsAndOtherAssetsBRL = (try? c.decodeIfPresent(Double.self, forKey: AnyKey("fgtsAndOtherAssetsBRL")))
            ?? (try? c.decodeIfPresent(Double.self, forKey: AnyKey("fgts_and_other_assets_brl"))) ?? 0.0
        self.totalAssetsBRL = (try? c.decodeIfPresent(Double.self, forKey: AnyKey("totalAssetsBRL")))
            ?? (try? c.decodeIfPresent(Double.self, forKey: AnyKey("total_assets_brl"))) ?? 0.0
        self.loansAndFinancingsLiabilitiesBRL = (try? c.decodeIfPresent(Double.self, forKey: AnyKey("loansAndFinancingsLiabilitiesBRL")))
            ?? (try? c.decodeIfPresent(Double.self, forKey: AnyKey("loans_and_financings_liabilities_brl"))) ?? 0.0
        self.creditCardsLiabilitiesBRL = (try? c.decodeIfPresent(Double.self, forKey: AnyKey("creditCardsLiabilitiesBRL")))
            ?? (try? c.decodeIfPresent(Double.self, forKey: AnyKey("credit_cards_liabilities_brl"))) ?? 0.0
        self.debtsLiabilitiesBRL = (try? c.decodeIfPresent(Double.self, forKey: AnyKey("debtsLiabilitiesBRL")))
            ?? (try? c.decodeIfPresent(Double.self, forKey: AnyKey("debts_liabilities_brl"))) ?? 0.0
        self.totalLiabilitiesBRL = (try? c.decodeIfPresent(Double.self, forKey: AnyKey("totalLiabilitiesBRL")))
            ?? (try? c.decodeIfPresent(Double.self, forKey: AnyKey("total_liabilities_brl"))) ?? 0.0
        self.netWorthBRL = (try? c.decodeIfPresent(Double.self, forKey: AnyKey("netWorthBRL")))
            ?? (try? c.decodeIfPresent(Double.self, forKey: AnyKey("net_worth_brl"))) ?? 0.0
        self.createdAt = (try? c.decodeIfPresent(Date.self, forKey: AnyKey("createdAt")))
            ?? (try? c.decodeIfPresent(Date.self, forKey: AnyKey("created_at"))) ?? Date()
        self.updatedAt = (try? c.decodeIfPresent(Date.self, forKey: AnyKey("updatedAt")))
            ?? (try? c.decodeIfPresent(Date.self, forKey: AnyKey("updated_at"))) ?? self.createdAt
    }
}

// MARK: - 10. Simulador de Independência Financeira (FIRE)

public struct FIREPlanScenario: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var monthlyCostOfLivingBRL: Double
    public var currentInvestedPatrimonyBRL: Double
    public var includeRealEstateAndFGTS: Bool
    public var monthlyContributionBRL: Double
    public var safeWithdrawalRatePercent: Double
    public var expectedAnnualNominalReturnPercent: Double
    public var expectedAnnualInflationPercent: Double
    public var notes: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String = "Plano FIRE Principal",
        monthlyCostOfLivingBRL: Double = 6000.0,
        currentInvestedPatrimonyBRL: Double = 0.0,
        includeRealEstateAndFGTS: Bool = false,
        monthlyContributionBRL: Double = 2000.0,
        safeWithdrawalRatePercent: Double = 4.0,
        expectedAnnualNominalReturnPercent: Double = 11.25,
        expectedAnnualInflationPercent: Double = 4.5,
        notes: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.monthlyCostOfLivingBRL = max(0.0, monthlyCostOfLivingBRL)
        self.currentInvestedPatrimonyBRL = max(0.0, currentInvestedPatrimonyBRL)
        self.includeRealEstateAndFGTS = includeRealEstateAndFGTS
        self.monthlyContributionBRL = max(0.0, monthlyContributionBRL)
        self.safeWithdrawalRatePercent = max(1.0, min(10.0, safeWithdrawalRatePercent))
        self.expectedAnnualNominalReturnPercent = max(0.0, expectedAnnualNominalReturnPercent)
        self.expectedAnnualInflationPercent = max(0.0, expectedAnnualInflationPercent)
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, name, monthlyCostOfLivingBRL, currentInvestedPatrimonyBRL, includeRealEstateAndFGTS
        case monthlyContributionBRL, safeWithdrawalRatePercent, expectedAnnualNominalReturnPercent
        case expectedAnnualInflationPercent, notes, createdAt, updatedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        self.id = (try? c.decode(UUID.self, forKey: AnyKey("id"))) ?? UUID()
        self.name = (try? c.decodeIfPresent(String.self, forKey: AnyKey("name"))) ?? "Plano FIRE Principal"
        self.monthlyCostOfLivingBRL = max(0.0, (try? c.decodeIfPresent(Double.self, forKey: AnyKey("monthlyCostOfLivingBRL")))
            ?? (try? c.decodeIfPresent(Double.self, forKey: AnyKey("monthly_cost_of_living_brl"))) ?? 6000.0)
        self.currentInvestedPatrimonyBRL = max(0.0, (try? c.decodeIfPresent(Double.self, forKey: AnyKey("currentInvestedPatrimonyBRL")))
            ?? (try? c.decodeIfPresent(Double.self, forKey: AnyKey("current_invested_patrimony_brl"))) ?? 0.0)
        self.includeRealEstateAndFGTS = (try? c.decodeIfPresent(Bool.self, forKey: AnyKey("includeRealEstateAndFGTS")))
            ?? (try? c.decodeIfPresent(Bool.self, forKey: AnyKey("include_real_estate_and_fgts"))) ?? false
        self.monthlyContributionBRL = max(0.0, (try? c.decodeIfPresent(Double.self, forKey: AnyKey("monthlyContributionBRL")))
            ?? (try? c.decodeIfPresent(Double.self, forKey: AnyKey("monthly_contribution_brl"))) ?? 2000.0)
        self.safeWithdrawalRatePercent = max(1.0, (try? c.decodeIfPresent(Double.self, forKey: AnyKey("safeWithdrawalRatePercent")))
            ?? (try? c.decodeIfPresent(Double.self, forKey: AnyKey("safe_withdrawal_rate_percent"))) ?? 4.0)
        self.expectedAnnualNominalReturnPercent = max(0.0, (try? c.decodeIfPresent(Double.self, forKey: AnyKey("expectedAnnualNominalReturnPercent")))
            ?? (try? c.decodeIfPresent(Double.self, forKey: AnyKey("expected_annual_nominal_return_percent"))) ?? 11.25)
        self.expectedAnnualInflationPercent = max(0.0, (try? c.decodeIfPresent(Double.self, forKey: AnyKey("expectedAnnualInflationPercent")))
            ?? (try? c.decodeIfPresent(Double.self, forKey: AnyKey("expected_annual_inflation_percent"))) ?? 4.5)
        self.notes = (try? c.decodeIfPresent(String.self, forKey: AnyKey("notes"))) ?? ""
        self.createdAt = (try? c.decodeIfPresent(Date.self, forKey: AnyKey("createdAt")))
            ?? (try? c.decodeIfPresent(Date.self, forKey: AnyKey("created_at"))) ?? Date()
        self.updatedAt = (try? c.decodeIfPresent(Date.self, forKey: AnyKey("updatedAt")))
            ?? (try? c.decodeIfPresent(Date.self, forKey: AnyKey("updated_at"))) ?? self.createdAt
    }
}
