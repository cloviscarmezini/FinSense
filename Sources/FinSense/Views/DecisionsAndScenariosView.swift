import SwiftUI
import Charts

public enum DecisionsTab: String, CaseIterable, Identifiable {
    case amortizeVsInvest = "Amortizar vs. Investir"
    case stressTest = "Stress Test de Caixa"
    case sinkingFunds = "Sinking Funds (Anuais)"

    public var id: String { rawValue }
}

public struct DecisionsAndScenariosView: View {
    @ObservedObject public var store: FinancialDataStore
    @State private var selectedTab: DecisionsTab = .amortizeVsInvest

    // Estado: Amortizar vs. Investir
    @State private var selectedContractId: UUID? = nil
    @State private var extraAmountText: String = "5000"
    @State private var benchmarkAnnualRate: Double = 11.25
    @State private var taxRatePercent: Double = 15.0

    // Estado: Stress Test de Caixa
    @State private var stressName: String = "Cenário Conservador"
    @State private var variableIncomeDropPercent: Double = 30.0
    @State private var unexpectedExpenseText: String = "4000"
    @State private var unexpectedExpenseMonthOffset: Int = 1

    // Estado: Sinking Funds Modal
    @State private var showSinkingFundEditor: Bool = false
    @State private var editingSinkingFund: SinkingFund? = nil
    @State private var depositFundTarget: SinkingFund? = nil
    @State private var depositAmountText: String = ""

    public init(store: FinancialDataStore) {
        self.store = store
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack(alignment: .center, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Motor de Decisão & Cenários \"E se?\"")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                        Text("Simulações financeiras não destrutivas (read-only) e provisões proporcionais para gastos anuais")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()

                    Picker("Módulo", selection: $selectedTab) {
                        ForEach(DecisionsTab.allCases) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 480)
                }

                // Read-only badge when on simulation tabs
                if selectedTab != .sinkingFunds {
                    HStack(spacing: 8) {
                        Image(systemName: "shield.checkered")
                            .foregroundStyle(Color(hex: "#0EA5E9"))
                        Text("Modo Simulação Segura: Nenhuma análise aqui altera seus lançamentos, orçamentos ou contratos reais.")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(Color(hex: "#0EA5E9").opacity(0.10)))
                }

