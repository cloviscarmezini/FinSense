import SwiftUI
import Charts

public struct DashboardView: View {
    @ObservedObject public var store: FinancialDataStore
    @ObservedObject public var llmService: LocalLLMService

    @State private var showCreateExpenseSheet: Bool = false
    @State private var showCreateIncomeSheet: Bool = false
    @State private var showImportStatementSheet: Bool = false
    @State private var showProvisionsSheet: Bool = false
    @State private var showAddQuotaSheet: Bool = false
    @State private var editingQuotaEnvelope: CategoryQuotaEnvelope? = nil
    @State private var redeemingQuotaEnvelope: CategoryQuotaEnvelope? = nil
    @State private var editingFreeBudgetEnvelope: CategoryProvisionEnvelope? = nil
    @State private var pendingDeleteQuotaEnvelope: CategoryQuotaEnvelope? = nil
    @State private var showDeleteQuotaScopeDialog: Bool = false
    @State private var pendingDeleteFreeBudgetEnvelope: CategoryProvisionEnvelope? = nil
    @State private var showDeleteFreeBudgetScopeDialog: Bool = false

    public init(store: FinancialDataStore, llmService: LocalLLMService) {
        self.store = store
        self.llmService = llmService
    }

    public var body: some View {
        let isAnnual = store.dashboardPeriodMode == .annual
        let yearStr = BRLFormatters.yearString(store.selectedMonth)
        let periodFullLabel = isAnnual
            ? "31/12/\(yearStr)"
            : BRLFormatters.monthYear(store.selectedMonth)

        let isPastPeriod = isAnnual
            ? (store.calendar.component(.year, from: store.selectedMonth) < store.calendar.component(.year, from: store.effectiveCurrentDate))
            : store.isMonthPriorToCurrent(store.selectedMonth)

        let periodIncome = isAnnual
            ? store.annualIncome(for: store.selectedMonth)
            : store.monthlyIncome(for: store.selectedMonth)
        let periodReceivedIncome = isAnnual
            ? store.annualReceivedIncome(for: store.selectedMonth)
            : store.monthlyReceivedIncome(for: store.selectedMonth)
        let periodPendingIncome = isAnnual
            ? store.annualPendingIncome(for: store.selectedMonth)
            : store.monthlyPendingIncome(for: store.selectedMonth)

        let periodExpense = isAnnual
            ? store.annualExpense(for: store.selectedMonth)
            : store.monthlyExpense(for: store.selectedMonth)
        let periodPaidExpense = isAnnual
            ? store.annualPaidExpense(for: store.selectedMonth)
            : store.monthlyPaidExpense(for: store.selectedMonth)
        let periodPendingExpense = isAnnual
            ? store.annualPendingExpense(for: store.selectedMonth)
            : store.monthlyPendingExpense(for: store.selectedMonth)

        let periodNet = periodIncome - periodExpense
        let savingsRate: Double? = periodIncome > 0 ? ((periodNet / periodIncome) * 100.0) : nil

        let accumulatedBalance = isAnnual
            ? store.accumulatedConsolidatedBalanceThroughYear(store.selectedMonth)
            : store.accumulatedConsolidatedBalance(throughMonth: store.selectedMonth)
        let expenseByCategory = isAnnual
            ? store.annualCategoryBreakdown(for: store.selectedMonth, type: .expense)
            : store.categoryBreakdown(for: store.selectedMonth, type: .expense)
        let cashFlowPoints = isAnnual
            ? store.annualCashFlowSeries(for: store.selectedMonth)
            : store.cashFlowSeries(around: store.selectedMonth, monthsBack: 2, monthsForward: 3)
        let debtSummary = store.buildComprehensiveDebtSummary(
            referenceDate: store.selectedMonth,
            isAnnual: isAnnual
        )
        let monthEnvelopes = store.provisionEnvelopes(for: store.selectedMonth)
        let monthQuotas = store.allQuotaEnvelopes(for: store.selectedMonth)
        let hasAnyProvisionOrQuota = !monthEnvelopes.isEmpty || !monthQuotas.isEmpty
        let remainingProvisionsTotal = isPastPeriod ? 0.0 : store.totalRemainingProvision(for: store.selectedMonth)
        let estimatedProvisionsTotal = store.totalEstimatedProvision(for: store.selectedMonth)

        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                // MARK: - Top Header Bar with Local LLM Chat Button
                HStack(alignment: .center, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Dashboard & Insights Financeiros")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                        Text(
                            isAnnual
                                ? "Projeção consolidada para o último dia do ano (31/12/\(yearStr))"
                                : "Visão consolidada de contas, categorias, investimentos, passivos e projeções"
                        )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }

                    Spacer()

                    DashboardPeriodNavigatorBar(store: store)

