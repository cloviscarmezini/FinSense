import Foundation

/// Motor de Decisão e Cenários "E se?" (100% read-only; nunca altera dados reais da base).
public enum DecisionAndScenarioEngine {

    // MARK: - 1. Comparador "Amortizar vs. Investir"

    public static func effectiveMonthlyRateDecimal(for contract: CreditContract, balance: Double, remainingMonths: Int) -> Double {
        if contract.kind == .financing {
            let nominalMonthly = contract.effectiveMonthlyNominalRateDecimal
            let trMonthly = max(0.0, (contract.estimatedMonthlyTR ?? 0.0) / 100.0)
            return max(0.0, nominalMonthly + trMonthly)
        } else {
            if contract.monthlyInterestRate > 0.0001 {
                return contract.monthlyInterestRate / 100.0
            }
            // Fallback por Newton-Raphson na Price caso a taxa não esteja preenchida
            let pmt = contract.installmentAmount
            let n = Double(max(1, remainingMonths))
            guard balance > 0, pmt * n > balance else { return 0.0 }
            var rate = 0.015
            for _ in 0..<25 {
                let powVal = pow(1.0 + rate, -n)
                let f = pmt * (1.0 - powVal) / rate - balance
                let df = pmt * ((n * pow(1.0 + rate, -n - 1.0) * rate) - (1.0 - powVal)) / (rate * rate)
                if abs(df) < 1e-9 { break }
                let next = rate - f / df
                if next > 0.0001 && next < 0.5 {
                    rate = next
                } else {
                    break
                }
            }
            return max(0.0, rate)
        }
    }

