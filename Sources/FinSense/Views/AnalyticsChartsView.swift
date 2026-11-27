import SwiftUI
import Charts

// MARK: - Dedicated Financial Charts & Analytics Center

public enum AnalyticsHorizon: String, CaseIterable, Identifiable {
    case currentMonth = "Mês"
    case last6Months = "6 Meses"
    case currentYear = "Ano"
    case last12Months = "12 Meses"

    public var id: String { rawValue }
}

public enum AnalyticsFlowFilter: String, CaseIterable, Identifiable {
    case all = "Todos"
    case expenses = "Despesas"
    case incomes = "Receitas"

    public var id: String { rawValue }
}

public enum AnalyticsStatusFilter: String, CaseIterable, Identifiable {
    case all = "Efetivados + Previstos"
    case paidOnly = "Somente Efetivados"
    case pendingOnly = "Somente Pendentes"

    public var id: String { rawValue }
}

public enum AnalyticsSourceFilter: Hashable, Identifiable {
    case all
    case account(UUID)
    case creditCard(UUID)

    public var id: String {
        switch self {
        case .all: return "all"
        case .account(let id): return "acc_\(id.uuidString)"
        case .creditCard(let id): return "card_\(id.uuidString)"
        }
    }
}

public enum AnalyticsEvolutionChartType: String, CaseIterable, Identifiable {
    case barsAndLine = "Barras + Saldo"
    case areaTrend = "Área Líquida"

    public var id: String { rawValue }
}

public enum AnalyticsCategoryChartMode: String, CaseIterable, Identifiable {
    case horizontalBars = "Ranking Barras"
    case donut = "Rosca"

    public var id: String { rawValue }
}

public struct AnalyticsChartsView: View {
    @ObservedObject public var store: FinancialDataStore
    @Environment(\.colorScheme) private var colorScheme

    @State private var horizon: AnalyticsHorizon = .last6Months
    @State private var flowFilter: AnalyticsFlowFilter = .all
    @State private var selectedCategoryId: UUID? = nil
    @State private var sourceFilter: AnalyticsSourceFilter = .all
    @State private var statusFilter: AnalyticsStatusFilter = .all
    @State private var evolutionChartType: AnalyticsEvolutionChartType = .barsAndLine
    @State private var categoryChartMode: AnalyticsCategoryChartMode = .horizontalBars
    @State private var hoveredMonthPointId: String? = nil

    public init(store: FinancialDataStore) {
        self.store = store
    }

    // MARK: - Derived Date Range & Read-Only Filtered Transactions

    private var dateRange: (start: Date, end: Date, months: [Date]) {
        let cal = store.calendar
        let anchorMonth = store.startOfMonth(for: store.selectedMonth)

        switch horizon {
        case .currentMonth:
            let end = store.endOfMonth(for: anchorMonth)
            return (anchorMonth, end, [anchorMonth])

        case .last6Months:
            let start = cal.date(byAdding: .month, value: -5, to: anchorMonth) ?? anchorMonth
            let end = store.endOfMonth(for: anchorMonth)
            let months = (0..<6).compactMap { cal.date(byAdding: .month, value: $0, to: start) }
            return (start, end, months)

        case .currentYear:
            let year = cal.component(.year, from: anchorMonth)
            let jan = cal.date(from: DateComponents(year: year, month: 1, day: 1)) ?? anchorMonth
            let decEnd = store.endOfYear(for: anchorMonth)
            let months = (0..<12).compactMap { cal.date(byAdding: .month, value: $0, to: jan) }
            return (jan, decEnd, months)

        case .last12Months:
            let start = cal.date(byAdding: .month, value: -11, to: anchorMonth) ?? anchorMonth
            let end = store.endOfMonth(for: anchorMonth)
            let months = (0..<12).compactMap { cal.date(byAdding: .month, value: $0, to: start) }
            return (start, end, months)
        }
    }

    private var hasActiveCustomFilters: Bool {
        flowFilter != .all || selectedCategoryId != nil || sourceFilter != .all || statusFilter != .all
    }

    private func normalizedAmountBRL(for tx: FinancialTransaction) -> Double {
        if tx.type == .expense {
            return store.effectiveExpenseAmountForBudgetAndCharts(for: tx)
        } else {
            return store.effectiveTransactionAmountInBRL(for: tx)
        }
    }

