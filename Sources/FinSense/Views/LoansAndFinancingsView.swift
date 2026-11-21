import SwiftUI

public struct LoansAndFinancingsView: View {
    @ObservedObject public var store: FinancialDataStore
    @ObservedObject public var llmService: LocalLLMService
    public let kind: CreditContractKind

    @State private var showCreateSheet: Bool = false
    @State private var showImportDocumentSheet: Bool = false
    @State private var contractToAmortize: CreditContract? = nil
    @State private var contractToSettle: CreditContract? = nil
    @State private var contractToPlan: CreditContract? = nil
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

                    if store.hasAnyAmortizationPlan {
                        Picker("Cenário", selection: $store.budgetProjectionScenario) {
                            ForEach(BudgetProjectionScenario.allCases) { scenario in
                                Text(scenario.rawValue).tag(scenario)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 240)
                        .help("Alterne entre a visão contratual base (Camada 1) e a projeção com planejamento de amortização (Camada 3)")
                    }

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

                // KPI Cards (Equal-Height Grid)
                Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                    GridRow {
                        MetricCardView(
                            title: kind == .loan ? "Saldo Devedor (Para quitar hoje)" : "Saldo Devedor Atual",
                            value: BRLFormatters.currency(totalOutstandingBalance),
                            subtitle: "\(activeList.count) \(kind.title.lowercased())(s) ativo(s)",
                            icon: "exclamationmark.shield.fill",
                            tint: Color(hex: "#EF4444")
                        )
                        .frame(maxWidth: .infinity)

                        MetricCardView(
                            title: kind == .loan ? "Economia se Quitar Hoje" : "Soma Nominal das Parcelas",
                            value: kind == .loan ? BRLFormatters.currency(max(0.0, totalNominal - totalOutstandingBalance)) : BRLFormatters.currency(totalNominal),
                            subtitle: kind == .loan ? "Juros futuros economizados na quitação" : "Total das parcelas futuras a vencer",
                            icon: kind == .loan ? "sparkles.rectangle.stack.fill" : (kind == .loan ? "banknote.fill" : "house.and.flag.fill"),
                            tint: kind == .loan ? Color(hex: "#10B981") : Color(hex: "#8B5CF6")
                        )
                        .frame(maxWidth: .infinity)

                        MetricCardView(
                            title: kind == .loan ? "Soma Nominal (c/ Juros Futuros)" : "Projeção para Quitar Hoje",
                            value: kind == .loan ? BRLFormatters.currency(totalNominal) : BRLFormatters.currency(totalProjectedPayoff),
                            subtitle: kind == .loan ? "Fluxo contratado se pagar mês a mês" : "Valor presente c/ desconto de juros",
                            icon: kind == .loan ? "banknote.fill" : "sparkles.rectangle.stack.fill",
                            tint: kind == .loan ? Color(hex: "#64748B") : Color(hex: "#10B981")
                        )
                        .frame(maxWidth: .infinity)

                        MetricCardView(
                            title: kind == .loan ? "Contratos Liquidados" : "Economia Estimada na Quitação",
                            value: kind == .loan ? "\(settledList.count) quitado(s)" : BRLFormatters.currency(totalSavingsOnPayoff),
                            subtitle: kind == .loan ? "Encerrados com desconto integral" : "\(settledList.count) contrato(s) já quitado(s)",
                            icon: kind == .loan ? "checkmark.seal.fill" : "arrow.down.right.circle.fill",
                            tint: Color(hex: "#3B82F6")
                        )
                        .frame(maxWidth: .infinity)
                    }
                }