    public static func compareAmortizeVsInvest(
        contract: CreditContract,
        outstandingBalance: Double,
        remainingMonths: Int,
        extraAmount: Double,
        benchmarkGrossAnnualRatePercent: Double,
        taxRatePercent: Double
    ) -> AmortizeVsInvestComparisonResult {
        let cleanBalance = max(0.0, outstandingBalance)
        let horizon = max(1, remainingMonths)
        let cleanExtra = min(max(0.0, extraAmount), cleanBalance > 0 ? cleanBalance : max(0.0, extraAmount))

        let debtMonthlyDecimal = effectiveMonthlyRateDecimal(for: contract, balance: cleanBalance, remainingMonths: horizon)
        let debtMonthlyPct = debtMonthlyDecimal * 100.0
        let debtAnnualPct = (pow(1.0 + debtMonthlyDecimal, 12.0) - 1.0) * 100.0

        let taxFactor = max(0.0, 1.0 - (min(max(0.0, taxRatePercent), 50.0) / 100.0))
        let benchGrossPct = max(0.0, benchmarkGrossAnnualRatePercent)
        let benchNetAnnualPct = benchGrossPct * taxFactor
        let benchNetMonthlyDecimal = pow(1.0 + benchNetAnnualPct / 100.0, 1.0 / 12.0) - 1.0
        let benchNetMonthlyPct = benchNetMonthlyDecimal * 100.0

        let breakEvenNetAnnual = debtAnnualPct
        let breakEvenGrossAnnual = taxFactor > 0.0001 ? (breakEvenNetAnnual / taxFactor) : breakEvenNetAnnual

        // Simula caminho A (Amortizar hoje com redução de prazo) vs Baseline sem amortizar
        let simA = simulateContractTotalInterest(
            balance: cleanBalance,
            extraAtStart: cleanExtra,
            monthlyRate: debtMonthlyDecimal,
            scheduledInstallment: contract.effectiveBaseInstallmentPrice > 0 ? contract.effectiveBaseInstallmentPrice : contract.installmentAmount,
            maxMonths: horizon,
            isSAC: contract.amortizationSystem == .sac
        )
        let simBase = simulateContractTotalInterest(
            balance: cleanBalance,
            extraAtStart: 0.0,
            monthlyRate: debtMonthlyDecimal,
            scheduledInstallment: contract.effectiveBaseInstallmentPrice > 0 ? contract.effectiveBaseInstallmentPrice : contract.installmentAmount,
            maxMonths: horizon,
            isSAC: contract.amortizationSystem == .sac
        )

        let totalInterestSaved = max(0.0, simBase.totalInterestPaid - simA.totalInterestPaid)
        let monthsEliminated = max(0, simBase.monthsTaken - simA.monthsTaken)

        // Simula caminho B (Investir o mesmo valor ao rendimento líquido de referência durante `horizon` meses)
        var investedBalance = cleanExtra
        var monthsUntilPayoff: Int? = nil
        var debtRunningForCrossover = cleanBalance
        let pmtForCrossover = contract.effectiveBaseInstallmentPrice > 0 ? contract.effectiveBaseInstallmentPrice : contract.installmentAmount

        var curvePoints: [AmortizeVsInvestCurvePoint] = [
            AmortizeVsInvestCurvePoint(monthIndex: 0, amortizedInterestSavedCumulative: 0.0, investedNetGainCumulative: 0.0)
        ]

        let maxPlotMonths = min(horizon, 120)
        let stepSize = max(1, horizon / maxPlotMonths)

        var simBaseBalance = cleanBalance
        var simAmortBalance = max(0.0, cleanBalance - cleanExtra)
        var cumBaseInt = 0.0
        var cumAmortInt = 0.0

        for m in 1...horizon {
            if simBaseBalance > 0.01 {
                let intB = simBaseBalance * debtMonthlyDecimal
                cumBaseInt += intB
                let prinB = contract.amortizationSystem == .sac
                    ? (cleanBalance / Double(horizon))
                    : max(0.0, pmtForCrossover - intB)
                simBaseBalance = max(0.0, simBaseBalance - min(simBaseBalance, max(prinB, 0.0)))
            }
            if simAmortBalance > 0.01 {
                let intA = simAmortBalance * debtMonthlyDecimal
                cumAmortInt += intA
                let prinA = contract.amortizationSystem == .sac
                    ? (cleanBalance / Double(horizon))
                    : max(0.0, pmtForCrossover - intA)
                simAmortBalance = max(0.0, simAmortBalance - min(simAmortBalance, max(prinA, 0.0)))
            }
            if debtRunningForCrossover > 0.01 {
                let intC = debtRunningForCrossover * debtMonthlyDecimal
                let prinC = contract.amortizationSystem == .sac
                    ? (cleanBalance / Double(horizon))
                    : max(0.0, pmtForCrossover - intC)
                debtRunningForCrossover = max(0.0, debtRunningForCrossover - min(debtRunningForCrossover, max(prinC, 0.0)))
            }

            investedBalance *= (1.0 + benchNetMonthlyDecimal)
            if monthsUntilPayoff == nil && investedBalance >= debtRunningForCrossover && debtRunningForCrossover > 0 {
                monthsUntilPayoff = m
            }

            if m % stepSize == 0 || m == horizon {
                curvePoints.append(
                    AmortizeVsInvestCurvePoint(
                        monthIndex: m,
                        amortizedInterestSavedCumulative: max(0.0, cumBaseInt - cumAmortInt),
                        investedNetGainCumulative: max(0.0, investedBalance - cleanExtra)
                    )
                )
            }
        }

        let investProjectedNetGain = max(0.0, investedBalance - cleanExtra)
        let netAdvantage = totalInterestSaved - investProjectedNetGain

        let recommendation: DecisionRecommendation
        if abs(debtAnnualPct - benchNetAnnualPct) < 0.25 && abs(netAdvantage) < max(50.0, cleanExtra * 0.01) {
            recommendation = .neutral
        } else if debtAnnualPct >= benchNetAnnualPct || netAdvantage > 0 {
            recommendation = .amortize
        } else {
            recommendation = .invest
        }

        let explanation: String
        switch recommendation {
        case .amortize:
            explanation = "A taxa efetiva da dívida (\(String(format: "%.2f", debtAnnualPct))% a.a.) supera o rendimento líquido de referência (\(String(format: "%.2f", benchNetAnnualPct))% a.a.). Amortizar agora poupa \(BRLFormatters.currency(totalInterestSaved)) em juros e elimina \(monthsEliminated) mês(es)."
        case .invest:
            let payoffNote = monthsUntilPayoff.map { " Em ~\($0) mês(es), o montante investido igualará o saldo restante para quitação." } ?? ""
            explanation = "O rendimento líquido do investimento (\(String(format: "%.2f", benchNetAnnualPct))% a.a.) supera o custo efetivo da dívida (\(String(format: "%.2f", debtAnnualPct))% a.a.), gerando vantagem projetada de \(BRLFormatters.currency(abs(netAdvantage))).\(payoffNote)"
        case .neutral:
            explanation = "O custo da dívida (\(String(format: "%.2f", debtAnnualPct))% a.a.) e o rendimento líquido (\(String(format: "%.2f", benchNetAnnualPct))% a.a.) estão praticamente no ponto de equilíbrio (break-even em \(String(format: "%.2f", breakEvenGrossAnnual))% a.a. bruto)."
        }

        return AmortizeVsInvestComparisonResult(
            contractId: contract.id,
            contractName: contract.name,
            contractKind: contract.kind,
            extraAmount: cleanExtra,
            outstandingBalance: cleanBalance,
            remainingMonths: horizon,
            contractEffectiveMonthlyRatePercent: debtMonthlyPct,
            contractEffectiveAnnualRatePercent: debtAnnualPct,
            benchmarkGrossAnnualRatePercent: benchGrossPct,
            benchmarkNetAnnualRatePercent: benchNetAnnualPct,
            benchmarkNetMonthlyRatePercent: benchNetMonthlyPct,
            breakEvenGrossAnnualRatePercent: breakEvenGrossAnnual,
            breakEvenNetAnnualRatePercent: breakEvenNetAnnual,
            amortizeInterestSaved: totalInterestSaved,
            amortizeMonthsEliminated: monthsEliminated,
            investProjectedNetGain: investProjectedNetGain,
            investFinalAmount: investedBalance,
            monthsUntilInvestmentPaysOffContract: monthsUntilPayoff,
            netFinancialAdvantage: netAdvantage,
            recommendation: recommendation,
            explanation: explanation,
            curvePoints: curvePoints
        )
    }

