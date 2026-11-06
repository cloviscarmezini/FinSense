import SwiftUI

public struct LoansAndFinancingsView: View {
    @ObservedObject public var store: FinancialDataStore
    public let kind: CreditContractKind

    @State private var showCreateSheet: Bool = false
    @State private var contractToAmortize: CreditContract? = nil
    @State private var contractToSettle: CreditContract? = nil
    @State private var contractPendingDeletion: CreditContract? = nil

    public init(store: FinancialDataStore, kind: CreditContractKind) {
        self.store = store
        self.kind = kind
    }

    public var body: some View {
        let activeList = store.activeContracts(for: kind)
        let settledList = store.settledContracts(for: kind)
        let totalNominal = activeList.reduce(0.0) { $0 + store.remainingNominalAmount(for: $1) }
        let totalProjectedPayoff = activeList.reduce(0.0) { $0 + store.projectedPayoffAmount(for: $1) }
        let totalSavingsOnPayoff = max(totalNominal - totalProjectedPayoff, 0)

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(kind == .loan ? "Gestão de Empréstimos" : "Gestão de Financiamentos (Imóvel e Carro)")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                        Text(
                            kind == .loan
                                ? "Controle consignados e empréstimos com cálculo de amortização, projeção de quitação e geração inteligente apenas de parcelas futuras"
                                : "Controle financiamentos de Imóvel e Carro com cálculo de amortização, projeção de quitação e parcelas futuras"
                        )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                    Spacer()

                    Button {
                        showCreateSheet = true
                    } label: {
                        Label("Novo \(kind.title)", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(kind == .loan ? Color(hex: "#D97706") : Color(hex: "#8B5CF6"))
                }

                // KPI Cards
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 3), spacing: 14) {
                    MetricCardView(
                        title: "Saldo Nominal das Parcelas Futuras",
                        value: BRLFormatters.currency(totalNominal),
                        subtitle: "\(activeList.count) \(kind.title.lowercased())(s) ativo(s)",
                        icon: kind == .loan ? "banknote.fill" : "house.and.flag.fill",
                        tint: kind == .loan ? Color(hex: "#D97706") : Color(hex: "#8B5CF6")
                    )

                    MetricCardView(
                        title: "Projeção Total para Quitar Hoje",
                        value: BRLFormatters.currency(totalProjectedPayoff),
                        subtitle: "Valor presente c/ desconto de juros futuros",
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
                        Text("Ao criar um \(kind.title.lowercased()) com data de início no passado, o app preserva todo o histórico contratual mas gera automaticamente apenas as transações das parcelas futuras.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 580)
                        Button("Cadastrar \(kind.title)") {
                            showCreateSheet = true
                        }
                        .buttonStyle(.borderedProminent)
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
            CreateCreditContractSheet(store: store, kind: kind)
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
            Text("Deseja realmente excluir o \(kind.title.lowercased()) \"\(contract.name)\" e remover todas as suas parcelas futuras não pagas? Esta ação não pode ser desfeita.")
        }
    }

    @ViewBuilder
    private func contractCard(_ contract: CreditContract) -> some View {
        let paidCount = store.paidTransactionsCount(forContract: contract)
        let remainingCount = store.remainingInstallmentsCount(for: contract)
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
                    Text("\(contract.amortizationSystem.rawValue) • Cobrança todo dia \(contract.billingDay)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(role: .destructive) {
                    contractPendingDeletion = contract
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Excluir contrato e parcelas futuras não pagas")
            }

            // Contract Details Grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 10) {
                detailCell(label: "Valor Total Contratado", value: BRLFormatters.currency(contract.totalContractedAmount))
                detailCell(label: "Valor da Parcela", value: BRLFormatters.currency(contract.installmentAmount))
                detailCell(label: "Taxa de Juros", value: String(format: "%.2f%% a.m.", contract.monthlyInterestRate))
                detailCell(label: "Parcelas Totais", value: "\(contract.totalInstallments)x (\(remainingCount)x futuras)")
                detailCell(label: "Saldo Nominal Futuro", value: BRLFormatters.currency(nominalRemaining))
                detailCell(
                    label: "Data de Início",
                    value: contract.startDate.map { BRLFormatters.shortDate($0) } ?? "A partir da criação"
                )
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

            // Highlighted Line: "Projeção de valor para quitar"
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .foregroundStyle(Color(hex: "#10B981"))
                        Text("Projeção de valor para quitar:")
                            .font(.subheadline.weight(.semibold))
                    }
                    Text("Desconto estimado de juros futuros (\(contract.subtypeDisplayName)): \(BRLFormatters.currency(discountEstimate))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

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
    private func detailCell(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.bold())
                .lineLimit(1)
        }
    }
}

// MARK: - Create Credit Contract Sheet (Empréstimo ou Financiamento)

public struct CreateCreditContractSheet: View {
    @ObservedObject public var store: FinancialDataStore
    @Environment(\.dismiss) private var dismiss

    public let kind: CreditContractKind

    @State private var name: String = ""
    @State private var loanSubtype: LoanSubtype = .consignado
    @State private var financingSubtype: FinancingSubtype = .imovel
    @State private var amortizationSystem: AmortizationSystem = .price
    @State private var totalContractedText: String = ""
    @State private var installmentAmountText: String = ""
    @State private var billingDay: Int = 10
    @State private var totalInstallments: Int = 48
    @State private var interestRateText: String = "1,65"
    @State private var hasStartDate: Bool = false
    @State private var startDate: Date = Date()
    @State private var accountId: UUID = UUID()
    @State private var notes: String = ""
    @State private var errorMsg: String? = nil