                // Active Contracts Grid (Equal-Height Rows)
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
                    Grid(horizontalSpacing: 18, verticalSpacing: 18) {
                        ForEach(Array(stride(from: 0, to: activeList.count, by: 2)), id: \.self) { rowStart in
                            GridRow {
                                contractCard(activeList[rowStart])
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                if rowStart + 1 < activeList.count {
                                    contractCard(activeList[rowStart + 1])
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                } else {
                                    Color.clear
                                        .gridCellUnsizedAxes([.horizontal, .vertical])
                                }
                            }
                        }
                    }
                }

                if !settledList.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(Color(hex: "#10B981"))
                            Text("Contratos Liquidados / Quitados (\(settledList.count))")
                                .font(.headline.bold())
                        }
                        .padding(.top, 12)

                        Grid(horizontalSpacing: 18, verticalSpacing: 18) {
                            ForEach(Array(stride(from: 0, to: settledList.count, by: 2)), id: \.self) { rowStart in
                                GridRow {
                                    contractCard(settledList[rowStart])
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    if rowStart + 1 < settledList.count {
                                        contractCard(settledList[rowStart + 1])
                                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    } else {
                                        Color.clear
                                            .gridCellUnsizedAxes([.horizontal, .vertical])
                                    }
                                }
                            }
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
        .sheet(item: $contractToPlan) { contract in
            AmortizationPlannerSheet(store: store, contract: contract)
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
        let metrics = store.progressMetrics(for: contract)
        let hasExtraAmortization = metrics.eliminatedByAmortizationCount > 0 || contract.extraAmortizedTotal > 0.01
        let paidCount = metrics.paidInFlowCount
        let remainingCount = metrics.remainingCount
        let outstandingBalance = store.currentOutstandingBalance(for: contract)
        let nominalRemaining = store.remainingNominalAmount(for: contract)
        let projectedPayoff = store.projectedPayoffAmount(for: contract)
        let discountEstimate = max(nominalRemaining - projectedPayoff, 0)
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

                        if contract.isSettled {
                            Text("QUITADO")
                                .font(.caption2.bold())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Color(hex: "#10B981").opacity(0.16)))
                                .foregroundStyle(Color(hex: "#10B981"))
                        }

                        if contract.kind == .loan && (contract.loanSubtype == .consignado || contract.effectiveLoanModel?.isPayrollDeductible == true) {
                            HStack(spacing: 4) {
                                Image(systemName: "person.text.rectangle.fill")
                                Text("Débito Direto em Folha")
                            }
                            .font(.caption2.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color(hex: "#10B981").opacity(0.16)))
                            .foregroundStyle(Color(hex: "#10B981"))
                        }
                    }
                    HStack(spacing: 6) {
                        if contract.effectiveBankDueDay != contract.billingDay {
                            Text("\(contract.amortizationSystem.rawValue) • Cobrança no salário: dia \(contract.billingDay) • Vencimento no banco: dia \(contract.effectiveBankDueDay)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("\(contract.amortizationSystem.rawValue) • Cobrança/Vencimento todo dia \(contract.billingDay)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let contractNo = contract.contractNumber, !contractNo.isEmpty {
                            Text("• Contrato: \(contractNo)")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer(minLength: 8)

                Button(role: .destructive) {
                    contractPendingDeletion = contract
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Excluir contrato e todas as suas transações vinculadas")
            }
            .frame(minHeight: 46, alignment: .topLeading)

            // Contract Details Grid
            if contract.kind == .financing {
                let finModel = contract.effectiveFinancingModel
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 10) {
                    detailCell(
                        label: "Saldo Devedor Teórico",
                        value: BRLFormatters.currency(outstandingBalance),
                        valueColor: Color(hex: "#EF4444")
                    )
                    detailCell(label: "Valor Total Contratado", value: BRLFormatters.currency(contract.totalContractedAmount))
                    detailCell(label: "Parcela Total Devida", value: BRLFormatters.currency(contract.installmentAmount))

                    detailCell(label: "Parcela Base Price", value: BRLFormatters.currency(contract.effectiveBaseInstallmentPrice))
                    detailCell(label: "Seguros MIP/DFI", value: BRLFormatters.currency(contract.effectiveInsuranceFee))
                    detailCell(label: "Taxa de Administração", value: BRLFormatters.currency(contract.effectiveAdminFee))

                    detailCell(
                        label: "Taxa Nominal Anual",
                        value: String(format: "%.2f%% a.a. (%.4f%% a.m.)", contract.effectiveAnnualNominalRate, contract.effectiveMonthlyNominalRateDecimal * 100.0)
                    )
                    detailCell(
                        label: "Amortização Real no Mês",
                        value: BRLFormatters.currency(finModel?.currentMonthlyAmortization ?? 0.0),
                        valueColor: Color(hex: "#10B981")
                    )
                    detailCell(
                        label: "Juros no Mês",
                        value: BRLFormatters.currency(finModel?.currentMonthlyInterest ?? 0.0),
                        valueColor: Color(hex: "#EF4444")
                    )

                    detailCell(label: "Indexador", value: contract.indexationRate?.rawValue ?? "TR")

                    if hasExtraAmortization {
                        detailCell(
                            label: "Prazo Original Contratado",
                            value: metrics.originalMonthsFormatted
                        )
                        detailCell(
                            label: "Novo Prazo Recalculado",
                            value: metrics.newRecalculatedMonthsFormatted
                        )
                        detailCell(
                            label: "Tempo Poupado",
                            value: "⚡ \(metrics.savedTimeString) adiantados",
                            valueColor: Color(hex: "#10B981")
                        )
                        detailCell(
                            label: "Total Amortizado Extraordinário",
                            value: "\(BRLFormatters.currency(contract.extraAmortizedTotal)) (\(metrics.eliminatedByAmortizationCount) parcelas eliminadas)",
                            valueColor: Color(hex: "#10B981")
                        )
                        detailCell(
                            label: "Parcelas Futuras Restantes",
                            value: "\(remainingCount) parcelas a pagar"
                        )
                        detailCell(
                            label: "Soma Nominal Futura",
                            value: BRLFormatters.currency(nominalRemaining)
                        )
                    } else {
                        detailCell(
                            label: "Prazo Contratado",
                            value: metrics.originalMonthsFormatted
                        )
                        detailCell(
                            label: "Parcelas Restantes",
                            value: "\(remainingCount) parcelas a pagar"
                        )
                        detailCell(
                            label: "Soma Nominal Futura",
                            value: BRLFormatters.currency(nominalRemaining)
                        )
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, minHeight: 215, alignment: .topLeading)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.03)))
            } else {
                let loanModel = contract.effectiveLoanModel
                let estimatedInterestSavings = max(0.0, nominalRemaining - outstandingBalance)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 10) {
                    detailCell(
                        label: "Saldo Devedor (Para quitar hoje)",
                        value: BRLFormatters.currency(outstandingBalance),
                        valueColor: Color(hex: "#EF4444")
                    )
                    detailCell(
                        label: "Economia se Quitar Hoje",
                        value: BRLFormatters.currency(estimatedInterestSavings),
                        valueColor: Color(hex: "#10B981")
                    )
                    detailCell(label: "Valor Total Contratado (PV)", value: BRLFormatters.currency(contract.totalContractedAmount))

                    detailCell(label: "Valor Fixo da Parcela (PMT)", value: BRLFormatters.currency(contract.installmentAmount))
                    detailCell(
                        label: "Amortização Real no Mês",
                        value: BRLFormatters.currency(loanModel?.currentMonthlyAmortization ?? 0.0),
                        valueColor: Color(hex: "#10B981")
                    )
                    detailCell(
                        label: "Juros no Mês",
                        value: BRLFormatters.currency(loanModel?.currentMonthlyInterest ?? 0.0),
                        valueColor: Color(hex: "#EF4444")
                    )

                    detailCell(label: "Taxa de Juros Mensal", value: String(format: "%.2f%% a.m.", contract.monthlyInterestRate))

                    if hasExtraAmortization {
                        detailCell(
                            label: "Prazo Original Contratado",
                            value: metrics.originalMonthsFormatted
                        )
                        detailCell(
                            label: "Novo Prazo Recalculado",
                            value: metrics.newRecalculatedMonthsFormatted
                        )
                        detailCell(
                            label: "Tempo Poupado",
                            value: "⚡ \(metrics.savedTimeString) adiantados",
                            valueColor: Color(hex: "#10B981")
                        )
                        detailCell(
                            label: "Total Amortizado Extraordinário",
                            value: "\(BRLFormatters.currency(contract.extraAmortizedTotal)) (\(metrics.eliminatedByAmortizationCount) parcelas eliminadas)",
                            valueColor: Color(hex: "#10B981")
                        )
                        detailCell(
                            label: "Parcelas Futuras Restantes",
                            value: "\(remainingCount) parcelas a pagar"
                        )
                        detailCell(
                            label: "Soma Nominal (Fluxo c/ Juros)",
                            value: BRLFormatters.currency(nominalRemaining),
                            valueColor: Color(hex: "#64748B")
                        )
                    } else {
                        detailCell(
                            label: "Prazo Contratado",
                            value: metrics.originalMonthsFormatted
                        )
                        detailCell(
                            label: "Parcelas Restantes",
                            value: "\(remainingCount) parcelas a pagar"
                        )
                        detailCell(
                            label: "Soma Nominal (Fluxo c/ Juros)",
                            value: BRLFormatters.currency(nominalRemaining),
                            valueColor: Color(hex: "#64748B")
                        )
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, minHeight: 180, alignment: .topLeading)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.03)))
            }

            // Segmented Progress Bar & Legend
            VStack(alignment: .leading, spacing: 8) {
                // Bar Header: Dualidade de Prazos vs. Unificado
                Group {
                    if hasExtraAmortization {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text("Avanço Frente ao Original: \(metrics.totalOvercomeMonths) de \(metrics.originalTotalInstallments) meses superados (\(String(format: "%.0f%% concluído", metrics.globalCompletionPercentage * 100)))")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Spacer()
                            }
                            HStack {
                                Text("Plano Atual: \(metrics.paidInFlowCount) de \(metrics.newRecalculatedTotalInstallments) parcelas (\(String(format: "%.0f%%", metrics.currentPlanCompletionPercentage * 100)))")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text("Progresso: \(paidCount) de \(contract.totalInstallments) parcelas pagas (\(String(format: "%.0f%% concluído", metrics.globalCompletionPercentage * 100)))")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Spacer()
                            }
                            Text("Cronograma regular sem amortizações extraordinárias")
                                .font(.caption2)
                                .foregroundStyle(.secondary.opacity(0.75))
                        }
                    }
                }
                .frame(minHeight: 34, alignment: .topLeading)

                // 3-Segment Visual Bar
                SegmentedContractProgressBar(metrics: metrics, accentHex: accentHex)

                // Legend: Bullets Alinhados Minimalistas
                HStack(alignment: .center, spacing: 18) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color(hex: accentHex))
                            .frame(width: 8, height: 8)
                        Text("\(paidCount) parcelas pagas")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    if hasExtraAmortization {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color(hex: "#10B981"))
                                .frame(width: 8, height: 8)
                            Text("\(metrics.eliminatedByAmortizationCount) parcelas amortizadas")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if contract.isSettled || remainingCount == 0 {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color(hex: "#10B981"))
                                .frame(width: 8, height: 8)
                            Text("Totalmente quitado")
                                .font(.caption2.bold())
                                .foregroundStyle(Color(hex: "#10B981"))
                        }
                    } else {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color.primary.opacity(0.28))
                                .frame(width: 8, height: 8)
                            Text("\(remainingCount) parcelas a pagar")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()
                }
                .frame(minHeight: 18, alignment: .leading)
            }

            // Highlighted Line: "Projeção de valor para quitar" / "Contrato Quitado"
            if contract.isSettled {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(Color(hex: "#10B981"))
                            Text("Contrato Liquidado com Sucesso")
                                .font(.subheadline.weight(.semibold))
                        }
                        Text(contract.settledDate.map { "Encerrado em \(BRLFormatters.shortDate($0)) • Nenhuma parcela futura pendente" } ?? "Nenhuma parcela futura pendente")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text(BRLFormatters.currency(0.0))
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color(hex: "#10B981"))
                }
                .padding(12)
                .frame(minHeight: 64)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(hex: "#10B981").opacity(0.10))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color(hex: "#10B981").opacity(0.30), lineWidth: 1)
                )
            } else {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles")
                                .foregroundStyle(Color(hex: "#10B981"))
                            Text(kind == .loan ? "Valor para Quitar Hoje (Saldo Devedor PV):" : "Projeção de valor para quitar:")
                                .font(.subheadline.weight(.semibold))
                        }
                        Text(kind == .loan
                            ? "Economia estimada de juros futuros: \(BRLFormatters.currency(discountEstimate)) (Soma Nominal: \(BRLFormatters.currency(nominalRemaining)))"
                            : "Saldo Devedor: \(BRLFormatters.currency(outstandingBalance)) • Desconto est. sobre nominal: \(BRLFormatters.currency(discountEstimate))"
                        )
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        let kindLower = contract.kind == .loan ? "empréstimo" : "financiamento"
                        let question = "[NOVA SIMULAÇÃO DO SISTEMA] Monte um plano de ação para eu quitar meu \(kindLower) \"\(contract.name)\" no menor prazo possível"
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

                    Text(BRLFormatters.currency(kind == .loan ? outstandingBalance : projectedPayoff))
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color(hex: "#10B981"))
                }
                .padding(12)
                .frame(minHeight: 64)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(hex: "#10B981").opacity(0.10))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color(hex: "#10B981").opacity(0.30), lineWidth: 1)
                )
            }

            if !contract.notes.isEmpty {
                Text(contract.notes)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            // Banner de Resolução Assistida de Aportes Vencidos (Camada 2 -> .expired)
            if !contract.isSettled {
                let expiredItems = store.expiredPlannedAmortizations(for: contract.id)
                if !expiredItems.isEmpty {
                    ForEach(expiredItems) { expiredItem in
                        ExpiredAmortizationResolutionBanner(
                            store: store,
                            contract: contract,
                            expiredItem: expiredItem
                        )
                    }
                }

                // Resumo do Planejamento de Amortização Ativo (Camada 3 — Read Model)
                if let plan = store.amortizationPlan(for: contract.id),
                   plan.items.contains(where: { $0.status == .pending }),
                   let projection = store.loanProjection(for: contract.id) {
                    let pendingCount = plan.items.filter { $0.status == .pending }.count
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "calendar.badge.clock")
                                .foregroundStyle(Color(hex: "#6366F1"))
                            Text("Planejamento de Amortização Ativo (\(pendingCount) aporte\(pendingCount > 1 ? "s" : "") planejado\(pendingCount > 1 ? "s" : ""))")
                                .font(.caption.bold())
                                .foregroundStyle(Color(hex: "#6366F1"))
                            Spacer()
                            Button("Editar Plano") {
                                contractToPlan = contract
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)

                            Button(role: .destructive) {
                                store.deleteAmortizationPlan(for: contract.id)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .controlSize(.mini)
                            .help("Excluir planejamento de amortização")
                        }

                        HStack(spacing: 16) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Total Planejado")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                Text(BRLFormatters.currency(LoanProjectionEngine.toDouble(projection.totalExtraAmortized)))
                                    .font(.caption.bold())
                            }
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Nova Quitação Projetada")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                Text("\(BRLFormatters.shortDate(projection.projectedMaturityDate)) (vs \(BRLFormatters.shortDate(projection.originalMaturityDate)))")
                                    .font(.caption.bold())
                                    .foregroundStyle(Color(hex: "#10B981"))
                            }
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Meses Economizados")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                Text("\(projection.monthsSaved) parcelas suprimidas")
                                    .font(.caption.bold())
                                    .foregroundStyle(Color(hex: "#10B981"))
                            }
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Juros Economizados")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                Text(BRLFormatters.currency(LoanProjectionEngine.toDouble(projection.totalInterestSaved)))
                                    .font(.caption.bold())
                                    .foregroundStyle(Color(hex: "#3B82F6"))
                            }
                        }
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(hex: "#6366F1").opacity(0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color(hex: "#6366F1").opacity(0.30), lineWidth: 1)
                    )
                }
            }

            // Espaçador flexível (mola) para nivelamento e ancoragem dos botões na base
            Spacer(minLength: 4)

            // Action Buttons: Planejar Amortização, Amortizar Agora & Quitar (Ancorados no rodapé)
            if contract.isSettled {
                HStack {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(Color(hex: "#10B981"))
                    Text("Contrato Liquidado / Quitado")
                        .font(.subheadline.bold())
                        .foregroundStyle(Color(hex: "#10B981"))
                    Spacer()
                    if let settledDate = contract.settledDate {
                        Text("Liquidado em \(BRLFormatters.shortDate(settledDate))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(10)
                .frame(minHeight: 38)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(hex: "#10B981").opacity(0.12))
                )
            } else {
                HStack(spacing: 10) {
                    Button {
                        contractToPlan = contract
                    } label: {
                        Label("Planejar Amortização", systemImage: "calendar.badge.clock")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(hex: "#6366F1"))

                    Button {
                        contractToAmortize = contract
                    } label: {
                        Label("Amortizar Agora", systemImage: "arrow.down.forward.and.arrow.up.backward.circle.fill")
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
                .frame(minHeight: 38)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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

// MARK: - Segmented Contract Progress Bar

public struct SegmentedContractProgressBar: View {
    public let metrics: ContractProgressMetrics
    public let accentHex: String

    public init(metrics: ContractProgressMetrics, accentHex: String) {
        self.metrics = metrics
        self.accentHex = accentHex
    }

    public var body: some View {
        GeometryReader { geometry in
            let totalWidth = geometry.size.width
            let naturalRatio = CGFloat(min(max(metrics.naturalProgressRatio, 0.0), 1.0))
            let amortRatio = CGFloat(min(max(metrics.amortizationAccelerationRatio, 0.0), 1.0))

            let naturalWidth = totalWidth * naturalRatio
            let amortWidth = min(totalWidth * amortRatio, max(0, totalWidth - naturalWidth))

            ZStack(alignment: .leading) {
                // Segment 3: Dívida Restante / Trilho Neutro
                Capsule()
                    .fill(Color.primary.opacity(0.12))

                HStack(spacing: 0) {
                    // Segment 1: Progresso Natural (Pagas no Fluxo)
                    if naturalWidth > 0.001 {
                        Rectangle()
                            .fill(Color(hex: accentHex))
                            .frame(width: naturalWidth)
                    }

                    // Segment 2: Aceleração por Amortização (Conquista Extraordinária)
                    if metrics.eliminatedByAmortizationCount > 0 && amortWidth > 0.001 {
                        Rectangle()
                            .fill(Color(hex: "#10B981"))
                            .frame(width: amortWidth)
                    }
                }
                .clipShape(Capsule())
            }
        }
        .frame(height: 10)
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
    @State private var billingDay: Int = 12
    @State private var bankDueDay: Int = 25
    @State private var totalInstallments: Int = 48
    @State private var interestRateText: String = "1,65"
    @State private var annualNominalRateText: String = "8,51"
    @State private var indexationRate: FinancingIndexation = .tr
    @State private var adminFeeText: String = "25,00"
    @State private var insuranceFeeText: String = "86,27"
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

                    if kind == .financing {
                        Picker("Indexador / Correção Monetária", selection: $indexationRate) {
                            ForEach(FinancingIndexation.allCases) { idx in
                                Text(idx.rawValue).tag(idx)
                            }
                        }
                    }
                }

                Section("Valores (R$), Saldo Devedor, Parcelas e Juros") {
                    HStack(spacing: 12) {
                        BRLCurrencyTextField(
                            label: kind == .loan ? "Valor Financiado / Liberado (PV)" : "Valor Total Contratado (R$)",
                            text: $totalContractedText
                        )

                        BRLCurrencyTextField(
                            label: kind == .loan ? "Saldo Devedor Atual (R$)" : "Saldo Devedor Atual (R$)",
                            text: $outstandingBalanceText
                        )

                        BRLCurrencyTextField(
                            label: kind == .loan ? "Valor Fixo da Parcela (PMT)" : "Valor da Parcela (R$)",
                            text: $installmentAmountText
                        )
                    }

                    HStack(spacing: 14) {
                        EditableIntegerStepperField(
                            label: "Quantidade de Parcelas",
                            value: $totalInstallments,
                            range: 1...600,
                            unitSuffix: "parcelas"
                        )

                        EditableIntegerStepperField(
                            label: "Dia de Cobrança no Salário (Manual)",
                            value: $billingDay,
                            range: 1...31,
                            unitSuffix: "dia"
                        )

                        EditableIntegerStepperField(
                            label: "Dia de Pagamento no Banco (DT.VCTO)",
                            value: $bankDueDay,
                            range: 1...31,
                            unitSuffix: "dia"
                        )
                    }

                    if kind == .loan {
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
                    } else {
                        // Financiamento: Seguros MIP/DFI, Taxa de Adm, Taxa Nominal Anual
                        HStack(spacing: 12) {
                            BorderedTextField(
                                label: "Taxa Nominal Anual (% a.a.)",
                                placeholder: "Ex: 8,51",
                                text: $annualNominalRateText,
                                suffix: "% a.a."
                            )

                            BRLCurrencyTextField(
                                label: "Seguros MIP/DFI (R$)",
                                text: $insuranceFeeText
                            )

                            BRLCurrencyTextField(
                                label: "Taxa Adm Fixa (R$)",
                                text: $adminFeeText
                            )
                        }

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
                            Picker("Conta Padrão para Cobrança", selection: $accountId) {
                                ForEach(store.accounts) { acc in
                                    Text(acc.name).tag(acc.id)
                                }
                            }
                        }

                        // Live Preview da Decomposição da Parcela Caixa (Tabela Price)
                        let instVal = BRLFormatters.parseAmount(installmentAmountText) ?? 0.0
                        let insVal = BRLFormatters.parseAmount(insuranceFeeText) ?? 0.0
                        let admVal = BRLFormatters.parseAmount(adminFeeText) ?? 0.0
                        let basePrice = max(instVal - insVal - admVal, 0.0)
                        let outBal = BRLFormatters.parseAmount(outstandingBalanceText) ?? (BRLFormatters.parseAmount(totalContractedText) ?? 0.0)
                        let annRate = BRLFormatters.parseAmount(annualNominalRateText) ?? 8.51
                        let monthlyRateDec = (annRate / 12.0) / 100.0
                        let monthInterest = outBal * monthlyRateDec
                        let realAmort = max(basePrice - monthInterest, 0.0)

                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Image(systemName: "building.columns.fill")
                                    .foregroundStyle(Color(hex: "#8B5CF6"))
                                Text("Composição CAIXA da Parcela (Tabela Price):")
                                    .font(.caption.bold())
                                    .foregroundStyle(Color(hex: "#8B5CF6"))
                                Spacer()
                                Text(String(format: "Taxa mensal calculada: %.4f%% a.m.", monthlyRateDec * 100.0))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            HStack(spacing: 16) {
                                Text("Base Price (Amort+Juros): \(BRLFormatters.currency(basePrice))")
                                    .font(.caption.weight(.semibold))
                                Text("Seguros: \(BRLFormatters.currency(insVal))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("Taxa Adm: \(BRLFormatters.currency(admVal))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            HStack(spacing: 16) {
                                Text("Juros Mês Atual: \(BRLFormatters.currency(monthInterest))")
                                    .font(.caption)
                                    .foregroundStyle(Color(hex: "#EF4444"))
                                Text("Amortização Real no Saldo: \(BRLFormatters.currency(realAmort))")
                                    .font(.caption.bold())
                                    .foregroundStyle(Color(hex: "#10B981"))
                            }
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: "#8B5CF6").opacity(0.08)))
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
                    let outBal = BRLFormatters.parseAmount(outstandingBalanceText) ?? (kind == .loan ? totalVal : nil)
                    let rateVal = BRLFormatters.parseAmount(interestRateText) ?? 0.0
                    let cleanContractNo = contractNumber.trimmingCharacters(in: .whitespacesAndNewlines)

                    let annNominal = kind == .financing ? (BRLFormatters.parseAmount(annualNominalRateText) ?? 8.51) : nil
                    let idxRate = kind == .financing ? indexationRate : nil
                    let admFee = kind == .financing ? (BRLFormatters.parseAmount(adminFeeText) ?? 25.0) : nil
                    let insFee = kind == .financing ? (BRLFormatters.parseAmount(insuranceFeeText) ?? 86.27) : nil
                    let basePriceAmt = kind == .financing ? max(instVal - (admFee ?? 0.0) - (insFee ?? 0.0), 0.0) : nil
                    let effMonthlyRate = kind == .financing ? ((annNominal ?? 8.51) / 12.0) : rateVal

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
                        monthlyInterestRate: effMonthlyRate,
                        startDate: hasStartDate ? startDate : nil,
                        accountId: accountId,
                        notes: notes,
                        annualNominalInterestRate: annNominal,
                        indexationRate: idxRate,
                        adminFee: admFee,
                        insuranceFee: insFee,
                        baseInstallmentAmount: basePriceAmt,
                        bankDueDay: bankDueDay
                    )
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(kind == .loan ? Color(hex: "#D97706") : Color(hex: "#8B5CF6"))
            }
        }
        .padding(22)
        .frame(width: 680, height: 720)
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
    @State private var billingDay: Int = 12
    @State private var bankDueDay: Int = 25
    @State private var totalInstallments: Int = 36
    @State private var paidInstallmentsCount: Int = 10
    @State private var interestRateText: String = "2,0087"
    @State private var annualNominalRateText: String = "8,51"
    @State private var indexationRate: FinancingIndexation = .tr
    @State private var adminFeeText: String = "25,00"
    @State private var insuranceFeeText: String = "86,27"
    @State private var baseInstallmentAmountText: String = ""
    @State private var startDate: Date = Date()
    @State private var referenceDate: Date = Date()
    @State private var maturityDate: Date? = nil
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
                                label: "Dia Pagto. no Banco (Extraído do PDF)",
                                value: $bankDueDay,
                                range: 1...31,
                                unitSuffix: "dia"
                            )

                            EditableIntegerStepperField(
                                label: "Dia de Cobrança no Salário (Manual)",
                                value: $billingDay,
                                range: 1...31,
                                unitSuffix: "dia"
                            )
                            .onChange(of: billingDay) { _, newDay in
                                var comps = store.calendar.dateComponents([.year, .month], from: firstFutureBillingDate)
                                comps.day = min(max(newDay, 1), 28)
                                if let updated = store.calendar.date(from: comps) {
                                    firstFutureBillingDate = updated
                                }
                            }
                        }

                        // Callout explicando a diferença entre o Dia de Pagamento no Banco (PDF) e o Dia de Cobrança no Salário (Manual)
                        HStack(spacing: 8) {
                            Image(systemName: "info.circle.fill")
                                .foregroundStyle(Color(hex: "#6366F1"))
                            Text("O Dia de Pagamento no Banco (dia \(bankDueDay), extraído do documento) é a data em que o banco recebe a liquidação e serve de base para o cálculo matemático de amortização. Insira manualmente o Dia de Cobrança no Salário (dia \(billingDay)) em que você recebe o desconto na folha/conta.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: "#6366F1").opacity(0.08)))

                        HStack(spacing: 14) {
                            if kind == .financing {
                                BorderedTextField(
                                    label: "Taxa Nominal Anual (% a.a.)",
                                    placeholder: "Ex: 8,51",
                                    text: $annualNominalRateText,
                                    suffix: "% a.a."
                                )
                                .frame(width: 180)

                                Picker("Indexador", selection: $indexationRate) {
                                    ForEach(FinancingIndexation.allCases) { idx in
                                        Text(idx.rawValue).tag(idx)
                                    }
                                }
                                .frame(width: 140)
                            } else {
                                BorderedTextField(
                                    label: "Taxa de Juros (% a.m.)",
                                    placeholder: "Ex: 2,0087",
                                    text: $interestRateText,
                                    suffix: "% a.m."
                                )
                                .frame(width: 180)
                            }

                            DatePicker("Data em que foi feito", selection: $startDate, displayedComponents: [.date])

                            DatePicker("Próximo Vencimento Futuro", selection: $firstFutureBillingDate, displayedComponents: [.date])
                        }

                        if kind == .financing {
                            HStack(spacing: 12) {
                                BRLCurrencyTextField(
                                    label: "Parcela Base Price (Amort+Juros)",
                                    text: $baseInstallmentAmountText
                                )

                                BRLCurrencyTextField(
                                    label: "Seguros MIP/DFI (R$)",
                                    text: $insuranceFeeText
                                )

                                BRLCurrencyTextField(
                                    label: "Taxa Adm Fixa (R$)",
                                    text: $adminFeeText
                                )
                            }
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
        bankDueDay = doc.bankDueDay
        billingDay = doc.billingDay
        totalInstallments = doc.totalInstallments
        paidInstallmentsCount = doc.paidInstallmentsCount
        interestRateText = String(format: "%.4f", doc.monthlyInterestRate).replacingOccurrences(of: ".", with: ",")
        if let ann = doc.annualNominalInterestRate {
            annualNominalRateText = String(format: "%.2f", ann).replacingOccurrences(of: ".", with: ",")
        }
        if let idx = doc.indexationRate {
            indexationRate = idx
        }
        if let adm = doc.adminFee {
            adminFeeText = BRLFormatters.currency(adm)
        }
        if let ins = doc.insuranceFee {
            insuranceFeeText = BRLFormatters.currency(ins)
        }
        if let bp = doc.baseInstallmentAmount {
            baseInstallmentAmountText = BRLFormatters.currency(bp)
        }
        startDate = doc.startDate
        referenceDate = doc.referenceDate ?? doc.documentEmissionDate ?? Date()
        maturityDate = doc.maturityDate
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

        let annNominal = kind == .financing ? (BRLFormatters.parseAmount(annualNominalRateText) ?? 8.51) : nil
        let idxRate = kind == .financing ? indexationRate : nil
        let admFee = kind == .financing ? (BRLFormatters.parseAmount(adminFeeText) ?? 25.0) : nil
        let insFee = kind == .financing ? (BRLFormatters.parseAmount(insuranceFeeText) ?? 86.27) : nil
        let basePriceAmt = kind == .financing ? (BRLFormatters.parseAmount(baseInstallmentAmountText) ?? max(instVal - (admFee ?? 0.0) - (insFee ?? 0.0), 0.0)) : nil
        let effMonthlyRate = kind == .financing ? ((annNominal ?? 8.51) / 12.0) : rateVal

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
            monthlyInterestRate: effMonthlyRate,
            startDate: startDate,
            accountId: selectedAccountId,
            notes: notes,
            overridePastInstallmentsCount: paidInstallmentsCount,
            overrideFirstFutureBillingDate: firstFutureBillingDate,
            annualNominalInterestRate: annNominal,
            indexationRate: idxRate,
            adminFee: admFee,
            insuranceFee: insFee,
            baseInstallmentAmount: basePriceAmt,
            bankDueDay: bankDueDay,
            documentReferenceDate: referenceDate,
            maturityDate: maturityDate
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
    @State private var proRataInterestText: String = ""
    @State private var selectedAccountId: UUID = UUID()
    @State private var date: Date = Date()
    @State private var mode: AmortizationRecalculationMode = .reduceTerm
    @State private var newInstallmentAmountText: String = ""
    @State private var newRemainingInstallments: Int = 1
    @State private var notes: String = ""
    @State private var errorMsg: String? = nil
    @State private var simulationResult: ExtraAmortizationSimulationResult? = nil

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

                    BorderedTextField(
                        label: "Juros diários (Mora / Encargo pró-rata)",
                        placeholder: "Ex: 0,00 ou conforme simulação da CAIXA",
                        text: $proRataInterestText,
                        suffix: "R$"
                    )
                    .onChange(of: proRataInterestText) { _, _ in
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
                    .disabled(isSettlingFullDebt)

                    if isSettlingFullDebt {
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.title2)
                                .foregroundStyle(Color(hex: "#10B981"))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Quitação Total do Contrato")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(Color(hex: "#10B981"))
                                Text("O valor amortizado cobre integralmente a dívida. Todas as parcelas futuras serão eliminadas e o contrato será liquidado.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: "#10B981").opacity(0.12)))
                    }

                    HStack(spacing: 14) {
                        EditableIntegerStepperField(
                            label: "Nova Qtd. de Parcelas Restantes",
                            value: $newRemainingInstallments,
                            range: 0...max(currentRemaining, 1),
                            unitSuffix: "parcelas"
                        )
                        .disabled(isSettlingFullDebt)

                        BRLCurrencyTextField(
                            label: "Novo Valor da Parcela (R$)",
                            text: $newInstallmentAmountText
                        )
                        .disabled(isSettlingFullDebt)
                    }

                    BorderedTextField(
                        label: "Observações (Opcional)",
                        placeholder: "Ex: Amortização extraordinária FGTS / 13º salário",
                        text: $notes
                    )
                }

                if let sim = simulationResult, (BRLFormatters.parseAmount(amountPaidText) ?? 0) > 0 {
                    Section("Simulação Matemática (Padrão CAIXA / Tabela Price)") {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Valor Pago Bruto:")
                                Spacer()
                                Text(BRLFormatters.currency(sim.grossPayment))
                                    .monospacedDigit()
                            }
                            if sim.proRataInterest > 0 {
                                HStack {
                                    Text("(-) Juros pró-rata deduzidos:")
                                        .foregroundStyle(Color(hex: "#EF4444"))
                                    Spacer()
                                    Text("- " + BRLFormatters.currency(sim.proRataInterest))
                                        .foregroundStyle(Color(hex: "#EF4444"))
                                        .monospacedDigit()
                                }
                            }
                            HStack {
                                Text("(=) Amortização Efetiva no Saldo:")
                                    .fontWeight(.semibold)
                                Spacer()
                                Text(BRLFormatters.currency(sim.effectiveAmortization))
                                    .fontWeight(.bold)
                                    .foregroundStyle(Color(hex: "#10B981"))
                                    .monospacedDigit()
                            }
                            Divider()
                            HStack {
                                Text("Novo Saldo Devedor:")
                                Spacer()
                                Text(sim.newBalance <= 0.01 ? "QUITADO (R$ 0,00)" : BRLFormatters.currency(sim.newBalance))
                                    .fontWeight(.bold)
                                    .foregroundStyle(sim.newBalance <= 0.01 ? Color(hex: "#10B981") : .primary)
                                    .monospacedDigit()
                            }
                            if mode == .reduceTerm {
                                HStack {
                                    Text("Novo Prazo:")
                                    Spacer()
                                    if sim.newRemainingInstallments == 0 {
                                        Text("0 parcelas (Contrato Quitado!)")
                                            .fontWeight(.bold)
                                            .foregroundStyle(Color(hex: "#10B981"))
                                    } else {
                                        Text("\(sim.newRemainingInstallments) parcelas (eliminou \(sim.eliminatedInstallmentsCount) parcelas!)")
                                            .fontWeight(.semibold)
                                            .foregroundStyle(Color(hex: "#10B981"))
                                    }
                                }
                            } else {
                                HStack {
                                    Text("Nova Parcela:")
                                    Spacer()
                                    Text(BRLFormatters.currency(sim.newInstallmentAmount))
                                        .fontWeight(.semibold)
                                        .foregroundStyle(Color(hex: "#10B981"))
                                }
                            }
                            HStack {
                                Text("Economia Estimada de Juros:")
                                Spacer()
                                Text(BRLFormatters.currency(sim.estimatedTotalInterestSaved))
                                    .fontWeight(.bold)
                                    .foregroundStyle(Color(hex: "#3B82F6"))
                                    .monospacedDigit()
                            }
                        }
                        .font(.caption)
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.03)))
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
                Button(isSettlingFullDebt ? "Confirmar Quitação Total" : "Confirmar Amortização e Recalcular") {
                    guard let paidVal = BRLFormatters.parseAmount(amountPaidText), paidVal > 0 else {
                        errorMsg = "Informe um valor amortizado válido maior que zero."
                        return
                    }
                    let proRata = BRLFormatters.parseAmount(proRataInterestText) ?? 0.0
                    let customInst = isSettlingFullDebt ? 0.0 : BRLFormatters.parseAmount(newInstallmentAmountText)
                    let customCount = isSettlingFullDebt ? 0 : newRemainingInstallments
                    store.amortizeContract(
                        contractId: contract.id,
                        amountPaid: paidVal,
                        accountId: selectedAccountId,
                        date: date,
                        mode: mode,
                        proRataInterest: proRata,
                        customNewInstallmentAmount: customInst,
                        customNewRemainingInstallments: customCount,
                        notes: notes
                    )
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(isSettlingFullDebt ? Color(hex: "#10B981") : Color(hex: "#D97706"))
            }
        }
        .padding(22)
        .frame(width: 580, height: 680)
        .onAppear {
            selectedAccountId = contract.accountId
            newRemainingInstallments = max(store.remainingInstallmentsCount(for: contract), 1)
            newInstallmentAmountText = BRLFormatters.currency(contract.installmentAmount)
        }
    }

    private var isSettlingFullDebt: Bool {
        guard let paid = BRLFormatters.parseAmount(amountPaidText), paid > 0 else { return false }
        let currentPV = store.currentOutstandingBalance(for: contract)
        return paid >= (currentPV - 0.01) || (simulationResult?.newBalance ?? 1.0) <= 0.01
    }

    private func recalculatePreview() {
        guard let paid = BRLFormatters.parseAmount(amountPaidText), paid > 0 else {
            simulationResult = nil
            return
        }
        let proRata = BRLFormatters.parseAmount(proRataInterestText) ?? 0.0
        let prevRem = store.remainingInstallmentsCount(for: contract)
        let currentPV = store.currentOutstandingBalance(for: contract)

        if contract.kind == .loan {
            let sim = LoanAmortizationEngine.simulateExtraAmortization(
                currentBalance: currentPV,
                monthlyInterestRate: contract.monthlyInterestRate,
                installmentValue: contract.installmentAmount,
                currentRemainingInstallments: prevRem,
                extraPayment: paid,
                proRataInterest: proRata,
                mode: mode
            )
            let result = ExtraAmortizationSimulationResult(
                grossPayment: sim.grossPayment,
                proRataInterest: sim.proRataInterest,
                effectiveAmortization: sim.effectiveAmortization,
                previousBalance: sim.previousBalance,
                newBalance: sim.newBalance,
                previousRemainingInstallments: sim.previousRemainingInstallments,
                newRemainingInstallments: sim.newRemainingInstallments,
                eliminatedInstallmentsCount: sim.eliminatedInstallmentsCount,
                previousInstallmentAmount: sim.previousInstallmentAmount,
                newInstallmentAmount: sim.newInstallmentAmount,
                basePriceInstallment: sim.newInstallmentAmount,
                estimatedTotalInterestSaved: sim.estimatedTotalInterestSaved,
                mode: sim.mode
            )
            simulationResult = result
            if paid >= (currentPV - 0.01) || sim.newBalance <= 0.01 {
                newRemainingInstallments = 0
                newInstallmentAmountText = BRLFormatters.currency(0.0)
            } else {
                newRemainingInstallments = sim.newRemainingInstallments
                newInstallmentAmountText = BRLFormatters.currency(sim.newInstallmentAmount)
            }
        } else {
            let sim = AmortizationEngine.simulateExtraAmortization(
                currentBalance: currentPV,
                annualNominalRate: contract.effectiveAnnualNominalRate,
                basePriceInstallment: contract.effectiveBaseInstallmentPrice,
                totalInstallmentAmount: contract.installmentAmount,
                currentRemainingInstallments: prevRem,
                extraPayment: paid,
                proRataInterest: proRata,
                mode: mode,
                adminFee: contract.effectiveAdminFee,
                insuranceFee: contract.effectiveInsuranceFee
            )
            simulationResult = sim
            if paid >= (currentPV - 0.01) || sim.newBalance <= 0.01 {
                newRemainingInstallments = 0
                newInstallmentAmountText = BRLFormatters.currency(0.0)
            } else {
                newRemainingInstallments = sim.newRemainingInstallments
                newInstallmentAmountText = BRLFormatters.currency(sim.newInstallmentAmount)
            }
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
            // Sugere automaticamente o Saldo Devedor Atual (Valor Presente)
            let suggestedPayoff = (outstandingBalance > 0.01) ? outstandingBalance : (projectedPayoff > 0.01 ? projectedPayoff : nominalRemaining)
            finalPayoffAmountText = BRLFormatters.currency(suggestedPayoff)
        }
    }
}