                switch selectedTab {
                case .amortizeVsInvest:
                    amortizeVsInvestSection
                case .stressTest:
                    stressTestSection
                case .sinkingFunds:
                    sinkingFundsSection
                }
            }
            .padding(24)
        }
        .sheet(isPresented: $showSinkingFundEditor) {
            SinkingFundEditorSheet(store: store, existingFund: editingSinkingFund)
        }
        .sheet(item: $depositFundTarget) { fund in
            SinkingFundDepositSheet(store: store, fund: fund)
        }
        .onAppear {
            if selectedContractId == nil {
                selectedContractId = activeContracts.first?.id
            }
        }
    }

    private var activeContracts: [CreditContract] {
        store.contracts.filter { !$0.isSettled }
    }

    // MARK: - 1. Comparador Amortizar vs. Investir

    @ViewBuilder
    private var amortizeVsInvestSection: some View {
        let contracts = activeContracts
        if contracts.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(Color(hex: "#10B981"))
                Text("Nenhum contrato ativo de empréstimo ou financiamento encontrado")
                    .font(.headline)
                Text("Cadastre um empréstimo ou financiamento para comparar a taxa efetiva da dívida contra investimentos em CDI/Selic.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 240)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .controlBackgroundColor)))
        } else {
            let chosen = contracts.first(where: { $0.id == selectedContractId }) ?? contracts[0]
            let balance = store.currentOutstandingBalance(for: chosen)
            let remaining = store.remainingInstallmentsCount(for: chosen)
            let extraAmount = max(100.0, BRLFormatters.parseCurrencyInput(extraAmountText))

            let comparison = DecisionAndScenarioEngine.compareAmortizeVsInvest(
                contract: chosen,
                outstandingBalance: balance,
                remainingMonths: remaining,
                extraAmount: extraAmount,
                benchmarkGrossAnnualRatePercent: benchmarkAnnualRate,
                taxRatePercent: taxRatePercent
            )

            VStack(alignment: .leading, spacing: 16) {
                // Painel de Parâmetros
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Contrato de Crédito")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        Picker("Contrato", selection: Binding(
                            get: { chosen.id },
                            set: { selectedContractId = $0 }
                        )) {
                            ForEach(contracts) { c in
                                Text("\(c.name) (\(c.kind.title))").tag(c.id)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 240)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Aporte Extra Simulado (R$)")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        TextField("Ex: 5000", text: $extraAmountText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 140)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Taxa Bruta Ref. (CDI/Selic % a.a.)")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        HStack(spacing: 6) {
                            Slider(value: $benchmarkAnnualRate, in: 2...22, step: 0.25)
                                .frame(width: 130)
                            Text(String(format: "%.2f%%", benchmarkAnnualRate))
                                .font(.caption.bold().monospacedDigit())
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Alíquota IR (%)")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        Picker("IR", selection: $taxRatePercent) {
                            Text("0% (Isento LCI/LCA)").tag(0.0)
                            Text("15% (> 720 dias)").tag(15.0)
                            Text("17,5%").tag(17.5)
                            Text("20%").tag(20.0)
                            Text("22,5%").tag(22.5)
                        }
                        .labelsHidden()
                        .frame(width: 155)
                    }

                    Spacer()
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .controlBackgroundColor)))

                // Banner Veredito + Break-even
                let verdictColor: Color = {
                    switch comparison.recommendation {
                    case .amortize: return Color(hex: "#10B981")
                    case .invest: return Color(hex: "#3B82F6")
                    case .neutral: return Color(hex: "#F59E0B")
                    }
                }()

                HStack(spacing: 16) {
                    Image(systemName: comparison.recommendation == .amortize ? "flame.fill" : (comparison.recommendation == .invest ? "chart.line.uptrend.xyaxis" : "equal.circle.fill"))
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(verdictColor)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 10) {
                            Text(comparison.recommendation.rawValue)
                                .font(.title3.bold())
                                .foregroundStyle(verdictColor)
                            Text("Break-even líquido: \(String(format: "%.2f", comparison.breakEvenNetAnnualRatePercent))% a.a. (Bruto: \(String(format: "%.2f", comparison.breakEvenGrossAnnualRatePercent))% a.a.)")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(verdictColor.opacity(0.14)))
                                .foregroundStyle(verdictColor)
                        }
                        Text(comparison.explanation)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                    }
                    Spacer()
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(verdictColor.opacity(0.08))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(verdictColor.opacity(0.35), lineWidth: 1))
                )

                // KPI Grid
                Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                    GridRow {
                        MetricCardView(
                            title: "Custo Efetivo da Dívida",
                            value: String(format: "%.2f%% a.a.", comparison.contractEffectiveAnnualRatePercent),
                            subtitle: String(format: "%.2f%% a.m. • Saldo %@", comparison.contractEffectiveMonthlyRatePercent, BRLFormatters.currency(comparison.outstandingBalance)),
                            icon: "percent",
                            tint: Color(hex: "#EF4444")
                        )
                        .frame(maxWidth: .infinity)

                        MetricCardView(
                            title: "Rendimento Líquido Ref.",
                            value: String(format: "%.2f%% a.a.", comparison.benchmarkNetAnnualRatePercent),
                            subtitle: String(format: "%.2f%% a.m. líquido após %.1f%% IR", comparison.benchmarkNetMonthlyRatePercent, taxRatePercent),
                            icon: "chart.line.uptrend.xyaxis",
                            tint: Color(hex: "#3B82F6")
                        )
                        .frame(maxWidth: .infinity)

                        MetricCardView(
                            title: "Economia ao Amortizar",
                            value: BRLFormatters.currency(comparison.amortizeInterestSaved),
                            subtitle: "\(comparison.amortizeMonthsEliminated) mês(es) eliminados no prazo",
                            icon: "checkmark.seal.fill",
                            tint: Color(hex: "#10B981")
                        )
                        .frame(maxWidth: .infinity)

                        MetricCardView(
                            title: "Ganho Líquido ao Investir",
                            value: BRLFormatters.currency(comparison.investProjectedNetGain),
                            subtitle: "Montante final: \(BRLFormatters.currency(comparison.investFinalAmount))",
                            icon: "banknote.fill",
                            tint: Color(hex: "#8B5CF6")
                        )
                        .frame(maxWidth: .infinity)
                    }
                }

                // Gráfico Comparativo de Curvas Acumuladas
                VStack(alignment: .leading, spacing: 12) {
                    Text("Evolução Comparativa: Juros Poupados (Amortização) vs. Rendimento Líquido (Investimento)")
                        .font(.headline)

                    Chart(comparison.curvePoints) { pt in
                        LineMark(
                            x: .value("Mês", pt.monthIndex),
                            y: .value("Valor", pt.amortizedInterestSavedCumulative),
                            series: .value("Estratégia", "Juros Poupados (Amortizar)")
                        )
                        .foregroundStyle(Color(hex: "#10B981"))
                        .lineStyle(StrokeStyle(lineWidth: 2.5))

                        LineMark(
                            x: .value("Mês", pt.monthIndex),
                            y: .value("Valor", pt.investedNetGainCumulative),
                            series: .value("Estratégia", "Ganho Líquido (Investir)")
                        )
                        .foregroundStyle(Color(hex: "#3B82F6"))
                        .lineStyle(StrokeStyle(lineWidth: 2.5))
                    }
                    .frame(height: 240)
                    .chartLegend(position: .top)
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .controlBackgroundColor)))
            }
        }
    }

    // MARK: - 2. Stress Test de Caixa (Sazonalidade e Imprevistos)

    @ViewBuilder
    private var stressTestSection: some View {
        let draftScenario = WhatIfScenario(
            name: stressName,
            variableIncomeReductionPercent: variableIncomeDropPercent,
            unexpectedExpenseAmount: max(0.0, BRLFormatters.parseCurrencyInput(unexpectedExpenseText)),
            unexpectedExpenseMonthOffset: unexpectedExpenseMonthOffset,
            benchmarkAnnualRatePercent: benchmarkAnnualRate,
            netYieldTaxRatePercent: taxRatePercent
        )

        let stressResult = DecisionAndScenarioEngine.runStressTest(
            store: store,
            scenario: draftScenario,
            horizonMonths: 12
        )

        VStack(alignment: .leading, spacing: 16) {
            // Controles do Choque Adverso
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Nome do Cenário")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        TextField("Ex: Queda Bônus + Imprevisto", text: $stressName)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 210)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Queda em Receitas Variáveis/Extras: \(Int(variableIncomeDropPercent))%")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        Slider(value: $variableIncomeDropPercent, in: 0...100, step: 5)
                            .frame(width: 200)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Despesa Imprevista (R$)")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        TextField("Ex: 4000", text: $unexpectedExpenseText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 130)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Mês do Imprevisto")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        Picker("Mês", selection: $unexpectedExpenseMonthOffset) {
                            ForEach(0..<12, id: \.self) { offset in
                                let mDate = store.calendar.date(byAdding: .month, value: offset, to: store.selectedMonth) ?? store.selectedMonth
                                Text(BRLFormatters.shortMonthYearFormatter.string(from: mDate).capitalized).tag(offset)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 120)
                    }

                    Spacer()

                    Button {
                        store.saveWhatIfScenario(draftScenario)
                    } label: {
                        Label("Salvar Cenário", systemImage: "bookmark.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(hex: "#6366F1"))
                }

                if !store.whatIfScenarios.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            Text("Cenários salvos:")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                            ForEach(store.whatIfScenarios) { saved in
                                HStack(spacing: 6) {
                                    Button(saved.name) {
                                        stressName = saved.name
                                        variableIncomeDropPercent = saved.variableIncomeReductionPercent
                                        unexpectedExpenseText = String(format: "%.0f", saved.unexpectedExpenseAmount)
                                        unexpectedExpenseMonthOffset = saved.unexpectedExpenseMonthOffset
                                        benchmarkAnnualRate = saved.benchmarkAnnualRatePercent
                                        taxRatePercent = saved.netYieldTaxRatePercent
                                    }
                                    .buttonStyle(.plain)
                                    .font(.caption.weight(.semibold))

                                    Button {
                                        store.deleteWhatIfScenario(saved.id)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Capsule().fill(Color.primary.opacity(0.06)))
                            }
                        }
                    }
                }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .controlBackgroundColor)))

            // KPIs de Resultado do Stress Test
            Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    MetricCardView(
                        title: "Meses em Risco (Negativos)",
                        value: "\(stressResult.negativeMonthKeys.count) mês(es)",
                        subtitle: stressResult.negativeMonthKeys.isEmpty ? "Caixa suporta o estresse sem negativar" : "Necessário ajuste ou liquidez",
                        icon: stressResult.negativeMonthKeys.isEmpty ? "checkmark.shield.fill" : "exclamationmark.triangle.fill",
                        tint: stressResult.negativeMonthKeys.isEmpty ? Color(hex: "#10B981") : Color(hex: "#EF4444")
                    )
                    .frame(maxWidth: .infinity)

                    MetricCardView(
                        title: "Pior Saldo no Cenário Estressado",
                        value: BRLFormatters.currency(stressResult.lowestStressedBalance),
                        subtitle: stressResult.lowestStressedMonthLabel.map { "Vale mínimo em \($0)" } ?? "Horizonte de 12 meses",
                        icon: "arrow.down.right.circle.fill",
                        tint: stressResult.lowestStressedBalance < 0 ? Color(hex: "#EF4444") : Color(hex: "#10B981")
                    )
                    .frame(maxWidth: .infinity)

                    MetricCardView(
                        title: "Saldo Após Mitigações Sugeridas",
                        value: BRLFormatters.currency(stressResult.mitigatedLowestBalance),
                        subtitle: "\(stressResult.suggestedMitigations.count) ação(ões) sugerida(s) sem alterar a base",
                        icon: "wand.and.stars",
                        tint: stressResult.mitigatedLowestBalance >= 0 ? Color(hex: "#10B981") : Color(hex: "#F59E0B")
                    )
                    .frame(maxWidth: .infinity)
                }
            }

            // Gráfico Baseline vs Estressado
            VStack(alignment: .leading, spacing: 12) {
                Text("Projeção de Caixa: Cenário Base vs. Cenário Estressado (12 meses)")
                    .font(.headline)

                Chart {
                    RuleMark(y: .value("Zero", 0))
                        .foregroundStyle(Color.secondary.opacity(0.45))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))

                    ForEach(stressResult.months) { pt in
                        LineMark(
                            x: .value("Mês", pt.label),
                            y: .value("Saldo", pt.baselineClosingBalance),
                            series: .value("Cenário", "Base Atual")
                        )
                        .foregroundStyle(Color(hex: "#3B82F6"))
                        .lineStyle(StrokeStyle(lineWidth: 2))

                        LineMark(
                            x: .value("Mês", pt.label),
                            y: .value("Saldo", pt.stressedClosingBalance),
                            series: .value("Cenário", "Estressado")
                        )
                        .foregroundStyle(Color(hex: "#EF4444"))
                        .lineStyle(StrokeStyle(lineWidth: 2.5))

                        if pt.isNegative {
                            PointMark(
                                x: .value("Mês", pt.label),
                                y: .value("Saldo", pt.stressedClosingBalance)
                            )
                            .foregroundStyle(Color(hex: "#EF4444"))
                        }
                    }
                }
                .frame(height: 230)
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .controlBackgroundColor)))

            // Sugestões Automáticas de Mitigação
            if !stressResult.suggestedMitigations.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Sugestões para Absorver o Impacto")
                        .font(.headline)

                    ForEach(stressResult.suggestedMitigations) { sug in
                        HStack(spacing: 12) {
                            Image(systemName: "lightbulb.fill")
                                .foregroundStyle(Color(hex: "#F59E0B"))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(sug.title)
                                    .font(.subheadline.bold())
                                Text(sug.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("+\(BRLFormatters.currency(sug.recoveredAmount))")
                                .font(.subheadline.bold().monospacedDigit())
                                .foregroundStyle(Color(hex: "#10B981"))
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color(hex: "#F59E0B").opacity(0.08)))
                    }
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .controlBackgroundColor)))
            }
        }
    }

    // MARK: - 3. Sinking Funds (Caixinhas de Provisão Anual)

    @ViewBuilder
    private var sinkingFundsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Reserva Mensal Proporcional (Integrada ao Orçamento)")
                        .font(.headline)
                    Text("Total reservado mensalmente: \(BRLFormatters.currency(store.totalMonthlySinkingFundContribution))/mês entre \(store.sinkingFunds.filter(\.isEnabled).count) caixinha(s) ativa(s)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    editingSinkingFund = nil
                    showSinkingFundEditor = true
                } label: {
                    Label("Nova Caixinha Anual", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(hex: "#0EA5E9"))
            }

            if store.sinkingFunds.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "tray.and.arrow.down.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(Color(hex: "#0EA5E9"))
                    Text("Nenhuma caixinha de provisão anual cadastrada")
                        .font(.headline)
                    Text("Cadastre gastos sazonais como IPVA, IPTU, Seguro Auto ou Licenciamento para diluir 1/12 por mês no seu orçamento.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, minHeight: 220)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .controlBackgroundColor)))
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 14)], spacing: 14) {
                    ForEach(store.sinkingFunds) { fund in
                        let monthlyShare = DecisionAndScenarioEngine.monthlyReserveContribution(for: fund)
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                CategoryBadgeView(symbol: fund.iconSymbol, colorHex: fund.colorHex, size: 36)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(fund.name)
                                        .font(.headline)
                                    Text("Vence em \(String(format: "%02d/%d", fund.dueMonth, fund.dueYear)) • Ciclo \(fund.recurrenceMonths)m")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Toggle("", isOn: Binding(
                                    get: { fund.isEnabled },
                                    set: { val in
                                        var updated = fund
                                        updated.isEnabled = val
                                        store.updateSinkingFund(updated)
                                    }
                                ))
                                .labelsHidden()
                                .toggleStyle(.switch)
                            }

                            ProgressView(value: fund.progressRatio)
                                .tint(Color(hex: fund.colorHex))

                            HStack {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("Acumulado / Meta")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Text("\(BRLFormatters.currency(fund.accumulatedReserve)) / \(BRLFormatters.currency(fund.targetAmount))")
                                        .font(.subheadline.bold())
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 1) {
                                    Text("Provisão Mensal (1/\(fund.recurrenceMonths))")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Text("\(BRLFormatters.currency(monthlyShare))/mês")
                                        .font(.subheadline.bold())
                                        .foregroundStyle(Color(hex: "#0EA5E9"))
                                }
                            }

                            HStack(spacing: 8) {
                                Button {
                                    depositFundTarget = fund
                                } label: {
                                    Label("Reservar Mês", systemImage: "plus.circle")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)

                                Button {
                                    editingSinkingFund = fund
                                    showSinkingFundEditor = true
                                } label: {
                                    Label("Editar", systemImage: "pencil")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)

                                Spacer()

                                Button(role: .destructive) {
                                    store.deleteSinkingFund(fund.id)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .controlBackgroundColor)))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.08), lineWidth: 1))
                        .opacity(fund.isEnabled ? 1.0 : 0.65)
                    }
                }
            }
        }
    }
}

