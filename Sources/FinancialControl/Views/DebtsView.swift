import SwiftUI

public struct DebtsView: View {
    @ObservedObject public var store: FinancialDataStore
    @ObservedObject public var llmService: LocalLLMService

    @State private var showCreateDebtSheet: Bool = false
    @State private var editingDebt: DebtItem? = nil
    @State private var payingDebt: DebtItem? = nil
    @State private var debtPendingDeletion: DebtItem? = nil

    public init(store: FinancialDataStore, llmService: LocalLLMService) {
        self.store = store
        self.llmService = llmService
    }

    public var body: some View {
        let openDebts = store.activeDebts
        let totalOpenAmount = openDebts.reduce(0.0) { $0 + $1.originalAmount }

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Dívidas em Aberto & Negociação")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                        Text("Registre dívidas pendentes (ex: Cartão Mercado Pago, Serasa), negocie descontos e simule com a IA Local em quanto tempo quitá-las")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        store.openAIChat()
                    } label: {
                        Label("Perguntar à IA Local", systemImage: "sparkles.bubble.fill")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        showCreateDebtSheet = true
                    } label: {
                        Label("Nova Dívida", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(hex: "#EF4444"))
                }

                // Summary Strip
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 3), spacing: 14) {
                    MetricCardView(
                        title: "Total em Dívidas Pendentes",
                        value: BRLFormatters.currency(totalOpenAmount),
                        subtitle: "\(openDebts.count) dívida(s) aguardando pagamento/acordo",
                        icon: "exclamationmark.shield.fill",
                        tint: Color(hex: "#EF4444")
                    )

                    MetricCardView(
                        title: "Saldo Disponível em Contas",
                        value: BRLFormatters.currency(store.totalCheckingBalanceNow),
                        subtitle: "Para pagamento ou negociação à vista",
                        icon: "building.columns.fill",
                        tint: Color(hex: "#3B82F6")
                    )

                    MetricCardView(
                        title: "Dívidas Já Quitadas",
                        value: "\(store.paidDebts.count)",
                        subtitle: "Negociações concluídas e lançadas",
                        icon: "checkmark.seal.fill",
                        tint: Color(hex: "#10B981")
                    )
                }

                // Active Debts Cards Grid
                if openDebts.isEmpty {
                    VStack(spacing: 14) {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(Color(hex: "#10B981"))
                        Text("Nenhuma dívida pendente na listagem!")
                            .font(.title3.bold())
                        Text("Adicione uma dívida caso deseje acompanhar acordos futuros e analisar prazos de quitação com a IA local.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Button("Adicionar Dívida") {
                            showCreateDebtSheet = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, minHeight: 280)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .controlBackgroundColor)))
                } else {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 18), GridItem(.flexible(), spacing: 18)], spacing: 18) {
                        ForEach(openDebts) { debt in
                            debtCard(debt)
                        }
                    }
                }
            }
            .padding(24)
        }
        .sheet(isPresented: $showCreateDebtSheet) {
            DebtEditorSheet(store: store, existingDebt: nil)
        }
        .sheet(item: $editingDebt) { debt in
            DebtEditorSheet(store: store, existingDebt: debt)
        }
        .sheet(item: $payingDebt) { debt in
            PayDebtNegotiationSheet(store: store, debt: debt)
        }
        .alert(
            "Confirmar Exclusão de Dívida",
            isPresented: Binding(
                get: { debtPendingDeletion != nil },
                set: { if !$0 { debtPendingDeletion = nil } }
            ),
            presenting: debtPendingDeletion
        ) { debt in
            Button("Excluir Dívida", role: .destructive) {
                store.deleteDebt(debt.id)
                debtPendingDeletion = nil
            }
            Button("Cancelar", role: .cancel) {
                debtPendingDeletion = nil
            }
        } message: { debt in
            Text("Deseja realmente excluir a dívida \"\(debt.name)\" no valor de \(BRLFormatters.currency(debt.originalAmount))? Esta ação não pode ser desfeita.")
        }
    }

    @ViewBuilder
    private func debtCard(_ debt: DebtItem) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Card Header: Attached Image/Icon + Title + Contracted Date
            HStack(alignment: .top, spacing: 14) {
                AccountAvatarView(
                    customImagePath: debt.customImagePath,
                    bankPresetId: debt.bankPresetId,
                    fallbackSymbol: debt.iconSymbol,
                    colorHex: debt.colorHex,
                    size: 48
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(debt.name)
                        .font(.title3.bold())

                    if let contracted = debt.contractedDate {
                        Label("Contraída em \(BRLFormatters.shortDate(contracted))", systemImage: "calendar.badge.exclamationmark")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Data de contratação não informada")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Text("EM ABERTO")
                    .font(.caption2.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color(hex: "#EF4444").opacity(0.15)))
                    .foregroundStyle(Color(hex: "#EF4444"))
            }

            // Original Amount Box
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Valor da Dívida")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(BRLFormatters.currency(debt.originalAmount))
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color(hex: "#EF4444"))
                }

                Spacer()

                Button {
                    let question = "Usando como referência o meu modo de gastar e receitas, em quanto tempo devo pagar a dívida \"\(debt.name)\"?"
                    store.requireInstalledLLM(forFeature: "Simular Prazo da Dívida '\(debt.name)' na IA Local") {
                        store.isAIChatPresented = true
                        Task {
                            await llmService.sendUserQuestion(question, store: store)
                        }
                    }
                } label: {
                    Label("Simular Prazo na IA", systemImage: "sparkles")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .help("Perguntar à IA local em quanto tempo quitar esta dívida")
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.035)))

            if !debt.notes.isEmpty {
                Text(debt.notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Divider()

            // Action Buttons: Editar, Excluir, Pagar
            HStack(spacing: 10) {
                Button {
                    editingDebt = debt
                } label: {
                    Label("Editar", systemImage: "pencil")
                }
                .buttonStyle(.bordered)

                Button(role: .destructive) {
                    debtPendingDeletion = debt
                } label: {
                    Label("Excluir", systemImage: "trash")
                }
                .buttonStyle(.bordered)

                Spacer()

                Button {
                    payingDebt = debt
                } label: {
                    Label("Pagar / Negociar", systemImage: "checkmark.circle.fill")
                        .fontWeight(.semibold)
                        .padding(.horizontal, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(hex: "#10B981"))
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(hex: debt.colorHex).opacity(0.28), lineWidth: 1.2)
        )
    }
}

