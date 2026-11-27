import SwiftUI
import Charts

public struct DashboardView: View {
    @ObservedObject public var store: FinancialDataStore
    @ObservedObject public var llmService: LocalLLMService
    @Environment(\.colorScheme) private var colorScheme

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
        let kpiSummary = store.buildUnifiedFinancialKPISummary(
            referenceDate: store.selectedMonth,
            isAnnual: isAnnual
        )
        let yearStr = BRLFormatters.yearString(store.selectedMonth)
        let periodFullLabel = isAnnual
            ? "31/12/\(yearStr)"
            : BRLFormatters.monthYear(store.selectedMonth)

        let isPastPeriod = isAnnual
            ? (store.calendar.component(.year, from: store.selectedMonth) < store.calendar.component(.year, from: store.effectiveCurrentDate))
            : store.isMonthPriorToCurrent(store.selectedMonth)

        let periodExpense = kpiSummary.recordedExpense

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
        let debtServiceBreakdown = store.buildPeriodDebtServiceBreakdown(
            referenceDate: store.selectedMonth,
            isAnnual: isAnnual
        )
        let monthEnvelopes = store.provisionEnvelopes(for: store.selectedMonth)
        let monthQuotas = store.allQuotaEnvelopes(for: store.selectedMonth)
        let hasAnyProvisionOrQuota = !monthEnvelopes.isEmpty || !monthQuotas.isEmpty
        let remainingProvisionsTotal = isPastPeriod ? 0.0 : store.totalRemainingProvision(for: store.selectedMonth)
        let estimatedProvisionsTotal = store.totalEstimatedProvision(for: store.selectedMonth)

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // MARK: - Minimalist Floating Header Toolbar
                HStack(alignment: .center, spacing: 14) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Dashboard")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                        Text(
                            isAnnual
                                ? "Projeção consolidada • 31/12/\(yearStr)"
                                : "Visão consolidada • \(periodFullLabel)"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    Spacer()

                    DashboardPeriodNavigatorBar(store: store)

                    Spacer()

