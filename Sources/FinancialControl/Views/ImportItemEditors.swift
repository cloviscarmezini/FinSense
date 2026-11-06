import SwiftUI

// MARK: - Editor de Item de Transação Encontrado no Relatório (antes de importar)

public struct ParsedTransactionItemEditorSheet: View {
    @ObservedObject public var store: FinancialDataStore
    @Environment(\.dismiss) private var dismiss

    public let originalItem: ParsedStatementTransaction
    public let onSave: (ParsedStatementTransaction) -> Void

    @State private var title: String = ""
    @State private var details: String = ""
    @State private var amountText: String = ""
    @State private var date: Date = Date()
    @State private var type: TransactionType = .expense
    @State private var categoryId: UUID = UUID()
    @State private var recurrenceMode: TransactionRecurrenceMode = .single
    @State private var installmentsCount: Int = 2
    @State private var recurrenceFrequency: RecurrenceFrequency = .monthly
    @State private var errorMsg: String? = nil

    public init(
        store: FinancialDataStore,
        item: ParsedStatementTransaction,
        onSave: @escaping (ParsedStatementTransaction) -> Void
    ) {
        self.store = store
        self.originalItem = item
        self.onSave = onSave
    }

    public var body: some View {
        let availableModes = TransactionRecurrenceMode.availableModes(for: type)

        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Editar Item do Relatório")
                    .font(.title2.bold())
                Text("Ajuste as informações extraídas pela LLM local antes de importar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Linha original: \(originalItem.rawLine)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Form {
                Section("Dados do Lançamento") {
                    Picker("Tipo", selection: $type) {
                        ForEach(TransactionType.allCases) { t in
                            Text(t.title).tag(t)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: type) { _, newType in
                        if store.category(for: categoryId)?.type != newType {
                            categoryId = store.fallbackCategoryId(for: newType)
                        }
                        if newType == .income && recurrenceMode == .installment {
                            recurrenceMode = .repeated
                        }
                    }

                    BorderedTextField(
                        label: "Nome",
                        placeholder: "Ex: Faculdade FIAP",
                        text: $title
                    )

                    HStack(alignment: .bottom, spacing: 14) {
                        BRLCurrencyTextField(
                            label: recurrenceMode == .installment ? "Valor de Cada Parcela (R$)" : "Valor (R$)",
                            text: $amountText
                        )
                        DatePicker(
                            recurrenceMode == .single ? "Data" : "Data de Início",
                            selection: $date,
                            displayedComponents: [.date]
                        )
                    }

                    Picker("Categoria", selection: $categoryId) {
                        ForEach(store.categories(for: type)) { cat in
                            Label(cat.name, systemImage: cat.iconSymbol).tag(cat.id)
                        }
                    }

                    BorderedTextField(
                        label: "Detalhes (Opcional)",
                        placeholder: "Observações sobre o lançamento",
                        text: $details
                    )
                }

                Section("Modalidade") {
                    Picker("Modalidade", selection: $recurrenceMode) {
                        ForEach(availableModes) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    if recurrenceMode == .installment {
                        EditableIntegerStepperField(
                            label: "Quantidade de Parcelas",
                            value: $installmentsCount,
                            range: 2...240,
                            unitSuffix: "parcelas"
                        )
                        if let perInst = BRLFormatters.parseAmount(amountText), perInst > 0 {
                            Text("\(installmentsCount)x de \(BRLFormatters.currency(perInst)) • Total: \(BRLFormatters.currency(perInst * Double(installmentsCount)))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else if recurrenceMode == .repeated {
                        EditableIntegerStepperField(
                            label: "Quantidade de Meses",
                            value: $installmentsCount,
                            range: 2...240,
                            unitSuffix: "meses"
                        )
                    } else if recurrenceMode == .recurring {
                        Picker("Frequência", selection: $recurrenceFrequency) {
                            ForEach(RecurrenceFrequency.allCases) { freq in
                                Text(freq.title).tag(freq)
                            }
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
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Salvar Alterações do Item") {
                    saveAction()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 600, height: 640)
        .onAppear {
            title = originalItem.cleanTitle
            details = originalItem.extractedDetails
            amountText = BRLFormatters.currency(originalItem.amount)
            date = originalItem.date
            type = originalItem.type
            categoryId = originalItem.suggestedCategoryId
                ?? originalItem.explicitCategoryName.flatMap { explicit in
                    StatementImportService.matchCategory(
                        explicitCategoryName: explicit,
                        cleanTitle: originalItem.cleanTitle,
                        rawDescription: originalItem.rawDescription,
                        type: originalItem.type,
                        categories: store.categories
                    )?.id
                }
                ?? store.fallbackCategoryId(for: originalItem.type)
            recurrenceMode = originalItem.recurrenceMode
            installmentsCount = max(originalItem.installmentsCount, 2)
            recurrenceFrequency = originalItem.recurrenceFrequency
        }
    }

    private func saveAction() {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else {
            errorMsg = "Informe o nome do lançamento."
            return
        }
        guard let amount = BRLFormatters.parseAmount(amountText), amount > 0 else {
            errorMsg = "Informe um valor válido maior que zero."
            return
        }

        var updated = originalItem
        updated.cleanTitle = cleanTitle
        updated.extractedDetails = details.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.amount = amount
        updated.date = date
        updated.type = type

        let categoryChanged = categoryId != originalItem.suggestedCategoryId || type != originalItem.type
        updated.suggestedCategoryId = categoryId
        updated.suggestedCategoryName = store.category(for: categoryId)?.name ?? updated.suggestedCategoryName
        if categoryChanged {
            // A categoria escolhida manualmente prevalece sobre a categoria explícita extraída do texto
            updated.explicitCategoryName = nil
        }

        updated.recurrenceMode = recurrenceMode
        updated.installmentsCount = recurrenceMode == .single || recurrenceMode == .recurring ? 1 : max(installmentsCount, 2)
        updated.recurrenceFrequency = recurrenceFrequency

        let recurrenceChanged = recurrenceMode != originalItem.recurrenceMode ||
            updated.installmentsCount != originalItem.installmentsCount ||
            recurrenceFrequency != originalItem.recurrenceFrequency
        if recurrenceChanged {
            updated.paymentMethod = recurrenceMode == .single
                ? (type == .expense ? "Despesa" : "Receita")
                : updated.recurrenceSummaryBadge
        }

        onSave(updated)
        dismiss()
    }
}

// MARK: - Editor de Item de Dívida Encontrado no Relatório (antes de importar)

public struct ParsedDebtItemEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    public let originalItem: ParsedDebtImportItem
    public let onSave: (ParsedDebtImportItem) -> Void

    @State private var name: String = ""
    @State private var amountText: String = ""
    @State private var hasContractedDate: Bool = false
    @State private var contractedDate: Date = Date()
    @State private var selectedBankPresetId: String? = nil
    @State private var colorHex: String = "#EF4444"
    @State private var notes: String = ""
    @State private var errorMsg: String? = nil

    public init(item: ParsedDebtImportItem, onSave: @escaping (ParsedDebtImportItem) -> Void) {
        self.originalItem = item
        self.onSave = onSave
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Editar Dívida do Relatório")
                    .font(.title2.bold())
                Text("Linha original: \(originalItem.rawLine)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Form {
                Section("Identificação e Valor") {
                    BorderedTextField(
                        label: "Nome da Dívida",
                        placeholder: "Ex: Cartão de crédito Nubank",
                        text: $name
                    )
                    BRLCurrencyTextField(
                        label: "Valor da Dívida (R$)",
                        text: $amountText
                    )
                    Toggle("Informar data em que contraiu a dívida (Opcional)", isOn: $hasContractedDate)
                    if hasContractedDate {
                        DatePicker("Data da Dívida", selection: $contractedDate, displayedComponents: [.date])
                    }
                }

                Section("Ícone da Instituição") {
                    HStack(spacing: 12) {
                        AccountAvatarView(
                            customImagePath: nil,
                            bankPresetId: selectedBankPresetId,
                            fallbackSymbol: originalItem.iconSymbol,
                            colorHex: colorHex,
                            size: 40
                        )
                        Picker("Banco / Instituição", selection: $selectedBankPresetId) {
                            Text("Ícone Padrão de Dívida").tag(String?.none)
                            ForEach(BrazilianBanksCatalog.presets) { preset in
                                Text(preset.name).tag(String?.some(preset.id))
                            }
                        }
                        .onChange(of: selectedBankPresetId) { _, newId in
                            if let preset = BrazilianBanksCatalog.preset(for: newId) {
                                colorHex = preset.primaryHex
                            }
                        }
                    }
                }

                Section("Observações (Opcional)") {
                    BorderedTextField(
                        label: "Observações",
                        placeholder: "Ex: Aguardando proposta de acordo",
                        text: $notes
                    )
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
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Salvar Alterações do Item") {
                    let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !cleanName.isEmpty else {
                        errorMsg = "Informe o nome da dívida."
                        return
                    }
                    guard let amount = BRLFormatters.parseAmount(amountText), amount > 0 else {
                        errorMsg = "Informe um valor válido maior que zero."
                        return
                    }
                    var updated = originalItem
                    updated.name = cleanName
                    updated.originalAmount = amount
                    updated.contractedDate = hasContractedDate ? contractedDate : nil
                    updated.bankPresetId = selectedBankPresetId
                    updated.colorHex = colorHex
                    updated.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
                    onSave(updated)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(hex: "#EF4444"))
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 540, height: 520)
        .onAppear {
            name = originalItem.name
            amountText = BRLFormatters.currency(originalItem.originalAmount)
            if let cd = originalItem.contractedDate {
                hasContractedDate = true
                contractedDate = cd
            }
            selectedBankPresetId = originalItem.bankPresetId
            colorHex = originalItem.colorHex
            notes = originalItem.notes
        }
    }
}
