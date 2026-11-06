import SwiftUI
import AppKit

public struct TransactionsView: View {
    @ObservedObject public var store: FinancialDataStore
    @ObservedObject public var llmService: LocalLLMService

    @State private var searchText: String = ""
    @State private var selectedTypeFilter: TransactionType? = nil
    @State private var selectedAccountFilter: UUID? = nil
    @State private var selectedCategoryFilter: UUID? = nil
    @State private var onlyPendingFilter: Bool = false

    @State private var showCreateExpenseSheet: Bool = false
    @State private var showCreateIncomeSheet: Bool = false
    @State private var showImportSheet: Bool = false
    @State private var editingTransaction: FinancialTransaction? = nil
    @State private var transactionPendingDeletion: FinancialTransaction? = nil
    @State private var recurringTransactionPendingCancellation: FinancialTransaction? = nil
    @State private var showFuturePaidBlockedAlert: Bool = false

    public init(store: FinancialDataStore, llmService: LocalLLMService) {
        self.store = store
        self.llmService = llmService
    }

    private var enforcedTypeFromSubmenu: TransactionType? {
        switch store.selectedTransactionsSubmenu {
        case .all:
            return selectedTypeFilter
        case .expenses:
            return .expense
        case .incomes:
            return .income
        }
    }

    private var filteredMonthTransactions: [FinancialTransaction] {
        store.transactionsForMonth(store.selectedMonth).filter { tx in
            if let typeFilter = enforcedTypeFromSubmenu, tx.type != typeFilter {
                return false
            }
            if let accFilter = selectedAccountFilter, tx.accountId != accFilter {
                return false
            }
            if let catFilter = selectedCategoryFilter, tx.categoryId != catFilter {
                return false
            }
            if onlyPendingFilter && tx.isPaid {
                return false
            }
            let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !q.isEmpty {
                let catName = store.category(for: tx.categoryId)?.name ?? ""
                let accName = store.account(for: tx.accountId)?.name ?? ""
                let matches = tx.name.localizedCaseInsensitiveContains(q) ||
                              tx.details.localizedCaseInsensitiveContains(q) ||
                              catName.localizedCaseInsensitiveContains(q) ||
                              accName.localizedCaseInsensitiveContains(q)
                if !matches { return false }
            }
            return true
        }
    }

    private var headerTitle: String {
        switch store.selectedTransactionsSubmenu {
        case .all:
            return "Transações por Mês"
        case .expenses:
            return "Despesas por Mês"
        case .incomes:
            return "Receitas por Mês"
        }
    }

    private var headerSubtitle: String {
        switch store.selectedTransactionsSubmenu {
        case .all:
            return "Gerencie despesas, receitas, parcelamentos, recorrências e importação via IA Local"
        case .expenses:
            return "Visão mensal de despesas únicas, parceladas, repetidas e recorrentes (assinaturas/contas)"
        case .incomes:
            return "Visão mensal de receitas únicas, repetidas e recebimentos recorrentes"
        }
    }