                    // Single Primary CTA Menu (+ Novo)
                    Menu {
                        Button {
                            showCreateExpenseSheet = true
                        } label: {
                            Label("Nova Despesa", systemImage: "minus.circle")
                        }

                        Button {
                            showCreateIncomeSheet = true
                        } label: {
                            Label("Nova Receita", systemImage: "plus.circle")
                        }

                        Divider()

                        Button {
                            store.requireInstalledLLM(forFeature: "Importar Extrato PDF / Relatório com IA Local") {
                                showImportStatementSheet = true
                            }
                        } label: {
                            Label("Importar Extrato com IA", systemImage: "doc.text.magnifyingglass")
                        }

                        Button {
                            showProvisionsSheet = true
                        } label: {
                            Label("Previsões & Tetos do Mês", systemImage: "tray.full")
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus")
                                .font(.system(size: 11.5, weight: .bold))
                            Text("Novo")
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9, weight: .bold))
                                .opacity(0.8)
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(FinSenseTheme.indigo)
                    )
                    .foregroundStyle(.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.16), lineWidth: 0.75)
                    )
                    .shadow(color: FinSenseTheme.indigo.opacity(0.24), radius: 6, x: 0, y: 2)
                    .fixedSize()
                }

                // MARK: - Alertas Contextuais (Central de Insights ML em pílula sutil)
                let dashIntraAnalysis: IntraMonthCashFlowAnalysis? = isAnnual ? nil : store.buildIntraMonthCashFlowAnalysis(for: store.selectedMonth)

                if store.activeUnreviewedInsightsCount > 0 {
                    HStack(spacing: 10) {
                        Circle()
                            .fill(FinSenseTheme.indigo)
                            .frame(width: 7, height: 7)
                        Image(systemName: "brain.filled.head.profile")
                            .font(.system(size: 13))
                            .foregroundStyle(FinSenseTheme.indigo)
                        Text("Central de Insights ML: \(store.activeUnreviewedInsightsCount) alerta(s) ou fechamento aguardando revisão.")
                            .font(.caption.weight(.medium))
                        Spacer()
                        Button("Abrir Central") {
                            store.selectedDestination = .insights
                        }
                        .buttonStyle(BentoGlassButtonStyle(tint: FinSenseTheme.indigo, cornerRadius: 8, verticalPadding: 4, horizontalPadding: 10))
                    }
                    .bentoCard(padding: 12, cornerRadius: 12, accent: FinSenseTheme.indigo, isHighlighted: false)
                }

                // MARK: - Top Bento KPI Section (Left Hero Projected Balance ~42% + Right 5-KPI Grid ~58%)
                DashboardTopKPICardsView(
                    summary: kpiSummary,
                    isAnnual: isAnnual,
                    intraMonthAnalysis: dashIntraAnalysis,
                    sinkingFundsReserve: isAnnual ? 0.0 : store.totalMonthlySinkingFundContribution(for: store.selectedMonth),
                    onEditProvisions: { showProvisionsSheet = true },
                    onOpenTransactions: { store.selectedDestination = .transactions }
                )

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
                            .buttonStyle(BentoGlassButtonStyle(tint: FinSenseTheme.cyan, cornerRadius: 8, verticalPadding: 5, horizontalPadding: 10))
                            .help("Cadastrar cota de item específico (ex: Galão de Água)")

                            Button {
                                showProvisionsSheet = true
                            } label: {
                                Label(
                                    hasAnyProvisionOrQuota ? "Gerenciar Tetos & Cotas" : "Configurar Previsões",
                                    systemImage: "slider.horizontal.3"
                                )
                            }
                            .buttonStyle(BentoGlassButtonStyle(tint: FinSenseTheme.indigo, cornerRadius: 8, verticalPadding: 5, horizontalPadding: 10))
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
                                    Grid(horizontalSpacing: 14, verticalSpacing: 14) {
                                        ForEach(Array(stride(from: 0, to: monthQuotas.count, by: 2)), id: \.self) { rowStart in
                                            GridRow {
                                                quotaItemCard(monthQuotas[rowStart])
                                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                                if rowStart + 1 < monthQuotas.count {
                                                    quotaItemCard(monthQuotas[rowStart + 1])
                                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                                } else {
                                                    Color.clear
                                                        .gridCellUnsizedAxes([.horizontal, .vertical])
                                                }
                                            }
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
                                    Grid(horizontalSpacing: 14, verticalSpacing: 14) {
                                        ForEach(Array(stride(from: 0, to: monthEnvelopes.count, by: 2)), id: \.self) { rowStart in
                                            GridRow {
                                                provisionEnvelopeCard(monthEnvelopes[rowStart])
                                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                                if rowStart + 1 < monthEnvelopes.count {
                                                    provisionEnvelopeCard(monthEnvelopes[rowStart + 1])
                                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                                } else {
                                                    Color.clear
                                                        .gridCellUnsizedAxes([.horizontal, .vertical])
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .bentoCard(padding: 18)
                }

                // MARK: - Charts Section (Expense by Category + Monthly/Annual Cash Flow)
                HStack(alignment: .top, spacing: 16) {
                    // Chart 1: Gráfico de Despesa por Categoria (Top 5 + Outros expansível)
                    ExpensesByCategoryCardView(
                        items: expenseByCategory,
                        totalExpense: periodExpense,
                        periodFullLabel: periodFullLabel,
                        isAnnual: isAnnual
                    )

                    // Chart 2: Evolução de Receitas vs Despesas e Projeção Empilhada
                    MonthlyCashFlowChartView(
                        points: cashFlowPoints,
                        isAnnual: isAnnual,
                        yearStr: yearStr
                    )
                }

                // MARK: - Total de Dívidas e Passivos (Balanço Patrimonial)
                VStack(alignment: .leading, spacing: 18) {
                    let totalRealLiabilities = debtSummary.totalRealLiabilities
                    let totalNominalLiabilities = debtSummary.totalNominalLiabilities

                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Image(systemName: "building.columns.fill")
                                    .foregroundStyle(Color(hex: "#EF4444"))
                                Text("Total de Dívidas e Passivos")
                                    .font(.title3.bold())
                            }
                            Text(
                                isAnnual
                                    ? "Estoque de passivos e saldos devedores consolidados projetados até 31/12 de \(yearStr)"
                                    : "Estoque de passivos e saldos devedores consolidados projetados para o mês selecionado"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        Spacer()

                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Total a Quitar (Dívida Real)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(BRLFormatters.currency(totalRealLiabilities))
                                .font(.system(size: 22, weight: .heavy, design: .rounded))
                                .foregroundStyle(Color(hex: "#EF4444"))
                                .monospacedDigit()
                            if abs(totalNominalLiabilities - totalRealLiabilities) > 0.01 {
                                Text("Soma nominal futura (com juros): \(BRLFormatters.currency(totalNominalLiabilities))")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                    }

                    // 4 Pillars Breakdown (Equal-Height Grid - Estoque / Balanço Patrimonial)
                    Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                        GridRow {
                            debtPillarCard(
                                title: "Passivo Total (Dívida Real)",
                                subtitle: isAnnual
                                    ? "\(BRLFormatters.currency(debtServiceBreakdown.totalDebtService)) em parcelas no ano"
                                    : "\(BRLFormatters.currency(debtServiceBreakdown.totalDebtService)) em parcelas no mês",
                                amount: totalRealLiabilities,
                                projected: nil,
                                nominalAmount: totalNominalLiabilities,
                                paidInPeriod: debtSummary.loansPaidInPeriodTotal + debtSummary.financingsPaidInPeriodTotal + debtServiceBreakdown.debtInstallments,
                                realAmortizationInPeriod: debtSummary.loansRealAmortizationInPeriodTotal + debtSummary.financingsRealAmortizationInPeriodTotal,
                                colorHex: "#EF4444",
                                icon: "building.columns.fill"
                            )
                            .frame(maxWidth: .infinity)

                            debtPillarCard(
                                title: "Dívidas (Acordos/Serasa)",
                                subtitle: debtSummary.activeDebts.count == 1 ? "1 dívida ativa" : "\(debtSummary.activeDebts.count) dívidas ativas",
                                amount: debtSummary.unpaidDebtsTotal,
                                projected: nil,
                                nominalAmount: nil,
                                paidInPeriod: debtServiceBreakdown.debtInstallments > 0 ? debtServiceBreakdown.debtInstallments : nil,
                                realAmortizationInPeriod: nil,
                                colorHex: "#EF4444",
                                icon: "exclamationmark.triangle.fill"
                            )
                            .frame(maxWidth: .infinity)

                            debtPillarCard(
                                title: "Empréstimos",
                                subtitle: isAnnual
                                    ? "\(BRLFormatters.currency(debtServiceBreakdown.loanInstallments)) no ano • \(debtSummary.activeLoans.count) contrato(s)"
                                    : "\(BRLFormatters.currency(debtServiceBreakdown.loanInstallments))/mês • \(debtSummary.activeLoans.count) contrato(s)",
                                amount: debtSummary.loansProjectedPayoffTotal,
                                projected: nil,
                                nominalAmount: debtSummary.loansRemainingNominalTotal,
                                paidInPeriod: debtSummary.loansPaidInPeriodTotal,
                                realAmortizationInPeriod: debtSummary.loansRealAmortizationInPeriodTotal,
                                colorHex: "#D97706",
                                icon: "banknote.fill"
                            )
                            .frame(maxWidth: .infinity)

                            debtPillarCard(
                                title: "Financiamentos",
                                subtitle: isAnnual
                                    ? "\(BRLFormatters.currency(debtServiceBreakdown.financingInstallments)) no ano • \(debtSummary.activeFinancings.count) contrato(s)"
                                    : "\(BRLFormatters.currency(debtServiceBreakdown.financingInstallments))/mês • \(debtSummary.activeFinancings.count) contrato(s)",
                                amount: debtSummary.financingsProjectedPayoffTotal,
                                projected: nil,
                                nominalAmount: debtSummary.financingsRemainingNominalTotal,
                                paidInPeriod: debtSummary.financingsPaidInPeriodTotal,
                                realAmortizationInPeriod: debtSummary.financingsRealAmortizationInPeriodTotal,
                                colorHex: "#8B5CF6",
                                icon: "house.and.flag.fill"
                            )
                            .frame(maxWidth: .infinity)
                        }
                    }

                    Divider()
                        .opacity(0.5)
                        .padding(.vertical, 2)

                    // MARK: - Painel Analítico: Comprometimento de Renda vs. Obrigações (Fluxo / DTI)
                    DebtCommitmentsDonutChartView(breakdown: debtServiceBreakdown)
                }
                .bentoCard(padding: 18)

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
                                .background(RoundedRectangle(cornerRadius: 10).fill(FinSenseTheme.nestedSurface(for: colorScheme)))
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .bentoCard(padding: 18)

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
                                        .foregroundStyle(FinSenseTheme.emerald)
                                        .monospacedDigit()
                                }
                                .padding(8)
                                .background(RoundedRectangle(cornerRadius: 10).fill(FinSenseTheme.nestedSurface(for: colorScheme)))
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .bentoCard(padding: 18)
                }

                // MARK: - Credit Cards Quick Overview (Limites & Faturas)
                if !store.creditCards.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("Cartões de Crédito", systemImage: "creditcard.fill")
                                .font(.headline)
                            Spacer()
                            Button("Abrir Faturas & Limites") {
                                store.selectedDestination = .creditCards
                            }
                            .buttonStyle(.link)
                            .font(.caption)
                        }

                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                            ForEach(store.creditCards) { card in
                                let used = store.usedLimit(for: card.id)
                                let available = store.availableLimit(for: card.id)
                                let ratio = card.totalLimit > 0 ? min(1.0, max(0.0, used / card.totalLimit)) : 0.0
                                let activeCycle = CreditCardEngine.allocateInvoice(forPurchaseDate: store.selectedMonth, card: card)
                                let invoiceSum = store.invoiceSummary(for: card.id, year: activeCycle.year, month: activeCycle.month)

                                Button {
                                    store.selectedCreditCardIdForDetail = card.id
                                    store.selectedDestination = .creditCards
                                } label: {
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack(spacing: 10) {
                                            AccountAvatarView(
                                                customImagePath: card.customImagePath,
                                                bankPresetId: card.bankPresetId,
                                                fallbackSymbol: card.iconSymbol,
                                                colorHex: card.colorHex,
                                                size: 34
                                            )
                                            VStack(alignment: .leading, spacing: 1) {
                                                Text(card.name)
                                                    .font(.subheadline.weight(.semibold))
                                                    .foregroundStyle(.primary)
                                                    .lineLimit(1)
                                                Text("Fecha \(card.closingDay) • Vence \(card.dueDay)")
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                            }
                                            Spacer()
                                            if let invoiceSum {
                                                Text(invoiceSum.status.rawValue)
                                                    .font(.system(size: 10, weight: .bold))
                                                    .padding(.horizontal, 7)
                                                    .padding(.vertical, 2)
                                                    .background(Capsule().fill(Color(hex: invoiceSum.status.colorHex).opacity(0.16)))
                                                    .foregroundStyle(Color(hex: invoiceSum.status.colorHex))
                                            }
                                        }

                                        ProgressView(value: ratio)
                                            .tint(used > card.totalLimit ? .red : Color(hex: card.colorHex))

                                        HStack {
                                            VStack(alignment: .leading, spacing: 1) {
                                                Text("Fatura \(activeCycle.month)/\(activeCycle.year % 100)")
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                                Text(BRLFormatters.currency(invoiceSum?.totalAmount ?? 0))
                                                    .font(.caption.bold())
                                                    .foregroundStyle(.primary)
                                            }
                                            Spacer()
                                            VStack(alignment: .trailing, spacing: 1) {
                                                Text("Disponível")
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                                Text(BRLFormatters.currency(available))
                                                    .font(.caption.bold())
                                                    .foregroundStyle(available > 0 ? .green : .red)
                                            }
                                        }
                                    }
                                    .padding(12)
                                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.03)))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .stroke(Color(hex: card.colorHex).opacity(0.20), lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .bentoCard(padding: 18)
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
                    Button("Excluir deste mês em diante") {
                        store.deleteCategoryQuota(
                            seriesId: q.seriesId,
                            for: store.selectedMonth,
                            scope: .fromThisMonthOnward
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
                Text("Esta cota possui recorrência ativa. Deseja removê-la somente deste mês, deste mês em diante (preservando o histórico anterior) ou excluir todas as ocorrências definitivamente?")
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
                    Button("Excluir deste mês em diante") {
                        store.deleteCategoryProvision(
                            categoryId: env.category.id,
                            for: store.selectedMonth,
                            scope: .fromThisMonthOnward
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
                Text("A verba livre desta categoria é recorrente. Deseja removê-la somente deste mês, deste mês em diante (preservando o histórico anterior) ou excluir todas as ocorrências?")
            } else {
                Text("Deseja remover a verba livre desta categoria no mês atual?")
            }
        }
    }

    @ViewBuilder
    private func quotaItemCard(_ quota: CategoryQuotaEnvelope) -> some View {
        let isInvestment = quota.quotaType == .investment
        let statusColorHex: String = {
            if isInvestment {
                return quota.statusColorHex
            }
            switch quota.status {
            case .normal: return "#0EA5E9"
            case .warning: return "#F59E0B"
            case .exceeded: return "#EF4444"
            }
        }()
        let categoryName = store.category(for: quota.categoryId)?.name ?? "Despesa"
        let investmentName = store.investment(for: quota.linkedInvestmentId)?.name

        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color(hex: statusColorHex).opacity(0.15))
                        .frame(width: 34, height: 34)
                    Image(systemName: isInvestment ? "chart.line.uptrend.xyaxis" : quota.iconSymbol)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color(hex: statusColorHex))
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        if isInvestment {
                            let target = quota.totalEstimatedAmount
                            let realized = quota.realizedExpense
                            if realized >= target && target > 0 {
                                if realized > target + 0.01 {
                                    Text("\(quota.name): \(BRLFormatters.currency(realized)) aportados (Meta: \(BRLFormatters.currency(target))) • Meta superada")
                                        .font(.subheadline.weight(.semibold))
                                        .lineLimit(1)
                                } else {
                                    Text("\(quota.name): \(BRLFormatters.currency(realized)) de \(BRLFormatters.currency(target)) • Meta concluída")
                                        .font(.subheadline.weight(.semibold))
                                        .lineLimit(1)
                                }
                            } else {
                                let remaining = max(0.0, target - realized)
                                Text("\(quota.name): \(BRLFormatters.currency(realized)) de \(BRLFormatters.currency(target)) • \(BRLFormatters.currency(remaining)) restantes")
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                            }
                        } else {
                            Text("\(quota.name): \(quota.consumedUnits) de \(quota.plannedQuantity) consumidos • \(BRLFormatters.currency(quota.remainingProvision)) restantes")
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                        }
                        if isInvestment {
                            Text("INVESTIMENTO")
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(Capsule().fill(Color(hex: "#10B981").opacity(0.18)))
                                .foregroundStyle(Color(hex: "#10B981"))
                        }
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
                    if isInvestment {
                        Text("Planejado: \(BRLFormatters.currency(quota.totalEstimatedAmount)) • Destino: \(investmentName ?? quota.name)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else {
                        Text("Unitário est.: \(BRLFormatters.currency(quota.estimatedUnitPrice)) • Pendentes: \(quota.pendingUnits) un. • Cat. padrão: \(categoryName)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                Text(isInvestment ? quota.statusTitle : quota.status.rawValue)
                    .font(.system(size: 10.5, weight: .bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color(hex: statusColorHex).opacity(0.15)))
                    .foregroundStyle(Color(hex: statusColorHex))
            }
            .frame(minHeight: 34, alignment: .leading)

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

            Spacer(minLength: 4)

            HStack(spacing: 8) {
                Button {
                    redeemingQuotaEnvelope = quota
                } label: {
                    Label(isInvestment ? "+ Realizar Aporte" : "+ Dar Baixa", systemImage: isInvestment ? "arrow.up.circle.fill" : "plus.circle.fill")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(hex: statusColorHex))
                .controlSize(.small)
                .help(isInvestment ? "Realizar aporte bancário no investimento e dar baixa na cota" : "Abrir mini-diálogo pré-preenchido para dar baixa em 1 unidade e lançar despesa real no extrato")

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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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

                Spacer(minLength: 8)

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
            .frame(minHeight: 34, alignment: .leading)

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

            Spacer(minLength: 4)

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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
        nominalAmount: Double? = nil,
        paidInPeriod: Double? = nil,
        realAmortizationInPeriod: Double? = nil,
        colorHex: String,
        icon: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Zona 1: Cabeçalho (Topo)
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(hex: colorHex))
                Text(title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
            }
            .frame(height: 20)

            // Zona 2: Valor Principal (Centro)
            Text(BRLFormatters.currency(amount))
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(Color(hex: colorHex))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .monospacedDigit()
                .frame(height: 22, alignment: .leading)

            // Espaçador flexível (mola) para nivelamento e ancoragem do rodapé
            Spacer(minLength: 6)

            // Zona 3: Metadados e Rodapé (Base ancorada)
            VStack(alignment: .leading, spacing: 2) {
                Text(subtitle)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let paidInPeriod, paidInPeriod > 0 {
                    Text("Pagamentos: \(BRLFormatters.currency(paidInPeriod))")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .monospacedDigit()
                }
                if let realAmortizationInPeriod, realAmortizationInPeriod > 0 {
                    Text("Amortização: \(BRLFormatters.currency(realAmortizationInPeriod))")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(hex: "#10B981"))
                        .lineLimit(1)
                        .monospacedDigit()
                }
                if let nominalAmount, nominalAmount > amount + 0.01 {
                    Text("Soma nominal: \(BRLFormatters.currency(nominalAmount))")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .monospacedDigit()
                }
                if let projected, abs(amount - projected) > 0.01 && (paidInPeriod == nil || paidInPeriod == 0) {
                    Text("Quitar: \(BRLFormatters.currency(projected))")
                        .font(.caption2.bold())
                        .foregroundStyle(Color(hex: "#10B981"))
                        .lineLimit(1)
                        .monospacedDigit()
                }
            }
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .bottomLeading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: 136)
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

// MARK: - Modal: Cadastrar / Editar Cota de Item Específico ou Planejamento de Investimento

public struct QuotaItemEditorSheet: View {
    @ObservedObject public var store: FinancialDataStore
    public let existingQuota: CategoryQuotaEnvelope?
    public var preselectedCategoryId: UUID? = nil
    @Environment(\.dismiss) private var dismiss

    @State private var quotaType: QuotaType = .expense
    @State private var selectedInvestmentId: UUID? = nil
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
        let isInvestment = quotaType == .investment
        let accentColorHex = isInvestment ? "#10B981" : "#0EA5E9"
        let monthTitle = BRLFormatters.monthYear(store.selectedMonth)
        let qty = isInvestment ? 1 : max(1, Int(plannedQuantityString.filter(\.isNumber)) ?? 1)
        let unitPrice = max(0.0, BRLFormatters.parseCurrencyInput(unitPriceString))
        let totalEstimated = Double(qty) * unitPrice

        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(hex: accentColorHex).opacity(0.16))
                        .frame(width: 40, height: 40)
                    Image(systemName: iconSymbol)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color(hex: accentColorHex))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(existingQuota == nil
                         ? (isInvestment ? "Novo Planejamento de Investimento" : "Nova Cota de Item Específico")
                         : "Editar: \(existingQuota?.name ?? "")")
                        .font(.title3.bold())
                    Text(isInvestment
                         ? "Guarda programada agregada aos orçamentos pendentes de \(monthTitle)"
                         : "Coexiste com a Verba Livre da categoria em \(monthTitle)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            // Seletor de Tipo: Cota de Despesa vs Planejamento de Investimento
            if existingQuota == nil {
                Picker("Tipo de Planejamento", selection: $quotaType) {
                    Text("Cota de Despesa").tag(QuotaType.expense)
                    Text("Planejamento de Investimento").tag(QuotaType.investment)
                }
                .pickerStyle(.segmented)
            }

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                if isInvestment {
                    // SELEÇÃO DE INVESTIMENTO
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Investimento de Destino")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        if store.investments.isEmpty {
                            Text("Nenhum investimento cadastrado. Cadastre investimentos na tela Investimentos para vincular.")
                                .font(.caption)
                                .foregroundStyle(Color(hex: "#EF4444"))
                        } else {
                            Picker("Investimento", selection: Binding(
                                get: { selectedInvestmentId ?? store.investments.first?.id ?? UUID() },
                                set: { newId in
                                    selectedInvestmentId = newId
                                    if let inv = store.investment(for: newId) {
                                        itemName = "Aporte \(inv.name)"
                                        iconSymbol = inv.iconSymbol
                                    }
                                }
                            )) {
                                ForEach(store.investments) { inv in
                                    Text("\(inv.name) (\(inv.groupName))").tag(inv.id)
                                }
                            }
                            .labelsHidden()
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Valor que quero guardar / investir no mês (R$)")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        TextField("Ex: 500,00", text: $unitPriceString)
                            .textFieldStyle(.roundedBorder)
                    }

                    Toggle("Repetir esta projeção de investimento para os próximos meses", isOn: $repeatForFutureMonths)
                        .toggleStyle(.checkbox)

                    HStack {
                        Text("Total Planejado a Guardar em \(monthTitle):")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(BRLFormatters.currency(unitPrice))
                            .font(.subheadline.bold())
                            .foregroundStyle(Color(hex: "#10B981"))
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: "#10B981").opacity(0.08)))
                } else {
                    // COTA DE DESPESA
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
                    Label(existingQuota == nil ? (isInvestment ? "Criar Planejamento" : "Adicionar Cota") : "Salvar", systemImage: "checkmark.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(hex: accentColorHex))
                .disabled((isInvestment && (store.investments.isEmpty || unitPrice <= 0)) || (!isInvestment && (itemName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || unitPrice <= 0)))
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 480)
        .onAppear {
            if let existing = existingQuota {
                quotaType = existing.quotaType
                selectedInvestmentId = existing.linkedInvestmentId
                selectedCategoryId = existing.categoryId
                itemName = existing.name
                iconSymbol = existing.iconSymbol
                plannedQuantityString = String(existing.plannedQuantity)
                unitPriceString = String(format: "%.2f", existing.estimatedUnitPrice).replacingOccurrences(of: ".", with: ",")
                repeatForFutureMonths = existing.repeatForFutureMonths
            } else {
                selectedCategoryId = preselectedCategoryId ?? store.expenseCategories.first?.id ?? UUID()
                selectedInvestmentId = store.investments.first?.id
                if quotaType == .investment, let firstInv = store.investments.first {
                    itemName = "Aporte \(firstInv.name)"
                    iconSymbol = firstInv.iconSymbol
                }
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
        let isInvestment = quotaType == .investment
        let qty = isInvestment ? 1 : max(1, Int(plannedQuantityString.filter(\.isNumber)) ?? 1)
        let unitPrice = max(0.0, BRLFormatters.parseCurrencyInput(unitPriceString))

        if isInvestment {
            let targetInvId = selectedInvestmentId ?? store.investments.first?.id
            let inv = targetInvId != nil ? store.investment(for: targetInvId!) : nil
            let cleanName = "Aporte \(inv?.name ?? "Investimento")"
            let cleanIcon = inv?.iconSymbol ?? "chart.line.uptrend.xyaxis"
            let fallbackCat = store.investmentDepositCategoryId()

            store.saveCategoryQuota(
                seriesId: existingQuota?.seriesId,
                categoryId: fallbackCat,
                name: cleanName,
                iconSymbol: cleanIcon,
                plannedQuantity: 1,
                estimatedUnitPrice: unitPrice,
                for: store.selectedMonth,
                repeatForFutureMonths: repeatForFutureMonths,
                editScope: scope,
                quotaType: .investment,
                linkedInvestmentId: targetInvId
            )
        } else {
            store.saveCategoryQuota(
                seriesId: existingQuota?.seriesId,
                categoryId: selectedCategoryId,
                name: itemName,
                iconSymbol: iconSymbol,
                plannedQuantity: qty,
                estimatedUnitPrice: unitPrice,
                for: store.selectedMonth,
                repeatForFutureMonths: repeatForFutureMonths,
                editScope: scope,
                quotaType: .expense,
                linkedInvestmentId: nil
            )
        }
        dismiss()
    }
}

// MARK: - Mini-Diálogo: Dar Baixa / Registrar Compra de Cota Específica ou Aporte de Investimento

public struct QuotaRedemptionSheet: View {
    @ObservedObject public var store: FinancialDataStore
    public let quotaEnvelope: CategoryQuotaEnvelope
    @Environment(\.dismiss) private var dismiss

    @State private var unitsString: String = "1"
    @State private var actualUnitPriceString: String = ""
    @State private var selectedAccountId: UUID = UUID()
    @State private var notes: String = ""

    public var body: some View {
        let isInvestment = quotaEnvelope.quotaType == .investment
        let accentColorHex = isInvestment ? "#10B981" : "#0EA5E9"
        let units = isInvestment ? 1 : max(1, Int(unitsString.filter(\.isNumber)) ?? 1)
        let actualUnitPrice = max(0.0, BRLFormatters.parseCurrencyInput(actualUnitPriceString))
        let totalRealAmount = Double(units) * actualUnitPrice
        let categoryName = store.category(for: quotaEnvelope.categoryId)?.name ?? "Despesa"
        let investmentName = store.investment(for: quotaEnvelope.linkedInvestmentId)?.name ?? quotaEnvelope.name

        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(hex: accentColorHex).opacity(0.16))
                        .frame(width: 40, height: 40)
                    Image(systemName: quotaEnvelope.iconSymbol)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color(hex: accentColorHex))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(isInvestment ? "Confirmar Aporte: \(quotaEnvelope.name)" : "Dar Baixa: \(quotaEnvelope.name)")
                        .font(.title3.bold())
                    if isInvestment {
                        Text("Destino: \(investmentName) • Planejado: \(BRLFormatters.currency(quotaEnvelope.totalEstimatedAmount))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Categoria vinculada: \(categoryName) • Consumidos: \(quotaEnvelope.consumedUnits) de \(quotaEnvelope.plannedQuantity)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
            }

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                if isInvestment {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Valor do Aporte a Realizar (R$)")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        TextField("0,00", text: $actualUnitPriceString)
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Conta Bancária de Origem (Débito)")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        if store.accounts.isEmpty {
                            Text("Cadastre uma conta bancária em Configurações → Contas para debitar.")
                                .font(.caption)
                                .foregroundStyle(Color(hex: "#EF4444"))
                        } else {
                            Picker("Conta de Origem", selection: $selectedAccountId) {
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
                        TextField("Ex: Aporte mensal programado", text: $notes)
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Valor Total a Debitar e Creditar no Investimento:")
                                .font(.caption.weight(.medium))
                            Spacer()
                            Text(BRLFormatters.currency(totalRealAmount))
                                .font(.subheadline.bold())
                                .foregroundStyle(Color(hex: "#10B981"))
                        }
                        Text("Esta baixa debitará a conta bancária selecionada, adicionará o saldo no investimento e registrará a baixa desta cota de investimento.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: "#10B981").opacity(0.08)))
                } else {
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
                        units: isInvestment ? 1 : units,
                        unitPriceOverride: actualUnitPrice,
                        accountId: selectedAccountId,
                        in: store.selectedMonth,
                        transactionDate: Date(),
                        details: notes
                    )
                    dismiss()
                } label: {
                    Label(isInvestment ? "Confirmar Aporte & Dar Baixa" : "Confirmar Compra & Dar Baixa", systemImage: "checkmark.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(hex: accentColorHex))
                .disabled(store.accounts.isEmpty || actualUnitPrice <= 0)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 460)
        .onAppear {
            if isInvestment {
                let remaining = quotaEnvelope.totalEstimatedAmount - quotaEnvelope.realizedExpense
                let defaultVal = remaining > 0 ? remaining : quotaEnvelope.estimatedUnitPrice
                actualUnitPriceString = String(format: "%.2f", defaultVal > 0 ? defaultVal : quotaEnvelope.estimatedUnitPrice).replacingOccurrences(of: ".", with: ",")
            } else {
                actualUnitPriceString = String(format: "%.2f", quotaEnvelope.estimatedUnitPrice).replacingOccurrences(of: ".", with: ",")
            }
            selectedAccountId = store.accounts.first?.id ?? UUID()
        }
    }
}

// MARK: - Gráfico de Fluxo de Caixa Empilhado & Tooltip de Projeção

// MARK: - Despesas por Categoria (Rosca Fina Top 5 + Outros com Total Centralizado)

public struct ExpensesByCategoryCardView: View {
    public let items: [CategorySpendSummary]
    public let totalExpense: Double
    public let periodFullLabel: String
    public let isAnnual: Bool

    @Environment(\.colorScheme) private var colorScheme
    @State private var showOthersPopover: Bool = false

    private struct SliceItem: Identifiable {
        let id: String
        let name: String
        let iconSymbol: String
        let colorHex: String
        let total: Double
        let percentage: Double
        let isOthers: Bool
    }

    public init(
        items: [CategorySpendSummary],
        totalExpense: Double,
        periodFullLabel: String,
        isAnnual: Bool
    ) {
        self.items = items
        self.totalExpense = totalExpense
        self.periodFullLabel = periodFullLabel
        self.isAnnual = isAnnual
    }

    private var topSlices: [SliceItem] {
        let sorted = items.sorted { $0.total > $1.total }
        let top = sorted.prefix(5).map { item in
            SliceItem(
                id: item.id.uuidString,
                name: item.category.name,
                iconSymbol: item.category.iconSymbol,
                colorHex: item.category.colorHex,
                total: item.total,
                percentage: item.percentage,
                isOthers: false
            )
        }
        let rest = sorted.dropFirst(5)
        guard !rest.isEmpty else { return top }

        let othersTotal = rest.reduce(0.0) { $0 + $1.total }
        let othersPercentage = rest.reduce(0.0) { $0 + $1.percentage }
        return top + [
            SliceItem(
                id: "__others__",
                name: "Outros (\(rest.count))",
                iconSymbol: "ellipsis.circle.fill",
                colorHex: "#94A3B8",
                total: othersTotal,
                percentage: othersPercentage,
                isOthers: true
            )
        ]
    }

    private var remainingCategories: [CategorySpendSummary] {
        Array(items.sorted { $0.total > $1.total }.dropFirst(5))
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Despesas por Categoria")
                        .font(.headline)
                    Text(isAnnual ? "Distribuição projetada até \(periodFullLabel)" : "Top categorias em \(periodFullLabel)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !remainingCategories.isEmpty {
                    Button {
                        showOthersPopover.toggle()
                    } label: {
                        HStack(spacing: 4) {
                            Text("Ver todas (\(items.count))")
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9, weight: .bold))
                        }
                    }
                    .buttonStyle(BentoGlassButtonStyle(cornerRadius: 8, verticalPadding: 4, horizontalPadding: 9))
                    .popover(isPresented: $showOthersPopover, arrowEdge: .bottom) {
                        othersCategoriesPopoverContent
                    }
                }
            }

            if items.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "chart.pie")
                        .font(.system(size: 34))
                        .foregroundStyle(.secondary.opacity(0.7))
                    Text(isAnnual ? "Nenhuma despesa registrada ou projetada neste ano." : "Nenhuma despesa registrada neste mês.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 224)
            } else {
                HStack(alignment: .center, spacing: 20) {
                    ZStack {
                        Chart(topSlices) { item in
                            SectorMark(
                                angle: .value("Total", item.total),
                                innerRadius: .ratio(0.74),
                                angularInset: 2.0
                            )
                            .cornerRadius(5)
                            .foregroundStyle(Color(hex: item.colorHex))
                        }
                        .frame(width: 194, height: 194)

                        VStack(spacing: 2) {
                            Text("Total")
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(.secondary)
                            Text(BRLFormatters.currency(totalExpense))
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                                .numericCurrencyTransition(value: totalExpense)
                            Text("\(items.count) categ.")
                                .font(.system(size: 9.5, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 108)
                    }

                    VStack(alignment: .leading, spacing: 9) {
                        ForEach(topSlices) { item in
                            if item.isOthers {
                                Button {
                                    showOthersPopover = true
                                } label: {
                                    categoryLegendRow(item, interactive: true)
                                }
                                .buttonStyle(.plain)
                                .help("Clique para detalhar as \(remainingCategories.count) categorias agrupadas em Outros")
                            } else {
                                categoryLegendRow(item, interactive: false)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 224)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 290, alignment: .topLeading)
        .bentoCard(padding: 18)
    }

    @ViewBuilder
    private func categoryLegendRow(_ item: SliceItem, interactive: Bool) -> some View {
        let itemDisplayColor = item.isOthers
            ? (colorScheme == .dark ? FinSenseTheme.slateLight : Color(hex: "#475569"))
            : Color(hex: item.colorHex)

        HStack(spacing: 8) {
            Circle()
                .fill(item.isOthers ? FinSenseTheme.slateLight : Color(hex: item.colorHex))
                .frame(width: 9, height: 9)
            Image(systemName: item.iconSymbol)
                .font(.system(size: 11.5))
                .foregroundStyle(itemDisplayColor)
                .frame(width: 15)
            Text(item.name)
                .font(.system(size: 12, weight: interactive ? .semibold : .medium))
                .foregroundStyle(interactive ? itemDisplayColor : .primary)
                .lineLimit(1)
            if interactive {
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 10))
                    .foregroundStyle(itemDisplayColor)
            }
            Spacer(minLength: 4)
            Text(String(format: "%.1f%%", item.percentage))
                .font(.system(size: 11, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Text(BRLFormatters.currency(item.total))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .frame(minWidth: 74, alignment: .trailing)
        }
        .padding(.horizontal, interactive ? 6 : 2)
        .padding(.vertical, interactive ? 4 : 2)
        .background(
            interactive
                ? RoundedRectangle(cornerRadius: 7, style: .continuous).fill(FinSenseTheme.glassFill(for: colorScheme))
                : nil
        )
    }

    private var othersCategoriesPopoverContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Demais Categorias (\(remainingCategories.count))")
                    .font(.headline)
                Spacer()
                Text(BRLFormatters.currency(remainingCategories.reduce(0.0) { $0 + $1.total }))
                    .font(.subheadline.bold())
                    .monospacedDigit()
            }
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(remainingCategories) { item in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Color(hex: item.category.colorHex))
                                .frame(width: 9, height: 9)
                            Image(systemName: item.category.iconSymbol)
                                .font(.caption)
                                .foregroundStyle(Color(hex: item.category.colorHex))
                                .frame(width: 16)
                            Text(item.category.name)
                                .font(.caption.weight(.medium))
                            Spacer()
                            Text(String(format: "%.1f%%", item.percentage))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                            Text(BRLFormatters.currency(item.total))
                                .font(.caption.bold())
                                .monospacedDigit()
                        }
                    }
                }
            }
            .frame(maxHeight: 260)
        }
        .padding(14)
        .frame(width: 340)
    }
}

