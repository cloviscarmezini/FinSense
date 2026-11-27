import SwiftUI
import Charts

public struct NetWorthDashboardView: View {
    @ObservedObject public var store: FinancialDataStore
    @Environment(\.colorScheme) private var colorScheme

    @State private var showCreateAssetSheet: Bool = false
    @State private var editingAsset: AssetItem? = nil
    @State private var showCreateIncomeSheet: Bool = false
    @State private var editingIncome: IncomeSource? = nil

    public init(store: FinancialDataStore) {
        self.store = store
    }

    public var body: some View {
        let overview = store.netWorthOverview()

        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Patrimônio Líquido & Fontes de Renda")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                        Text("Visão estratégica isolada de Ativos, Passivos, Equity Imobiliário e Capacidade de Poupança")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()

                    Button {
                        _ = store.captureNetWorthSnapshot()
                    } label: {
                        Label("Registrar Snapshot do Mês", systemImage: "camera.aperture")
                    }
                    .buttonStyle(BentoPrimaryButtonStyle(color: FinSenseTheme.indigo))
                }

                // KPIs Estratégicos
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 14)], spacing: 14) {
                    MetricCardView(
                        title: "Patrimônio Líquido (Net Worth)",
                        value: BRLFormatters.currency(overview.netWorthBRL),
                        subtitle: "Ativos Totais − Passivos Totais",
                        icon: "crown.fill",
                        tint: overview.netWorthBRL >= 0 ? Color(hex: "#10B981") : Color(hex: "#EF4444")
                    )

                    MetricCardView(
                        title: "Total de Ativos",
                        value: BRLFormatters.currency(overview.totalAssetsBRL),
                        subtitle: "Liquidez \(BRLFormatters.currency(overview.liquidAssetsBRL)) • Inv. \(BRLFormatters.currency(overview.investmentsBRL))",
                        icon: "chart.bar.fill",
                        tint: Color(hex: "#3B82F6")
                    )

                    MetricCardView(
                        title: "Total de Passivos",
                        value: BRLFormatters.currency(overview.totalLiabilitiesBRL),
                        subtitle: "Contratos \(BRLFormatters.currency(overview.loansAndFinancingsDebtBRL)) • Cartões \(BRLFormatters.currency(overview.creditCardOpenInvoicesBRL))",
                        icon: "exclamationmark.shield.fill",
                        tint: Color(hex: "#EF4444")
                    )

                    MetricCardView(
                        title: "Renda Líquida Mensal Equiv.",
                        value: BRLFormatters.currency(overview.incomeSummary.totalMonthlyExpectedIncomeBRL),
                        subtitle: "Taxa de Poupança est.: \(String(format: "%.1f%%", overview.incomeSummary.estimatedSavingsRatePercent))",
                        icon: "banknote.fill",
                        tint: Color(hex: "#8B5CF6")
                    )
                }

                // Gráficos: Evolução Histórica + Composição por Classe
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Evolução Histórica do Patrimônio Líquido")
                                .font(.headline)
                            Spacer()
                            Text("Liquidez Imediata: \(String(format: "%.1f%%", overview.immediateLiquidityRatioPercent))")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Color(hex: "#10B981").opacity(0.14)))
                        }

                        if store.netWorthSnapshots.isEmpty {
                            VStack(spacing: 8) {
                                Text("Nenhum snapshot mensal salvo ainda")
                                    .font(.subheadline.weight(.semibold))
                                Text("Clique em \"Registrar Snapshot do Mês\" acima para iniciar a série histórica.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, minHeight: 200)
                        } else {
                            Chart(store.netWorthSnapshots.sorted { $0.yearMonthKey < $1.yearMonthKey }) { snap in
                                AreaMark(
                                    x: .value("Mês", "\(snap.yearMonthKey / 100)/\(String(format: "%02d", snap.yearMonthKey % 100))"),
                                    y: .value("Net Worth", snap.netWorthBRL)
                                )
                                .foregroundStyle(Color(hex: "#6366F1").opacity(0.18))

                                LineMark(
                                    x: .value("Mês", "\(snap.yearMonthKey / 100)/\(String(format: "%02d", snap.yearMonthKey % 100))"),
                                    y: .value("Net Worth", snap.netWorthBRL)
                                )
                                .foregroundStyle(Color(hex: "#6366F1"))
                                .symbol(Circle())
                            }
                            .frame(height: 220)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .bentoCard(padding: 18)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Composição de Ativos")
                            .font(.headline)

                        if overview.assetSlices.isEmpty {
                            Text("Sem ativos cadastrados.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, minHeight: 200)
                        } else {
                            Chart(overview.assetSlices) { slice in
                                BarMark(
                                    x: .value("Valor", slice.amountBRL),
                                    y: .value("Classe", slice.label)
                                )
                                .foregroundStyle(Color(hex: slice.colorHex))
                                .annotation(position: .trailing) {
                                    Text("\(String(format: "%.0f%%", slice.percentage))")
                                        .font(.caption2.bold())
                                }
                            }
                            .frame(height: 220)
                        }
                    }
                    .frame(width: 380)
                    .bentoCard(padding: 18)
                }

                // Seção de Bens Patrimoniais Não-Bancários (Imóveis, Veículos, FGTS, Previdência)
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Bens Patrimoniais (Imóveis, Veículos, FGTS & Outros)")
                                .font(.headline)
                            Text("Imóveis/Veículos financiados calculam automaticamente o Equity (Valor de Mercado − Saldo Devedor).")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            showCreateAssetSheet = true
                        } label: {
                            Label("Adicionar Bem/Ativo", systemImage: "plus")
                        }
                        .buttonStyle(BentoGlassButtonStyle(tint: FinSenseTheme.indigo))
                    }

                    if overview.assetEquities.isEmpty {
                        Text("Nenhum bem patrimonial cadastrado. Cadastre imóveis, veículos, saldo FGTS ou previdência privada.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 12)
                    } else {
                        ForEach(overview.assetEquities) { eq in
                            HStack(spacing: 12) {
                                Image(systemName: eq.asset.assetClass.iconSymbol)
                                    .font(.title3)
                                    .foregroundStyle(Color(hex: eq.asset.assetClass.colorHex))
                                    .frame(width: 32)

                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(eq.asset.name)
                                            .font(.subheadline.weight(.semibold))
                                        Text(eq.asset.assetClass.title)
                                            .font(.caption2)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Capsule().fill(Color.primary.opacity(0.07)))
                                    }
                                    if eq.linkedDebtBRL > 0 {
                                        Text("Mercado: \(BRLFormatters.currency(eq.marketValueBRL)) • Dívida vinculada: \(BRLFormatters.currency(eq.linkedDebtBRL))")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    } else if eq.asset.currencyCode != "BRL" {
                                        Text("Original: \(BRLFormatters.currency(eq.asset.currentMarketValue, currencyCode: eq.asset.currencyCode))")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Spacer()

                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(BRLFormatters.currency(eq.equityBRL))
                                        .font(.subheadline.bold().monospacedDigit())
                                        .foregroundStyle(eq.equityBRL >= 0 ? Color(hex: "#10B981") : Color(hex: "#EF4444"))
                                    Text(eq.linkedDebtBRL > 0 ? "Equity Real" : "Valor Atual")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }

                                Button { editingAsset = eq.asset } label: { Image(systemName: "pencil") }
                                    .buttonStyle(.borderless)
                                Button(role: .destructive) { store.deleteAssetItem(eq.asset.id) } label: {
                                    Image(systemName: "trash").foregroundStyle(.red)
                                }
                                .buttonStyle(.borderless)
                            }
                            .padding(11)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(FinSenseTheme.nestedSurface(for: colorScheme)))
                        }
                    }
                }
                .bentoCard(padding: 18)

                // Seção de Fontes de Renda Estruturadas
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Fontes de Renda Estruturadas")
                                .font(.headline)
                            Text("Fixas: \(BRLFormatters.currency(overview.incomeSummary.fixedMonthlyNetBRL))/mês • Sazonais/13º: \(BRLFormatters.currency(overview.incomeSummary.variableAnnualEquivMonthlyBRL))/mês • Passivas: \(BRLFormatters.currency(overview.incomeSummary.passiveMonthlyNetBRL))/mês")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            showCreateIncomeSheet = true
                        } label: {
                            Label("Adicionar Fonte de Renda", systemImage: "plus")
                        }
                        .buttonStyle(BentoGlassButtonStyle(tint: FinSenseTheme.indigo))
                    }

                    if store.incomeSources.isEmpty {
                        Text("Nenhuma fonte de renda cadastrada. Cadastre salário líquido, bônus anual/PLR, 13º ou aluguéis recebidos.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 12)
                    } else {
                        ForEach(store.incomeSources) { src in
                            HStack(spacing: 12) {
                                Image(systemName: "banknote.fill")
                                    .foregroundStyle(src.isActive ? Color(hex: "#10B981") : .secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(src.name)
                                        .font(.subheadline.weight(.semibold))
                                    Text("\(src.kind.title) • \(src.frequency.title)" + (src.payerName.isEmpty ? "" : " • \(src.payerName)"))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("\(BRLFormatters.currency(src.netAmount, currencyCode: src.currencyCode))")
                                        .font(.subheadline.bold().monospacedDigit())
                                    Text("Equiv.: \(BRLFormatters.currency(store.convertToBRL(src.monthlyEquivalentNetAmount, currencyCode: src.currencyCode)))/mês")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Button { editingIncome = src } label: { Image(systemName: "pencil") }
                                    .buttonStyle(.borderless)
                                Button(role: .destructive) { store.deleteIncomeSource(src.id) } label: {
                                    Image(systemName: "trash").foregroundStyle(.red)
                                }
                                .buttonStyle(.borderless)
                            }
                            .padding(11)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(FinSenseTheme.nestedSurface(for: colorScheme)))
                        }
                    }
                }
                .bentoCard(padding: 18)
            }
            .padding(24)
        }
        .sheet(isPresented: $showCreateAssetSheet) {
            AssetItemEditorSheet(store: store, existingAsset: nil)
        }
        .sheet(item: $editingAsset) { item in
            AssetItemEditorSheet(store: store, existingAsset: item)
        }
        .sheet(isPresented: $showCreateIncomeSheet) {
            IncomeSourceEditorSheet(store: store, existingSource: nil)
        }
        .sheet(item: $editingIncome) { src in
            IncomeSourceEditorSheet(store: store, existingSource: src)
        }
    }
}