    private var filteredTransactions: [FinancialTransaction] {
        let range = dateRange
        return store.transactions.filter { tx in
            guard tx.date >= range.start && tx.date <= range.end else { return false }
            guard store.isTransactionVisibleInCurrentScenario(tx) else { return false }
            guard !tx.ignoreInConsolidated,
                  !tx.isCreditCardInvoicePayment,
                  tx.transactionOrigin != .reimbursementReceipt else {
                return false
            }

            switch flowFilter {
            case .all: break
            case .expenses: if tx.type != .expense { return false }
            case .incomes: if tx.type != .income { return false }
            }

            if let catId = selectedCategoryId, tx.categoryId != catId {
                return false
            }

            switch sourceFilter {
            case .all:
                break
            case .account(let accId):
                if tx.isCreditCardExpense || tx.accountId != accId { return false }
            case .creditCard(let cardId):
                if !tx.isCreditCardExpense || tx.creditCardId != cardId { return false }
            }

            switch statusFilter {
            case .all: break
            case .paidOnly: if !tx.isPaid { return false }
            case .pendingOnly: if tx.isPaid { return false }
            }

            return normalizedAmountBRL(for: tx) > 0.001
        }
    }

    // MARK: - Chart Data Series

    private struct MonthlySeriesPoint: Identifiable, Hashable {
        let id: String
        let monthDate: Date
        let label: String
        let income: Double
        let expense: Double
        let net: Double
        let cumulativeNet: Double
    }

    private var monthlySeries: [MonthlySeriesPoint] {
        let cal = store.calendar
        let range = dateRange
        var running = 0.0

        return range.months.map { monthStart in
            let mEnd = store.endOfMonth(for: monthStart)
            let monthTxs = filteredTransactions.filter { $0.date >= monthStart && $0.date <= mEnd }
            let inc = monthTxs.filter { $0.type == .income }.reduce(0.0) { $0 + normalizedAmountBRL(for: $1) }
            let exp = monthTxs.filter { $0.type == .expense }.reduce(0.0) { $0 + normalizedAmountBRL(for: $1) }
            let net = inc - exp
            running += net
            let label = BRLFormatters.shortMonthYearFormatter.string(from: monthStart).capitalized
            let ymKey = cal.component(.year, from: monthStart) * 100 + cal.component(.month, from: monthStart)
            return MonthlySeriesPoint(
                id: "m_\(ymKey)",
                monthDate: monthStart,
                label: label,
                income: inc,
                expense: exp,
                net: net,
                cumulativeNet: running
            )
        }
    }

    private var dailyCumulativeSamples: [BalanceSparklineSample] {
        let cal = store.calendar
        let txs = filteredTransactions.sorted { $0.date < $1.date }
        guard !txs.isEmpty else { return [] }

        var groupedByDay: [Date: Double] = [:]
        for tx in txs {
            let day = cal.startOfDay(for: tx.date)
            let signed = tx.type == .income ? normalizedAmountBRL(for: tx) : -normalizedAmountBRL(for: tx)
            groupedByDay[day, default: 0.0] += signed
        }

        let sortedDays = groupedByDay.keys.sorted()
        var running = 0.0
        return sortedDays.enumerated().map { idx, day in
            running += groupedByDay[day] ?? 0.0
            return BalanceSparklineSample(
                id: "day_\(idx)",
                xValue: Double(idx + 1),
                label: BRLFormatters.shortDate(day),
                value: running
            )
        }
    }

    private struct CategoryAnalyticsSlice: Identifiable {
        let id: String
        let name: String
        let icon: String
        let colorHex: String
        let amount: Double
        let percentage: Double
        let count: Int
        let isOthers: Bool
    }

    private var categorySlices: [CategoryAnalyticsSlice] {
        let targetType: TransactionType = flowFilter == .incomes ? .income : .expense
        let scopedTxs = filteredTransactions.filter { flowFilter == .all ? $0.type == .expense : $0.type == targetType }
        let total = scopedTxs.reduce(0.0) { $0 + normalizedAmountBRL(for: $1) }
        guard total > 0.001 else { return [] }

        var grouped: [UUID: (amount: Double, count: Int)] = [:]
        for tx in scopedTxs {
            let amt = normalizedAmountBRL(for: tx)
            let cur = grouped[tx.categoryId] ?? (0.0, 0)
            grouped[tx.categoryId] = (cur.amount + amt, cur.count + 1)
        }

        let sorted = grouped.map { catId, info -> CategoryAnalyticsSlice in
            let cat = store.category(for: catId)
            return CategoryAnalyticsSlice(
                id: catId.uuidString,
                name: cat?.name ?? "Outros",
                icon: cat?.iconSymbol ?? "tag.fill",
                colorHex: cat?.colorHex ?? "#94A3B8",
                amount: info.amount,
                percentage: (info.amount / total) * 100.0,
                count: info.count,
                isOthers: false
            )
        }.sorted { $0.amount > $1.amount }

        let top = Array(sorted.prefix(6))
        let rest = sorted.dropFirst(6)
        guard !rest.isEmpty else { return top }

        let othersAmount = rest.reduce(0.0) { $0 + $1.amount }
        let othersPct = (othersAmount / total) * 100.0
        let othersCount = rest.reduce(0) { $0 + $1.count }
        return top + [
            CategoryAnalyticsSlice(
                id: "__others__",
                name: "Outros (\(rest.count))",
                icon: "ellipsis.circle.fill",
                colorHex: "#94A3B8",
                amount: othersAmount,
                percentage: othersPct,
                count: othersCount,
                isOthers: true
            )
        ]
    }

