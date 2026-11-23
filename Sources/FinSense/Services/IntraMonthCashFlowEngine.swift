import Foundation

/// Motor cronológico puro para detectar descasamentos de fluxo de caixa dentro de um mês (Vale Intramês).
/// Regras:
/// 1. Ponto de partida = Saldo acumulado consolidado do mês anterior (incluindo previsões acumuladas anteriores).
/// 2. Previsões do mês selecionado NÃO entram na linha do tempo diária das transações, mas reduzem o fechamento projetado,
///    gerando alerta de criticidade menor (.possibleRisk) quando apenas as previsões podem negativar o caixa.
/// 3. Episódios negativos em datas passadas já normalizados até a data atual mantêm marcação na lista de transações,
///    mas NÃO geram alerta crítico no card. Episódios não normalizados até hoje ou no futuro geram alerta crítico (.confirmedDeficit).
public enum IntraMonthCashFlowEngine {
    public static func analyze(
        monthReference: Date,
        openingBalance: Double,
        currentMonthRemainingProvisions: Double = 0.0,
        monthTransactions: [FinancialTransaction],
        isClosedMonth: Bool,
        referenceNow: Date = Date(),
        calendar: Calendar = .current,
        isVisible: (FinancialTransaction) -> Bool,
        effectiveSignedAmount: (FinancialTransaction) -> Double
    ) -> IntraMonthCashFlowAnalysis {
        let monthComps = calendar.dateComponents([.year, .month], from: monthReference)
        let year = monthComps.year ?? calendar.component(.year, from: referenceNow)
        let month = monthComps.month ?? calendar.component(.month, from: referenceNow)

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

        let todayStart = calendar.startOfDay(for: referenceNow)

        let eligibleMonthTxs = monthTransactions.filter { tx in
            guard !tx.ignoreInConsolidated else { return false }
            guard !tx.isCreditCardExpense else { return false }
            guard isVisible(tx) else { return false }
            if isClosedMonth && !tx.isPaid { return false }
            return true
        }

        // Ordenação cronológica determinística: por dia; dentro do mesmo dia, receitas antes de despesas
        let sortedMonthTxs = eligibleMonthTxs.sorted { a, b in
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
            let day = max(1, min(daysInMonth, calendar.component(.day, from: tx.date)))
            txsByDay[day, default: []].append(tx)
        }

        var runningBalance = openingBalance
        var minimumBalance = openingBalance
        var minimumBalanceDate: Date? = openingBalance < -0.005 ? monthStart : nil
        var minimumBalanceDay: Int? = openingBalance < -0.005 ? 1 : nil

        var cutoffTransactionIds = Set<UUID>()
        var deepeningDeficitTransactionIds = Set<UUID>()
        var recoveryTransactionIds = Set<UUID>()
        var deficitZoneTransactionIds = Set<UUID>()
        var runningBalanceByTxId: [UUID: Double] = [:]

        // Rastreamento de ocasiões em que transações levaram ou aprofundaram o caixa abaixo de zero
        struct MutableOccasion {
            let transactionId: UUID
            let date: Date
            let day: Int
            let deficitAmount: Double
            let resultingBalance: Double
            var isRecovered: Bool = false
            var recoveredDate: Date? = nil
        }
        var mutableOccasions: [MutableOccasion] = []

        var firstAlertRiskStartDay: Int? = nil
        var firstAlertRiskEndDay: Int? = nil

        var dailyPoints: [DailyCashFlowPoint] = []
        dailyPoints.reserveCapacity(daysInMonth)

        for day in 1...daysInMonth {
            let dayDate = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? monthStart
            let dayOpening = runningBalance
            var dayIncome = 0.0
            var dayExpense = 0.0

            let dayItems = txsByDay[day] ?? []
            for tx in dayItems {
                let prevBalance = runningBalance
                let signed = effectiveSignedAmount(tx)
                if signed >= 0 {
                    dayIncome += signed
                } else {
                    dayExpense += abs(signed)
                }

                let wasInDeficit = prevBalance < -0.005
                runningBalance += signed
                runningBalanceByTxId[tx.id] = runningBalance

                if runningBalance < minimumBalance {
                    minimumBalance = runningBalance
                    minimumBalanceDate = dayDate
                    minimumBalanceDay = day
                }

                let isNowInDeficit = runningBalance < -0.005

                if signed < -0.005 && isNowInDeficit {
                    deficitZoneTransactionIds.insert(tx.id)
                    let deficitDelta: Double
                    if !wasInDeficit {
                        cutoffTransactionIds.insert(tx.id)
                        deficitDelta = abs(runningBalance)
                    } else {
                        deepeningDeficitTransactionIds.insert(tx.id)
                        deficitDelta = max(0.0, prevBalance - runningBalance)
                    }
                    if deficitDelta > 0.005 {
                        mutableOccasions.append(
                            MutableOccasion(
                                transactionId: tx.id,
                                date: tx.date,
                                day: day,
                                deficitAmount: deficitDelta,
                                resultingBalance: runningBalance
                            )
                        )
                    }
                } else if wasInDeficit && isNowInDeficit {
                    deficitZoneTransactionIds.insert(tx.id)
                } else if wasInDeficit && !isNowInDeficit {
                    // Receita normalizou o caixa para >= 0 neste lançamento
                    recoveryTransactionIds.insert(tx.id)
                    for i in mutableOccasions.indices where !mutableOccasions[i].isRecovered {
                        mutableOccasions[i].isRecovered = true
                        mutableOccasions[i].recoveredDate = tx.date
                    }
                }
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
        let cleanProvisions = isClosedMonth ? 0.0 : max(0.0, currentMonthRemainingProvisions)
        let closingBalanceWithProvisions = closingBalance - cleanProvisions

        // Constrói ocasiões finais avaliando se já foram normalizadas até a data atual (`<= todayStart`)
        let finalOccasions: [IntraMonthDeficitOccasion] = mutableOccasions.map { occ in
            let occDayStart = calendar.startOfDay(for: occ.date)
            let resolvedByToday: Bool = {
                guard occ.isRecovered, let recDate = occ.recoveredDate else { return false }
                let recDayStart = calendar.startOfDay(for: recDate)
                return occDayStart <= todayStart && recDayStart <= todayStart
            }()
            return IntraMonthDeficitOccasion(
                transactionId: occ.transactionId,
                date: occ.date,
                day: occ.day,
                month: month,
                deficitAmount: occ.deficitAmount,
                resultingBalance: occ.resultingBalance,
                isRecoveredLater: occ.isRecovered,
                recoveredDate: occ.recoveredDate,
                isResolvedByToday: resolvedByToday
            )
        }

        let alertableOccasions = finalOccasions.filter { !$0.isResolvedByToday }
        let unrecoveredOpeningDeficit = openingBalance < -0.005 && closingBalance < -0.005

        // Determina o nível de alerta (2 níveis)
        let alertLevel: IntraMonthAlertLevel
        if isClosedMonth {
            alertLevel = .none
        } else if !alertableOccasions.isEmpty || unrecoveredOpeningDeficit {
            alertLevel = .confirmedDeficit
        } else if closingBalanceWithProvisions < -0.005 {
            alertLevel = .possibleRisk
        } else {
            alertLevel = .none
        }

        let hasAlert = alertLevel != .none
        let isTemporaryTrough = (alertLevel == .confirmedDeficit) && (closingBalance >= -0.005)

        if let firstAlertOcc = alertableOccasions.first {
            firstAlertRiskStartDay = firstAlertOcc.day
            if let recDate = firstAlertOcc.recoveredDate, firstAlertOcc.isRecoveredLater {
                firstAlertRiskEndDay = calendar.component(.day, from: recDate)
            } else {
                firstAlertRiskEndDay = daysInMonth
            }
        } else if unrecoveredOpeningDeficit {
            firstAlertRiskStartDay = 1
            firstAlertRiskEndDay = daysInMonth
        }

        let firstAlertCutoffId = alertableOccasions.first?.transactionId ?? finalOccasions.last?.transactionId
        let firstRecoveryId = recoveryTransactionIds.first

        return IntraMonthCashFlowAnalysis(
            monthStart: monthStart,
            monthEnd: monthEnd,
            openingBalance: openingBalance,
            closingBalance: closingBalance,
            currentMonthProvisionsTotal: cleanProvisions,
            closingBalanceWithProvisions: closingBalanceWithProvisions,
            minimumBalance: minimumBalance,
            minimumBalanceDate: minimumBalanceDate,
            minimumBalanceDay: minimumBalanceDay,
            alertLevel: alertLevel,
            hasIntraMonthDeficit: hasAlert,
            isTemporaryTrough: isTemporaryTrough,
            riskStartDay: firstAlertRiskStartDay,
            riskEndDay: firstAlertRiskEndDay,
            cutoffTransactionId: firstAlertCutoffId,
            recoveryTransactionId: firstRecoveryId,
            cutoffTransactionIds: cutoffTransactionIds,
            deepeningDeficitTransactionIds: deepeningDeficitTransactionIds,
            recoveryTransactionIds: recoveryTransactionIds,
            deficitZoneTransactionIds: deficitZoneTransactionIds,
            deficitOccasions: finalOccasions,
            alertableOccasions: alertableOccasions,
            runningBalanceByTransactionId: runningBalanceByTxId,
            dailyPoints: dailyPoints
        )
    }
}
