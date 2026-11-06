import SwiftUI

public struct SettingsView: View {
    @ObservedObject public var store: FinancialDataStore
    @ObservedObject public var llmService: LocalLLMService

    public init(store: FinancialDataStore, llmService: LocalLLMService) {
        self.store = store
        self.llmService = llmService
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Header + Section Tabs
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Configurações do Sistema")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                    Text("Configure sua LLM local via Hugging Face, gerencie contas bancárias e personalize categorias de despesas e receitas")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Picker("Seção", selection: $store.selectedSettingsSection) {
                    ForEach(SettingsSection.allCases) { sec in
                        Label(sec.title, systemImage: sec.icon).tag(sec)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 480)
            }

            Divider()

            switch store.selectedSettingsSection {
            case .llm:
                LLMConfigurationSectionView(store: store, llmService: llmService)
            case .accounts:
                AccountsManagementSectionView(store: store)
            case .categories:
                CategoriesManagementSectionView(store: store)
            }
        }
        .padding(24)
    }
}

// MARK: - 1. Configuração da LLM Local (Hugging Face Token, Download, Select & Delete)

public struct LLMConfigurationSectionView: View {
    @ObservedObject public var store: FinancialDataStore
    @ObservedObject public var llmService: LocalLLMService

    @State private var hfTokenInput: String = ""
    @State private var modelNameInput: String = "Qwen/Qwen2.5-3B-Instruct-GGUF"
    @State private var showTokenPlain: Bool = false

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Card 1: Hugging Face Token & Download Model
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Image(systemName: "cpu.fill")
                            .font(.title2)
                            .foregroundStyle(Color(hex: "#6366F1"))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Configuração e Download da LLM Local (Hugging Face)")
                                .font(.title3.bold())
                            Text("Informe seu token do Hugging Face e o nome do repositório do modelo para baixá-lo para o seu Mac.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Token do Hugging Face (hf_...)")
                            .font(.subheadline.weight(.semibold))
                        HStack(spacing: 10) {
                            if showTokenPlain {
                                TextField("Ex: hf_xxxxxxxxxxxxxxxxxxxxxxxxxxxx", text: $hfTokenInput)
                                    .textFieldStyle(.roundedBorder)
                            } else {
                                SecureField("Ex: hf_xxxxxxxxxxxxxxxxxxxxxxxxxxxx", text: $hfTokenInput)
                                    .textFieldStyle(.roundedBorder)
                            }
                            Button {
                                showTokenPlain.toggle()
                            } label: {
                                Image(systemName: showTokenPlain ? "eye.slash" : "eye")
                            }
                            .buttonStyle(.bordered)
                            .help("Mostrar / ocultar token")

                            Button("Salvar Token") {
                                store.llmConfig.huggingFaceToken = hfTokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
                                store.save()
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Nome do Modelo no Hugging Face")
                            .font(.subheadline.weight(.semibold))
                        HStack(spacing: 10) {
                            TextField("Ex: Qwen/Qwen2.5-3B-Instruct-GGUF", text: $modelNameInput)
                                .textFieldStyle(.roundedBorder)

                            if llmService.isDownloading {
                                Button(role: .destructive) {
                                    llmService.cancelDownload()
                                } label: {
                                    Label("Cancelar", systemImage: "xmark.circle.fill")
                                }
                                .buttonStyle(.bordered)
                            } else {
                                Button {
                                    llmService.downloadModel(
                                        modelRepoId: modelNameInput,
                                        huggingFaceToken: hfTokenInput,
                                        into: store
                                    )
                                } label: {
                                    Label("Baixar Modelo", systemImage: "arrow.down.circle.fill")
                                        .fontWeight(.semibold)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(Color(hex: "#6366F1"))
                            }
                        }

                        // Quick Model Suggestions
                        HStack(spacing: 8) {
                            Text("Sugestões para Mac:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            ForEach(LocalLLMService.suggestedModels, id: \.id) { sug in
                                Button(sug.name) {
                                    modelNameInput = sug.id
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                    }

                    if llmService.isDownloading || !llmService.downloadStatusMessage.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(llmService.downloadStatusMessage)
                                    .font(.caption.weight(.medium))
                                Spacer()
                                if llmService.isDownloading {
                                    Text(String(format: "%.0f%%", llmService.downloadProgress * 100))
                                        .font(.caption.bold())
                                }
                            }
                            if llmService.isDownloading {
                                ProgressView(value: llmService.downloadProgress)
                                    .tint(Color(hex: "#6366F1"))
                            }
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.indigo.opacity(0.08)))
                    }

                    if let err = llmService.lastErrorMessage {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                            Text(err)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }
                .padding(20)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .controlBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.08), lineWidth: 1))

                // Card 2: Modelos Locais Baixados (Selecionar e Deletar)
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Modelos Locais Instalados no Mac")
                                .font(.title3.bold())
                            Text("Selecione qual modelo a aplicação deve usar na importação de extratos e no Chat Financeiro, ou delete modelos locais para liberar espaço.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(store.llmConfig.downloadedModels.count) modelo(s) local(is)")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                    }

                    if store.llmConfig.downloadedModels.isEmpty {
                        HStack(spacing: 12) {
                            Image(systemName: "externaldrive.badge.plus")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Nenhum modelo baixado ainda")
                                    .font(.subheadline.weight(.semibold))
                                Text("Digite o nome de um modelo acima e clique em 'Baixar Modelo' para adicioná-lo à lista.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.03)))
                    } else {
                        ForEach(store.llmConfig.downloadedModels) { model in
                            let isSelected = store.llmConfig.selectedModelId == model.id
                            HStack(spacing: 14) {
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(isSelected ? Color(hex: "#10B981") : .secondary)

                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 8) {
                                        Text(model.id)
                                            .font(.headline)
                                        Text(model.quantization)
                                            .font(.caption2.bold())
                                            .padding(.horizontal, 7)
                                            .padding(.vertical, 2)
                                            .background(Capsule().fill(Color.blue.opacity(0.15)))
                                            .foregroundStyle(.blue)
                                        if isSelected {
                                            Text("EM USO")
                                                .font(.caption2.bold())
                                                .padding(.horizontal, 7)
                                                .padding(.vertical, 2)
                                                .background(Capsule().fill(Color.green.opacity(0.15)))
                                                .foregroundStyle(.green)
                                        }
                                    }
                                    Text("Arquivo: \(model.fileName) • Tamanho est.: \(model.formattedSize) • Baixado em \(BRLFormatters.shortDate(model.downloadedAt))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                if !isSelected {
                                    Button("Selecionar Modelo") {
                                        llmService.selectModel(model.id, in: store)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(Color(hex: "#6366F1"))
                                }

                                Button(role: .destructive) {
                                    llmService.deleteModel(model.id, from: store)
                                } label: {
                                    Label("Deletar Modelo Local", systemImage: "trash")
                                }
                                .buttonStyle(.bordered)
                            }
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(isSelected ? Color(hex: "#10B981").opacity(0.07) : Color.primary.opacity(0.03))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(isSelected ? Color(hex: "#10B981").opacity(0.4) : Color.clear, lineWidth: 1.2)
                            )
                        }
                    }
                }
                .padding(20)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .controlBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.08), lineWidth: 1))
            }
        }
        .onAppear {
            hfTokenInput = store.llmConfig.huggingFaceToken
        }
    }
}