public struct MonthlyCashFlowChartView: View {
    public let points: [MonthlyCashFlowPoint]
    public let isAnnual: Bool
    public let yearStr: String

    @Environment(\.colorScheme) private var colorScheme
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
                        Circle().fill(FinSenseTheme.emerald.opacity(0.85)).frame(width: 8, height: 8)
                        Text("Receitas").font(.caption2).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 4) {
                        Circle().fill(FinSenseTheme.coral.opacity(0.85)).frame(width: 8, height: 8)
                        Text("Despesas").font(.caption2).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(FinSenseTheme.coral.opacity(0.35))
                            .frame(width: 8, height: 8)
                        Text("Previsões & Tetos").font(.caption2).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 4) {
                        Capsule().fill(Color(hex: "#38BDF8")).frame(width: 10, height: 3)
                        Circle().fill(Color(hex: "#38BDF8")).frame(width: 6, height: 6)
                        Text("Saldo Final").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }

            // Hover Tooltip Display no macOS detalhando valores da barra
            if let pt = hoveredPoint {
                HStack(spacing: 10) {
                    Image(systemName: "cursorarrow.rays")
                        .font(.caption)
                        .foregroundStyle(FinSenseTheme.indigo)
                    Text(pt.label)
                        .font(.caption.weight(.bold))
                    Text("•")
                        .foregroundStyle(.secondary.opacity(0.5))
                    Text("Despesas Lançadas: ")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    + Text(BRLFormatters.currency(pt.expense))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(FinSenseTheme.coral)
                    Text("•")
                        .foregroundStyle(.secondary.opacity(0.5))
                    Text("Previsões/Tetos: ")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    + Text(BRLFormatters.currency(pt.remainingProvisions))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(FinSenseTheme.indigo)
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
                        .foregroundStyle(Color(hex: "#38BDF8"))
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(FinSenseTheme.nestedSurface(for: colorScheme))
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
                    .foregroundStyle(
                        LinearGradient(
                            colors: [FinSenseTheme.emerald.opacity(0.92), FinSenseTheme.emerald.opacity(0.55)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .position(by: .value("Tipo", "Receitas"))
                    .cornerRadius(6)

                    // Base sólida: Despesas já lançadas
                    BarMark(
                        x: .value("Mês", pt.label),
                        yStart: .value("Base", 0),
                        yEnd: .value("Valor", pt.expense)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [FinSenseTheme.coral.opacity(0.90), FinSenseTheme.coral.opacity(0.55)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .position(by: .value("Tipo", "Despesas"))
                    .cornerRadius(!pt.isPastMonth && pt.remainingProvisions > 0 ? 0 : 6)

                    // Topo translúcido: Margem de Previsões & Tetos restantes
                    if !pt.isPastMonth && pt.remainingProvisions > 0 {
                        BarMark(
                            x: .value("Mês", pt.label),
                            yStart: .value("Base", pt.expense),
                            yEnd: .value("Valor", pt.totalBudgetedExpense)
                        )
                        .foregroundStyle(FinSenseTheme.coral.opacity(0.28))
                        .position(by: .value("Tipo", "Despesas"))
                        .cornerRadius(6)
                    }

                    // Linha sobreposta e pontos: Evolução do Saldo Final
                    LineMark(
                        x: .value("Mês", pt.label),
                        y: .value("Saldo Final", pt.accumulatedBalance)
                    )
                    .foregroundStyle(Color(hex: "#38BDF8"))
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))

                    PointMark(
                        x: .value("Mês", pt.label),
                        y: .value("Saldo Final", pt.accumulatedBalance)
                    )
                    .foregroundStyle(Color(hex: "#38BDF8"))
                    .symbolSize(34)
                }
            }
            .chartYAxis {
                let axisLabelColor = colorScheme == .dark ? Color.white.opacity(0.55) : Color.black.opacity(0.55)
                AxisMarks(position: .leading) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6, dash: [3, 4]))
                        .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.08))
                    if let num = value.as(Double.self) {
                        AxisValueLabel {
                            Text(Self.formatAxisNumber(num))
                                .font(.system(size: 10, design: .rounded))
                                .foregroundStyle(axisLabelColor)
                                .monospacedDigit()
                        }
                    }
                }
            }
            .chartXAxis {
                let axisLabelColor = colorScheme == .dark ? Color.white.opacity(0.55) : Color.black.opacity(0.55)
                AxisMarks { value in
                    if let label = value.as(String.self) {
                        AxisValueLabel {
                            Text(label)
                                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                                .foregroundStyle(axisLabelColor)
                        }
                    }
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
        .frame(maxWidth: .infinity, minHeight: 290, alignment: .topLeading)
        .bentoCard(padding: 18)
    }

    private static let axisNumberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    private static func formatAxisNumber(_ value: Double) -> String {
        axisNumberFormatter.string(from: NSNumber(value: value)) ?? "\(Int(value.rounded()))"
    }
}

