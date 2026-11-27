import SwiftUI

public struct InsightsCenterView: View {
    @ObservedObject public var store: FinancialDataStore

    @State private var selectedKindFilter: InsightKind? = nil
    @State private var showHistoryFeedback: Bool = false
    @State private var reviewNotes: String = ""

    public init(store: FinancialDataStore) {
        self.store = store
    }

    private var filteredInsights: [FinancialInsight] {
        store.insights.filter { item in
            if !showHistoryFeedback && item.feedback != .pending {
                return false
            }
            if let filter = selectedKindFilter, item.kind != filter {
                return false
            }
            return true
        }
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack(alignment: .center, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Central de Insights & Machine Learning")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                        Text("Detectores comportamentais contínuos, inflação pessoal, assinaturas e fechamento mensal guiado")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()

                    Button {
                        _ = store.runDailyBehavioralMLAnalysisIfNeeded(force: true)
                    } label: {
                        Label("Treinar & Analisar Agora", systemImage: "brain.filled.head.profile")
                    }
                    .buttonStyle(BentoPrimaryButtonStyle(color: FinSenseTheme.indigo))
                }

                // Painel do Motor ML
                mlHealthBar

                // Fechamento Mensal Guiado (Monthly Review)
                if let pendingReview = store.monthlyReviews.first(where: { !$0.isCompleted }) {
                    monthlyReviewCard(pendingReview, isEditable: true)
                }

                // Filtros dos Insights
                HStack(spacing: 10) {
                    Picker("Detector", selection: $selectedKindFilter) {
                        Text("Todos os Detectores").tag(InsightKind?.none)
                        ForEach(InsightKind.allCases) { kind in
                            Text(kind.rawValue).tag(InsightKind?.some(kind))
                        }
                    }
                    .frame(width: 240)

                    Toggle("Exibir já avaliados/dispensados", isOn: $showHistoryFeedback)
                        .toggleStyle(.checkbox)

                    Spacer()

                    Text("\(filteredInsights.count) insight(s)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if filteredInsights.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "sparkles.rectangle.stack")
                            .font(.system(size: 40))
                            .foregroundStyle(Color(hex: "#6366F1"))
                        Text("Nenhum insight pendente no momento")
                            .font(.headline)
                        Text("O motor de ML comportamental analisa suas transações diariamente para identificar inflação pessoal, reajustes de assinaturas e desvios.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 520)
                    }
                    .frame(maxWidth: .infinity, minHeight: 200)
                    .bentoCard(padding: 20)
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(filteredInsights) { insight in
                            insightCard(insight)
                        }
                    }
                }

                // Histórico de Revisões Mensais Concluídas
                let completedReviews = store.monthlyReviews.filter(\.isCompleted)
                if !completedReviews.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Histórico de Fechamentos Mensais")
                            .font(.headline)
                        ForEach(completedReviews) { rev in
                            monthlyReviewCard(rev, isEditable: false)
                        }
                    }
                }
            }
            .padding(24)
        }
        .onAppear {
            _ = store.runDailyBehavioralMLAnalysisIfNeeded(force: false)
        }
    }

    private var mlHealthBar: some View {
        let profile = store.mlBehavioralProfile
        return Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                MetricCardView(
                    title: "Último Treino ML",
                    value: profile.lastTrainedAt.map { BRLFormatters.dateTime($0) } ?? "Aguardando",
                    subtitle: "Ciclos (épocas): \(profile.trainingEpochCount) • Aprendizado diário",
                    icon: "cpu.fill",
                    tint: Color(hex: "#6366F1")
                )
                .frame(maxWidth: .infinity)

                MetricCardView(
                    title: "Base Analisada pelo Modelo",
                    value: "\(profile.analyzedTransactionsCount) transações",
                    subtitle: "\(profile.categoryStats.count) categoria(s) modeladas (EWMA + Tendência)",
                    icon: "chart.xyaxis.line",
                    tint: Color(hex: "#0EA5E9")
                )
                .frame(maxWidth: .infinity)

                MetricCardView(
                    title: "Calibração via Feedback",
                    value: "\(profile.usefulFeedbackCount) úteis",
                    subtitle: "\(profile.ignoredFeedbackCount) ignorados • \(profile.dismissedFeedbackCount) dispensados",
                    icon: "hand.thumbsup.fill",
                    tint: Color(hex: "#10B981")
                )
                .frame(maxWidth: .infinity)

                MetricCardView(
                    title: "Sensibilidade Atual",
                    value: String(format: "Z ≥ %.1f", profile.anomalyZThreshold),
                    subtitle: String(format: "Reajuste ≥ %.1f%% • Inflação x%.2f", profile.subscriptionDriftThresholdPercent, profile.inflationSensitivity),
                    icon: "slider.horizontal.3",
                    tint: Color(hex: "#F59E0B")
                )
                .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private func insightCard(_ insight: FinancialInsight) -> some View {
        let sevColor = Color(hex: insight.severity.colorHex)
        let kindColor = Color(hex: insight.kind.colorHex)

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                CategoryBadgeView(symbol: insight.kind.iconSymbol, colorHex: insight.kind.colorHex, size: 38)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(insight.kind.rawValue)
                            .font(.caption2.bold())
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(kindColor.opacity(0.15)))
                            .foregroundStyle(kindColor)

                        Text(insight.severity.title)
                            .font(.caption2.bold())
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(sevColor.opacity(0.15)))
                            .foregroundStyle(sevColor)

                        Text("Confiança \(Int(round(insight.confidenceScore * 100)))%")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Text(insight.title)
                        .font(.headline)

                    Text(insight.message)
                        .font(.subheadline)
                        .foregroundStyle(.primary)

                    Text("Recomendação: \(insight.recommendation)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color(hex: "#0284C7"))
                }

                Spacer()

                if insight.impactAmount > 0.01 {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Impacto Estimado")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(BRLFormatters.currency(insight.impactAmount))
                            .font(.subheadline.bold().monospacedDigit())
                            .foregroundStyle(sevColor)
                    }
                }
            }

            Divider()

            HStack(spacing: 10) {
                if insight.feedback == .pending {
                    Button {
                        store.submitInsightFeedback(.useful, forInsightId: insight.id)
                    } label: {
                        Label("Útil", systemImage: "hand.thumbsup.fill")
                    }
                    .buttonStyle(BentoPrimaryButtonStyle(color: FinSenseTheme.emerald, cornerRadius: 8, verticalPadding: 4.5, horizontalPadding: 10))

                    Button {
                        store.submitInsightFeedback(.ignored, forInsightId: insight.id)
                    } label: {
                        Label("Ignorar", systemImage: "eye.slash")
                    }
                    .buttonStyle(BentoGlassButtonStyle(cornerRadius: 8, verticalPadding: 4.5, horizontalPadding: 10))

                    Button {
                        store.submitInsightFeedback(.dismissed, forInsightId: insight.id)
                    } label: {
                        Label("Dispensar", systemImage: "xmark")
                    }
                    .buttonStyle(BentoGlassButtonStyle(cornerRadius: 8, verticalPadding: 4.5, horizontalPadding: 10))
                } else {
                    Text("Feedback registrado: \(insight.feedback.title)")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
        }
        .bentoCard(
            padding: 16,
            cornerRadius: 15,
            accent: insight.feedback == .pending ? sevColor : nil,
            isHighlighted: insight.feedback == .pending
        )
    }

    @ViewBuilder
    private func monthlyReviewCard(_ review: MonthlyReviewRecord, isEditable: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: review.isCompleted ? "checkmark.seal.fill" : "checklist.checked")
                    .foregroundStyle(review.isCompleted ? Color(hex: "#10B981") : Color(hex: "#6366F1"))
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Fechamento Mensal Guiado — \(String(format: "%02d/%d", review.month, review.year))")
                        .font(.headline)
                    Text(review.isCompleted ? "Revisão concluída" : "Resumo automático do mês anterior para conferência e ajustes")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if review.pendingAmortizationsCount > 0 && isEditable {
                    Button("Ver Amortizações Pendentes") {
                        store.selectedDestination = .loans
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            HStack(spacing: 16) {
                reviewMetricBox("Receitas (Prev. vs Real)", primary: BRLFormatters.currency(review.realizedIncome), secondary: "Previsto: \(BRLFormatters.currency(review.plannedIncome))")
                reviewMetricBox("Despesas (Prev. vs Real)", primary: BRLFormatters.currency(review.realizedExpense), secondary: "Previsto: \(BRLFormatters.currency(review.plannedExpense))")
                reviewMetricBox("Caixa Final Realizado", primary: BRLFormatters.currency(review.realizedEndBalance), secondary: "Evolução m/m: \(BRLFormatters.currency(review.cashEvolutionDelta))")
                reviewMetricBox("Amortizações Pendentes", primary: "\(review.pendingAmortizationsCount) item(ns)", secondary: BRLFormatters.currency(review.pendingAmortizationsAmount))
            }

            if !review.deviationHighlights.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Principais Desvios & Observações ML:")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    ForEach(review.deviationHighlights, id: \.self) { h in
                        Text("• \(h)")
                            .font(.caption)
                    }
                }
            }

            if isEditable {
                HStack(spacing: 10) {
                    TextField("Anotações do fechamento (opcional)...", text: $reviewNotes)
                        .textFieldStyle(.roundedBorder)
                    Button {
                        store.markMonthlyReviewCompleted(reviewId: review.id, notes: reviewNotes.isEmpty ? nil : reviewNotes)
                        reviewNotes = ""
                    } label: {
                        Label("Concluir Fechamento", systemImage: "checkmark.circle.fill")
                    }
                    .buttonStyle(BentoPrimaryButtonStyle(color: FinSenseTheme.emerald))
                }
            } else if !review.notes.isEmpty {
                Text("Notas: \(review.notes)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .bentoCard(
            padding: 16,
            cornerRadius: 15,
            accent: isEditable ? FinSenseTheme.indigo : FinSenseTheme.emerald,
            isHighlighted: isEditable
        )
    }

    @ViewBuilder
    private func reviewMetricBox(_ title: String, primary: String, secondary: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(primary)
                .font(.subheadline.bold().monospacedDigit())
            Text(secondary)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .bentoCard(padding: 10, cornerRadius: 10)
    }
}