// MARK: - Banner Não-Destrutivo de Resolução Assistida de Aportes Vencidos (Camada 2 -> .expired)

public struct ExpiredAmortizationResolutionBanner: View {
    @ObservedObject public var store: FinancialDataStore
    public let contract: CreditContract
    public let expiredItem: PlannedAmortization

    @State private var showReschedulePopover: Bool = false
    @State private var newScheduledDate: Date = Date()

    public init(store: FinancialDataStore, contract: CreditContract, expiredItem: PlannedAmortization) {
        self.store = store
        self.contract = contract
        self.expiredItem = expiredItem
    }

    public var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "clock.badge.exclamationmark.fill")
                .font(.title3)
                .foregroundStyle(Color(hex: "#F59E0B"))

            VStack(alignment: .leading, spacing: 3) {
                Text("A amortização de \(BRLFormatters.currency(expiredItem.amountDouble)) prevista para \(BRLFormatters.shortDate(expiredItem.date)) não foi confirmada.")
                    .font(.caption.bold())
                    .foregroundStyle(.primary)
                Text("O orçamento foi recalculado automaticamente sem ela (parcelas suprimidas voltaram ao fluxo ativo).")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 8) {
                Button {
                    store.confirmPlannedAmortizationPayment(
                        contractId: contract.id,
                        itemId: expiredItem.id,
                        accountId: contract.accountId,
                        paymentDate: expiredItem.date
                    )
                } label: {
                    Text("Confirmar que paguei")
                        .font(.caption2.bold())
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(hex: "#10B981"))
                .controlSize(.small)

                Button {
                    newScheduledDate = store.calendar.date(byAdding: .day, value: 7, to: store.effectiveCurrentDate) ?? Date()
                    showReschedulePopover = true
                } label: {
                    Text("Reagendar data")
                        .font(.caption2.bold())
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .popover(isPresented: $showReschedulePopover) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Reagendar Amortização")
                            .font(.headline)
                        DatePicker("Nova data futura:", selection: $newScheduledDate, in: store.effectiveCurrentDate..., displayedComponents: [.date])
                        HStack {
                            Button("Cancelar") {
                                showReschedulePopover = false
                            }
                            Spacer()
                            Button("Confirmar Nova Data") {
                                store.rescheduleExpiredAmortization(
                                    contractId: contract.id,
                                    itemId: expiredItem.id,
                                    newDate: newScheduledDate
                                )
                                showReschedulePopover = false
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(14)
                    .frame(width: 300)
                }

                Button(role: .destructive) {
                    store.skipExpiredAmortization(contractId: contract.id, itemId: expiredItem.id)
                } label: {
                    Text("Descartar")
                        .font(.caption2)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(hex: "#F59E0B").opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color(hex: "#F59E0B").opacity(0.35), lineWidth: 1)
        )
    }
}

