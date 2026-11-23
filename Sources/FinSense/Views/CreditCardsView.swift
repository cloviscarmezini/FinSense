import SwiftUI
import AppKit

// MARK: - Dedicated Desktop Credit Cards Management & Invoices Screen

public struct CreditCardsView: View {
    @ObservedObject public var store: FinancialDataStore
    @ObservedObject public var llmService: LocalLLMService

    @State private var selectedMonthKey: Int = {
        let cal = Calendar.current
        let now = Date()
        return cal.component(.year, from: now) * 100 + cal.component(.month, from: now)
    }()

    @State private var showCreateCardSheet: Bool = false
    @State private var editingCard: CreditCard? = nil
    @State private var cardPendingDelete: CreditCard? = nil

    @State private var showNewPurchaseSheet: Bool = false
    @State private var editingTransaction: FinancialTransaction? = nil
    @State private var transactionPendingDelete: FinancialTransaction? = nil
    @State private var payingSummary: CreditCardInvoiceSummary? = nil

    public init(store: FinancialDataStore, llmService: LocalLLMService) {
        self.store = store
        self.llmService = llmService
    }

    private var activeCard: CreditCard? {
        if let selectedId = store.selectedCreditCardIdForDetail,
           let found = store.creditCards.first(where: { $0.id == selectedId }) {
            return found
        }
        return store.creditCards.first
    }