    private struct SourceMixSlice: Identifiable {
        let id: String
        let name: String
        let subtitle: String
        let colorHex: String
        let amount: Double
        let percentage: Double
        let icon: String
    }

    private var sourceMixSlices: [SourceMixSlice] {
        let targetTxs = filteredTransactions.filter { flowFilter == .incomes ? $0.type == .income : $0.type == .expense }
        let total = targetTxs.reduce(0.0) { $0 + normalizedAmountBRL(for: $1) }
        guard total > 0.001 else { return [] }

        var grouped: [String: (name: String, subtitle: String, colorHex: String, icon: String, amount: Double)] = [:]
        for tx in targetTxs {
            let amt = normalizedAmountBRL(for: tx)
            if tx.isCreditCardExpense, let cardId = tx.creditCardId {
                let key = "card_\(cardId.uuidString)"
                let card = store.creditCard(for: cardId)
                let cur = grouped[key]
                grouped[key] = (
                    name: card?.name ?? "Cartão de Crédito",
                    subtitle: "Cartão (Competência)",
                    colorHex: card?.colorHex ?? "#6366F1",
                    icon: "creditcard.fill",
                    amount: (cur?.amount ?? 0.0) + amt
                )
            } else {
                let key = "acc_\(tx.accountId.uuidString)"
                let acc = store.account(for: tx.accountId)
                let cur = grouped[key]
                grouped[key] = (
                    name: acc?.name ?? "Conta Bancária",
                    subtitle: "Conta / Débito",
                    colorHex: acc?.colorHex ?? "#10B981",
                    icon: "building.columns.fill",
                    amount: (cur?.amount ?? 0.0) + amt
                )
            }
        }

        return grouped.map { key, info in
            SourceMixSlice(
                id: key,
                name: info.name,
                subtitle: info.subtitle,
                colorHex: info.colorHex,
                amount: info.amount,
                percentage: (info.amount / total) * 100.0,
                icon: info.icon
            )
        }.sorted { $0.amount > $1.amount }
    }

    private struct StructureSlice: Identifiable {
        let id: String
        let title: String
        let amount: Double
        let percentage: Double
        let count: Int
        let color: Color
        let icon: String
    }

    private var structureSlices: [StructureSlice] {
        let targetTxs = filteredTransactions.filter { flowFilter == .incomes ? $0.type == .income : $0.type == .expense }
        let total = targetTxs.reduce(0.0) { $0 + normalizedAmountBRL(for: $1) }
        guard total > 0.001 else { return [] }

        var recurringSum = 0.0, recurringCount = 0
        var installmentSum = 0.0, installmentCount = 0
        var contractSum = 0.0, contractCount = 0
        var singleSum = 0.0, singleCount = 0

        for tx in targetTxs {
            let amt = normalizedAmountBRL(for: tx)
            if tx.linkedContractId != nil || tx.linkedDebtId != nil {
                contractSum += amt
                contractCount += 1
            } else if tx.installmentTotal != nil && (tx.installmentTotal ?? 1) > 1 {
                installmentSum += amt
                installmentCount += 1
            } else if tx.recurrenceMode == .recurring || tx.recurrenceMode == .repeated {
                recurringSum += amt
                recurringCount += 1
            } else {
                singleSum += amt
                singleCount += 1
            }
        }

        var slices: [StructureSlice] = []
        if recurringSum > 0.001 {
            slices.append(StructureSlice(id: "rec", title: "Recorrentes & Fixas", amount: recurringSum, percentage: (recurringSum / total) * 100.0, count: recurringCount, color: FinSenseTheme.cyan, icon: "arrow.triangle.2.circlepath"))
        }
        if installmentSum > 0.001 {
            slices.append(StructureSlice(id: "inst", title: "Parcelamentos", amount: installmentSum, percentage: (installmentSum / total) * 100.0, count: installmentCount, color: FinSenseTheme.amber, icon: "square.stack.3d.up.fill"))
        }
        if singleSum > 0.001 {
            slices.append(StructureSlice(id: "single", title: "Avulsas / Variáveis", amount: singleSum, percentage: (singleSum / total) * 100.0, count: singleCount, color: FinSenseTheme.emerald, icon: "bolt.fill"))
        }
        if contractSum > 0.001 {
            slices.append(StructureSlice(id: "contract", title: "Contratos, Dívidas & Amortizações", amount: contractSum, percentage: (contractSum / total) * 100.0, count: contractCount, color: FinSenseTheme.coral, icon: "doc.text.fill"))
        }
        return slices.sorted { $0.amount > $1.amount }
    }

