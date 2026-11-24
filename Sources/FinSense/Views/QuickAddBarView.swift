import SwiftUI

public struct QuickAddBarView: View {
    @ObservedObject public var store: FinancialDataStore
    public var onDismiss: () -> Void

    @State private var rawInput: String = ""
    @State private var draft: QuickAddDraft? = nil
    @State private var selectedCategoryId: UUID = UUID()
    @State private var selectedAccountId: UUID? = nil
    @State private var selectedCreditCardId: UUID? = nil
    @State private var selectedInstallments: Int = 1
    @State private var isReimbursable: Bool = false
    @State private var debtorText: String = ""
    @State private var selectedCurrency: String = "BRL"
    @State private var savedConfirmation: String? = nil
    @FocusState private var isInputFocused: Bool

    public init(store: FinancialDataStore, onDismiss: @escaping () -> Void = {}) {
        self.store = store
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "bolt.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Color(hex: "#6366F1"))

                TextField(
                    "Ex: 185 mercado nubank • 1200 em 3x tênis cartão • 250 combustível reembolsável empresa",
                    text: $rawInput
                )
                .textFieldStyle(.plain)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .focused($isInputFocused)
                .onSubmit {
                    confirmQuickAdd()
                }
                .onChange(of: rawInput) { _, newValue in
                    reparse(newValue)
                }

                if !rawInput.isEmpty {
                    Button {
                        rawInput = ""
                        draft = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                Button("Esc") {
                    onDismiss()
                }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .textBackgroundColor)))

            if let d = draft, d.amount > 0 {
                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Label(d.cleanTitle, systemImage: d.type == .expense ? "arrow.up.right.circle.fill" : "arrow.down.left.circle.fill")
                            .font(.subheadline.bold())
                            .foregroundStyle(d.type == .expense ? Color(hex: "#EF4444") : Color(hex: "#10B981"))

                        Spacer()

                        Text(BRLFormatters.currency(d.amount, currencyCode: selectedCurrency))
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(d.type == .expense ? Color(hex: "#EF4444") : Color(hex: "#10B981"))
                            .monospacedDigit()

                        if selectedCurrency != "BRL" {
                            let brlVal = store.convertToBRL(d.amount, currencyCode: selectedCurrency)
                            Text("≈ \(BRLFormatters.currency(brlVal))")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Chips editáveis
                    HStack(spacing: 8) {
                        Picker("Categoria", selection: $selectedCategoryId) {
                            ForEach(store.categories(for: d.type)) { cat in
                                Text(cat.name).tag(cat.id)
                            }
                        }
                        .frame(maxWidth: 165)

                        if d.type == .expense && !store.creditCards.isEmpty {
                            Picker("Destino", selection: Binding(
                                get: { selectedCreditCardId.map { "card:\($0.uuidString)" } ?? selectedAccountId.map { "acc:\($0.uuidString)" } ?? "" },
                                set: { val in
                                    if val.hasPrefix("card:"), let uuid = UUID(uuidString: String(val.dropFirst(5))) {
                                        selectedCreditCardId = uuid
                                        selectedAccountId = nil
                                    } else if val.hasPrefix("acc:"), let uuid = UUID(uuidString: String(val.dropFirst(4))) {
                                        selectedAccountId = uuid
                                        selectedCreditCardId = nil
                                    }
                                }
                            )) {
                                ForEach(store.accounts) { acc in
                                    Text("🏦 \(acc.name)").tag("acc:\(acc.id.uuidString)")
                                }
                                ForEach(store.creditCards) { card in
                                    Text("💳 \(card.name)").tag("card:\(card.id.uuidString)")
                                }
                            }
                            .frame(maxWidth: 175)
                        } else {
                            Picker("Conta", selection: $selectedAccountId) {
                                ForEach(store.accounts) { acc in
                                    Text("🏦 \(acc.name)").tag(UUID?.some(acc.id))
                                }
                            }
                            .frame(maxWidth: 175)
                        }

                        if d.type == .expense {
                            Stepper("\(selectedInstallments)x", value: $selectedInstallments, in: 1...24)
                                .frame(width: 85)

                            Toggle("Reembolsável", isOn: $isReimbursable)
                                .toggleStyle(.switch)
                                .controlSize(.small)
                        }
                    }
                    .font(.caption)

                    if isReimbursable {
                        HStack(spacing: 8) {
                            TextField("Quem irá reembolsar? (Ex: Empresa, João)", text: $debtorText)
                                .textFieldStyle(.roundedBorder)
                                .font(.caption)
                            Picker("Moeda", selection: $selectedCurrency) {
                                ForEach(SupportedCurrency.allCases) { cur in
                                    Text(cur.rawValue).tag(cur.rawValue)
                                }
                            }
                            .frame(width: 85)
                        }
                    }

                    HStack {
                        Text("Pressione ⏎ Enter para lançar instantaneamente")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Lançar Agora") {
                            confirmQuickAdd()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color(hex: "#10B981"))
                        .keyboardShortcut(.defaultAction)
                    }
                }
            } else {
                HStack(spacing: 8) {
                    Text("Dicas:")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Text("\"185 mercado nubank\" • \"1200 em 3x tênis cartão\" • \"250 combustível reembolsável empresa\"")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            if let msg = savedConfirmation {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(msg)
                        .font(.caption.weight(.semibold))
                }
            }
        }
        .padding(18)
        .frame(width: 640)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.25), radius: 22, y: 10)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .onAppear {
            isInputFocused = true
            if selectedAccountId == nil {
                selectedAccountId = store.accounts.first?.id
            }
        }
    }

    private func reparse(_ input: String) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            draft = nil
            return
        }
        let parsed = QuickAddParserService.parse(trimmed, store: store)
        draft = parsed
        selectedCategoryId = parsed.categoryId
        selectedAccountId = parsed.targetAccountId ?? store.accounts.first?.id
        selectedCreditCardId = parsed.targetCreditCardId
        selectedInstallments = parsed.installmentsCount
        isReimbursable = parsed.isReimbursable
        debtorText = parsed.reimbursableDebtor ?? ""
        selectedCurrency = parsed.currencyCode
    }

    private func confirmQuickAdd() {
        guard let d = draft, d.amount > 0 else { return }
        let isCard = selectedCreditCardId != nil && d.type == .expense
        let targetAcc = isCard ? (selectedCreditCardId ?? UUID()) : (selectedAccountId ?? store.accounts.first?.id ?? UUID())
        guard store.creditCard(for: targetAcc) != nil || store.account(for: targetAcc) != nil else { return }

        store.createExtendedTransaction(
            name: d.cleanTitle,
            details: "Quick-Add: \(rawInput)",
            amount: d.amount,
            date: d.date,
            type: d.type,
            isPaid: isCard ? true : !store.isDateInFuture(d.date),
            categoryId: selectedCategoryId,
            accountId: targetAcc,
            ignoreInConsolidated: false,
            recurrenceMode: (d.type == .expense && selectedInstallments >= 2) ? .installment : .single,
            installmentsOrMonthsCount: selectedInstallments,
            creditCardId: isCard ? selectedCreditCardId : nil,
            currencyCode: selectedCurrency,
            isReimbursable: isReimbursable && d.type == .expense,
            reimbursableAmount: isReimbursable ? d.amount : nil,
            reimbursableDebtor: isReimbursable ? debtorText : nil,
            needsReview: false,
            sourceApp: "quick_add_mac"
        )
        savedConfirmation = "Lançado: \(d.cleanTitle) (\(BRLFormatters.currency(d.amount, currencyCode: selectedCurrency)))"
        rawInput = ""
        draft = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            onDismiss()
        }
    }
}