    private var currentMonthKey: Int {
        let cal = Calendar.current
        let now = Date()
        return cal.component(.year, from: now) * 100 + cal.component(.month, from: now)
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerBar

                if store.creditCards.isEmpty {
                    emptyStateCard
                } else {
                    cardSelectorStrip

                    if let card = activeCard {
                        cardLimitHeroSection(card)
                        invoiceSection(for: card)
                    }
                }
            }
            .padding(24)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            syncSelectedCardAndMonth()
        }
        .onChange(of: store.selectedCreditCardIdForDetail) { _, _ in
            syncSelectedCardAndMonth(resetMonthIfNeeded: true)
        }
        .sheet(isPresented: $showCreateCardSheet) {
            CreditCardEditorSheet(store: store, existingCard: nil)
        }
        .sheet(item: $editingCard) { card in
            CreditCardEditorSheet(store: store, existingCard: card)
        }
        .sheet(item: $payingSummary) { summary in
            if let card = store.creditCard(for: summary.cardId) {
                PayCreditCardInvoiceSheet(store: store, card: card, summary: summary)
            }
        }
        .sheet(isPresented: $showNewPurchaseSheet) {
            TransactionEditorSheet(
                store: store,
                llmService: llmService,
                initialType: .expense,
                existingTransaction: nil,
                initialCreditCardId: activeCard?.id
            )
        }
        .sheet(item: $editingTransaction) { tx in
            TransactionEditorSheet(
                store: store,
                llmService: llmService,
                initialType: tx.type,
                existingTransaction: tx
            )
        }
        .confirmationDialog(
            "Excluir Cartão de Crédito?",
            isPresented: Binding(
                get: { cardPendingDelete != nil },
                set: { if !$0 { cardPendingDelete = nil } }
            ),
            presenting: cardPendingDelete
        ) { card in
            Button("Excluir Cartão", role: .destructive) {
                store.deleteCreditCard(card.id)
                cardPendingDelete = nil
                syncSelectedCardAndMonth(resetMonthIfNeeded: true)
            }
            Button("Cancelar", role: .cancel) {
                cardPendingDelete = nil
            }
        } message: { card in
            Text("O cartão \"\(card.name)\" será removido. Lançamentos vinculados perderão a associação com o cartão e projeções de faturas em aberto serão canceladas.")
        }
        .confirmationDialog(
            "Excluir Compra no Cartão?",
            isPresented: Binding(
                get: { transactionPendingDelete != nil },
                set: { if !$0 { transactionPendingDelete = nil } }
            ),
            presenting: transactionPendingDelete
        ) { tx in
            Button("Excluir Somente Esta Parcela", role: .destructive) {
                store.deleteTransaction(tx.id, scope: .onlyThis)
                transactionPendingDelete = nil
            }
            if tx.seriesGroupId != nil {
                Button("Excluir Todas as Parcelas da Série", role: .destructive) {
                    store.deleteTransaction(tx.id, scope: .allInSeries)
                    transactionPendingDelete = nil
                }
            }
            Button("Cancelar", role: .cancel) {
                transactionPendingDelete = nil
            }
        } message: { tx in
            Text("Deseja excluir \"\(tx.name)\" (\(BRLFormatters.currency(tx.amount)))? O total da fatura correspondente será recalculado automaticamente.")
        }
    }

    private func syncSelectedCardAndMonth(resetMonthIfNeeded: Bool = false) {
        if store.selectedCreditCardIdForDetail == nil || store.creditCard(for: store.selectedCreditCardIdForDetail) == nil {
            store.selectedCreditCardIdForDetail = store.creditCards.first?.id
        }
        guard let card = activeCard else { return }
        let months = store.allRelevantInvoiceMonths(for: card.id)
        if resetMonthIfNeeded || !months.contains(where: { $0.key == selectedMonthKey }) {
            let currentAllocated = CreditCardEngine.allocateInvoice(forPurchaseDate: Date(), card: card).yearMonthKey
            if months.contains(where: { $0.key == currentAllocated }) {
                selectedMonthKey = currentAllocated
            } else if months.contains(where: { $0.key == currentMonthKey }) {
                selectedMonthKey = currentMonthKey
            } else if let first = months.first {
                selectedMonthKey = first.key
            }
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Cartões de Crédito")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                Text("Limites disponíveis, fechamento de ciclo, faturas futuras e pagamentos sem contagem dupla.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if activeCard != nil {
                Button {
                    showNewPurchaseSheet = true
                } label: {
                    Label("Nova Compra no Cartão", systemImage: "cart.badge.plus")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
            }

            Button {
                showCreateCardSheet = true
            } label: {
                Label("Novo Cartão", systemImage: "plus.circle.fill")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Empty State

    private var emptyStateCard: some View {
        VStack(spacing: 16) {
            Image(systemName: "creditcard.trianglebadge.exclamationmark")
                .font(.system(size: 46))
                .foregroundStyle(Color.accentColor)

            Text("Nenhum Cartão de Crédito Cadastrado")
                .font(.title3.bold())

            Text("Cadastre seus cartões para separar o Regime de Competência (compras na categoria correta no mês da compra) do Regime de Caixa (saída do banco apenas no pagamento da fatura).")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)

            Button {
                showCreateCardSheet = true
            } label: {
                Label("Cadastrar Primeiro Cartão", systemImage: "plus.circle.fill")
                    .padding(.horizontal, 8)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 52)
        .padding(.horizontal, 24)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: - Card Selector Strip

    private var cardSelectorStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(store.creditCards) { card in
                    let isSelected = card.id == activeCard?.id
                    let used = store.usedLimit(for: card.id)
                    let available = store.availableLimit(for: card.id)

                    Button {
                        store.selectedCreditCardIdForDetail = card.id
                        syncSelectedCardAndMonth(resetMonthIfNeeded: true)
                    } label: {
                        HStack(spacing: 12) {
                            AccountAvatarView(
                                customImagePath: card.customImagePath,
                                bankPresetId: card.bankPresetId,
                                fallbackSymbol: card.iconSymbol,
                                colorHex: card.colorHex,
                                size: 42
                            )

                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(card.name)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)

                                    if !card.lastFourDigits.isEmpty {
                                        Text("•••• \(card.lastFourDigits)")
                                            .font(.caption.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                HStack(spacing: 8) {
                                    Text(card.brand.shortBadge)
                                        .font(.system(size: 10, weight: .bold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Capsule().fill(Color(hex: card.colorHex).opacity(0.16)))
                                        .foregroundStyle(Color(hex: card.colorHex))

                                    Text("Disp: \(BRLFormatters.currency(available))")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(used > card.totalLimit ? .red : .secondary)
                                }
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(isSelected ? Color(hex: card.colorHex).opacity(0.12) : Color(nsColor: .controlBackgroundColor))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(isSelected ? Color(hex: card.colorHex) : Color.primary.opacity(0.08), lineWidth: isSelected ? 2 : 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - Card Hero & Limit Progress Bar

    private func cardLimitHeroSection(_ card: CreditCard) -> some View {
        let used = store.usedLimit(for: card.id)
        let available = store.availableLimit(for: card.id)
        let ratio = card.totalLimit > 0 ? min(1.0, max(0.0, used / card.totalLimit)) : 0.0
        let defaultBankName = card.defaultPaymentAccountId.flatMap { store.account(for: $0)?.name } ?? "Não vinculada"

        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                AccountAvatarView(
                    customImagePath: card.customImagePath,
                    bankPresetId: card.bankPresetId,
                    fallbackSymbol: card.iconSymbol,
                    colorHex: card.colorHex,
                    size: 56
                )

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(card.name)
                            .font(.title2.bold())
                        Text(card.brand.rawValue)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color(hex: card.colorHex).opacity(0.15)))
                            .foregroundStyle(Color(hex: card.colorHex))
                        if !card.lastFourDigits.isEmpty {
                            Text("Final \(card.lastFourDigits)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack(spacing: 16) {
                        Label("Fecha dia \(card.closingDay)", systemImage: "calendar.badge.clock")
                        Label("Melhor compra dia \(card.bestPurchaseDay)", systemImage: "sparkles")
                        Label("Vence dia \(card.dueDay)", systemImage: "bell.badge")
                        Label("Débito: \(defaultBankName)", systemImage: "building.columns")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 8) {
                    Button {
                        editingCard = card
                    } label: {
                        Label("Editar Cartão", systemImage: "pencil")
                    }
                    .buttonStyle(.bordered)

                    Button(role: .destructive) {
                        cardPendingDelete = card
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.bordered)
                }
            }

            // Progress bar & 3 KPI metrics
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Uso de Limite")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int((ratio * 100).rounded()))% comprometido")
                        .font(.caption.bold())
                        .foregroundStyle(used > card.totalLimit ? .red : Color(hex: card.colorHex))
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.primary.opacity(0.08))
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(used > card.totalLimit ? Color.red : Color(hex: card.colorHex))
                            .frame(width: max(0, geo.size.width * ratio))
                    }
                }
                .frame(height: 10)

                HStack(spacing: 18) {
                    limitMetricPill(title: "Limite Total", value: BRLFormatters.currency(card.totalLimit), color: .primary)
                    limitMetricPill(title: "Limite Utilizado (Faturas em Aberto)", value: BRLFormatters.currency(used), color: used > 0 ? .orange : .secondary)
                    limitMetricPill(title: "Limite Disponível", value: BRLFormatters.currency(available), color: available > 0 ? .green : .red)
                }
                .padding(.top, 4)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(hex: card.colorHex).opacity(0.28), lineWidth: 1.2)
        )
    }

    private func limitMetricPill(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor).opacity(0.65))
        )
    }

    // MARK: - Invoice Browser & Transactions List

    private func invoiceSection(for card: CreditCard) -> some View {
        let relevantMonths = store.allRelevantInvoiceMonths(for: card.id)
        let components = CreditCardEngine.yearMonthComponents(fromKey: selectedMonthKey)
        let summary = store.invoiceSummary(for: card.id, year: components.year, month: components.month)

        return VStack(alignment: .leading, spacing: 16) {
            // Invoice month tabs
            VStack(alignment: .leading, spacing: 8) {
                Text("Faturas do Cartão (Anteriores, Atual e Parcelas Futuras)")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(relevantMonths, id: \.key) { item in
                            let itemSummary = store.invoiceSummary(for: card.id, year: item.year, month: item.month)
                            let isSelected = item.key == selectedMonthKey
                            let statusColor = Color(hex: itemSummary?.status.colorHex ?? CreditCardInvoiceStatus.open.colorHex)

                            Button {
                                selectedMonthKey = item.key
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 5) {
                                        Text(CreditCardEngine.shortInvoiceLabel(year: item.year, month: item.month))
                                            .font(.caption.bold())
                                        if let status = itemSummary?.status {
                                            Circle()
                                                .fill(Color(hex: status.colorHex))
                                                .frame(width: 6, height: 6)
                                        }
                                    }
                                    Text(BRLFormatters.currency(itemSummary?.totalAmount ?? 0))
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(isSelected ? .primary : .secondary)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(isSelected ? statusColor.opacity(0.14) : Color(nsColor: .controlBackgroundColor))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(isSelected ? statusColor : Color.primary.opacity(0.08), lineWidth: isSelected ? 1.6 : 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            if let summary {
                invoiceDetailCard(card: card, summary: summary)
            }
        }
    }

    private func invoiceDetailCard(card: CreditCard, summary: CreditCardInvoiceSummary) -> some View {
        let statusColor = Color(hex: summary.status.colorHex)
        let payAccountName = summary.paymentAccountId.flatMap { store.account(for: $0)?.name } ?? "Conta padrão"

        return VStack(alignment: .leading, spacing: 16) {
            // Invoice Summary Header + Primary CTA
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        Text("Fatura \(summary.monthYearLabel)")
                            .font(.title3.bold())

                        Label(summary.status.rawValue, systemImage: summary.status.iconSymbol)
                            .font(.caption.bold())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(statusColor.opacity(0.16)))
                            .foregroundStyle(statusColor)
                    }

                    HStack(spacing: 16) {
                        Label("Fechamento: \(BRLFormatters.shortDate(summary.closingDate))", systemImage: "lock.shield")
                        Label("Vencimento: \(BRLFormatters.shortDate(summary.dueDate))", systemImage: "calendar")
                        Label("Conta prevista: \(payAccountName)", systemImage: "building.columns")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    if summary.status == .paid, let paidDate = summary.paidDate {
                        Text("Fatura paga em \(BRLFormatters.shortDate(paidDate)) (\(BRLFormatters.currency(summary.paidAmount ?? summary.totalAmount))) via \(payAccountName).")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.green)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("Total da Fatura")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(BRLFormatters.currency(summary.totalAmount))
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(summary.status == .paid ? .green : .primary)
                }

                if summary.status != .paid && summary.totalAmount > 0.001 {
                    Button {
                        payingSummary = summary
                    } label: {
                        Label("Pagar Fatura", systemImage: "checkmark.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .controlSize(.large)
                } else if summary.status == .paid {
                    Label("Fatura Quitada", systemImage: "checkmark.seal.fill")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.green.opacity(0.14)))
                        .foregroundStyle(.green)
                }
            }

            Divider()

            // Transactions in this cycle
            if summary.transactions.isEmpty {
                HStack {
                    Image(systemName: "tray")
                        .foregroundStyle(.secondary)
                    Text("Nenhuma compra lançada nesta fatura.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Lançar Compra neste Cartão") {
                        showNewPurchaseSheet = true
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.vertical, 16)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Compras e Parcelas do Ciclo (\(summary.transactions.count))")
                            .font(.subheadline.bold())
                        Spacer()
                        Text("Contabilizadas em Competência nos gráficos e orçamentos")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    ForEach(summary.transactions) { tx in
                        invoiceTransactionRow(tx)
                    }
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private func invoiceTransactionRow(_ tx: FinancialTransaction) -> some View {
        let category = store.category(for: tx.categoryId)

        return HStack(spacing: 12) {
            CategoryBadgeView(category: category, size: 32)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(tx.name)
                        .font(.subheadline.weight(.semibold))
                    if let badge = tx.installmentBadge {
                        Text(badge)
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                            .foregroundStyle(Color.accentColor)
                    }
                }

                HStack(spacing: 8) {
                    Text(BRLFormatters.shortDate(tx.date))
                    Text("•")
                    Text(category?.name ?? "Sem categoria")
                    if !tx.details.isEmpty {
                        Text("•")
                        Text(tx.details).lineLimit(1)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Text(BRLFormatters.currency(tx.amount))
                .font(.subheadline.bold().monospacedDigit())

            Button {
                editingTransaction = tx
            } label: {
                Image(systemName: "pencil")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .help("Editar lançamento")

            Button(role: .destructive) {
                transactionPendingDelete = tx
            } label: {
                Image(systemName: "trash")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .help("Excluir lançamento")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor).opacity(0.65))
        )
    }
}

// MARK: - Credit Card Editor Sheet (Create & Edit)

public struct CreditCardEditorSheet: View {
    @ObservedObject public var store: FinancialDataStore
    @Environment(\.dismiss) private var dismiss

    public let existingCard: CreditCard?

    @State private var name: String = ""
    @State private var totalLimitText: String = ""
    @State private var closingDay: Int = 25
    @State private var bestPurchaseDay: Int = 26
    @State private var bestPurchaseManuallyEdited: Bool = false
    @State private var dueDay: Int = 5
    @State private var defaultPaymentAccountId: UUID? = nil
    @State private var brand: CreditCardBrand = .mastercard
    @State private var selectedPresetId: String? = "nubank"
    @State private var customImagePath: String? = nil
    @State private var colorHex: String = "#820AD1"
    @State private var lastFourDigits: String = ""
    @State private var errorMsg: String? = nil

    public init(store: FinancialDataStore, existingCard: CreditCard? = nil) {
        self.store = store
        self.existingCard = existingCard
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(existingCard == nil ? "Cadastro de Cartão de Crédito" : "Editar Cartão de Crédito")
                .font(.title2.bold())

            Form {
                Section("Dados do Cartão") {
                    BorderedTextField(
                        label: "Nome do Cartão",
                        placeholder: "Ex: Cartão Principal, Nubank Ultravioleta, Cartão da Mãe",
                        text: $name
                    )

                    HStack(alignment: .bottom, spacing: 12) {
                        BRLCurrencyTextField(
                            label: "Limite Total (R$)",
                            text: $totalLimitText
                        )

                        BorderedTextField(
                            label: "4 Últimos Dígitos (Opcional)",
                            placeholder: "Ex: 4821",
                            text: $lastFourDigits
                        )
                        .frame(width: 170)

                        VStack(alignment: .leading, spacing: 5) {
                            Text("Bandeira")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Picker("Bandeira", selection: $brand) {
                                ForEach(CreditCardBrand.allCases) { b in
                                    Text(b.rawValue).tag(b)
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(width: 170)
                    }
                }

                Section("Ciclo de Fatura & Conta de Pagamento") {
                    HStack(alignment: .bottom, spacing: 14) {
                        EditableIntegerStepperField(
                            label: "Dia de Fechamento (1–31)",
                            value: $closingDay,
                            range: 1...31
                        )

                        EditableIntegerStepperField(
                            label: "Melhor Dia de Compra (Sugerido)",
                            value: $bestPurchaseDay,
                            range: 1...31
                        )

                        EditableIntegerStepperField(
                            label: "Dia de Vencimento (1–31)",
                            value: $dueDay,
                            range: 1...31
                        )
                    }

                    Text("Regra de alocação: compras a partir do dia de fechamento (\(closingDay)) entram automaticamente na fatura do mês seguinte. Melhor dia sugerido: \(CreditCardEngine.suggestedBestPurchaseDay(forClosingDay: closingDay)).")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Picker("Conta Padrão para Pagamento da Fatura (Opcional)", selection: $defaultPaymentAccountId) {
                        Text("Usar conta bancária principal automaticamente").tag(UUID?.none)
                        ForEach(store.accounts) { acc in
                            Text(acc.name).tag(UUID?.some(acc.id))
                        }
                    }
                }

                Section("Identidade Visual (Banco ou Imagem)") {
                    HStack(spacing: 16) {
                        AccountAvatarView(
                            customImagePath: customImagePath,
                            bankPresetId: selectedPresetId,
                            fallbackSymbol: "creditcard.fill",
                            colorHex: colorHex,
                            size: 52
                        )

                        VStack(alignment: .leading, spacing: 6) {
                            Button {
                                if let url = MacFilePicker.pickImageFile(),
                                   let saved = store.copyAttachmentToStorage(from: url) {
                                    customImagePath = saved.path
                                }
                            } label: {
                                Label("Anexar Ícone ou Foto do Cartão...", systemImage: "photo.badge.plus")
                            }

                            if customImagePath != nil {
                                Button("Remover imagem anexada") {
                                    customImagePath = nil
                                }
                                .buttonStyle(.link)
                                .font(.caption)
                            }
                        }
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(BrazilianBanksCatalog.presets) { preset in
                                let isSelected = selectedPresetId == preset.id && customImagePath == nil
                                Button {
                                    selectedPresetId = preset.id
                                    colorHex = preset.primaryHex
                                    if name.trimmingCharacters(in: .whitespaces).isEmpty {
                                        name = "Cartão \(preset.name)"
                                    }
                                } label: {
                                    VStack(spacing: 6) {
                                        AccountAvatarView(
                                            customImagePath: nil,
                                            bankPresetId: preset.id,
                                            fallbackSymbol: preset.symbolName,
                                            colorHex: preset.primaryHex,
                                            size: 38
                                        )
                                        Text(preset.name)
                                            .font(.caption2)
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                    }
                                    .frame(width: 72)
                                    .padding(6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(isSelected ? Color(hex: preset.primaryHex).opacity(0.14) : Color.clear)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .stroke(isSelected ? Color(hex: preset.primaryHex) : Color.clear, lineWidth: 2)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                if let errorMsg {
                    Text(errorMsg)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancelar") { dismiss() }
                Button(existingCard == nil ? "Cadastrar Cartão" : "Salvar Alterações") {
                    saveCard()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(22)
        .frame(width: 660, height: 610)
        .onChange(of: closingDay) { _, newClosing in
            if !bestPurchaseManuallyEdited {
                bestPurchaseDay = CreditCardEngine.suggestedBestPurchaseDay(forClosingDay: newClosing)
            }
        }
        .onChange(of: bestPurchaseDay) { _, newBest in
            let suggested = CreditCardEngine.suggestedBestPurchaseDay(forClosingDay: closingDay)
            if newBest != suggested {
                bestPurchaseManuallyEdited = true
            }
        }
        .onChange(of: lastFourDigits) { _, newVal in
            let digits = String(newVal.filter { $0.isNumber }.prefix(4))
            if digits != newVal { lastFourDigits = digits }
        }
        .onAppear {
            if let card = existingCard {
                name = card.name
                totalLimitText = BRLFormatters.currency(card.totalLimit)
                closingDay = card.closingDay
                bestPurchaseDay = card.bestPurchaseDay
                bestPurchaseManuallyEdited = card.bestPurchaseDay != CreditCardEngine.suggestedBestPurchaseDay(forClosingDay: card.closingDay)
                dueDay = card.dueDay
                defaultPaymentAccountId = card.defaultPaymentAccountId
                brand = card.brand
                selectedPresetId = card.bankPresetId
                customImagePath = card.customImagePath
                colorHex = card.colorHex
                lastFourDigits = card.lastFourDigits
            } else {
                closingDay = 25
                bestPurchaseDay = CreditCardEngine.suggestedBestPurchaseDay(forClosingDay: 25)
                dueDay = 5
                defaultPaymentAccountId = store.accounts.first?.id
            }
        }
    }

    private func saveCard() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMsg = "Informe o nome do cartão."
            return
        }
        let limitValue = BRLFormatters.parseCurrencyInput(totalLimitText)
        guard limitValue > 0 else {
            errorMsg = "Informe um limite total maior que R$ 0,00."
            return
        }

        if var card = existingCard {
            card.name = trimmed
            card.totalLimit = limitValue
            card.closingDay = closingDay
            card.bestPurchaseDay = bestPurchaseDay
            card.dueDay = dueDay
            card.defaultPaymentAccountId = defaultPaymentAccountId
            card.brand = brand
            card.bankPresetId = selectedPresetId
            card.customImagePath = customImagePath
            card.colorHex = colorHex
            card.lastFourDigits = lastFourDigits
            store.updateCreditCard(card)
        } else {
            let created = store.addCreditCard(
                name: trimmed,
                totalLimit: limitValue,
                closingDay: closingDay,
                bestPurchaseDay: bestPurchaseDay,
                dueDay: dueDay,
                defaultPaymentAccountId: defaultPaymentAccountId,
                brand: brand,
                bankPresetId: selectedPresetId,
                customImagePath: customImagePath,
                iconSymbol: "creditcard.fill",
                colorHex: colorHex,
                lastFourDigits: lastFourDigits
            )
            store.selectedCreditCardIdForDetail = created.id
        }
        dismiss()
    }
}

// MARK: - Pay Credit Card Invoice Sheet (Confirm Account, Date, Amount)

public struct PayCreditCardInvoiceSheet: View {
    @ObservedObject public var store: FinancialDataStore
    @Environment(\.dismiss) private var dismiss

    public let card: CreditCard
    public let summary: CreditCardInvoiceSummary

    @State private var selectedAccountId: UUID = UUID()
    @State private var paymentDate: Date = Date()
    @State private var amountText: String = ""
    @State private var errorMsg: String? = nil

    public init(store: FinancialDataStore, card: CreditCard, summary: CreditCardInvoiceSummary) {
        self.store = store
        self.card = card
        self.summary = summary
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                AccountAvatarView(
                    customImagePath: card.customImagePath,
                    bankPresetId: card.bankPresetId,
                    fallbackSymbol: card.iconSymbol,
                    colorHex: card.colorHex,
                    size: 44
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pagar Fatura — \(card.name)")
                        .font(.title3.bold())
                    Text("Fatura \(summary.monthYearLabel) • Vencimento \(BRLFormatters.shortDate(summary.dueDate))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Form {
                Section("Confirmação do Pagamento (Regime de Caixa)") {
                    Picker("Conta de Origem (Débito Bancário)", selection: $selectedAccountId) {
                        ForEach(store.accounts) { acc in
                            Text("\(acc.name) (Saldo: \(BRLFormatters.currency(store.currentBalance(forAccount: acc.id))))")
                                .tag(acc.id)
                        }
                    }

                    DatePicker("Data Efetiva do Pagamento", selection: $paymentDate, displayedComponents: .date)

                    BRLCurrencyTextField(
                        label: "Valor a Pagar (R$)",
                        text: $amountText
                    )
                }

                Section {
                    Label(
                        "Ao confirmar, a fatura mudará para \"Paga\", o débito bancário será efetivado na conta selecionada e o limite correspondente do cartão será restabelecido — sem duplicar despesas por categoria.",
                        systemImage: "info.circle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                if let errorMsg {
                    Text(errorMsg)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancelar") { dismiss() }
                Button("Confirmar Pagamento da Fatura") {
                    confirmPayment()
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
        }
        .padding(22)
        .frame(width: 520, height: 430)
        .onAppear {
            selectedAccountId = summary.paymentAccountId
                ?? card.defaultPaymentAccountId
                ?? store.accounts.first?.id
                ?? UUID()
            paymentDate = Date()
            amountText = BRLFormatters.currency(summary.totalAmount)
        }
    }

    private func confirmPayment() {
        guard !store.accounts.isEmpty, store.account(for: selectedAccountId) != nil else {
            errorMsg = "Cadastre ou selecione uma conta bancária válida para pagar a fatura."
            return
        }
        let amount = BRLFormatters.parseCurrencyInput(amountText)
        guard amount > 0 else {
            errorMsg = "Informe um valor de pagamento válido."
            return
        }
        let ok = store.payCreditCardInvoice(
            cardId: card.id,
            year: summary.year,
            month: summary.month,
            fromAccountId: selectedAccountId,
            amount: amount,
            paymentDate: paymentDate
        )
        if ok {
            dismiss()
        } else {
            errorMsg = "Não foi possível registrar o pagamento desta fatura."
        }
    }
}