// MARK: - Painel Analítico: Comprometimento de Renda vs. Obrigações (Fluxo / DTI)

public struct DebtCommitmentsDonutChartView: View {
    public let breakdown: PeriodDebtServiceBreakdown
    @Environment(\.colorScheme) private var colorScheme

    public struct DonutSegment: Identifiable, Hashable {
        public let id: String
        public let name: String
        public let amount: Double
        public let color: Color
        public let icon: String
        public let isFreeMargin: Bool
        public let isDeficit: Bool

        public init(
            id: String,
            name: String,
            amount: Double,
            color: Color,
            icon: String,
            isFreeMargin: Bool = false,
            isDeficit: Bool = false
        ) {
            self.id = id
            self.name = name
            self.amount = amount
            self.color = color
            self.icon = icon
            self.isFreeMargin = isFreeMargin
            self.isDeficit = isDeficit
        }
    }

    public init(breakdown: PeriodDebtServiceBreakdown) {
        self.breakdown = breakdown
    }

    /// Ordem estrita de renderização:
    /// Receita (Livre) -> Parcelas de Empréstimo -> Parcelas de Financiamento -> Custo de Vida Operacional
    private var segments: [DonutSegment] {
        var list: [DonutSegment] = []

        // 1. Receita (Margem Livre / Poupança)
        if breakdown.freeMargin > 0.001 {
            list.append(DonutSegment(
                id: "revenue",
                name: breakdown.isAnnual ? "Receita Livre do Ano" : "Receita Livre do Mês",
                amount: breakdown.freeMargin,
                color: Color(hex: "#10B981"),
                icon: "shield.fill",
                isFreeMargin: true
            ))
        }

        // 2. Parcelas de Empréstimo
        if breakdown.loanInstallments > 0.001 {
            list.append(DonutSegment(
                id: "loans",
                name: breakdown.isAnnual ? "Parcelas de Empréstimos (Ano)" : "Parcelas de Empréstimos",
                amount: breakdown.loanInstallments,
                color: Color(hex: "#F97316"),
                icon: "banknote.fill"
            ))
        }

        // 3. Parcelas de Financiamento
        if breakdown.financingInstallments > 0.001 {
            list.append(DonutSegment(
                id: "financing",
                name: breakdown.isAnnual ? "Parcelas de Financiamentos (Ano)" : "Parcelas de Financiamentos",
                amount: breakdown.financingInstallments,
                color: Color(hex: "#C2410C"),
                icon: "house.fill"
            ))
        }

        // Parcelas de Acordos / Dívidas (se houver ativas no período)
        if breakdown.debtInstallments > 0.001 {
            list.append(DonutSegment(
                id: "debts",
                name: breakdown.isAnnual ? "Parcelas Acordos / Dívidas (Ano)" : "Parcelas Acordos / Dívidas",
                amount: breakdown.debtInstallments,
                color: Color(hex: "#E11D48"),
                icon: "exclamationmark.triangle.fill"
            ))
        }

        // 4. Custo de Vida Operacional
        if breakdown.operationalExpenses > 0.001 {
            list.append(DonutSegment(
                id: "operational",
                name: breakdown.isAnnual ? "Custo de Vida Operacional (Ano)" : "Custo de Vida Operacional",
                amount: breakdown.operationalExpenses,
                color: Color(hex: "#0284C7"),
                icon: "cart.fill"
            ))
        }

        // Déficit Operacional (se as saídas ultrapassarem a receita)
        if breakdown.deficit > 0.001 {
            list.append(DonutSegment(
                id: "deficit",
                name: breakdown.isAnnual ? "Déficit Orçamentário (Ano)" : "Déficit Orçamentário",
                amount: breakdown.deficit,
                color: Color(hex: "#EF4444"),
                icon: "exclamationmark.octagon.fill",
                isDeficit: true
            ))
        }

        return list
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header interno
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Image(systemName: "chart.pie.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color(hex: "#6366F1"))
                        Text("Distribuição de Compromissos vs Receitas")
                            .font(.subheadline.weight(.bold))
                    }
                    Text(
                        breakdown.isAnnual
                            ? "Fatiamento da receita anual de \(breakdown.yearStr) entre receita livre, empréstimos, financiamentos e custo de vida"
                            : "Fatiamento da receita mensal entre receita livre, empréstimos, financiamentos e custo de vida"
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                // Badge de Nível de Comprometimento / Risco
                HStack(spacing: 5) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 7, height: 7)
                    Text(statusText)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(statusColor)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(statusColor.opacity(0.12))
                .clipShape(Capsule())
            }

