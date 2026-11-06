import SwiftUI

public struct InvestmentsView: View {
    @ObservedObject public var store: FinancialDataStore

    @State private var showCreateInvestmentSheet: Bool = false
    @State private var selectedInvestmentForAction: InvestmentItem? = nil
    @State private var showGeneralInvestSheet: Bool = false
    @State private var investmentPendingDeletion: InvestmentItem? = nil

    public init(store: FinancialDataStore) {
        self.store = store
    }

    public var body: some View {
        let totalInvested = store.totalInvestmentsBalance
        let consolidatedTotal = store.consolidatedInvestmentsBalance
        let nonConsolidatedTotal = max(totalInvested - consolidatedTotal, 0)

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Investimentos por Grupo")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                        Text("Organize suas reservas (Ex: Caixinha Itaú, CDB Santander), realize aportes entre contas e escolha quais exibir no consolidado")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()

                    Button {
                        showCreateInvestmentSheet = true
                    } label: {
                        Label("Novo Investimento / Grupo", systemImage: "plus.circle")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        showGeneralInvestSheet = true
                    } label: {
                        Label("Investir (Adicionar Valor)", systemImage: "arrow.up.right.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(hex: "#10B981"))
                    .disabled(store.investments.isEmpty)
                }

                // KPI Cards
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 3), spacing: 14) {
                    MetricCardView(
                        title: "Total Geral Investido",
                        value: BRLFormatters.currency(totalInvested),
                        subtitle: "\(store.investments.count) ativo(s) em \(store.investmentGroups.count) grupo(s)",
                        icon: "chart.line.uptrend.xyaxis",
                        tint: Color(hex: "#10B981")
                    )

                    MetricCardView(
                        title: "Exibido no Consolidado",
                        value: BRLFormatters.currency(consolidatedTotal),
                        subtitle: "Somado ao saldo consolidado geral",
                        icon: "checkmark.seal.fill",
                        tint: Color(hex: "#3B82F6")
                    )

                    MetricCardView(
                        title: "Fora do Consolidado",
                        value: BRLFormatters.currency(nonConsolidatedTotal),
                        subtitle: "Apenas registro isolado de reserva",
                        icon: "eye.slash.fill",
                        tint: Color(hex: "#64748B")
                    )
                }

                // Groups List
                if store.investments.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "chart.line.uptrend.xyaxis.circle")
                            .font(.system(size: 46))
                            .foregroundStyle(.secondary)
                        Text("Nenhum investimento cadastrado")
                            .font(.headline)
                        Text("Crie um grupo e investimento (ex: Caixinha Itaú, CDB Santander) para começar a investir.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Button("Criar Primeiro Investimento") {
                            showCreateInvestmentSheet = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, minHeight: 280)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .controlBackgroundColor)))
                } else {
                    ForEach(store.investmentGroups, id: \.self) { groupName in
                        VStack(alignment: .leading, spacing: 12) {
                            let groupItems = store.investments(inGroup: groupName)
                            let groupSum = groupItems.reduce(0.0) { $0 + $1.balance }

                            HStack {
                                Label(groupName, systemImage: "folder.fill.badge.person.crop")
                                    .font(.title3.bold())
                                Spacer()
                                Text("Subtotal do grupo: \(BRLFormatters.currency(groupSum))")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }

                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 16) {
                                ForEach(groupItems) { item in
                                    investmentCard(item)
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
                }
            }
            .padding(24)
        }
        .sheet(isPresented: $showCreateInvestmentSheet) {
            CreateInvestmentSheet(store: store)
        }
        .sheet(item: $selectedInvestmentForAction) { inv in
            ContributeInvestmentSheet(store: store, preselectedInvestmentId: inv.id)
        }
        .sheet(isPresented: $showGeneralInvestSheet) {
            ContributeInvestmentSheet(store: store, preselectedInvestmentId: store.investments.first?.id)
        }
        .alert(
            "Confirmar Exclusão de Investimento",
            isPresented: Binding(
                get: { investmentPendingDeletion != nil },
                set: { if !$0 { investmentPendingDeletion = nil } }
            ),
            presenting: investmentPendingDeletion
        ) { item in
            Button("Excluir Investimento", role: .destructive) {
                store.deleteInvestment(item.id)
                investmentPendingDeletion = nil
            }
            Button("Cancelar", role: .cancel) {
                investmentPendingDeletion = nil
            }
        } message: { item in
            Text("Deseja realmente excluir o investimento \"\(item.name)\" do grupo \"\(item.groupName)\" (Saldo acumulado: \(BRLFormatters.currency(item.balance)))? Esta ação não pode ser desfeita.")
        }
    }

    @ViewBuilder
    private func investmentCard(_ item: InvestmentItem) -> some View {
        let holderAccount = store.account(for: item.investmentAccountId)

        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                CategoryBadgeView(symbol: item.iconSymbol, colorHex: item.colorHex, size: 42)

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name)
                        .font(.headline)
                    HStack(spacing: 6) {
                        Text("Grupo: \(item.groupName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let holderAccount {
                            Text("• Conta: \(holderAccount.name)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer()

                Button(role: .destructive) {
                    investmentPendingDeletion = item
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Excluir investimento")
            }

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Saldo Acumulado")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(BRLFormatters.currency(item.balance))
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(hex: "#10B981"))
                }

                Spacer()

                // Toggle Exibir no Consolidado a qualquer momento
                Toggle(isOn: Binding(
                    get: { item.showInConsolidated },
                    set: { _ in store.toggleInvestmentConsolidated(item.id) }
                )) {
                    Text("Exibir no consolidado")
                        .font(.caption.weight(.medium))
                }
                .toggleStyle(.switch)
                .controlSize(.small)
            }

            if !item.notes.isEmpty {
                Text(item.notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !item.movements.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Últimas Movimentações")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                    ForEach(item.movements.prefix(3)) { mov in
                        let srcName = store.account(for: mov.sourceAccountId)?.name ?? "Conta"
                        let dstName = store.account(for: mov.investmentAccountId)?.name ?? "Investimento"
                        HStack {
                            Text(BRLFormatters.shortDate(mov.date))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                            Text(mov.type == .deposit ? "De \(srcName) → \(dstName)" : "Resgate p/ \(srcName)")
                                .font(.caption2)
                                .lineLimit(1)
                            Spacer()
                            Text((mov.type == .deposit ? "+" : "-") + BRLFormatters.currency(mov.amount))
                                .font(.caption2.bold())
                                .foregroundStyle(mov.type == .deposit ? Color(hex: "#10B981") : Color(hex: "#F59E0B"))
                        }
                    }
                }
            }

            HStack {
                Spacer()
                Button {
                    selectedInvestmentForAction = item
                } label: {
                    Label("Adicionar Valor / Movimentar", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(hex: item.colorHex))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(hex: item.colorHex).opacity(0.25), lineWidth: 1)
        )
    }
}