                    Button {
                        store.openAIChat()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "sparkles.bubble.fill")
                                .font(.system(size: 15, weight: .semibold))
                            Text("Chat IA Local")
                                .fontWeight(.semibold)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            LinearGradient(
                                colors: [Color(hex: "#6366F1"), Color(hex: "#8B5CF6")],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .shadow(color: Color(hex: "#6366F1").opacity(0.3), radius: 5, x: 0, y: 2)
                    }
                    .buttonStyle(.plain)
                    .help("Perguntar para a LLM local com acesso total à base de dados")
                }

                // Quick Actions Bar
                HStack(spacing: 10) {
                    Button {
                        showCreateExpenseSheet = true
                    } label: {
                        Label("Nova Despesa", systemImage: "minus.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(hex: "#EF4444"))

                    Button {
                        showCreateIncomeSheet = true
                    } label: {
                        Label("Nova Receita", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(hex: "#10B981"))

                    Button {
                        store.requireInstalledLLM(forFeature: "Importar Extrato PDF / Relatório com IA Local") {
                            showImportStatementSheet = true
                        }
                    } label: {
                        Label("Importar", systemImage: "doc.text.magnifyingglass")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        showProvisionsSheet = true
                    } label: {
                        Label("Previsões & Tetos do Mês", systemImage: "tray.full.fill")
                    }
                    .buttonStyle(.bordered)
                    .tint(Color(hex: "#6366F1"))
                    .help("Definir limites/previsões de gastos variáveis por categoria (Envelopes Dinâmicos)")

                    Spacer()

                    if let activeModel = store.llmConfig.selectedModel {
                        Label("LLM Ativa: \(activeModel.displayName)", systemImage: "cpu.fill")
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(Color.green.opacity(0.14)))
                            .foregroundStyle(.green)
                    } else {
                        Button {
                            store.selectedDestination = .settings
                            store.selectedSettingsSection = .llm
                        } label: {
                            Label("Configurar Modelo Hugging Face", systemImage: "cpu")
                                .font(.caption)
                        }
                        .buttonStyle(.link)
                    }
                }

                // MARK: - Top KPI Cards (4 Sequential Lifecycle Cards)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 4), spacing: 14) {
                    // Card 1 — Receitas do Mês / Ano
                    MetricCardView(
                        title: isAnnual ? "Receitas do Ano" : "Receitas do Mês",
                        value: BRLFormatters.currency(periodIncome),
                        subtitle: "\(BRLFormatters.currency(periodReceivedIncome)) recebidos • \(BRLFormatters.currency(periodPendingIncome)) a receber",
                        icon: "arrow.down.left.circle.fill",
                        tint: Color(hex: "#10B981")
                    )

                    // Card 2 — Despesas do Mês / Ano (Estritamente compromissos/transações lançadas, NUNCA somar tetos/cotas)
                    MetricCardView(
                        title: isAnnual ? "Despesas do Ano" : "Despesas do Mês",
                        value: BRLFormatters.currency(periodExpense),
                        subtitle: "\(BRLFormatters.currency(periodPaidExpense)) pagas • \(BRLFormatters.currency(periodPendingExpense)) pendentes",
                        icon: "arrow.up.right.circle.fill",
                        tint: Color(hex: "#EF4444")
                    )

                    // Card 3 — Balanço Operacional (Receitas - Despesas com Taxa de Poupança / Margem Líquida)
                    let operationalSubtitle: String = {
                        if let rate = savingsRate {
                            return rate >= 0
                                ? String(format: "%.1f%% sobre a Receita", rate)
                                : String(format: "Déficit operacional (%.1f%%)", abs(rate))
                        } else {
                            return periodNet >= 0 ? "Superávit operacional" : "Déficit operacional"
                        }
                    }()

                    MetricCardView(
                        title: "Balanço Operacional",
                        value: BRLFormatters.currency(periodNet),
                        subtitle: operationalSubtitle,
                        icon: "equal.circle.fill",
                        tint: periodNet >= 0 ? Color(hex: "#10B981") : Color(hex: "#EF4444")
                    )

                    // Card 4 — Saldo Projetado / Resultado Final
                    let finalTitle: String = {
                        if isAnnual {
                            return isPastPeriod
                                ? "Resultado Consolidado"
                                : "Saldo Previsto para 31/12/\(yearStr)"
                        } else {
                            return store.monthEndBalanceCardTitle(for: store.selectedMonth)
                        }
                    }()

                    let finalSubtitle = store.deductionSubtitleForProjectedBalance(
                        periodMode: store.dashboardPeriodMode,
                        selectedMonth: store.selectedMonth
                    )
                    let finalTooltip = store.deductionBreakdownTooltipForProjectedBalance(
                        periodMode: store.dashboardPeriodMode,
                        selectedMonth: store.selectedMonth
                    )

                    MetricCardView(
                        title: finalTitle,
                        value: BRLFormatters.currency(accumulatedBalance),
                        subtitle: finalSubtitle,
                        icon: isPastPeriod ? "checkmark.seal.fill" : "chart.line.uptrend.xyaxis",
                        tint: accumulatedBalance >= 0 ? Color(hex: "#10B981") : Color(hex: "#EF4444"),
                        footnote: (!isPastPeriod && accumulatedBalance < 0) ? "Alerta: Risco de caixa negativo" : nil,
                        footnoteColor: Color(hex: "#EF4444"),
                        subtitleHelp: finalTooltip
                    )
                }

                // MARK: - Previsões & Tetos do Mês (Divisão Visual em Dois Blocos Claros)
                if !isAnnual {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(alignment: .center, spacing: 12) {
                            HStack(spacing: 8) {
                                Image(systemName: "tray.full.fill")
                                    .foregroundStyle(Color(hex: "#6366F1"))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Previsões & Tetos do Mês")
                                        .font(.headline)
                                    Text("Cotas específicas e tetos por categoria desacoplados em \(periodFullLabel) (abatimento em tempo real)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer()

                            if hasAnyProvisionOrQuota {
                                HStack(spacing: 14) {
                                    VStack(alignment: .trailing, spacing: 1) {
                                        Text("Total Orçado")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                        Text(BRLFormatters.currency(estimatedProvisionsTotal))
                                            .font(.subheadline.weight(.semibold))
                                    }
                                    Divider().frame(height: 26)
                                    VStack(alignment: .trailing, spacing: 1) {
                                        Text("Provisão Total Futura")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                        Text("\(BRLFormatters.currency(remainingProvisionsTotal)) restantes")
                                            .font(.subheadline.bold())
                                            .foregroundStyle(Color(hex: "#6366F1"))
                                    }
                                }
                            }

                            Button {
                                showAddQuotaSheet = true
                            } label: {
                                Label("Nova Cota do Mês", systemImage: "plus.square.on.square")
                            }
                            .buttonStyle(.bordered)
                            .tint(Color(hex: "#0EA5E9"))
                            .controlSize(.small)
                            .help("Cadastrar cota de item específico (ex: Galão de Água)")

                            Button {
                                showProvisionsSheet = true
                            } label: {
                                Label(
                                    hasAnyProvisionOrQuota ? "Gerenciar Tetos & Cotas" : "Configurar Previsões",
                                    systemImage: "slider.horizontal.3"
                                )
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Color(hex: "#6366F1"))
                            .controlSize(.small)
                        }

                        if !hasAnyProvisionOrQuota {
                            HStack(spacing: 12) {
                                Image(systemName: "sparkles.rectangle.stack")
                                    .font(.system(size: 22))
                                    .foregroundStyle(Color(hex: "#6366F1").opacity(0.8))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Nenhuma cota específica ou teto de categoria configurado para \(periodFullLabel).")
                                        .font(.subheadline.weight(.medium))
                                    Text("Adicione Cotas do Mês (ex: Galão de Água) ou Orçamentos por Categoria (ex: Combustível) de forma 100% independente.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.primary.opacity(0.03))
                            )
                        } else {
                            // BLOCO 1: Cotas do Mês (Itens Específicos)
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    HStack(spacing: 6) {
                                        Image(systemName: "shippingbox.fill")
                                            .font(.caption.bold())
                                            .foregroundStyle(Color(hex: "#0EA5E9"))
                                        Text("Cotas do Mês (Itens Específicos)")
                                            .font(.subheadline.bold())
                                    }
                                    Spacer()
                                    Text("Subtotal Cotas Restantes: \(BRLFormatters.currency(store.totalQuotasRemaining(for: store.selectedMonth)))")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(Color(hex: "#0EA5E9"))
                                }

                                if monthQuotas.isEmpty {
                                    HStack {
                                        Text("Nenhuma cota de item específico cadastrada neste mês.")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        Button("Adicionar Cota Específica") {
                                            showAddQuotaSheet = true
                                        }
                                        .buttonStyle(.link)
                                        .font(.caption)
                                    }
                                    .padding(10)
                                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.025)))
                                } else {
                                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 2), spacing: 14) {
                                        ForEach(monthQuotas) { quota in
                                            quotaItemCard(quota)
                                        }
                                    }
                                }
                            }

                            Divider()

                            // BLOCO 2: Orçamentos por Categoria (Tetos Mensais)
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    HStack(spacing: 6) {
                                        Image(systemName: "chart.bar.fill")
                                            .font(.caption.bold())
                                            .foregroundStyle(Color(hex: "#6366F1"))
                                        Text("Orçamentos por Categoria (Tetos Mensais)")
                                            .font(.subheadline.bold())
                                    }
                                    Spacer()
                                    Text("Subtotal Tetos Restantes: \(BRLFormatters.currency(store.totalCategoryProvisionsRemaining(for: store.selectedMonth)))")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(Color(hex: "#6366F1"))
                                }

                                if monthEnvelopes.isEmpty {
                                    HStack {
                                        Text("Nenhuma categoria possui teto mensal aberto configurado neste mês.")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        Button("Definir Teto de Categoria") {
                                            showProvisionsSheet = true
                                        }
                                        .buttonStyle(.link)
                                        .font(.caption)
                                    }
                                    .padding(10)
                                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.025)))
                                } else {
                                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 2), spacing: 14) {
                                        ForEach(monthEnvelopes) { env in
                                            provisionEnvelopeCard(env)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(18)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.primary.opacity(0.07), lineWidth: 1)
                    )
                }

                // MARK: - Charts Section (Expense by Category + Monthly/Annual Cash Flow)
                HStack(alignment: .top, spacing: 16) {
                    // Chart 1: Gráfico de Despesa por Categoria
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Despesas por Categoria")
                                    .font(.headline)
                                Text(isAnnual ? "Distribuição projetada até \(periodFullLabel)" : "Distribuição de gastos em \(periodFullLabel)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(BRLFormatters.currency(periodExpense))
                                .font(.subheadline.bold())
                                .foregroundStyle(Color(hex: "#EF4444"))
                        }

                        if expenseByCategory.isEmpty {
                            VStack(spacing: 10) {
                                Image(systemName: "chart.pie")
                                    .font(.system(size: 36))
                                    .foregroundStyle(.secondary)
                                Text(isAnnual ? "Nenhuma despesa registrada ou projetada neste ano." : "Nenhuma despesa registrada neste mês.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, minHeight: 240)
                        } else {
                            HStack(spacing: 18) {
                                Chart(expenseByCategory) { item in
                                    SectorMark(
                                        angle: .value("Total", item.total),
                                        innerRadius: .ratio(0.58),
                                        angularInset: 1.5
                                    )
                                    .cornerRadius(4)
                                    .foregroundStyle(Color(hex: item.category.colorHex))
                                }
                                .frame(width: 190, height: 190)

                                ScrollView {
                                    VStack(alignment: .leading, spacing: 8) {
                                        ForEach(expenseByCategory) { item in
                                            HStack(spacing: 8) {
                                                Circle()
                                                    .fill(Color(hex: item.category.colorHex))
                                                    .frame(width: 10, height: 10)
                                                Image(systemName: item.category.iconSymbol)
                                                    .font(.caption)
                                                    .foregroundStyle(Color(hex: item.category.colorHex))
                                                    .frame(width: 16)
                                                Text(item.category.name)
                                                    .font(.caption)
                                                    .lineLimit(1)
                                                Spacer()
                                                Text(String(format: "%.1f%%", item.percentage))
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                                Text(BRLFormatters.currency(item.total))
                                                    .font(.caption.bold())
                                            }
                                        }
                                    }
                                }
                                .frame(maxHeight: 200)
                            }
                        }
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, minHeight: 290, alignment: .topLeading)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.primary.opacity(0.07), lineWidth: 1)
                    )

                    // Chart 2: Evolução de Receitas vs Despesas e Projeção Empilhada
                    MonthlyCashFlowChartView(
                        points: cashFlowPoints,
                        isAnnual: isAnnual,
                        yearStr: yearStr
                    )
                }

                // MARK: - Total de Dívidas e Compromissos
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.shield.fill")
                                    .foregroundStyle(Color(hex: "#EF4444"))
                                Text("Total de Dívidas e Compromissos")
                                    .font(.title3.bold())
                            }
                            Text("Detalhamento de transações pendentes atuais e futuras, dívidas em aberto (ex: Serasa/Cartões), empréstimos e financiamentos")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()

                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Total Acumulado Geral")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(BRLFormatters.currency(debtSummary.grandTotalNominal))
                                .font(.system(size: 22, weight: .heavy, design: .rounded))
                                .foregroundStyle(Color(hex: "#EF4444"))
                            if abs(debtSummary.grandTotalNominal - debtSummary.grandTotalWithPayoffProjection) > 0.01 {
                                Text("Projeção para quitar hoje: \(BRLFormatters.currency(debtSummary.grandTotalWithPayoffProjection))")
                                    .font(.caption.bold())
                                    .foregroundStyle(Color(hex: "#10B981"))
                            }
                        }
                    }

                    // 5 Pillars Breakdown
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 5), spacing: 12) {
                        debtPillarCard(
                            title: isAnnual ? "Pendentes no Ano" : "Transações Atuais",
                            subtitle: isAnnual ? "\(debtSummary.currentMonthUnpaidTransactions.count) pendente(s) em \(yearStr)" : "\(debtSummary.currentMonthUnpaidTransactions.count) pendente(s) no mês",
                            amount: debtSummary.currentMonthUnpaidTotal,
                            projected: nil,
                            colorHex: "#F59E0B",
                            icon: "calendar.badge.exclamationmark"
                        )
                        debtPillarCard(
                            title: "Transações Futuras",
                            subtitle: "\(debtSummary.futureUnpaidRegularTransactions.count) parcela(s)/agendada(s)",
                            amount: debtSummary.futureRegularExpensesTotal,
                            projected: nil,
                            colorHex: "#3B82F6",
                            icon: "clock.arrow.circlepath"
                        )
                        debtPillarCard(
                            title: "Dívidas (Acordos/Serasa)",
                            subtitle: "\(debtSummary.activeDebts.count) dívida(s) ativa(s)",
                            amount: debtSummary.unpaidDebtsTotal,
                            projected: nil,
                            colorHex: "#EF4444",
                            icon: "exclamationmark.triangle.fill"
                        )
                        debtPillarCard(
                            title: "Empréstimos",
                            subtitle: "\(debtSummary.activeLoans.count) contrato(s) ativo(s)",
                            amount: debtSummary.loansRemainingNominalTotal,
                            projected: debtSummary.loansProjectedPayoffTotal,
                            amortizedInPeriod: debtSummary.loansAmortizedInPeriodTotal,
                            colorHex: "#D97706",
                            icon: "banknote.fill"
                        )
                        debtPillarCard(
                            title: "Financiamentos",
                            subtitle: "\(debtSummary.activeFinancings.count) contrato(s) (Imóvel/Carro)",
                            amount: debtSummary.financingsRemainingNominalTotal,
                            projected: debtSummary.financingsProjectedPayoffTotal,
                            amortizedInPeriod: debtSummary.financingsAmortizedInPeriodTotal,
                            colorHex: "#8B5CF6",
                            icon: "house.and.flag.fill"
                        )
                    }
                }
                .padding(18)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.primary.opacity(0.07), lineWidth: 1)
                )

                // MARK: - Accounts & Investments Quick Overview
                HStack(alignment: .top, spacing: 16) {
                    // Accounts Card
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Saldos por Conta")
                                .font(.headline)
                            Spacer()
                            Button("Gerenciar Contas") {
                                store.selectedDestination = .settings
                                store.selectedSettingsSection = .accounts
                            }
                            .buttonStyle(.link)
                            .font(.caption)
                        }

                        if store.accounts.isEmpty {
                            Text("Nenhuma conta cadastrada. Acesse Configurações → Contas para adicionar.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(store.accounts) { account in
                                HStack(spacing: 12) {
                                    AccountAvatarView(account: account, size: 36)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(account.name)
                                            .font(.subheadline.weight(.semibold))
                                        if !account.agency.isEmpty || !account.accountNumber.isEmpty {
                                            Text("Ag: \(account.agency) • CC: \(account.accountNumber)")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    let bal = store.currentBalance(forAccount: account.id)
                                    Text(BRLFormatters.currency(bal))
                                        .font(.subheadline.bold())
                                        .foregroundStyle(bal >= 0 ? Color.primary : Color(hex: "#EF4444"))
                                }
                                .padding(8)
                                .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.03)))
                            }
                        }
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.primary.opacity(0.07), lineWidth: 1)
                    )

                    // Investments Card
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Investimentos por Grupo")
                                .font(.headline)
                            Spacer()
                            Button("Acessar Investimentos") {
                                store.selectedDestination = .investments
                            }
                            .buttonStyle(.link)
                            .font(.caption)
                        }

                        if store.investments.isEmpty {
                            Text("Nenhum investimento cadastrado.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(store.investments) { inv in
                                HStack(spacing: 12) {
                                    CategoryBadgeView(symbol: inv.iconSymbol, colorHex: inv.colorHex, size: 36)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(inv.name)
                                            .font(.subheadline.weight(.semibold))
                                        Text("Grupo: \(inv.groupName)")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Toggle("Consolidar", isOn: Binding(
                                        get: { inv.showInConsolidated },
                                        set: { _ in store.toggleInvestmentConsolidated(inv.id) }
                                    ))
                                    .toggleStyle(.switch)
                                    .controlSize(.mini)
                                    .labelsHidden()
                                    .help("Exibir no consolidado")

                                    Text(BRLFormatters.currency(inv.balance))
                                        .font(.subheadline.bold())
                                        .foregroundStyle(Color(hex: "#10B981"))
                                }
                                .padding(8)
                                .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.03)))
                            }
                        }
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.primary.opacity(0.07), lineWidth: 1)
                    )
                }
            }
            .padding(24)
        }
        .sheet(isPresented: $showCreateExpenseSheet) {
            TransactionEditorSheet(
                store: store,
                llmService: llmService,
                initialType: .expense
            )
        }
        .sheet(isPresented: $showCreateIncomeSheet) {
            TransactionEditorSheet(
                store: store,
                llmService: llmService,
                initialType: .income
            )
        }
        .sheet(isPresented: $showImportStatementSheet) {
            StatementImportSheet(
                store: store,
                llmService: llmService,
                initialFilterMode: .hybrid
            )
        }
        .sheet(isPresented: $showProvisionsSheet) {
            MonthlyProvisionsSheet(store: store)
        }
        .sheet(isPresented: $showAddQuotaSheet) {
            QuotaItemEditorSheet(store: store, existingQuota: nil)
        }
        .sheet(item: $editingQuotaEnvelope) { quotaEnv in
            QuotaItemEditorSheet(store: store, existingQuota: quotaEnv)
        }
        .sheet(item: $redeemingQuotaEnvelope) { quotaEnv in
            QuotaRedemptionSheet(store: store, quotaEnvelope: quotaEnv)
        }
        .sheet(item: $editingFreeBudgetEnvelope) { env in
            FreeBudgetEditorSheet(store: store, envelope: env)
        }
        .confirmationDialog(
            pendingDeleteQuotaEnvelope?.repeatForFutureMonths == true
                ? "Excluir Cota Recorrente: \(pendingDeleteQuotaEnvelope?.name ?? "")"
                : "Confirmar Exclusão da Cota: \(pendingDeleteQuotaEnvelope?.name ?? "")",
            isPresented: $showDeleteQuotaScopeDialog,
            titleVisibility: .visible
        ) {
            if let q = pendingDeleteQuotaEnvelope {
                if q.repeatForFutureMonths {
                    Button("Excluir somente deste mês") {
                        store.deleteCategoryQuota(
                            seriesId: q.seriesId,
                            for: store.selectedMonth,
                            scope: .onlyThisMonth
                        )
                        pendingDeleteQuotaEnvelope = nil
                    }
                    Button("Excluir todas as ocorrências", role: .destructive) {
                        store.deleteCategoryQuota(
                            seriesId: q.seriesId,
                            for: store.selectedMonth,
                            scope: .allOccurrences
                        )
                        pendingDeleteQuotaEnvelope = nil
                    }
                } else {
                    Button("Excluir deste mês", role: .destructive) {
                        store.deleteCategoryQuota(
                            seriesId: q.seriesId,
                            for: store.selectedMonth,
                            scope: .onlyThisMonth
                        )
                        pendingDeleteQuotaEnvelope = nil
                    }
                }
            }
            Button("Cancelar", role: .cancel) {
                pendingDeleteQuotaEnvelope = nil
            }
        } message: {
            if pendingDeleteQuotaEnvelope?.repeatForFutureMonths == true {
                Text("Esta cota possui recorrência ativa. Deseja removê-la apenas deste mês (mantendo nos meses anteriores e futuros) ou excluir todas as ocorrências definitivamente?")
            } else {
                Text("Deseja remover esta cota específica do mês selecionado?")
            }
        }
        .confirmationDialog(
            pendingDeleteFreeBudgetEnvelope?.provision.repeatForFutureMonths == true
                ? "Excluir Verba Livre Recorrente: \(pendingDeleteFreeBudgetEnvelope?.category.name ?? "")"
                : "Confirmar Exclusão da Verba Livre: \(pendingDeleteFreeBudgetEnvelope?.category.name ?? "")",
            isPresented: $showDeleteFreeBudgetScopeDialog,
            titleVisibility: .visible
        ) {
            if let env = pendingDeleteFreeBudgetEnvelope {
                if env.provision.repeatForFutureMonths {
                    Button("Excluir somente deste mês") {
                        store.deleteCategoryProvision(
                            categoryId: env.category.id,
                            for: store.selectedMonth,
                            scope: .onlyThisMonth
                        )
                        pendingDeleteFreeBudgetEnvelope = nil
                    }
                    Button("Excluir todas as ocorrências", role: .destructive) {
                        store.deleteCategoryProvision(
                            categoryId: env.category.id,
                            for: store.selectedMonth,
                            scope: .allOccurrences
                        )
                        pendingDeleteFreeBudgetEnvelope = nil
                    }
                } else {
                    Button("Excluir deste mês", role: .destructive) {
                        store.deleteCategoryProvision(
                            categoryId: env.category.id,
                            for: store.selectedMonth,
                            scope: .onlyThisMonth
                        )
                        pendingDeleteFreeBudgetEnvelope = nil
                    }
                }
            }
            Button("Cancelar", role: .cancel) {
                pendingDeleteFreeBudgetEnvelope = nil
            }
        } message: {
            if pendingDeleteFreeBudgetEnvelope?.provision.repeatForFutureMonths == true {
                Text("A verba livre desta categoria é recorrente. Deseja removê-la somente deste mês (mantendo nos meses anteriores e futuros) ou excluir todas as ocorrências?")
            } else {
                Text("Deseja remover a verba livre desta categoria no mês atual?")
            }
        }
    }

    @ViewBuilder
    private func quotaItemCard(_ quota: CategoryQuotaEnvelope) -> some View {
        let statusColorHex: String = {
            switch quota.status {
            case .normal: return "#0EA5E9"
            case .warning: return "#F59E0B"
            case .exceeded: return "#EF4444"
            }
        }()
        let categoryName = store.category(for: quota.categoryId)?.name ?? "Despesa"

        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color(hex: statusColorHex).opacity(0.15))
                        .frame(width: 34, height: 34)
                    Image(systemName: quota.iconSymbol)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color(hex: statusColorHex))
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text("\(quota.name): \(quota.consumedUnits) de \(quota.plannedQuantity) consumidos • \(BRLFormatters.currency(quota.remainingProvision)) restantes")
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        if quota.repeatForFutureMonths {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .help("Repetir automaticamente para os próximos meses")
                        }
                        if quota.isLocalMonthOverride {
                            Text("(Mês)")
                                .font(.system(size: 9.5, weight: .bold))
                                .foregroundStyle(Color(hex: "#F59E0B"))
                        }
                    }
                    Text("Unitário est.: \(BRLFormatters.currency(quota.estimatedUnitPrice)) • Pendentes: \(quota.pendingUnits) un. • Cat. padrão: \(categoryName)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Text(quota.status.rawValue)
                    .font(.system(size: 10.5, weight: .bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color(hex: statusColorHex).opacity(0.15)))
                    .foregroundStyle(Color(hex: statusColorHex))
            }

            // Progress Bar autônoma da cota específica (Unidades Baixadas / Quantidade Prevista)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.08))
                        .frame(height: 8)
                    Capsule()
                        .fill(Color(hex: statusColorHex).gradient)
                        .frame(
                            width: max(0, geo.size.width * CGFloat(quota.progressRatio)),
                            height: 8
                        )
                }
            }
            .frame(height: 8)

            HStack(spacing: 8) {
                Button {
                    redeemingQuotaEnvelope = quota
                } label: {
                    Label("+ Dar Baixa", systemImage: "plus.circle.fill")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(hex: "#0EA5E9"))
                .controlSize(.small)
                .help("Abrir mini-diálogo pré-preenchido para dar baixa em 1 unidade e lançar despesa real no extrato")

                Spacer()

                if quota.consumedUnits > quota.plannedQuantity {
                    Text("Acima do planejado: \(quota.consumedUnits) de \(quota.plannedQuantity) un.")
                        .font(.caption2.bold())
                        .foregroundStyle(Color(hex: "#EF4444"))
                } else {
                    Text("Total previsto: \(BRLFormatters.currency(quota.totalEstimatedAmount))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Button {
                    editingQuotaEnvelope = quota
                } label: {
                    Image(systemName: "pencil")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("Editar cota específica")

                Button(role: .destructive) {
                    pendingDeleteQuotaEnvelope = quota
                    showDeleteQuotaScopeDialog = true
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundStyle(Color(hex: "#EF4444"))
                }
                .buttonStyle(.borderless)
                .help("Excluir cota específica")
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(hex: "#0EA5E9").opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(hex: statusColorHex).opacity(0.28), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func provisionEnvelopeCard(_ env: CategoryProvisionEnvelope) -> some View {
        let statusColorHex: String = {
            switch env.status {
            case .normal: return "#10B981"
            case .warning: return "#F59E0B"
            case .exceeded: return "#EF4444"
            }
        }()

        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                CategoryBadgeView(category: env.category, size: 32)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(env.category.name)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        if env.repeatForFutureMonths {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .help("Repetir automaticamente para os próximos meses")
                        }
                        if env.isFreeBudgetLocalOverride {
                            Text("(Exceção do mês)")
                                .font(.system(size: 9.5, weight: .medium))
                                .foregroundStyle(Color(hex: "#F59E0B"))
                        }
                    }
                    Text("Teto Mensal: \(BRLFormatters.currency(env.estimatedAmount)) • Gasto Avulso: \(BRLFormatters.currency(env.realizedExpense))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Button {
                    editingFreeBudgetEnvelope = env
                } label: {
                    Image(systemName: "pencil")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("Editar Teto da Categoria")

                Button(role: .destructive) {
                    pendingDeleteFreeBudgetEnvelope = env
                    showDeleteFreeBudgetScopeDialog = true
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundStyle(Color(hex: "#EF4444"))
                }
                .buttonStyle(.borderless)
                .help("Excluir Teto da Categoria")

                Text(env.status.rawValue)
                    .font(.system(size: 10.5, weight: .bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color(hex: statusColorHex).opacity(0.15)))
                    .foregroundStyle(Color(hex: statusColorHex))
            }

            // Progress Bar do Teto Geral da Categoria (comparando exclusivamente com gastos avulsos)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.08))
                        .frame(height: 8)
                    Capsule()
                        .fill(Color(hex: statusColorHex).gradient)
                        .frame(
                            width: max(0, geo.size.width * CGFloat(env.clampedProgressPercentage / 100.0)),
                            height: 8
                        )
                }
            }
            .frame(height: 8)

            HStack {
                Text(String(format: "%.0f%% utilizado", env.clampedProgressPercentage))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Color(hex: statusColorHex))

                Spacer()

                if env.status == .exceeded && env.exceededAmount > 0 {
                    Text("Excedente: +\(BRLFormatters.currency(env.exceededAmount)) • Teto Restante: \(BRLFormatters.currency(env.remainingProvision))")
                        .font(.caption2.bold())
                        .foregroundStyle(Color(hex: "#EF4444"))
                } else {
                    Text("Teto Restante: \(BRLFormatters.currency(env.remainingProvision))")
                        .font(.caption2.bold())
                        .foregroundStyle(.primary)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(hex: statusColorHex).opacity(0.28), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func debtPillarCard(
        title: String,
        subtitle: String,
        amount: Double,
        projected: Double?,
        amortizedInPeriod: Double? = nil,
        colorHex: String,
        icon: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(Color(hex: colorHex))
                Spacer()
            }
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            Text(BRLFormatters.currency(amount))
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(Color(hex: colorHex))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .monospacedDigit()
            if let amortizedInPeriod, amortizedInPeriod > 0 {
                Text("Amortizado no período: \(BRLFormatters.currency(amortizedInPeriod))")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(hex: "#10B981"))
                    .lineLimit(1)
                    .monospacedDigit()
            }
            if let projected, abs(amount - projected) > 0.01 {
                Text("Quitar: \(BRLFormatters.currency(projected))")
                    .font(.caption2.bold())
                    .foregroundStyle(Color(hex: "#10B981"))
                    .lineLimit(1)
                    .monospacedDigit()
            } else {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(hex: colorHex).opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color(hex: colorHex).opacity(0.22), lineWidth: 1)
        )
    }
}

