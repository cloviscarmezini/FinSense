import Foundation

/// Motor de Machine Learning Comportamental Contínuo (On-Device).
/// Treina diariamente sobre o histórico real do usuário, calcula regressões de tendência,
/// agrupamento de recorrências e curva de consumo por dia do mês, ajustando pesos com feedback.
public enum BehavioralMLInsightsEngine {

    public struct TrainingOutput {
        public let updatedProfile: MLBehavioralProfile
        public let generatedInsights: [FinancialInsight]
        public let monthlyReview: MonthlyReviewRecord?
    }

    @MainActor
    public static func trainAndDetect(
        store: FinancialDataStore,
        referenceDate: Date? = nil,
        forceRun: Bool = false
    ) -> TrainingOutput {
        let now = referenceDate ?? store.effectiveCurrentDate
        let calendar = store.calendar
        var profile = store.mlBehavioralProfile

        if !forceRun, let last = profile.lastTrainedAt, calendar.isDate(last, inSameDayAs: now) {
            return TrainingOutput(updatedProfile: profile, generatedInsights: [], monthlyReview: nil)
        }

        let activeTxs = store.transactions.filter { tx in
            !tx.ignoreInConsolidated &&
            !tx.isCreditCardInvoicePayment &&
            tx.isCanceledRecurringSeries != true
        }

        let expenses = activeTxs.filter { $0.type == .expense }
        let currentComps = calendar.dateComponents([.year, .month, .day], from: now)
        let curYear = currentComps.year ?? 2026
        let curMonth = currentComps.month ?? 1
        let curDay = max(1, min(31, currentComps.day ?? 15))
        let currentYMKey = curYear * 100 + curMonth

        // 1. Aprender curva acumulada de gasto por dia do mês (dias 1...31) a partir de meses anteriores
        let learnedCurve = learnDayOfMonthSpendCurve(expenses: expenses, currentYMKey: currentYMKey, calendar: calendar)
        profile.dayOfMonthSpendCurve = learnedCurve

        // 2. Estatísticas e regressão linear por categoria (EWMA, slope, média, mediana e MAD)
        let catStats = computeCategoryStats(
            expenses: expenses,
            categories: store.categories,
            currentYMKey: currentYMKey,
            calendar: calendar,
            amountProvider: { store.effectiveTransactionAmount(for: $0) }
        )
        profile.categoryStats = catStats

        var insights: [FinancialInsight] = []

        // 3. Detector Proativo 1: Inflação Pessoal
        insights.append(contentsOf: detectPersonalInflation(
            expenses: expenses,
            catStats: catStats,
            profile: profile,
            currentYMKey: currentYMKey,
            calendar: calendar,
            amountProvider: { store.effectiveTransactionAmount(for: $0) }
        ))

        // 4. Detector Proativo 2: Assinaturas Reajustadas ou Esquecidas
        insights.append(contentsOf: detectSubscriptionDriftsAndForgotten(
            expenses: expenses,
            profile: profile,
            currentYMKey: currentYMKey,
            now: now,
            calendar: calendar,
            amountProvider: { store.effectiveTransactionAmount(for: $0) }
        ))

        // 5. Detector Proativo 3: Anomalias de Consumo (Curva do Mês + MAD/Z-Score)
        insights.append(contentsOf: detectConsumptionAnomalies(
            expenses: expenses,
            catStats: catStats,
            profile: profile,
            currentYMKey: currentYMKey,
            curDay: curDay,
            calendar: calendar,
            amountProvider: { store.effectiveTransactionAmount(for: $0) }
        ))

        // 6. Detector Contextual 4: Descasamento de Caixa Intramês (mês atual + próximos 2 meses futuros)
        for monthOffset in 0...2 {
            guard let targetMonth = calendar.date(byAdding: .month, value: monthOffset, to: now) else { continue }
            let mComps = calendar.dateComponents([.year, .month], from: targetMonth)
            let mYMKey = (mComps.year ?? curYear) * 100 + (mComps.month ?? curMonth)
            let intra = store.buildIntraMonthCashFlowAnalysis(for: targetMonth, referenceNow: now)
            let monthLabel = BRLFormatters.monthYear(targetMonth)

            switch intra.alertLevel {
            case .confirmedDeficit:
                let fingerprint = "cash_mismatch_critical_\(mYMKey)"
                let alertBody = intra.alertSummaryText ?? "Saldo acumulado ficará negativo."
                let title = intra.isTemporaryTrough
                    ? "Vale de caixa intramês em \(monthLabel)"
                    : "Falta de caixa confirmada em \(monthLabel)"
                insights.append(
                    FinancialInsight(
                        fingerprint: fingerprint,
                        kind: .cashMismatchRisk,
                        severity: .critical,
                        title: title,
                        message: "\(alertBody). Menor saldo acumulado por transações: \(BRLFormatters.currency(intra.minimumBalance)) (abertura: \(BRLFormatters.currency(intra.openingBalance)) • fechamento sem previsões: \(BRLFormatters.currency(intra.closingBalance))).",
                        recommendation: "Antecipe uma receita ou reprograme o vencimento da despesa na linha de corte antes das datas em déficit.",
                        impactAmount: intra.shortfallAmount,
                        confidenceScore: 0.97,
                        yearMonthKey: mYMKey
                    )
                )
            case .possibleRisk:
                let fingerprint = "cash_mismatch_possible_\(mYMKey)"
                let shortfallWithProv = max(0.0, -intra.closingBalanceWithProvisions)
                insights.append(
                    FinancialInsight(
                        fingerprint: fingerprint,
                        kind: .cashMismatchRisk,
                        severity: .warning,
                        title: "Possibilidade de caixa negativo em \(monthLabel)",
                        message: "As transações agendadas mantêm o saldo positivo (\(BRLFormatters.currency(intra.closingBalance))), porém as previsões de gastos (\(BRLFormatters.currency(intra.currentMonthProvisionsTotal))) podem levar o caixa final para \(BRLFormatters.currency(intra.closingBalanceWithProvisions)).",
                        recommendation: "Monitore o consumo das categorias provisionadas neste mês para evitar déficit de até \(BRLFormatters.currency(shortfallWithProv)).",
                        impactAmount: shortfallWithProv,
                        confidenceScore: 0.78,
                        yearMonthKey: mYMKey
                    )
                )
            case .none:
                break
            }
        }

        // 7. Fechamento Mensal Guiado (mês anterior)
        let prevMonthReview = buildPreviousMonthReviewIfNeeded(
            store: store,
            now: now,
            mlInsights: insights
        )

        profile.lastTrainedAt = now
        profile.trainingEpochCount += 1
        profile.analyzedTransactionsCount = activeTxs.count
        profile.updatedAt = now

        return TrainingOutput(updatedProfile: profile, generatedInsights: insights, monthlyReview: prevMonthReview)
    }

