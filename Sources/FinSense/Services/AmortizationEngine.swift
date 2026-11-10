import Foundation

/// Detalhamento dos 4 componentes da prestação mensal e da evolução do Saldo Devedor.
public struct MonthlyInstallmentBreakdown: Hashable, Identifiable {
    public var id: UUID = UUID()
    public let installmentIndex: Int
    public let previousBalance: Double
    public let trCorrection: Double
    public let updatedBalance: Double
    public let interestAmount: Double
    public let amortizationAmount: Double
    public let newBalance: Double
    public let baseInstallmentPrice: Double
    public let updatedInsurance: Double
    public let adminFee: Double
    public let totalInstallmentDue: Double
    public let calculationDate: Date

    public init(
        installmentIndex: Int = 1,
        previousBalance: Double,
        trCorrection: Double,
        updatedBalance: Double,
        interestAmount: Double,
        amortizationAmount: Double,
        newBalance: Double,
        baseInstallmentPrice: Double,
        updatedInsurance: Double,
        adminFee: Double,
        totalInstallmentDue: Double,
        calculationDate: Date = Date()
    ) {
        self.installmentIndex = installmentIndex
        self.previousBalance = previousBalance
        self.trCorrection = trCorrection
        self.updatedBalance = updatedBalance
        self.interestAmount = interestAmount
        self.amortizationAmount = amortizationAmount
        self.newBalance = newBalance
        self.baseInstallmentPrice = baseInstallmentPrice
        self.updatedInsurance = updatedInsurance
        self.adminFee = adminFee
        self.totalInstallmentDue = totalInstallmentDue
        self.calculationDate = calculationDate
    }
}

/// Resultado analítico e centavo a centavo da simulação de amortização extraordinária.
public struct ExtraAmortizationSimulationResult: Hashable {
    public let grossPayment: Double
    public let proRataInterest: Double
    public let effectiveAmortization: Double
    public let previousBalance: Double
    public let newBalance: Double
    public let previousRemainingInstallments: Int
    public let newRemainingInstallments: Int
    public let eliminatedInstallmentsCount: Int
    public let previousInstallmentAmount: Double
    public let newInstallmentAmount: Double
    public let basePriceInstallment: Double
    public let estimatedTotalInterestSaved: Double
    public let mode: AmortizationRecalculationMode

    public init(
        grossPayment: Double,
        proRataInterest: Double,
        effectiveAmortization: Double,
        previousBalance: Double,
        newBalance: Double,
        previousRemainingInstallments: Int,
        newRemainingInstallments: Int,
        eliminatedInstallmentsCount: Int,
        previousInstallmentAmount: Double,
        newInstallmentAmount: Double,
        basePriceInstallment: Double,
        estimatedTotalInterestSaved: Double,
        mode: AmortizationRecalculationMode
    ) {
        self.grossPayment = grossPayment
        self.proRataInterest = proRataInterest
        self.effectiveAmortization = effectiveAmortization
        self.previousBalance = previousBalance
        self.newBalance = newBalance
        self.previousRemainingInstallments = previousRemainingInstallments
        self.newRemainingInstallments = newRemainingInstallments
        self.eliminatedInstallmentsCount = eliminatedInstallmentsCount
        self.previousInstallmentAmount = previousInstallmentAmount
        self.newInstallmentAmount = newInstallmentAmount
        self.basePriceInstallment = basePriceInstallment
        self.estimatedTotalInterestSaved = estimatedTotalInterestSaved
        self.mode = mode
    }
}

/// Motor de Matemática Financeira e Engenharia de Amortização (Padrão CAIXA Econômica Federal - Tabela Price + TR).
public enum AmortizationEngine {

    // MARK: - 1. Motor de Evolução Mensal (Cálculo de Competência CAIXA)

