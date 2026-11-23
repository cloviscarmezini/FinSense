import Foundation

/// Motor cronológico puro para detectar descasamentos de fluxo de caixa dentro de um mês (Vale Intramês).
public enum IntraMonthCashFlowEngine {
    public static func analyze(
        monthReference: Date,
        accounts: [BankAccount],
        investments: [InvestmentItem],
        transactions: [FinancialTransaction],
        isClosedMonth: Bool,
        calendar: Calendar = .current,
        isVisible: (FinancialTransaction) -> Bool,
        effectiveSignedAmount: (FinancialTransaction) -> Double
    ) -> IntraMonthCashFlowAnalysis {
        let monthComps = calendar.dateComponents([.year, .month], from: monthReference)
        let year = monthComps.year ?? calendar.component(.year, from: Date())
        let month = monthComps.month ?? calendar.component(.month, from: Date())

        let monthStart = calendar.date(from: DateComponents(year: year, month: month, day: 1, hour: 0, minute: 0, second: 0))
            ?? calendar.startOfDay(for: monthReference)
        let dayRange = calendar.range(of: .day, in: .month, for: monthStart) ?? (1..<31)
        let daysInMonth = dayRange.count
        let monthEnd: Date = {
            if let nextMonth = calendar.date(byAdding: .month, value: 1, to: monthStart) {
                return calendar.date(byAdding: .second, value: -1, to: nextMonth) ?? nextMonth
            }
            return monthReference
        }()

        let baseOpening = accounts.reduce(0.0) { $0 + $1.initialBalance }
            + investments.filter(\.showInConsolidated).reduce(0.0) { $0 + $1.balance }

        var priorDelta = 0.0
        var monthTxs: [FinancialTransaction] = []
        monthTxs.reserveCapacity(64)

        for tx in transactions {
            guard !tx.ignoreInConsolidated else { continue }
            guard !tx.isCreditCardExpense else { continue }
            guard isVisible(tx) else { continue }
            if isClosedMonth && !tx.isPaid { continue }

            if tx.date < monthStart {
                priorDelta += effectiveSignedAmount(tx)
            } else if tx.date <= monthEnd {
                monthTxs.append(tx)
            }
        }

        let openingBalance = baseOpening + priorDelta

        // Ordenação cronológica determinística: por dia; dentro do mesmo dia, receitas antes de despesas para não gerar falso positivo por hora de cadastro.
        let sortedMonthTxs = monthTxs.sorted { a, b in
            let dayA = calendar.component(.day, from: a.date)
            let dayB = calendar.component(.day, from: b.date)
            if dayA != dayB { return dayA < dayB }
            if a.type != b.type { return a.type == .income }
            if a.date != b.date { return a.date < b.date }
            if a.createdAt != b.createdAt { return a.createdAt < b.createdAt }
            return a.id.uuidString < b.id.uuidString
        }

        var txsByDay: [Int: [FinancialTransaction]] = [:]
        for tx in sortedMonthTxs {
            let day = calendar.component(.day, from: tx.date)
            txsByDay[day, default: []].append(tx)
        }

        var runningBalance = openingBalance
        var minimumBalance = openingBalance
        var minimumBalanceDate: Date? = openingBalance < -0.005 ? monthStart : nil
        var minimumBalanceDay: Int? = openingBalance < -0.005 ? 1 : nil

        var cutoffTransactionId: UUID? = nil
        var recoveryTransactionId: UUID? = nil
        var deficitZoneTransactionIds = Set<UUID>()
        var runningBalanceByTxId: [UUID: Double] = [:]

        var riskStartDay: Int? = openingBalance < -0.005 ? 1 : nil
        var riskEndDay: Int? = nil
        var currentlyInDeficit = openingBalance < -0.005

        var dailyPoints: [DailyCashFlowPoint] = []
        dailyPoints.reserveCapacity(daysInMonth)

        for day in 1...daysInMonth {
            let dayDate = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? monthStart
            let dayOpening = runningBalance
            var dayIncome = 0.0
            var dayExpense = 0.0

            let dayItems = txsByDay[day] ?? []
            for tx in dayItems {
                let signed = effectiveSignedAmount(tx)
                if signed >= 0 {
                    dayIncome += signed
                } else {
                    dayExpense += abs(signed)
                }

                let wasInDeficit = runningBalance < -0.005
                runningBalance += signed
                runningBalanceByTxId[tx.id] = runningBalance

                if runningBalance < minimumBalance {
                    minimumBalance = runningBalance
                    minimumBalanceDate = dayDate
                    minimumBalanceDay = day
                }

                let isNowInDeficit = runningBalance < -0.005

                if !wasInDeficit && isNowInDeficit {
                    if cutoffTransactionId == nil {
                        cutoffTransactionId = tx.id
                    }
                    if riskStartDay == nil {
                        riskStartDay = day
                    }
                    currentlyInDeficit = true
                    deficitZoneTransactionIds.insert(tx.id)
                } else if wasInDeficit && isNowInDeficit {
                    currentlyInDeficit = true
                    deficitZoneTransactionIds.insert(tx.id)
                } else if wasInDeficit && !isNowInDeficit {
                    // Receita normalizou o caixa neste lançamento
                    if cutoffTransactionId != nil && recoveryTransactionId == nil {
                        recoveryTransactionId = tx.id
                    }
                    currentlyInDeficit = false
                    riskEndDay = max(riskEndDay ?? day, day)
                }
            }

            if currentlyInDeficit || runningBalance < -0.005 {
                if riskStartDay == nil {
                    riskStartDay = day
                }
                riskEndDay = day
            }

            dailyPoints.append(
                DailyCashFlowPoint(
                    day: day,
                    date: dayDate,
                    openingBalance: dayOpening,
                    dayIncome: dayIncome,
                    dayExpense: dayExpense,
                    closingBalance: runningBalance
                )
            )
        }

        let closingBalance = runningBalance
        let hasDeficit = minimumBalance < -0.005 || dailyPoints.contains { $0.closingBalance < -0.005 }
        let isTemporaryTrough = hasDeficit && closingBalance >= -0.005

        return IntraMonthCashFlowAnalysis(
            monthStart: monthStart,
            monthEnd: monthEnd,
            openingBalance: openingBalance,
            closingBalance: closingBalance,
            minimumBalance: minimumBalance,
            minimumBalanceDate: minimumBalanceDate,
            minimumBalanceDay: minimumBalanceDay,
            hasIntraMonthDeficit: hasDeficit,
            isTemporaryTrough: isTemporaryTrough,
            riskStartDay: hasDeficit ? riskStartDay : nil,
            riskEndDay: hasDeficit ? riskEndDay : nil,
            cutoffTransactionId: cutoffTransactionId,
            recoveryTransactionId: recoveryTransactionId,
            deficitZoneTransactionIds: deficitZoneTransactionIds,
            runningBalanceByTransactionId: runningBalanceByTxId,
            dailyPoints: dailyPoints
        )
    }
}