// MARK: - 2. Gestão de Contas (Cadastro de Conta com Nome + Ícone/Imagem da Máquina ou Base de Bancos)

public struct AccountsManagementSectionView: View {
    @ObservedObject public var store: FinancialDataStore

    @State private var showCreateAccountSheet: Bool = false
    @State private var editingAccount: BankAccount? = nil

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Contas Bancárias & Carteiras")
                        .font(.title3.bold())
                    Text("Base inicial com os principais bancos e ícones oficiais, além da opção de anexar qualquer imagem/ícone da sua máquina")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    showCreateAccountSheet = true
                } label: {
                    Label("Adicionar Conta", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderedProminent)
            }

            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 16) {
                    ForEach(store.accounts) { account in
                        let currentBal = store.currentBalance(forAccount: account.id)
                        HStack(spacing: 14) {
                            AccountAvatarView(account: account, size: 48)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(account.name)
                                    .font(.headline)
                                if !account.agency.isEmpty || !account.accountNumber.isEmpty {
                                    Text("Agência: \(account.agency) • Conta: \(account.accountNumber)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Text("Saldo Inicial: \(BRLFormatters.currency(account.initialBalance))")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 6) {
                                Text(BRLFormatters.currency(currentBal))
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .foregroundStyle(currentBal >= 0 ? Color(hex: "#10B981") : Color(hex: "#EF4444"))

                                HStack(spacing: 6) {
                                    Button {
                                        editingAccount = account
                                    } label: {
                                        Image(systemName: "pencil")
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)

                                    if store.accounts.count > 1 {
                                        Button(role: .destructive) {
                                            store.deleteAccount(account.id)
                                        } label: {
                                            Image(systemName: "trash")
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                    }
                                }
                            }
                        }
                        .padding(16)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .controlBackgroundColor)))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.08), lineWidth: 1))
                    }
                }
            }
        }
        .sheet(isPresented: $showCreateAccountSheet) {
            AccountEditorSheet(store: store, existingAccount: nil)
        }
        .sheet(item: $editingAccount) { acc in
            AccountEditorSheet(store: store, existingAccount: acc)
        }
    }
}