// MARK: - Modal: Previsões & Tetos do Mês (Verba Livre + Cotas Específicas)

public struct MonthlyProvisionsSheet: View {
    @ObservedObject public var store: FinancialDataStore
    @Environment(\.dismiss) private var dismiss

    private struct DraftProvisionItem: Identifiable {
        var id: UUID { category.id }
        let category: CategoryItem
        let realizedFreeExpense: Double
        var amountString: String
        let initialAmount: Double
        var repeatForFutureMonths: Bool
        let wasInitiallyActive: Bool
        let wasInitiallyRecurring: Bool
    }

    @State private var draftItems: [DraftProvisionItem] = []
    @State private var globalRepeatToggle: Bool = true
    @State private var addQuotaForCategory: CategoryItem? = nil
    @State private var editingQuota: CategoryQuotaEnvelope? = nil
    @State private var redeemingQuota: CategoryQuotaEnvelope? = nil
    @State private var showRecurringEditScopeDialog: Bool = false

    public init(store: FinancialDataStore) {
        self.store = store
    }

    public var body: some View {
        let monthTitle = BRLFormatters.monthYear(store.selectedMonth)

        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(hex: "#6366F1").opacity(0.15))
                        .frame(width: 40, height: 40)
                    Image(systemName: "tray.full.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color(hex: "#6366F1"))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Previsões & Tetos do Mês")
                        .font(.title3.bold())
                    Text("Configure Verbas Livres e Cotas de Itens Específicos para \(monthTitle) sem criar lançamentos fictícios")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(20)

            Divider()

            // Global Persistence Toggle Bar
            HStack(spacing: 12) {
                Toggle(isOn: $globalRepeatToggle) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .foregroundStyle(Color(hex: "#6366F1"))
                        Text("Repetir previsões para os próximos meses")
                            .font(.subheadline.weight(.medium))
                    }
                }
                .toggleStyle(.checkbox)
                .onChange(of: globalRepeatToggle) { _, newValue in
                    for idx in draftItems.indices {
                        draftItems[idx].repeatForFutureMonths = newValue
                    }
                }

