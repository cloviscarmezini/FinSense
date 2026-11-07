import SwiftUI

public struct LoansAndFinancingsView: View {
    @ObservedObject public var store: FinancialDataStore
    @ObservedObject public var llmService: LocalLLMService
    public let kind: CreditContractKind

    @State private var showCreateSheet: Bool = false
    @State private var showImportDocumentSheet: Bool = false
    @State private var contractToAmortize: CreditContract? = nil
    @State private var contractToSettle: CreditContract? = nil
    @State private var contractPendingDeletion: CreditContract? = nil

    public init(store: FinancialDataStore, llmService: LocalLLMService, kind: CreditContractKind) {
        self.store = store
        self.llmService = llmService
        self.kind = kind
    }

    public var body: some View {
        let activeList = store.activeContracts(for: kind)
        let settledList = store.settledContracts(for: kind)
        let totalOutstandingBalance = activeList.reduce(0.0) { $0 + store.currentOutstandingBalance(for: $1) }
        let totalNominal = activeList.reduce(0.0) { $0 + store.remainingNominalAmount(for: $1) }
        let totalProjectedPayoff = activeList.reduce(0.0) { $0 + store.projectedPayoffAmount(for: $1) }
        let totalSavingsOnPayoff = max(totalNominal - totalProjectedPayoff, 0)

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(kind == .loan ? "Gestão de Empréstimos" : "Gestão de Financiamentos (Imóvel e Carro)")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                        Text(
                            kind == .loan
                                ? "Controle consignados e empréstimos, importe documentos com IA Local, acompanhe o Saldo Devedor e amortize parcelas"
                                : "Controle financiamentos de Imóvel e Carro, importe demonstrativos com IA Local, acompanhe o Saldo Devedor e projeções"
                        )
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
                        store.requireInstalledLLM(forFeature: "Importar \(kind.title) via Documento (IA Local)") {
                            showImportDocumentSheet = true
                        }
                    } label: {
                        Label("Importar", systemImage: "doc.text.magnifyingglass")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        showCreateSheet = true
                    } label: {
                        Label("Novo \(kind.title)", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(kind == .loan ? Color(hex: "#D97706") : Color(hex: "#8B5CF6"))
                }

                // KPI Cards
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                    MetricCardView(
                        title: "Saldo Devedor Atual",
                        value: BRLFormatters.currency(totalOutstandingBalance),
                        subtitle: "\(activeList.count) \(kind.title.lowercased())(s) ativo(s)",
                        icon: "exclamationmark.shield.fill",
                        tint: Color(hex: "#EF4444")
                    )

                    MetricCardView(
                        title: "Soma Nominal das Parcelas",
                        value: BRLFormatters.currency(totalNominal),
                        subtitle: "Total das parcelas futuras a vencer",
                        icon: kind == .loan ? "banknote.fill" : "house.and.flag.fill",
                        tint: kind == .loan ? Color(hex: "#D97706") : Color(hex: "#8B5CF6")
                    )

                    MetricCardView(
                        title: "Projeção para Quitar Hoje",
                        value: BRLFormatters.currency(totalProjectedPayoff),
                        subtitle: "Valor presente c/ desconto de juros",
                        icon: "sparkles.rectangle.stack.fill",
                        tint: Color(hex: "#10B981")
                    )

                    MetricCardView(
                        title: "Economia Estimada na Quitação",
                        value: BRLFormatters.currency(totalSavingsOnPayoff),
                        subtitle: "\(settledList.count) contrato(s) já quitado(s)",
                        icon: "arrow.down.right.circle.fill",
                        tint: Color(hex: "#3B82F6")
                    )
                }