// MARK: - Create Investment Sheet

public struct CreateInvestmentSheet: View {
    @ObservedObject public var store: FinancialDataStore
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var groupName: String = ""
    @State private var investmentAccountId: UUID = UUID()
    @State private var initialBalanceText: String = "R$ 0,00"
    @State private var showInConsolidated: Bool = true
    @State private var iconSymbol: String = "chart.line.uptrend.xyaxis"
    @State private var colorHex: String = "#10B981"
    @State private var notes: String = ""
    @State private var errorMsg: String? = nil

    private let colorChoices = ["#10B981", "#EC7000", "#EC0000", "#3B82F6", "#8B5CF6", "#EAB308", "#06B6D4"]

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Criar Novo Investimento")
                .font(.title2.bold())

            Form {
                Section("Identificação e Grupo") {
                    BorderedTextField(
                        label: "Grupo do Investimento",
                        placeholder: "Ex: Caixinha Itaú, CDB Santander, Tesouro Direto",
                        text: $groupName
                    )
                    if !store.investmentGroups.isEmpty {
                        HStack {
                            Text("Grupos existentes:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            ForEach(store.investmentGroups, id: \.self) { grp in
                                Button(grp) {
                                    groupName = grp
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.mini)
                            }
                        }
                    }
                    BorderedTextField(
                        label: "Nome do Investimento",
                        placeholder: "Ex: Cofrinho Reserva, CDB Liquidez Diária",
                        text: $name
                    )
                }

                Section("Conta Vinculada e Saldo Inicial") {
                    Picker("Conta onde está o investimento", selection: $investmentAccountId) {
                        ForEach(store.accounts) { acc in
                            Text(acc.name).tag(acc.id)
                        }
                    }
                    BRLCurrencyTextField(
                        label: "Saldo Inicial já investido (R$)",
                        text: $initialBalanceText
                    )
                    Toggle("Exibir no consolidado geral", isOn: $showInConsolidated)
                }

                Section("Cor e Observações") {
                    HStack(spacing: 10) {
                        Text("Cor do Card:")
                        ForEach(colorChoices, id: \.self) { hex in
                            Circle()
                                .fill(Color(hex: hex))
                                .frame(width: 24, height: 24)
                                .overlay(
                                    Circle()
                                        .stroke(Color.primary, lineWidth: colorHex == hex ? 2.5 : 0)
                                )
                                .onTapGesture {
                                    colorHex = hex
                                }
                        }
                    }
                    BorderedTextField(
                        label: "Observações (Opcional)",
                        placeholder: "Ex: 100% do CDI, liquidez diária",
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
                Button("Criar Investimento") {
                    guard !store.accounts.isEmpty else {
                        errorMsg = "Cadastre pelo menos uma conta em Configurações → Contas antes de criar um investimento."
                        return
                    }
                    let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    let cleanGroup = groupName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !cleanName.isEmpty, !cleanGroup.isEmpty else {
                        errorMsg = "Informe o nome do grupo e o nome do investimento."
                        return
                    }
                    let initBal = BRLFormatters.parseAmount(initialBalanceText) ?? 0.0
                    store.addInvestment(
                        name: cleanName,
                        groupName: cleanGroup,
                        investmentAccountId: investmentAccountId,
                        initialBalance: initBal,
                        showInConsolidated: showInConsolidated,
                        iconSymbol: iconSymbol,
                        colorHex: colorHex,
                        notes: notes
                    )
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(hex: "#10B981"))
            }
        }
        .padding(22)
        .frame(width: 540, height: 500)
        .onAppear {
            investmentAccountId = store.accounts.first?.id ?? UUID()
        }
    }
}