    // MARK: - Feedback Loop (Aprendizado Contínuo)

    public static func applyFeedback(
        _ feedback: InsightFeedback,
        insight: FinancialInsight,
        to profile: inout MLBehavioralProfile
    ) {
        let catKey = insight.relatedCategoryId?.uuidString
        let now = Date()
        profile.updatedAt = now

        switch feedback {
        case .useful:
            profile.usefulFeedbackCount += 1
            if let catKey {
                let current = profile.categoryWeightAdjustments[catKey] ?? 1.0
                profile.categoryWeightAdjustments[catKey] = min(1.5, current + 0.08)
            }
            switch insight.kind {
            case .personalInflation:
                profile.inflationSensitivity = min(1.4, profile.inflationSensitivity + 0.05)
            case .consumptionAnomaly:
                profile.anomalyZThreshold = max(1.6, profile.anomalyZThreshold - 0.1)
            case .subscriptionDriftOrForgotten:
                profile.subscriptionDriftThresholdPercent = max(1.0, profile.subscriptionDriftThresholdPercent - 0.3)
            default:
                break
            }
        case .ignored, .dismissed:
            if feedback == .ignored { profile.ignoredFeedbackCount += 1 }
            else { profile.dismissedFeedbackCount += 1 }

            if let catKey {
                let current = profile.categoryWeightAdjustments[catKey] ?? 1.0
                profile.categoryWeightAdjustments[catKey] = max(0.5, current - 0.12)
            }
            switch insight.kind {
            case .personalInflation:
                profile.inflationSensitivity = max(0.65, profile.inflationSensitivity - 0.08)
            case .consumptionAnomaly:
                profile.anomalyZThreshold = min(3.5, profile.anomalyZThreshold + 0.2)
            case .subscriptionDriftOrForgotten:
                profile.subscriptionDriftThresholdPercent = min(15.0, profile.subscriptionDriftThresholdPercent + 1.0)
            default:
                break
            }
        case .pending:
            break
        }
    }