    public var body: some View {
        let monthIncome = store.monthlyIncome(for: store.selectedMonth)
        let monthReceivedIncome = store.monthlyReceivedIncome(for: store.selectedMonth)
        let monthPendingIncome = store.monthlyPendingIncome(for: store.selectedMonth)

        let monthExpense = store.monthlyExpense(for: store.selectedMonth)
        let monthPendingExpense = store.monthlyPendingExpense(for: store.selectedMonth)

        let monthBalance = monthIncome - monthExpense
        let accumulatedBalance = store.accumulatedConsolidatedBalance(throughMonth: store.selectedMonth)

        VStack(alignment: .leading, spacing: 18) {
            // MARK: - Header & Month Navigation
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(headerTitle)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                    Text(headerSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                MonthNavigatorBar(store: store)
            }

            // MARK: - Monthly Summary Cards (Adaptados por Submenu: Todas, Despesas ou Receitas)
            switch store.selectedTransactionsSubmenu {
            case .all:
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                    MetricCardView(
                        title: "Receitas no Mês",
                        value: BRLFormatters.currency(monthIncome),
                        subtitle: BRLFormatters.monthYear(store.selectedMonth),
                        icon: "arrow.down.left.circle.fill",
                        tint: Color(hex: "#10B981")
                    )

                    MetricCardView(
                        title: "Despesas no Mês",
                        value: BRLFormatters.currency(monthExpense),
                        subtitle: BRLFormatters.monthYear(store.selectedMonth),
                        icon: "arrow.up.right.circle.fill",
                        tint: Color(hex: "#EF4444")
                    )

                    MetricCardView(
                        title: "Balanço do Mês",
                        value: BRLFormatters.currency(monthBalance),
                        subtitle: monthBalance >= 0 ? "Superávit no período" : "Déficit no período",
                        icon: "equal.circle.fill",
                        tint: monthBalance >= 0 ? Color(hex: "#10B981") : Color(hex: "#EF4444")
                    )

                    MetricCardView(
                        title: "Acumulado até o Mês",
                        value: BRLFormatters.currency(accumulatedBalance),
                        subtitle: "Saldo + Invest. Consolidados",
                        icon: "chart.line.uptrend.xyaxis.circle.fill",
                        tint: Color(hex: "#3B82F6")
                    )
                }

            case .expenses:
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 12) {
                    MetricCardView(
                        title: "Total de Despesas",
                        value: BRLFormatters.currency(monthExpense),
                        subtitle: "Despesas consolidadas em \(BRLFormatters.monthYear(store.selectedMonth))",
                        icon: "arrow.up.right.circle.fill",
                        tint: Color(hex: "#EF4444")
                    )

                    MetricCardView(
                        title: "Total Pendente",
                        value: BRLFormatters.currency(monthPendingExpense),
                        subtitle: "Despesas ainda não pagas em \(BRLFormatters.monthYear(store.selectedMonth))",
                        icon: "clock.badge.exclamationmark",
                        tint: Color(hex: "#F59E0B")
                    )
                }

            case .incomes:
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 12) {
                    MetricCardView(
                        title: "Total Recebido",
                        value: BRLFormatters.currency(monthReceivedIncome),
                        subtitle: "Receitas efetivadas em \(BRLFormatters.monthYear(store.selectedMonth))",
                        icon: "checkmark.circle.fill",
                        tint: Color(hex: "#10B981")
                    )

                    MetricCardView(
                        title: "À Receber",
                        value: BRLFormatters.currency(monthPendingIncome),
                        subtitle: "Receitas pendentes/previstas em \(BRLFormatters.monthYear(store.selectedMonth))",
                        icon: "clock.arrow.circlepath",
                        tint: Color(hex: "#3B82F6")
                    )
                }
            }

            // MARK: - Action & Filter Bar
            HStack(spacing: 10) {
                if store.selectedTransactionsSubmenu != .incomes {
                    Button {
                        showCreateExpenseSheet = true
                    } label: {
                        Label("Nova Despesa", systemImage: "minus.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(hex: "#EF4444"))
                }

                if store.selectedTransactionsSubmenu != .expenses {
                    Button {
                        showCreateIncomeSheet = true
                    } label: {
                        Label("Nova Receita", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(hex: "#10B981"))
                }

                Button {
                    store.requireInstalledLLM(forFeature: "Importar Relatório / Extrato com IA Local") {
                        showImportSheet = true
                    }
                } label: {
                    Label("Importar Relatório / Extrato (IA Local)", systemImage: "doc.text.magnifyingglass")
                }
                .buttonStyle(.bordered)

                Divider().frame(height: 22)

                if store.selectedTransactionsSubmenu == .all {
                    Picker("Tipo", selection: $selectedTypeFilter) {
                        Text("Todos os Tipos").tag(TransactionType?.none)
                        Text("Apenas Despesas").tag(TransactionType?.some(.expense))
                        Text("Apenas Receitas").tag(TransactionType?.some(.income))
                    }
                    .frame(width: 155)
                }

                Picker("Categoria", selection: $selectedCategoryFilter) {
                    Text("Todas as Categorias").tag(UUID?.none)
                    let catsToList = enforcedTypeFromSubmenu.map { store.categories(for: $0) } ?? store.categories
                    ForEach(catsToList) { cat in
                        Text(cat.name).tag(UUID?.some(cat.id))
                    }
                }
                .frame(width: 175)

                Picker("Conta", selection: $selectedAccountFilter) {
                    Text("Todas as Contas").tag(UUID?.none)
                    ForEach(store.accounts) { acc in
                        Text(acc.name).tag(UUID?.some(acc.id))
                    }
                }
                .frame(width: 155)

                Toggle("Só Pendentes", isOn: $onlyPendingFilter)
                    .toggleStyle(.checkbox)

                Spacer()

                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    MacFullWidthTextInput(
                        text: $searchText,
                        placeholder: "Buscar...",
                        font: .systemFont(ofSize: 13)
                    )
                    .frame(width: 150, height: 20)
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.28), lineWidth: 1))
            }

            // MARK: - Transactions List
            if filteredMonthTransactions.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 42))
                        .foregroundStyle(.secondary)
                    Text("Nenhum lançamento encontrado para \(BRLFormatters.monthYear(store.selectedMonth))")
                        .font(.headline)
                    Text("Adicione um lançamento, navegue entre os meses ou importe um extrato PDF com a LLM local.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredMonthTransactions) { tx in
                            transactionRow(tx)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(24)
        .onChange(of: store.selectedTransactionsSubmenu) { _, _ in
            selectedCategoryFilter = nil
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
        .sheet(isPresented: $showImportSheet) {
            StatementImportSheet(
                store: store,
                llmService: llmService,
                initialFilterMode: store.selectedTransactionsSubmenu == .expenses
                    ? .expensesOnly
                    : (store.selectedTransactionsSubmenu == .incomes ? .incomesOnly : .hybrid)
            )
        }
        .sheet(item: $editingTransaction) { txToEdit in
            TransactionEditorSheet(
                store: store,
                llmService: llmService,
                initialType: txToEdit.type,
                existingTransaction: txToEdit
            )
        }
        .alert(
            "Confirmar Exclusão de Transação",
            isPresented: Binding(
                get: { transactionPendingDeletion != nil },
                set: { if !$0 { transactionPendingDeletion = nil } }
            ),
            presenting: transactionPendingDeletion
        ) { tx in
            Button("Excluir Transação", role: .destructive) {
                store.deleteTransaction(tx.id)
                transactionPendingDeletion = nil
            }
            Button("Cancelar", role: .cancel) {
                transactionPendingDeletion = nil
            }
        } message: { tx in
            Text("Deseja realmente excluir a transação \"\(tx.name)\" no valor de \(BRLFormatters.currency(tx.amount)) (\(BRLFormatters.shortDate(tx.date)))? Esta ação não pode ser desfeita.")
        }
        .alert(
            "Cancelar Recorrência / Assinatura",
            isPresented: Binding(
                get: { recurringTransactionPendingCancellation != nil },
                set: { if !$0 { recurringTransactionPendingCancellation = nil } }
            ),
            presenting: recurringTransactionPendingCancellation
        ) { tx in
            Button("Cancelar Próximas Cobranças", role: .destructive) {
                store.cancelRecurringSeries(from: tx, includeCurrent: false)
                recurringTransactionPendingCancellation = nil
            }
            Button("Cancelar Incluindo Esta (\(BRLFormatters.shortDate(tx.date)))", role: .destructive) {
                store.cancelRecurringSeries(from: tx, includeCurrent: true)
                recurringTransactionPendingCancellation = nil
            }
            Button("Voltar", role: .cancel) {
                recurringTransactionPendingCancellation = nil
            }
        } message: { tx in
            Text("Deseja encerrar a recorrência de \"\(tx.name)\" a partir de \(BRLFormatters.shortDate(tx.date))? As ocorrências futuras em aberto serão removidas.")
        }
        .alert("Não Permitido para Data no Futuro", isPresented: $showFuturePaidBlockedAlert) {
            Button("Entendi", role: .cancel) {}
        } message: {
            Text("Não é possível marcar como paga ou recebida uma conta com data no futuro. Aguarde a data do lançamento ou altere a data para hoje ou uma data passada.")
        }
    }

    @ViewBuilder
    private func transactionRow(_ tx: FinancialTransaction) -> some View {
        let cat = store.category(for: tx.categoryId)
        let acc = store.account(for: tx.accountId)
        let isFuture = store.isDateInFuture(tx.date)

        HStack(spacing: 14) {
            CategoryBadgeView(category: cat, size: 40)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(tx.name)
                        .font(.system(size: 14, weight: .semibold))
                        .strikethrough(tx.ignoreInConsolidated, color: .secondary)

                    if let badge = tx.installmentBadge {
                        Text(badge)
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.blue.opacity(0.15)))
                            .foregroundStyle(.blue)
                    }

                    if tx.recurrenceMode == .repeated {
                        Label("Repetida", systemImage: "repeat")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.purple.opacity(0.15)))
                            .foregroundStyle(.purple)
                    }

                    if tx.recurrenceMode == .recurring {
                        let freqLabel = tx.recurrenceFrequency?.shortTitle ?? "Mensal"
                        let isCanceled = tx.isCanceledRecurringSeries == true
                        Label(
                            isCanceled ? "Recorrente (\(freqLabel) • Cancelada)" : "Recorrente • \(freqLabel)",
                            systemImage: "arrow.triangle.2.circlepath"
                        )
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill((isCanceled ? Color.secondary : Color(hex: "#06B6D4")).opacity(0.16)))
                        .foregroundStyle(isCanceled ? Color.secondary : Color(hex: "#06B6D4"))
                    }

                    if tx.ignoreInConsolidated {
                        Text("Ignorado no Consolidado")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.orange.opacity(0.16)))
                            .foregroundStyle(.orange)
                    }

                    if let attName = tx.attachmentName, let attPath = tx.attachmentPath {
                        Button {
                            NSWorkspace.shared.open(URL(fileURLWithPath: attPath))
                        } label: {
                            Label(attName, systemImage: "paperclip")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.secondary.opacity(0.15)))
                        }
                        .buttonStyle(.plain)
                        .help("Abrir anexo: \(attName)")
                    }
                }

                HStack(spacing: 10) {
                    Text(BRLFormatters.shortDate(tx.date))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let cat {
                        Text("• \(cat.name)")
                            .font(.caption)
                            .foregroundStyle(Color(hex: cat.colorHex))
                    }

                    if let acc {
                        Text("• \(acc.name)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if !tx.details.isEmpty {
                        Text("• \(tx.details)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            // Paid / Received Status Toggle (Bloqueado se data for futura)
            Button {
                if !tx.isPaid && isFuture {
                    showFuturePaidBlockedAlert = true
                } else {
                    _ = store.toggleTransactionPaid(tx.id)
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: tx.isPaid ? "checkmark.circle.fill" : (isFuture ? "calendar.badge.clock" : "clock.badge.exclamationmark"))
                    Text(tx.isPaid ? (tx.type == .expense ? "Pago" : "Recebido") : (tx.type == .expense ? "Não Pago" : "Não Recebido"))
                        .font(.caption.weight(.semibold))
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(tx.isPaid ? Color.green.opacity(0.14) : Color.amberWarning.opacity(0.16))
                )
                .foregroundStyle(tx.isPaid ? Color.green : Color.amberWarning)
            }
            .buttonStyle(.plain)
            .help(isFuture && !tx.isPaid ? "Não é possível pagar uma conta com data no futuro" : "Alternar status de Pago / Recebido")

            // Amount
            Text((tx.type == .expense ? "- " : "+ ") + BRLFormatters.currency(tx.amount))
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(
                    tx.ignoreInConsolidated
                        ? Color.secondary
                        : (tx.type == .expense ? Color(hex: "#EF4444") : Color(hex: "#10B981"))
                )
                .frame(minWidth: 115, alignment: .trailing)

            // Context actions
            HStack(spacing: 4) {
                if tx.recurrenceMode == .recurring && tx.isCanceledRecurringSeries != true {
                    Button {
                        recurringTransactionPendingCancellation = tx
                    } label: {
                        Image(systemName: "stop.circle")
                            .foregroundStyle(.orange)
                            .frame(width: 26, height: 26)
                    }
                    .buttonStyle(.borderless)
                    .help("Cancelar recorrência / assinatura")
                }

                Button {
                    editingTransaction = tx
                } label: {
                    Image(systemName: "pencil")
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.borderless)
                .help("Editar transação")

                Button(role: .destructive) {
                    transactionPendingDeletion = tx
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.borderless)
                .help("Excluir transação")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

extension Color {
    static let amberWarning = Color(hex: "#D97706")
}

// MARK: - Transaction Editor Sheet (Create Expense / Create Income / Edit + Series Edit Scope Prompt)

public struct TransactionEditorSheet: View {
    @ObservedObject public var store: FinancialDataStore
    @ObservedObject public var llmService: LocalLLMService
    @Environment(\.dismiss) private var dismiss

    public let existingTransaction: FinancialTransaction?

    @State private var type: TransactionType
    @State private var name: String = ""
    @State private var details: String = ""
    @State private var amountText: String = ""
    @State private var date: Date = Date()
    @State private var isPaid: Bool = true // Marcado por default quando não está no futuro!
    @State private var categoryId: UUID = UUID()
    @State private var accountId: UUID = UUID()
    @State private var ignoreInConsolidated: Bool = false
    @State private var attachmentPath: String? = nil
    @State private var attachmentName: String? = nil

    // Modalidade de lançamento (Único, Parcelado, Repetido, Recorrente) e Frequência
    @State private var recurrenceMode: TransactionRecurrenceMode = .single
    @State private var installmentsOrMonthsCount: Int = 2
    @State private var recurrenceFrequency: RecurrenceFrequency = .monthly

    @State private var showEmbeddedStatementImporter: Bool = false
    @State private var showRemoveAttachmentConfirmation: Bool = false
    @State private var pendingSeriesUpdateTransaction: FinancialTransaction? = nil
    @State private var validationError: String? = nil

    public init(
        store: FinancialDataStore,
        llmService: LocalLLMService,
        initialType: TransactionType,
        existingTransaction: FinancialTransaction? = nil
    ) {
        self.store = store
        self.llmService = llmService
        self.existingTransaction = existingTransaction
        _type = State(initialValue: existingTransaction?.type ?? initialType)
    }

    private var isSelectedDateInFuture: Bool {
        store.isDateInFuture(date)
    }

    public var body: some View {
        let availableModes = TransactionRecurrenceMode.availableModes(for: type)

        VStack(alignment: .leading, spacing: 18) {
            // Top bar
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(existingTransaction == nil ? "Criar \(type.title)" : "Editar \(type.title)")
                        .font(.title2.bold())
                    Text("Preencha os dados manualmente ou importe um relatório/extrato com análise via LLM local")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()

                if existingTransaction == nil {
                    Button {
                        store.requireInstalledLLM(forFeature: "Importar Relatório com LLM Local") {
                            showEmbeddedStatementImporter = true
                        }
                    } label: {
                        Label(
                            "Importar Relatório (Extrato c/ LLM Local)",
                            systemImage: "sparkles.rectangle.stack.fill"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(hex: "#6366F1"))
                }
            }

            Divider()

            // Type selector
            Picker("Tipo de Lançamento", selection: $type) {
                ForEach(TransactionType.allCases) { t in
                    Text(t.title).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: type) { _, newType in
                if let firstCat = store.categories(for: newType).first {
                    categoryId = firstCat.id
                }
                if newType == .income && recurrenceMode == .installment {
                    recurrenceMode = .single
                }
            }

            Form {
                Section("Dados Principais") {
                    BorderedTextField(
                        label: "Nome da Transação",
                        placeholder: type == .expense
                            ? "Ex: Energia CPFL, Água, Wellhub, Netflix, Prime Video"
                            : "Ex: Salário Mensal, Aluguel Recebido, Dividendos",
                        text: $name
                    )

                    HStack(alignment: .bottom, spacing: 14) {
                        BRLCurrencyTextField(
                            label: type == .expense && recurrenceMode == .installment
                                ? "Valor Cheio Total (R$)"
                                : "Valor (R$)",
                            text: $amountText
                        )

                        DatePicker("Data", selection: $date, displayedComponents: [.date])
                            .onChange(of: date) { _, newDate in
                                if store.isDateInFuture(newDate) {
                                    isPaid = false
                                }
                            }
                    }

                    BorderedTextField(
                        label: "Detalhes / Observações (Opcional)",
                        placeholder: "Ex: Assinatura anual, conta de consumo, NF",
                        text: $details
                    )
                }

                Section("Classificação e Conta") {
                    Picker("Categoria", selection: $categoryId) {
                        ForEach(store.categories(for: type)) { cat in
                            Label(cat.name, systemImage: cat.iconSymbol)
                                .tag(cat.id)
                        }
                    }

                    if store.accounts.isEmpty {
                        HStack {
                            Text("Nenhuma conta cadastrada.")
                                .font(.caption)
                                .foregroundStyle(.orange)
                            Spacer()
                            Button("Ir para Contas") {
                                dismiss()
                                store.selectedDestination = .settings
                                store.selectedSettingsSection = .accounts
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    } else {
                        Picker("Conta Bancária", selection: $accountId) {
                            ForEach(store.accounts) { acc in
                                Text(acc.name).tag(acc.id)
                            }
                        }
                    }
                }

                if existingTransaction == nil {
                    Section(type == .expense ? "Modalidade de Pagamento (Único, Parcelado, Repetido ou Recorrente)" : "Modalidade de Recebimento (Único, Repetido ou Recorrente)") {
                        Picker("Modalidade", selection: $recurrenceMode) {
                            ForEach(availableModes) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)

                        if recurrenceMode == .installment && type == .expense {
                            EditableIntegerStepperField(
                                label: "Quantidade de Parcelas (Digite ou ajuste)",
                                value: $installmentsOrMonthsCount,
                                range: 2...240,
                                unitSuffix: "parcelas"
                            )
                            if let totalVal = BRLFormatters.parseAmount(amountText), totalVal > 0 {
                                let perInstallment = totalVal / Double(installmentsOrMonthsCount)
                                Text("Serão criadas \(installmentsOrMonthsCount) parcelas mensais de \(BRLFormatters.currency(perInstallment)) somando o valor cheio de \(BRLFormatters.currency(totalVal)).")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } else if recurrenceMode == .repeated {
                            EditableIntegerStepperField(
                                label: "Quantidade de Meses em Repetir (Digite ou ajuste)",
                                value: $installmentsOrMonthsCount,
                                range: 2...240,
                                unitSuffix: "meses"
                            )
                            if let monthlyVal = BRLFormatters.parseAmount(amountText), monthlyVal > 0 {
                                Text("O mesmo valor de \(BRLFormatters.currency(monthlyVal)) será repetido por \(installmentsOrMonthsCount) meses consecutivos.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } else if recurrenceMode == .recurring {
                            Picker("Frequência da Recorrência", selection: $recurrenceFrequency) {
                                ForEach(RecurrenceFrequency.allCases) { freq in
                                    Text(freq.title).tag(freq)
                                }
                            }
                            if let recVal = BRLFormatters.parseAmount(amountText), recVal > 0 {
                                Text("Cobrança/recebimento contínuo (\(recurrenceFrequency.shortTitle)) no valor de \(BRLFormatters.currency(recVal)) enquanto não for cancelado.")
                                    .font(.caption)
                                    .foregroundStyle(Color(hex: "#06B6D4"))
                            } else {
                                Text("Ideal para contas contínuas (Energia, Água, Wellhub, Netflix mensal, Prime Video anual, Salário). Existirá automaticamente nos períodos futuros até você cancelar.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section("Status, Consolidação e Anexo") {
                    Toggle(
                        type == .expense ? "Pago (Desmarque para despesa não paga)" : "Recebido (Desmarque para receita pendente)",
                        isOn: $isPaid
                    )
                    .disabled(isSelectedDateInFuture)

                    if isSelectedDateInFuture {
                        Text("Não é possível marcar como \(type == .expense ? "paga" : "recebida") uma conta com data no futuro (\(BRLFormatters.shortDate(date))).")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }

                    Toggle(
                        "Ignorar no consolidado (Apenas registro, não soma/desconta no saldo)",
                        isOn: $ignoreInConsolidated
                    )

                    HStack {
                        Text("Anexo (Opcional):")
                        Spacer()
                        if let attName = attachmentName {
                            HStack(spacing: 6) {
                                Image(systemName: "paperclip")
                                Text(attName)
                                    .font(.caption)
                                    .lineLimit(1)
                                Button("Remover") {
                                    showRemoveAttachmentConfirmation = true
                                }
                                .buttonStyle(.link)
                            }
                        } else {
                            Button {
                                if let url = MacFilePicker.pickAttachmentFile(),
                                   let saved = store.copyAttachmentToStorage(from: url) {
                                    attachmentPath = saved.path
                                    attachmentName = saved.fileName
                                }
                            } label: {
                                Label("Anexar Arquivo do Mac...", systemImage: "paperclip")
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)

            if let validationError {
                Text(validationError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Button("Cancelar") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button(existingTransaction == nil ? "Salvar \(type.title)" : "Atualizar \(type.title)") {
                    saveAction()
                }
                .buttonStyle(.borderedProminent)
                .tint(type == .expense ? Color(hex: "#EF4444") : Color(hex: "#10B981"))
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 640, height: 640)
        .onAppear {
            if let existing = existingTransaction {
                type = existing.type
                name = existing.name
                details = existing.details
                amountText = BRLFormatters.currency(existing.amount)
                date = existing.date
                isPaid = store.isDateInFuture(existing.date) ? false : existing.isPaid
                categoryId = existing.categoryId
                accountId = existing.accountId
                ignoreInConsolidated = existing.ignoreInConsolidated
                attachmentPath = existing.attachmentPath
                attachmentName = existing.attachmentName
                recurrenceMode = existing.recurrenceMode
                recurrenceFrequency = existing.recurrenceFrequency ?? .monthly
            } else {
                // Sempre aponta a data inicial para o mês filtrado (`store.selectedMonth`)!
                let defaultDate = store.defaultTransactionDateForSelectedMonth()
                date = defaultDate
                isPaid = !store.isDateInFuture(defaultDate)
                categoryId = store.fallbackCategoryId(for: type)
                accountId = store.accounts.first?.id ?? UUID()
            }
        }
        .sheet(isPresented: $showEmbeddedStatementImporter) {
            StatementImportSheet(
                store: store,
                llmService: llmService,
                initialFilterMode: type == .expense ? .expensesOnly : .incomesOnly,
                onCompleteImport: {
                    dismiss()
                }
            )
        }
        .alert("Confirmar Remoção de Anexo", isPresented: $showRemoveAttachmentConfirmation) {
            Button("Remover Anexo", role: .destructive) {
                attachmentPath = nil
                attachmentName = nil
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Deseja realmente remover o anexo \"\(attachmentName ?? "")\" desta transação?")
        }
        .alert(
            "Como deseja aplicar a alteração?",
            isPresented: Binding(
                get: { pendingSeriesUpdateTransaction != nil },
                set: { if !$0 { pendingSeriesUpdateTransaction = nil } }
            ),
            presenting: pendingSeriesUpdateTransaction
        ) { updatedTx in
            Button("Alterar em todas as parcelas") {
                store.updateTransaction(updatedTx, scope: .allInSeries)
                pendingSeriesUpdateTransaction = nil
                dismiss()
            }
            Button("Somente naquela transação") {
                store.updateTransaction(updatedTx, scope: .onlyThis)
                pendingSeriesUpdateTransaction = nil
                dismiss()
            }
            Button("Da transação atual e todas no futuro") {
                store.updateTransaction(updatedTx, scope: .thisAndFuture)
                pendingSeriesUpdateTransaction = nil
                dismiss()
            }
            Button("Cancelar", role: .cancel) {
                pendingSeriesUpdateTransaction = nil
            }
        } message: { updatedTx in
            Text("Este lançamento faz parte de uma série (\(updatedTx.recurrenceMode.title.lowercased())). Escolha onde aplicar o novo valor de \(BRLFormatters.currency(updatedTx.amount)) e as demais alterações:")
        }
    }

    private func saveAction() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            validationError = "Informe o nome da transação."
            return
        }
        guard !store.accounts.isEmpty else {
            validationError = "Cadastre pelo menos uma conta bancária em Configurações → Contas antes de lançar transações."
            return
        }
        guard let parsedAmount = BRLFormatters.parseAmount(amountText), parsedAmount > 0 else {
            validationError = "Informe um valor válido maior que zero."
            return
        }

        let effectivePaid = store.isDateInFuture(date) ? false : isPaid

        if var existing = existingTransaction {
            existing.name = trimmedName
            existing.details = details.trimmingCharacters(in: .whitespacesAndNewlines)
            existing.amount = parsedAmount
            existing.date = date
            existing.type = type
            existing.isPaid = effectivePaid
            existing.categoryId = categoryId
            existing.accountId = accountId
            existing.ignoreInConsolidated = ignoreInConsolidated
            existing.attachmentPath = attachmentPath
            existing.attachmentName = attachmentName

            if existing.isPartOfSeries {
                pendingSeriesUpdateTransaction = existing
                return
            } else {
                store.updateTransaction(existing, scope: .onlyThis)
                dismiss()
            }
        } else {
            store.createTransaction(
                name: trimmedName,
                details: details.trimmingCharacters(in: .whitespacesAndNewlines),
                amount: parsedAmount,
                date: date,
                type: type,
                isPaid: effectivePaid,
                categoryId: categoryId,
                accountId: accountId,
                attachmentPath: attachmentPath,
                attachmentName: attachmentName,
                ignoreInConsolidated: ignoreInConsolidated,
                recurrenceMode: recurrenceMode,
                installmentsOrMonthsCount: installmentsOrMonthsCount,
                recurrenceFrequency: recurrenceFrequency
            )
            dismiss()
        }
    }
}

// MARK: - Statement Import Sheet (LLM Local Categorization + Deduplication)

public struct StatementImportSheet: View {
    @ObservedObject public var store: FinancialDataStore
    @ObservedObject public var llmService: LocalLLMService
    @Environment(\.dismiss) private var dismiss

    @State private var filterMode: StatementImportFilterMode
    @State private var selectedAccountId: UUID = UUID()
    @State private var selectedFileURL: URL? = nil
    @State private var selectedFileName: String = "Nenhum arquivo selecionado"
    @State private var parsedItems: [ParsedStatementTransaction] = []
    @State private var importSummaryMessage: String? = nil

    public var onCompleteImport: (() -> Void)? = nil

    public init(
        store: FinancialDataStore,
        llmService: LocalLLMService,
        initialFilterMode: StatementImportFilterMode = .hybrid,
        onCompleteImport: (() -> Void)? = nil
    ) {
        self.store = store
        self.llmService = llmService
        _filterMode = State(initialValue: initialFilterMode)
        self.onCompleteImport = onCompleteImport
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: "cpu.fill")
                            .foregroundStyle(Color(hex: "#6366F1"))
                        Text("Importar Relatório / Extrato Bancário com LLM Local")
                            .font(.title2.bold())
                    }
                    Text("Analisa extratos PDF/CSV/TXT usando a LLM local, separa por categoria com máximo de detalhes e evita transações duplicadas.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let activeModel = store.llmConfig.selectedModel {
                    Label(activeModel.displayName, systemImage: "checkmark.seal.fill")
                        .font(.caption.bold())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.green.opacity(0.15)))
                        .foregroundStyle(.green)
                }
            }

            // Controls bar
            HStack(spacing: 12) {
                Picker("Modo de Importação", selection: $filterMode) {
                    ForEach(StatementImportFilterMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .frame(width: 290)
                .onChange(of: filterMode) { _, _ in
                    if !parsedItems.isEmpty {
                        Task {
                            await reloadSampleIfNeeded()
                        }
                    }
                }

                Picker("Conta Destino", selection: $selectedAccountId) {
                    ForEach(store.accounts) { acc in
                        Text(acc.name).tag(acc.id)
                    }
                }
                .frame(width: 220)

                Spacer()

                Button {
                    if let url = MacFilePicker.pickStatementFile() {
                        selectedFileURL = url
                        selectedFileName = url.lastPathComponent
                        Task {
                            parsedItems = await llmService.analyzeStatementFile(
                                fileURL: url,
                                filterMode: filterMode,
                                store: store
                            )
                        }
                    }
                } label: {
                    Label("Selecionar Documento PDF no Mac", systemImage: "folder.fill")
                }
                .buttonStyle(.borderedProminent)
            }

            if llmService.isAnalyzingStatement {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text("A LLM local está analisando os lançamentos, identificando estabelecimentos e classificando categorias...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.indigo.opacity(0.1)))
            }

            // Preview Table
            if parsedItems.isEmpty && !llmService.isAnalyzingStatement {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "doc.viewfinder")
                        .font(.system(size: 44))
                        .foregroundStyle(.secondary)
                    Text("Clique em \"Selecionar Documento PDF no Mac\" para importar seu extrato ou relatório")
                        .font(.headline)
                    Text("Suporta importação de Apenas Despesas, Apenas Receitas ou Híbrido (Receitas + Despesas).")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
            } else {
                let duplicateCount = parsedItems.filter { store.transactionAlreadyExists($0, inAccountId: selectedAccountId) }.count
                let newCount = parsedItems.count - duplicateCount

                HStack {
                    Text("Arquivo: \(selectedFileName) • \(parsedItems.count) itens identificados pela LLM")
                        .font(.subheadline.bold())
                    Spacer()
                    Text("\(newCount) novas para adicionar")
                        .font(.caption.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.green.opacity(0.15)))
                        .foregroundStyle(.green)

                    if duplicateCount > 0 {
                        Text("\(duplicateCount) já existentes (serão ignoradas)")
                            .font(.caption.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.orange.opacity(0.15)))
                            .foregroundStyle(.orange)
                    }
                }

                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach($parsedItems) { $item in
                            let alreadyExists = store.transactionAlreadyExists(item, inAccountId: selectedAccountId)
                            HStack(spacing: 12) {
                                Text(BRLFormatters.shortDate(item.date))
                                    .font(.caption.monospacedDigit())
                                    .frame(width: 75, alignment: .leading)

                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(item.cleanTitle)
                                            .font(.subheadline.weight(.semibold))
                                        Text(item.paymentMethod)
                                            .font(.caption2)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 1)
                                            .background(Capsule().fill(Color.primary.opacity(0.07)))
                                    }
                                    Text(item.extractedDetails)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }

                                Spacer()

                                Picker("", selection: Binding(
                                    get: { item.suggestedCategoryId ?? store.fallbackCategoryId(for: item.type) },
                                    set: { newCatId in
                                        item.suggestedCategoryId = newCatId
                                        if let cat = store.category(for: newCatId) {
                                            item.suggestedCategoryName = cat.name
                                        }
                                    }
                                )) {
                                    ForEach(store.categories(for: item.type)) { cat in
                                        Text(cat.name).tag(cat.id)
                                    }
                                }
                                .frame(width: 195)

                                Text((item.type == .expense ? "- " : "+ ") + BRLFormatters.currency(item.amount))
                                    .font(.subheadline.bold())
                                    .foregroundStyle(item.type == .expense ? Color(hex: "#EF4444") : Color(hex: "#10B981"))
                                    .frame(width: 105, alignment: .trailing)

                                Text(alreadyExists ? "Já Existe" : "Nova")
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(Capsule().fill(alreadyExists ? Color.orange.opacity(0.16) : Color.green.opacity(0.16)))
                                    .foregroundStyle(alreadyExists ? .orange : .green)
                                    .frame(width: 72)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
                        }
                    }
                }
            }

            if let summaryMsg = importSummaryMessage {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(summaryMsg)
                        .font(.subheadline.weight(.medium))
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.green.opacity(0.12)))
            }

            HStack {
                Button("Fechar") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button {
                    guard !store.accounts.isEmpty else {
                        importSummaryMessage = "Atenção: Cadastre pelo menos uma conta bancária em Configurações → Contas antes de importar transações."
                        return
                    }
                    let summary = store.importParsedTransactions(
                        parsedItems,
                        intoAccountId: selectedAccountId,
                        filterMode: filterMode
                    )
                    importSummaryMessage = "Importação concluída: \(summary.addedCount) novas transações adicionadas (\(summary.addedExpenses) despesas, \(summary.addedIncomes) receitas) e \(summary.skippedDuplicatesCount) duplicadas ignoradas."
                    if let firstDate = parsedItems.first?.date {
                        store.selectedMonth = firstDate
                    }
                    onCompleteImport?()
                } label: {
                    Label("Confirmar e Adicionar Transações Não Duplicadas", systemImage: "checkmark.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(hex: "#10B981"))
                .disabled(parsedItems.isEmpty)
            }
        }
        .padding(22)
        .frame(width: 900, height: 620)
        .onAppear {
            selectedAccountId = store.accounts.first(where: { $0.bankPresetId == "itau" })?.id
                ?? store.accounts.first?.id
                ?? UUID()
        }
    }

    private func reloadSampleIfNeeded() async {
        if let url = selectedFileURL {
            parsedItems = await llmService.analyzeStatementFile(
                fileURL: url,
                filterMode: filterMode,
                store: store
            )
        }
    }
}