                Spacer()

                Text("Verba Livre (genérica) coexiste com Cotas de Itens Específicos na mesma categoria.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color.primary.opacity(0.03))

            Divider()

            // Category List
            ScrollView {
                VStack(spacing: 12) {
                    ForEach($draftItems) { $item in
                        let parsedEstimated = BRLFormatters.parseCurrencyInput(item.amountString)
                        let freeRemaining = max(0.0, parsedEstimated - item.realizedFreeExpense)
                        let catQuotas = store.quotaEnvelopes(forCategory: item.category.id, in: store.selectedMonth)
                        let quotasRemaining = catQuotas.reduce(0.0) { $0 + $1.remainingProvision }

                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 14) {
                                CategoryBadgeView(category: item.category, size: 36)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.category.name)
                                        .font(.subheadline.weight(.semibold))
                                    HStack(spacing: 8) {
                                        Text("Despesas avulsas no mês: \(BRLFormatters.currency(item.realizedFreeExpense))")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        if parsedEstimated > 0 || quotasRemaining > 0 {
                                            Text("• Provisão da categoria: \(BRLFormatters.currency(freeRemaining + quotasRemaining))")
                                                .font(.caption.weight(.medium))
                                                .foregroundStyle(Color(hex: "#6366F1"))
                                        }
                                    }
                                }

                                Spacer()

                                Button {
                                    addQuotaForCategory = item.category
                                } label: {
                                    Label("Adicionar Cota", systemImage: "plus.square.on.square")
                                        .font(.caption)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)

                                Toggle("Repetir", isOn: $item.repeatForFutureMonths)
                                    .toggleStyle(.checkbox)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .help("Repetir esta Verba Livre para os próximos meses")

                                HStack(spacing: 6) {
                                    Text("Verba Livre R$")
                                        .font(.caption.bold())
                                        .foregroundStyle(.secondary)
                                    TextField("0,00", text: $item.amountString)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 105)
                                        .multilineTextAlignment(.trailing)
                                }
                            }

