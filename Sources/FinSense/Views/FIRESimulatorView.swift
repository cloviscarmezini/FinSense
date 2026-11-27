import SwiftUI
import Charts

public struct FIRESimulatorView: View {
    @ObservedObject public var store: FinancialDataStore

    @State private var scenarioName: String = "Plano FIRE Principal"
    @State private var monthlyCostOfLiving: Double = 6000.0
    @State private var currentInvestedPatrimony: Double = 0.0
    @State private var includeRealEstateAndFGTS: Bool = false
    @State private var monthlyContribution: Double = 2500.0
    @State private var swrPercent: Double = 4.0
    @State private var nominalReturnPercent: Double = 11.25
    @State private var inflationPercent: Double = 4.5
    @State private var isLoadingMacro: Bool = false
    @State private var macroStatusMessage: String? = nil
    @State private var didSeedFromStore: Bool = false

    public init(store: FinancialDataStore) {
        self.store = store
    }

    public var body: some View {
        let baseline = FIRESimulatorEngine.computeBaselineFromStore(store: store)
        let effectiveInitialPatrimony = currentInvestedPatrimony + (includeRealEstateAndFGTS ? baseline.realEstateAndFGTSBRL : 0.0)
        let activeScenario = FIREPlanScenario(
            name: scenarioName,
            monthlyCostOfLivingBRL: monthlyCostOfLiving,
            currentInvestedPatrimonyBRL: effectiveInitialPatrimony,
            includeRealEstateAndFGTS: includeRealEstateAndFGTS,
            monthlyContributionBRL: monthlyContribution,
            safeWithdrawalRatePercent: swrPercent,
            expectedAnnualNominalReturnPercent: nominalReturnPercent,
            expectedAnnualInflationPercent: inflationPercent
        )
        let simResult = FIRESimulatorEngine.simulate(
            scenario: activeScenario,
            additionalDebtFreedMonthlyContributionBRL: baseline.activeMonthlyDebtInstallmentsBRL,
            debtPayoffYearOffset: max(1, Int(ceil(baseline.estimatedDebtPayoffYears))),
            referenceDate: store.effectiveCurrentDate
        )

        VStack(alignment: .leading, spacing: 18) {
            // KPI Cards FIRE
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 14)], spacing: 14) {
                MetricCardView(
                    title: "Número FIRE (Meta Patrimonial)",
                    value: BRLFormatters.currency(simResult.fireTargetNumberBRL),
                    subtitle: "Para custear \(BRLFormatters.currency(monthlyCostOfLiving))/mês a \(String(format: "%.1f%%", swrPercent)) a.a.",
                    icon: "flame.fill",
                    tint: Color(hex: "#F59E0B")
                )

                MetricCardView(
                    title: "Previsão Base FIRE",
                    value: simResult.yearsToFIREBaseline.map { "\($0) ano\($0 == 1 ? "" : "s")" } ?? "> 40 anos",
                    subtitle: simResult.estimatedFIREDateBaseline.map { "Estimado em \(BRLFormatters.monthYear($0))" } ?? "Aumente o aporte ou reduza o custo",
                    icon: "calendar.badge.clock",
                    tint: Color(hex: "#6366F1")
                )

                MetricCardView(
                    title: "Com Quitação de Dívidas",
                    value: simResult.yearsToFIREPostDebt.map { "\($0) ano\($0 == 1 ? "" : "s")" } ?? "> 40 anos",
                    subtitle: baseline.activeMonthlyDebtInstallmentsBRL > 0
                        ? "Antecipa \(simResult.yearsAcceleratedByDebtPayoff) ano(s) liberando \(BRLFormatters.currency(baseline.activeMonthlyDebtInstallmentsBRL))/mês"
                        : "Nenhuma parcela ativa no momento",
                    icon: "bolt.fill",
                    tint: Color(hex: "#10B981")
                )

                MetricCardView(
                    title: "Juro Real (Fisher)",
                    value: String(format: "%.2f%% a.a.", simResult.annualRealReturnRate * 100.0),
                    subtitle: "Nominal \(String(format: "%.2f%%", nominalReturnPercent)) vs IPCA \(String(format: "%.2f%%", inflationPercent))",
                    icon: "percent",
                    tint: Color(hex: "#0EA5E9")
                )
            }

            // Parâmetros interativos + Gráfico
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Premissas Interativas")
                            .font(.headline)
                        Spacer()
                        Button {
                            loadBaselineFromStore(baseline: baseline)
                        } label: {
                            Label("Sincronizar com Base Real", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    sliderRow(
                        title: "Custo de Vida Alvo Mensal (Base real 6m: \(BRLFormatters.currency(baseline.averageMonthlyCostOfLivingBRL)))",
                        valueText: BRLFormatters.currency(monthlyCostOfLiving),
                        value: $monthlyCostOfLiving,
                        range: 1500...40000,
                        step: 250
                    )

                    sliderRow(
                        title: "Aporte Mensal Projetado",
                        valueText: BRLFormatters.currency(monthlyContribution),
                        value: $monthlyContribution,
                        range: 200...30000,
                        step: 100
                    )

                    sliderRow(
                        title: "Taxa de Retirada Segura (SWR Regra dos 4%)",
                        valueText: String(format: "%.2f%% a.a.", swrPercent),
                        value: $swrPercent,
                        range: 2.5...6.0,
                        step: 0.25
                    )

                    sliderRow(
                        title: "Retorno Nominal Esperado",
                        valueText: String(format: "%.2f%% a.a.", nominalReturnPercent),
                        value: $nominalReturnPercent,
                        range: 4.0...20.0,
                        step: 0.25
                    )

                    sliderRow(
                        title: "Inflação Anual Esperada (IPCA)",
                        valueText: String(format: "%.2f%% a.a.", inflationPercent),
                        value: $inflationPercent,
                        range: 2.0...12.0,
                        step: 0.25
                    )

                    Toggle("Incluir Imóveis + FGTS (\(BRLFormatters.currency(baseline.realEstateAndFGTSBRL)))", isOn: $includeRealEstateAndFGTS)
                        .font(.caption)

                    HStack(spacing: 8) {
                        Button {
                            Task { await fetchMacroFromBCB() }
                        } label: {
                            Label(isLoadingMacro ? "Buscando BCB..." : "Atualizar Selic/IPCA", systemImage: "globe")
                        }
                        .buttonStyle(.bordered)
                        .disabled(isLoadingMacro)

                        Spacer()

                        Button {
                            let toSave = FIREPlanScenario(
                                name: scenarioName,
                                monthlyCostOfLivingBRL: monthlyCostOfLiving,
                                currentInvestedPatrimonyBRL: currentInvestedPatrimony,
                                includeRealEstateAndFGTS: includeRealEstateAndFGTS,
                                monthlyContributionBRL: monthlyContribution,
                                safeWithdrawalRatePercent: swrPercent,
                                expectedAnnualNominalReturnPercent: nominalReturnPercent,
                                expectedAnnualInflationPercent: inflationPercent
                            )
                            store.saveFIREScenario(toSave)
                        } label: {
                            Label("Salvar Cenário", systemImage: "square.and.arrow.down")
                        }
                        .buttonStyle(BentoPrimaryButtonStyle(color: FinSenseTheme.indigo))
                    }

                    if let msg = macroStatusMessage {
                        Text(msg)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 410)
                .bentoCard(padding: 18)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Trajetória Patrimonial (Poder de Compra Real Hoje)")
                        .font(.headline)

                    Chart(simResult.projectionPoints) { pt in
                        LineMark(
                            x: .value("Ano", pt.label),
                            y: .value("Base", pt.baselinePatrimonyBRL),
                            series: .value("Cenário", "Base")
                        )
                        .foregroundStyle(Color(hex: "#6366F1"))

                        LineMark(
                            x: .value("Ano", pt.label),
                            y: .value("Pós-Dívidas", pt.acceleratedPostDebtPatrimonyBRL),
                            series: .value("Cenário", "Acelerado")
                        )
                        .foregroundStyle(Color(hex: "#10B981"))

                        RuleMark(y: .value("Meta FIRE", pt.fireTargetBRL))
                            .foregroundStyle(Color(hex: "#F59E0B"))
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 5]))
                    }
                    .frame(height: 310)

                    if !store.fireScenarios.isEmpty {
                        Divider()
                        Text("Cenários FIRE Salvos")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(store.fireScenarios) { saved in
                                    HStack(spacing: 6) {
                                        Button(saved.name) {
                                            monthlyCostOfLiving = saved.monthlyCostOfLivingBRL
                                            currentInvestedPatrimony = saved.currentInvestedPatrimonyBRL
                                            includeRealEstateAndFGTS = saved.includeRealEstateAndFGTS
                                            monthlyContribution = saved.monthlyContributionBRL
                                            swrPercent = saved.safeWithdrawalRatePercent
                                            nominalReturnPercent = saved.expectedAnnualNominalReturnPercent
                                            inflationPercent = saved.expectedAnnualInflationPercent
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)

                                        Button {
                                            store.deleteFIREScenario(saved.id)
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .bentoCard(padding: 18)
            }
        }
        .onAppear {
            if !didSeedFromStore {
                didSeedFromStore = true
                loadBaselineFromStore(baseline: baseline)
            }
        }
    }

    @ViewBuilder
    private func sliderRow(
        title: String,
        valueText: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title).font(.caption)
                Spacer()
                Text(valueText).font(.caption.bold().monospacedDigit())
            }
            Slider(value: value, in: range, step: step)
        }
    }

    private func loadBaselineFromStore(baseline: FIREBaselineMetrics) {
        monthlyCostOfLiving = max(1500.0, (baseline.averageMonthlyCostOfLivingBRL / 100.0).rounded() * 100.0)
        currentInvestedPatrimony = max(0.0, baseline.currentLiquidAndInvestedBRL)
        monthlyContribution = max(500.0, (baseline.currentMonthlySurplusBRL / 100.0).rounded() * 100.0)
    }

    private func fetchMacroFromBCB() async {
        isLoadingMacro = true
        defer { isLoadingMacro = false }

        // Série BCB 432 = Selic Meta (% a.a.) | Série BCB 13522 = IPCA acumulado 12m (% a.a.)
        async let selicRes = fetchLatestBCBValue(seriesId: 432)
        async let ipcaRes = fetchLatestBCBValue(seriesId: 13522)

        let selic = await selicRes
        let ipca = await ipcaRes
        if let selic {
            nominalReturnPercent = selic
        }
        if let ipca {
            inflationPercent = ipca
        }
        if selic != nil || ipca != nil {
            macroStatusMessage = "Atualizado via BCB: Selic \(String(format: "%.2f%%", nominalReturnPercent)) | IPCA 12m \(String(format: "%.2f%%", inflationPercent))."
        } else {
            macroStatusMessage = "Sem acesso ao BCB no momento — mantendo premissas locais."
        }
    }

    private func fetchLatestBCBValue(seriesId: Int) async -> Double? {
        guard let url = URL(string: "https://api.bcb.gov.br/dados/serie/bcdata.sgs.\(seriesId)/dados/ultimos/1?formato=json") else {
            return nil
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 6.0
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let valStr = arr.first?["valor"] as? String else {
            return nil
        }
        return Double(valStr.replacingOccurrences(of: ",", with: "."))
    }
}