    private struct WeekdayPoint: Identifiable {
        let id: Int
        let dayName: String
        let amount: Double
        let count: Int
    }

    private var weekdayPoints: [WeekdayPoint] {
        let cal = store.calendar
        let targetTxs = filteredTransactions.filter { flowFilter == .incomes ? $0.type == .income : $0.type == .expense }
        let labels = ["Dom", "Seg", "Ter", "Qua", "Qui", "Sex", "Sáb"]
        var sums = Array(repeating: 0.0, count: 7)
        var counts = Array(repeating: 0, count: 7)

        for tx in targetTxs {
            let wd = cal.component(.weekday, from: tx.date) // 1 = Dom .. 7 = Sáb
            let idx = max(0, min(6, wd - 1))
            sums[idx] += normalizedAmountBRL(for: tx)
            counts[idx] += 1
        }

        // Ordena Segunda -> Domingo para leitura natural
        let order = [1, 2, 3, 4, 5, 6, 0]
        return order.map { idx in
            WeekdayPoint(id: idx, dayName: labels[idx], amount: sums[idx], count: counts[idx])
        }
    }

    // MARK: - Body

    public var body: some View {
        let totalIncomes = filteredTransactions.filter { $0.type == .income }.reduce(0.0) { $0 + normalizedAmountBRL(for: $1) }
        let totalExpenses = filteredTransactions.filter { $0.type == .expense }.reduce(0.0) { $0 + normalizedAmountBRL(for: $1) }
        let netFlow = totalIncomes - totalExpenses
        let activeVolume = flowFilter == .incomes ? totalIncomes : (flowFilter == .expenses ? totalExpenses : netFlow)
        let avgPerMonth = monthlySeries.isEmpty ? 0.0 : (flowFilter == .incomes ? totalIncomes : (flowFilter == .expenses ? totalExpenses : netFlow)) / Double(monthlySeries.count)

        let netWorth = store.netWorthOverview()
        let axisLabelColor = colorScheme == .dark ? Color.white.opacity(0.55) : Color.black.opacity(0.55)

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header + Period Anchor
                HStack(alignment: .center, spacing: 14) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Gráficos & Analytics")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                        Text("Exploração visual multidimensional com recorte dinâmico por período, conta, cartão, categoria e status")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    MonthNavigatorBar(store: store)
                }

                // Interactive Multi-Filter Control Deck
                filterControlBar

                // Dynamic KPI Strip reacting to filters
                HStack(spacing: 12) {
                    MetricCardView(
                        title: flowFilter == .all ? "Saldo Líquido Filtrado" : (flowFilter == .incomes ? "Receitas Filtradas" : "Despesas Filtradas"),
                        value: BRLFormatters.currency(activeVolume),
                        valueColor: flowFilter == .all ? (netFlow >= 0 ? FinSenseTheme.emerald : FinSenseTheme.coral) : (flowFilter == .incomes ? FinSenseTheme.emerald : FinSenseTheme.coral),
                        subtitle: flowFilter == .all ? "Entradas \(BRLFormatters.currency(totalIncomes)) • Saídas \(BRLFormatters.currency(totalExpenses))" : "\(filteredTransactions.count) lançamento(s) no recorte",
                        icon: "waveform.path.ecg",
                        tint: FinSenseTheme.indigo,
                        cardHeight: 112
                    )

                    MetricCardView(
                        title: "Média Mensal do Recorte",
                        value: BRLFormatters.currency(avgPerMonth),
                        subtitle: "Considerando \(monthlySeries.count) mês(es) em \(horizon.rawValue)",
                        icon: "calendar.badge.clock",
                        tint: FinSenseTheme.cyan,
                        cardHeight: 112
                    )

                    MetricCardView(
                        title: "Maior Categoria",
                        value: categorySlices.first?.name ?? "—",
                        subtitle: categorySlices.first.map { "\(BRLFormatters.currency($0.amount)) (\(String(format: "%.1f%%", $0.percentage)))" } ?? "Sem registros",
                        icon: "chart.bar.fill",
                        tint: FinSenseTheme.amber,
                        cardHeight: 112
                    )

                    MetricCardView(
                        title: "Volume Analisado",
                        value: "\(filteredTransactions.count) lançamentos",
                        subtitle: hasActiveCustomFilters ? "Filtros personalizados ativos" : "Visão integral do período",
                        icon: "slider.horizontal.3",
                        tint: FinSenseTheme.emerald,
                        cardHeight: 112
                    )
                }