// MARK: - Modal de Planejamento Dinâmico de Amortização (Manual & Automático — Camadas 2 e 3)

public struct AmortizationPlannerSheet: View {
    @ObservedObject public var store: FinancialDataStore
    @Environment(\.dismiss) private var dismiss

    public let contract: CreditContract

    private enum PlannerDetailTab: String, CaseIterable, Identifiable {
        case plannedItems = "Aportes Planejados (Editor Dinâmico)"
        case fullTimeline = "Evolução Mês a Mês (Timeline Completa)"
        var id: String { rawValue }
    }

    @State private var selectedMode: AmortizationPlanGenerationMode = .manual
    @State private var selectedDetailTab: PlannerDetailTab = .plannedItems

    // Campos do Modo Manual
    @State private var manualDate: Date = Date()
    @State private var manualAmountText: String = ""
    @State private var manualSource: AmortizationFundingSource = .cash
    @State private var manualRecalcMode: AmortizationRecalculationMode = .reduceTerm
    @State private var manualNotes: String = ""

    // Campos do Modo Automático (% da Renda / Dinheiro Previsto ao Final do Mês)
    @State private var autoBillingDay: Int = 26
    @State private var autoCommitmentPercentage: Double = 30.0
    @State private var autoRecalcMode: AmortizationRecalculationMode = .reduceTerm
    @State private var customMonthlySurplusOverrideText: String = ""