    /// Executa rigorosamente a matemática de competência da CAIXA a cada mês:
    /// 1. Correção do Saldo: Saldo Atualizado = Saldo Anterior + TR do Mês (ou Saldo * (1 + TR))
    /// 2. Cálculo dos Juros: Juros = Saldo Atualizado * (Taxa Nominal Anual / 12)
    /// 3. Cálculo da Amortização (Price): Amortização = Parcela Base Price - Juros
    /// 4. Novo Saldo Devedor: Novo Saldo = Saldo Atualizado - Amortização
    /// 5. Valor da Parcela a Pagar: Parcela Base Price + Seguros Atualizados + Taxa de Admin
    public static func calculateNextInstallment(
        currentBalance: Double,
        annualNominalRate: Double,
        basePriceInstallment: Double,
        adminFee: Double = 25.0,
        insuranceFee: Double = 0.0,
        monthlyTR: Double = 0.0,
        trIsPercentageRate: Bool = false,
        installmentIndex: Int = 1,
        date: Date = Date()
    ) -> MonthlyInstallmentBreakdown {
        let cleanBalance = max(0.0, currentBalance)
        let cleanBasePrice = max(0.0, basePriceInstallment)
        let cleanAdmin = max(0.0, adminFee)
        let cleanInsurance = max(0.0, insuranceFee)

        // 1. Correção do Saldo: Saldo Atualizado = Saldo Anterior + TR do Mês
        let trMonetary: Double = {
            if trIsPercentageRate {
                let rate = monthlyTR > 1.0 ? (monthlyTR / 100.0) : monthlyTR
                return cleanBalance * rate
            } else {
                return monthlyTR
            }
        }()
        let updatedBalance = max(0.0, cleanBalance + trMonetary)

        // 2. Cálculo dos Juros: Juros = Saldo Atualizado * (Taxa Nominal Anual / 12)
        let monthlyRateDecimal = (annualNominalRate / 12.0) / 100.0
        let interest = updatedBalance * monthlyRateDecimal

        // 3. Cálculo da Amortização (Price): Amortização = Parcela Base Price - Juros
        let amortization = max(0.0, cleanBasePrice - interest)

        // 4. Novo Saldo Devedor: Novo Saldo = Saldo Atualizado - Amortização
        let newBalance = max(0.0, updatedBalance - amortization)

        // 5. Seguros Atualizados (Seguro MIP diminui proporcionalmente com o saldo caso o saldo diminua)
        let updatedInsurance: Double
        if cleanBalance > 0.01 && cleanInsurance > 0 {
            let ratio = newBalance / cleanBalance
            updatedInsurance = cleanInsurance * min(1.0, max(0.0, ratio))
        } else {
            updatedInsurance = cleanInsurance
        }

        // Valor da Parcela a Pagar: Parcela Base Price + Seguros Atualizados + Taxa de Admin
        let totalDue = cleanBasePrice + updatedInsurance + cleanAdmin

        return MonthlyInstallmentBreakdown(
            installmentIndex: installmentIndex,
            previousBalance: cleanBalance,
            trCorrection: trMonetary,
            updatedBalance: updatedBalance,
            interestAmount: interest,
            amortizationAmount: amortization,
            newBalance: newBalance,
            baseInstallmentPrice: cleanBasePrice,
            updatedInsurance: updatedInsurance,
            adminFee: cleanAdmin,
            totalInstallmentDue: totalDue,
            calculationDate: date
        )
    }

    /// Conveniência executando a competência a partir de um `FinancingModel`.
    public static func calculateNextInstallment(
        for financing: FinancingModel,
        monthlyTR: Double = 0.0,
        trIsPercentageRate: Bool = false,
        installmentIndex: Int = 1,
        date: Date = Date()
    ) -> MonthlyInstallmentBreakdown {
        calculateNextInstallment(
            currentBalance: financing.balance,
            annualNominalRate: financing.annualNominalInterestRate,
            basePriceInstallment: financing.baseInstallmentPrice,
            adminFee: financing.adminFee,
            insuranceFee: financing.insuranceFee,
            monthlyTR: monthlyTR,
            trIsPercentageRate: trIsPercentageRate,
            installmentIndex: installmentIndex,
            date: date
        )
    }

    // MARK: - 2. Motor de Amortização Extraordinária (Simulador Manual CAIXA)

