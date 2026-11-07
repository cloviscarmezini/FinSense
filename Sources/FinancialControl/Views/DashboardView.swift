import SwiftUI
import Charts

public struct DashboardView: View {
    @ObservedObject public var store: FinancialDataStore
    @ObservedObject public var llmService: LocalLLMService

    @State private var showCreateExpenseSheet: Bool = false
    @State private var showCreateIncomeSheet: Bool = false
    @State private var showImportStatementSheet: Bool = false
    @State private var showProvisionsSheet: Bool = false

    public init(store: FinancialDataStore, llmService: LocalLLMService) {
        self.store = store
        self.llmService = llmService
    }

    public var body: some View {
        let isAnnual = store.dashboardPeriodMode == .annual
        let yearStr = BRLFormatters.yearString(store.selectedMonth)
        let periodLabel = isAnnual
            ? "Ano \(yearStr)"
            : BRLFormatters.shortMonthYearFormatter.string(from: store.selectedMonth).capitalized
        let periodFullLabel = isAnnual
            ? "31/12/\(yearStr)"
            : BRLFormatters.monthYear(store.selectedMonth)

        let periodIncome = isAnnual
            ? store.annualIncome(for: store.selectedMonth)
            : store.monthlyIncome(for: store.selectedMonth)
        let periodExpense = isAnnual
            ? store.annualExpense(for: store.selectedMonth)
            : store.monthlyExpense(for: store.selectedMonth)
        let periodNet = periodIncome - periodExpense
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
        let remainingProvisionsTotal = store.totalRemainingProvision(for: store.selectedMonth)
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

                // MARK: - Top KPI Cards
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 4), spacing: 14) {
                    MetricCardView(
                        title: "Patrimônio Consolidado",
                        value: BRLFormatters.currency(store.totalConsolidatedPatrimonyNow),
                        subtitle: "Contas (\(BRLFormatters.currency(store.totalCheckingBalanceNow))) + Invest. Consolidados (\(BRLFormatters.currency(store.consolidatedInvestmentsBalance)))",
                        icon: "building.columns.fill",
                        tint: Color(hex: "#3B82F6")
                    )

                    MetricCardView(
                        title: "Receitas (\(periodLabel))",
                        value: BRLFormatters.currency(periodIncome),
                        subtitle: isAnnual ? "Entradas projetadas até 31/12/\(yearStr)" : "Entradas consolidadas no mês",
                        icon: "arrow.down.left.circle.fill",
                        tint: Color(hex: "#10B981")
                    )

                    MetricCardView(
                        title: "Despesas (\(periodLabel))",
                        value: BRLFormatters.currency(periodExpense),
                        subtitle: isAnnual ? "Saídas projetadas até 31/12/\(yearStr)" : "Saídas consolidadas no mês",
                        icon: "arrow.up.right.circle.fill",
                        tint: Color(hex: "#EF4444")
                    )

                    MetricCardView(
                        title: isAnnual ? "Acumulado em 31/12/\(yearStr)" : "Saldo Projetado no Mês",
                        value: BRLFormatters.currency(accumulatedBalance),
                        subtitle: isAnnual ? "Balanço anual projetado: \(BRLFormatters.currency(periodNet))" : "Balanço mensal: \(BRLFormatters.currency(periodNet))",
                        icon: "chart.line.uptrend.xyaxis",
                        tint: periodNet >= 0 ? Color(hex: "#10B981") : Color(hex: "#F59E0B"),
                        footnote: (!isAnnual && !monthEnvelopes.isEmpty)
                            ? "Provisão de Gastos Variáveis: \(BRLFormatters.currency(remainingProvisionsTotal)) restantes"
                            : nil,
                        footnoteColor: remainingProvisionsTotal > 0 ? Color(hex: "#6366F1") : .secondary
                    )
                }

                // MARK: - Previsões & Tetos do Mês (Orçamento por Envelopes Dinâmicos)
                if !isAnnual {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .center, spacing: 12) {
                            HStack(spacing: 8) {
                                Image(systemName: "tray.full.fill")
                                    .foregroundStyle(Color(hex: "#6366F1"))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Previsões & Tetos do Mês")
                                        .font(.headline)
                                    Text("Orçamento por envelopes dinâmicos em \(periodFullLabel) (abatimento em tempo real sem gerar transações fictícias)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer()

                            if !monthEnvelopes.isEmpty {
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
                                        Text("Provisão de Gastos Variáveis")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                        Text("\(BRLFormatters.currency(remainingProvisionsTotal)) restantes")
                                            .font(.subheadline.bold())
                                            .foregroundStyle(Color(hex: "#6366F1"))
                                    }
                                }
                            }

                            Button {
                                showProvisionsSheet = true
                            } label: {
                                Label(
                                    monthEnvelopes.isEmpty ? "Configurar Previsões" : "Editar Tetos",
                                    systemImage: "slider.horizontal.3"
                                )
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Color(hex: "#6366F1"))
                            .controlSize(.small)
                        }

                        if monthEnvelopes.isEmpty {
                            HStack(spacing: 12) {
                                Image(systemName: "sparkles.rectangle.stack")
                                    .font(.system(size: 22))
                                    .foregroundStyle(Color(hex: "#6366F1").opacity(0.8))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Nenhum teto estimado configurado para \(periodFullLabel).")
                                        .font(.subheadline.weight(.medium))
                                    Text("Defina limites para categorias variáveis (ex: Combustível, Alimentação, Lazer) ou peça no Chat IA: \"Reserve R$ 500 para gasolina este mês\".")
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
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                                ForEach(monthEnvelopes) { env in
                                    provisionEnvelopeCard(env)
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

                    // Chart 2: Evolução de Receitas vs Despesas e Acumulado
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
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
                            }
                        }

                        Chart {
                            ForEach(cashFlowPoints) { pt in
                                BarMark(
                                    x: .value("Mês", pt.label),
                                    y: .value("Valor", pt.income)
                                )
                                .foregroundStyle(Color(hex: "#10B981"))
                                .position(by: .value("Tipo", "Receitas"))
                                .cornerRadius(4)

                                BarMark(
                                    x: .value("Mês", pt.label),
                                    y: .value("Valor", pt.expense)
                                )
                                .foregroundStyle(Color(hex: "#EF4444"))
                                .position(by: .value("Tipo", "Despesas"))
                                .cornerRadius(4)
                            }
                        }
                        .frame(height: 205)
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
                            colorHex: "#D97706",
                            icon: "banknote.fill"
                        )
                        debtPillarCard(
                            title: "Financiamentos",
                            subtitle: "\(debtSummary.activeFinancings.count) contrato(s) (Imóvel/Carro)",
                            amount: debtSummary.financingsRemainingNominalTotal,
                            projected: debtSummary.financingsProjectedPayoffTotal,
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
                        if env.provision.repeatForFutureMonths {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .help("Repetir automaticamente para os próximos meses")
                        }
                    }
                    Text("Gasto Real: \(BRLFormatters.currency(env.realizedExpense)) de \(BRLFormatters.currency(env.estimatedAmount))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Text(env.status.rawValue)
                    .font(.system(size: 10.5, weight: .bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color(hex: statusColorHex).opacity(0.15)))
                    .foregroundStyle(Color(hex: statusColorHex))
            }

            // Progress Bar: min(100, (G_real / T_estimado) * 100)
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

                if env.status == .exceeded {
                    Text("Excedente: +\(BRLFormatters.currency(env.exceededAmount))")
                        .font(.caption2.bold())
                        .foregroundStyle(Color(hex: "#EF4444"))
                } else {
                    Text("Restante: \(BRLFormatters.currency(env.remainingProvision))")
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
            if let projected, abs(amount - projected) > 0.01 {
                Text("Quitar: \(BRLFormatters.currency(projected))")
                    .font(.caption2.bold())
                    .foregroundStyle(Color(hex: "#10B981"))
                    .lineLimit(1)
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

// MARK: - Modal: Previsões & Tetos do Mês (Orçamento por Envelopes Dinâmicos)

public struct MonthlyProvisionsSheet: View {
    @ObservedObject public var store: FinancialDataStore
    @Environment(\.dismiss) private var dismiss

    private struct DraftProvisionItem: Identifiable {
        var id: UUID { category.id }
        let category: CategoryItem
        let realizedExpense: Double
        var amountString: String
        var repeatForFutureMonths: Bool
        var wasInitiallyActive: Bool
    }

    @State private var draftItems: [DraftProvisionItem] = []
    @State private var globalRepeatToggle: Bool = true

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
                    Text("Defina tetos de gastos variáveis para \(monthTitle) sem criar lançamentos fictícios no extrato")
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
                        Text("Repetir esta previsão para os próximos meses")
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

                Text("Deixe em R$ 0,00 ou vazio para categorias sem teto estimado.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color.primary.opacity(0.03))

            Divider()

            // Category List
            ScrollView {
                VStack(spacing: 10) {
                    ForEach($draftItems) { $item in
                        let parsedEstimated = BRLFormatters.parseCurrencyInput(item.amountString)
                        let remaining = max(0.0, parsedEstimated - item.realizedExpense)

                        HStack(spacing: 14) {
                            CategoryBadgeView(category: item.category, size: 36)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.category.name)
                                    .font(.subheadline.weight(.semibold))
                                HStack(spacing: 8) {
                                    Text("Gasto realizado no mês: \(BRLFormatters.currency(item.realizedExpense))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    if parsedEstimated > 0 {
                                        Text("• Restante projetado: \(BRLFormatters.currency(remaining))")
                                            .font(.caption.weight(.medium))
                                            .foregroundStyle(
                                                item.realizedExpense >= parsedEstimated
                                                    ? Color(hex: "#EF4444")
                                                    : Color(hex: "#6366F1")
                                            )
                                    }
                                }
                            }

                            Spacer()

                            Toggle("Repetir esta previsão para os próximos meses", isOn: $item.repeatForFutureMonths)
                                .toggleStyle(.checkbox)
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            HStack(spacing: 6) {
                                Text("R$")
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
                                TextField("0,00", text: $item.amountString)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 110)
                                    .multilineTextAlignment(.trailing)
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
                                    parsedEstimated > 0
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
            let totalEstimatedDraft = draftItems.reduce(0.0) {
                $0 + max(0.0, BRLFormatters.parseCurrencyInput($1.amountString))
            }
            let totalRemainingDraft = draftItems.reduce(0.0) { acc, item in
                let est = max(0.0, BRLFormatters.parseCurrencyInput(item.amountString))
                guard est > 0 else { return acc }
                return acc + max(0.0, est - item.realizedExpense)
            }

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Total Orçado: \(BRLFormatters.currency(totalEstimatedDraft))")
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
                    saveProvisions()
                    dismiss()
                } label: {
                    Label("Salvar Previsões", systemImage: "checkmark.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(hex: "#6366F1"))
                .keyboardShortcut(.defaultAction)
            }
            .padding(20)
        }
        .frame(minWidth: 740, minHeight: 540)
        .onAppear {
            loadDrafts()
        }
    }

    private func loadDrafts() {
        let monthRef = store.selectedMonth
        draftItems = store.expenseCategories.map { cat in
            let realized = store.realizedMonthlyExpense(forCategory: cat.id, in: monthRef)
            if let effective = store.effectiveProvision(forCategory: cat.id, in: monthRef) {
                return DraftProvisionItem(
                    category: cat,
                    realizedExpense: realized,
                    amountString: String(format: "%.2f", effective.provision.estimatedAmount).replacingOccurrences(of: ".", with: ","),
                    repeatForFutureMonths: effective.provision.repeatForFutureMonths,
                    wasInitiallyActive: true
                )
            } else {
                return DraftProvisionItem(
                    category: cat,
                    realizedExpense: realized,
                    amountString: "",
                    repeatForFutureMonths: true,
                    wasInitiallyActive: false
                )
            }
        }
    }

    private func saveProvisions() {
        let monthRef = store.selectedMonth
        for item in draftItems {
            let trimmed = item.amountString.trimmingCharacters(in: .whitespacesAndNewlines)
            let amount = trimmed.isEmpty ? 0.0 : max(0.0, BRLFormatters.parseCurrencyInput(trimmed))
            if amount > 0 || item.wasInitiallyActive {
                store.setCategoryProvision(
                    categoryId: item.category.id,
                    estimatedAmount: amount,
                    for: monthRef,
                    repeatForFutureMonths: item.repeatForFutureMonths
                )
            }
        }
    }
}