// MARK: - Sheets Auxiliares de Sinking Fund

public struct SinkingFundEditorSheet: View {
    @ObservedObject public var store: FinancialDataStore
    public let existingFund: SinkingFund?
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var targetAmountText: String = ""
    @State private var recurrenceMonths: Int = 12
    @State private var dueMonth: Int = 1
    @State private var dueYear: Int = Calendar.current.component(.year, from: Date()) + 1
    @State private var accumulatedText: String = "0"
    @State private var selectedCategoryId: UUID? = nil
    @State private var notes: String = ""

    public init(store: FinancialDataStore, existingFund: SinkingFund? = nil) {
        self.store = store
        self.existingFund = existingFund
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(existingFund == nil ? "Nova Caixinha (Sinking Fund)" : "Editar Caixinha")
                .font(.title3.bold())

            Form {
                TextField("Nome (ex: IPVA, IPTU, Seguro Auto)", text: $name)
                TextField("Valor Anual Estimado (R$)", text: $targetAmountText)
                Stepper("Ciclo de rateio: \(recurrenceMonths) mês(es)", value: $recurrenceMonths, in: 2...36)
                HStack {
                    Picker("Mês Vencimento", selection: $dueMonth) {
                        ForEach(1...12, id: \.self) { m in
                            Text("Mês \(m)").tag(m)
                        }
                    }
                    Stepper("Ano: \(dueYear)", value: $dueYear, in: 2024...2040)
                }
                TextField("Já reservado (R$)", text: $accumulatedText)
                Picker("Categoria Vinculada (Opcional)", selection: $selectedCategoryId) {
                    Text("Nenhuma").tag(UUID?.none)
                    ForEach(store.categories(for: .expense)) { cat in
                        Text(cat.name).tag(UUID?.some(cat.id))
                    }
                }
                TextField("Observações", text: $notes)
            }
            .formStyle(.grouped)

            let previewMonthly = max(0.0, BRLFormatters.parseCurrencyInput(targetAmountText)) / Double(max(1, recurrenceMonths))
            Text("Parcela mensal diluída no orçamento: \(BRLFormatters.currency(previewMonthly))/mês")
                .font(.subheadline.bold())
                .foregroundStyle(Color(hex: "#0EA5E9"))

            HStack {
                Spacer()
                Button("Cancelar") { dismiss() }
                Button("Salvar") {
                    let target = max(0.0, BRLFormatters.parseCurrencyInput(targetAmountText))
                    let acc = max(0.0, BRLFormatters.parseCurrencyInput(accumulatedText))
                    guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, target > 0 else { return }
                    if var existing = existingFund {
                        existing.name = name
                        existing.targetAmount = target
                        existing.recurrenceMonths = recurrenceMonths
                        existing.dueMonth = dueMonth
                        existing.dueYear = dueYear
                        existing.accumulatedReserve = acc
                        existing.categoryId = selectedCategoryId
                        existing.notes = notes
                        store.updateSinkingFund(existing)
                    } else {
                        let newFund = SinkingFund(
                            name: name,
                            categoryId: selectedCategoryId,
                            targetAmount: target,
                            recurrenceMonths: recurrenceMonths,
                            dueMonth: dueMonth,
                            dueYear: dueYear,
                            accumulatedReserve: acc,
                            notes: notes
                        )
                        store.addSinkingFund(newFund)
                    }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 460)
        .onAppear {
            if let f = existingFund {
                name = f.name
                targetAmountText = String(format: "%.2f", f.targetAmount)
                recurrenceMonths = f.recurrenceMonths
                dueMonth = f.dueMonth
                dueYear = f.dueYear
                accumulatedText = String(format: "%.2f", f.accumulatedReserve)
                selectedCategoryId = f.categoryId
                notes = f.notes
            }
        }
    }
}

public struct SinkingFundDepositSheet: View {
    @ObservedObject public var store: FinancialDataStore
    public let fund: SinkingFund
    @Environment(\.dismiss) private var dismiss
    @State private var amountText: String = ""

    public init(store: FinancialDataStore, fund: SinkingFund) {
        self.store = store
        self.fund = fund
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Registrar Reserva em \(fund.name)")
                .font(.headline)
            Text("Cota mensal sugerida: \(BRLFormatters.currency(fund.monthlyContribution))")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("Valor a reservar (R$)", text: $amountText)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancelar") { dismiss() }
                Button("Confirmar Reserva") {
                    let amt = BRLFormatters.parseCurrencyInput(amountText)
                    if amt > 0 {
                        store.addReserveDeposit(toSinkingFundId: fund.id, amount: amt)
                    }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 360)
        .onAppear {
            amountText = String(format: "%.2f", DecisionAndScenarioEngine.monthlyReserveContribution(for: fund))
        }
    }
}