    /// Simula amortização extraordinária abatendo juros diários (pró-rata) e recalculando
    /// o Valor Presente (PV) matematicamente na Tabela Price.
    public static func simulateExtraAmortization(
        currentBalance: Double,
        annualNominalRate: Double,
        basePriceInstallment: Double,
        totalInstallmentAmount: Double,
        currentRemainingInstallments: Int,
        extraPayment: Double,
        proRataInterest: Double = 0.0,
        mode: AmortizationRecalculationMode = .reduceTerm,
        adminFee: Double = 25.0,
        insuranceFee: Double = 0.0
    ) -> ExtraAmortizationSimulationResult {
        let grossPayment = max(0.0, extraPayment)
        let cleanProRata = max(0.0, min(proRataInterest, grossPayment))

        // 1. Abate o proRataInterest do extraPayment
        // 2. A amortização efetiva é extraPayment - proRataInterest
        let effectiveAmortization = max(0.0, grossPayment - cleanProRata)

        // 3. Novo Saldo Devedor = Saldo Atual - Amortização Efetiva
        let newBalance = max(0.0, currentBalance - effectiveAmortization)

        let i = (annualNominalRate / 12.0) / 100.0

        var newRemaining = currentRemainingInstallments
        var newInstallment = totalInstallmentAmount

        if newBalance <= 0.01 || effectiveAmortization >= currentBalance {
            newRemaining = 0
            newInstallment = 0.0
            let saved = Double(currentRemainingInstallments) * totalInstallmentAmount - grossPayment
            return ExtraAmortizationSimulationResult(
                grossPayment: grossPayment,
                proRataInterest: cleanProRata,
                effectiveAmortization: min(effectiveAmortization, currentBalance),
                previousBalance: currentBalance,
                newBalance: 0.0,
                previousRemainingInstallments: currentRemainingInstallments,
                newRemainingInstallments: 0,
                eliminatedInstallmentsCount: currentRemainingInstallments,
                previousInstallmentAmount: totalInstallmentAmount,
                newInstallmentAmount: 0.0,
                basePriceInstallment: basePriceInstallment,
                estimatedTotalInterestSaved: max(0.0, saved),
                mode: mode
            )
        }

        switch mode {
        case .reduceTerm:
            // 4. Cálculo do Novo Prazo (N) na Tabela Price com base no Novo Saldo Devedor e na mesma Parcela Base Price:
            // N = -ln(1 - (PV * i) / PMT) / ln(1 + i)
            if i > 0.000001 && basePriceInstallment > newBalance * i {
                let ratio = 1.0 - (newBalance * i) / basePriceInstallment
                let calcN = -log(max(ratio, 0.000001)) / log(1.0 + i)
                newRemaining = max(1, min(Int(ceil(calcN - 1e-9)), currentRemainingInstallments))
            } else {
                newRemaining = max(1, Int(ceil((newBalance / max(basePriceInstallment, 1.0)) - 1e-9)))
            }
            // Na redução de prazo, a parcela permanece a mesma
            newInstallment = totalInstallmentAmount

        case .reduceInstallment:
            // Mantém o prazo restante e recalcula o PMT da Tabela Price:
            // PMT = PV * i / (1 - (1 + i)^(-n))
            let newBase: Double
            if i > 0.000001 && currentRemainingInstallments > 0 {
                newBase = (newBalance * i) / (1.0 - pow(1.0 + i, -Double(currentRemainingInstallments)))
            } else {
                newBase = newBalance / Double(max(currentRemainingInstallments, 1))
            }
            let newInsurance = currentBalance > 0.01 ? insuranceFee * (newBalance / currentBalance) : insuranceFee
            newInstallment = newBase + newInsurance + adminFee
            newRemaining = currentRemainingInstallments
        }

        let eliminated = max(0, currentRemainingInstallments - newRemaining)

        // Economia estimada em juros futuros = fluxo anterior - novo fluxo - amortização
        let oldTotalFuture = Double(currentRemainingInstallments) * totalInstallmentAmount
        let newTotalFuture = Double(newRemaining) * newInstallment
        let interestSaved = max(0.0, oldTotalFuture - (newTotalFuture + effectiveAmortization))

        return ExtraAmortizationSimulationResult(
            grossPayment: grossPayment,
            proRataInterest: cleanProRata,
            effectiveAmortization: effectiveAmortization,
            previousBalance: currentBalance,
            newBalance: newBalance,
            previousRemainingInstallments: currentRemainingInstallments,
            newRemainingInstallments: newRemaining,
            eliminatedInstallmentsCount: eliminated,
            previousInstallmentAmount: totalInstallmentAmount,
            newInstallmentAmount: newInstallment,
            basePriceInstallment: basePriceInstallment,
            estimatedTotalInterestSaved: interestSaved,
            mode: mode
        )
    }

    /// Conveniência simulando a partir de um `FinancingModel`.
    public static func simulateExtraAmortization(
        for financing: FinancingModel,
        extraPayment: Double,
        proRataInterest: Double = 0.0,
        mode: AmortizationRecalculationMode = .reduceTerm
    ) -> ExtraAmortizationSimulationResult {
        simulateExtraAmortization(
            currentBalance: financing.balance,
            annualNominalRate: financing.annualNominalInterestRate,
            basePriceInstallment: financing.baseInstallmentPrice,
            totalInstallmentAmount: financing.totalInstallmentAmount,
            currentRemainingInstallments: financing.remainingInstallments,
            extraPayment: extraPayment,
            proRataInterest: proRataInterest,
            mode: mode,
            adminFee: financing.adminFee,
            insuranceFee: financing.insuranceFee
        )
    }

    // MARK: - 3. Projeção Cronológica e Amortização Real Acumulada

    /// Simula a evolução do financiamento mês a mês para N meses.
    public static func simulateSchedule(
        initialBalance: Double,
        annualNominalRate: Double,
        basePriceInstallment: Double,
        adminFee: Double = 25.0,
        insuranceFee: Double = 0.0,
        monthsCount: Int,
        monthlyTR: Double = 0.0,
        startDate: Date = Date()
    ) -> [MonthlyInstallmentBreakdown] {
        var schedule: [MonthlyInstallmentBreakdown] = []
        var runningBalance = initialBalance
        let cal = Calendar.current

        for idx in 1...max(monthsCount, 1) {
            guard runningBalance > 0.01 else { break }
            let paymentDate = cal.date(byAdding: .month, value: idx, to: startDate) ?? startDate
            let breakdown = calculateNextInstallment(
                currentBalance: runningBalance,
                annualNominalRate: annualNominalRate,
                basePriceInstallment: basePriceInstallment,
                adminFee: adminFee,
                insuranceFee: insuranceFee,
                monthlyTR: monthlyTR,
                trIsPercentageRate: false,
                installmentIndex: idx,
                date: paymentDate
            )
            schedule.append(breakdown)
            runningBalance = breakdown.newBalance
        }

        return schedule
    }
}
