import Foundation

// MARK: - FinancialDataStore Extensions for IntraMonth Analysis, Sinking Funds, What-If & ML Insights

extension FinancialDataStore {

    // MARK: - 1. Análise Cronológica de Fluxo de Caixa Intramês (Vale de Caixa)

    public func buildIntraMonthCashFlowAnalysis(for monthReference: Date) -> IntraMonthCashFlowAnalysis {
        let comps = calendar.dateComponents([.year, .month], from: monthReference)
        let ymKey = (comps.year ?? 2026) * 100 + (comps.month ?? 1)
        if let cached = cachedIntraMonthAnalysisByYM[ymKey] {
            return cached
        }

        let isClosed = isMonthPriorToCurrent(monthReference, referenceNow: effectiveCurrentDate)
        let result = IntraMonthCashFlowEngine.analyze(
            monthReference: monthReference,
            accounts: accounts,
            investments: investments,
            transactions: transactions,
            isClosedMonth: isClosed,
            calendar: calendar,
            isVisible: { [weak self] tx in
                self?.isTransactionVisibleInCurrentScenario(tx) ?? true
            },
            effectiveSignedAmount: { [weak self] tx in
                self?.effectiveSignedTransactionAmount(for: tx) ?? tx.signedAmount
            }
        )
        cachedIntraMonthAnalysisByYM[ymKey] = result
        return result
    }

    // MARK: - 2. Sinking Funds (Caixinhas de Provisão Anuais)

    public var totalMonthlySinkingFundContribution: Double {
        sinkingFunds
            .filter(\.isEnabled)
            .reduce(0.0) { $0 + DecisionAndScenarioEngine.monthlyReserveContribution(for: $1) }
    }

    public func totalMonthlySinkingFundContribution(for monthReference: Date) -> Double {
        if isMonthPriorToCurrent(monthReference) {
            return 0.0
        }
        return totalMonthlySinkingFundContribution
    }

    public func addSinkingFund(_ fund: SinkingFund) {
        var item = fund
        item.updatedAt = Date()
        sinkingFunds.append(item)
        save()
        cloudSyncService?.recordLocalMutation(entityName: "sinking_funds", entityId: item.id, operation: .insert, entity: item)
    }

    public func updateSinkingFund(_ fund: SinkingFund) {
        var item = fund
        item.updatedAt = Date()
        if let idx = sinkingFunds.firstIndex(where: { $0.id == item.id }) {
            sinkingFunds[idx] = item
        } else {
            sinkingFunds.append(item)
        }
        save()
        cloudSyncService?.recordLocalMutation(entityName: "sinking_funds", entityId: item.id, operation: .update, entity: item)
    }

    public func addReserveDeposit(toSinkingFundId id: UUID, amount: Double) {
        guard amount > 0, let idx = sinkingFunds.firstIndex(where: { $0.id == id }) else { return }
        sinkingFunds[idx].accumulatedReserve = min(
            sinkingFunds[idx].targetAmount,
            sinkingFunds[idx].accumulatedReserve + amount
        )
        sinkingFunds[idx].updatedAt = Date()
        let updated = sinkingFunds[idx]
        save()
        cloudSyncService?.recordLocalMutation(entityName: "sinking_funds", entityId: updated.id, operation: .update, entity: updated)
    }

    public func deleteSinkingFund(_ id: UUID) {
        sinkingFunds.removeAll { $0.id == id }
        save()
        cloudSyncService?.recordLocalMutation(entityName: "sinking_funds", entityId: id, operation: .delete)
    }

    // MARK: - 3. Cenários E se? (What-If)

    public func saveWhatIfScenario(_ scenario: WhatIfScenario) {
        var item = scenario
        item.updatedAt = Date()
        let op: SyncOperation
        if let idx = whatIfScenarios.firstIndex(where: { $0.id == item.id }) {
            whatIfScenarios[idx] = item
            op = .update
        } else {
            whatIfScenarios.append(item)
            op = .insert
        }
        save()
        cloudSyncService?.recordLocalMutation(entityName: "what_if_scenarios", entityId: item.id, operation: op, entity: item)
    }

    public func deleteWhatIfScenario(_ id: UUID) {
        whatIfScenarios.removeAll { $0.id == id }
        save()
        cloudSyncService?.recordLocalMutation(entityName: "what_if_scenarios", entityId: id, operation: .delete)
    }

    // MARK: - 4. Central de Insights & Motor ML Comportamental