public struct AssetItemEditorSheet: View {
    @ObservedObject public var store: FinancialDataStore
    public let existingAsset: AssetItem?
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var assetClass: AssetClass = .realEstate
    @State private var purchaseValueText: String = ""
    @State private var marketValueText: String = ""
    @State private var currencyCode: String = "BRL"
    @State private var linkedContractId: UUID? = nil
    @State private var notes: String = ""

    public init(store: FinancialDataStore, existingAsset: AssetItem?) {
        self.store = store
        self.existingAsset = existingAsset
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(existingAsset == nil ? "Novo Bem Patrimonial" : "Editar Bem Patrimonial")
                .font(.title2.bold())
            Form {
                TextField("Nome (Ex: Apartamento Centro, Honda Civic, FGTS)", text: $name)
                Picker("Classe do Ativo", selection: $assetClass) {
                    ForEach(AssetClass.allCases) { cls in Text(cls.title).tag(cls) }
                }
                Picker("Moeda", selection: $currencyCode) {
                    ForEach(SupportedCurrency.allCases) { cur in Text(cur.displayName).tag(cur.rawValue) }
                }
                TextField("Valor de Compra / Custo", text: $purchaseValueText)
                TextField("Valor de Mercado Atual", text: $marketValueText)
                Picker("Financiamento Vinculado (para cálculo de Equity)", selection: $linkedContractId) {
                    Text("Nenhum").tag(UUID?.none)
                    ForEach(store.contracts) { c in Text("\(c.name) (\(c.kind.title))").tag(UUID?.some(c.id)) }
                }
                TextField("Observações", text: $notes)
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancelar") { dismiss() }
                Button("Salvar") {
                    let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    let marketVal = max(0.0, BRLFormatters.parseCurrencyInput(marketValueText))
                    let purchaseVal = max(0.0, BRLFormatters.parseCurrencyInput(purchaseValueText))
                    guard !cleanName.isEmpty else { return }

                    if var existing = existingAsset {
                        existing.name = cleanName
                        existing.assetClass = assetClass
                        existing.purchaseValue = purchaseVal
                        existing.currentMarketValue = marketVal
                        existing.currencyCode = currencyCode
                        existing.linkedFinancingContractId = linkedContractId
                        existing.notes = notes
                        store.updateAssetItem(existing)
                    } else {
                        let newItem = AssetItem(
                            name: cleanName,
                            assetClass: assetClass,
                            purchaseValue: purchaseVal,
                            currentMarketValue: marketVal,
                            linkedFinancingContractId: linkedContractId,
                            currencyCode: currencyCode,
                            notes: notes
                        )
                        store.addAssetItem(newItem)
                    }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 500, height: 470)
        .onAppear {
            if let a = existingAsset {
                name = a.name
                assetClass = a.assetClass
                purchaseValueText = String(format: "%.2f", a.purchaseValue)
                marketValueText = String(format: "%.2f", a.currentMarketValue)
                currencyCode = a.currencyCode
                linkedContractId = a.linkedFinancingContractId
                notes = a.notes
            }
        }
    }
}

public struct IncomeSourceEditorSheet: View {
    @ObservedObject public var store: FinancialDataStore
    public let existingSource: IncomeSource?
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var kind: IncomeSourceKind = .fixedSalary
    @State private var grossText: String = ""
    @State private var netText: String = ""
    @State private var frequency: RecurrenceFrequency = .monthly
    @State private var payerName: String = ""
    @State private var currencyCode: String = "BRL"
    @State private var isActive: Bool = true

