import SwiftUI
import Charts

public struct InvestmentsView: View {
    @ObservedObject public var store: FinancialDataStore

    @State private var showCreateInvestmentSheet: Bool = false
    @State private var selectedInvestmentForAction: InvestmentItem? = nil
    @State private var selectedInvestmentForDetails: InvestmentItem? = nil
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

                // KPI Cards (Equal-Height Grid)
                Grid(horizontalSpacing: 14, verticalSpacing: 14) {
                    GridRow {
                        MetricCardView(
                            title: "Total Geral Investido",
                            value: BRLFormatters.currency(totalInvested),
                            subtitle: "\(store.investments.count) ativo(s) em \(store.investmentGroups.count) grupo(s)",
                            icon: "chart.line.uptrend.xyaxis",
                            tint: Color(hex: "#10B981")
                        )
                        .frame(maxWidth: .infinity)

                        MetricCardView(
                            title: "Exibido no Consolidado",
                            value: BRLFormatters.currency(consolidatedTotal),
                            subtitle: "Somado ao saldo consolidado geral",
                            icon: "checkmark.seal.fill",
                            tint: Color(hex: "#3B82F6")
                        )
                        .frame(maxWidth: .infinity)

                        MetricCardView(
                            title: "Fora do Consolidado",
                            value: BRLFormatters.currency(nonConsolidatedTotal),
                            subtitle: "Apenas registro isolado de reserva",
                            icon: "eye.slash.fill",
                            tint: Color(hex: "#64748B")
                        )
                        .frame(maxWidth: .infinity)
                    }
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

                            Grid(horizontalSpacing: 16, verticalSpacing: 16) {
                                ForEach(Array(stride(from: 0, to: groupItems.count, by: 2)), id: \.self) { rowStart in
                                    GridRow {
                                        investmentCard(groupItems[rowStart])
                                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                                        if rowStart + 1 < groupItems.count {
                                            investmentCard(groupItems[rowStart + 1])
                                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                        } else {
                                            Color.clear
                                                .gridCellUnsizedAxes([.horizontal, .vertical])
                                        }
                                    }
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
        .sheet(item: $selectedInvestmentForDetails) { inv in
            InvestmentDetailView(store: store, investmentId: inv.id)
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
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedInvestmentForDetails = item
                }

                Spacer(minLength: 8)

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
            .frame(minHeight: 44, alignment: .topLeading)

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

            Spacer(minLength: 4)

            HStack(spacing: 8) {
                Button {
                    selectedInvestmentForDetails = item
                } label: {
                    Label("Ver Detalhes", systemImage: "chart.bar.xaxis")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .frame(minHeight: 32)

                Button {
                    selectedInvestmentForAction = item
                } label: {
                    Label("Movimentar", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(hex: item.colorHex))
                .frame(minHeight: 32)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
    @State private var initialBalanceText: String = ""
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
    public let initialMovementType: InvestmentMovementType

    public init(
        store: FinancialDataStore,
        preselectedInvestmentId: UUID?,
        initialMovementType: InvestmentMovementType = .deposit
    ) {
        self.store = store
        self.preselectedInvestmentId = preselectedInvestmentId
        self.initialMovementType = initialMovementType
        _movementType = State(initialValue: initialMovementType)
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
            movementType = initialMovementType
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

// MARK: - Investment Detail View (macOS)

public struct InvestmentDetailView: View {
    @ObservedObject public var store: FinancialDataStore
    public let investmentId: UUID
    @Environment(\.dismiss) private var dismiss

    @State private var selectedYear: Int
    @State private var selectedPeriod: InvestmentPeriodFilter = .oneYear
    @State private var showContributeSheet: Bool = false
    @State private var contributeMovementType: InvestmentMovementType = .deposit
    @State private var movementPendingDeletion: InvestmentMovement? = nil

    public init(store: FinancialDataStore, investmentId: UUID, initialYear: Int? = nil) {
        self.store = store
        self.investmentId = investmentId
        let y = initialYear ?? Calendar.current.component(.year, from: Date())
        _selectedYear = State(initialValue: y)
    }

    private var currentInvestment: InvestmentItem? {
        store.investments.first(where: { $0.id == investmentId })
    }

    private var availableYears: [Int] {
        let currentY = store.calendar.component(.year, from: Date())
        let movYears = store.investmentMovements(for: investmentId).map {
            store.calendar.component(.year, from: $0.date)
        }
        let minY = min(currentY - 2, movYears.min() ?? (currentY - 2))
        let maxY = max(currentY + 2, movYears.max() ?? (currentY + 2))
        return Array(minY...maxY)
    }

    public var body: some View {
        Group {
            if let inv = currentInvestment {
                detailContent(inv)
            } else {
                VStack(spacing: 14) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    Text("Investimento não encontrado ou removido.")
                        .font(.headline)
                    Button("Fechar") { dismiss() }
                        .buttonStyle(.borderedProminent)
                }
                .frame(width: 500, height: 260)
            }
        }
        .frame(minWidth: 860, idealWidth: 960, maxWidth: 1150, minHeight: 680, idealHeight: 800)
        .sheet(isPresented: $showContributeSheet) {
            if let inv = currentInvestment {
                ContributeInvestmentSheet(
                    store: store,
                    preselectedInvestmentId: inv.id,
                    initialMovementType: contributeMovementType
                )
            }
        }
        .alert(
            "Confirmar Exclusão de Movimentação",
            isPresented: Binding(
                get: { movementPendingDeletion != nil },
                set: { if !$0 { movementPendingDeletion = nil } }
            ),
            presenting: movementPendingDeletion
        ) { mov in
            Button("Excluir Movimentação", role: .destructive) {
                store.deleteInvestmentMovement(investmentId: investmentId, movementId: mov.id)
                movementPendingDeletion = nil
            }
            Button("Cancelar", role: .cancel) {
                movementPendingDeletion = nil
            }
        } message: { mov in
            Text("Deseja realmente excluir a movimentação de \(mov.type.title) no valor de \(BRLFormatters.currency(mov.amount)) de \(BRLFormatters.shortDate(mov.date))? O saldo do investimento e o lançamento de conta serão estornados.")
        }
    }

    @ViewBuilder
    private func detailContent(_ inv: InvestmentItem) -> some View {
        let holderAccount = store.account(for: inv.investmentAccountId)
        let movements = store.investmentMovements(for: inv.id)
        let timeline = store.investmentTimeline(for: inv.id, year: selectedYear, period: selectedPeriod)
        let currentYear = store.calendar.component(.year, from: Date())
        let isPastYear = selectedYear < currentYear

        let futureProjections = timeline.filter(\.isFuture).reduce(0.0) { $0 + $1.projectedDeposits }
            + (timeline.first(where: \.isCurrent)?.projectedDeposits ?? 0.0)
        let forecastEndBalance = timeline.last?.endBalance ?? (inv.balance + futureProjections)

        let linkedQuotaRules = store.categoryQuotas.filter {
            $0.quotaType == .investment && $0.linkedInvestmentId == inv.id
        }

        VStack(spacing: 0) {
            // 1. Barra Superior do Modal (Título, Seletor de Ano, Botão Fechar destacado)
            HStack(alignment: .center, spacing: 16) {
                HStack(spacing: 8) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.title3)
                        .foregroundStyle(Color(hex: "#10B981"))
                    Text("Detalhes do Investimento")
                        .font(.title3.bold())
                }

                Spacer()

                // Barra de Seleção de Ano
                HStack(spacing: 6) {
                    Button {
                        if let idx = availableYears.firstIndex(of: selectedYear), idx > 0 {
                            selectedYear = availableYears[idx - 1]
                        } else {
                            selectedYear -= 1
                        }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.caption.bold())
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    ForEach(availableYears.filter { abs($0 - selectedYear) <= 2 }, id: \.self) { y in
                        Button {
                            selectedYear = y
                        } label: {
                            Text(String(y))
                                .font(.subheadline.weight(y == selectedYear ? .bold : .medium))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(y == selectedYear ? Color.accentColor : Color.primary.opacity(0.06))
                                )
                                .foregroundStyle(y == selectedYear ? Color.white : Color.primary)
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        if let idx = availableYears.firstIndex(of: selectedYear), idx < availableYears.count - 1 {
                            selectedYear = availableYears[idx + 1]
                        } else {
                            selectedYear += 1
                        }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.caption.bold())
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    Capsule()
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )

                Spacer()

                // Botão de Fechar Modal claro e destacado
                Button {
                    dismiss()
                } label: {
                    Label("Fechar", systemImage: "xmark")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)
            .padding(.bottom, 12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // 2. Card do Ativo (Identificação, Saldo, Toggle Consolidado, Botões de Movimentação)
                    HStack(alignment: .center, spacing: 14) {
                        CategoryBadgeView(symbol: inv.iconSymbol, colorHex: inv.colorHex, size: 48)

                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Text(inv.name)
                                    .font(.system(size: 22, weight: .bold, design: .rounded))
                                Text(inv.groupName)
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Capsule().fill(Color(hex: inv.colorHex).opacity(0.18)))
                                    .foregroundStyle(Color(hex: inv.colorHex))
                            }

                            HStack(spacing: 6) {
                                Text("Conta de Custódia: \(holderAccount?.name ?? "Não especificada")")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                if !inv.notes.isEmpty {
                                    Text("• \(inv.notes)")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }

                        Spacer()

                        Toggle(isOn: Binding(
                            get: { inv.showInConsolidated },
                            set: { _ in store.toggleInvestmentConsolidated(inv.id) }
                        )) {
                            Text("Exibir no consolidado")
                                .font(.subheadline.weight(.medium))
                        }
                        .toggleStyle(.switch)

                        Divider().frame(height: 32)

                        Button {
                            contributeMovementType = .deposit
                            showContributeSheet = true
                        } label: {
                            Label("Novo Aporte", systemImage: "arrow.down.right.circle.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color(hex: "#10B981"))

                        Button {
                            contributeMovementType = .withdrawal
                            showContributeSheet = true
                        } label: {
                            Label("Resgatar", systemImage: "arrow.up.left.circle.fill")
                        }
                        .buttonStyle(.bordered)
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

                    // 3. Barra de Seleção de Período (Acima dos Cards)
                    HStack {
                        Text("Período do Planejamento:")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)

                        Picker("Período", selection: $selectedPeriod) {
                            ForEach(InvestmentPeriodFilter.allCases) { p in
                                Text(p.title).tag(p)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 320)

                        Spacer()

                        if isPastYear {
                            HStack(spacing: 4) {
                                Image(systemName: "clock.arrow.circlepath")
                                Text("Ano Histórico Encerrado (\(selectedYear))")
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.secondary.opacity(0.12)))
                        }
                    }

                    // 4. Cards de Métricas (Saldo Acumulado, Projeção Futura e Previsão para 12/ANO)
                    Grid(horizontalSpacing: 14, verticalSpacing: 14) {
                        GridRow {
                            if !isPastYear {
                                MetricCardView(
                                    title: "Saldo Acumulado",
                                    value: BRLFormatters.currency(inv.balance),
                                    subtitle: "Posição atual do ativo",
                                    icon: "banknote.fill",
                                    tint: Color(hex: "#10B981")
                                )
                                .frame(maxWidth: .infinity)

                                MetricCardView(
                                    title: "Projeção Futura",
                                    value: BRLFormatters.currency(futureProjections),
                                    subtitle: "Aportes planejados no período",
                                    icon: "chart.line.uptrend.xyaxis",
                                    tint: Color(hex: "#6366F1")
                                )
                                .frame(maxWidth: .infinity)

                                MetricCardView(
                                    title: "Previsão para 12/\(selectedYear)",
                                    value: BRLFormatters.currency(forecastEndBalance),
                                    subtitle: "Saldo estimado em 31/12/\(selectedYear)",
                                    icon: "sparkles",
                                    tint: Color(hex: "#3B82F6")
                                )
                                .frame(maxWidth: .infinity)
                            } else {
                                let openingBal = timeline.first?.baseAccumulated ?? 0.0
                                let yearDeposits = timeline.reduce(0.0) { $0 + $1.deposits }
                                let closingBal = timeline.last?.endBalance ?? 0.0

                                MetricCardView(
                                    title: "Saldo Inicial (\(selectedYear))",
                                    value: BRLFormatters.currency(openingBal),
                                    subtitle: "Posição em 01/01/\(selectedYear)",
                                    icon: "arrow.right.circle.fill",
                                    tint: Color(hex: "#3B82F6")
                                )
                                .frame(maxWidth: .infinity)

                                MetricCardView(
                                    title: "Total Aportado em \(selectedYear)",
                                    value: BRLFormatters.currency(yearDeposits),
                                    subtitle: "Histórico de entradas no exercício",
                                    icon: "arrow.down.right.circle.fill",
                                    tint: Color(hex: "#10B981")
                                )
                                .frame(maxWidth: .infinity)

                                MetricCardView(
                                    title: "Fechamento em 31/12/\(selectedYear)",
                                    value: BRLFormatters.currency(closingBal),
                                    subtitle: "Posição final em 31/12/\(selectedYear)",
                                    icon: "flag.checkered",
                                    tint: Color(hex: "#F59E0B")
                                )
                                .frame(maxWidth: .infinity)
                            }
                        }
                    }

                    // 5. Gráfico de Barras: Acumulado, Aportes, Projeção e Resgates
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Fluxo Mensal & Composição Acumulada")
                                    .font(.headline)
                                Text(isPastYear
                                     ? "Evolução histórica mês a mês em \(selectedYear)"
                                     : "Evolução do saldo acumulado com aportes e projeções de cotas na mesma barra")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()

                            // Legenda com Acumulado, Aportes, Projeção, Resgate
                            HStack(spacing: 14) {
                                HStack(spacing: 6) {
                                    Circle().fill(Color(hex: "#3B82F6")).frame(width: 9, height: 9)
                                    Text("Acumulado").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                                }
                                HStack(spacing: 6) {
                                    Circle().fill(Color(hex: "#10B981")).frame(width: 9, height: 9)
                                    Text("Aportes").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                                }
                                if !isPastYear {
                                    HStack(spacing: 6) {
                                        Circle().fill(Color(hex: "#6366F1")).frame(width: 9, height: 9)
                                        Text("Projeção").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                                    }
                                }
                                HStack(spacing: 6) {
                                    Circle().fill(Color(hex: "#EF4444")).frame(width: 9, height: 9)
                                    Text("Resgate").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                                }
                            }
                        }

                        let hasAnyData = timeline.contains {
                            $0.baseAccumulated > 0 || $0.deposits > 0 || $0.withdrawals > 0 || $0.projectedDeposits > 0
                        }

                        if hasAnyData {
                            Chart {
                                ForEach(timeline) { pt in
                                    // 1. Acumulado (Base da barra)
                                    if pt.baseAccumulated > 0 {
                                        BarMark(
                                            x: .value("Mês", pt.shortLabel),
                                            yStart: .value("Base", 0),
                                            yEnd: .value("Valor", pt.baseAccumulated)
                                        )
                                        .foregroundStyle(Color(hex: "#3B82F6"))
                                        .position(by: .value("Grupo", "Evolução"))
                                        .cornerRadius(pt.deposits > 0 || pt.projectedDeposits > 0 ? 0 : 4)
                                    }

                                    // 2. Aportes (Fatia sobre o acumulado)
                                    if pt.deposits > 0 {
                                        BarMark(
                                            x: .value("Mês", pt.shortLabel),
                                            yStart: .value("Base", pt.baseAccumulated),
                                            yEnd: .value("Valor", pt.baseAccumulated + pt.deposits)
                                        )
                                        .foregroundStyle(Color(hex: "#10B981"))
                                        .position(by: .value("Grupo", "Evolução"))
                                        .cornerRadius(pt.projectedDeposits > 0 ? 0 : 4)
                                    }

                                    // 3. Projeção (Fatia sobre acumulado + aportes)
                                    if pt.projectedDeposits > 0 {
                                        BarMark(
                                            x: .value("Mês", pt.shortLabel),
                                            yStart: .value("Base", pt.baseAccumulated + pt.deposits),
                                            yEnd: .value("Valor", pt.baseAccumulated + pt.deposits + pt.projectedDeposits)
                                        )
                                        .foregroundStyle(Color(hex: "#6366F1"))
                                        .position(by: .value("Grupo", "Evolução"))
                                        .cornerRadius(4)
                                    }

                                    // 4. Resgates (Barra ao lado se houver resgate no mês)
                                    if pt.withdrawals > 0 {
                                        BarMark(
                                            x: .value("Mês", pt.shortLabel),
                                            yStart: .value("Base", 0),
                                            yEnd: .value("Valor", pt.withdrawals)
                                        )
                                        .foregroundStyle(Color(hex: "#EF4444"))
                                        .position(by: .value("Grupo", "Resgates"))
                                        .cornerRadius(4)
                                    }
                                }
                            }
                            .frame(height: 250)
                            .chartYAxis {
                                AxisMarks(position: .leading) { value in
                                    AxisGridLine()
                                    if let doubleVal = value.as(Double.self) {
                                        AxisValueLabel {
                                            Text(BRLFormatters.currency(doubleVal))
                                                .font(.caption2.monospacedDigit())
                                        }
                                    }
                                }
                            }
                        } else {
                            VStack(spacing: 8) {
                                Image(systemName: "chart.bar")
                                    .font(.system(size: 32))
                                    .foregroundStyle(.secondary.opacity(0.6))
                                Text("Nenhum saldo ou movimentação no período selecionado.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, minHeight: 180)
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

                    // 6. Cotas Vinculadas (Planejamento Ativo)
                    if !linkedQuotaRules.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Label("Planejamentos de Investimento Ativos (Cotas)", systemImage: "target")
                                    .font(.headline)
                                Spacer()
                                Text("\(linkedQuotaRules.count) cota(s) vinculada(s)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }

                            ForEach(linkedQuotaRules) { rule in
                                HStack {
                                    CategoryBadgeView(symbol: rule.iconSymbol, colorHex: "#6366F1", size: 34)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(rule.name)
                                            .font(.subheadline.bold())
                                        Text("\(rule.plannedQuantity) un. × \(BRLFormatters.currency(rule.estimatedUnitPrice)) = \(BRLFormatters.currency(Double(rule.plannedQuantity) * rule.estimatedUnitPrice)) / mês")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(rule.repeatForFutureMonths ? "Recorrente (todos os meses)" : "Mês pontual")
                                        .font(.caption2.weight(.medium))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Capsule().fill(Color.primary.opacity(0.06)))
                                }
                                .padding(10)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.02)))
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

                    // 7. Todas as Movimentações
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Label("Todas as Movimentações", systemImage: "clock.arrow.circlepath")
                                .font(.headline)
                            Spacer()
                            Text("\(movements.count) movimentação(ões)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }

                        if movements.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "tray")
                                    .font(.system(size: 30))
                                    .foregroundStyle(.secondary.opacity(0.6))
                                Text("Nenhuma movimentação registrada para este investimento.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Button("Realizar Primeiro Aporte") {
                                    contributeMovementType = .deposit
                                    showContributeSheet = true
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(Color(hex: "#10B981"))
                            }
                            .frame(maxWidth: .infinity, minHeight: 140)
                        } else {
                            VStack(spacing: 8) {
                                ForEach(movements) { mov in
                                    let srcAccount = store.account(for: mov.sourceAccountId)
                                    let dstAccount = store.account(for: mov.investmentAccountId)

                                    HStack(spacing: 12) {
                                        HStack(spacing: 4) {
                                            Image(systemName: mov.type == .deposit ? "arrow.down.right" : "arrow.up.left")
                                                .font(.caption.bold())
                                            Text(mov.type.title)
                                                .font(.caption.bold())
                                        }
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(
                                            Capsule()
                                                .fill((mov.type == .deposit ? Color(hex: "#10B981") : Color(hex: "#EF4444")).opacity(0.15))
                                        )
                                        .foregroundStyle(mov.type == .deposit ? Color(hex: "#10B981") : Color(hex: "#EF4444"))

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(mov.type == .deposit
                                                 ? "De \(srcAccount?.name ?? "Conta") → \(dstAccount?.name ?? "Investimento")"
                                                 : "De \(dstAccount?.name ?? "Investimento") → \(srcAccount?.name ?? "Conta")")
                                                .font(.subheadline.weight(.semibold))

                                            if !mov.notes.isEmpty {
                                                Text(mov.notes)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(2)
                                            }
                                        }

                                        Spacer()

                                        Text(BRLFormatters.shortDate(mov.date))
                                            .font(.caption.monospacedDigit())
                                            .foregroundStyle(.secondary)

                                        Text((mov.type == .deposit ? "+ " : "- ") + BRLFormatters.currency(mov.amount))
                                            .font(.subheadline.bold().monospacedDigit())
                                            .foregroundStyle(mov.type == .deposit ? Color(hex: "#10B981") : Color(hex: "#EF4444"))
                                            .frame(minWidth: 110, alignment: .trailing)

                                        Button(role: .destructive) {
                                            movementPendingDeletion = mov
                                        } label: {
                                            Image(systemName: "trash")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        .buttonStyle(.borderless)
                                        .help("Excluir movimentação")
                                    }
                                    .padding(12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(Color.primary.opacity(0.025))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .stroke(Color.primary.opacity(0.05), lineWidth: 1)
                                    )
                                }
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
                .padding(24)
            }
        }
    }
}