                            if !catQuotas.isEmpty {
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(catQuotas) { q in
                                        HStack(spacing: 10) {
                                            Image(systemName: q.iconSymbol)
                                                .font(.caption)
                                                .foregroundStyle(Color(hex: "#0EA5E9"))
                                                .frame(width: 18)

                                            Text("\(q.name): \(q.consumedUnits) de \(q.plannedQuantity) consumidos • \(BRLFormatters.currency(q.remainingProvision)) restantes")
                                                .font(.caption.weight(.semibold))

                                            Text("(\(q.plannedQuantity) un. × \(BRLFormatters.currency(q.estimatedUnitPrice)))")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)

                                            Spacer()

                                            Button {
                                                redeemingQuota = q
                                            } label: {
                                                Label("Dar Baixa", systemImage: "plus.circle.fill")
                                                    .font(.caption2.bold())
                                            }
                                            .buttonStyle(.borderedProminent)
                                            .tint(Color(hex: "#0EA5E9"))
                                            .controlSize(.mini)

                                            Button {
                                                editingQuota = q
                                            } label: {
                                                Image(systemName: "pencil")
                                                    .font(.caption2)
                                            }
                                            .buttonStyle(.borderless)
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: "#0EA5E9").opacity(0.08)))
                                    }
                                }
                                .padding(.leading, 48)
                            }
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color(nsColor: .controlBackgroundColor))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(
                                    (parsedEstimated > 0 || !catQuotas.isEmpty)
                                        ? Color(hex: "#6366F1").opacity(0.35)
                                        : Color.primary.opacity(0.07),
                                    lineWidth: 1
                                )
                        )
                    }
                }
                .padding(20)
            }

            Divider()

            // Footer with live summary & Save button
            let allQuotas = store.allQuotaEnvelopes(for: store.selectedMonth)
            let quotasEstimatedSum = allQuotas.reduce(0.0) { $0 + $1.totalEstimatedAmount }
            let quotasRemainingSum = allQuotas.reduce(0.0) { $0 + $1.remainingProvision }

            let totalEstimatedDraft = draftItems.reduce(0.0) {
                $0 + max(0.0, BRLFormatters.parseCurrencyInput($1.amountString))
            } + quotasEstimatedSum

            let totalRemainingDraft = draftItems.reduce(0.0) { acc, item in
                let est = max(0.0, BRLFormatters.parseCurrencyInput(item.amountString))
                guard est > 0 else { return acc }
                return acc + max(0.0, est - item.realizedFreeExpense)
            } + quotasRemainingSum

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Total Orçado (Verbas Livres + Cotas): \(BRLFormatters.currency(totalEstimatedDraft))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Provisão de Gastos Variáveis: \(BRLFormatters.currency(totalRemainingDraft)) restantes")
                        .font(.subheadline.bold())
                        .foregroundStyle(Color(hex: "#6366F1"))
                }

                Spacer()

                Button("Cancelar") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button {
                    if hasModifiedExistingRecurringProvision() {
                        showRecurringEditScopeDialog = true
                    } else {
                        saveProvisions(scope: .thisAndFutureMonths)
                        dismiss()
                    }
                } label: {
                    Label("Salvar Previsões", systemImage: "checkmark.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(hex: "#6366F1"))
                .keyboardShortcut(.defaultAction)
            }
            .padding(20)
        }
        .frame(minWidth: 820, minHeight: 580)
        .onAppear {
            loadDrafts()
        }
        .sheet(item: $addQuotaForCategory) { category in
            QuotaItemEditorSheet(store: store, existingQuota: nil, preselectedCategoryId: category.id)
        }
        .sheet(item: $editingQuota) { quota in
            QuotaItemEditorSheet(store: store, existingQuota: quota)
        }
        .sheet(item: $redeemingQuota) { quota in
            QuotaRedemptionSheet(store: store, quotaEnvelope: quota)
        }
        .confirmationDialog(
            "Escopo da Alteração de Previsão Recorrente",
            isPresented: $showRecurringEditScopeDialog,
            titleVisibility: .visible
        ) {
            Button("Aplicar somente a este mês") {
                saveProvisions(scope: .onlyThisMonth)
                dismiss()
            }
            Button("Aplicar a este e a todos os meses futuros") {
                saveProvisions(scope: .thisAndFutureMonths)
                dismiss()
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Você alterou o valor de uma ou mais previsões com recorrência ativa. Deseja aplicar somente a este mês ou aplicar a este e a todos os meses futuros?")
        }
    }

    private func loadDrafts() {
        let monthRef = store.selectedMonth
        draftItems = store.expenseCategories.map { cat in
            let realizedFree = store.realizedFreeBudgetExpense(forCategory: cat.id, in: monthRef)
            if let effective = store.effectiveProvision(forCategory: cat.id, in: monthRef) {
                return DraftProvisionItem(
                    category: cat,
                    realizedFreeExpense: realizedFree,
                    amountString: String(format: "%.2f", effective.provision.estimatedAmount).replacingOccurrences(of: ".", with: ","),
                    initialAmount: effective.provision.estimatedAmount,
                    repeatForFutureMonths: effective.provision.repeatForFutureMonths,
                    wasInitiallyActive: true,
                    wasInitiallyRecurring: effective.provision.repeatForFutureMonths
                )
            } else {
                return DraftProvisionItem(
                    category: cat,
                    realizedFreeExpense: realizedFree,
                    amountString: "",
                    initialAmount: 0.0,
                    repeatForFutureMonths: true,
                    wasInitiallyActive: false,
                    wasInitiallyRecurring: false
                )
            }
        }
    }

    private func hasModifiedExistingRecurringProvision() -> Bool {
        for item in draftItems where item.wasInitiallyActive && item.wasInitiallyRecurring {
            let trimmed = item.amountString.trimmingCharacters(in: .whitespacesAndNewlines)
            let newAmount = trimmed.isEmpty ? 0.0 : max(0.0, BRLFormatters.parseCurrencyInput(trimmed))
            if abs(newAmount - item.initialAmount) > 0.01 {
                return true
            }
        }
        return false
    }

    private func saveProvisions(scope: ProvisionEditScope) {
        let monthRef = store.selectedMonth
        for item in draftItems {
            let trimmed = item.amountString.trimmingCharacters(in: .whitespacesAndNewlines)
            let amount = trimmed.isEmpty ? 0.0 : max(0.0, BRLFormatters.parseCurrencyInput(trimmed))
            if amount > 0 || item.wasInitiallyActive {
                let effectiveScope: ProvisionEditScope = (item.wasInitiallyActive && item.wasInitiallyRecurring && abs(amount - item.initialAmount) > 0.01)
                    ? scope
                    : .thisAndFutureMonths
                store.setCategoryProvision(
                    categoryId: item.category.id,
                    estimatedAmount: amount,
                    for: monthRef,
                    repeatForFutureMonths: item.repeatForFutureMonths,
                    editScope: effectiveScope
                )
            }
        }
    }
}

