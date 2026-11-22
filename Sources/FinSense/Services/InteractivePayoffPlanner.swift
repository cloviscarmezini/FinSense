import Foundation

public enum PendingSimulationTarget: Equatable, Sendable {
    case contract(id: UUID, name: String, kind: CreditContractKind)
    case debt(id: UUID, name: String)

    public var isDebt: Bool {
        if case .debt = self { return true }
        return false
    }
}

public enum PayoffIntensity: String, CaseIterable, Sendable {
    case aggressive
    case moderate
    case light

    public var displayTitle: String {
        switch self {
        case .aggressive: return "Agressivo"
        case .moderate: return "Moderado"
        case .light: return "Leve"
        }
    }

    public var surplusAllocationRatio: Double {
        switch self {
        case .aggressive: return 0.80
        case .moderate: return 0.50
        case .light: return 0.25
        }
    }

    public var summaryDescription: String {
        switch self {
        case .aggressive: return "Prioriza quitação no menor prazo usando ~80% da sobra livre mensal projetada"
        case .moderate: return "Equilíbrio saudável usando ~50% da sobra livre mensal sem apertar o mês"
        case .light: return "Ritmo suave usando ~25% da sobra livre mensal preservando folga máxima no caixa"
        }
    }

    public static func parse(from raw: String) -> PayoffIntensity? {
        let norm = raw.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR"))
            .lowercased()
        if norm.contains("agressiv") || norm.contains("rapido") || norm.contains("maximo") || norm.contains("intenso") {
            return .aggressive
        }
        if norm.contains("moderad") || norm.contains("equilibr") || norm.contains("medio") {
            return .moderate
        }
        if norm.contains("leve") || norm.contains("suave") || norm.contains("conservador") || norm.contains("lento") || norm.contains("baixo") {
            return .light
        }
        return nil
    }
}

/// Motor determinístico de planejamento interativo em 2 etapas para os botões fixos de "Simular Prazo":
/// 1) Identifica o alvo (Contrato vs Dívida), entende a diferença operacional e pergunta o ritmo (Agressivo / Moderado / Leve).
/// 2) Ao receber o ritmo, calcula um cronograma mês a mês ancorado SEMPRE no final de cada mês (`endOfMonth`),
///    considerando o impacto cumulativo nos meses futuros (amortizações anteriores, parcelas sombreadas e Saldo Previsto).
@MainActor
public enum InteractivePayoffPlanner {

    public struct ExtractedPromptMetadata {
        public let target: PendingSimulationTarget?
        public let askIntensityFirst: Bool
        public let cleanPrompt: String
    }

    public static func extractMetadata(from prompt: String, store: FinancialDataStore) -> ExtractedPromptMetadata {
        var clean = prompt
            .replacingOccurrences(of: "[NOVA SIMULAÇÃO DO SISTEMA]", with: "")
        var parsedType: String? = nil
        var parsedId: UUID? = nil
        var askPace = false

        if let typeMatch = matchBracketValue(tag: "TIPO", in: prompt) {
            parsedType = typeMatch.uppercased()
        }
        if let idMatch = matchBracketValue(tag: "ID", in: prompt) {
            parsedId = UUID(uuidString: idMatch)
        }
        if let modeMatch = matchBracketValue(tag: "MODO", in: prompt),
           modeMatch.uppercased() == "PERGUNTAR_RITMO" {
            askPace = true
        }

        if let regex = try? NSRegularExpression(pattern: "\\[(?:TIPO|MODO|ID):[^\\]]+\\]") {
            let ns = NSRange(clean.startIndex..<clean.endIndex, in: clean)
            clean = regex.stringByReplacingMatches(in: clean, options: [], range: ns, withTemplate: "")
        }
        clean = clean.trimmingCharacters(in: .whitespacesAndNewlines)

        var resolvedTarget: PendingSimulationTarget? = nil
        if parsedType == "CONTRATO", let uuid = parsedId,
           let contract = store.contracts.first(where: { $0.id == uuid && !$0.isSettled }) {
            resolvedTarget = .contract(id: contract.id, name: contract.name, kind: contract.kind)
        } else if parsedType == "DIVIDA", let uuid = parsedId,
                  let debt = store.activeDebts.first(where: { $0.id == uuid }) {
            resolvedTarget = .debt(id: debt.id, name: debt.name)
        } else if let uuid = parsedId {
            if let contract = store.contracts.first(where: { $0.id == uuid && !$0.isSettled }) {
                resolvedTarget = .contract(id: contract.id, name: contract.name, kind: contract.kind)
            } else if let debt = store.activeDebts.first(where: { $0.id == uuid }) {
                resolvedTarget = .debt(id: debt.id, name: debt.name)
            }
        }

        return ExtractedPromptMetadata(target: resolvedTarget, askIntensityFirst: askPace, cleanPrompt: clean)
    }

    /// Recupera o alvo da simulação a partir do histórico persistido caso a memória em RAM tenha sido reiniciada.
    public static func recoverTargetFromHistory(_ history: [ChatMessage], store: FinancialDataStore) -> PendingSimulationTarget? {
        for msg in history.reversed() {
            if msg.role == .tool, msg.toolName == "interactive_simulation_context",
               let data = msg.content.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let kind = obj["kind"] as? String,
               let idStr = obj["id"] as? String,
               let uuid = UUID(uuidString: idStr) {
                if kind == "debt", let debt = store.activeDebts.first(where: { $0.id == uuid }) {
                    return .debt(id: debt.id, name: debt.name)
                }
                if kind == "contract", let contract = store.contracts.first(where: { $0.id == uuid && !$0.isSettled }) {
                    return .contract(id: contract.id, name: contract.name, kind: contract.kind)
                }
            }
            if msg.role == .user {
                let meta = extractMetadata(from: msg.content, store: store)
                if let target = meta.target {
                    return target
                }
            }
        }
        return nil
    }