// MARK: - Debt Create / Edit Sheet

public struct DebtEditorSheet: View {
    @ObservedObject public var store: FinancialDataStore
    @Environment(\.dismiss) private var dismiss

    public let existingDebt: DebtItem?

    @State private var name: String = ""
    @State private var originalAmountText: String = ""
    @State private var hasContractedDate: Bool = false
    @State private var contractedDate: Date = Date()
    @State private var selectedBankPresetId: String? = "mercadopago"
    @State private var customImagePath: String? = nil
    @State private var customImageName: String? = nil
    @State private var showRemoveImageConfirmation: Bool = false
    @State private var colorHex: String = "#EF4444"
    @State private var notes: String = ""
    @State private var errorMsg: String? = nil

    public init(store: FinancialDataStore, existingDebt: DebtItem?) {
        self.store = store
        self.existingDebt = existingDebt
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(existingDebt == nil ? "Adicionar Dívida" : "Editar Dívida")
                .font(.title2.bold())

            Form {
                Section("Identificação e Valor") {
                    TextField("Nome da Dívida (Ex: Cartão Mercado Pago)", text: $name)
                    TextField("Valor da Dívida (R$)", text: $originalAmountText)

                    Toggle("Informar data em que contraiu a dívida (Opcional)", isOn: $hasContractedDate)
                    if hasContractedDate {
                        DatePicker("Data da Dívida", selection: $contractedDate, displayedComponents: [.date])
                    }
                }

                Section("Ícone ou Imagem Anexa da Máquina") {
                    HStack(spacing: 14) {
                        AccountAvatarView(
                            customImagePath: customImagePath,
                            bankPresetId: selectedBankPresetId,
                            fallbackSymbol: "creditcard.trianglebadge.exclamationmark",
                            colorHex: colorHex,
                            size: 48
                        )

                        VStack(alignment: .leading, spacing: 6) {
                            Button {
                                if let url = MacFilePicker.pickImageFile(),
                                   let saved = store.copyAttachmentToStorage(from: url) {
                                    customImagePath = saved.path
                                    customImageName = saved.fileName
                                }
                            } label: {
                                Label("Anexar Imagem / Ícone do Mac...", systemImage: "photo.badge.plus")
                            }

                            if customImagePath != nil {
                                Button("Remover imagem anexada") {
                                    showRemoveImageConfirmation = true
                                }
                                .buttonStyle(.link)
                                .font(.caption)
                            }
                        }
                    }

                    Picker("Ou escolher ícone de banco:", selection: $selectedBankPresetId) {
                        Text("Ícone Padrão de Dívida").tag(String?.none)
                        ForEach(BrazilianBanksCatalog.presets) { preset in
                            Text(preset.name).tag(String?.some(preset.id))
                        }
                    }
                    .onChange(of: selectedBankPresetId) { _, newPresetId in
                        if let preset = BrazilianBanksCatalog.preset(for: newPresetId) {
                            colorHex = preset.primaryHex
                        }
                    }
                }

                Section("Observações (Opcional)") {
                    TextField("Ex: Aguardando campanha de desconto para pagamento à vista", text: $notes)
                }
            }
            .formStyle(.grouped)

            if let errorMsg {
                Text(errorMsg)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Button("Cancelar") { dismiss() }
                Spacer()
                Button(existingDebt == nil ? "Criar Dívida" : "Salvar Alterações") {
                    let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !cleanName.isEmpty else {
                        errorMsg = "Informe o nome da dívida (ex: Cartão Mercado Pago)."
                        return
                    }
                    guard let val = BRLFormatters.parseAmount(originalAmountText), val > 0 else {
                        errorMsg = "Informe um valor válido maior que zero."
                        return
                    }

                    if var existing = existingDebt {
                        existing.name = cleanName
                        existing.originalAmount = val
                        existing.contractedDate = hasContractedDate ? contractedDate : nil
                        existing.customImagePath = customImagePath
                        existing.bankPresetId = selectedBankPresetId
                        existing.colorHex = colorHex
                        existing.notes = notes
                        store.updateDebt(existing)
                    } else {
                        store.addDebt(
                            name: cleanName,
                            customImagePath: customImagePath,
                            bankPresetId: selectedBankPresetId,
                            iconSymbol: "creditcard.trianglebadge.exclamationmark",
                            colorHex: colorHex,
                            originalAmount: val,
                            contractedDate: hasContractedDate ? contractedDate : nil,
                            notes: notes
                        )
                    }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(hex: "#EF4444"))
            }
        }
        .padding(22)
        .frame(width: 540, height: 520)
        .onAppear {
            if let existing = existingDebt {
                name = existing.name
                originalAmountText = BRLFormatters.decimalFormatter.string(from: NSNumber(value: existing.originalAmount)) ?? String(format: "%.2f", existing.originalAmount)
                if let cd = existing.contractedDate {
                    hasContractedDate = true
                    contractedDate = cd
                }
                customImagePath = existing.customImagePath
                selectedBankPresetId = existing.bankPresetId
                colorHex = existing.colorHex
                notes = existing.notes
            }
        }
        .alert("Confirmar Remoção de Imagem", isPresented: $showRemoveImageConfirmation) {
            Button("Remover Imagem", role: .destructive) {
                customImagePath = nil
                customImageName = nil
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Deseja realmente remover a imagem personalizada anexada a esta dívida?")
        }
    }
}