    // Configuração de TR Mensal Estimada (Caixa Habitação)
    @State private var estimatedMonthlyTRText: String = "0,00"
    @State private var errorMsg: String? = nil

    public init(store: FinancialDataStore, contract: CreditContract) {
        self.store = store
        self.contract = contract
    }

    private var liveContract: CreditContract {
        store.contracts.first(where: { $0.id == contract.id }) ?? contract
    }

    public var body: some View {
        let currentContract = liveContract
        let plan = store.amortizationPlan(for: currentContract.id)
        let projection = store.loanProjection(for: currentContract.id)
        let pendingItems = (plan?.items ?? []).filter { $0.status == .pending }.sorted { $0.date < $1.date }
        let expiredItems = store.expiredPlannedAmortizations(for: currentContract.id)
        let detectedMonthlySurplusDec = store.projectedAvailableMonthlySurplusForAmortization(
            in: store.selectedMonth,
            excludingContractId: currentContract.id
        )
        let detectedMonthlySurplusDouble = LoanProjectionEngine.toDouble(detectedMonthlySurplusDec)
        let effectiveBaseSurplusDouble: Double = {
            if let custom = BRLFormatters.parseAmount(customMonthlySurplusOverrideText), custom > 0 {
                return custom
            }
            return detectedMonthlySurplusDouble
        }()
        let autoMonthlyContributionPreview = effectiveBaseSurplusDouble * (autoCommitmentPercentage / 100.0)

        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: "wand.and.stars")
                            .foregroundStyle(Color(hex: "#6366F1"))
                        Text("Planejamento Dinâmico de Amortização: \(currentContract.name)")
                            .font(.title2.bold())
                    }
                    HStack(spacing: 12) {
                        Text("\(currentContract.amortizationSystem.rawValue)")
                        Text("•")
                        Text("Cobrança no Salário: dia \(currentContract.billingDay)")
                        Text("•")
                        Text("Pagamento no Banco: dia \(currentContract.effectiveBankDueDay)")
                        if currentContract.kind == .loan {
                            Text("•")
                            Text(String(format: "Taxa Efetiva: %.4f%% a.m.", currentContract.monthlyInterestRate))
                        } else {
                            Text("•")
                            Text(String(format: "Taxa Nominal: %.2f%% a.a. + %@", currentContract.effectiveAnnualNominalRate, currentContract.indexationRate?.shortLabel ?? "TR"))
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                if currentContract.kind == .financing && (currentContract.indexationRate ?? .tr) == .tr {
                    HStack(spacing: 6) {
                        Text("TR Mensal Est. (%):")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        TextField("0,00", text: $estimatedMonthlyTRText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 70)
                            .onSubmit {
                                applyTRUpdate()
                            }
                        Button("Aplicar TR") {
                            applyTRUpdate()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }

                Picker("Cenário Orçamentário", selection: $store.budgetProjectionScenario) {
                    ForEach(BudgetProjectionScenario.allCases) { sc in
                        Text(sc.rawValue).tag(sc)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
            }

            // Alerta Operacional de Folha de Pagamento (Santander Consignado)
            if let payrollTip = projection?.payrollOperationalTip {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(Color(hex: "#D97706"))
                    Text(payrollTip)
                        .font(.caption)
                        .foregroundStyle(.primary)
                    Spacer()
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: "#D97706").opacity(0.10)))
            }

            // Alertas Legais do FGTS (Interstício de 24 meses para parcial)
            if let fgtsWarnings = projection?.fgtsWarnings, !fgtsWarnings.isEmpty {
                ForEach(fgtsWarnings, id: \.self) { warning in
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Color(hex: "#EF4444"))
                        Text(warning)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color(hex: "#EF4444"))
                        Spacer()
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: "#EF4444").opacity(0.10)))
                }
            }

            // Banners de Resolução de Aportes Expirados
            if !expiredItems.isEmpty {
                ForEach(expiredItems) { expItem in
                    ExpiredAmortizationResolutionBanner(
                        store: store,
                        contract: currentContract,
                        expiredItem: expItem
                    )
                }
            }

            // 4 Cards de Resumo da Projeção (Decimal Puro)
            if let proj = projection {
                Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                    GridRow {
                        MetricCardView(
                            title: "Saldo Devedor → Pós-Amortizações",
                            value: "\(BRLFormatters.currency(LoanProjectionEngine.toDouble(proj.currentRealBalance))) → \(BRLFormatters.currency(LoanProjectionEngine.toDouble(proj.projectedFinalBalanceAfterPlan)))",
                            subtitle: "Total extra planejado: \(BRLFormatters.currency(LoanProjectionEngine.toDouble(proj.totalExtraAmortized)))",
                            icon: "scalemass.fill",
                            tint: Color(hex: "#6366F1")
                        )
                        .frame(maxWidth: .infinity)

                        MetricCardView(
                            title: "Término Original vs. Projetado",
                            value: "\(BRLFormatters.shortDate(proj.originalMaturityDate)) → \(BRLFormatters.shortDate(proj.projectedMaturityDate))",
                            subtitle: "De \(proj.originalRemainingMonths) para \(proj.projectedActiveMonths) parcelas ativas",
                            icon: "calendar.badge.checkmark",
                            tint: Color(hex: "#10B981")
                        )
                        .frame(maxWidth: .infinity)

                        MetricCardView(
                            title: "Prazo Economizado (Shadowing)",
                            value: "\(proj.monthsSaved) m\(proj.monthsSaved == 1 ? "ês" : "eses") economizado\(proj.monthsSaved == 1 ? "" : "s")",
                            subtitle: "\(proj.shadowedInstallmentTransactionIds.count) parcelas suprimidas (R$ 0 no orçamento)",
                            icon: "bolt.circle.fill",
                            tint: Color(hex: "#D97706")
                        )
                        .frame(maxWidth: .infinity)

                        MetricCardView(
                            title: "Total de Juros Economizados",
                            value: BRLFormatters.currency(LoanProjectionEngine.toDouble(proj.totalInterestSaved)),
                            subtitle: "Originais: \(BRLFormatters.currency(LoanProjectionEngine.toDouble(proj.originalTotalInterest))) • Projetados: \(BRLFormatters.currency(LoanProjectionEngine.toDouble(proj.projectedTotalInterest)))",
                            icon: "sparkles.rectangle.stack.fill",
                            tint: Color(hex: "#3B82F6")
                        )
                        .frame(maxWidth: .infinity)
                    }
                }
            }

            // Seletor de Modo de Planejamento: Manual vs Automático
            HStack(spacing: 16) {
                Picker("Modo de Simulação", selection: $selectedMode) {
                    ForEach(AmortizationPlanGenerationMode.allCases) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 360)

                Spacer()

                Picker("Visualização", selection: $selectedDetailTab) {
                    ForEach(PlannerDetailTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 440)
            }

            // Painel de Entrada (Manual ou Automático)
            if selectedMode == .manual {
                manualInputPanel(currentContract: currentContract, projection: projection)
            } else {
                automaticInputPanel(
                    currentContract: currentContract,
                    detectedMonthlySurplusDouble: detectedMonthlySurplusDouble,
                    effectiveBaseSurplusDouble: effectiveBaseSurplusDouble,
                    autoMonthlyContributionPreview: autoMonthlyContributionPreview
                )
            }

            if let errorMsg {
                Text(errorMsg)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            // Conteúdo Principal: Lista Dinâmica de Aportes Planejados OU Linha do Tempo Completa Mês a Mês
            if selectedDetailTab == .plannedItems {
                plannedItemsListSection(
                    currentContract: currentContract,
                    pendingItems: pendingItems,
                    projection: projection
                )
            } else {
                fullTimelineTableSection(projection: projection)
            }

            // Rodapé
            HStack {
                if !pendingItems.isEmpty || !(plan?.items.isEmpty ?? true) {
                    Button(role: .destructive) {
                        store.deleteAmortizationPlan(for: currentContract.id)
                    } label: {
                        Label("Excluir Planejamento", systemImage: "trash.fill")
                    }
                    .buttonStyle(.bordered)
                }

                Spacer()

                Button("Fechar") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 1020, height: 760)
        .onAppear {
            let current = liveContract
            let existingPlan = store.amortizationPlan(for: current.id)
            selectedMode = existingPlan?.generationMode ?? .manual
            let bestDay = current.effectiveBankDueDay >= 28 ? 1 : (current.effectiveBankDueDay + 1)
            autoBillingDay = existingPlan?.billingDay ?? (current.kind == .loan ? bestDay : current.billingDay)
            autoCommitmentPercentage = existingPlan.map { LoanProjectionEngine.toDouble($0.incomeCommitmentPercentage) } ?? 30.0
            autoRecalcMode = existingPlan?.defaultRecalculationMode ?? .reduceTerm
            manualRecalcMode = existingPlan?.defaultRecalculationMode ?? .reduceTerm
            let trVal = existingPlan.map { LoanProjectionEngine.toDouble($0.estimatedMonthlyTR) } ?? (current.estimatedMonthlyTR ?? 0.0)
            estimatedMonthlyTRText = String(format: "%.2f", trVal).replacingOccurrences(of: ".", with: ",")

            // Sugere próxima data de amortização após o último item planejado (ou mês atual no melhor dia)
            if let lastItem = existingPlan?.items.filter({ $0.status == .pending }).sorted(by: { $0.date < $1.date }).last,
               let nextMonth = store.calendar.date(byAdding: .month, value: 1, to: lastItem.date) {
                manualDate = nextMonth
            } else {
                var comps = store.calendar.dateComponents([.year, .month], from: store.effectiveCurrentDate)
                comps.day = min(max(autoBillingDay, 1), 28)
                manualDate = store.calendar.date(from: comps) ?? store.effectiveCurrentDate
            }
        }
    }

    private func applyTRUpdate() {
        let tr = BRLFormatters.parseAmount(estimatedMonthlyTRText) ?? 0.0
        store.updateAmortizationPlanParameters(
            contractId: contract.id,
            estimatedMonthlyTR: LoanProjectionEngine.toDecimal(tr)
        )
    }

    @ViewBuilder
    private func manualInputPanel(currentContract: CreditContract, projection: LoanProjectionResult?) -> some View {
        let remainingAfterCurrentPlan = LoanProjectionEngine.toDouble(projection?.projectedFinalBalanceAfterPlan ?? LoanProjectionEngine.toDecimal(store.currentOutstandingBalance(for: currentContract)))

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Adicionar Amortização Manual ao Planejamento", systemImage: "plus.circle.fill")
                    .font(.subheadline.bold())
                    .foregroundStyle(Color(hex: "#6366F1"))
                Spacer()
                Text("Saldo planejado de referência atual: \(BRLFormatters.currency(remainingAfterCurrentPlan))")
                    .font(.caption.bold())
                    .foregroundStyle(remainingAfterCurrentPlan <= 0.01 ? Color(hex: "#10B981") : Color(hex: "#EF4444"))
                if remainingAfterCurrentPlan > 0.01 {
                    Button("Preencher Saldo Restante (\(BRLFormatters.currency(remainingAfterCurrentPlan)))") {
                        manualAmountText = BRLFormatters.currency(remainingAfterCurrentPlan)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
            }

            HStack(spacing: 12) {
                DatePicker("Data:", selection: $manualDate, displayedComponents: [.date])
                    .frame(width: 175)

                BRLCurrencyTextField(
                    label: "Valor da Amortização (R$)",
                    text: $manualAmountText
                )
                .frame(width: 200)

                if currentContract.kind == .financing {
                    Picker("Recurso", selection: $manualSource) {
                        ForEach(AmortizationFundingSource.allCases) { src in
                            Text(src.shortTitle).tag(src)
                        }
                    }
                    .frame(width: 165)

                    Picker("Efeito", selection: $manualRecalcMode) {
                        ForEach(AmortizationRecalculationMode.allCases) { m in
                            Text(m == .reduceTerm ? "Reduzir Prazo" : "Reduzir Parcela").tag(m)
                        }
                    }
                    .frame(width: 185)
                } else {
                    Text("Efeito: Reduzir Prazo (Consignado mantém parcela fixa)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    guard let val = BRLFormatters.parseAmount(manualAmountText), val > 0 else {
                        errorMsg = "Informe um valor de amortização válido maior que zero."
                        return
                    }
                    errorMsg = nil
                    store.addPlannedAmortization(
                        contractId: currentContract.id,
                        date: manualDate,
                        amount: LoanProjectionEngine.toDecimal(val),
                        source: currentContract.kind == .loan ? .cash : manualSource,
                        mode: currentContract.kind == .loan ? .reduceTerm : manualRecalcMode,
                        notes: manualNotes
                    )
                    manualAmountText = ""
                    if let nextDate = store.calendar.date(byAdding: .month, value: 1, to: manualDate) {
                        manualDate = nextDate
                    }
                } label: {
                    Label("Adicionar ao Plano", systemImage: "plus")
                        .fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(hex: "#6366F1"))
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
    }

    @ViewBuilder
    private func automaticInputPanel(
        currentContract: CreditContract,
        detectedMonthlySurplusDouble: Double,
        effectiveBaseSurplusDouble: Double,
        autoMonthlyContributionPreview: Double
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Gerador Automático por Comprometimento de Renda / Sobra Prevista no Fim do Mês", systemImage: "wand.and.stars.inverse")
                    .font(.subheadline.bold())
                    .foregroundStyle(Color(hex: "#10B981"))
                Spacer()
                Text("Dinheiro previsto ao final do mês: \(BRLFormatters.currency(detectedMonthlySurplusDouble)) • Aporte mensal (\(Int(autoCommitmentPercentage))%): \(BRLFormatters.currency(autoMonthlyContributionPreview))")
                    .font(.caption.bold())
                    .foregroundStyle(Color(hex: "#10B981"))
            }

            HStack(spacing: 14) {
                EditableIntegerStepperField(
                    label: "Dia de Cobrança / Amortização",
                    value: $autoBillingDay,
                    range: 1...31,
                    unitSuffix: "dia"
                )
                .frame(width: 210)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Comprometer da Renda/Sobra: \(Int(autoCommitmentPercentage))%")
                        .font(.caption.weight(.semibold))
                    Slider(value: $autoCommitmentPercentage, in: 5...100, step: 5)
                        .frame(width: 180)
                }

                BRLCurrencyTextField(
                    label: "Sobra Prevista Base (Opcional)",
                    text: $customMonthlySurplusOverrideText
                )
                .frame(width: 190)

                if currentContract.kind == .financing {
                    Picker("Modalidade", selection: $autoRecalcMode) {
                        ForEach(AmortizationRecalculationMode.allCases) { m in
                            Text(m == .reduceTerm ? "Reduzir Prazo" : "Reduzir Parcela").tag(m)
                        }
                    }
                    .frame(width: 180)
                }

                Spacer()

                Button {
                    guard effectiveBaseSurplusDouble > 10.0 else {
                        errorMsg = "O saldo previsto ao final do mês é insuficiente. Informe uma receita no mês ou defina o valor no campo 'Sobra Prevista Base'."
                        return
                    }
                    errorMsg = nil
                    let customFallbackDec = customMonthlySurplusOverrideText.isEmpty
                        ? nil
                        : LoanProjectionEngine.toDecimal(effectiveBaseSurplusDouble)
                    store.generateAutomaticAmortizationPlan(
                        contractId: currentContract.id,
                        billingDay: autoBillingDay,
                        incomeCommitmentPercentage: Decimal(Int(autoCommitmentPercentage)),
                        mode: currentContract.kind == .loan ? .reduceTerm : autoRecalcMode,
                        fallbackMonthlyBaseSurplus: customFallbackDec
                    )
                } label: {
                    Label("Gerar Planejamento Automático", systemImage: "sparkles")
                        .fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(hex: "#10B981"))
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
    }

    @ViewBuilder
    private func plannedItemsListSection(
        currentContract: CreditContract,
        pendingItems: [PlannedAmortization],
        projection: LoanProjectionResult?
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Cronograma de Amortizações Planejadas (\(pendingItems.count) item(ns))")
                    .font(.subheadline.bold())
                Spacer()
                Text("Altere qualquer data ou valor na lista abaixo para recalcular instantaneamente o saldo restante e o orçamento")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if pendingItems.isEmpty {
                VStack(spacing: 10) {
                    Spacer()
                    Image(systemName: "calendar.badge.plus")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    Text("Nenhuma amortização futura planejada ainda")
                        .font(.headline)
                    Text("Adicione aportes manualmente acima ou use o modo Automático (% do dinheiro previsto ao final do mês) para gerar o plano até a quitação.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 520)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(Array(pendingItems.enumerated()), id: \.element.id) { index, item in
                            PlannedAmortizationEditableRow(
                                store: store,
                                contract: currentContract,
                                index: index + 1,
                                item: item,
                                outcome: projection?.plannedItemOutcomes[item.id]
                            )
                        }
                    }
                    .padding(10)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
            }
        }
    }

    @ViewBuilder
    private func fullTimelineTableSection(projection: LoanProjectionResult?) -> some View {
        let rows = projection?.timeline ?? []
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Linha do Tempo Cronológica Orientada a Eventos (\(rows.count) eventos)")
                    .font(.subheadline.bold())
                Spacer()
                HStack(spacing: 14) {
                    HStack(spacing: 4) {
                        Circle().fill(Color(hex: "#3B82F6")).frame(width: 8, height: 8)
                        Text("Parcela Ativa").font(.caption2)
                    }
                    HStack(spacing: 4) {
                        Circle().fill(Color(hex: "#6366F1")).frame(width: 8, height: 8)
                        Text("Amortização Planejada").font(.caption2)
                    }
                    HStack(spacing: 4) {
                        Circle().fill(Color.secondary.opacity(0.5)).frame(width: 8, height: 8)
                        Text("Parcela Suprimida (.shadowed = R$ 0)").font(.caption2)
                    }
                }
            }

            // Cabeçalho da Tabela
            HStack(spacing: 8) {
                Text("Data").frame(width: 78, alignment: .leading)
                Text("Evento / Parcela").frame(maxWidth: .infinity, alignment: .leading)
                Text("Saldo Inicial").frame(width: 95, alignment: .trailing)
                Text("Corr./TR").frame(width: 70, alignment: .trailing)
                Text("Juros").frame(width: 85, alignment: .trailing)
                Text("Amort. Normal").frame(width: 95, alignment: .trailing)
                Text("Amort. Extra").frame(width: 95, alignment: .trailing)
                Text("Saldo Final").frame(width: 95, alignment: .trailing)
                Text("Status").frame(width: 135, alignment: .trailing)
            }
            .font(.caption2.bold())
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.05))
            .cornerRadius(6)

            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(rows) { row in
                        let isShadowed = row.status == .shadowed
                        let isExtra = row.status == .pendingAmortization
                        HStack(spacing: 8) {
                            Text(BRLFormatters.shortDate(row.date))
                                .frame(width: 78, alignment: .leading)
                            Text(row.title)
                                .lineLimit(1)
                                .strikethrough(isShadowed)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(BRLFormatters.currency(LoanProjectionEngine.toDouble(row.initialBalance)))
                                .frame(width: 95, alignment: .trailing)
                            Text(BRLFormatters.currency(LoanProjectionEngine.toDouble(row.trCorrection)))
                                .frame(width: 70, alignment: .trailing)
                            Text(BRLFormatters.currency(LoanProjectionEngine.toDouble(row.interestAmount)))
                                .foregroundStyle(row.interestAmount > .zero ? Color(hex: "#EF4444") : .secondary)
                                .frame(width: 85, alignment: .trailing)
                            Text(BRLFormatters.currency(LoanProjectionEngine.toDouble(row.normalAmortization)))
                                .foregroundStyle(row.normalAmortization > .zero ? Color(hex: "#10B981") : .secondary)
                                .frame(width: 95, alignment: .trailing)
                            Text(BRLFormatters.currency(LoanProjectionEngine.toDouble(row.extraAmortization)))
                                .foregroundStyle(row.extraAmortization > .zero ? Color(hex: "#6366F1") : .secondary)
                                .fontWeight(isExtra ? .bold : .regular)
                                .frame(width: 95, alignment: .trailing)
                            Text(BRLFormatters.currency(LoanProjectionEngine.toDouble(row.finalBalance)))
                                .fontWeight(.semibold)
                                .frame(width: 95, alignment: .trailing)

                            Text(row.status.rawValue)
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule().fill(
                                        isShadowed
                                            ? Color.secondary.opacity(0.16)
                                            : (isExtra ? Color(hex: "#6366F1").opacity(0.18) : Color(hex: "#10B981").opacity(0.16))
                                    )
                                )
                                .foregroundStyle(
                                    isShadowed
                                        ? Color.secondary
                                        : (isExtra ? Color(hex: "#6366F1") : Color(hex: "#10B981"))
                                )
                                .frame(width: 135, alignment: .trailing)
                        }
                        .font(.caption.monospacedDigit())
                        .opacity(isShadowed ? 0.50 : 1.0)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(isExtra ? Color(hex: "#6366F1").opacity(0.08) : Color.primary.opacity(0.02))
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
        }
    }
}