// MARK: - Modal: Editar Verba Livre Individual com Escopo Temporal

public struct FreeBudgetEditorSheet: View {
    @ObservedObject public var store: FinancialDataStore
    public let envelope: CategoryProvisionEnvelope
    @Environment(\.dismiss) private var dismiss

    @State private var amountString: String = ""
    @State private var repeatForFutureMonths: Bool = true
    @State private var showScopeDialog: Bool = false

    public var body: some View {
        let monthTitle = BRLFormatters.monthYear(store.selectedMonth)

        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                CategoryBadgeView(category: envelope.category, size: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Editar Verba Livre: \(envelope.category.name)")
                        .font(.title3.bold())
                    Text("Mês de referência: \(monthTitle)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Valor da Verba Livre Mensal (R$)")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                TextField("Ex: 300,00", text: $amountString)
                    .textFieldStyle(.roundedBorder)
            }

            Toggle("Repetir esta previsão para os próximos meses", isOn: $repeatForFutureMonths)
                .toggleStyle(.checkbox)

            Divider()

            HStack {
                Button("Cancelar") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button {
                    if envelope.provision.repeatForFutureMonths {
                        showScopeDialog = true
                    } else {
                        applySave(scope: .onlyThisMonth)
                    }
                } label: {
                    Label("Salvar Alterações", systemImage: "checkmark.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(hex: "#6366F1"))
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 440)
        .onAppear {
            amountString = String(format: "%.2f", envelope.freeBudgetEstimated).replacingOccurrences(of: ".", with: ",")
            repeatForFutureMonths = envelope.provision.repeatForFutureMonths
        }
        .confirmationDialog(
            "Aplicar Alteração no Teto Recorrente",
            isPresented: $showScopeDialog,
            titleVisibility: .visible
        ) {
            Button("Aplicar somente a este mês") {
                applySave(scope: .onlyThisMonth)
            }
            Button("Aplicar a este e a todos os meses futuros") {
                applySave(scope: .thisAndFutureMonths)
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Deseja aplicar a alteração somente a este mês (\(monthTitle)) ou a este e a todos os meses futuros?")
        }
    }

    private func applySave(scope: ProvisionEditScope) {
        let value = max(0.0, BRLFormatters.parseCurrencyInput(amountString))
        store.setCategoryProvision(
            categoryId: envelope.category.id,
            estimatedAmount: value,
            for: store.selectedMonth,
            repeatForFutureMonths: repeatForFutureMonths,
            editScope: scope
        )
        dismiss()
    }
}

// MARK: - Modal: Cadastrar / Editar Cota de Item Específico (ex: Galão de Água)

public struct QuotaItemEditorSheet: View {
    @ObservedObject public var store: FinancialDataStore
    public let existingQuota: CategoryQuotaEnvelope?
    public var preselectedCategoryId: UUID? = nil
    @Environment(\.dismiss) private var dismiss

    @State private var selectedCategoryId: UUID = UUID()
    @State private var itemName: String = ""
    @State private var iconSymbol: String = "drop.fill"
    @State private var plannedQuantityString: String = "1"
    @State private var unitPriceString: String = ""
    @State private var repeatForFutureMonths: Bool = true
    @State private var showEditScopeDialog: Bool = false

    private let suggestedIcons: [String] = [
        "drop.fill", "flame.fill", "shippingbox.fill", "cart.fill",
        "fuelpump.fill", "pills.fill", "pawprint.fill", "cup.and.saucer.fill",
        "bag.fill", "bolt.fill", "leaf.fill", "sparkles"
    ]

    public var body: some View {
        let monthTitle = BRLFormatters.monthYear(store.selectedMonth)
        let qty = max(1, Int(plannedQuantityString.filter(\.isNumber)) ?? 1)
        let unitPrice = max(0.0, BRLFormatters.parseCurrencyInput(unitPriceString))
        let totalEstimated = Double(qty) * unitPrice

        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(hex: "#0EA5E9").opacity(0.16))
                        .frame(width: 40, height: 40)
                    Image(systemName: iconSymbol)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color(hex: "#0EA5E9"))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(existingQuota == nil ? "Nova Cota de Item Específico" : "Editar Cota: \(existingQuota?.name ?? "")")
                        .font(.title3.bold())
                    Text("Coexiste com a Verba Livre da categoria em \(monthTitle)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Categoria Vinculada")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Picker("Categoria", selection: $selectedCategoryId) {
                        ForEach(store.expenseCategories) { cat in
                            Text(cat.name).tag(cat.id)
                        }
                    }
                    .labelsHidden()
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Nome do Item Específico")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    TextField("Ex: Galão de Água, Botijão de Gás, Ração...", text: $itemName)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: itemName) { _, newValue in
                            if existingQuota == nil {
                                iconSymbol = FinancialDataStore.defaultIconForQuotaName(newValue)
                            }
                        }
                }

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Quantidade prevista por mês")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        TextField("Ex: 1", text: $plannedQuantityString)
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Valor unitário estimado (R$)")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        TextField("Ex: 13,00", text: $unitPriceString)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Ícone do Item")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        ForEach(suggestedIcons, id: \.self) { sym in
                            Button {
                                iconSymbol = sym
                            } label: {
                                Image(systemName: sym)
                                    .font(.system(size: 13, weight: .semibold))
                                    .frame(width: 28, height: 28)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(iconSymbol == sym ? Color(hex: "#0EA5E9").opacity(0.22) : Color.primary.opacity(0.05))
                                    )
                                    .foregroundStyle(iconSymbol == sym ? Color(hex: "#0EA5E9") : .primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Toggle("Repetir esta cota automaticamente para os próximos meses", isOn: $repeatForFutureMonths)
                    .toggleStyle(.checkbox)

                HStack {
                    Text("Provisão Total da Cota (\(qty) un. × \(BRLFormatters.currency(unitPrice))):")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(BRLFormatters.currency(totalEstimated))
                        .font(.subheadline.bold())
                        .foregroundStyle(Color(hex: "#0EA5E9"))
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: "#0EA5E9").opacity(0.08)))
            }

            Divider()

            HStack {
                Button("Cancelar") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button {
                    if let existing = existingQuota, existing.repeatForFutureMonths {
                        showEditScopeDialog = true
                    } else {
                        saveQuota(scope: .thisAndFutureMonths)
                    }
                } label: {
                    Label(existingQuota == nil ? "Adicionar Cota" : "Salvar Cota", systemImage: "checkmark.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(hex: "#0EA5E9"))
                .disabled(itemName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || unitPrice <= 0)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 480)
        .onAppear {
            if let existing = existingQuota {
                selectedCategoryId = existing.categoryId
                itemName = existing.name
                iconSymbol = existing.iconSymbol
                plannedQuantityString = String(existing.plannedQuantity)
                unitPriceString = String(format: "%.2f", existing.estimatedUnitPrice).replacingOccurrences(of: ".", with: ",")
                repeatForFutureMonths = existing.repeatForFutureMonths
            } else {
                selectedCategoryId = preselectedCategoryId ?? store.expenseCategories.first?.id ?? UUID()
                plannedQuantityString = "1"
                unitPriceString = ""
            }
        }
        .confirmationDialog(
            "Escopo da Alteração da Cota Recorrente",
            isPresented: $showEditScopeDialog,
            titleVisibility: .visible
        ) {
            Button("Aplicar somente a este mês") {
                saveQuota(scope: .onlyThisMonth)
            }
            Button("Aplicar a este e a todos os meses futuros") {
                saveQuota(scope: .thisAndFutureMonths)
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Esta cota possui recorrência ativa. Deseja aplicar somente a este mês (\(monthTitle)) ou aplicar a este e a todos os meses futuros?")
        }
    }

    private func saveQuota(scope: ProvisionEditScope) {
        let qty = max(1, Int(plannedQuantityString.filter(\.isNumber)) ?? 1)
        let unitPrice = max(0.0, BRLFormatters.parseCurrencyInput(unitPriceString))
        store.saveCategoryQuota(
            seriesId: existingQuota?.seriesId,
            categoryId: selectedCategoryId,
            name: itemName,
            iconSymbol: iconSymbol,
            plannedQuantity: qty,
            estimatedUnitPrice: unitPrice,
            for: store.selectedMonth,
            repeatForFutureMonths: repeatForFutureMonths,
            editScope: scope
        )
        dismiss()
    }
}

// MARK: - Mini-Diálogo: Dar Baixa / Registrar Compra de Cota Específica

public struct QuotaRedemptionSheet: View {
    @ObservedObject public var store: FinancialDataStore
    public let quotaEnvelope: CategoryQuotaEnvelope
    @Environment(\.dismiss) private var dismiss

    @State private var unitsString: String = "1"
    @State private var actualUnitPriceString: String = ""
    @State private var selectedAccountId: UUID = UUID()
    @State private var notes: String = ""

    public var body: some View {
        let units = max(1, Int(unitsString.filter(\.isNumber)) ?? 1)
        let actualUnitPrice = max(0.0, BRLFormatters.parseCurrencyInput(actualUnitPriceString))
        let totalRealAmount = Double(units) * actualUnitPrice
        let categoryName = store.category(for: quotaEnvelope.categoryId)?.name ?? "Despesa"

        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(hex: "#0EA5E9").opacity(0.16))
                        .frame(width: 40, height: 40)
                    Image(systemName: quotaEnvelope.iconSymbol)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color(hex: "#0EA5E9"))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Dar Baixa: \(quotaEnvelope.name)")
                        .font(.title3.bold())
                    Text("Categoria vinculada: \(categoryName) • Consumidos: \(quotaEnvelope.consumedUnits) de \(quotaEnvelope.plannedQuantity)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Quantidade Comprada")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        TextField("1", text: $unitsString)
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Valor Unitário Real (R$)")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        TextField("0,00", text: $actualUnitPriceString)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Conta de Débito")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    if store.accounts.isEmpty {
                        Text("Cadastre uma conta bancária em Configurações → Contas para debitar.")
                            .font(.caption)
                            .foregroundStyle(Color(hex: "#EF4444"))
                    } else {
                        Picker("Conta", selection: $selectedAccountId) {
                            ForEach(store.accounts) { acc in
                                Text(acc.name).tag(acc.id)
                            }
                        }
                        .labelsHidden()
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Observação (Opcional)")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    TextField("Ex: Entrega rápida", text: $notes)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Valor Total a Debitar no Extrato:")
                            .font(.caption.weight(.medium))
                        Spacer()
                        Text(BRLFormatters.currency(totalRealAmount))
                            .font(.subheadline.bold())
                            .foregroundStyle(Color(hex: "#EF4444"))
                    }
                    Text("Esta baixa incrementará o contador da cota e criará a transação real com a data atual, sem abater da Verba Livre da categoria.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
            }

            Divider()

            HStack {
                Button("Cancelar") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button {
                    store.redeemCategoryQuota(
                        seriesId: quotaEnvelope.seriesId,
                        units: units,
                        unitPriceOverride: actualUnitPrice,
                        accountId: selectedAccountId,
                        in: store.selectedMonth,
                        transactionDate: Date(),
                        details: notes
                    )
                    dismiss()
                } label: {
                    Label("Confirmar Compra & Dar Baixa", systemImage: "checkmark.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(hex: "#0EA5E9"))
                .disabled(store.accounts.isEmpty || actualUnitPrice <= 0)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 460)
        .onAppear {
            actualUnitPriceString = String(format: "%.2f", quotaEnvelope.estimatedUnitPrice).replacingOccurrences(of: ".", with: ",")
            selectedAccountId = store.accounts.first?.id ?? UUID()
        }
    }
}