    private static func simulateContractTotalInterest(
        balance: Double,
        extraAtStart: Double,
        monthlyRate: Double,
        scheduledInstallment: Double,
        maxMonths: Int,
        isSAC: Bool
    ) -> (totalInterestPaid: Double, monthsTaken: Int) {
        var remaining = max(0.0, balance - extraAtStart)
        guard remaining > 0.01 else { return (0.0, 0) }
        var totalInterest = 0.0
        var months = 0
        let fixedSACAmort = balance / Double(max(1, maxMonths))

        while remaining > 0.01 && months < maxMonths + 120 {
            months += 1
            let interest = remaining * monthlyRate
            totalInterest += interest
            let principalPaid: Double
            if isSAC {
                principalPaid = min(remaining, fixedSACAmort)
            } else {
                let pmt = max(scheduledInstallment, interest + 1.0)
                principalPaid = min(remaining, max(0.0, pmt - interest))
            }
            remaining -= principalPaid
            if principalPaid <= 0.0001 { break }
        }
        return (totalInterest, months)
    }

    // MARK: - 2. Stress Test de Caixa (Projeção Multi-Meses Não Destrutiva)

    @MainActor
    public static func runStressTest(
        store: FinancialDataStore,
        scenario: WhatIfScenario,
        horizonMonths: Int = 12,
        startMonth: Date? = nil
    ) -> StressTestResult {
        let calendar = store.calendar
        let baseMonth = store.startOfMonth(for: startMonth ?? store.selectedMonth)
        let horizon = max(3, min(24, horizonMonths))

        // Saldo de abertura no início de `baseMonth`
        let initialAnalysis = store.buildIntraMonthCashFlowAnalysis(for: baseMonth)
        var runningBaseClosing = initialAnalysis.openingBalance
        var runningStressedClosing = initialAnalysis.openingBalance

        var points: [StressTestMonthPoint] = []
        var negativeKeys: [Int] = []
        var mitigations: [SuggestedStressMitigation] = []

        // Coleta amortizações planejadas pendentes para sugerir adiamento
        let pendingPlannedItems: [(contractName: String, item: PlannedAmortization)] = store.amortizationPlans.flatMap { plan in
            let contractName = store.contracts.first(where: { $0.id == plan.contractId })?.name ?? "Contrato"
            return plan.items
                .filter { $0.status == .pending }
                .map { (contractName, $0) }
        }

        for offset in 0..<horizon {
            guard let mDate = calendar.date(byAdding: .month, value: offset, to: baseMonth) else { continue }
            let ymComps = calendar.dateComponents([.year, .month], from: mDate)
            let ymKey = (ymComps.year ?? 2026) * 100 + (ymComps.month ?? 1)
            let label = BRLFormatters.shortMonthYearFormatter.string(from: mDate).capitalized

            let monthTxs = store.transactionsForMonth(mDate).filter {
                !$0.ignoreInConsolidated &&
                !$0.isCreditCardExpense &&
                store.isTransactionVisibleInCurrentScenario($0)
            }

            let baseIncome = monthTxs.filter { $0.type == .income }.reduce(0.0) { $0 + store.effectiveTransactionAmount(for: $1) }
            // Receitas variáveis / extraordinárias (13º, bônus, PLR, avulsas)
            let variableIncome = monthTxs
                .filter { $0.type == .income && ($0.isExtraordinaryIncome || $0.recurrenceMode == .single) }
                .reduce(0.0) { $0 + store.effectiveTransactionAmount(for: $1) }

            let incomeCutBase = variableIncome > 0.01 ? variableIncome : (baseIncome * 0.20)
            let incomeDrop = incomeCutBase * (scenario.variableIncomeReductionPercent / 100.0)
            let stressedIncome = max(0.0, baseIncome - incomeDrop)

            let cashExpenses = monthTxs.filter { $0.type == .expense }.reduce(0.0) { $0 + store.effectiveTransactionAmount(for: $1) }
            let provisionsInMonth = store.isMonthPriorToCurrent(mDate) ? 0.0 : store.totalRemainingProvision(for: mDate)
            let baseExpense = cashExpenses + provisionsInMonth

            let shockExpense = (offset == scenario.unexpectedExpenseMonthOffset) ? scenario.unexpectedExpenseAmount : 0.0
            let stressedExpense = baseExpense + shockExpense

            let plannedAmort = monthTxs
                .filter { $0.transactionOrigin == .plannedAmortization }
                .reduce(0.0) { $0 + store.effectiveTransactionAmount(for: $1) }

            // Intra-mês estimado no estresse: usa o perfil intramês do mês e aplica o delta de choque acumulado
            let monthIntra = store.buildIntraMonthCashFlowAnalysis(for: mDate)
            let intraShift = (runningStressedClosing - monthIntra.openingBalance) - incomeDrop - shockExpense - provisionsInMonth
            let minIntraStressed = monthIntra.minimumBalance + intraShift

            runningBaseClosing += (baseIncome - baseExpense)
            runningStressedClosing += (stressedIncome - stressedExpense)

            let pt = StressTestMonthPoint(
                monthOffset: offset,
                yearMonthKey: ymKey,
                monthDate: mDate,
                label: label,
                baselineIncome: baseIncome,
                stressedIncome: stressedIncome,
                baselineExpense: baseExpense,
                stressedExpense: stressedExpense,
                baselineClosingBalance: runningBaseClosing,
                stressedClosingBalance: runningStressedClosing,
                minimumIntraMonthStressedBalance: minIntraStressed,
                plannedAmortizationInMonth: plannedAmort
            )
            points.append(pt)

            if pt.isNegative {
                negativeKeys.append(ymKey)
            }
        }

        let lowestPoint = points.min(by: { min($0.stressedClosingBalance, $0.minimumIntraMonthStressedBalance) < min($1.stressedClosingBalance, $1.minimumIntraMonthStressedBalance) })
        let lowestBalance = lowestPoint.map { min($0.stressedClosingBalance, $0.minimumIntraMonthStressedBalance) } ?? runningStressedClosing

        // Gera recomendações práticas de mitigação sem alterar dados reais
        var totalMitigable = 0.0
        if !negativeKeys.isEmpty, let firstNegKey = negativeKeys.first {
            // 1. Sugerir adiar amortizações planejadas nos meses até/durante o déficit
            for (cName, planItem) in pendingPlannedItems where planItem.amountDouble > 0 {
                let comps = calendar.dateComponents([.year, .month], from: planItem.date)
                let itemYM = (comps.year ?? 2026) * 100 + (comps.month ?? 1)
                if itemYM <= (negativeKeys.last ?? firstNegKey) {
                    let amt = planItem.amountDouble
                    totalMitigable += amt
                    mitigations.append(
                        SuggestedStressMitigation(
                            title: "Adiar amortização planejada (\(cName))",
                            description: "Adiar aporte de \(BRLFormatters.currency(amt)) previsto para \(BRLFormatters.shortDate(planItem.date)) preserva liquidez imediata.",
                            recoveredAmount: amt,
                            targetYearMonthKey: itemYM
                        )
                    )
                }
            }

            // 2. Sugerir pausa temporária em tetos variáveis / provisões caso o déficit persista
            if lowestBalance + totalMitigable < 0 {
                let firstNegPoint = points.first(where: { $0.yearMonthKey == firstNegKey })
                let remProv = firstNegPoint.map { store.totalRemainingProvision(for: $0.monthDate) } ?? 0.0
                if remProv > 50 {
                    let pauseCut = min(remProv, abs(lowestBalance + totalMitigable))
                    totalMitigable += pauseCut
                    mitigations.append(
                        SuggestedStressMitigation(
                            title: "Reduzir gastos variáveis orçados em \(firstNegPoint?.label ?? "mês crítico")",
                            description: "Segurar \(BRLFormatters.currency(pauseCut)) dos envelopes variáveis não essenciais evita saldo negativo.",
                            recoveredAmount: pauseCut,
                            targetYearMonthKey: firstNegKey
                        )
                    )
                }
            }

            // 3. Sugerir utilização temporária de reserva Sinking Fund
            if lowestBalance + totalMitigable < 0 {
                let sfMonthly = store.totalMonthlySinkingFundContribution
                if sfMonthly > 10 {
                    let sfSave = sfMonthly * Double(min(3, negativeKeys.count))
                    totalMitigable += sfSave
                    mitigations.append(
                        SuggestedStressMitigation(
                            title: "Suspender temporariamente aportes em Sinking Funds",
                            description: "Pausar a reserva mensal anualizada (\(BRLFormatters.currency(sfMonthly))/mês) por até 3 meses recupera \(BRLFormatters.currency(sfSave)).",
                            recoveredAmount: sfSave,
                            targetYearMonthKey: firstNegKey
                        )
                    )
                }
            }
        }

        return StressTestResult(
            scenario: scenario,
            months: points,
            negativeMonthKeys: negativeKeys,
            lowestStressedBalance: lowestBalance,
            lowestStressedMonthLabel: lowestPoint?.label,
            suggestedMitigations: mitigations,
            mitigatedLowestBalance: lowestBalance + totalMitigable
        )
    }

    // MARK: - 3. Sinking Funds

    /// Retorna o quanto o fundo ainda precisa provisionar no mês (respeitando teto da meta restante e estado ativo).
    public static func monthlyReserveContribution(for fund: SinkingFund) -> Double {
        guard fund.isEnabled, fund.targetAmount > 0.001 else { return 0.0 }
        let proportional = fund.monthlyContribution
        if fund.accumulatedReserve >= fund.targetAmount - 0.001 {
            return 0.0
        }
        return min(proportional, fund.remainingToTarget)
    }
}