            if segments.isEmpty && breakdown.periodIncome <= 0 {
                VStack(spacing: 8) {
                    Image(systemName: "chart.pie")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary.opacity(0.5))
                    Text(breakdown.isAnnual ? "Nenhuma movimentação financeira ou receita registrada em \(breakdown.yearStr)." : "Nenhuma movimentação financeira ou receita registrada neste mês.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                HStack(alignment: .center, spacing: 22) {
                    // Donut Chart (Ordem: Receita -> Empréstimos -> Financiamentos -> Custo de Vida)
                    ZStack {
                        Chart(segments) { item in
                            SectorMark(
                                angle: .value("Valor", item.amount),
                                innerRadius: .ratio(0.66),
                                angularInset: 2.5
                            )
                            .cornerRadius(4)
                            .foregroundStyle(item.color)
                        }
                        .frame(width: 196, height: 196)

                        // Center Overlay (Indicador Central de Saúde)
                        VStack(spacing: 2) {
                            if breakdown.deficit > 0.001 {
                                Text(breakdown.isAnnual ? "Déficit Anual" : "Déficit Mensal")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(Color(hex: "#EF4444"))
                                    .lineLimit(1)

                                Text("-" + BRLFormatters.currency(breakdown.deficit))
                                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                                    .foregroundStyle(Color(hex: "#EF4444"))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                                    .monospacedDigit()

                                let excessPct = (breakdown.deficit / max(breakdown.periodIncome, 1.0)) * 100.0
                                Text(String(format: "+%.1f%% da receita", excessPct))
                                    .font(.caption.bold())
                                    .foregroundStyle(Color(hex: "#EF4444"))
                                    .lineLimit(1)

                                Text("DTI: \(String(format: "%.1f%%", breakdown.debtToIncomeRatio))")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            } else {
                                Text(breakdown.isAnnual ? "Margem Livre Anual" : "Margem Livre Mensal")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)

                                Text(BRLFormatters.currency(breakdown.freeMargin))
                                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                                    .foregroundStyle(Color(hex: "#10B981"))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                                    .monospacedDigit()

                                let freePct = breakdown.periodIncome > 0 ? (breakdown.freeMargin / breakdown.periodIncome) * 100.0 : 0.0
                                Text(String(format: "%.1f%% receita livre", freePct))
                                    .font(.caption.bold())
                                    .foregroundStyle(Color(hex: "#10B981"))
                                    .lineLimit(1)

                                Text("DTI: \(String(format: "%.1f%%", breakdown.debtToIncomeRatio))")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .padding(6)
                    }
                    .frame(width: 196, height: 196)

                    // Right Breakdown Panel (3 Mini Cards Equalizados em Altura + Lista Detalhada)
                    VStack(alignment: .leading, spacing: 9) {
                        // 3 Mini Cards Comparativos de Fluxo (Alturas Estritamente Equalizadas)
                        HStack(spacing: 8) {
                            miniMetricBox(
                                title: breakdown.isAnnual ? "Receita do Ano" : "Receita do Mês",
                                value: BRLFormatters.currency(breakdown.periodIncome),
                                color: Color(hex: "#10B981"),
                                icon: "arrow.down.left.circle.fill",
                                subtitle: breakdown.periodIncome > 0 ? "100% da base" : "Sem receitas"
                            )

                            miniMetricBox(
                                title: "Serviço da Dívida (DTI)",
                                value: BRLFormatters.currency(breakdown.totalDebtService),
                                color: breakdown.debtToIncomeRatio > 50 ? Color(hex: "#EF4444") : (breakdown.debtToIncomeRatio > 30 ? Color(hex: "#F97316") : Color(hex: "#10B981")),
                                icon: "creditcard.fill",
                                subtitle: String(format: "DTI: %.1f%% da renda", breakdown.debtToIncomeRatio)
                            )

                            miniMetricBox(
                                title: breakdown.deficit > 0 ? "Déficit Orçamentário" : "Margem Livre",
                                value: BRLFormatters.currency(breakdown.deficit > 0 ? breakdown.deficit : breakdown.freeMargin),
                                color: breakdown.deficit > 0 ? Color(hex: "#EF4444") : Color(hex: "#10B981"),
                                icon: breakdown.deficit > 0 ? "xmark.octagon.fill" : "checkmark.shield.fill",
                                subtitle: breakdown.deficit > 0
                                    ? String(format: "+%.1f%% s/ receita", (breakdown.deficit / max(breakdown.periodIncome, 1.0)) * 100.0)
                                    : String(format: "%.1f%% da receita", breakdown.periodIncome > 0 ? (breakdown.freeMargin / breakdown.periodIncome) * 100.0 : 0.0)
                            )
                        }

                        // Lista Detalhada com Barras Horizontais Proporcionais (Na mesma ordem do gráfico)
                        VStack(spacing: 10) {
                            ForEach(segments) { item in
                                distributionRow(item: item)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .animation(.easeInOut(duration: 0.28), value: breakdown)
    }

    @ViewBuilder
    private func distributionRow(item: DonutSegment) -> some View {
        let pctOfIncome: Double = {
            guard breakdown.periodIncome > 0 else { return 0.0 }
            return (item.amount / breakdown.periodIncome) * 100.0
        }()
        let progressRatio: Double = {
            guard breakdown.periodIncome > 0 else { return 0.0 }
            return min(max(item.amount / breakdown.periodIncome, 0.0), 1.0)
        }()
        let neutralCardBg = colorScheme == .dark ? Color(hex: "#18181B") : FinSenseTheme.nestedSurface(for: colorScheme)
        let neutralBorder = colorScheme == .dark ? Color.white.opacity(0.07) : Color.black.opacity(0.07)
        let neutralMutedText = colorScheme == .dark ? Color.white.opacity(0.55) : Color.secondary

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                // Ícone colorido temático
                Image(systemName: item.icon)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(item.color)
                    .frame(width: 18, height: 18)

                // Título
                Text(item.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 6)

                // Percentual em cinza neutro
                if breakdown.periodIncome > 0 {
                    Text(
                        item.isDeficit
                            ? String(format: "+%.1f%% acima da receita", pctOfIncome)
                            : String(format: "%.1f%% da receita", pctOfIncome)
                    )
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(item.isDeficit ? FinSenseTheme.coral : neutralMutedText)
                }

                // Valor Monetário em branco puro (dark) / primary (light) com .monospacedDigit()
                Text(item.isDeficit ? ("-" + BRLFormatters.currency(item.amount)) : BRLFormatters.currency(item.amount))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(colorScheme == .dark ? Color.white : Color.primary)
            }

            // Barra Horizontal Proporcional (com cor temática)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.06))
                        .frame(height: 4)

                    Capsule()
                        .fill(item.color)
                        .frame(
                            width: max(geo.size.width * progressRatio, progressRatio > 0 ? 4 : 0),
                            height: 4
                        )
                }
            }
            .frame(height: 4)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(neutralCardBg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(neutralBorder, lineWidth: FinSenseTheme.hairlineWidth)
        )
    }

    private func miniMetricBox(
        title: String,
        value: String,
        color: Color,
        icon: String,
        subtitle: String
    ) -> some View {
        let neutralBoxBg = colorScheme == .dark ? Color(hex: "#18181B") : FinSenseTheme.nestedSurface(for: colorScheme)
        let neutralBorder = colorScheme == .dark ? Color.white.opacity(0.07) : Color.black.opacity(0.07)
        let neutralMutedText = colorScheme == .dark ? Color.white.opacity(0.55) : Color.secondary

        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(color)
                Text(title)
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(neutralMutedText)
                    .lineLimit(1)
            }

            Text(value)
                .font(.system(size: 12.5, weight: .bold, design: .rounded))
                .foregroundStyle(colorScheme == .dark ? Color.white : Color.primary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(subtitle)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(neutralMutedText)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 62, maxHeight: 62, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(neutralBoxBg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(neutralBorder, lineWidth: FinSenseTheme.hairlineWidth)
        )
    }

    private var statusColor: Color {
        if breakdown.deficit > 0.001 {
            return Color(hex: "#EF4444")
        } else if breakdown.debtToIncomeRatio <= 30.0 {
            return Color(hex: "#10B981")
        } else if breakdown.debtToIncomeRatio <= 50.0 {
            return Color(hex: "#F97316")
        } else {
            return Color(hex: "#EF4444")
        }
    }

    private var statusText: String {
        if breakdown.deficit > 0.001 {
            let excessPct = breakdown.periodIncome > 0 ? (breakdown.totalOutflows / breakdown.periodIncome) * 100.0 : 100.0
            return breakdown.isAnnual
                ? "Déficit Anual (\(String(format: "%.0f%%", excessPct)) da receita)"
                : "Déficit Mensal (\(String(format: "%.0f%%", excessPct)) da receita)"
        } else if breakdown.debtToIncomeRatio <= 30.0 {
            return breakdown.isAnnual
                ? "DTI Saudável (\(String(format: "%.1f%%", breakdown.debtToIncomeRatio)) a.a.)"
                : "DTI Saudável (\(String(format: "%.1f%%", breakdown.debtToIncomeRatio)) da renda)"
        } else if breakdown.debtToIncomeRatio <= 50.0 {
            return breakdown.isAnnual
                ? "DTI em Atenção (\(String(format: "%.1f%%", breakdown.debtToIncomeRatio)) a.a.)"
                : "DTI em Atenção (\(String(format: "%.1f%%", breakdown.debtToIncomeRatio)) da renda)"
        } else {
            return breakdown.isAnnual
                ? "DTI Crítico (\(String(format: "%.1f%%", breakdown.debtToIncomeRatio)) a.a.)"
                : "DTI Crítico (\(String(format: "%.1f%%", breakdown.debtToIncomeRatio)) da renda)"
        }
    }
}

// MARK: - Dashboard Top 6 KPI Cards View

public struct DashboardTopKPICardsView: View {
    public let summary: UnifiedFinancialKPISummary
    public let isAnnual: Bool
    public var intraMonthAnalysis: IntraMonthCashFlowAnalysis?
    public var sinkingFundsReserve: Double
    public var onEditProvisions: () -> Void
    public var onOpenTransactions: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    public init(
        summary: UnifiedFinancialKPISummary,
        isAnnual: Bool,
        intraMonthAnalysis: IntraMonthCashFlowAnalysis? = nil,
        sinkingFundsReserve: Double = 0.0,
        onEditProvisions: @escaping () -> Void,
        onOpenTransactions: @escaping () -> Void = {}
    ) {
        self.summary = summary
        self.isAnnual = isAnnual
        self.intraMonthAnalysis = intraMonthAnalysis
        self.sinkingFundsReserve = sinkingFundsReserve
        self.onEditProvisions = onEditProvisions
        self.onOpenTransactions = onOpenTransactions
    }

    public var body: some View {
        let projectedBalanceValue = summary.isPast
            ? summary.projectedAccountBalance
            : summary.balanceIfAllBudgetsConsumed

        let cardAlertLevel: IntraMonthAlertLevel = summary.isPast ? .none : (intraMonthAnalysis?.alertLevel ?? .none)
        let projectedBalanceTint: Color = {
            if cardAlertLevel == .confirmedDeficit || projectedBalanceValue < 0 { return FinSenseTheme.coral }
            if cardAlertLevel == .possibleRisk { return FinSenseTheme.amber }
            return FinSenseTheme.emerald
        }()

        let accountIcon: String = {
            switch cardAlertLevel {
            case .confirmedDeficit: return "exclamationmark.triangle.fill"
            case .possibleRisk: return "exclamationmark.circle.fill"
            case .none: return summary.isPast ? "checkmark.seal.fill" : "building.columns.fill"
            }
        }()

        let despesasSub = MetricCardView.despesasLancadasSubtitle(
            paidExpense: summary.paidExpense,
            pendingExpense: summary.pendingExpense,
            isPast: summary.isPast,
            isAnnual: isAnnual
        )

        let budgetSubtitle: String = {
            if summary.isPast {
                return "Período fechado (sem orçamentos)"
            }
            if summary.hasBudgetOverrun {
                return "Estouro: \(BRLFormatters.currency(summary.totalBudgetsOverrun))"
            }
            if sinkingFundsReserve > 0.01 {
                return "Tetos: \(BRLFormatters.currency(summary.categoryCeilingsRemaining)) • Cotas: \(BRLFormatters.currency(summary.specificQuotasRemaining)) • Caixinhas: \(BRLFormatters.currency(sinkingFundsReserve))"
            }
            return "Tetos: \(BRLFormatters.currency(summary.categoryCeilingsRemaining)) • Cotas: \(BRLFormatters.currency(summary.specificQuotasRemaining))"
        }()

        let surplusTint: Color = {
            if summary.surplusAfterPlanning > 0 { return FinSenseTheme.emerald }
            if summary.surplusAfterPlanning < 0 { return FinSenseTheme.coral }
            return Color(hex: "#64748B")
        }()

        let surplusSubtitle: String = {
            if summary.surplusAfterPlanning > 0 {
                return "Superávit após despesas e tetos"
            } else if summary.surplusAfterPlanning < 0 {
                return "Déficit de \(BRLFormatters.currency(abs(summary.surplusAfterPlanning)))"
            } else {
                return "Equilíbrio exato (R$ 0)"
            }
        }()

        HStack(alignment: .top, spacing: 14) {
            // MARK: Left Hero Card (~42% width) — Saldo Previsto na Conta + Sparkline + Vale Intramês
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 8) {
                    Text(summary.projectedAccountBalanceTitle)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    ZStack {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(projectedBalanceTint.opacity(colorScheme == .dark ? 0.16 : 0.12))
                            .frame(width: 30, height: 30)
                        Image(systemName: accountIcon)
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(projectedBalanceTint)
                    }
                }

                Text(BRLFormatters.currency(projectedBalanceValue))
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(projectedBalanceValue < 0 ? FinSenseTheme.coral : .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .numericCurrencyTransition(value: projectedBalanceValue)

                if summary.isPast {
                    Text("Saldo final histórico conciliado")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                } else {
                    (
                        Text("Se não usar o orçamento: ")
                            .foregroundColor(.secondary)
                        + Text(BRLFormatters.currency(summary.projectedAccountBalance))
                            .fontWeight(.semibold)
                            .foregroundColor(summary.projectedAccountBalance >= 0 ? FinSenseTheme.emerald : FinSenseTheme.coral)
                    )
                    .font(.system(size: 12))
                }

                if let intra = intraMonthAnalysis, !summary.isPast, !intra.dailyPoints.isEmpty {
                    IntraMonthSparklineView(analysis: intra, height: 52)
                        .padding(.top, 2)
                } else {
                    Spacer(minLength: 8)
                }

                Spacer(minLength: 0)

                // Hero Inline Footer Pill (Vale Intramês / Status Conciliado)
                if !summary.isPast, cardAlertLevel != .none, let intra = intraMonthAnalysis {
                    let pillColor = cardAlertLevel == .confirmedDeficit ? FinSenseTheme.coral : FinSenseTheme.amber
                    Button(action: onOpenTransactions) {
                        HStack(spacing: 8) {
                            Image(systemName: cardAlertLevel == .confirmedDeficit ? "exclamationmark.triangle.fill" : "exclamationmark.circle.fill")
                                .font(.system(size: 11.5, weight: .bold))
                                .foregroundStyle(pillColor)
                            Text(intra.alertSummaryText ?? (cardAlertLevel == .confirmedDeficit ? "Vale intramês detectado" : "Possível déficit por previsões"))
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(pillColor)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 4)
                            Text(cardAlertLevel == .confirmedDeficit ? "Ver Corte →" : "Lançamentos →")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(pillColor)
                        }
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(pillColor.opacity(colorScheme == .dark ? 0.14 : 0.10))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(pillColor.opacity(0.32), lineWidth: 0.75)
                        )
                    }
                    .buttonStyle(.plain)
                    .help(
                        cardAlertLevel == .confirmedDeficit
                            ? "Menor saldo projetado por transações: \(BRLFormatters.currency(intra.minimumBalance))"
                            : "Com previsões: \(BRLFormatters.currency(intra.closingBalanceWithProvisions))"
                    )
                } else {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(projectedBalanceTint)
                            .frame(width: 6, height: 6)
                        Text(
                            summary.isPast
                                ? "Resultado final registrado"
                                : (projectedBalanceValue < 0 ? "Alerta: Risco de caixa negativo" : "Caixa intramês saudável")
                        )
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(summary.isPast ? Color.secondary : projectedBalanceTint)
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(FinSenseTheme.nestedSurface(for: colorScheme))
                    )
                }
            }
            .frame(minWidth: 330, idealWidth: 400, maxWidth: 460, minHeight: 256, alignment: .topLeading)
            .bentoCard(padding: 18, cornerRadius: FinSenseTheme.cardCornerRadius, accent: projectedBalanceTint, isHighlighted: true)