    public init(store: FinancialDataStore, kind: CreditContractKind) {
        self.store = store
        self.kind = kind
    }

    public var body: some View {
        let previewSchedule = store.computePastInstallmentsAndFirstFutureDate(
            startDate: hasStartDate ? startDate : nil,
            billingDay: billingDay,
            totalInstallments: totalInstallments
        )
        let futureToCreate = max(totalInstallments - previewSchedule.pastInstallmentsCount, 0)

        VStack(alignment: .leading, spacing: 18) {
            Text("Cadastrar \(kind.title)")
                .font(.title2.bold())

            Form {
                Section("Identificação e Modalidade") {
                    TextField(
                        kind == .loan
                            ? "Nome (Ex: Consignado Itaú, Empréstimo Pessoal)"
                            : "Nome (Ex: Apartamento Centro, Financiamento Honda Civic)",
                        text: $name
                    )

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

                Section("Valores, Parcelas e Juros") {
                    HStack(spacing: 14) {
                        TextField("Valor Total Contratado (R$)", text: $totalContractedText)
                        TextField("Valor da Parcela (R$)", text: $installmentAmountText)
                    }

                    HStack(spacing: 14) {
                        Stepper("Qtd. de Parcelas: \(totalInstallments)x", value: $totalInstallments, in: 1...420)
                        Stepper("Dia de Cobrança: \(billingDay)", value: $billingDay, in: 1...31)
                    }

                    HStack(spacing: 14) {
                        TextField("Taxa de Juros Mensal (% a.m.)", text: $interestRateText)
                        Picker("Conta Padrão", selection: $accountId) {
                            ForEach(store.accounts) { acc in
                                Text(acc.name).tag(acc.id)
                            }
                        }
                    }
                }

                Section("Data de Início Inteligente (Opcional)") {
                    Toggle("Informar Data de Início do Contrato", isOn: $hasStartDate)

                    if hasStartDate {
                        DatePicker("Data de Início", selection: $startDate, displayedComponents: [.date])
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Como funciona o registro inteligente:")
                            .font(.caption.bold())
                        Text("• O contrato registra o Valor Total, Juros e as \(totalInstallments) parcelas totais.")
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
                    let rateVal = BRLFormatters.parseAmount(interestRateText) ?? 0.0

                    store.createCreditContract(
                        kind: kind,
                        name: cleanName,
                        loanSubtype: kind == .loan ? loanSubtype : nil,
                        financingSubtype: kind == .financing ? financingSubtype : nil,
                        amortizationSystem: amortizationSystem,
                        totalContractedAmount: totalVal,
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
        .frame(width: 620, height: 600)
        .onAppear {
            accountId = store.accounts.first?.id ?? UUID()
        }
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
                    TextField("Valor Amortizado (R$)", text: $amountPaidText)
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

                    Stepper(
                        "Nova Quantidade de Parcelas Restantes: \(newRemainingInstallments)x",
                        value: $newRemainingInstallments,
                        in: 1...max(currentRemaining, 1)
                    )

                    TextField("Novo Valor da Parcela (R$)", text: $newInstallmentAmountText)

                    TextField("Observações (Opcional)", text: $notes)
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
        .frame(width: 560, height: 540)
        .onAppear {
            selectedAccountId = contract.accountId
            newRemainingInstallments = max(store.remainingInstallmentsCount(for: contract), 1)
            newInstallmentAmountText = BRLFormatters.decimalFormatter.string(from: NSNumber(value: contract.installmentAmount))
                ?? String(format: "%.2f", contract.installmentAmount)
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
            newInstallmentAmountText = "0,00"
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
            newInstallmentAmountText = BRLFormatters.decimalFormatter.string(from: NSNumber(value: prevInst))
                ?? String(format: "%.2f", prevInst)
        case .reduceInstallment:
            newRemainingInstallments = max(prevRem, 1)
            let newInst: Double
            if i > 0.0001 && prevRem > 0 {
                newInst = newPV * i / (1.0 - pow(1.0 + i, -Double(prevRem)))
            } else {
                newInst = newPV / Double(max(prevRem, 1))
            }
            newInstallmentAmountText = BRLFormatters.decimalFormatter.string(from: NSNumber(value: newInst))
                ?? String(format: "%.2f", newInst)
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
                    TextField("Valor Final para Quitar (R$)", text: $finalPayoffAmountText)
                        .font(.system(size: 15, weight: .bold))

                    HStack {
                        Text("Preencher rápido:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Usar Valor Original/Nominal (\(BRLFormatters.currency(nominalRemaining)))") {
                            finalPayoffAmountText = BRLFormatters.decimalFormatter.string(from: NSNumber(value: nominalRemaining)) ?? ""
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)

                        Button("Usar Projeção c/ Desconto (\(BRLFormatters.currency(projectedPayoff)))") {
                            finalPayoffAmountText = BRLFormatters.decimalFormatter.string(from: NSNumber(value: projectedPayoff)) ?? ""
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
        .frame(width: 560, height: 490)
        .onAppear {
            selectedAccountId = contract.accountId
            // Vem preenchido inicialmente com o valor original!
            let initialVal = nominalRemaining > 0 ? nominalRemaining : contract.totalContractedAmount
            finalPayoffAmountText = BRLFormatters.decimalFormatter.string(from: NSNumber(value: initialVal))
                ?? String(format: "%.2f", initialVal)
        }
    }
}
