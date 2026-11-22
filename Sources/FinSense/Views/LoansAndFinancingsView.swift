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
                    detailCell(label: "Valor Cadastrado da Parcela", value: BRLFormatters.currency(contract.installmentAmount))

                    detailCell(label: "Parcela Base Price", value: BRLFormatters.currency(contract.effectiveBaseInstallmentPrice))
                    detailCell(label: "Seguros MIP/DFI", value: BRLFormatters.currency(contract.effectiveInsuranceFee))
                    detailCell(label: "Taxa de Administração", value: BRLFormatters.currency(contract.effectiveAdminFee))

                    if let avgGrowth = contract.averageMonthlyInstallmentGrowth, avgGrowth > 0.001 {
                        detailCell(
                            label: "Projeção Mensal (Média Doc)",
                            value: "+\(BRLFormatters.currency(avgGrowth))/mês (1ª: \(BRLFormatters.currency(contract.installmentAmount + avgGrowth)))",
                            valueColor: Color(hex: "#8B5CF6")
                        )
                    }

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
                        let contractNumInfo = contract.contractNumber.map { " — Contrato \($0)" } ?? ""
                        let question = "[NOVA SIMULAÇÃO DO SISTEMA] Monte um plano de ação completo para quitar meu \(kindLower) \"\(contract.name)\"\(contractNumInfo) no menor prazo possível, simulando cenários mensais de amortização e validando a viabilidade no meu Saldo Previsto."
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
                    let achievesPayoff = projection.doesPlanAchieveFullPayoff
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: achievesPayoff ? "checkmark.seal.fill" : "calendar.badge.clock")
                                .foregroundStyle(achievesPayoff ? Color(hex: "#10B981") : Color(hex: "#6366F1"))
                            Text(
                                achievesPayoff
                                    ? "Planejamento Ativo • QUITAÇÃO TOTAL em \(BRLFormatters.shortDate(projection.projectedMaturityDate)) (\(pendingCount) aporte\(pendingCount > 1 ? "s" : ""))"
                                    : "Planejamento de Amortização Ativo (\(pendingCount) aporte\(pendingCount > 1 ? "s" : "") planejado\(pendingCount > 1 ? "s" : ""))"
                            )
                            .font(.caption.bold())
                            .foregroundStyle(achievesPayoff ? Color(hex: "#10B981") : Color(hex: "#6366F1"))

                            Spacer()

                            Button("Ver Planejamento") {
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
                            .help("Remover planejamento de amortização")
                        }

                        HStack(spacing: 16) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Início (Saldo Atual)")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                Text(BRLFormatters.currency(LoanProjectionEngine.toDouble(projection.currentRealBalance)))
                                    .font(.caption.bold())
                            }
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Meio (Total Planejado)")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                Text(BRLFormatters.currency(LoanProjectionEngine.toDouble(projection.totalExtraAmortized)))
                                    .font(.caption.bold())
                                    .foregroundStyle(Color(hex: "#6366F1"))
                            }
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Fim (Saldo Pós-Plano)")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                Text(
                                    achievesPayoff
                                        ? "R$ 0,00 (QUITADO)"
                                        : BRLFormatters.currency(LoanProjectionEngine.toDouble(projection.projectedFinalBalanceAfterPlan))
                                )
                                .font(.caption.bold())
                                .foregroundStyle(achievesPayoff ? Color(hex: "#10B981") : .primary)
                            }
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Juros Economizados")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                Text("\(BRLFormatters.currency(LoanProjectionEngine.toDouble(projection.totalInterestSaved))) (\(projection.monthsSaved)m)")
                                    .font(.caption.bold())
                                    .foregroundStyle(Color(hex: "#3B82F6"))
                            }
                        }
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill((achievesPayoff ? Color(hex: "#10B981") : Color(hex: "#6366F1")).opacity(0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke((achievesPayoff ? Color(hex: "#10B981") : Color(hex: "#6366F1")).opacity(0.32), lineWidth: 1)
                    )
                }
            }

            // Espaçador flexível (mola) para nivelamento e ancoragem dos botões na base
            Spacer(minLength: 4)

            // Action Buttons: Planejar Amortização / Ver Planejamento, Amortizar Agora & Quitar (Ancorados no rodapé)
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
                let hasSavedPlan = store.hasSavedAmortizationPlan(for: contract.id)
                HStack(spacing: 10) {
                    Button {
                        contractToPlan = contract
                    } label: {
                        Label(
                            hasSavedPlan ? "Ver Planejamento" : "Planejar Amortização",
                            systemImage: hasSavedPlan ? "calendar.badge.checkmark" : "calendar.badge.clock"
                        )
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
    @State private var billingDay: Int = 1
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
            if kind == .financing && billingDay == 1 {
                billingDay = 5
                bankDueDay = 5
            }
        }
        .sheet(isPresented: $showEmbeddedDocImporter) {
            ImportCreditContractDocumentSheet(
                store: store,
                llmService: llmService,
                kind: kind,
                initialBillingDay: billingDay,
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
    public var initialBillingDay: Int? = nil
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
    @State private var billingDay: Int = 1
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
        initialBillingDay: Int? = nil,
        onCompleteImport: (() -> Void)? = nil
    ) {
        self.store = store
        self.llmService = llmService
        self.kind = kind
        self.initialBillingDay = initialBillingDay
        self.onCompleteImport = onCompleteImport
        _billingDay = State(initialValue: initialBillingDay ?? (kind == .loan ? 1 : 5))
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
                                recalculateScheduleForSalaryBillingDay(newDay)
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
        if doc.kind == .financing && initialBillingDay == nil {
            billingDay = doc.billingDay
        }
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
        referenceDate = doc.referenceDate ?? doc.documentEmissionDate ?? store.effectiveCurrentDate
        maturityDate = doc.maturityDate
        firstFutureBillingDate = doc.firstFutureBillingDate
        notes = doc.extractedNotes
        errorMsg = nil

        // Recalcula parcelas já pagas e próxima cobrança com base no dia em que o valor sai do salário/conta (`billingDay`)
        recalculateScheduleForSalaryBillingDay(billingDay)
    }

    private func recalculateScheduleForSalaryBillingDay(_ salaryDay: Int) {
        guard let doc = parsedDoc else {
            var comps = store.calendar.dateComponents([.year, .month], from: firstFutureBillingDate)
            comps.day = min(max(salaryDay, 1), 28)
            if let updated = store.calendar.date(from: comps) {
                firstFutureBillingDate = updated
            }
            return
        }
        let recalc = doc.recalculatedForSalaryBillingDay(
            salaryDay,
            referenceNow: store.effectiveCurrentDate,
            calendar: store.calendar
        )
        paidInstallmentsCount = recalc.paidCount
        firstFutureBillingDate = recalc.firstFutureBillingDate
        outstandingBalanceText = BRLFormatters.currency(recalc.remainingBalance)
        installmentAmountText = BRLFormatters.currency(recalc.nextInstallmentAmount)
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
            referenceDate: store.effectiveCurrentDate,
            overridePastInstallmentsCount: paidInstallmentsCount,
            overrideFirstFutureBillingDate: firstFutureBillingDate,
            annualNominalInterestRate: annNominal,
            indexationRate: idxRate,
            adminFee: admFee,
            insuranceFee: insFee,
            baseInstallmentAmount: basePriceAmt,
            bankDueDay: bankDueDay,
            documentReferenceDate: referenceDate,
            maturityDate: maturityDate,
            scheduledInstallments: parsedDoc?.scheduledInstallments,
            averageMonthlyInstallmentGrowth: parsedDoc?.averageMonthlyInstallmentGrowth
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

// MARK: - Modal de Planejamento Dinâmico de Amortização (2 Estados: Criação/Edição em Rascunho vs. Visualização Salva)

public struct AmortizationPlannerSheet: View {
    @ObservedObject public var store: FinancialDataStore
    @Environment(\.dismiss) private var dismiss

    public let contract: CreditContract

    private enum UnifiedTimelineFilter: String, CaseIterable, Identifiable {
        case allEvents = "Evolução Mês a Mês + Aportes"
        case onlyContributions = "Somente Aportes Planejados"
        var id: String { rawValue }
    }

    // Estado da Tela:
    // - `isEditingMode == true`: Tela de Criação / Edição em Rascunho (só aplica ao clicar em "Salvar Planejamento")
    // - `isEditingMode == false`: Tela de Visualização do Planejamento Salvo ("Ver Planejamento", com opções "Editar" e "Remover")
    @State private var isEditingMode: Bool = true
    @State private var selectedMode: AmortizationPlanGenerationMode = .manual
    @State private var timelineFilter: UnifiedTimelineFilter = .allEvents

    // Rascunho Local dos Aportes Planejados (Camada 2 em Rascunho até clicar em Salvar)
    @State private var draftItems: [PlannedAmortization] = []

    // Campos do Modo Manual
    @State private var manualDate: Date = Date()
    @State private var manualAmountText: String = ""
    @State private var manualSource: AmortizationFundingSource = .cash
    @State private var manualRecalcMode: AmortizationRecalculationMode = .reduceTerm
    @State private var manualNotes: String = ""
    @State private var clampFeedbackMessage: String? = nil

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

    private var parsedTRDecimal: Decimal {
        LoanProjectionEngine.toDecimal(BRLFormatters.parseAmount(estimatedMonthlyTRText) ?? 0.0)
    }

    private func buildActivePlanForSimulation(currentContract: CreditContract) -> AmortizationPlan {
        if isEditingMode {
            let effMode: AmortizationRecalculationMode = currentContract.kind == .loan
                ? .reduceTerm
                : (selectedMode == .manual ? manualRecalcMode : autoRecalcMode)
            return AmortizationPlan(
                contractId: currentContract.id,
                generationMode: selectedMode,
                billingDay: autoBillingDay,
                incomeCommitmentPercentage: Decimal(Int(autoCommitmentPercentage)),
                defaultRecalculationMode: effMode,
                estimatedMonthlyTR: parsedTRDecimal,
                items: draftItems
            )
        } else {
            return store.amortizationPlan(for: currentContract.id) ?? AmortizationPlan(
                contractId: currentContract.id,
                generationMode: selectedMode,
                billingDay: autoBillingDay,
                incomeCommitmentPercentage: Decimal(Int(autoCommitmentPercentage)),
                defaultRecalculationMode: .reduceTerm,
                estimatedMonthlyTR: parsedTRDecimal,
                items: []
            )
        }
    }

    public var body: some View {
        let currentContract = liveContract
        let activePlan = buildActivePlanForSimulation(currentContract: currentContract)
        let projection = isEditingMode
            ? store.simulateAmortizationPlanPreview(for: currentContract.id, draftPlan: activePlan)
            : store.loanProjection(for: currentContract.id)
        let pendingItems = activePlan.items.filter { $0.status == .pending }.sorted { $0.date < $1.date }
        let expiredItems = store.expiredPlannedAmortizations(for: currentContract.id)
        let achievesFullPayoff = projection?.doesPlanAchieveFullPayoff ?? false

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

        VStack(alignment: .leading, spacing: 12) {
            // 1. Header Compacto com Badge de Estado (Modo Criação/Edição vs. Modo Visualização)
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Image(systemName: isEditingMode ? "wand.and.stars" : "calendar.badge.checkmark")
                            .foregroundStyle(Color(hex: isEditingMode ? "#6366F1" : "#10B981"))
                        Text(isEditingMode ? "Planejar Amortização: \(currentContract.name)" : "Planejamento de Amortização: \(currentContract.name)")
                            .font(.title3.bold())

                        Text(isEditingMode ? "MODO EDIÇÃO (RASCUNHO)" : "PLANEJAMENTO SALVO")
                            .font(.system(size: 10, weight: .heavy))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                Capsule().fill(Color(hex: isEditingMode ? "#F59E0B" : "#10B981").opacity(0.18))
                            )
                            .foregroundStyle(Color(hex: isEditingMode ? "#D97706" : "#10B981"))
                    }

                    HStack(spacing: 10) {
                        Text(currentContract.amortizationSystem.rawValue)
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
                        if let payrollTip = projection?.payrollOperationalTip {
                            Text("•")
                            Text(payrollTip)
                                .foregroundStyle(Color(hex: "#D97706"))
                                .lineLimit(1)
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                if isEditingMode && currentContract.kind == .financing && (currentContract.indexationRate ?? .tr) == .tr {
                    HStack(spacing: 6) {
                        Text("TR Mensal Est. (%):")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        TextField("0,00", text: $estimatedMonthlyTRText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 64)
                    }
                }
            }

            // 2. Jornada do Planejamento: INÍCIO → MEIO → FIM + Visibilidade Clara de Quitação
            if let proj = projection {
                planningLifecycleJourneySection(
                    proj: proj,
                    pendingCount: pendingItems.count,
                    achievesFullPayoff: achievesFullPayoff
                )
            }

            // Alertas Legais do FGTS (Interstício de 24 meses para parcial)
            if let fgtsWarnings = projection?.fgtsWarnings, !fgtsWarnings.isEmpty {
                ForEach(fgtsWarnings, id: \.self) { warning in
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Color(hex: "#EF4444"))
                        Text(warning)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(Color(hex: "#EF4444"))
                        Spacer()
                    }
                    .padding(7)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: "#EF4444").opacity(0.10)))
                }
            }

            // Banners de Resolução de Aportes Expirados (quando visualizando plano salvo)
            if !isEditingMode && !expiredItems.isEmpty {
                ForEach(expiredItems) { expItem in
                    ExpiredAmortizationResolutionBanner(
                        store: store,
                        contract: currentContract,
                        expiredItem: expItem
                    )
                }
            }

            // 3. Painel de Inserção (No Modo Criação/Edição exibe os controles; no Modo Visualização exibe atalho rápido para Adicionar Aporte Manual)
            if isEditingMode {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 14) {
                        Picker("Modo de Planejamento", selection: $selectedMode) {
                            ForEach(AmortizationPlanGenerationMode.allCases) { m in
                                Text(m.rawValue).tag(m)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 340)

                        Spacer()

                        if !pendingItems.isEmpty {
                            Button(role: .destructive) {
                                draftItems.removeAll { $0.status == .pending }
                                manualAmountText = ""
                                clampFeedbackMessage = nil
                                errorMsg = nil
                            } label: {
                                Label("Limpar Aportes do Rascunho", systemImage: "xmark.bin")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }

                    if selectedMode == .manual {
                        manualInputPanel(
                            currentContract: currentContract,
                            activePlan: activePlan,
                            projection: projection,
                            achievesFullPayoff: achievesFullPayoff
                        )
                    } else {
                        automaticInputPanel(
                            currentContract: currentContract,
                            detectedMonthlySurplusDouble: detectedMonthlySurplusDouble,
                            effectiveBaseSurplusDouble: effectiveBaseSurplusDouble,
                            autoMonthlyContributionPreview: autoMonthlyContributionPreview
                        )
                    }
                }
            } else {
                // Atalho visível no topo do Modo Visualização para entrar imediatamente na inserção manual ou edição
                HStack(spacing: 12) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(Color(hex: "#6366F1"))
                    Text("Você está visualizando o planejamento salvo. Para adicionar novos aportes manuais ou alterar valores, clique ao lado:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        loadStateFromStore(enterEditIfEmpty: true)
                        isEditingMode = true
                        selectedMode = .manual
                        errorMsg = nil
                        clampFeedbackMessage = nil
                    } label: {
                        Label("Adicionar / Editar Amortização Manual", systemImage: "plus.circle.fill")
                            .font(.caption.bold())
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(hex: "#6366F1"))
                    .controlSize(.small)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(hex: "#6366F1").opacity(0.08)))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(hex: "#6366F1").opacity(0.25), lineWidth: 1))
            }

            if let errorMsg {
                Text(errorMsg)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.red)
            }

            if let clampFeedbackMessage {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.shield.fill")
                        .foregroundStyle(Color(hex: "#10B981"))
                    Text(clampFeedbackMessage)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color(hex: "#10B981"))
                    Spacer()
                }
            }

            // 4. Tabela Unificada Clean: Evolução Mês a Mês & Aportes Planejados
            unifiedEvolutionAndContributionsSection(
                currentContract: currentContract,
                activePlan: activePlan,
                pendingItems: pendingItems,
                projection: projection
            )

            // 5. Rodapé Adaptado aos 2 Estados (Criação/Edição vs Visualização)
            HStack(spacing: 12) {
                if isEditingMode {
                    Button("Cancelar") {
                        if store.hasSavedAmortizationPlan(for: currentContract.id) {
                            // Volta para o modo de visualização com os dados salvos originais
                            loadStateFromStore(enterEditIfEmpty: false)
                            isEditingMode = false
                            errorMsg = nil
                            clampFeedbackMessage = nil
                        } else {
                            dismiss()
                        }
                    }
                    .keyboardShortcut(.cancelAction)

                    Spacer()

                    Text(
                        pendingItems.isEmpty
                            ? "Adicione pelo menos 1 aporte planejado para salvar o planejamento."
                            : "O planejamento será aplicado ao orçamento somente ao clicar em \"Salvar Planejamento\"."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    Button {
                        saveDraftPlan(for: currentContract)
                    } label: {
                        Label("Salvar Planejamento", systemImage: "checkmark.circle.fill")
                            .fontWeight(.semibold)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(hex: "#10B981"))
                    .disabled(pendingItems.isEmpty)
                    .keyboardShortcut(.defaultAction)
                } else {
                    // Modo Visualização ("Ver Planejamento"): Botões "Remover", "Editar" e "Fechar"
                    Button(role: .destructive) {
                        store.deleteAmortizationPlan(for: currentContract.id)
                        dismiss()
                    } label: {
                        Label("Remover Planejamento", systemImage: "trash.fill")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        loadStateFromStore(enterEditIfEmpty: true)
                        isEditingMode = true
                        errorMsg = nil
                        clampFeedbackMessage = nil
                    } label: {
                        Label("Editar Planejamento", systemImage: "pencil")
                            .fontWeight(.semibold)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(hex: "#6366F1"))

                    Spacer()

                    Button("Fechar") {
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(20)
        .frame(width: 1060, height: 780)
        .onAppear {
            let hasActiveSaved = store.hasSavedAmortizationPlan(for: liveContract.id)
            loadStateFromStore(enterEditIfEmpty: !hasActiveSaved)
        }
    }

    private func loadStateFromStore(enterEditIfEmpty: Bool) {
        let current = liveContract
        let existingPlan = store.amortizationPlan(for: current.id)
        let hasActiveSaved = store.hasSavedAmortizationPlan(for: current.id)

        if enterEditIfEmpty {
            isEditingMode = true
        } else {
            isEditingMode = !hasActiveSaved
        }
        selectedMode = existingPlan?.generationMode ?? .manual
        draftItems = existingPlan?.items ?? []

        let bestDay = current.effectiveBankDueDay >= 28 ? 1 : (current.effectiveBankDueDay + 1)
        autoBillingDay = existingPlan?.billingDay ?? (current.kind == .loan ? bestDay : current.billingDay)
        autoCommitmentPercentage = existingPlan.map { LoanProjectionEngine.toDouble($0.incomeCommitmentPercentage) } ?? 30.0
        autoRecalcMode = existingPlan?.defaultRecalculationMode ?? .reduceTerm
        manualRecalcMode = existingPlan?.defaultRecalculationMode ?? .reduceTerm
        let trVal = existingPlan.map { LoanProjectionEngine.toDouble($0.estimatedMonthlyTR) } ?? (current.estimatedMonthlyTR ?? 0.0)
        estimatedMonthlyTRText = String(format: "%.2f", trVal).replacingOccurrences(of: ".", with: ",")

        if let lastItem = draftItems.filter({ $0.status == .pending }).sorted(by: { $0.date < $1.date }).last,
           let nextMonth = store.calendar.date(byAdding: .month, value: 1, to: lastItem.date) {
            manualDate = nextMonth
        } else {
            var comps = store.calendar.dateComponents([.year, .month], from: store.effectiveCurrentDate)
            comps.day = min(max(autoBillingDay, 1), 28)
            var candidate = store.calendar.date(from: comps) ?? store.effectiveCurrentDate
            if store.calendar.startOfDay(for: candidate) < store.calendar.startOfDay(for: store.effectiveCurrentDate) {
                candidate = store.calendar.date(byAdding: .month, value: 1, to: candidate) ?? candidate
            }
            manualDate = candidate
        }
    }

    private func saveDraftPlan(for currentContract: CreditContract) {
        let effMode: AmortizationRecalculationMode = currentContract.kind == .loan
            ? .reduceTerm
            : (selectedMode == .manual ? manualRecalcMode : autoRecalcMode)
        _ = store.saveAmortizationPlan(
            contractId: currentContract.id,
            generationMode: selectedMode,
            billingDay: autoBillingDay,
            incomeCommitmentPercentage: Decimal(Int(autoCommitmentPercentage)),
            defaultRecalculationMode: effMode,
            estimatedMonthlyTR: parsedTRDecimal,
            draftItems: draftItems
        )
        loadStateFromStore(enterEditIfEmpty: false)
        isEditingMode = false
        errorMsg = nil
        clampFeedbackMessage = nil
    }

    private func recomputeSanitizedDraftItems(for currentContract: CreditContract, candidateItems: [PlannedAmortization]) {
        let unpaidInstallments = store.transactions.filter {
            $0.linkedContractId == currentContract.id &&
            $0.installmentIndex != nil &&
            !$0.isPaid
        }
        let currentRealBal = store.currentOutstandingBalance(for: currentContract)
        draftItems = LoanProjectionEngine.clampAndSanitizePlannedItems(
            candidateItems,
            contract: currentContract,
            unpaidInstallmentTransactions: unpaidInstallments,
            currentRealBalanceDouble: currentRealBal,
            estimatedMonthlyTR: parsedTRDecimal,
            calendar: store.calendar
        )
    }

    // MARK: - Jornada do Planejamento (Início → Meio → Fim) & Banner de Quitação

    @ViewBuilder
    private func planningLifecycleJourneySection(
        proj: LoanProjectionResult,
        pendingCount: Int,
        achievesFullPayoff: Bool
    ) -> some View {
        let initialBal = LoanProjectionEngine.toDouble(proj.currentRealBalance)
        let extraTotal = LoanProjectionEngine.toDouble(proj.totalExtraAmortized)
        let finalBal = LoanProjectionEngine.toDouble(proj.projectedFinalBalanceAfterPlan)
        let interestSaved = LoanProjectionEngine.toDouble(proj.totalInterestSaved)

        VStack(alignment: .leading, spacing: 8) {
            // 3 Cards Conectados: 1. Início -> 2. Meio -> 3. Fim
            HStack(spacing: 10) {
                // INÍCIO
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Text("1. INÍCIO (SITUAÇÃO ATUAL)")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Image(systemName: "flag.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text(BRLFormatters.currency(initialBal))
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                    Text("\(proj.originalRemainingMonths) parcelas restantes • Término original: \(BRLFormatters.shortDate(proj.originalMaturityDate))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.08), lineWidth: 1))

                Image(systemName: "arrow.right.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Color(hex: "#6366F1"))

                // MEIO
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Text("2. MEIO (APORTES & ECONOMIA)")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(Color(hex: "#6366F1"))
                        Spacer()
                        Image(systemName: "bolt.fill")
                            .font(.caption2)
                            .foregroundStyle(Color(hex: "#6366F1"))
                    }
                    Text("\(BRLFormatters.currency(extraTotal)) em \(pendingCount) aporte(s)")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(hex: "#6366F1"))
                    Text("\(proj.monthsSaved) parcelas eliminadas • Juros economizados: \(BRLFormatters.currency(interestSaved))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(hex: "#6366F1").opacity(0.07)))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(hex: "#6366F1").opacity(0.28), lineWidth: 1))

                Image(systemName: "arrow.right.circle.fill")
                    .font(.title3)
                    .foregroundStyle(achievesFullPayoff ? Color(hex: "#10B981") : Color(hex: "#F59E0B"))

                // FIM
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Text(achievesFullPayoff ? "3. FIM (QUITAÇÃO TOTAL ATINGIDA!)" : "3. FIM (SALDO APÓS PLANEJAMENTO)")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(achievesFullPayoff ? Color(hex: "#10B981") : Color(hex: "#D97706"))
                        Spacer()
                        Image(systemName: achievesFullPayoff ? "checkmark.seal.fill" : "clock.badge.checkmark")
                            .font(.caption2)
                            .foregroundStyle(achievesFullPayoff ? Color(hex: "#10B981") : Color(hex: "#D97706"))
                    }
                    Text(achievesFullPayoff ? "R$ 0,00 • QUITADO" : BRLFormatters.currency(finalBal))
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(achievesFullPayoff ? Color(hex: "#10B981") : .primary)
                    Text(
                        achievesFullPayoff
                            ? "Liquidação final em \(BRLFormatters.shortDate(proj.projectedMaturityDate)) (\(proj.projectedActiveMonths) parcelas ativas)"
                            : "Faltam \(BRLFormatters.currency(finalBal)) para quitar • Novo término: \(BRLFormatters.shortDate(proj.projectedMaturityDate))"
                    )
                    .font(.caption2.weight(achievesFullPayoff ? .semibold : .regular))
                    .foregroundStyle(achievesFullPayoff ? Color(hex: "#10B981") : .secondary)
                    .lineLimit(1)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill((achievesFullPayoff ? Color(hex: "#10B981") : Color(hex: "#F59E0B")).opacity(0.12))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke((achievesFullPayoff ? Color(hex: "#10B981") : Color(hex: "#F59E0B")).opacity(0.45), lineWidth: achievesFullPayoff ? 1.5 : 1)
                )
            }
        }
    }

    // MARK: - Painel de Inserção Manual (Com Saldo Esperado no Fim do Mês + Saldo do Empréstimo Após Amortização + Trava de Quitação)

    @ViewBuilder
    private func manualInputPanel(
        currentContract: CreditContract,
        activePlan: AmortizationPlan,
        projection: LoanProjectionResult?,
        achievesFullPayoff: Bool
    ) -> some View {
        let maxAllowedOnDate = store.maxAvailableLoanBalanceToAmortize(
            for: currentContract.id,
            draftItems: draftItems,
            onDate: manualDate,
            excludingItemId: nil,
            estimatedMonthlyTR: parsedTRDecimal
        )
        let isAlreadyQuitado = achievesFullPayoff || maxAllowedOnDate <= 0.01

        let rawTyped = BRLFormatters.parseAmount(manualAmountText) ?? 0.0
        let effectiveTyped = min(max(rawTyped, 0.0), maxAllowedOnDate)
        let loanBalanceAfterInput = max(0.0, maxAllowedOnDate - effectiveTyped)
        let inputLeadsToPayoff = !isAlreadyQuitado && effectiveTyped > 0.01 && loanBalanceAfterInput <= 0.01

        let monthEndCashBeforeInput = store.expectedMonthEndCashBalance(
            for: manualDate,
            contractId: currentContract.id,
            draftPlan: activePlan,
            draftProjection: projection,
            additionalTypingOutflow: 0.0
        )
        let monthEndCashAfterInput = store.expectedMonthEndCashBalance(
            for: manualDate,
            contractId: currentContract.id,
            draftPlan: activePlan,
            draftProjection: projection,
            additionalTypingOutflow: effectiveTyped
        )

        VStack(alignment: .leading, spacing: 8) {
            if isAlreadyQuitado {
                // Trava quando o empréstimo já estaria quitado pelos aportes planejados atuais
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.title3)
                        .foregroundStyle(Color(hex: "#10B981"))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Este planejamento já leva à QUITAÇÃO TOTAL do contrato (Saldo Devedor R$ 0,00)!")
                            .font(.subheadline.bold())
                            .foregroundStyle(Color(hex: "#10B981"))
                        Text("Novos aportes adicionais estão bloqueados porque o empréstimo já estará 100% quitado. Você pode editar qualquer valor na lista abaixo ou clicar ao lado para reabrir a inserção manual.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()

                    if !draftItems.filter({ $0.status == .pending }).isEmpty {
                        Button {
                            var pending = draftItems.filter { $0.status == .pending }.sorted { $0.date < $1.date }
                            if !pending.isEmpty {
                                let removedLast = pending.removeLast()
                                let nonPending = draftItems.filter { $0.status != .pending }
                                draftItems = nonPending + pending
                                manualDate = removedLast.date
                                manualAmountText = BRLFormatters.currency(removedLast.amountDouble)
                            }
                        } label: {
                            Label("Ajustar Último Aporte Manualmente", systemImage: "pencil.and.outline")
                                .font(.caption.bold())
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color(hex: "#6366F1"))
                        .controlSize(.small)
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(hex: "#10B981").opacity(0.10)))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(hex: "#10B981").opacity(0.35), lineWidth: 1))
            } else {
                // Linha 1: Controles de Inserção
                HStack(spacing: 10) {
                    DatePicker("Data do Aporte:", selection: $manualDate, displayedComponents: [.date])
                        .frame(width: 215)
                        .onChange(of: manualDate) { _, newDate in
                            let newMax = store.maxAvailableLoanBalanceToAmortize(
                                for: currentContract.id,
                                draftItems: draftItems,
                                onDate: newDate,
                                excludingItemId: nil,
                                estimatedMonthlyTR: parsedTRDecimal
                            )
                            if let cur = BRLFormatters.parseAmount(manualAmountText), cur > newMax + 0.005, newMax > 0 {
                                manualAmountText = BRLFormatters.currency(newMax)
                                clampFeedbackMessage = "Valor ajustado para \(BRLFormatters.currency(newMax)) (teto máximo para quitação total em \(BRLFormatters.shortDate(newDate)))."
                            }
                        }

                    BRLCurrencyTextField(
                        label: "",
                        text: $manualAmountText,
                        placeholder: "Valor do Aporte (Máx: \(BRLFormatters.currency(maxAllowedOnDate)))"
                    )
                    .frame(width: 235)
                    .onChange(of: manualAmountText) { _, newText in
                        guard let val = BRLFormatters.parseAmount(newText) else {
                            clampFeedbackMessage = nil
                            return
                        }
                        if val > maxAllowedOnDate + 0.005 && maxAllowedOnDate > 0 {
                            let clampedStr = BRLFormatters.currency(maxAllowedOnDate)
                            if manualAmountText != clampedStr {
                                manualAmountText = clampedStr
                            }
                            clampFeedbackMessage = "Valor limitado a \(clampedStr) — este aporte quita 100% do saldo restante nesta data!"
                        } else if abs(val - maxAllowedOnDate) <= 0.01 && maxAllowedOnDate > 0 {
                            clampFeedbackMessage = "Este valor (\(BRLFormatters.currency(maxAllowedOnDate))) leva à QUITAÇÃO TOTAL do empréstimo!"
                        } else {
                            clampFeedbackMessage = nil
                        }
                    }

                    Button("Quitar Saldo (\(BRLFormatters.currency(maxAllowedOnDate)))") {
                        manualAmountText = BRLFormatters.currency(maxAllowedOnDate)
                        clampFeedbackMessage = "Valor preenchido para QUITAÇÃO TOTAL em \(BRLFormatters.shortDate(manualDate))."
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    if currentContract.kind == .financing {
                        Picker("", selection: $manualSource) {
                            ForEach(AmortizationFundingSource.allCases) { src in
                                Text(src.shortTitle).tag(src)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 110)

                        Picker("", selection: $manualRecalcMode) {
                            ForEach(AmortizationRecalculationMode.allCases) { m in
                                Text(m == .reduceTerm ? "Reduzir Prazo" : "Reduzir Parcela").tag(m)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 135)
                    }

                    Spacer()

                    Button {
                        guard let val = BRLFormatters.parseAmount(manualAmountText), val > 0 else {
                            errorMsg = "Informe um valor de amortização válido maior que zero."
                            return
                        }
                        guard maxAllowedOnDate > 0.01 else {
                            errorMsg = "O empréstimo já está quitado nesta data."
                            return
                        }
                        let clampedVal = min(val, maxAllowedOnDate)
                        errorMsg = nil
                        clampFeedbackMessage = nil

                        let newItem = PlannedAmortization(
                            contractId: currentContract.id,
                            date: manualDate,
                            amount: LoanProjectionEngine.toDecimal(clampedVal),
                            source: currentContract.kind == .loan ? .cash : manualSource,
                            mode: currentContract.kind == .loan ? .reduceTerm : manualRecalcMode,
                            status: .pending,
                            notes: manualNotes
                        )
                        recomputeSanitizedDraftItems(for: currentContract, candidateItems: draftItems + [newItem])
                        manualAmountText = ""
                        if let nextDate = store.calendar.date(byAdding: .month, value: 1, to: manualDate) {
                            manualDate = nextDate
                        }
                    } label: {
                        Label(
                            inputLeadsToPayoff ? "Adicionar Quitação Total" : "Adicionar Aporte",
                            systemImage: inputLeadsToPayoff ? "checkmark.seal.fill" : "plus.circle.fill"
                        )
                        .fontWeight(.semibold)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(hex: inputLeadsToPayoff ? "#10B981" : "#6366F1"))
                }

                // Linha 2 (Na mesma linha): Visibilidade em Tempo Real do Saldo Esperado no Fim do Mês + Saldo do Empréstimo Após Amortização
                HStack(spacing: 16) {
                    HStack(spacing: 6) {
                        Image(systemName: "wallet.pass.fill")
                            .foregroundStyle(monthEndCashAfterInput >= 0 ? Color(hex: "#10B981") : Color(hex: "#EF4444"))
                        Text("Saldo Esperado no Fim de \(BRLFormatters.monthYear(manualDate)):")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(BRLFormatters.currency(monthEndCashAfterInput))
                            .font(.caption.bold().monospacedDigit())
                            .foregroundStyle(monthEndCashAfterInput >= 0 ? Color(hex: "#10B981") : Color(hex: "#EF4444"))
                        if effectiveTyped > 0.01 {
                            Text("(antes do aporte: \(BRLFormatters.currency(monthEndCashBeforeInput)))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Divider().frame(height: 16)

                    HStack(spacing: 6) {
                        Image(systemName: "banknote.fill")
                            .foregroundStyle(inputLeadsToPayoff ? Color(hex: "#10B981") : Color(hex: "#6366F1"))
                        Text("Saldo do Empréstimo Após Amortização:")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(BRLFormatters.currency(loanBalanceAfterInput))
                            .font(.caption.bold().monospacedDigit())
                            .foregroundStyle(inputLeadsToPayoff ? Color(hex: "#10B981") : .primary)

                        if inputLeadsToPayoff {
                            Text("🎉 LEVA À QUITAÇÃO TOTAL")
                                .font(.system(size: 10, weight: .heavy))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color(hex: "#10B981").opacity(0.20)))
                                .foregroundStyle(Color(hex: "#10B981"))
                        }
                    }

                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(inputLeadsToPayoff ? Color(hex: "#10B981").opacity(0.10) : Color.primary.opacity(0.03))
                )
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.08), lineWidth: 1))
    }

    @ViewBuilder
    private func automaticInputPanel(
        currentContract: CreditContract,
        detectedMonthlySurplusDouble: Double,
        effectiveBaseSurplusDouble: Double,
        autoMonthlyContributionPreview: Double
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Gerador Automático por Comprometimento do Saldo Previsto no Fim do Mês", systemImage: "wand.and.stars.inverse")
                    .font(.caption.bold())
                    .foregroundStyle(Color(hex: "#10B981"))
                Spacer()
                Text("Saldo previsto no fim do mês: \(BRLFormatters.currency(detectedMonthlySurplusDouble)) • Aporte sugerido (\(Int(autoCommitmentPercentage))%): \(BRLFormatters.currency(autoMonthlyContributionPreview))/mês")
                    .font(.caption.bold())
                    .foregroundStyle(Color(hex: "#10B981"))
            }

            HStack(spacing: 12) {
                EditableIntegerStepperField(
                    label: "Dia da Amortização",
                    value: $autoBillingDay,
                    range: 1...31,
                    unitSuffix: "dia"
                )
                .frame(width: 175)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Comprometer: \(Int(autoCommitmentPercentage))% da sobra")
                        .font(.caption.weight(.semibold))
                    Slider(value: $autoCommitmentPercentage, in: 5...100, step: 5)
                        .frame(width: 165)
                }

                BRLCurrencyTextField(
                    label: "Sobra Base Mensal (Opcional)",
                    text: $customMonthlySurplusOverrideText
                )
                .frame(width: 190)

                if currentContract.kind == .financing {
                    Picker("Modalidade", selection: $autoRecalcMode) {
                        ForEach(AmortizationRecalculationMode.allCases) { m in
                            Text(m == .reduceTerm ? "Reduzir Prazo" : "Reduzir Parcela").tag(m)
                        }
                    }
                    .frame(width: 170)
                }

                Spacer()

                Button {
                    guard effectiveBaseSurplusDouble > 10.0 else {
                        errorMsg = "O saldo previsto ao final do mês é insuficiente. Informe uma receita no mês ou defina o valor no campo 'Sobra Base Mensal'."
                        return
                    }
                    errorMsg = nil
                    clampFeedbackMessage = nil
                    let customFallbackDec = customMonthlySurplusOverrideText.isEmpty
                        ? nil
                        : LoanProjectionEngine.toDecimal(effectiveBaseSurplusDouble)
                    let unpaidInstallments = store.transactions.filter {
                        $0.linkedContractId == currentContract.id &&
                        $0.installmentIndex != nil &&
                        !$0.isPaid
                    }
                    let currentRealBal = store.currentOutstandingBalance(for: currentContract)
                    let effMode: AmortizationRecalculationMode = currentContract.kind == .loan ? .reduceTerm : autoRecalcMode

                    let generated = LoanProjectionEngine.generateAutomaticPlanItems(
                        contract: currentContract,
                        unpaidInstallmentTransactions: unpaidInstallments,
                        currentRealBalanceDouble: currentRealBal,
                        billingDay: autoBillingDay,
                        incomeCommitmentPercentage: Decimal(Int(autoCommitmentPercentage)),
                        mode: effMode,
                        estimatedMonthlyTR: parsedTRDecimal,
                        referenceNow: store.effectiveCurrentDate,
                        monthlyAvailableSurplusProvider: { targetMonth in
                            let computed = store.projectedAvailableMonthlySurplusForAmortization(
                                in: targetMonth,
                                excludingContractId: currentContract.id
                            )
                            if computed > .zero { return computed }
                            return customFallbackDec ?? .zero
                        },
                        calendar: store.calendar
                    )
                    let executedItems = draftItems.filter { $0.status == .executed }
                    draftItems = (executedItems + generated).sorted { $0.date < $1.date }
                } label: {
                    Label("Gerar Aportes até Quitação", systemImage: "sparkles")
                        .fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(hex: "#10B981"))
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.08), lineWidth: 1))
    }

    // MARK: - Tabela Unificada Clean: Evolução Mês a Mês & Aportes Planejados

    @ViewBuilder
    private func unifiedEvolutionAndContributionsSection(
        currentContract: CreditContract,
        activePlan: AmortizationPlan,
        pendingItems: [PlannedAmortization],
        projection: LoanProjectionResult?
    ) -> some View {
        let allRows = projection?.timeline ?? []
        let filteredRows: [LoanProjectionTimelineRow] = {
            switch timelineFilter {
            case .allEvents:
                return allRows
            case .onlyContributions:
                return allRows.filter { $0.status == .pendingAmortization }
            }
        }()
        let pendingById = Dictionary(uniqueKeysWithValues: pendingItems.map { ($0.id, $0) })

        // Pré-calcula o Saldo Esperado no Fim do Mês para cada yearMonthKey distinto presente na tabela
        let uniqueMonthDatesByYM: [Int: Double] = {
            var map: [Int: Double] = [:]
            for row in filteredRows where map[row.yearMonthKey] == nil {
                map[row.yearMonthKey] = store.expectedMonthEndCashBalance(
                    for: row.date,
                    contractId: currentContract.id,
                    draftPlan: activePlan,
                    draftProjection: projection,
                    additionalTypingOutflow: 0.0
                )
            }
            return map
        }()

        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Evolução Mês a Mês & Aportes Planejados (\(pendingItems.count) aporte\(pendingItems.count == 1 ? "" : "s") planejado\(pendingItems.count == 1 ? "" : "s"))")
                    .font(.subheadline.bold())

                Spacer()

                Picker("", selection: $timelineFilter) {
                    ForEach(UnifiedTimelineFilter.allCases) { f in
                        Text(f.rawValue).tag(f)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 340)
            }

            // Cabeçalho Clean Unificado (Apenas as informações essenciais na mesma linha)
            HStack(spacing: 10) {
                Text("Data")
                    .frame(width: 112, alignment: .leading)
                Text("Evento (Parcela / Aporte Planejado)")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Valor (Parcela / Aporte)")
                    .frame(width: 165, alignment: .trailing)
                Text("Saldo Esperado no Fim do Mês")
                    .frame(width: 185, alignment: .trailing)
                Text("Saldo do Empréstimo Após")
                    .frame(width: 210, alignment: .trailing)
                Text(isEditingMode ? "Ação" : "Status")
                    .frame(width: 115, alignment: .trailing)
            }
            .font(.caption2.bold())
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.05))
            .cornerRadius(6)

            if filteredRows.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "calendar.badge.plus")
                        .font(.system(size: 30))
                        .foregroundStyle(.secondary)
                    Text("Nenhum aporte planejado neste filtro")
                        .font(.subheadline.bold())
                    Text("Adicione um aporte acima ou alterne o filtro para visualizar todas as parcelas mês a mês.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
            } else {
                ScrollView {
                    LazyVStack(spacing: 5) {
                        ForEach(filteredRows) { row in
                            let monthEndCash = uniqueMonthDatesByYM[row.yearMonthKey] ?? 0.0
                            if row.status == .pendingAmortization,
                               let plannedId = row.linkedPlannedAmortizationId,
                               let plannedItem = pendingById[plannedId] {
                                let outcome = projection?.plannedItemOutcomes[plannedId]
                                UnifiedPlannedContributionRowView(
                                    store: store,
                                    contract: currentContract,
                                    item: plannedItem,
                                    outcome: outcome,
                                    monthEndExpectedCash: monthEndCash,
                                    isEditingMode: isEditingMode,
                                    maxAllowedForThisRow: { candidateDate in
                                        store.maxAvailableLoanBalanceToAmortize(
                                            for: currentContract.id,
                                            draftItems: draftItems,
                                            onDate: candidateDate,
                                            excludingItemId: plannedItem.id,
                                            estimatedMonthlyTR: parsedTRDecimal
                                        )
                                    },
                                    onUpdateDraftItem: { newDate, newAmountDec, newSource, newMode in
                                        var updatedList = draftItems
                                        if let idx = updatedList.firstIndex(where: { $0.id == plannedItem.id }) {
                                            updatedList[idx].date = newDate
                                            updatedList[idx].amount = newAmountDec
                                            updatedList[idx].source = newSource
                                            updatedList[idx].mode = newMode
                                            recomputeSanitizedDraftItems(for: currentContract, candidateItems: updatedList)
                                        }
                                    },
                                    onRemoveDraftItem: {
                                        var updatedList = draftItems
                                        updatedList.removeAll { $0.id == plannedItem.id }
                                        recomputeSanitizedDraftItems(for: currentContract, candidateItems: updatedList)
                                    }
                                )
                            } else {
                                unifiedRegularInstallmentRow(
                                    row: row,
                                    monthEndCash: monthEndCash
                                )
                            }
                        }
                    }
                    .padding(8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func unifiedRegularInstallmentRow(
        row: LoanProjectionTimelineRow,
        monthEndCash: Double
    ) -> some View {
        let isShadowed = row.status == .shadowed
        let outflowDouble = LoanProjectionEngine.toDouble(row.totalBudgetOutflow)
        let finalLoanBalDouble = LoanProjectionEngine.toDouble(row.finalBalance)
        let isNaturalPayoff = !isShadowed && finalLoanBalDouble <= 0.01

        HStack(spacing: 10) {
            Text(BRLFormatters.shortDate(row.date))
                .font(.caption.monospacedDigit())
                .frame(width: 112, alignment: .leading)

            HStack(spacing: 6) {
                Circle()
                    .fill(isShadowed ? Color.secondary.opacity(0.4) : Color(hex: "#3B82F6"))
                    .frame(width: 7, height: 7)
                Text(row.title)
                    .font(.caption.weight(isShadowed ? .regular : .medium))
                    .strikethrough(isShadowed)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(isShadowed ? "R$ 0,00 (Suprimida)" : BRLFormatters.currency(outflowDouble))
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(isShadowed ? .secondary : .primary)
                .frame(width: 165, alignment: .trailing)

            Text(BRLFormatters.currency(monthEndCash))
                .font(.caption.bold().monospacedDigit())
                .foregroundStyle(monthEndCash >= 0 ? Color(hex: "#10B981") : Color(hex: "#EF4444"))
                .frame(width: 185, alignment: .trailing)

            HStack(spacing: 5) {
                Spacer(minLength: 0)
                Text(BRLFormatters.currency(finalLoanBalDouble))
                    .font(.caption.bold().monospacedDigit())
                    .foregroundStyle(isNaturalPayoff ? Color(hex: "#10B981") : .primary)
                if isNaturalPayoff {
                    Text("QUITADO")
                        .font(.system(size: 9, weight: .heavy))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(Capsule().fill(Color(hex: "#10B981").opacity(0.20)))
                        .foregroundStyle(Color(hex: "#10B981"))
                }
            }
            .frame(width: 210, alignment: .trailing)

            Text(isShadowed ? "Já Quitado" : "Parcela Ativa")
                .font(.system(size: 10, weight: .semibold))
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(
                    Capsule().fill(isShadowed ? Color.secondary.opacity(0.14) : Color(hex: "#3B82F6").opacity(0.14))
                )
                .foregroundStyle(isShadowed ? Color.secondary : Color(hex: "#3B82F6"))
                .frame(width: 115, alignment: .trailing)
        }
        .opacity(isShadowed ? 0.48 : 1.0)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Color.primary.opacity(0.02))
        )
    }
}

// MARK: - Linha Unificada de Aporte Planejado (Modo Edição com Teto de Quitação vs Modo Visualização)

private struct UnifiedPlannedContributionRowView: View {
    @ObservedObject var store: FinancialDataStore
    let contract: CreditContract
    let item: PlannedAmortization
    let outcome: PlannedItemProjectionOutcome?
    let monthEndExpectedCash: Double
    let isEditingMode: Bool
    let maxAllowedForThisRow: (Date) -> Double
    let onUpdateDraftItem: (Date, Decimal, AmortizationFundingSource, AmortizationRecalculationMode) -> Void
    let onRemoveDraftItem: () -> Void

    @State private var editableDate: Date = Date()
    @State private var editableAmountText: String = ""

    var body: some View {
        let effectiveAmortDouble = LoanProjectionEngine.toDouble(outcome?.effectiveAmortization ?? item.amount)
        let remainingBalanceAfterDouble = LoanProjectionEngine.toDouble(outcome?.remainingBalanceAfter ?? .zero)
        let isPayoff = (outcome?.isFullPayoffStep ?? false) || remainingBalanceAfterDouble <= 0.01

        // Ajuste dinâmico do Saldo Esperado no Fim do Mês conforme o usuário digita um valor maior/menor na linha
        let liveTypedAmount = isEditingMode ? (BRLFormatters.parseAmount(editableAmountText) ?? effectiveAmortDouble) : effectiveAmortDouble
        let maxAllowed = isEditingMode ? max(effectiveAmortDouble, maxAllowedForThisRow(editableDate)) : effectiveAmortDouble
        let clampedLiveAmount = min(max(liveTypedAmount, 0.0), maxAllowed)
        let deltaFromCurrent = isEditingMode ? (clampedLiveAmount - effectiveAmortDouble) : 0.0
        let liveMonthEndCash = monthEndExpectedCash - deltaFromCurrent
        let liveLoanBalanceAfter = isEditingMode ? max(0.0, maxAllowed - clampedLiveAmount) : remainingBalanceAfterDouble
        let liveIsPayoff = isEditingMode ? (liveLoanBalanceAfter <= 0.01 && clampedLiveAmount > 0.01) : isPayoff

        HStack(spacing: 10) {
            // 1. Data
            if isEditingMode {
                DatePicker("", selection: $editableDate, displayedComponents: [.date])
                    .labelsHidden()
                    .frame(width: 112, alignment: .leading)
                    .onChange(of: editableDate) { _, newDate in
                        guard !store.calendar.isDate(newDate, inSameDayAs: item.date) else { return }
                        commitRowEdit(newDate: newDate)
                    }
            } else {
                Text(BRLFormatters.shortDate(item.date))
                    .font(.caption.bold().monospacedDigit())
                    .frame(width: 112, alignment: .leading)
            }

            // 2. Evento / Descrição
            HStack(spacing: 6) {
                Image(systemName: liveIsPayoff ? "checkmark.seal.fill" : "wand.and.stars")
                    .font(.caption)
                    .foregroundStyle(liveIsPayoff ? Color(hex: "#10B981") : Color(hex: "#6366F1"))
                Text(
                    liveIsPayoff
                        ? "Aporte Planejado — LIQUIDAÇÃO TOTAL (\(item.source.shortTitle))"
                        : "Aporte Planejado — Amortização Extra (\(item.source.shortTitle))"
                )
                .font(.caption.bold())
                .foregroundStyle(liveIsPayoff ? Color(hex: "#10B981") : Color(hex: "#6366F1"))
                .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // 3. Valor do Aporte (Editável com trava de quitação no modo Edição)
            if isEditingMode {
                HStack(spacing: 4) {
                    TextField("Valor (R$)", text: $editableAmountText)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption.bold().monospacedDigit())
                        .frame(width: 132)
                        .onChange(of: editableAmountText) { _, newVal in
                            if let parsed = BRLFormatters.parseAmount(newVal), parsed > maxAllowed + 0.005, maxAllowed > 0 {
                                editableAmountText = BRLFormatters.currency(maxAllowed)
                            }
                        }
                        .onSubmit {
                            commitRowEdit()
                        }
                    Button {
                        commitRowEdit()
                    } label: {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color(hex: "#6366F1"))
                    }
                    .buttonStyle(.borderless)
                    .help("Aplicar valor deste aporte")
                }
                .frame(width: 165, alignment: .trailing)
            } else {
                Text(BRLFormatters.currency(effectiveAmortDouble))
                    .font(.caption.bold().monospacedDigit())
                    .foregroundStyle(liveIsPayoff ? Color(hex: "#10B981") : Color(hex: "#6366F1"))
                    .frame(width: 165, alignment: .trailing)
            }

            // 4. Saldo Esperado no Fim do Mês (ajusta conforme coloca aporte maior)
            Text(BRLFormatters.currency(liveMonthEndCash))
                .font(.caption.bold().monospacedDigit())
                .foregroundStyle(liveMonthEndCash >= 0 ? Color(hex: "#10B981") : Color(hex: "#EF4444"))
                .frame(width: 185, alignment: .trailing)

            // 5. Saldo do Empréstimo Após Amortização + Destaque de Quitação
            HStack(spacing: 6) {
                Spacer(minLength: 0)
                Text(BRLFormatters.currency(liveLoanBalanceAfter))
                    .font(.caption.bold().monospacedDigit())
                    .foregroundStyle(liveIsPayoff ? Color(hex: "#10B981") : .primary)

                if liveIsPayoff {
                    Text("QUITAÇÃO TOTAL")
                        .font(.system(size: 9, weight: .heavy))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color(hex: "#10B981").opacity(0.22)))
                        .foregroundStyle(Color(hex: "#10B981"))
                }
            }
            .frame(width: 210, alignment: .trailing)

            // 6. Ação
            HStack(spacing: 6) {
                Spacer(minLength: 0)
                if isEditingMode {
                    Button(role: .destructive) {
                        onRemoveDraftItem()
                    } label: {
                        Label("Remover", systemImage: "trash")
                            .font(.caption2)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                } else {
                    Button {
                        store.confirmPlannedAmortizationPayment(
                            contractId: contract.id,
                            itemId: item.id,
                            accountId: contract.accountId,
                            paymentDate: item.date
                        )
                    } label: {
                        Text(liveIsPayoff ? "Confirmar Quitação" : "Confirmar Pagto.")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(hex: liveIsPayoff ? "#10B981" : "#6366F1"))
                    .controlSize(.mini)
                }
            }
            .frame(width: 115, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(liveIsPayoff ? Color(hex: "#10B981").opacity(0.12) : Color(hex: "#6366F1").opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(liveIsPayoff ? Color(hex: "#10B981").opacity(0.50) : Color(hex: "#6366F1").opacity(0.28), lineWidth: liveIsPayoff ? 1.4 : 1)
        )
        .onAppear {
            syncFields()
        }
        .onChange(of: item) { _, _ in
            syncFields()
        }
    }

    private func syncFields() {
        editableDate = item.date
        let shownAmt = LoanProjectionEngine.toDouble(outcome?.effectiveAmortization ?? item.amount)
        editableAmountText = BRLFormatters.currency(shownAmt)
    }

    private func commitRowEdit(newDate: Date? = nil) {
        let targetDate = newDate ?? editableDate
        let maxAllowed = maxAllowedForThisRow(targetDate)
        guard maxAllowed > 0.01 else { return }
        let parsedAmt = BRLFormatters.parseAmount(editableAmountText) ?? item.amountDouble
        guard parsedAmt > 0 else { return }
        let clamped = min(parsedAmt, maxAllowed)
        editableAmountText = BRLFormatters.currency(clamped)
        onUpdateDraftItem(
            targetDate,
            LoanProjectionEngine.toDecimal(clamped),
            item.source,
            item.mode
        )
    }
}