            // MARK: Right Asymmetric 5-KPI Bento Grid (~58% width)
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    MetricCardView(
                        title: isAnnual ? "Receitas Previstas (Ano)" : "Receitas Previstas",
                        value: BRLFormatters.currency(summary.projectedIncome),
                        subtitle: summary.isPast
                            ? "\(BRLFormatters.currency(summary.receivedIncome)) recebidos"
                            : "\(BRLFormatters.currency(summary.receivedIncome)) recebidos • \(BRLFormatters.currency(summary.pendingIncome)) a receber",
                        icon: "arrow.down.left.circle.fill",
                        tint: FinSenseTheme.emerald,
                        footnote: summary.extraordinaryIncome > 0
                            ? "Habitual: \(BRLFormatters.currency(summary.habitualIncome)) • Extra: \(BRLFormatters.currency(summary.extraordinaryIncome))"
                            : nil,
                        footnoteColor: FinSenseTheme.indigo,
                        cardHeight: 122
                    )

                    MetricCardView(
                        title: isAnnual ? "Despesas Lançadas (Ano)" : "Despesas Lançadas",
                        value: BRLFormatters.currency(summary.recordedExpense),
                        subtitle: despesasSub.text,
                        customSubtitle: despesasSub.styled,
                        icon: "arrow.up.right.circle.fill",
                        tint: FinSenseTheme.coral,
                        cardHeight: 122
                    )
                }

                HStack(spacing: 12) {
                    MetricCardView(
                        title: isAnnual ? "Orçamentos Restantes" : "Orçamentos & Cotas",
                        value: BRLFormatters.currency(summary.remainingBudgetsAndQuotas),
                        subtitle: budgetSubtitle,
                        icon: "tray.full.fill",
                        tint: summary.hasBudgetOverrun ? FinSenseTheme.coral : FinSenseTheme.cyan,
                        footnote: summary.isPast ? nil : (summary.hasBudgetOverrun ? "Orçamento excedido" : "Reservado para consumo"),
                        footnoteColor: summary.hasBudgetOverrun ? FinSenseTheme.coral : .secondary,
                        action: onEditProvisions,
                        actionLabel: "Ver",
                        actionIcon: "pencil",
                        cardHeight: 122
                    )

                    MetricCardView(
                        title: isAnnual ? "Gastos Planejados (Ano)" : "Gastos Planejados",
                        value: BRLFormatters.currency(summary.totalPlannedExpenses),
                        subtitle: summary.isPast
                            ? "Gastos consolidados realizados"
                            : "\(BRLFormatters.currency(summary.recordedExpense)) lançados + \(BRLFormatters.currency(summary.remainingBudgetsAndQuotas)) orçados",
                        icon: "chart.bar.doc.horizontal.fill",
                        tint: FinSenseTheme.cyan,
                        footnote: summary.isPast ? nil : "Teto máximo planejado",
                        footnoteColor: .secondary,
                        cardHeight: 122
                    )

                    MetricCardView(
                        title: isAnnual ? "Sobra Planejada (Ano)" : "Sobra Planejada",
                        value: BRLFormatters.currency(summary.surplusAfterPlanning),
                        valueColor: summary.surplusAfterPlanning < 0 ? FinSenseTheme.coral : nil,
                        subtitle: surplusSubtitle,
                        icon: summary.surplusAfterPlanning >= 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                        tint: surplusTint,
                        footnote: summary.surplusAfterPlanning >= 0 ? "Sustentável" : "Déficit planejado",
                        footnoteColor: surplusTint,
                        cardHeight: 122
                    )
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}