                // Active Contracts Grid
                if activeList.isEmpty {
                    VStack(spacing: 14) {
                        Image(systemName: kind == .loan ? "banknote" : "car.2.fill")
                            .font(.system(size: 46))
                            .foregroundStyle(.secondary)
                        Text("Nenhum \(kind.title.lowercased()) ativo cadastrado")
                            .font(.title3.bold())
                        Text("Cadastre manualmente ou importe um documento PDF (ex: Demonstrativo de Crédito ou Evolução de Financiamento) usando a LLM local.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 580)
                        HStack(spacing: 12) {
                            Button {
                                store.requireInstalledLLM(forFeature: "Importar \(kind.title) via Documento (IA Local)") {
                                    showImportDocumentSheet = true
                                }
                            } label: {
                                Label("Importar", systemImage: "sparkles.rectangle.stack.fill")
                            }
                            .buttonStyle(.bordered)

                            Button("Cadastrar \(kind.title) Manualmente") {
                                showCreateSheet = true
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 280)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .controlBackgroundColor)))
                } else {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 18), GridItem(.flexible(), spacing: 18)], spacing: 18) {
                        ForEach(activeList) { contract in
                            contractCard(contract)
                        }
                    }
                }
            }
            .padding(24)
        }
        .sheet(isPresented: $showCreateSheet) {
            CreateCreditContractSheet(store: store, llmService: llmService, kind: kind)
        }
        .sheet(isPresented: $showImportDocumentSheet) {
            ImportCreditContractDocumentSheet(store: store, llmService: llmService, kind: kind)
        }
        .sheet(item: $contractToAmortize) { contract in
            AmortizeContractSheet(store: store, contract: contract)
        }
        .sheet(item: $contractToSettle) { contract in
            SettleContractSheet(store: store, contract: contract)
        }
        .alert(
            "Confirmar Exclusão de \(kind.title)",
            isPresented: Binding(
                get: { contractPendingDeletion != nil },
                set: { if !$0 { contractPendingDeletion = nil } }
            ),
            presenting: contractPendingDeletion
        ) { contract in
            Button("Excluir \(kind.title)", role: .destructive) {
                store.deleteContract(contract.id)
                contractPendingDeletion = nil
            }
            Button("Cancelar", role: .cancel) {
                contractPendingDeletion = nil
            }
        } message: { contract in
            Text("Deseja realmente excluir o \(kind.title.lowercased()) \"\(contract.name)\" e remover todas as transações vinculadas a ele? Esta ação não pode ser desfeita.")
        }
    }

    @ViewBuilder
    private func contractCard(_ contract: CreditContract) -> some View {
        let paidCount = store.paidTransactionsCount(forContract: contract)
        let remainingCount = store.remainingInstallmentsCount(for: contract)
        let outstandingBalance = store.currentOutstandingBalance(for: contract)
        let nominalRemaining = store.remainingNominalAmount(for: contract)
        let projectedPayoff = store.projectedPayoffAmount(for: contract)
        let discountEstimate = max(nominalRemaining - projectedPayoff, 0)
        let progress = Double(paidCount) / Double(max(contract.totalInstallments, 1))
        let accentHex = kind == .loan ? "#D97706" : "#8B5CF6"

        VStack(alignment: .leading, spacing: 14) {
            // Card Header
            HStack(alignment: .top, spacing: 12) {
                CategoryBadgeView(symbol: contract.iconSymbol, colorHex: accentHex, size: 44)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(contract.name)
                            .font(.title3.bold())
                        Text(contract.subtypeDisplayName)
                            .font(.caption2.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color(hex: accentHex).opacity(0.16)))
                            .foregroundStyle(Color(hex: accentHex))
                    }
                    HStack(spacing: 6) {
                        Text("\(contract.amortizationSystem.rawValue) • Cobrança todo dia \(contract.billingDay)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let contractNo = contract.contractNumber, !contractNo.isEmpty {
                            Text("• Contrato: \(contractNo)")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer()

                Button(role: .destructive) {
                    contractPendingDeletion = contract
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Excluir contrato e todas as suas transações vinculadas")
            }

            // Contract Details Grid (Incluindo o campo "Saldo devedor" no card!)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 10) {
                detailCell(
                    label: "Saldo Devedor",
                    value: BRLFormatters.currency(outstandingBalance),
                    valueColor: Color(hex: "#EF4444")
                )
                detailCell(label: "Valor Total Contratado", value: BRLFormatters.currency(contract.totalContractedAmount))
                detailCell(label: "Valor da Parcela", value: BRLFormatters.currency(contract.installmentAmount))
                detailCell(label: "Taxa de Juros", value: String(format: "%.2f%% a.m.", contract.monthlyInterestRate))
                detailCell(label: "Parcelas Totais", value: "\(contract.totalInstallments)x (\(remainingCount)x futuras)")
                detailCell(
                    label: "Data em que foi feito",
                    value: contract.startDate.map { BRLFormatters.shortDate($0) } ?? "A partir da criação"
                )
                detailCell(label: "Saldo Nominal Futuro", value: BRLFormatters.currency(nominalRemaining))
                detailCell(label: "Parcelas Pagas", value: "\(paidCount) de \(contract.totalInstallments)")
                detailCell(label: "Vencimento Mensal", value: "Todo dia \(contract.billingDay)")
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.03)))

            // Progress Bar
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Progresso do Contrato: \(paidCount) de \(contract.totalInstallments) parcelas decorridas/pagas")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "%.0f%%", progress * 100))
                        .font(.caption.bold())
                }
                ProgressView(value: min(max(progress, 0), 1))
                    .tint(Color(hex: accentHex))
            }

            // Highlighted Line: "Projeção de valor para quitar" + "Simular Prazo com IA"
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .foregroundStyle(Color(hex: "#10B981"))
                        Text("Projeção de valor para quitar:")
                            .font(.subheadline.weight(.semibold))
                    }
                    Text("Saldo Devedor: \(BRLFormatters.currency(outstandingBalance)) • Desconto est. sobre nominal: \(BRLFormatters.currency(discountEstimate))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    let kindLower = contract.kind == .loan ? "empréstimo" : "financiamento"
                    let question = "Monte um plano de ação para eu quitar meu \(kindLower) \"\(contract.name)\" no menor prazo possível"
                    store.requireInstalledLLM(forFeature: "Simular Prazo de '\(contract.name)' com IA Local") {
                        store.isAIChatPresented = true
                        Task {
                            await llmService.sendUserQuestion(question, store: store)
                        }
                    }
                } label: {
                    Label("Simular Prazo com IA", systemImage: "sparkles")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .help("Gerar plano de ação na IA Local para quitar este \(contract.kind.title.lowercased()) no menor prazo possível")

                Text(BRLFormatters.currency(projectedPayoff))
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color(hex: "#10B981"))
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(hex: "#10B981").opacity(0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color(hex: "#10B981").opacity(0.30), lineWidth: 1)
            )

            if !contract.notes.isEmpty {
                Text(contract.notes)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            // Action Buttons: Amortizar & Quitar
            HStack(spacing: 12) {
                Button {
                    contractToAmortize = contract
                } label: {
                    Label("Amortizar Parcelas / Saldo", systemImage: "arrow.down.forward.and.arrow.up.backward.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    contractToSettle = contract
                } label: {
                    Label("Quitar \(kind.title)", systemImage: "checkmark.seal.fill")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
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
                .stroke(Color(hex: accentHex).opacity(0.25), lineWidth: 1.2)
        )
    }

    @ViewBuilder
    private func detailCell(label: String, value: String, valueColor: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.bold())
                .foregroundStyle(valueColor)
                .lineLimit(1)
        }
    }
}