                // ROW 1: Main Evolution Chart + Cumulative Dynamic Bicolor Trend
                HStack(alignment: .top, spacing: 16) {
                    evolutionChartCard(axisLabelColor: axisLabelColor)
                        .frame(maxWidth: .infinity)

                    cumulativeFlowCard
                        .frame(width: 390)
                }

                // ROW 2: Category Ranking/Donut + Account/Card Mix Donut
                HStack(alignment: .top, spacing: 16) {
                    categoryBreakdownCard(axisLabelColor: axisLabelColor)
                    sourceMixCard
                }

                // ROW 3: Spending Structure + Weekday Cadence & Patrimony Mix
                HStack(alignment: .top, spacing: 16) {
                    structureMixCard
                    weekdayAndNetWorthColumn(netWorth: netWorth, axisLabelColor: axisLabelColor)
                }
            }
            .padding(24)
            .animation(.snappy(duration: 0.22), value: horizon)
            .animation(.snappy(duration: 0.22), value: flowFilter)
            .animation(.snappy(duration: 0.22), value: selectedCategoryId)
            .animation(.snappy(duration: 0.22), value: sourceFilter)
            .animation(.snappy(duration: 0.22), value: statusFilter)
        }
    }

    // MARK: - Filter Control Bar

    private var filterControlBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Picker("Horizonte", selection: $horizon) {
                    ForEach(AnalyticsHorizon.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 270)

                Picker("Fluxo", selection: $flowFilter) {
                    ForEach(AnalyticsFlowFilter.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 220)

                Spacer()

                if hasActiveCustomFilters {
                    Button {
                        flowFilter = .all
                        selectedCategoryId = nil
                        sourceFilter = .all
                        statusFilter = .all
                    } label: {
                        Label("Limpar Filtros", systemImage: "xmark.circle")
                    }
                    .buttonStyle(BentoGlassButtonStyle(tint: FinSenseTheme.coral, cornerRadius: 8, verticalPadding: 4.5, horizontalPadding: 10))
                }
            }

            HStack(spacing: 10) {
                Picker("Categoria", selection: $selectedCategoryId) {
                    Text("Todas Categorias").tag(UUID?.none)
                    let cats = flowFilter == .expenses
                        ? store.categories(for: .expense)
                        : (flowFilter == .incomes ? store.categories(for: .income) : store.categories)
                    ForEach(cats) { cat in
                        Text(cat.name).tag(UUID?.some(cat.id))
                    }
                }
                .frame(width: 190)

                Picker("Origem", selection: $sourceFilter) {
                    Text("Todas Contas & Cartões").tag(AnalyticsSourceFilter.all)
                    if !store.accounts.isEmpty {
                        Divider()
                        ForEach(store.accounts) { acc in
                            Text("🏦 \(acc.name)").tag(AnalyticsSourceFilter.account(acc.id))
                        }
                    }
                    if !store.creditCards.isEmpty {
                        Divider()
                        ForEach(store.creditCards) { card in
                            Text("💳 \(card.name)").tag(AnalyticsSourceFilter.creditCard(card.id))
                        }
                    }
                }
                .frame(width: 215)

                Picker("Status", selection: $statusFilter) {
                    ForEach(AnalyticsStatusFilter.allCases) { st in
                        Text(st.rawValue).tag(st)
                    }
                }
                .frame(width: 195)

                Spacer()
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(FinSenseTheme.nestedSurface(for: colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(FinSenseTheme.cardBorder(for: colorScheme), lineWidth: FinSenseTheme.hairlineWidth)
        )
    }

    // MARK: - Chart 1: Evolução Mensal / Área Líquida

    @ViewBuilder
    private func evolutionChartCard(axisLabelColor: Color) -> some View {
        let hoveredPoint = monthlySeries.first(where: { $0.id == hoveredMonthPointId })

        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Evolução Financeira no Horizonte")
                        .font(.headline)
                    Text("Receitas, despesas e curva de resultado líquido filtrados mês a mês")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Picker("Tipo", selection: $evolutionChartType) {
                    ForEach(AnalyticsEvolutionChartType.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 205)
            }

            if let pt = hoveredPoint {
                HStack(spacing: 12) {
                    Text(pt.label)
                        .font(.caption.bold())
                    Text("Entradas: ")
                        .font(.caption2).foregroundStyle(.secondary)
                    + Text(BRLFormatters.currency(pt.income))
                        .font(.caption2.bold()).foregroundStyle(FinSenseTheme.emerald)
                    Text("Saídas: ")
                        .font(.caption2).foregroundStyle(.secondary)
                    + Text(BRLFormatters.currency(pt.expense))
                        .font(.caption2.bold()).foregroundStyle(FinSenseTheme.coral)
                    Text("Líquido: ")
                        .font(.caption2).foregroundStyle(.secondary)
                    + Text(BRLFormatters.currency(pt.net))
                        .font(.caption2.bold()).foregroundStyle(FinSenseTheme.cyan)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(FinSenseTheme.nestedSurface(for: colorScheme))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            if monthlySeries.allSatisfy({ $0.income == 0 && $0.expense == 0 }) {
                emptyChartPlaceholder(text: "Sem movimentações para os filtros selecionados.")
            } else {
                Chart {
                    if evolutionChartType == .barsAndLine {
                        ForEach(monthlySeries) { pt in
                            if flowFilter != .expenses {
                                BarMark(
                                    x: .value("Mês", pt.label),
                                    y: .value("Valor", pt.income)
                                )
                                .foregroundStyle(FinSenseTheme.emerald.opacity(0.82))
                                .position(by: .value("Tipo", "Entradas"))
                                .cornerRadius(5)
                            }
                            if flowFilter != .incomes {
                                BarMark(
                                    x: .value("Mês", pt.label),
                                    y: .value("Valor", pt.expense)
                                )
                                .foregroundStyle(FinSenseTheme.coral.opacity(0.82))
                                .position(by: .value("Tipo", "Saídas"))
                                .cornerRadius(5)
                            }
                            LineMark(
                                x: .value("Mês", pt.label),
                                y: .value("Líquido", flowFilter == .incomes ? pt.income : (flowFilter == .expenses ? pt.expense : pt.net))
                            )
                            .foregroundStyle(FinSenseTheme.cyan)
                            .interpolationMethod(.catmullRom)
                            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))

                            PointMark(
                                x: .value("Mês", pt.label),
                                y: .value("Líquido", flowFilter == .incomes ? pt.income : (flowFilter == .expenses ? pt.expense : pt.net))
                            )
                            .foregroundStyle(FinSenseTheme.cyan)
                            .symbolSize(30)
                        }
                    } else {
                        ForEach(monthlySeries) { pt in
                            let val = flowFilter == .incomes ? pt.income : (flowFilter == .expenses ? pt.expense : pt.cumulativeNet)
                            AreaMark(
                                x: .value("Mês", pt.label),
                                y: .value("Acumulado", val)
                            )
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [FinSenseTheme.cyan.opacity(0.32), FinSenseTheme.cyan.opacity(0.03)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .interpolationMethod(.catmullRom)

                            LineMark(
                                x: .value("Mês", pt.label),
                                y: .value("Acumulado", val)
                            )
                            .foregroundStyle(FinSenseTheme.cyan)
                            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                            .interpolationMethod(.catmullRom)

                            PointMark(
                                x: .value("Mês", pt.label),
                                y: .value("Acumulado", val)
                            )
                            .foregroundStyle(FinSenseTheme.cyan)
                            .symbolSize(30)
                        }
                    }
                }
                .chartYAxis {
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
                                        if let label: String = proxy.value(atX: xInPlot),
                                           let match = monthlySeries.first(where: { $0.label == label }) {
                                            hoveredMonthPointId = match.id
                                            return
                                        }
                                    }
                                    hoveredMonthPointId = nil
                                case .ended:
                                    hoveredMonthPointId = nil
                                }
                            }
                    }
                }
                .frame(height: 230)
            }
        }
        .bentoCard(padding: 18)
    }

    // MARK: - Chart 2: Curva Acumulada Diária Bicolor

    private var cumulativeFlowCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Curva Diária Acumulada")
                    .font(.headline)
                Text("Escala dinâmica com preenchimento esmeralda/coral e valores no hover")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if dailyCumulativeSamples.isEmpty {
                emptyChartPlaceholder(text: "Sem pontos diários para os filtros ativos.")
            } else {
                let finalAccumulated = dailyCumulativeSamples.last?.value ?? 0.0
                let minVal = dailyCumulativeSamples.map(\.value).min() ?? 0.0
                let maxVal = dailyCumulativeSamples.map(\.value).max() ?? 0.0

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Saldo Acumulado Final")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(BRLFormatters.currency(finalAccumulated))
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(finalAccumulated >= 0 ? FinSenseTheme.emerald : FinSenseTheme.coral)
                            .numericCurrencyTransition(value: finalAccumulated)
                    }
                    Spacer()
                }

                ProjectedBalanceSparklineView(
                    samples: dailyCumulativeSamples,
                    height: 126,
                    showHoverTooltip: true,
                    helpText: "Evolução acumulada dia a dia no recorte filtrado"
                )

                HStack(spacing: 10) {
                    statChip(label: "Mínimo", value: BRLFormatters.currency(minVal), color: minVal < 0 ? FinSenseTheme.coral : .secondary)
                    statChip(label: "Máximo", value: BRLFormatters.currency(maxVal), color: FinSenseTheme.emerald)
                }
            }
        }
        .frame(minHeight: 280, alignment: .topLeading)
        .bentoCard(padding: 18)
    }

    // MARK: - Chart 3: Ranking / Rosca por Categorias

    @ViewBuilder
    private func categoryBreakdownCard(axisLabelColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(flowFilter == .incomes ? "Receitas por Categoria" : "Despesas por Categoria")
                        .font(.headline)
                    Text("Distribuição filtrada por conta, cartão e status")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Picker("Modo", selection: $categoryChartMode) {
                    ForEach(AnalyticsCategoryChartMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 195)
            }

            if categorySlices.isEmpty {
                emptyChartPlaceholder(text: "Nenhuma categoria encontrada para este filtro.")
            } else if categoryChartMode == .horizontalBars {
                Chart(categorySlices) { item in
                    BarMark(
                        x: .value("Valor", item.amount),
                        y: .value("Categoria", item.name)
                    )
                    .foregroundStyle(Color(hex: item.colorHex))
                    .cornerRadius(5)
                    .annotation(position: .trailing) {
                        Text("\(BRLFormatters.currency(item.amount)) (\(String(format: "%.0f%%", item.percentage)))")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(axisLabelColor)
                            .monospacedDigit()
                    }
                }
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks { value in
                        if let name = value.as(String.self) {
                            AxisValueLabel {
                                Text(name)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(axisLabelColor)
                            }
                        }
                    }
                }
                .frame(height: max(180, CGFloat(categorySlices.count * 34)))
            } else {
                let total = categorySlices.reduce(0.0) { $0 + $1.amount }
                HStack(spacing: 20) {
                    ZStack {
                        Chart(categorySlices) { item in
                            SectorMark(
                                angle: .value("Valor", item.amount),
                                innerRadius: .ratio(0.72),
                                angularInset: 2
                            )
                            .cornerRadius(5)
                            .foregroundStyle(Color(hex: item.colorHex))
                        }
                        .frame(width: 184, height: 184)

                        VStack(spacing: 2) {
                            Text("Total")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(BRLFormatters.currency(total))
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .monospacedDigit()
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(categorySlices) { item in
                            HStack(spacing: 8) {
                                Circle().fill(Color(hex: item.colorHex)).frame(width: 8, height: 8)
                                Text(item.name)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(item.isOthers ? FinSenseTheme.slateLight : .primary)
                                    .lineLimit(1)
                                Spacer()
                                Text(String(format: "%.1f%%", item.percentage))
                                    .font(.caption2)
                                    .foregroundStyle(axisLabelColor)
                                    .monospacedDigit()
                                Text(BRLFormatters.currency(item.amount))
                                    .font(.caption.bold())
                                    .monospacedDigit()
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .bentoCard(padding: 18)
    }

    // MARK: - Chart 4: Origem por Conta vs Cartão

    private var sourceMixCard: some View {
        let total = sourceMixSlices.reduce(0.0) { $0 + $1.amount }
        let neutralMuted = colorScheme == .dark ? Color.white.opacity(0.55) : Color.secondary

        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Mix por Conta & Cartão")
                    .font(.headline)
                Text("Concentração do volume entre contas bancárias e faturas de cartão")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if sourceMixSlices.isEmpty {
                emptyChartPlaceholder(text: "Sem registros por conta/cartão neste recorte.")
            } else {
                HStack(alignment: .center, spacing: 18) {
                    ZStack {
                        Chart(sourceMixSlices) { slice in
                            SectorMark(
                                angle: .value("Valor", slice.amount),
                                innerRadius: .ratio(0.72),
                                angularInset: 2
                            )
                            .cornerRadius(5)
                            .foregroundStyle(Color(hex: slice.colorHex))
                        }
                        .frame(width: 170, height: 170)

                        VStack(spacing: 2) {
                            Text("Fontes")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text("\(sourceMixSlices.count)")
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                            Text(BRLFormatters.currency(total))
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }

                    VStack(spacing: 8) {
                        ForEach(sourceMixSlices.prefix(6)) { slice in
                            HStack(spacing: 8) {
                                Image(systemName: slice.icon)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color(hex: slice.colorHex))
                                    .frame(width: 16)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(slice.name)
                                        .font(.caption.weight(.semibold))
                                        .lineLimit(1)
                                    Text(slice.subtitle)
                                        .font(.system(size: 10))
                                        .foregroundStyle(neutralMuted)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 1) {
                                    Text(BRLFormatters.currency(slice.amount))
                                        .font(.caption.bold())
                                        .monospacedDigit()
                                    Text(String(format: "%.1f%%", slice.percentage))
                                        .font(.system(size: 10))
                                        .foregroundStyle(neutralMuted)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(FinSenseTheme.nestedSurface(for: colorScheme))
                            )
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .bentoCard(padding: 18)
    }

    // MARK: - Chart 5: Estrutura (Fixos vs Parcelamentos vs Avulsos)

    private var structureMixCard: some View {
        let neutralMuted = colorScheme == .dark ? Color.white.opacity(0.55) : Color.secondary

        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Estrutura Financeira dos Lançamentos")
                    .font(.headline)
                Text("Comprometimento recorrente/fixo, parcelamentos, avulsos e contratos")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if structureSlices.isEmpty {
                emptyChartPlaceholder(text: "Sem dados estruturais para o recorte atual.")
            } else {
                VStack(spacing: 10) {
                    ForEach(structureSlices) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                Image(systemName: item.icon)
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .foregroundStyle(item.color)
                                    .frame(width: 18)
                                Text(item.title)
                                    .font(.system(size: 12, weight: .semibold))
                                Spacer()
                                Text("\(item.count)x • \(String(format: "%.1f%%", item.percentage))")
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(neutralMuted)
                                Text(BRLFormatters.currency(item.amount))
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                    .foregroundStyle(colorScheme == .dark ? .white : .primary)
                                    .monospacedDigit()
                            }

                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.06))
                                        .frame(height: 5)
                                    Capsule()
                                        .fill(item.color)
                                        .frame(width: max(geo.size.width * min(item.percentage / 100.0, 1.0), 4), height: 5)
                                }
                            }
                            .frame(height: 5)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(FinSenseTheme.nestedSurface(for: colorScheme))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(FinSenseTheme.cardBorder(for: colorScheme), lineWidth: FinSenseTheme.hairlineWidth)
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .bentoCard(padding: 18)
    }

    // MARK: - Chart 6: Ritmo por Dia da Semana + Balanço Patrimonial

    @ViewBuilder
    private func weekdayAndNetWorthColumn(netWorth: NetWorthOverviewSummary, axisLabelColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Cadência Semanal & Patrimônio")
                    .font(.headline)
                Text("Concentração por dia da semana no filtro + posição atual de ativos vs passivos")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if weekdayPoints.allSatisfy({ $0.amount == 0 }) {
                emptyChartPlaceholder(text: "Sem volume semanal nos filtros ativos.")
            } else {
                Chart(weekdayPoints) { pt in
                    BarMark(
                        x: .value("Dia", pt.dayName),
                        y: .value("Volume", pt.amount)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [FinSenseTheme.indigo.opacity(0.92), FinSenseTheme.cyan.opacity(0.55)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .cornerRadius(5)
                }
                .chartYAxis {
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
                    AxisMarks { value in
                        if let name = value.as(String.self) {
                            AxisValueLabel {
                                Text(name)
                                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                                    .foregroundStyle(axisLabelColor)
                            }
                        }
                    }
                }
                .frame(height: 135)
            }

            HStack(spacing: 10) {
                statChip(label: "Ativos Totais", value: BRLFormatters.currency(netWorth.totalAssetsBRL), color: FinSenseTheme.emerald)
                statChip(label: "Passivos Totais", value: BRLFormatters.currency(netWorth.totalLiabilitiesBRL), color: FinSenseTheme.coral)
                statChip(label: "Net Worth", value: BRLFormatters.currency(netWorth.netWorthBRL), color: netWorth.netWorthBRL >= 0 ? FinSenseTheme.cyan : FinSenseTheme.coral)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .bentoCard(padding: 18)
    }

    // MARK: - Helpers

    private func statChip(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 12.5, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(FinSenseTheme.nestedSurface(for: colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(FinSenseTheme.cardBorder(for: colorScheme), lineWidth: FinSenseTheme.hairlineWidth)
        )
    }

    private func emptyChartPlaceholder(text: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 28))
                .foregroundStyle(.secondary.opacity(0.6))
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
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