    private static func matchBracketValue(tag: String, in text: String) -> String? {
        let pattern = "\\[\(tag):([^\\]]+)\\]"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges > 1 else {
            return nil
        }
        return ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Garante uma lista de parcelas futuras não pagas caso o contrato ainda não possua transações materializadas no banco.
    public static func unresolvedInstallments(for contract: CreditContract, in store: FinancialDataStore) -> [FinancialTransaction] {
        let unpaid = store.transactions.filter {
            $0.linkedContractId == contract.id &&
            $0.installmentIndex != nil &&
            !$0.isPaid
        }
        if !unpaid.isEmpty {
            return unpaid
        }
        let rem = store.remainingInstallmentsCount(for: contract)
        guard rem > 0 else { return [] }

        let cal = store.calendar
        let paid = store.paidTransactionsCount(forContract: contract)
        let schedByNum = Dictionary(uniqueKeysWithValues: (contract.scheduledInstallments ?? []).map { ($0.installmentNumber, $0) })
        let baseAnchor = cal.date(byAdding: .month, value: 1, to: store.effectiveCurrentDate) ?? store.effectiveCurrentDate
        let day = min(max(contract.billingDay, 1), 28)

        var synthetic: [FinancialTransaction] = []
        synthetic.reserveCapacity(rem)
        for idx in 0..<rem {
            let instNum = paid + idx + 1
            let monthDate = cal.date(byAdding: .month, value: idx, to: baseAnchor) ?? baseAnchor
            var comps = cal.dateComponents([.year, .month], from: monthDate)
            comps.day = day
            let txDate = cal.date(from: comps) ?? monthDate
            let amount = schedByNum[instNum]?.amount ?? contract.installmentAmount
            synthetic.append(
                FinancialTransaction(
                    name: "\(contract.name) (\(instNum)/\(contract.totalInstallments))",
                    amount: amount,
                    date: txDate,
                    type: .expense,
                    isPaid: false,
                    categoryId: contract.categoryId,
                    accountId: contract.accountId,
                    installmentIndex: instNum,
                    installmentTotal: contract.totalInstallments,
                    linkedContractId: contract.id
                )
            )
        }
        return synthetic
    }

    public static func simulateProjectionSafe(
        for contract: CreditContract,
        draftPlan: AmortizationPlan?,
        in store: FinancialDataStore
    ) -> LoanProjectionResult? {
        let existingUnpaid = store.transactions.filter {
            $0.linkedContractId == contract.id &&
            $0.installmentIndex != nil &&
            !$0.isPaid
        }
        if !existingUnpaid.isEmpty {
            return draftPlan != nil
                ? store.simulateAmortizationPlanPreview(for: contract.id, draftPlan: draftPlan)
                : store.loanProjection(for: contract.id)
        }
        let fallbackUnpaid = unresolvedInstallments(for: contract, in: store)
        guard !fallbackUnpaid.isEmpty else {
            return draftPlan != nil
                ? store.simulateAmortizationPlanPreview(for: contract.id, draftPlan: draftPlan)
                : store.loanProjection(for: contract.id)
        }
        let effectivePlan = draftPlan ?? store.amortizationPlan(for: contract.id)
        return LoanProjectionEngine.simulate(
            contract: contract,
            unpaidInstallmentTransactions: fallbackUnpaid,
            currentRealBalanceDouble: store.currentOutstandingBalance(for: contract),
            plan: effectivePlan,
            calendar: store.calendar
        )
    }

    // MARK: - Etapa 1: Clarificação do Ritmo (Agressivo / Moderado / Leve)

    public static func buildClarificationPayload(
        target: PendingSimulationTarget,
        store: FinancialDataStore
    ) -> [String: Any] {
        let monthEnd = store.endOfMonth(for: store.selectedMonth)
        let monthEndStr = BRLFormatters.shortDate(monthEnd)
        let kpi = store.buildUnifiedFinancialKPISummary(referenceDate: store.selectedMonth, isAnnual: false)
        let saldoPrevistoFimMes = kpi.isPast ? kpi.projectedAccountBalance : kpi.balanceIfAllBudgetsConsumed

        var payload: [String: Any] = [
            "status": "awaiting_intensity_choice",
            "dataReferenciaFechamentoMes": monthEndStr,
            "saldoPrevistoNaDataReferencia": BRLFormatters.currency(saldoPrevistoFimMes),
            "instrucaoImportanteEtapa1": "NÃO informe nem estime valores em R$/mês agora; apenas pergunte se o usuário deseja ritmo Agressivo, Moderado ou Leve para então calcular os valores reais apenas nos meses em que houver folga no fechamento do mês.",
            "perfisRitmoSemValores": [
                "agressivo": "Prioriza quitar no menor prazo possível, alocando a maior parte da folga disponível exclusivamente nos meses com fechamento positivo e respeitando os meses futuros.",
                "moderado": "Equilíbrio entre prazo de quitação e conforto no orçamento, separando parte moderada nos meses positivos sem comprometer contas nem reservas.",
                "leve": "Ritmo conservador e suave, reservando apenas uma pequena parcela da sobra positiva nos meses favoráveis para manter folga máxima no caixa."
            ]
        ]

        switch target {
        case .contract(let id, let name, let kind):
            let c = store.contracts.first(where: { $0.id == id })
            let bal = c.map { store.currentOutstandingBalance(for: $0) } ?? 0.0
            let rem = c.map { store.remainingInstallmentsCount(for: $0) } ?? 0
            let inst = c?.installmentAmount ?? 0.0
            payload["tipoAlvo"] = kind == .loan ? "Empréstimo (Amortização com Parcelas)" : "Financiamento (Amortização com Parcelas)"
            payload["estrategiaObrigatoria"] = "Plano de amortização mensal sobre parcelas e saldo devedor"
            payload["nome"] = name
            payload["numeroContrato"] = c?.contractNumber ?? ""
            payload["saldoDevedorAtual"] = BRLFormatters.currency(bal)
            payload["parcelaAtual"] = BRLFormatters.currency(inst)
            payload["parcelasRestantes"] = rem

        case .debt(let id, let name):
            let d = store.activeDebts.first(where: { $0.id == id })
            let amt = d?.originalAmount ?? 0.0
            payload["tipoAlvo"] = "Dívida em Aberto (NÃO é empréstimo/financiamento)"
            payload["estrategiaObrigatoria"] = "Plano progressivo de guardar dinheiro pouco a pouco nos meses em que houver folga até atingir o valor total para quitar"
            payload["nome"] = name
            payload["valorDaDivida"] = BRLFormatters.currency(amt)
        }
        return payload
    }

    public static func buildClarificationFallbackMarkdown(
        target: PendingSimulationTarget,
        store: FinancialDataStore
    ) -> String {
        let monthEndStr = BRLFormatters.shortDate(store.endOfMonth(for: store.selectedMonth))
        let kpi = store.buildUnifiedFinancialKPISummary(referenceDate: store.selectedMonth, isAnnual: false)
        let saldoPrevisto = kpi.isPast ? kpi.projectedAccountBalance : kpi.balanceIfAllBudgetsConsumed

        let introHeader: String
        let strategyExplanation: String
        switch target {
        case .contract(let id, let name, let kind):
            let c = store.contracts.first(where: { $0.id == id })
            let bal = c.map { store.currentOutstandingBalance(for: $0) } ?? 0.0
            let rem = c.map { store.remainingInstallmentsCount(for: $0) } ?? 0
            let inst = c?.installmentAmount ?? 0.0
            let kindTitle = kind == .loan ? "Empréstimo" : "Financiamento"
            introHeader = "Identifiquei no seu banco local o **\(kindTitle): \(name)** (Saldo Devedor de **\(BRLFormatters.currency(bal))**, \(rem) parcelas de \(BRLFormatters.currency(inst)))."
            strategyExplanation = "Como se trata de um contrato com parcelas e juros mensais, vou montar um **plano de amortização mês a mês** usando o fechamento de cada mês a partir de **\(monthEndStr)** e considerando o impacto acumulado nos meses seguintes."

        case .debt(let id, let name):
            let d = store.activeDebts.first(where: { $0.id == id })
            let amt = d?.originalAmount ?? 0.0
            introHeader = "Identifiquei no seu banco local a dívida em aberto **\(name)** no valor de **\(BRLFormatters.currency(amt))**."
            strategyExplanation = "Como se trata de uma dívida em aberto sem parcelas fixas automáticas, vou estruturar um **plano gradual de guardar dinheiro pouco a pouco** considerando apenas os meses em que seu **Saldo Previsto no fechamento de cada mês** (a partir de **\(monthEndStr)**) realmente permitir acumular sem comprometer suas despesas nem os meses futuros."
        }

        return """
        ### 🎯 Antes de calcular as datas e valores

        \(introHeader)

        \(strategyExplanation)

        📊 **Referência no Banco Local (`\(monthEndStr)`):**
        • **Saldo Previsto em \(monthEndStr):** \(BRLFormatters.currency(saldoPrevisto))

        Qual ritmo de plano você prefere antes de eu calcular os valores mês a mês?
        • **Agressivo:** prioriza quitar no menor prazo possível, alocando a maior parte da folga disponível exclusivamente nos meses positivos.
        • **Moderado:** equilíbrio entre velocidade de quitação e conforto no orçamento mensal.
        • **Leve:** avança suavemente nos meses com saldo disponível, preservando folga máxima no caixa.

        Selecione **Plano Agressivo**, **Plano Moderado** ou **Plano Leve** para eu consultar todos os meses futuros e gerar o cronograma completo com datas e valores reais.
        """
    }

    // MARK: - Etapa 2: Cálculo Mês a Mês Ancorado no Final do Mês com Impacto Futuro Cumulativo

    public static func simulateDetailedPlan(
        target: PendingSimulationTarget,
        intensity: PayoffIntensity,
        store: FinancialDataStore
    ) -> (payload: [String: Any], markdown: String) {
        switch target {
        case .contract(let id, _, _):
            if let contract = store.contracts.first(where: { $0.id == id && !$0.isSettled }) {
                return simulateContractInteractivePlan(contract: contract, intensity: intensity, store: store)
            }
            return (["status": "not_found"], "Não localizei esse contrato ativo no banco local.")
        case .debt(let id, _):
            if let debt = store.activeDebts.first(where: { $0.id == id }) {
                return simulateDebtSavingsPlan(debt: debt, intensity: intensity, store: store)
            }
            return (["status": "not_found"], "Não localizei essa dívida em aberto (`isPaid == false`) no banco local.")
        }
    }

    private static func simulateDebtSavingsPlan(
        debt: DebtItem,
        intensity: PayoffIntensity,
        store: FinancialDataStore
    ) -> (payload: [String: Any], markdown: String) {
        let cal = store.calendar
        let startMonth = store.selectedMonth
        if let horizon = cal.date(byAdding: .month, value: 62, to: startMonth) {
            store.ensureRecurringTransactionsMaterialized(upTo: horizon)
        }

        let targetAmount = debt.originalAmount
        let ratio = intensity.surplusAllocationRatio
        let baseKPI = store.buildUnifiedFinancialKPISummary(referenceDate: startMonth, isAnnual: false)
        // Protege investimentos consolidados sem deixar Saldo Previsto em conta ficar negativo em nenhum mês futuro
        let protectedReserve = store.consolidatedInvestmentsBalance
        let firstMonthEnd = store.endOfMonth(for: startMonth)
        let baseFirstSaldoPrevisto = baseKPI.isPast ? baseKPI.projectedAccountBalance : baseKPI.balanceIfAllBudgetsConsumed

        struct StepRow {
            let monthIndex: Int
            let dateStr: String
            let amountSaved: Double
            let cumulativeSaved: Double
            let remainingDebt: Double
            let saldoPrevistoBeforeReserve: Double
            let saldoPrevistoAfterReserve: Double
        }

        // Calcula folga habitual média (excluindo receitas extraordinárias pontuais como 13º) caso meses futuros distantes não tenham lançamentos
        let (fallbackHabitualIncome, fallbackHabitualExpense, fallbackHabitualSurplus): (Double, Double, Double) = {
            var incTotal = 0.0
            var expTotal = 0.0
            var surTotal = 0.0
            var count = 0
            for offset in 0..<12 {
                if let m = cal.date(byAdding: .month, value: offset, to: startMonth) {
                    let k = store.buildUnifiedFinancialKPISummary(referenceDate: m, isAnnual: false)
                    if k.habitualIncome > 0 {
                        incTotal += k.habitualIncome
                        expTotal += k.totalPlannedExpenses
                        surTotal += max(0.0, k.habitualIncome - k.totalPlannedExpenses)
                        count += 1
                    }
                }
            }
            if count > 0 {
                let dCount = Double(count)
                return (incTotal / dCount, expTotal / dCount, max(0.0, surTotal / dCount))
            }
            return (
                baseKPI.habitualIncome,
                baseKPI.totalPlannedExpenses,
                max(0.0, baseKPI.habitualIncome - baseKPI.totalPlannedExpenses)
            )
        }()

        // Pré-calcula a linha de base de Saldo Previsto mês a mês nos próximos 60 meses
        let totalHorizon = 60
        var monthDates: [Date] = []
        var monthKPIs: [UnifiedFinancialKPISummary] = []
        var baseSaldoAtMonth: [Double] = []
        var monthlySurplusAtMonth: [Double] = []
        var unmaterializedDrift = 0.0

        for idx in 0..<totalHorizon {
            guard let mDate = cal.date(byAdding: .month, value: idx, to: startMonth) else { break }
            let kpi = store.buildUnifiedFinancialKPISummary(referenceDate: mDate, isAnnual: false)
            let recordedSurplus = kpi.surplusAfterPlanning
            let effectiveSurplus: Double = {
                if kpi.projectedIncome > 0 {
                    return max(0.0, recordedSurplus)
                }
                if kpi.totalPlannedExpenses > 0 {
                    return max(0.0, fallbackHabitualIncome - kpi.totalPlannedExpenses)
                }
                return fallbackHabitualSurplus
            }()

            if idx >= 1 && kpi.projectedIncome <= 0 {
                let missingExp = kpi.totalPlannedExpenses <= 0 ? fallbackHabitualExpense : 0.0
                unmaterializedDrift += max(0.0, fallbackHabitualIncome - missingExp)
            }

            let rawSaldo = kpi.isPast ? kpi.projectedAccountBalance : kpi.balanceIfAllBudgetsConsumed
            monthDates.append(mDate)
            monthKPIs.append(kpi)
            baseSaldoAtMonth.append(rawSaldo + unmaterializedDrift)
            monthlySurplusAtMonth.append(effectiveSurplus)
        }

        var rows: [StepRow] = []
        var cumulativeSaved = 0.0
        var payoffDateStr: String? = nil

        for k in 0..<monthDates.count {
            guard cumulativeSaved + 0.01 < targetAmount else { break }
            let monthDate = monthDates[k]
            let monthEnd = store.endOfMonth(for: monthDate)
            let baseSaldoAtK = baseSaldoAtMonth[k]
            let saldoAvailableBeforeStep = baseSaldoAtK - cumulativeSaved

            // Garante impacto futuro real: não guarda valor se reduzir Saldo Previsto do mês k OU dos próximos 12 meses abaixo de protectedReserve
            let lookaheadEnd = min(k + 12, baseSaldoAtMonth.count)
            let minFutureSaldoBeforeStep = (k..<lookaheadEnd)
                .map { baseSaldoAtMonth[$0] - cumulativeSaved }
                .min() ?? saldoAvailableBeforeStep

            let maxSafeIncludingFuture = max(0.0, minFutureSaldoBeforeStep - protectedReserve)
            let effectiveSurplus = monthlySurplusAtMonth[k]

            // Se o mês teve déficit operacional, mas o acumulado positivo em conta (após futuros) já cobre reserva com segurança,
            // ainda respeita estritamente `maxSafeIncludingFuture`; só guarda quando efetivamente sobra e mantém o futuro positivo.
            var desiredSlice = (effectiveSurplus * ratio * 100.0).rounded() / 100.0
            if desiredSlice <= 0.01 && maxSafeIncludingFuture >= 100.0 && monthKPIs[k].surplusAfterPlanning > 0 {
                desiredSlice = (maxSafeIncludingFuture * ratio * 100.0).rounded() / 100.0
            }

            let cappedBySafety = min(desiredSlice, maxSafeIncludingFuture)
            let remainingNeeded = max(0.0, targetAmount - cumulativeSaved)
            let actualSaved = min(remainingNeeded, max(0.0, (cappedBySafety * 100.0).rounded() / 100.0))

            if actualSaved < 10.0 && remainingNeeded > 10.0 {
                rows.append(
                    StepRow(
                        monthIndex: k + 1,
                        dateStr: BRLFormatters.shortDate(monthEnd),
                        amountSaved: 0.0,
                        cumulativeSaved: cumulativeSaved,
                        remainingDebt: remainingNeeded,
                        saldoPrevistoBeforeReserve: saldoAvailableBeforeStep,
                        saldoPrevistoAfterReserve: saldoAvailableBeforeStep
                    )
                )
                continue
            }

            cumulativeSaved = ((cumulativeSaved + actualSaved) * 100.0).rounded() / 100.0
            let remAfter = max(0.0, ((targetAmount - cumulativeSaved) * 100.0).rounded() / 100.0)
            let saldoAfter = ((baseSaldoAtK - cumulativeSaved) * 100.0).rounded() / 100.0
            let dStr = BRLFormatters.shortDate(monthEnd)

            rows.append(
                StepRow(
                    monthIndex: k + 1,
                    dateStr: dStr,
                    amountSaved: actualSaved,
                    cumulativeSaved: cumulativeSaved,
                    remainingDebt: remAfter,
                    saldoPrevistoBeforeReserve: saldoAvailableBeforeStep,
                    saldoPrevistoAfterReserve: saldoAfter
                )
            )

            if remAfter <= 0.01 {
                payoffDateStr = dStr
                break
            }
        }

        let activeSavingRows = rows.filter { $0.amountSaved > 0.01 }
        let avgActiveMonthlySave = activeSavingRows.map(\.amountSaved).reduce(0.0, +) / Double(max(activeSavingRows.count, 1))
        let totalMonthsNeeded = rows.count

        let scheduleJson: [[String: Any]] = {
            let sliced = rows.count > 16 ? Array(rows.prefix(14)) + Array(rows.suffix(2)) : rows
            return sliced.map { r in
                [
                    "dataFechamentoMes": r.dateStr,
                    "valorAGuardar": BRLFormatters.currency(r.amountSaved),
                    "totalAcumulado": BRLFormatters.currency(r.cumulativeSaved),
                    "saldoFaltanteDivida": BRLFormatters.currency(r.remainingDebt),
                    "saldoPrevistoAposReserva": BRLFormatters.currency(r.saldoPrevistoAfterReserve)
                ]
            }
        }()

        let payload: [String: Any] = [
            "status": "success",
            "estrategia": "Plano gradual de guardar dinheiro pouco a pouco (Dívida em aberto, NÃO é empréstimo)",
            "ritmo": intensity.displayTitle,
            "dividaNome": debt.name,
            "valorDivida": BRLFormatters.currency(targetAmount),
            "dataInicioReferencia": BRLFormatters.shortDate(firstMonthEnd),
            "saldoPrevistoInicialFimMes": BRLFormatters.currency(baseFirstSaldoPrevisto),
            "sobraMensalBase": BRLFormatters.currency(baseKPI.surplusAfterPlanning),
            "dataQuitacaoPossivel": payoffDateStr ?? "Mais de 60 meses sem nova receita/corte",
            "mesesTotais": payoffDateStr != nil ? totalMonthsNeeded : -1,
            "mesesComReservaEfetiva": activeSavingRows.count,
            "mediaNosMesesPositivos": BRLFormatters.currency(avgActiveMonthlySave),
            "cronogramaReserva": scheduleJson
        ]

        var md = """
        ### 💎 Plano \(intensity.displayTitle) para Quitar Dívida: \(debt.name)

        • **Valor em Aberto (`isPaid == false`):** **\(BRLFormatters.currency(targetAmount))**
        • **Estratégia:** Guardar dinheiro pouco a pouco no fechamento de cada mês (a partir de **\(BRLFormatters.shortDate(firstMonthEnd))**) apenas nos meses em que o **Saldo Previsto** e o impacto nos meses seguintes permanecerem no positivo.
        • **Base Inicial (\(BRLFormatters.shortDate(firstMonthEnd))):** Saldo Previsto de **\(BRLFormatters.currency(baseFirstSaldoPrevisto))** · Sobra Planejada de **\(BRLFormatters.currency(baseKPI.surplusAfterPlanning))**

        """

        if let payoffDateStr {
            md += "🏁 **Data prevista para quitação integral:** **\(payoffDateStr)** _(em **\(totalMonthsNeeded) \(totalMonthsNeeded == 1 ? "mês" : "meses")** no horizonte, sendo **\(activeSavingRows.count) \(activeSavingRows.count == 1 ? "mês" : "meses")** com reserva efetiva e média de **\(BRLFormatters.currency(avgActiveMonthlySave))/mês** nos meses positivos)_.\n\n"
            md += "#### 📅 Cronograma Mês a Mês (Fechamento do Mês + Impacto Futuro):\n"
            for r in rows.prefix(24) {
                if r.amountSaved <= 0.01 {
                    md += "• **\(r.dateStr):** Sem reserva possível neste mês *(Saldo Previsto projetado: \(BRLFormatters.currency(r.saldoPrevistoBeforeReserve)))*\n"
                } else if r.remainingDebt <= 0.01 {
                    md += "• **\(r.dateStr) 🏁 Quitação:** Guardar **\(BRLFormatters.currency(r.amountSaved))** · Total Acumulado: **\(BRLFormatters.currency(r.cumulativeSaved))** · Falta: **R$ 0,00** · Saldo Previsto após reserva: **\(BRLFormatters.currency(r.saldoPrevistoAfterReserve))**\n"
                } else {
                    md += "• **\(r.dateStr):** Guardar **\(BRLFormatters.currency(r.amountSaved))** · Acumulado: **\(BRLFormatters.currency(r.cumulativeSaved))** · Falta: **\(BRLFormatters.currency(r.remainingDebt))** · Saldo Previsto após reserva: **\(BRLFormatters.currency(r.saldoPrevistoAfterReserve))**\n"
                }
            }
            if rows.count > 24, let last = rows.last {
                md += "\n_...demais meses seguem no mesmo ritmo até a quitação final em **\(last.dateStr)**._\n"
            }
        } else {
            let maxAcc = rows.last?.cumulativeSaved ?? 0.0
            md += "⚠️ **Atenção:** Com o fluxo atual projetado para os próximos 60 meses, considerando a proteção do Saldo Previsto positivo nos meses futuros, o máximo acumulável automaticamente seria **\(BRLFormatters.currency(maxAcc))** (abaixo dos **\(BRLFormatters.currency(targetAmount))** necessários).\n"
            md += "• **Próximo passo recomendado:** Podemos revisar cortes em despesas variáveis ou verificar reservas para viabilizar os aportes positivos."
        }

        return (payload, md)
    }

    private static func simulateContractInteractivePlan(
        contract: CreditContract,
        intensity: PayoffIntensity,
        store: FinancialDataStore
    ) -> (payload: [String: Any], markdown: String) {
        let cal = store.calendar
        let startMonth = store.selectedMonth
        let prevRem = max(store.remainingInstallmentsCount(for: contract), 1)
        let horizonMonths = min(prevRem + 6, 120)
        if let horizonDate = cal.date(byAdding: .month, value: horizonMonths, to: startMonth) {
            store.ensureRecurringTransactionsMaterialized(upTo: horizonDate)
        }

        let initialBalance = store.currentOutstandingBalance(for: contract)
        let ratio = intensity.surplusAllocationRatio
        let firstMonthEnd = store.endOfMonth(for: startMonth)
        let baseKPI = store.buildUnifiedFinancialKPISummary(referenceDate: startMonth, isAnnual: false)
        let baseFirstSaldoPrevisto = baseKPI.isPast ? baseKPI.projectedAccountBalance : baseKPI.balanceIfAllBudgetsConsumed

        let hasPersistedUnpaid = !store.transactions.filter {
            $0.linkedContractId == contract.id && $0.installmentIndex != nil && !$0.isPaid
        }.isEmpty
        let syntheticInstallments = hasPersistedUnpaid ? [] : unresolvedInstallments(for: contract, in: store)

        // Exclui eventuais parcelas deste contrato no mês base para calcular a folga operacional recorrente antes do contrato
        let baseContractInstallmentsInStartMonth = store.transactions
            .filter { $0.linkedContractId == contract.id && store.isInMonth($0.date, monthReference: startMonth) && !$0.ignoreInConsolidated }
            .reduce(0.0) { $0 + $1.amount }
        let baseLivingNetWithoutContract = max(0.0, baseKPI.surplusAfterPlanning + baseContractInstallmentsInStartMonth)

        let protectedReserve = store.consolidatedInvestmentsBalance + 500.0
        var builtItems: [PlannedAmortization] = []
        var cumulativeCashSpent = 0.0
        var unmaterializedLivingNetAccumulated = 0.0
        var syntheticInstallmentsPaidAccumulated = 0.0
        var unmaterializedByStepEnd: [UUID: Double] = [:]

        // Construção iterativa considerando o impacto REAL de cada amortização anterior nos meses seguintes
        let maxSteps = min(prevRem, 96)
        for k in 0..<maxSteps {
            guard let monthDate = cal.date(byAdding: .month, value: k, to: startMonth) else { break }
            let monthEnd = store.endOfMonth(for: monthDate)

            // Recalcula projeção com todos os aportes já inseridos até o mês k-1
            let draftSoFar = AmortizationPlan(
                contractId: contract.id,
                generationMode: .manual,
                defaultRecalculationMode: .reduceTerm,
                items: builtItems
            )
            let projSoFar = simulateProjectionSafe(for: contract, draftPlan: builtItems.isEmpty ? nil : draftSoFar, in: store)
            let remainingContractBal: Double = {
                if let projSoFar {
                    if builtItems.isEmpty {
                        return LoanProjectionEngine.toDouble(projSoFar.currentRealBalance)
                    }
                    let lastBalanceBeforeCutoff = projSoFar.timeline
                        .filter { $0.date <= monthEnd }
                        .last?.finalBalance
                    return LoanProjectionEngine.toDouble(lastBalanceBeforeCutoff ?? projSoFar.projectedFinalBalanceAfterPlan)
                }
                return initialBalance
            }()

            if remainingContractBal <= 0.01 {
                break
            }

            let monthKPI = store.buildUnifiedFinancialKPISummary(referenceDate: monthDate, isAnnual: false)
            // Parcelas já sombreadas em meses anteriores liberam caixa futuro!
            let shadowedIds = projSoFar?.shadowedInstallmentTransactionIds ?? []
            let shadowedSavingInThisMonth: Double = store.transactions
                .filter { shadowedIds.contains($0.id) && store.isInMonth($0.date, monthReference: monthDate) }
                .reduce(0.0) { $0 + $1.amount }

            let activeSyntheticInThisMonth: Double = syntheticInstallments
                .filter { !shadowedIds.contains($0.id) && store.isInMonth($0.date, monthReference: monthDate) }
                .reduce(0.0) { $0 + $1.amount }

            if !hasPersistedUnpaid {
                syntheticInstallmentsPaidAccumulated += activeSyntheticInThisMonth
            }

            if k >= 1 && monthKPI.projectedIncome <= 0 {
                unmaterializedLivingNetAccumulated += baseLivingNetWithoutContract
            }

            let effectiveMonthlySurplus: Double = {
                if monthKPI.projectedIncome > 0 {
                    return max(0.0, monthKPI.surplusAfterPlanning + shadowedSavingInThisMonth - activeSyntheticInThisMonth)
                }
                // Quando meses futuros não têm salário materializado ainda, usa folga líquida base descontando parcela ativa não sombreada
                let activeContractInMonth = hasPersistedUnpaid
                    ? max(0.0, contract.installmentAmount - shadowedSavingInThisMonth)
                    : activeSyntheticInThisMonth
                return max(0.0, baseLivingNetWithoutContract - activeContractInMonth)
            }()

            var candidateExtra = (effectiveMonthlySurplus * ratio * 100.0).rounded() / 100.0
            candidateExtra = min(candidateExtra, remainingContractBal)

            let expectedCashBeforeStep: Double = {
                if hasPersistedUnpaid {
                    return store.expectedMonthEndCashBalance(
                        for: monthEnd,
                        contractId: contract.id,
                        draftPlan: draftSoFar,
                        draftProjection: projSoFar
                    ) + unmaterializedLivingNetAccumulated
                }
                let baseMonthSaldo = monthKPI.isPast ? monthKPI.projectedAccountBalance : monthKPI.balanceIfAllBudgetsConsumed
                return baseMonthSaldo + unmaterializedLivingNetAccumulated - syntheticInstallmentsPaidAccumulated - cumulativeCashSpent
            }()

            // Garante impacto nos meses seguintes (evita amortizar em dezembro se janeiro/fevereiro entrariam em déficit)
            var minFutureCash = expectedCashBeforeStep
            var futureDrift = unmaterializedLivingNetAccumulated
            for offset in 1...4 {
                guard let futureMonth = cal.date(byAdding: .month, value: offset, to: monthDate) else { break }
                let futureEnd = store.endOfMonth(for: futureMonth)
                let fKPI = store.buildUnifiedFinancialKPISummary(referenceDate: futureMonth, isAnnual: false)
                if fKPI.projectedIncome <= 0 {
                    futureDrift += baseLivingNetWithoutContract
                }
                let futureCash: Double = {
                    if hasPersistedUnpaid {
                        return store.expectedMonthEndCashBalance(
                            for: futureEnd,
                            contractId: contract.id,
                            draftPlan: draftSoFar,
                            draftProjection: projSoFar
                        ) + futureDrift
                    }
                    let fBase = fKPI.isPast ? fKPI.projectedAccountBalance : fKPI.balanceIfAllBudgetsConsumed
                    let futureSynthDue = syntheticInstallments
                        .filter { !shadowedIds.contains($0.id) && $0.date > monthEnd && $0.date <= futureEnd }
                        .reduce(0.0) { $0 + $1.amount }
                    return fBase + futureDrift - syntheticInstallmentsPaidAccumulated - futureSynthDue - cumulativeCashSpent
                }()
                minFutureCash = min(minFutureCash, futureCash)
            }

            let maxSafeFromCash = max(0.0, minFutureCash - protectedReserve)
            if candidateExtra > maxSafeFromCash {
                candidateExtra = (maxSafeFromCash * 100.0).rounded() / 100.0
            }

            if candidateExtra < 25.0 {
                continue
            }

            cumulativeCashSpent += candidateExtra
            let itemId = UUID()
            unmaterializedByStepEnd[itemId] = unmaterializedLivingNetAccumulated - syntheticInstallmentsPaidAccumulated
            builtItems.append(
                PlannedAmortization(
                    id: itemId,
                    contractId: contract.id,
                    date: monthEnd,
                    amount: LoanProjectionEngine.toDecimal(candidateExtra),
                    source: .cash,
                    mode: .reduceTerm,
                    status: .pending,
                    notes: "Simulação \(intensity.displayTitle)"
                )
            )
        }

        let finalPlan = AmortizationPlan(
            contractId: contract.id,
            generationMode: .manual,
            defaultRecalculationMode: .reduceTerm,
            items: builtItems
        )
        let finalProj = simulateProjectionSafe(for: contract, draftPlan: finalPlan, in: store)

        struct ContractScheduleRow {
            let dateStr: String
            let amortized: Double
            let remainingContractAfter: Double
            let saldoPrevistoAfter: Double
            let isPayoffStep: Bool
        }

        var rows: [ContractScheduleRow] = []
        var runningCumulativeAmortized = 0.0
        for item in builtItems {
            let outcome = finalProj?.plannedItemOutcomes[item.id]
            let effectiveAmort = outcome.map { LoanProjectionEngine.toDouble($0.effectiveAmortization) } ?? item.amountDouble
            guard effectiveAmort > 0.01 else { continue }
            runningCumulativeAmortized += effectiveAmort
            let remBal = outcome.map { LoanProjectionEngine.toDouble($0.remainingBalanceAfter) } ?? max(0.0, initialBalance - runningCumulativeAmortized)
            let isPayoff = (outcome?.isFullPayoffStep == true) || remBal <= 0.01
            let stepNetDrift = unmaterializedByStepEnd[item.id] ?? 0.0

            let saldoPrevistoAfter: Double = {
                if hasPersistedUnpaid {
                    return store.expectedMonthEndCashBalance(
                        for: item.date,
                        contractId: contract.id,
                        draftPlan: finalPlan,
                        draftProjection: finalProj
                    ) + stepNetDrift
                }
                let k = store.buildUnifiedFinancialKPISummary(referenceDate: item.date, isAnnual: false)
                let baseS = k.isPast ? k.projectedAccountBalance : k.balanceIfAllBudgetsConsumed
                return baseS + stepNetDrift - runningCumulativeAmortized
            }()

            rows.append(
                ContractScheduleRow(
                    dateStr: BRLFormatters.shortDate(item.date),
                    amortized: effectiveAmort,
                    remainingContractAfter: remBal,
                    saldoPrevistoAfter: saldoPrevistoAfter,
                    isPayoffStep: isPayoff
                )
            )
        }

        let origMonths = finalProj?.originalRemainingMonths ?? prevRem
        let newMonths = finalProj?.projectedActiveMonths ?? max(1, prevRem - rows.count)
        let monthsSaved = finalProj?.monthsSaved ?? max(0, origMonths - newMonths)
        let interestSaved = finalProj.map { LoanProjectionEngine.toDouble($0.totalInterestSaved) } ?? 0.0
        let payoffDate = rows.last(where: { $0.isPayoffStep })?.dateStr
            ?? finalProj.map { BRLFormatters.shortDate($0.projectedMaturityDate) }
            ?? BRLFormatters.shortDate(firstMonthEnd)
        let origMaturity = finalProj.map { BRLFormatters.shortDate($0.originalMaturityDate) } ?? "-"

        let scheduleJson: [[String: Any]] = {
            let sliced = rows.count > 14 ? Array(rows.prefix(12)) + Array(rows.suffix(2)) : rows
            return sliced.map { r in
                [
                    "dataFechamentoMes": r.dateStr,
                    "amortizacaoExtra": BRLFormatters.currency(r.amortized),
                    "saldoDevedorRestante": BRLFormatters.currency(r.remainingContractAfter),
                    "saldoPrevistoAposAmortizacao": BRLFormatters.currency(r.saldoPrevistoAfter),
                    "quitacaoFinalNesteMes": r.isPayoffStep
                ]
            }
        }()

        let kindTitle = contract.kind == .loan ? "Empréstimo" : "Financiamento"
        let payload: [String: Any] = [
            "status": "success",
            "estrategia": "amortizacao_parcelada_mensal",
            "ritmo": intensity.displayTitle,
            "contratoNome": contract.name,
            "contratoTipo": kindTitle,
            "numeroContrato": contract.contractNumber ?? "",
            "saldoDevedorAtual": BRLFormatters.currency(initialBalance),
            "parcelaAtual": BRLFormatters.currency(contract.installmentAmount),
            "prazoOriginalRestanteMeses": origMonths,
            "novoPrazoComPlanoMeses": newMonths,
            "mesesEliminados": monthsSaved,
            "economiaTotalDeJuros": BRLFormatters.currency(interestSaved),
            "dataOriginalTermino": origMaturity,
            "dataQuitacaoPrevista": payoffDate,
            "dataReferenciaInicialFimMes": BRLFormatters.shortDate(firstMonthEnd),
            "saldoPrevistoInicialFimMes": BRLFormatters.currency(baseFirstSaldoPrevisto),
            "cronogramaAmortizacao": scheduleJson
        ]

        var md = """
        ### ⚡ Plano de Amortização \(intensity.displayTitle): \(contract.name) (\(kindTitle))

        • **Saldo Devedor Atual:** **\(BRLFormatters.currency(initialBalance))** (\(origMonths) parcelas restantes de \(BRLFormatters.currency(contract.installmentAmount)))
        • **Data Base Inicial (Final do Mês):** **\(BRLFormatters.shortDate(firstMonthEnd))** (Saldo Previsto: \(BRLFormatters.currency(baseFirstSaldoPrevisto)) • Sobra Planejada: \(BRLFormatters.currency(baseKPI.surplusAfterPlanning)))
        • **Resultado do Plano \(intensity.displayTitle):** Elimina **\(monthsSaved) parcelas**, reduz o prazo restante para **\(newMonths) meses**, economiza **\(BRLFormatters.currency(interestSaved))** em juros futuros e antecipa a quitação de **\(origMaturity)** para **\(payoffDate)**!

        """

        if !rows.isEmpty {
            md += "#### 📅 Cronograma de Amortização (Fechamento de Mês + Impacto nos Meses Futuros):\n"
            for r in rows.prefix(24) {
                let tag = r.isPayoffStep ? " 🏁 Quitação" : ""
                md += "• **\(r.dateStr)\(tag):** Amortizar **\(BRLFormatters.currency(r.amortized))** · Saldo Devedor Restante: **\(BRLFormatters.currency(r.remainingContractAfter))** · Saldo Previsto após aporte: **\(BRLFormatters.currency(r.saldoPrevistoAfter))**\n"
            }
            if rows.count > 24 {
                md += "\n_...exibindo os primeiros 24 meses; quitação final alcançada em **\(payoffDate)** considerando todas as parcelas futuras sombreadas após a liquidação._\n"
            }
        } else {
            md += "⚠️ **Atenção:** Sua sobra mensal líquida projetada atual não deixou margem segura acima da reserva para aportes extras automáticos sem comprometer o caixa futuro. Considere reduzir gastos variáveis antes de iniciar aportes extras."
        }

        return (payload, md)
    }
}