// MARK: - Gráfico de Fluxo de Caixa Empilhado & Tooltip de Projeção

public struct MonthlyCashFlowChartView: View {
    public let points: [MonthlyCashFlowPoint]
    public let isAnnual: Bool
    public let yearStr: String

    @State private var hoveredPoint: MonthlyCashFlowPoint? = nil

    public init(points: [MonthlyCashFlowPoint], isAnnual: Bool, yearStr: String) {
        self.points = points
        self.isAnnual = isAnnual
        self.yearStr = yearStr
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(isAnnual ? "Projeção Anual Mês a Mês (\(yearStr))" : "Fluxo de Caixa Mensal & Projeção")
                        .font(.headline)
                    Text(isAnnual ? "Receitas e despesas projetadas de Janeiro a 31/12/\(yearStr)" : "Comparativo de receitas e despesas entre os meses")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Circle().fill(Color(hex: "#10B981")).frame(width: 8, height: 8)
                        Text("Receitas").font(.caption2)
                    }
                    HStack(spacing: 4) {
                        Circle().fill(Color(hex: "#EF4444")).frame(width: 8, height: 8)
                        Text("Despesas").font(.caption2)
                    }
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(hex: "#EF4444").opacity(0.45))
                            .frame(width: 8, height: 8)
                        Text("Previsões & Tetos").font(.caption2)
                    }
                    HStack(spacing: 4) {
                        Capsule().fill(Color(hex: "#3B82F6")).frame(width: 10, height: 3)
                        Circle().fill(Color(hex: "#3B82F6")).frame(width: 6, height: 6)
                        Text("Saldo Final").font(.caption2)
                    }
                }
            }

            // Hover Tooltip Display no macOS detalhando valores da barra
            if let pt = hoveredPoint {
                HStack(spacing: 10) {
                    Image(systemName: "cursorarrow.rays")
                        .font(.caption)
                        .foregroundStyle(Color(hex: "#6366F1"))
                    Text(pt.label)
                        .font(.caption.weight(.bold))
                    Text("•")
                        .foregroundStyle(.secondary.opacity(0.5))
                    Text("Despesas Lançadas: ")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    + Text(BRLFormatters.currency(pt.expense))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color(hex: "#EF4444"))
                    Text("•")
                        .foregroundStyle(.secondary.opacity(0.5))
                    Text("Previsões/Tetos: ")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    + Text(BRLFormatters.currency(pt.remainingProvisions))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color(hex: "#6366F1"))
                    Text("•")
                        .foregroundStyle(.secondary.opacity(0.5))
                    Text("Total Orçado: ")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    + Text(BRLFormatters.currency(pt.totalBudgetedExpense))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.primary)
                    Text("•")
                        .foregroundStyle(.secondary.opacity(0.5))
                    Text("Saldo Final: ")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    + Text(BRLFormatters.currency(pt.accumulatedBalance))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color(hex: "#3B82F6"))
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.primary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .transition(.opacity)
            }

            Chart {
                ForEach(points) { pt in
                    // Receitas
                    BarMark(
                        x: .value("Mês", pt.label),
                        y: .value("Valor", pt.income)
                    )
                    .foregroundStyle(Color(hex: "#10B981"))
                    .position(by: .value("Tipo", "Receitas"))
                    .cornerRadius(4)

                    // Base sólida: Despesas já lançadas
                    BarMark(
                        x: .value("Mês", pt.label),
                        yStart: .value("Base", 0),
                        yEnd: .value("Valor", pt.expense)
                    )
                    .foregroundStyle(Color(hex: "#EF4444"))
                    .position(by: .value("Tipo", "Despesas"))
                    .cornerRadius(!pt.isPastMonth && pt.remainingProvisions > 0 ? 0 : 4)

                    // Topo translúcido: Margem de Previsões & Tetos restantes
                    if !pt.isPastMonth && pt.remainingProvisions > 0 {
                        BarMark(
                            x: .value("Mês", pt.label),
                            yStart: .value("Base", pt.expense),
                            yEnd: .value("Valor", pt.totalBudgetedExpense)
                        )
                        .foregroundStyle(Color(hex: "#EF4444").opacity(0.45))
                        .position(by: .value("Tipo", "Despesas"))
                        .cornerRadius(4)
                    }

                    // Linha sobreposta e pontos: Evolução do Saldo Final
                    LineMark(
                        x: .value("Mês", pt.label),
                        y: .value("Saldo Final", pt.accumulatedBalance)
                    )
                    .foregroundStyle(Color(hex: "#3B82F6"))
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))

                    PointMark(
                        x: .value("Mês", pt.label),
                        y: .value("Saldo Final", pt.accumulatedBalance)
                    )
                    .foregroundStyle(Color(hex: "#3B82F6"))
                    .symbolSize(32)
                }
            }
            .frame(height: 205)
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                if let plotFrame = proxy.plotFrame {
                                    let origin = geometry[plotFrame].origin
                                    let xInPlot = location.x - origin.x
                                    if let label: String = proxy.value(atX: xInPlot) {
                                        hoveredPoint = points.first(where: { $0.label == label })
                                        return
                                    }
                                }
                                hoveredPoint = nil
                            case .ended:
                                hoveredPoint = nil
                            }
                        }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 290, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.07), lineWidth: 1)
        )
    }
}