// MARK: - Contribute / Add Value to Investment Sheet

public struct ContributeInvestmentSheet: View {
    @ObservedObject public var store: FinancialDataStore
    @Environment(\.dismiss) private var dismiss

    @State private var selectedInvestmentId: UUID = UUID()
    @State private var movementType: InvestmentMovementType = .deposit
    @State private var amountText: String = ""
    @State private var sourceAccountId: UUID = UUID()
    @State private var investmentAccountId: UUID = UUID()
    @State private var date: Date = Date()
    @State private var notes: String = ""
    @State private var errorMsg: String? = nil

    public let preselectedInvestmentId: UUID?

    public init(store: FinancialDataStore, preselectedInvestmentId: UUID?) {
        self.store = store
        self.preselectedInvestmentId = preselectedInvestmentId
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Investir / Movimentar Valor")
                .font(.title2.bold())
            Text("Selecione de qual conta deseja retirar o valor e em qual conta está o investimento. O valor será descontado da conta de origem e adicionado ao investimento.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Form {
                Section("Investimento e Operação") {
                    Picker("Investimento", selection: $selectedInvestmentId) {
                        ForEach(store.investments) { inv in
                            Text("\(inv.groupName) — \(inv.name) (Saldo: \(BRLFormatters.currency(inv.balance)))")
                                .tag(inv.id)
                        }
                    }
                    .onChange(of: selectedInvestmentId) { _, newId in
                        if let found = store.investments.first(where: { $0.id == newId }) {
                            investmentAccountId = found.investmentAccountId
                        }
                    }

                    Picker("Tipo de Operação", selection: $movementType) {
                        ForEach(InvestmentMovementType.allCases) { t in
                            Text(t.title).tag(t)
                        }
                    }
                    .pickerStyle(.segmented)

                    BRLCurrencyTextField(
                        label: "Valor (R$)",
                        text: $amountText
                    )
                    DatePicker("Data", selection: $date, displayedComponents: [.date])
                }

                Section("Origem e Destino entre Contas") {
                    Picker(
                        movementType == .deposit ? "De qual conta tirar o valor (Origem)" : "Para qual conta enviar o resgate",
                        selection: $sourceAccountId
                    ) {
                        ForEach(store.accounts) { acc in
                            let bal = store.currentBalance(forAccount: acc.id)
                            Text("\(acc.name) (Saldo atual: \(BRLFormatters.currency(bal)))").tag(acc.id)
                        }
                    }

                    Picker("Em qual conta está o investimento", selection: $investmentAccountId) {
                        ForEach(store.accounts) { acc in
                            Text(acc.name).tag(acc.id)
                        }
                    }

                    BorderedTextField(
                        label: "Observação (Opcional)",
                        placeholder: "Ex: Aporte mensal, resgate parcial",
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
                Button(movementType == .deposit ? "Confirmar Aporte no Investimento" : "Confirmar Resgate") {
                    guard !store.accounts.isEmpty else {
                        errorMsg = "Cadastre pelo menos uma conta em Configurações → Contas antes de movimentar valores."
                        return
                    }
                    guard let val = BRLFormatters.parseAmount(amountText), val > 0 else {
                        errorMsg = "Informe um valor válido maior que zero."
                        return
                    }
                    store.contributeToInvestment(
                        investmentId: selectedInvestmentId,
                        amount: val,
                        sourceAccountId: sourceAccountId,
                        investmentAccountId: investmentAccountId,
                        date: date,
                        movementType: movementType,
                        notes: notes
                    )
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(hex: "#10B981"))
            }
        }
        .padding(22)
        .frame(width: 560, height: 480)
        .onAppear {
            if let pre = preselectedInvestmentId,
               let inv = store.investments.first(where: { $0.id == pre }) {
                selectedInvestmentId = inv.id
                investmentAccountId = inv.investmentAccountId
            } else if let first = store.investments.first {
                selectedInvestmentId = first.id
                investmentAccountId = first.investmentAccountId
            }
            sourceAccountId = store.accounts.first?.id ?? UUID()
        }
    }
}