    public var activeUnreviewedInsightsCount: Int {
        let pendingInsights = insights.filter { $0.feedback == .pending }.count
        let pendingReviews = monthlyReviews.filter { !$0.isCompleted }.count
        return pendingInsights + pendingReviews
    }

    @discardableResult
    public func runDailyBehavioralMLAnalysisIfNeeded(force: Bool = false, referenceDate: Date? = nil) -> [FinancialInsight] {
        let output = BehavioralMLInsightsEngine.trainAndDetect(
            store: self,
            referenceDate: referenceDate,
            forceRun: force
        )
        guard force || output.updatedProfile.lastTrainedAt != nil && output.updatedProfile.trainingEpochCount > mlBehavioralProfile.trainingEpochCount else {
            return []
        }

        mlBehavioralProfile = output.updatedProfile

        var newlyAdded: [FinancialInsight] = []
        for candidate in output.generatedInsights {
            if let existingIdx = insights.firstIndex(where: { $0.fingerprint == candidate.fingerprint }) {
                // Atualiza mensagem/impacto se o feedback ainda estiver pendente
                if insights[existingIdx].feedback == .pending {
                    insights[existingIdx].title = candidate.title
                    insights[existingIdx].message = candidate.message
                    insights[existingIdx].recommendation = candidate.recommendation
                    insights[existingIdx].impactAmount = candidate.impactAmount
                    insights[existingIdx].confidenceScore = candidate.confidenceScore
                    insights[existingIdx].severity = candidate.severity
                    insights[existingIdx].updatedAt = Date()
                    cloudSyncService?.recordLocalMutation(
                        entityName: "financial_insights",
                        entityId: insights[existingIdx].id,
                        operation: .update,
                        entity: insights[existingIdx]
                    )
                }
            } else {
                insights.insert(candidate, at: 0)
                newlyAdded.append(candidate)
                cloudSyncService?.recordLocalMutation(
                    entityName: "financial_insights",
                    entityId: candidate.id,
                    operation: .insert,
                    entity: candidate
                )
            }
        }

        if let review = output.monthlyReview {
            if let idx = monthlyReviews.firstIndex(where: { $0.yearMonthKey == review.yearMonthKey }) {
                if !monthlyReviews[idx].isCompleted {
                    monthlyReviews[idx] = review
                    cloudSyncService?.recordLocalMutation(
                        entityName: "monthly_reviews",
                        entityId: review.id,
                        operation: .update,
                        entity: review
                    )
                }
            } else {
                monthlyReviews.insert(review, at: 0)
                cloudSyncService?.recordLocalMutation(
                    entityName: "monthly_reviews",
                    entityId: review.id,
                    operation: .insert,
                    entity: review
                )
            }
        }

        cloudSyncService?.recordLocalMutation(
            entityName: "ml_behavioral_profiles",
            entityId: mlBehavioralProfile.id,
            operation: .upsert,
            entity: mlBehavioralProfile
        )
        save()
        return newlyAdded
    }

    public func submitInsightFeedback(_ feedback: InsightFeedback, forInsightId id: UUID) {
        guard let idx = insights.firstIndex(where: { $0.id == id }) else { return }
        insights[idx].feedback = feedback
        insights[idx].updatedAt = Date()
        let updatedInsight = insights[idx]

        BehavioralMLInsightsEngine.applyFeedback(feedback, insight: updatedInsight, to: &mlBehavioralProfile)

        save()
        cloudSyncService?.recordLocalMutation(
            entityName: "financial_insights",
            entityId: updatedInsight.id,
            operation: .update,
            entity: updatedInsight
        )
        cloudSyncService?.recordLocalMutation(
            entityName: "ml_behavioral_profiles",
            entityId: mlBehavioralProfile.id,
            operation: .upsert,
            entity: mlBehavioralProfile
        )
    }

    public func markMonthlyReviewCompleted(reviewId: UUID, notes: String? = nil) {
        guard let idx = monthlyReviews.firstIndex(where: { $0.id == reviewId }) else { return }
        monthlyReviews[idx].isCompleted = true
        monthlyReviews[idx].completedAt = Date()
        monthlyReviews[idx].updatedAt = Date()
        if let notes {
            monthlyReviews[idx].notes = notes
        }
        let updated = monthlyReviews[idx]
        save()
        cloudSyncService?.recordLocalMutation(
            entityName: "monthly_reviews",
            entityId: updated.id,
            operation: .update,
            entity: updated
        )
    }
}