public struct AccountEditorSheet: View {
    @ObservedObject public var store: FinancialDataStore
    @Environment(\.dismiss) private var dismiss

    public let existingAccount: BankAccount?

    @State private var name: String = ""
    @State private var selectedPresetId: String? = "itau"
    @State private var customImagePath: String? = nil
    @State private var colorHex: String = "#EC7000"
    @State private var initialBalanceText: String = "0,00"
    @State private var agency: String = ""
    @State private var accountNumber: String = ""
    @State private var errorMsg: String? = nil

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(existingAccount == nil ? "Cadastro de Conta" : "Editar Conta")
                .font(.title2.bold())

            Form {
                Section("Dados da Conta") {
                    TextField("Nome da Conta (Ex: Itaú Unibanco, Nubank, Santander)", text: $name)
                    HStack(spacing: 12) {
                        TextField("Saldo Inicial (R$)", text: $initialBalanceText)
                        TextField("Agência (Opcional)", text: $agency)
                        TextField("Conta (Opcional)", text: $accountNumber)
                    }
                }

                Section("Ícone da Base de Bancos ou Imagem Anexa da Máquina") {
                    HStack(spacing: 16) {
                        AccountAvatarView(
                            customImagePath: customImagePath,
                            bankPresetId: selectedPresetId,
                            fallbackSymbol: "building.columns.fill",
                            colorHex: colorHex,
                            size: 54
                        )

                        VStack(alignment: .leading, spacing: 6) {
                            Button {
                                if let url = MacFilePicker.pickImageFile(),
                                   let saved = store.copyAttachmentToStorage(from: url) {
                                    customImagePath = saved.path
                                }
                            } label: {
                                Label("Anexar Imagem / Ícone da Minha Máquina...", systemImage: "photo.badge.plus")
                            }

                            if customImagePath != nil {
                                Button("Remover imagem anexada e usar ícone do banco") {
                                    customImagePath = nil
                                }
                                .buttonStyle(.link)
                                .font(.caption)
                            }
                        }
                    }

                    Text("Base Inicial dos Principais Bancos (Clique para selecionar):")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(BrazilianBanksCatalog.presets) { preset in
                                let isSelected = selectedPresetId == preset.id && customImagePath == nil
                                Button {
                                    selectedPresetId = preset.id
                                    colorHex = preset.primaryHex
                                    if name.trimmingCharacters(in: .whitespaces).isEmpty {
                                        name = preset.name
                                    }
                                } label: {
                                    VStack(spacing: 6) {
                                        AccountAvatarView(
                                            customImagePath: nil,
                                            bankPresetId: preset.id,
                                            fallbackSymbol: preset.symbolName,
                                            colorHex: preset.primaryHex,
                                            size: 40
                                        )
                                        Text(preset.name)
                                            .font(.caption2)
                                            .lineLimit(1)
                                            .frame(width: 82)
                                    }
                                    .padding(8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(isSelected ? Color(hex: preset.primaryHex).opacity(0.16) : Color.primary.opacity(0.03))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(isSelected ? Color(hex: preset.primaryHex) : Color.clear, lineWidth: 1.5)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
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
                Button(existingAccount == nil ? "Salvar Conta" : "Atualizar Conta") {
                    let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !cleanName.isEmpty else {
                        errorMsg = "Informe o nome da conta."
                        return
                    }
                    let initBal = BRLFormatters.parseAmount(initialBalanceText) ?? 0.0
                    let symbol = BrazilianBanksCatalog.preset(for: selectedPresetId)?.symbolName ?? "building.columns.fill"

                    if var existing = existingAccount {
                        existing.name = cleanName
                        existing.bankPresetId = selectedPresetId
                        existing.customImagePath = customImagePath
                        existing.iconSymbol = symbol
                        existing.colorHex = colorHex
                        existing.initialBalance = initBal
                        existing.agency = agency
                        existing.accountNumber = accountNumber
                        store.updateAccount(existing)
                    } else {
                        store.addAccount(
                            name: cleanName,
                            bankPresetId: selectedPresetId,
                            customImagePath: customImagePath,
                            iconSymbol: symbol,
                            colorHex: colorHex,
                            initialBalance: initBal,
                            agency: agency,
                            accountNumber: accountNumber
                        )
                    }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(22)
        .frame(width: 640, height: 540)
        .onAppear {
            if let existing = existingAccount {
                name = existing.name
                selectedPresetId = existing.bankPresetId
                customImagePath = existing.customImagePath
                colorHex = existing.colorHex
                initialBalanceText = BRLFormatters.decimalFormatter.string(from: NSNumber(value: existing.initialBalance)) ?? "0,00"
                agency = existing.agency
                accountNumber = existing.accountNumber
            }
        }
    }
}

// MARK: - 3. Gestão de Categorias (Separadas por Despesas e Receitas + Seletor Completo de Ícones do Mac)

public struct CategoriesManagementSectionView: View {
    @ObservedObject public var store: FinancialDataStore

    @State private var selectedTypeTab: TransactionType = .expense
    @State private var showCreateCategorySheet: Bool = false
    @State private var editingCategory: CategoryItem? = nil

    public var body: some View {
        let filteredCategories = store.categories(for: selectedTypeTab)

        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Picker("Tipo de Categoria", selection: $selectedTypeTab) {
                    Text("Categorias de Despesas (\(store.categories(for: .expense).count))").tag(TransactionType.expense)
                    Text("Categorias de Receitas (\(store.categories(for: .income).count))").tag(TransactionType.income)
                }
                .pickerStyle(.segmented)
                .frame(width: 440)

                Spacer()

                Button {
                    showCreateCategorySheet = true
                } label: {
                    Label("Nova Categoria de \(selectedTypeTab.title)", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(selectedTypeTab == .expense ? Color(hex: "#EF4444") : Color(hex: "#10B981"))
            }

            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                    ForEach(filteredCategories) { cat in
                        HStack(spacing: 12) {
                            CategoryBadgeView(category: cat, size: 40)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(cat.name)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                Text(cat.iconSymbol)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            Button {
                                editingCategory = cat
                            } label: {
                                Image(systemName: "pencil")
                            }
                            .buttonStyle(.borderless)

                            Button(role: .destructive) {
                                store.deleteCategory(cat.id)
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.07), lineWidth: 1))
                    }
                }
            }
        }
        .sheet(isPresented: $showCreateCategorySheet) {
            CategoryEditorSheet(store: store, initialType: selectedTypeTab, existingCategory: nil)
        }
        .sheet(item: $editingCategory) { cat in
            CategoryEditorSheet(store: store, initialType: cat.type, existingCategory: cat)
        }
    }
}

public struct CategoryEditorSheet: View {
    @ObservedObject public var store: FinancialDataStore
    @Environment(\.dismiss) private var dismiss

    public let existingCategory: CategoryItem?

    @State private var name: String = ""
    @State private var type: TransactionType
    @State private var selectedSymbol: String = "cart.fill"
    @State private var colorHex: String = "#F97316"
    @State private var iconSearchQuery: String = ""
    @State private var errorMsg: String? = nil

    private let colorPalette = [
        "#EF4444", "#F97316", "#EAB308", "#10B981", "#14B8A6",
        "#06B6D4", "#3B82F6", "#6366F1", "#8B5CF6", "#EC4899", "#64748B"
    ]

    public init(store: FinancialDataStore, initialType: TransactionType, existingCategory: CategoryItem?) {
        self.store = store
        self.existingCategory = existingCategory
        _type = State(initialValue: existingCategory?.type ?? initialType)
    }

    public var body: some View {
        let matchingIconGroups = MacIconCatalog.search(iconSearchQuery)

        VStack(alignment: .leading, spacing: 16) {
            HStack {
                CategoryBadgeView(symbol: selectedSymbol, colorHex: colorHex, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(existingCategory == nil ? "Cadastro de Categoria" : "Editar Categoria")
                        .font(.title2.bold())
                    Text("Escolha o nome, a cor e selecione o ícone na biblioteca completa de símbolos nativos do macOS")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 14) {
                TextField("Nome da Categoria (Ex: Supermercado, Salário, Academia)", text: $name)
                    .textFieldStyle(.roundedBorder)

                Picker("Tipo", selection: $type) {
                    ForEach(TransactionType.allCases) { t in
                        Text(t.title).tag(t)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
            }

            // Color Palette
            HStack(spacing: 10) {
                Text("Cor:")
                    .font(.caption.bold())
                ForEach(colorPalette, id: \.self) { hex in
                    Circle()
                        .fill(Color(hex: hex))
                        .frame(width: 22, height: 22)
                        .overlay(
                            Circle()
                                .stroke(Color.primary, lineWidth: colorHex == hex ? 2.5 : 0)
                        )
                        .onTapGesture {
                            colorHex = hex
                        }
                }
            }

            Divider()

            // Searchable Complete macOS SF Symbols Picker
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Buscar ícone do macOS (ex: carro, casa, comida, banco, avião, pet ou nome SF Symbol)...", text: $iconSearchQuery)
                    .textFieldStyle(.plain)
                if !iconSearchQuery.isEmpty {
                    Button {
                        iconSearchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.1), lineWidth: 1))

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(matchingIconGroups) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(group.title)
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)

                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                                ForEach(group.symbols) { item in
                                    let isSelected = selectedSymbol == item.symbol
                                    Button {
                                        selectedSymbol = item.symbol
                                    } label: {
                                        VStack(spacing: 5) {
                                            Image(systemName: item.symbol)
                                                .font(.system(size: 18, weight: .semibold))
                                                .foregroundStyle(isSelected ? Color(hex: colorHex) : .primary)
                                                .frame(height: 22)
                                            Text(item.label)
                                                .font(.system(size: 10))
                                                .lineLimit(1)
                                                .foregroundStyle(.secondary)
                                        }
                                        .padding(.vertical, 8)
                                        .padding(.horizontal, 4)
                                        .frame(maxWidth: .infinity)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(isSelected ? Color(hex: colorHex).opacity(0.18) : Color(nsColor: .controlBackgroundColor))
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(isSelected ? Color(hex: colorHex) : Color.primary.opacity(0.06), lineWidth: isSelected ? 1.5 : 1)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            if let errorMsg {
                Text(errorMsg)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Button("Cancelar") { dismiss() }
                Spacer()
                Button(existingCategory == nil ? "Salvar Categoria" : "Atualizar Categoria") {
                    let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !cleanName.isEmpty else {
                        errorMsg = "Informe o nome da categoria."
                        return
                    }
                    if var existing = existingCategory {
                        existing.name = cleanName
                        existing.type = type
                        existing.iconSymbol = selectedSymbol
                        existing.colorHex = colorHex
                        store.updateCategory(existing)
                    } else {
                        store.addCategory(
                            name: cleanName,
                            type: type,
                            iconSymbol: selectedSymbol,
                            colorHex: colorHex
                        )
                    }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(hex: colorHex))
            }
        }
        .padding(22)
        .frame(width: 680, height: 600)
        .onAppear {
            if let existing = existingCategory {
                name = existing.name
                type = existing.type
                selectedSymbol = existing.iconSymbol
                colorHex = existing.colorHex
            }
        }
    }
}