// MARK: - Create Credit Contract Sheet (Empréstimo ou Financiamento)

public struct CreateCreditContractSheet: View {
    @ObservedObject public var store: FinancialDataStore
    @ObservedObject public var llmService: LocalLLMService
    @Environment(\.dismiss) private var dismiss

    public let kind: CreditContractKind

    @State private var name: String = ""
    @State private var contractNumber: String = ""
    @State private var loanSubtype: LoanSubtype = .consignado
    @State private var financingSubtype: FinancingSubtype = .imovel
    @State private var amortizationSystem: AmortizationSystem = .price
    @State private var totalContractedText: String = ""
    @State private var outstandingBalanceText: String = ""
    @State private var installmentAmountText: String = ""
    @State private var billingDay: Int = 10
    @State private var totalInstallments: Int = 48
    @State private var interestRateText: String = "1,65"
    @State private var hasStartDate: Bool = false
    @State private var startDate: Date = Date()
    @State private var accountId: UUID = UUID()
    @State private var notes: String = ""
    @State private var showEmbeddedDocImporter: Bool = false
    @State private var errorMsg: String? = nil

    public init(store: FinancialDataStore, llmService: LocalLLMService, kind: CreditContractKind) {
        self.store = store
        self.llmService = llmService
        self.kind = kind
    }