    // MARK: - Pipeline ML Helpers

    private static func yearMonthKey(from date: Date, calendar: Calendar) -> Int {
        let c = calendar.dateComponents([.year, .month], from: date)
        return (c.year ?? 2026) * 100 + (c.month ?? 1)
    }

    private static func learnDayOfMonthSpendCurve(
        expenses: [FinancialTransaction],
        currentYMKey: Int,
        calendar: Calendar
    ) -> [Double] {
        var totalsByDay = Array(repeating: 0.0, count: 31)
        var grandTotal = 0.0

        for tx in expenses {
            let ym = yearMonthKey(from: tx.date, calendar: calendar)
            guard ym < currentYMKey else { continue }
            let day = max(1, min(31, calendar.component(.day, from: tx.date)))
            totalsByDay[day - 1] += tx.amount
            grandTotal += tx.amount
        }

        guard grandTotal > 10.0 else {
            return Array(1...31).map { Double($0) / 31.0 }
        }

        var cumulative = Array(repeating: 0.0, count: 31)
        var running = 0.0
        for d in 0..<31 {
            running += totalsByDay[d]
            cumulative[d] = min(1.0, running / grandTotal)
        }
        return cumulative
    }

    private static func computeCategoryStats(
        expenses: [FinancialTransaction],
        categories: [CategoryItem],
        currentYMKey: Int,
        calendar: Calendar,
        amountProvider: (FinancialTransaction) -> Double
    ) -> [String: CategoryMLStats] {
        let catNames = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0.name) })
        var byCategory: [UUID: [FinancialTransaction]] = [:]
        for tx in expenses {
            byCategory[tx.categoryId, default: []].append(tx)
        }

        var result: [String: CategoryMLStats] = [:]
        for (catId, txs) in byCategory {
            let historicalTxs = txs.filter { yearMonthKey(from: $0.date, calendar: calendar) < currentYMKey }
            let sourceTxs = historicalTxs.isEmpty ? txs : historicalTxs
            let amounts = sourceTxs.map { amountProvider($0) }.filter { $0 > 0 }
            guard !amounts.isEmpty else { continue }

            // Agrupamento mensal ordenado cronologicamente
            var monthlyMap: [Int: Double] = [:]
            for tx in historicalTxs {
                let ym = yearMonthKey(from: tx.date, calendar: calendar)
                monthlyMap[ym, default: 0.0] += amountProvider(tx)
            }
            let sortedMonths = monthlyMap.keys.sorted()
            let monthlyValues = sortedMonths.compactMap { monthlyMap[$0] }

            // EWMA (alpha = 0.35)
            var ewma = monthlyValues.first ?? amounts.reduce(0.0, +)
            for v in monthlyValues.dropFirst() {
                ewma = 0.35 * v + 0.65 * ewma
            }

            let monthlyMean = monthlyValues.isEmpty ? ewma : (monthlyValues.reduce(0.0, +) / Double(monthlyValues.count))
            let monthlyVar = monthlyValues.count > 1
                ? monthlyValues.reduce(0.0) { $0 + pow($1 - monthlyMean, 2) } / Double(monthlyValues.count - 1)
                : 0.0
            let monthlyStd = sqrt(monthlyVar)
            let slope = linearRegressionSlope(monthlyValues)

            let sortedAmounts = amounts.sorted()
            let median = sortedAmounts[sortedAmounts.count / 2]
            let avg = amounts.reduce(0.0, +) / Double(amounts.count)
            let absDevs = sortedAmounts.map { abs($0 - median) }.sorted()
            let mad = absDevs[absDevs.count / 2]

            result[catId.uuidString] = CategoryMLStats(
                categoryId: catId,
                categoryName: catNames[catId] ?? "Categoria",
                ewmaMonthlySpend: ewma,
                stdDevMonthlySpend: monthlyStd,
                monthlySlope: slope,
                averageTransactionAmount: avg,
                medianTransactionAmount: median,
                madTransactionAmount: mad,
                monthsObserved: monthlyValues.count,
                sampleCount: amounts.count
            )
        }
        return result
    }

    private static func linearRegressionSlope(_ values: [Double]) -> Double {
        let n = values.count
        guard n >= 2 else { return 0.0 }
        let xMean = Double(n - 1) / 2.0
        let yMean = values.reduce(0.0, +) / Double(n)
        var num = 0.0
        var den = 0.0
        for i in 0..<n {
            let dx = Double(i) - xMean
            num += dx * (values[i] - yMean)
            den += dx * dx
        }
        return den > 1e-9 ? (num / den) : 0.0
    }

    // MARK: - Detector 1: Inflação Pessoal

    private static func detectPersonalInflation(
        expenses: [FinancialTransaction],
        catStats: [String: CategoryMLStats],
        profile: MLBehavioralProfile,
        currentYMKey: Int,
        calendar: Calendar,
        amountProvider: (FinancialTransaction) -> Double
    ) -> [FinancialInsight] {
        var insights: [FinancialInsight] = []

        // Agrupa gasto por categoria e mês (anteriores ao mês corrente ou incluindo corrente se já fechando)
        var monthlyByCat: [UUID: [Int: Double]] = [:]
        for tx in expenses {
            let ym = yearMonthKey(from: tx.date, calendar: calendar)
            guard ym <= currentYMKey else { continue }
            monthlyByCat[tx.categoryId, default: [:]][ym, default: 0.0] += amountProvider(tx)
        }

        let growthThresholdPct = max(8.0, 12.0 / max(0.5, profile.inflationSensitivity))

        for (catId, monthMap) in monthlyByCat {
            // Usa meses históricos fechados (< currentYMKey); se houver >= 4 meses fechados, compara últimos 3 vs anteriores
            let pastMonths = monthMap.keys.filter { $0 < currentYMKey }.sorted()
            guard pastMonths.count >= 4 else { continue }

            let recent3 = pastMonths.suffix(3).compactMap { monthMap[$0] }
            let baselineMonths = pastMonths.dropLast(3).compactMap { monthMap[$0] }
            guard !baselineMonths.isEmpty else { continue }

            let recentAvg = recent3.reduce(0.0, +) / Double(recent3.count)
            let baselineAvg = baselineMonths.reduce(0.0, +) / Double(baselineMonths.count)
            guard baselineAvg >= 80.0 else { continue }

            let pctIncrease = ((recentAvg - baselineAvg) / baselineAvg) * 100.0
            let catWeight = profile.categoryWeightAdjustments[catId.uuidString] ?? 1.0
            let catName = catStats[catId.uuidString]?.categoryName ?? "Categoria"

            if pctIncrease * catWeight >= growthThresholdPct {
                let deltaMonthly = recentAvg - baselineAvg
                let severity: InsightSeverity = pctIncrease >= 25.0 ? .critical : .warning
                let confidence = min(0.95, 0.65 + (pctIncrease / 100.0) * 0.5)

                insights.append(
                    FinancialInsight(
                        fingerprint: "inflation_\(catId.uuidString)_\(currentYMKey)",
                        kind: .personalInflation,
                        severity: severity,
                        title: "Inflação pessoal em \(catName): +\(String(format: "%.1f", pctIncrease))%",
                        message: "Nos últimos 3 meses, sua média mensal em \(catName) subiu de \(BRLFormatters.currency(baselineAvg)) para \(BRLFormatters.currency(recentAvg)) (+\(BRLFormatters.currency(deltaMonthly))/mês).",
                        recommendation: "Revise o teto mensal de \(catName) ou identifique itens recorrentes que encareceram recentemente.",
                        impactAmount: deltaMonthly,
                        confidenceScore: confidence,
                        yearMonthKey: currentYMKey,
                        relatedCategoryId: catId
                    )
                )
            }
        }
        return insights
    }

    // MARK: - Detector 2: Assinaturas Reajustadas ou Esquecidas

    private static func normalizeMerchantName(_ raw: String) -> String {
        let folded = raw.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "pt_BR"))
            .lowercased()
        let cleaned = folded.replacingOccurrences(of: #"[\d/\-\*#]+"#, with: " ", options: .regularExpression)
        return cleaned.split(separator: " ").prefix(3).joined(separator: " ")
    }

    private static func detectSubscriptionDriftsAndForgotten(
        expenses: [FinancialTransaction],
        profile: MLBehavioralProfile,
        currentYMKey: Int,
        now: Date,
        calendar: Calendar,
        amountProvider: (FinancialTransaction) -> Double
    ) -> [FinancialInsight] {
        var insights: [FinancialInsight] = []
        let thresholdPct = profile.subscriptionDriftThresholdPercent

        var groups: [String: [FinancialTransaction]] = [:]
        for tx in expenses where tx.linkedContractId == nil && !tx.isCreditCardInvoicePayment {
            let key = normalizeMerchantName(tx.name)
            guard !key.isEmpty else { continue }
            groups[key, default: []].append(tx)
        }

        for (merchantKey, txs) in groups {
            let ordered = txs.sorted { $0.date < $1.date }
            guard ordered.count >= 2 else { continue }

            // Verifica se possui cadência mensal/recorrente (pelo menos 2 meses distintos)
            let distinctMonths = Set(ordered.map { yearMonthKey(from: $0.date, calendar: calendar) })
            let isLikelySubscription = ordered.contains { $0.recurrenceMode == .recurring } || distinctMonths.count >= 2
            guard isLikelySubscription else { continue }

            // Ignora cobranças futuras muito distantes; olha histórico até fim do mês atual
            let untilCurrent = ordered.filter { yearMonthKey(from: $0.date, calendar: calendar) <= currentYMKey && $0.date <= calendar.date(byAdding: .day, value: 35, to: now) ?? now }
            guard untilCurrent.count >= 2 else { continue }

            let latest = untilCurrent[untilCurrent.count - 1]
            let previous = untilCurrent[untilCurrent.count - 2]
            let latestAmt = amountProvider(latest)
            let prevAmt = amountProvider(previous)

            // 2A. Reajuste silencioso
            if prevAmt > 5.0 && latestAmt > prevAmt + 1.0 {
                let pctDiff = ((latestAmt - prevAmt) / prevAmt) * 100.0
                if pctDiff >= thresholdPct {
                    let diff = latestAmt - prevAmt
                    insights.append(
                        FinancialInsight(
                            fingerprint: "sub_drift_\(merchantKey)_\(currentYMKey)",
                            kind: .subscriptionDriftOrForgotten,
                            severity: pctDiff >= 15.0 ? .warning : .info,
                            title: "Reajuste detectado em \"\(latest.name)\" (+\(String(format: "%.1f", pctDiff))%)",
                            message: "A cobrança recorrente subiu de \(BRLFormatters.currency(prevAmt)) para \(BRLFormatters.currency(latestAmt)) (+\(BRLFormatters.currency(diff))/ciclo, impacto anual de \(BRLFormatters.currency(diff * 12))).",
                            recommendation: "Confirme se o reajuste faz sentido ou avalie negociar/cancelar a assinatura antes da próxima renovação.",
                            impactAmount: diff * 12,
                            confidenceScore: 0.90,
                            yearMonthKey: currentYMKey,
                            relatedCategoryId: latest.categoryId,
                            relatedTransactionId: latest.id
                        )
                    )
                }
            }

            // 2B. Assinatura repetida idêntica por >= 3 meses seguidos marcada ou com keyword de assinatura que pode estar esquecida
            let isExplicitSub = latest.recurrenceMode == .recurring || containsSubscriptionKeyword(latest.name)
            if isExplicitSub && distinctMonths.count >= 3 && latestAmt >= 15.0 {
                let lastAmounts = untilCurrent.suffix(3).map { amountProvider($0) }
                let allEqual = lastAmounts.allSatisfy { abs($0 - latestAmt) < 0.50 }
                if allEqual && untilCurrent.count <= 12 {
                    let annualCost = latestAmt * 12.0
                    // Verifica se já não emitimos um alerta de drift para a mesma assinatura
                    if !insights.contains(where: { $0.fingerprint == "sub_drift_\(merchantKey)_\(currentYMKey)" }) {
                        insights.append(
                            FinancialInsight(
                                fingerprint: "sub_forgotten_\(merchantKey)_\(currentYMKey)",
                                kind: .subscriptionDriftOrForgotten,
                                severity: .info,
                                title: "Assinatura contínua: \"\(latest.name)\"",
                                message: "Cobrança automática recorrente de \(BRLFormatters.currency(latestAmt)) mantida há \(distinctMonths.count) mês(es) (\(BRLFormatters.currency(annualCost))/ano).",
                                recommendation: "Se não estiver utilizando com frequência, cancelar ou pausar gera economia anual de \(BRLFormatters.currency(annualCost)).",
                                impactAmount: annualCost,
                                confidenceScore: 0.72,
                                yearMonthKey: currentYMKey,
                                relatedCategoryId: latest.categoryId,
                                relatedTransactionId: latest.id
                            )
                        )
                    }
                }
            }
        }

        return insights
    }

    private static func containsSubscriptionKeyword(_ text: String) -> Bool {
        let norm = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "pt_BR")).lowercased()
        let keys = ["netflix", "spotify", "amazon", "prime", "disney", "max", "hbo", "icloud", "apple", "youtube", "academia", "gym", "wellhub", "totalpass", "assinatura", "clube", "mensalidade", "globoplay", "chatgpt", "openai"]
        return keys.contains { norm.contains($0) }
    }

    // MARK: - Detector 3: Anomalias de Consumo

    private static func detectConsumptionAnomalies(
        expenses: [FinancialTransaction],
        catStats: [String: CategoryMLStats],
        profile: MLBehavioralProfile,
        currentYMKey: Int,
        curDay: Int,
        calendar: Calendar,
        amountProvider: (FinancialTransaction) -> Double
    ) -> [FinancialInsight] {
        var insights: [FinancialInsight] = []
        let zLimit = profile.anomalyZThreshold
        let expectedProgressRatio = profile.dayOfMonthSpendCurve[max(0, min(30, curDay - 1))]

        let currentExpenses = expenses.filter {
            yearMonthKey(from: $0.date, calendar: calendar) == currentYMKey &&
            $0.linkedContractId == nil &&
            !$0.isCreditCardInvoicePayment
        }

        // 3A. Anomalias individuais fora da curva (MAD / Z-Score robusto)
        for tx in currentExpenses {
            guard let stats = catStats[tx.categoryId.uuidString], stats.sampleCount >= 3 else { continue }
            let amt = amountProvider(tx)
            let robustScale = max(stats.madTransactionAmount * 1.4826, stats.averageTransactionAmount * 0.25, 25.0)
            let zScore = (amt - stats.medianTransactionAmount) / robustScale
            let weight = profile.categoryWeightAdjustments[tx.categoryId.uuidString] ?? 1.0

            if zScore * weight >= zLimit && amt >= stats.medianTransactionAmount * 1.65 && amt >= 100.0 {
                insights.append(
                    FinancialInsight(
                        fingerprint: "anomaly_tx_\(tx.id.uuidString)_\(currentYMKey)",
                        kind: .consumptionAnomaly,
                        severity: zScore >= 3.2 ? .critical : .warning,
                        title: "Gasto fora do padrão em \(stats.categoryName): \"\(tx.name)\"",
                        message: "O lançamento de \(BRLFormatters.currency(amt)) está \(String(format: "%.1fx", amt / max(1.0, stats.medianTransactionAmount))) acima da sua mediana histórica nessa categoria (\(BRLFormatters.currency(stats.medianTransactionAmount))).",
                        recommendation: "Considere compensar esse pico reduzindo gastos variáveis em outras categorias até o fim do mês.",
                        impactAmount: max(0.0, amt - stats.medianTransactionAmount),
                        confidenceScore: min(0.95, 0.65 + (zScore / 6.0)),
                        yearMonthKey: currentYMKey,
                        relatedCategoryId: tx.categoryId,
                        relatedTransactionId: tx.id
                    )
                )
            }
        }

        // 3B. Ritmo mensal acelerado antes do fechamento (curva aprendida por dia do mês)
        var currentSpendByCat: [UUID: Double] = [:]
        for tx in currentExpenses where tx.isPaid || tx.isCreditCardExpense {
            currentSpendByCat[tx.categoryId, default: 0.0] += amountProvider(tx)
        }

        if expectedProgressRatio >= 0.15 {
            for (catId, currentSpent) in currentSpendByCat {
                guard let stats = catStats[catId.uuidString],
                      stats.monthsObserved >= 2,
                      stats.ewmaMonthlySpend >= 150.0 else { continue }

                let expectedByToday = stats.ewmaMonthlySpend * expectedProgressRatio
                let projectedMonthClose = currentSpent / max(0.15, expectedProgressRatio)

                if currentSpent > expectedByToday * 1.45 && projectedMonthClose > stats.ewmaMonthlySpend * 1.30 {
                    let excessProjected = projectedMonthClose - stats.ewmaMonthlySpend
                    guard excessProjected >= 100.0 else { continue }
                    insights.append(
                        FinancialInsight(
                            fingerprint: "pace_anomaly_\(catId.uuidString)_\(currentYMKey)",
                            kind: .consumptionAnomaly,
                            severity: .warning,
                            title: "Ritmo acelerado em \(stats.categoryName)",
                            message: "Até o dia \(curDay), você já gastou \(BRLFormatters.currency(currentSpent)) (esperado para esta altura do mês: \(BRLFormatters.currency(expectedByToday))). Projeção de fechamento: \(BRLFormatters.currency(projectedMonthClose)).",
                            recommendation: "Segure novos gastos nessa categoria para encerrar o mês dentro da média (\(BRLFormatters.currency(stats.ewmaMonthlySpend))).",
                            impactAmount: excessProjected,
                            confidenceScore: 0.82,
                            yearMonthKey: currentYMKey,
                            relatedCategoryId: catId
                        )
                    )
                }
            }
        }

        return insights
    }

    // MARK: - Fechamento Mensal Guiado (Mês Anterior)

    @MainActor
    public static func buildPreviousMonthReviewIfNeeded(
        store: FinancialDataStore,
        now: Date,
        mlInsights: [FinancialInsight]
    ) -> MonthlyReviewRecord? {
        let calendar = store.calendar
        guard let prevMonthDate = calendar.date(byAdding: .month, value: -1, to: store.startOfMonth(for: now)),
              let twoMonthsAgoDate = calendar.date(byAdding: .month, value: -2, to: store.startOfMonth(for: now)) else {
            return nil
        }

        let comps = calendar.dateComponents([.year, .month], from: prevMonthDate)
        let prevYear = comps.year ?? 2026
        let prevMonth = comps.month ?? 1
        let prevYMKey = prevYear * 100 + prevMonth

        // Só gera se houver transações no mês anterior e se não existir revisão concluída ou recente para aquele mês
        let prevTxs = store.transactionsForMonth(prevMonthDate).filter { !$0.ignoreInConsolidated }
        guard !prevTxs.isEmpty else { return nil }

        let plannedIncome = prevTxs.filter { $0.type == .income }.reduce(0.0) { $0 + store.effectiveTransactionAmount(for: $1) }
        let realizedIncome = prevTxs.filter { $0.type == .income && $0.isPaid }.reduce(0.0) { $0 + store.effectiveTransactionAmount(for: $1) }

        let prevExpenseTxs = prevTxs.filter { $0.type == .expense && !$0.isCreditCardInvoicePayment }
        let plannedExpense = prevExpenseTxs.reduce(0.0) { $0 + store.effectiveTransactionAmount(for: $1) }
            + store.totalEstimatedProvision(for: prevMonthDate)
        let realizedExpense = prevExpenseTxs.filter { $0.isPaid || $0.isCreditCardExpense }.reduce(0.0) { $0 + store.effectiveTransactionAmount(for: $1) }

        let realizedEndBalance = store.accumulatedConsolidatedBalance(throughMonth: prevMonthDate, includeProjectedUnpaid: false)
        let plannedEndBalance = store.accumulatedConsolidatedBalance(throughMonth: prevMonthDate, includeProjectedUnpaid: true)
        let twoMonthsEndBalance = store.accumulatedConsolidatedBalance(throughMonth: twoMonthsAgoDate, includeProjectedUnpaid: false)

        // Amortizações planejadas pendentes do mês anterior
        let prevMonthEnd = store.endOfMonth(for: prevMonthDate)
        let pendingAmortItems = store.amortizationPlans.flatMap(\.items).filter { item in
            item.status == .pending && item.date <= prevMonthEnd
        }
        let pendingCount = pendingAmortItems.count
        let pendingAmount = pendingAmortItems.reduce(0.0) { $0 + $1.amountDouble }

        var highlights: [String] = []
        let expenseDiff = realizedExpense - plannedExpense
        if abs(expenseDiff) > 50 {
            if expenseDiff > 0 {
                highlights.append("Despesas realizadas ficaram \(BRLFormatters.currency(expenseDiff)) acima do planejado.")
            } else {
                highlights.append("Economia de \(BRLFormatters.currency(abs(expenseDiff))) abaixo do orçamento planejado.")
            }
        }
        if pendingCount > 0 {
            highlights.append("\(pendingCount) amortização(ões) planejada(s) pendente(s) de confirmação (\(BRLFormatters.currency(pendingAmount))).")
        }
        for topML in mlInsights.prefix(3) {
            highlights.append(topML.title)
        }

        if let existing = store.monthlyReviews.first(where: { $0.yearMonthKey == prevYMKey }) {
            if existing.isCompleted {
                return existing
            }
            var updated = existing
            updated.plannedIncome = plannedIncome
            updated.realizedIncome = realizedIncome
            updated.plannedExpense = plannedExpense
            updated.realizedExpense = realizedExpense
            updated.plannedEndBalance = plannedEndBalance
            updated.realizedEndBalance = realizedEndBalance
            updated.previousMonthEndBalance = twoMonthsEndBalance
            updated.pendingAmortizationsCount = pendingCount
            updated.pendingAmortizationsAmount = pendingAmount
            updated.deviationHighlights = highlights
            updated.updatedAt = now
            return updated
        }

        return MonthlyReviewRecord(
            year: prevYear,
            month: prevMonth,
            plannedIncome: plannedIncome,
            realizedIncome: realizedIncome,
            plannedExpense: plannedExpense,
            realizedExpense: realizedExpense,
            plannedEndBalance: plannedEndBalance,
            realizedEndBalance: realizedEndBalance,
            previousMonthEndBalance: twoMonthsEndBalance,
            pendingAmortizationsCount: pendingCount,
            pendingAmortizationsAmount: pendingAmount,
            deviationHighlights: highlights,
            isCompleted: false,
            createdAt: now,
            updatedAt: now
        )
    }
}