// MARK: - Linha Editável Dinâmica de Amortização Planejada (Data - Valor da Amortização - Saldo Restante)

private struct PlannedAmortizationEditableRow: View {
    @ObservedObject var store: FinancialDataStore
    let contract: CreditContract
    let index: Int
    let item: PlannedAmortization
    let outcome: PlannedItemProjectionOutcome?

    @State private var editableDate: Date = Date()
    @State private var editableAmountText: String = ""
    @State private var editableSource: AmortizationFundingSource = .cash
    @State private var editableMode: AmortizationRecalculationMode = .reduceTerm

    var body: some View {
        let balanceBeforeDouble = LoanProjectionEngine.toDouble(outcome?.balanceBefore ?? .zero)
        let effectiveAmortDouble = LoanProjectionEngine.toDouble(outcome?.effectiveAmortization ?? item.amount)
        let remainingBalanceAfterDouble = LoanProjectionEngine.toDouble(outcome?.remainingBalanceAfter ?? .zero)
        let leftoverDouble = LoanProjectionEngine.toDouble(outcome?.changeLeftover ?? .zero)
        let isPayoff = outcome?.isFullPayoffStep ?? false

        HStack(spacing: 12) {
            Text("#\(index)")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .leading)

            // 1. Data da Amortização (Editável)
            DatePicker("", selection: $editableDate, displayedComponents: [.date])
                .labelsHidden()
                .frame(width: 120)
                .onChange(of: editableDate) { _, newDate in
                    guard newDate != item.date else { return }
                    commitRowUpdate(newDate: newDate)
                }

            // 2. Valor da Amortização (Editável)
            HStack(spacing: 4) {
                TextField("Valor (R$)", text: $editableAmountText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 125)
                    .onSubmit {
                        commitRowUpdate()
                    }
                Button {
                    commitRowUpdate()
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.borderless)
                .help("Aplicar novo valor e recalcular saldo restante")
            }

            if contract.kind == .financing {
                Picker("", selection: $editableSource) {
                    ForEach(AmortizationFundingSource.allCases) { src in
                        Text(src.shortTitle).tag(src)
                    }
                }
                .labelsHidden()
                .frame(width: 100)
                .onChange(of: editableSource) { _, newSrc in
                    guard newSrc != item.source else { return }
                    commitRowUpdate(newSource: newSrc)
                }

                Picker("", selection: $editableMode) {
                    ForEach(AmortizationRecalculationMode.allCases) { m in
                        Text(m == .reduceTerm ? "Reduzir Prazo" : "Reduzir Parcela").tag(m)
                    }
                }
                .labelsHidden()
                .frame(width: 130)
                .onChange(of: editableMode) { _, newMode in
                    guard newMode != item.mode else { return }
                    commitRowUpdate(newMode: newMode)
                }
            }

            // 3. Saldo Restante (Gerado Dinamicamente com base no saldo planejado anterior)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Saldo Restante:")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(BRLFormatters.currency(remainingBalanceAfterDouble))
                        .font(.caption.bold().monospacedDigit())
                        .foregroundStyle(isPayoff ? Color(hex: "#10B981") : .primary)

                    if isPayoff {
                        Text("QUITAÇÃO TOTAL")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color(hex: "#10B981").opacity(0.18)))
                            .foregroundStyle(Color(hex: "#10B981"))
                    }
                }
                HStack(spacing: 8) {
                    Text("Saldo antes: \(BRLFormatters.currency(balanceBeforeDouble)) • Abatido: \(BRLFormatters.currency(effectiveAmortDouble))")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    if leftoverDouble > 0.01 {
                        Text("• Sobra ajustada: \(BRLFormatters.currency(leftoverDouble))")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color(hex: "#3B82F6"))
                    }
                    if outcome?.isFGTSFullPayoffExempt == true {
                        Text("• Carência FGTS 24m dispensada por lei (Quitação)")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color(hex: "#10B981"))
                    }
                }
            }

            Spacer()

            // Ações da Linha: Confirmar Pagamento Real (Camada 1) ou Remover do Plano
            Button {
                store.confirmPlannedAmortizationPayment(
                    contractId: contract.id,
                    itemId: item.id,
                    accountId: contract.accountId,
                    paymentDate: item.date
                )
            } label: {
                Label("Confirmar Pagamento", systemImage: "checkmark.circle.fill")
                    .font(.caption2.bold())
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(hex: "#10B981"))
            .controlSize(.small)
            .help("Confirmar que este aporte foi pago e abater definitivamente do contrato real (Camada 1)")

            Button(role: .destructive) {
                store.removePlannedAmortization(contractId: contract.id, itemId: item.id)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Remover esta amortização do planejamento")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isPayoff ? Color(hex: "#10B981").opacity(0.08) : Color.primary.opacity(0.03))
        )
        .onAppear {
            syncLocalFields()
        }
        .onChange(of: item) { _, _ in
            syncLocalFields()
        }
    }

    private func syncLocalFields() {
        editableDate = item.date
        editableAmountText = BRLFormatters.currency(item.amountDouble)
        editableSource = item.source
        editableMode = item.mode
    }

    private func commitRowUpdate(
        newDate: Date? = nil,
        newSource: AmortizationFundingSource? = nil,
        newMode: AmortizationRecalculationMode? = nil
    ) {
        let parsedAmt = BRLFormatters.parseAmount(editableAmountText) ?? item.amountDouble
        guard parsedAmt > 0 else { return }
        store.updatePlannedAmortization(
            contractId: contract.id,
            itemId: item.id,
            date: newDate ?? editableDate,
            amount: LoanProjectionEngine.toDecimal(parsedAmt),
            source: newSource ?? editableSource,
            mode: newMode ?? editableMode,
            notes: item.notes
        )
    }
}