    public var body: some View {
        let previewSchedule = store.computePastInstallmentsAndFirstFutureDate(
            startDate: hasStartDate ? startDate : nil,
            billingDay: billingDay,
            totalInstallments: totalInstallments
        )
        let futureToCreate = max(totalInstallments - previewSchedule.pastInstallmentsCount, 0)

        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Cadastrar \(kind.title)")
                        .font(.title2.bold())
                    Text("Preencha os dados manualmente ou importe um documento PDF com interpretação via LLM local")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()

                Button {
                    store.requireInstalledLLM(forFeature: "Importar \(kind.title) via Documento (IA Local)") {
                        showEmbeddedDocImporter = true
                    }
                } label: {
                    Label("Importar", systemImage: "sparkles.rectangle.stack.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(hex: "#6366F1"))
            }

            Divider()

            Form {
                Section("Identificação e Modalidade") {
                    HStack(spacing: 12) {
                        BorderedTextField(
                            label: "Nome do \(kind.title)",
                            placeholder: kind == .loan
                                ? "Ex: Consignado Santander, Empréstimo Pessoal"
                                : "Ex: Financiamento Habitação CAIXA, Honda Civic",
                            text: $name
                        )

                        BorderedTextField(
                            label: "Nº do Contrato (Opcional)",
                            placeholder: "Ex: 783694303",
                            text: $contractNumber
                        )
                        .frame(width: 190)
                    }

                    if kind == .loan {
                        Picker("Tipo do Empréstimo", selection: $loanSubtype) {
                            ForEach(LoanSubtype.allCases) { st in
                                Text(st.rawValue).tag(st)
                            }
                        }
                    } else {
                        Picker("Tipo do Financiamento", selection: $financingSubtype) {
                            ForEach(FinancingSubtype.allCases) { ft in
                                Label(ft.rawValue, systemImage: ft.iconSymbol).tag(ft)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    Picker("Sistema de Amortização", selection: $amortizationSystem) {
                        ForEach(AmortizationSystem.allCases) { sys in
                            Text(sys.rawValue).tag(sys)
                        }
                    }
                }

                Section("Valores (R$), Saldo Devedor, Parcelas e Juros") {
                    HStack(spacing: 12) {
                        BRLCurrencyTextField(
                            label: "Valor Total Contratado (R$)",
                            text: $totalContractedText
                        )

                        BRLCurrencyTextField(
                            label: "Saldo Devedor Atual (R$)",
                            text: $outstandingBalanceText
                        )

                        BRLCurrencyTextField(
                            label: "Valor da Parcela (R$)",
                            text: $installmentAmountText
                        )
                    }

                    HStack(spacing: 16) {
                        EditableIntegerStepperField(
                            label: "Quantidade de Parcelas (Digite ou ajuste)",
                            value: $totalInstallments,
                            range: 1...600,
                            unitSuffix: "parcelas"
                        )

                        EditableIntegerStepperField(
                            label: "Dia de Cobrança (1 a 31)",
                            value: $billingDay,
                            range: 1...31,
                            unitSuffix: "dia"
                        )
                    }

                    HStack(spacing: 14) {
                        BorderedTextField(
                            label: "Taxa de Juros Mensal (% a.m.)",
                            placeholder: "Ex: 2,0087",
                            text: $interestRateText,
                            suffix: "% a.m."
                        )
                        .frame(width: 220)

                        if store.accounts.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Conta Bancária")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                HStack {
                                    Text("Nenhuma conta cadastrada.")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                    Button("Ir para Contas") {
                                        dismiss()
                                        store.selectedDestination = .settings
                                        store.selectedSettingsSection = .accounts
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            }
                        } else {
                            Picker("Conta Padrão", selection: $accountId) {
                                ForEach(store.accounts) { acc in
                                    Text(acc.name).tag(acc.id)
                                }
                            }
                        }
                    }

                    BorderedTextField(
                        label: "Observações (Opcional)",
                        placeholder: "Ex: Desconto em folha, indexador TR...",
                        text: $notes
                    )
                }

                Section("Data de Início Inteligente (Opcional)") {
                    Toggle("Informar Data em que o Contrato foi feito (Data de Início)", isOn: $hasStartDate)

                    if hasStartDate {
                        DatePicker("Data de Início", selection: $startDate, displayedComponents: [.date])
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Como funciona o registro inteligente:")
                            .font(.caption.bold())
                        Text("• O contrato registra o Valor Total, Saldo Devedor, Juros e as \(totalInstallments) parcelas totais.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("• Parcelas já ocorridas no passado: \(previewSchedule.pastInstallmentsCount) (não poluem seu extrato passado).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("• Serão geradas apenas as \(futureToCreate) transações futuras a partir de \(BRLFormatters.shortDate(previewSchedule.firstFutureBillingDate)).")
                            .font(.caption.bold())
                            .foregroundStyle(Color(hex: "#10B981"))
                    }
                    .padding(.vertical, 4)
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
                Button("Criar \(kind.title)") {
                    guard !store.accounts.isEmpty else {
                        errorMsg = "Cadastre pelo menos uma conta em Configurações → Contas antes de criar um \(kind.title.lowercased())."
                        return
                    }
                    let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !cleanName.isEmpty else {
                        errorMsg = "Informe o nome do \(kind.title.lowercased())."
                        return
                    }
                    guard let totalVal = BRLFormatters.parseAmount(totalContractedText), totalVal > 0 else {
                        errorMsg = "Informe o valor total contratado."
                        return
                    }
                    guard let instVal = BRLFormatters.parseAmount(installmentAmountText), instVal > 0 else {
                        errorMsg = "Informe o valor da parcela."
                        return
                    }
                    let outBal = BRLFormatters.parseAmount(outstandingBalanceText)
                    let rateVal = BRLFormatters.parseAmount(interestRateText) ?? 0.0
                    let cleanContractNo = contractNumber.trimmingCharacters(in: .whitespacesAndNewlines)

                    store.createCreditContract(
                        kind: kind,
                        name: cleanName,
                        contractNumber: cleanContractNo.isEmpty ? nil : cleanContractNo,
                        loanSubtype: kind == .loan ? loanSubtype : nil,
                        financingSubtype: kind == .financing ? financingSubtype : nil,
                        amortizationSystem: amortizationSystem,
                        totalContractedAmount: totalVal,
                        outstandingBalance: outBal,
                        installmentAmount: instVal,
                        billingDay: billingDay,
                        totalInstallments: totalInstallments,
                        monthlyInterestRate: rateVal,
                        startDate: hasStartDate ? startDate : nil,
                        accountId: accountId,
                        notes: notes
                    )
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(kind == .loan ? Color(hex: "#D97706") : Color(hex: "#8B5CF6"))
            }
        }
        .padding(22)
        .frame(width: 680, height: 670)
        .onAppear {
            accountId = store.accounts.first?.id ?? UUID()
        }
        .sheet(isPresented: $showEmbeddedDocImporter) {
            ImportCreditContractDocumentSheet(
                store: store,
                llmService: llmService,
                kind: kind,
                onCompleteImport: {
                    dismiss()
                }
            )
        }
    }
}

// MARK: - Import Credit Contract Document Sheet (LLM Local Document Interpreter)

public struct ImportCreditContractDocumentSheet: View {
    @ObservedObject public var store: FinancialDataStore
    @ObservedObject public var llmService: LocalLLMService
    @Environment(\.dismiss) private var dismiss

    public let kind: CreditContractKind
    public var onCompleteImport: (() -> Void)? = nil

    @State private var selectedFileName: String = "Nenhum documento selecionado"
    @State private var rawTextInput: String = ""
    @AppStorage("import_show_text_input_box") private var showTextInputBox: Bool = false
    @State private var parsedDoc: ParsedCreditContractDocument? = nil

    // Campos editáveis após a leitura pela LLM
    @State private var name: String = ""
    @State private var contractNumber: String = ""
    @State private var loanSubtype: LoanSubtype = .consignado
    @State private var financingSubtype: FinancingSubtype = .imovel
    @State private var amortizationSystem: AmortizationSystem = .price
    @State private var totalContractedText: String = ""
    @State private var outstandingBalanceText: String = ""
    @State private var installmentAmountText: String = ""
    @State private var billingDay: Int = 25
    @State private var totalInstallments: Int = 36
    @State private var paidInstallmentsCount: Int = 10
    @State private var interestRateText: String = "2,0087"
    @State private var startDate: Date = Date()
    @State private var firstFutureBillingDate: Date = Date()
    @State private var selectedAccountId: UUID = UUID()
    @State private var notes: String = ""
    @State private var errorMsg: String? = nil

    public init(
        store: FinancialDataStore,
        llmService: LocalLLMService,
        kind: CreditContractKind,
        onCompleteImport: (() -> Void)? = nil
    ) {
        self.store = store
        self.llmService = llmService
        self.kind = kind
        self.onCompleteImport = onCompleteImport
    }

    public var body: some View {
        let futureCount = max(totalInstallments - paidInstallmentsCount, 0)

        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: "cpu.fill")
                            .foregroundStyle(Color(hex: "#6366F1"))
                        Text("Importar \(kind.title) com Base em Documento (LLM Local)")
                            .font(.title2.bold())
                    }
                    Text(
                        kind == .loan
                            ? "Selecione o documento PDF do empréstimo no seu Mac para extrair valores, Saldo Devedor e data original."
                            : "Selecione o documento PDF do financiamento no seu Mac para extrair valores, Saldo Devedor e data original."
                    )
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

            // Document Selection Bar
            HStack(spacing: 12) {
                Button {
                    if let url = MacFilePicker.pickStatementFile() {
                        selectedFileName = url.lastPathComponent
                        Task {
                            if let doc = await llmService.analyzeCreditContractFile(
                                fileURL: url,
                                expectedKind: kind,
                                store: store
                            ) {
                                applyParsedDocument(doc)
                                showTextInputBox = false
                            }
                        }
                    }
                } label: {
                    Label("Selecionar Documento PDF no Mac", systemImage: "folder.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(hex: "#6366F1"))

                Button {
                    showTextInputBox.toggle()
                } label: {
                    Label(
                        showTextInputBox ? "Ocultar Caixa de Texto" : "Digitar / Colar Texto",
                        systemImage: "text.alignleft"
                    )
                }
                .buttonStyle(.bordered)

                Spacer()
            }

            if showTextInputBox {
                VStack(alignment: .leading, spacing: 8) {
                    BorderedMultilineTextEditor(
                        label: "Ou cole / digite o texto do demonstrativo de \(kind.title.lowercased()) abaixo:",
                        placeholder: kind == .loan
                            ? "Ex: Nr. Contrato: 783694303 Dt. Formalização: 30/10/2025 Vlr. Financiado: 110.108,13 Dívida para Liquidação: 91.039,22 Nr. Parcelas: 36 Tx. Efet. do contrato: 2,0087 % a.m."
                            : "Ex: Contrato: 178770203328-1 Saldo Devedor Teórico Valor R$ 324.737,86 Prazo do Financiamento: 360 meses Prazo Remanescente: 332 meses Taxa de Juros: 8,51% Devido 2.658,04",
                        text: $rawTextInput,
                        minHeight: parsedDoc == nil ? 120 : 85
                    )

                    HStack {
                        Text("Dica: Cole o conteúdo textual do contrato/demonstrativo para interpretação pela LLM local.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if !rawTextInput.isEmpty {
                            Button("Limpar Texto") {
                                rawTextInput = ""
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        Button {
                            selectedFileName = "Texto digitado / colado"
                            Task {
                                if let doc = await llmService.analyzeCreditContractRawText(
                                    rawText: rawTextInput,
                                    expectedKind: kind,
                                    store: store
                                ) {
                                    applyParsedDocument(doc)
                                    showTextInputBox = false
                                }
                            }
                        } label: {
                            Label("Analisar Texto com LLM Local", systemImage: "sparkles")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color(hex: "#6366F1"))
                        .controlSize(.small)
                        .disabled(rawTextInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
            }

            if llmService.isAnalyzingStatement {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text("A LLM local está interpretando o documento, extraindo Saldo Devedor, juros, data de contratação e cronograma de parcelas...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.indigo.opacity(0.1)))
            }

            if parsedDoc == nil && !llmService.isAnalyzingStatement {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "doc.text.viewfinder")
                        .font(.system(size: 46))
                        .foregroundStyle(.secondary)
                    Text("Clique em \"Selecionar Documento PDF no Mac\" acima para importar o contrato")
                        .font(.headline)
                    Text("A LLM local identificará automaticamente o contrato, data em que foi feito, Saldo Devedor, parcelas pagas e parcelas futuras.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
            } else if parsedDoc != nil {
                Form {
                    Section("Dados Extraídos do Documento (\(selectedFileName))") {
                        HStack(spacing: 12) {
                            BorderedTextField(
                                label: "Nome do \(kind.title)",
                                placeholder: "Nome do Contrato",
                                text: $name
                            )

                            BorderedTextField(
                                label: "Nº do Contrato",
                                placeholder: "Contrato",
                                text: $contractNumber
                            )
                            .frame(width: 190)
                        }

                        HStack(spacing: 12) {
                            BRLCurrencyTextField(
                                label: "Valor Total Contratado (R$)",
                                text: $totalContractedText
                            )

                            BRLCurrencyTextField(
                                label: "Saldo Devedor (R$)",
                                text: $outstandingBalanceText
                            )

                            BRLCurrencyTextField(
                                label: "Valor da Parcela (R$)",
                                text: $installmentAmountText
                            )
                        }

                        HStack(spacing: 14) {
                            EditableIntegerStepperField(
                                label: "Total de Parcelas",
                                value: $totalInstallments,
                                range: 1...600,
                                unitSuffix: "meses"
                            )

                            EditableIntegerStepperField(
                                label: "Parcelas Já Pagas no Passado",
                                value: $paidInstallmentsCount,
                                range: 0...600,
                                unitSuffix: "pagas"
                            )

                            EditableIntegerStepperField(
                                label: "Dia de Cobrança",
                                value: $billingDay,
                                range: 1...31,
                                unitSuffix: "dia"
                            )
                        }

                        HStack(spacing: 14) {
                            BorderedTextField(
                                label: "Taxa de Juros (% a.m.)",
                                placeholder: "Ex: 2,0087",
                                text: $interestRateText,
                                suffix: "% a.m."
                            )
                            .frame(width: 180)

                            DatePicker("Data em que foi feito", selection: $startDate, displayedComponents: [.date])

                            DatePicker("Próximo Vencimento Futuro", selection: $firstFutureBillingDate, displayedComponents: [.date])
                        }

                        HStack(spacing: 14) {
                            if store.accounts.isEmpty {
                                HStack {
                                    Text("Nenhuma conta bancária cadastrada.")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                    Button("Ir para Configurações → Contas") {
                                        dismiss()
                                        store.selectedDestination = .settings
                                        store.selectedSettingsSection = .accounts
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            } else {
                                Picker("Conta Bancária para Cobrança das Parcelas Futuras", selection: $selectedAccountId) {
                                    ForEach(store.accounts) { acc in
                                        Text(acc.name).tag(acc.id)
                                    }
                                }
                            }
                        }

                        BorderedTextField(
                            label: "Detalhes Extraídos pela LLM",
                            placeholder: "Detalhes do contrato",
                            text: $notes
                        )

                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(Color(hex: "#10B981"))
                            Text("Resumo da Importação: Contrato feito em \(BRLFormatters.shortDate(startDate)) • \(paidInstallmentsCount) parcelas passadas preservadas • Serão geradas \(futureCount) parcelas futuras a partir de \(BRLFormatters.shortDate(firstFutureBillingDate)) • Saldo Devedor: \(outstandingBalanceText).")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color(hex: "#10B981"))
                        }
                    }
                }
                .formStyle(.grouped)
            }

            if let errorMsg {
                Text(errorMsg)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Button("Cancelar") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button {
                    confirmImport()
                } label: {
                    Label("Confirmar e Importar \(kind.title)", systemImage: "checkmark.circle.fill")
                        .fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(hex: "#10B981"))
                .disabled(parsedDoc == nil)
            }
        }
        .padding(22)
        .frame(width: 820, height: 640)
        .onAppear {
            selectedAccountId = store.accounts.first?.id ?? UUID()
        }
    }

    private func applyParsedDocument(_ doc: ParsedCreditContractDocument) {
        parsedDoc = doc
        name = doc.name
        contractNumber = doc.contractNumber
        loanSubtype = doc.loanSubtype
        financingSubtype = doc.financingSubtype
        amortizationSystem = doc.amortizationSystem
        totalContractedText = BRLFormatters.currency(doc.totalContractedAmount)
        outstandingBalanceText = BRLFormatters.currency(doc.outstandingBalance)
        installmentAmountText = BRLFormatters.currency(doc.installmentAmount)
        billingDay = doc.billingDay
        totalInstallments = doc.totalInstallments
        paidInstallmentsCount = doc.paidInstallmentsCount
        interestRateText = String(format: "%.4f", doc.monthlyInterestRate).replacingOccurrences(of: ".", with: ",")
        startDate = doc.startDate
        firstFutureBillingDate = doc.firstFutureBillingDate
        notes = doc.extractedNotes
        errorMsg = nil
    }

    private func confirmImport() {
        guard !store.accounts.isEmpty else {
            errorMsg = "Cadastre pelo menos uma conta bancária em Configurações → Contas antes de importar o contrato."
            return
        }
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else {
            errorMsg = "Informe o nome do contrato."
            return
        }
        guard let totalVal = BRLFormatters.parseAmount(totalContractedText), totalVal > 0 else {
            errorMsg = "Informe o valor total contratado."
            return
        }
        guard let instVal = BRLFormatters.parseAmount(installmentAmountText), instVal > 0 else {
            errorMsg = "Informe o valor da parcela."
            return
        }
        let outBal = BRLFormatters.parseAmount(outstandingBalanceText) ?? totalVal
        let rateVal = BRLFormatters.parseAmount(interestRateText) ?? 0.0

        store.createCreditContract(
            kind: kind,
            name: cleanName,
            contractNumber: contractNumber.isEmpty ? nil : contractNumber,
            loanSubtype: kind == .loan ? loanSubtype : nil,
            financingSubtype: kind == .financing ? financingSubtype : nil,
            amortizationSystem: amortizationSystem,
            totalContractedAmount: totalVal,
            outstandingBalance: outBal,
            installmentAmount: instVal,
            billingDay: billingDay,
            totalInstallments: totalInstallments,
            monthlyInterestRate: rateVal,
            startDate: startDate,
            accountId: selectedAccountId,
            notes: notes,
            overridePastInstallmentsCount: paidInstallmentsCount,
            overrideFirstFutureBillingDate: firstFutureBillingDate
        )
        onCompleteImport?()
        dismiss()
    }
}

// MARK: - Amortize Contract Sheet (Amortizar Empréstimo / Financiamento)

public struct AmortizeContractSheet: View {
    @ObservedObject public var store: FinancialDataStore
    @Environment(\.dismiss) private var dismiss

    public let contract: CreditContract

    @State private var amountPaidText: String = ""
    @State private var selectedAccountId: UUID = UUID()
    @State private var date: Date = Date()
    @State private var mode: AmortizationRecalculationMode = .reduceTerm
    @State private var newInstallmentAmountText: String = ""
    @State private var newRemainingInstallments: Int = 1
    @State private var notes: String = ""
    @State private var errorMsg: String? = nil

    public init(store: FinancialDataStore, contract: CreditContract) {
        self.store = store
        self.contract = contract
    }

    public var body: some View {
        let currentRemaining = store.remainingInstallmentsCount(for: contract)
        let currentOutstanding = store.currentOutstandingBalance(for: contract)
        let currentProjectedPV = store.projectedPayoffAmount(for: contract)

        VStack(alignment: .leading, spacing: 18) {
            Text("Amortizar \(contract.kind.title): \(contract.name)")
                .font(.title2.bold())
            Text("Informe o valor amortizado, a conta de saída e os parâmetros para recalcular o \(contract.kind.title.lowercased()).")
                .font(.caption)
                .foregroundStyle(.secondary)

            Form {
                Section("Resumo Atual do Contrato") {
                    HStack {
                        Text("Saldo Devedor Atual:")
                        Spacer()
                        Text(BRLFormatters.currency(currentOutstanding))
                            .fontWeight(.bold)
                            .foregroundStyle(Color(hex: "#EF4444"))
                    }
                    HStack {
                        Text("Parcelas Futuras Restantes:")
                        Spacer()
                        Text("\(currentRemaining)x de \(BRLFormatters.currency(contract.installmentAmount))")
                            .fontWeight(.semibold)
                    }
                    HStack {
                        Text("Projeção Atual para Quitar:")
                        Spacer()
                        Text(BRLFormatters.currency(currentProjectedPV))
                            .fontWeight(.bold)
                            .foregroundStyle(Color(hex: "#10B981"))
                    }
                }

                Section("Pagamento da Amortização") {
                    BRLCurrencyTextField(
                        label: "Valor Amortizado (R$)",
                        text: $amountPaidText
                    )
                    .onChange(of: amountPaidText) { _, _ in
                        recalculatePreview()
                    }

                    Picker("Conta de onde saiu o pagamento", selection: $selectedAccountId) {
                        ForEach(store.accounts) { acc in
                            let bal = store.currentBalance(forAccount: acc.id)
                            Text("\(acc.name) (Saldo: \(BRLFormatters.currency(bal)))").tag(acc.id)
                        }
                    }

                    DatePicker("Data da Amortização", selection: $date, displayedComponents: [.date])
                }

                Section("Recálculo do Empréstimo / Financiamento") {
                    Picker("Modalidade de Recálculo", selection: $mode) {
                        ForEach(AmortizationRecalculationMode.allCases) { m in
                            Text(m.rawValue).tag(m)
                        }
                    }
                    .onChange(of: mode) { _, _ in
                        recalculatePreview()
                    }

                    HStack(spacing: 14) {
                        EditableIntegerStepperField(
                            label: "Nova Qtd. de Parcelas Restantes",
                            value: $newRemainingInstallments,
                            range: 1...max(currentRemaining, 1),
                            unitSuffix: "parcelas"
                        )

                        BRLCurrencyTextField(
                            label: "Novo Valor da Parcela (R$)",
                            text: $newInstallmentAmountText
                        )
                    }

                    BorderedTextField(
                        label: "Observações (Opcional)",
                        placeholder: "Ex: Amortização extraordinária FGTS / 13º salário",
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
                Spacer()
                Button("Confirmar Amortização e Recalcular") {
                    guard let paidVal = BRLFormatters.parseAmount(amountPaidText), paidVal > 0 else {
                        errorMsg = "Informe um valor amortizado válido maior que zero."
                        return
                    }
                    let customInst = BRLFormatters.parseAmount(newInstallmentAmountText)
                    store.amortizeContract(
                        contractId: contract.id,
                        amountPaid: paidVal,
                        accountId: selectedAccountId,
                        date: date,
                        mode: mode,
                        customNewInstallmentAmount: customInst,
                        customNewRemainingInstallments: newRemainingInstallments,
                        notes: notes
                    )
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(hex: "#D97706"))
            }
        }
        .padding(22)
        .frame(width: 580, height: 590)
        .onAppear {
            selectedAccountId = contract.accountId
            newRemainingInstallments = max(store.remainingInstallmentsCount(for: contract), 1)
            newInstallmentAmountText = BRLFormatters.currency(contract.installmentAmount)
        }
    }

    private func recalculatePreview() {
        guard let paid = BRLFormatters.parseAmount(amountPaidText), paid > 0 else { return }
        let prevRem = store.remainingInstallmentsCount(for: contract)
        let prevInst = contract.installmentAmount
        let currentPV = max(store.projectedPayoffAmount(for: contract), paid)
        let newPV = max(currentPV - paid, 0)
        let i = contract.monthlyInterestRate / 100.0

        if newPV <= 0.01 {
            newRemainingInstallments = 1
            newInstallmentAmountText = BRLFormatters.currency(0.0)
            return
        }

        switch mode {
        case .reduceTerm:
            if i > 0.0001 && prevInst > newPV * i {
                let ratio = 1.0 - (newPV * i) / prevInst
                let calcN = Int(ceil(-log(max(ratio, 0.0001)) / log(1.0 + i)))
                newRemainingInstallments = max(1, min(calcN, prevRem))
            } else {
                newRemainingInstallments = max(1, Int(ceil(newPV / max(prevInst, 1))))
            }
            newInstallmentAmountText = BRLFormatters.currency(prevInst)
        case .reduceInstallment:
            newRemainingInstallments = max(prevRem, 1)
            let newInst: Double
            if i > 0.0001 && prevRem > 0 {
                newInst = newPV * i / (1.0 - pow(1.0 + i, -Double(prevRem)))
            } else {
                newInst = newPV / Double(max(prevRem, 1))
            }
            newInstallmentAmountText = BRLFormatters.currency(newInst)
        }
    }
}

// MARK: - Settle Contract Sheet (Quitar Empréstimo / Financiamento)

public struct SettleContractSheet: View {
    @ObservedObject public var store: FinancialDataStore
    @Environment(\.dismiss) private var dismiss

    public let contract: CreditContract

    @State private var selectedAccountId: UUID = UUID()
    @State private var finalPayoffAmountText: String = ""
    @State private var settleDate: Date = Date()
    @State private var errorMsg: String? = nil

    public init(store: FinancialDataStore, contract: CreditContract) {
        self.store = store
        self.contract = contract
    }

    public var body: some View {
        let outstandingBalance = store.currentOutstandingBalance(for: contract)
        let nominalRemaining = store.remainingNominalAmount(for: contract)
        let projectedPayoff = store.projectedPayoffAmount(for: contract)

        VStack(alignment: .leading, spacing: 18) {
            Text("Quitar \(contract.kind.title): \(contract.name)")
                .font(.title2.bold())
            Text("Confirme o valor final para quitar e selecione a conta de onde saiu o pagamento. Todas as parcelas futuras em aberto serão encerradas.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Form {
                Section("Valores de Referência do Contrato") {
                    HStack {
                        Text("Valor Original Contratado:")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(BRLFormatters.currency(contract.totalContractedAmount))
                            .fontWeight(.medium)
                    }
                    HStack {
                        Text("Saldo Devedor Atual:")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(BRLFormatters.currency(outstandingBalance))
                            .fontWeight(.bold)
                            .foregroundStyle(Color(hex: "#EF4444"))
                    }
                    HStack {
                        Text("Soma Nominal das Parcelas Restantes:")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(BRLFormatters.currency(nominalRemaining))
                            .fontWeight(.semibold)
                    }
                    HStack {
                        Text("Projeção Calculada para Quitar Hoje:")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(BRLFormatters.currency(projectedPayoff))
                            .fontWeight(.bold)
                            .foregroundStyle(Color(hex: "#10B981"))
                    }
                }

                Section("Pagamento da Quitação") {
                    BRLCurrencyTextField(
                        label: "Valor Final para Quitar (R$)",
                        text: $finalPayoffAmountText
                    )

                    HStack {
                        Text("Preencher rápido:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Usar Saldo Devedor (\(BRLFormatters.currency(outstandingBalance)))") {
                            finalPayoffAmountText = BRLFormatters.currency(outstandingBalance)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)

                        Button("Usar Projeção (\(BRLFormatters.currency(projectedPayoff)))") {
                            finalPayoffAmountText = BRLFormatters.currency(projectedPayoff)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }

                    Picker("Conta de onde saiu o dinheiro", selection: $selectedAccountId) {
                        ForEach(store.accounts) { acc in
                            let bal = store.currentBalance(forAccount: acc.id)
                            Text("\(acc.name) (Saldo: \(BRLFormatters.currency(bal)))").tag(acc.id)
                        }
                    }

                    DatePicker("Data da Quitação", selection: $settleDate, displayedComponents: [.date])
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
                Button("Confirmar Quitação") {
                    guard let finalVal = BRLFormatters.parseAmount(finalPayoffAmountText), finalVal > 0 else {
                        errorMsg = "Informe um valor final válido para quitar."
                        return
                    }
                    store.settleContract(
                        contractId: contract.id,
                        finalPayoffAmount: finalVal,
                        accountId: selectedAccountId,
                        date: settleDate
                    )
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(hex: "#10B981"))
            }
        }
        .padding(22)
        .frame(width: 580, height: 520)
        .onAppear {
            selectedAccountId = contract.accountId
            // Vem preenchido inicialmente com o valor original!
            let initialVal = nominalRemaining > 0 ? nominalRemaining : contract.totalContractedAmount
            finalPayoffAmountText = BRLFormatters.currency(initialVal)
        }
    }
}