    public init(store: FinancialDataStore, existingSource: IncomeSource?) {
        self.store = store
        self.existingSource = existingSource
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(existingSource == nil ? "Nova Fonte de Renda" : "Editar Fonte de Renda")
                .font(.title2.bold())
            Form {
                TextField("Descrição (Ex: Salário CLT, Bônus Anual, Aluguel)", text: $name)
                Picker("Tipo", selection: $kind) {
                    ForEach(IncomeSourceKind.allCases) { k in Text(k.title).tag(k) }
                }
                Picker("Frequência", selection: $frequency) {
                    ForEach(RecurrenceFrequency.allCases) { f in Text(f.title).tag(f) }
                }
                Picker("Moeda", selection: $currencyCode) {
                    ForEach(SupportedCurrency.allCases) { cur in Text(cur.displayName).tag(cur.rawValue) }
                }
                TextField("Valor Bruto", text: $grossText)
                TextField("Valor Líquido Recebido", text: $netText)
                TextField("Fonte Pagadora (Ex: Empresa, Inquilino)", text: $payerName)
                Toggle("Ativa nos cálculos de renda esperada", isOn: $isActive)
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancelar") { dismiss() }
                Button("Salvar") {
                    let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    let netVal = max(0.0, BRLFormatters.parseCurrencyInput(netText))
                    let grossVal = max(netVal, BRLFormatters.parseCurrencyInput(grossText))
                    guard !cleanName.isEmpty, netVal > 0 else { return }

                    if var existing = existingSource {
                        existing.name = cleanName
                        existing.kind = kind
                        existing.grossAmount = grossVal
                        existing.netAmount = netVal
                        existing.frequency = frequency
                        existing.payerName = payerName
                        existing.currencyCode = currencyCode
                        existing.isActive = isActive
                        store.updateIncomeSource(existing)
                    } else {
                        let newSrc = IncomeSource(
                            name: cleanName,
                            kind: kind,
                            grossAmount: grossVal,
                            netAmount: netVal,
                            frequency: frequency,
                            payerName: payerName,
                            currencyCode: currencyCode,
                            isActive: isActive
                        )
                        store.addIncomeSource(newSrc)
                    }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 500, height: 480)
        .onAppear {
            if let s = existingSource {
                name = s.name
                kind = s.kind
                grossText = String(format: "%.2f", s.grossAmount)
                netText = String(format: "%.2f", s.netAmount)
                frequency = s.frequency
                payerName = s.payerName
                currencyCode = s.currencyCode
                isActive = s.isActive
            }
        }
    }
}