// MARK: - Pay Debt Negotiation Sheet (Pagar Dívida)

public struct PayDebtNegotiationSheet: View {
    @ObservedObject public var store: FinancialDataStore
    @Environment(\.dismiss) private var dismiss

    public let debt: DebtItem

    @State private var selectedAccountId: UUID = UUID()
    @State private var negotiatedAmountText: String = ""
    @State private var paymentDate: Date = Date()
    @State private var errorMsg: String? = nil

    public init(store: FinancialDataStore, debt: DebtItem) {
        self.store = store
        self.debt = debt
    }

    public var body: some View {
        let negotiatedVal = BRLFormatters.parseAmount(negotiatedAmountText) ?? debt.originalAmount
        let discount = debt.originalAmount - negotiatedVal

        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                AccountAvatarView(
                    customImagePath: debt.customImagePath,
                    bankPresetId: debt.bankPresetId,
                    fallbackSymbol: debt.iconSymbol,
                    colorHex: debt.colorHex,
                    size: 42
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pagar / Quitar Dívida: \(debt.name)")
                        .font(.title2.bold())
                    Text("Ao confirmar, será criada uma transação de pagamento na conta selecionada e o card será removido da listagem de dívidas.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Form {
                Section("Conta para Pagamento") {
                    Picker("De qual conta vai sair o pagamento", selection: $selectedAccountId) {
                        ForEach(store.accounts) { acc in
                            let bal = store.currentBalance(forAccount: acc.id)
                            Text("\(acc.name) (Saldo: \(BRLFormatters.currency(bal)))").tag(acc.id)
                        }
                    }

                    DatePicker("Data do Pagamento", selection: $paymentDate, displayedComponents: [.date])
                }

                Section("Valores do Acordo / Quitação") {
                    HStack {
                        Text("Valor Original (Fixo):")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(BRLFormatters.currency(debt.originalAmount))
                            .font(.headline)
                    }

                    TextField("Valor da Negociação (R$)", text: $negotiatedAmountText)
                        .font(.system(size: 15, weight: .bold))

                    if abs(discount) > 0.01 {
                        HStack {
                            Text(discount > 0 ? "Economia obtida na negociação:" : "Acréscimo sobre o valor original:")
                                .font(.caption)
                            Spacer()
                            Text(BRLFormatters.currency(abs(discount)))
                                .font(.caption.bold())
                                .foregroundStyle(discount > 0 ? Color(hex: "#10B981") : Color(hex: "#EF4444"))
                        }
                    }
                }
            }
            .formStyle(.grouped)

            if let errorMsg {
                Text(errorMsg)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Button("Cancelar") { dismiss() }
                Spacer()
                Button("Confirmar Pagamento e Remover Dívida") {
                    guard !store.accounts.isEmpty else {
                        errorMsg = "Cadastre uma conta em Configurações → Contas antes de registrar o pagamento."
                        return
                    }
                    guard let finalAmount = BRLFormatters.parseAmount(negotiatedAmountText), finalAmount > 0 else {
                        errorMsg = "Informe um valor de negociação válido."
                        return
                    }
                    store.payDebt(
                        debtId: debt.id,
                        fromAccountId: selectedAccountId,
                        negotiatedAmount: finalAmount,
                        paymentDate: paymentDate
                    )
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(hex: "#10B981"))
            }
        }
        .padding(22)
        .frame(width: 520, height: 430)
        .onAppear {
            selectedAccountId = store.accounts.first?.id ?? UUID()
            // Vem preenchido inicialmente com o valor original!
            negotiatedAmountText = BRLFormatters.decimalFormatter.string(from: NSNumber(value: debt.originalAmount))
                ?? String(format: "%.2f", debt.originalAmount)
        }
    }
}
