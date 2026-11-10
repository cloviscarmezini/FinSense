import Foundation

/// Detalhamento dos componentes da prestação mensal e da evolução do Saldo Devedor em um empréstimo puro (Tabela Price).
public struct LoanMonthlyBreakdown: Hashable, Identifiable {
    public var id: UUID = UUID()
    public let installmentIndex: Int
    public let previousBalance: Double
    public let interestAmount: Double
    public let amortizationAmount: Double
    public let newBalance: Double
    public let installmentDue: Double
    public let calculationDate: Date

    public init(
        installmentIndex: Int = 1,
        previousBalance: Double,
        interestAmount: Double,
        amortizationAmount: Double,
        newBalance: Double,
        installmentDue: Double,
        calculationDate: Date = Date()
    ) {
        self.installmentIndex = installmentIndex
        self.previousBalance = previousBalance
        self.interestAmount = interestAmount
        self.amortizationAmount = amortizationAmount
        self.newBalance = newBalance
        self.installmentDue = installmentDue
        self.calculationDate = calculationDate
    }
}

/// Resultado analítico e centavo a centavo da amortização extraordinária de um empréstimo.
public struct LoanAmortizationResult: Hashable {
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
        self.estimatedTotalInterestSaved = estimatedTotalInterestSaved
        self.mode = mode
    }
}

/// Resultado do recálculo inverso ou reestruturação de empréstimo (reversão de transação / linked transaction rollback).
public struct LoanRecalculationResult: Hashable {
    public let balance: Double
    public let remainingInstallments: Int
    public let installmentValue: Double

    public init(
        balance: Double,
        remainingInstallments: Int,
        installmentValue: Double
    ) {
        self.balance = balance
        self.remainingInstallments = remainingInstallments
        self.installmentValue = installmentValue
    }
}

/// Motor de Matemática Financeira e Engenharia de Amortização para Empréstimos Convencionais e Consignados.
/// Opera estritamente com a Tabela Price pré-fixada pura (PMT = Amortização + Juros),
/// sem as taxas de seguros (MIP/DFI) e taxas de administração próprias de financiamentos imobiliários.
public enum LoanAmortizationEngine {

    // MARK: - 1. Motor de Evolução Mensal (Competência Price Pura)

    /// Calcula a evolução de uma competência mensal de empréstimo:
    /// 1. Juros = Saldo Atualizado * (Taxa Mensal / 100)
    /// 2. Amortização = Parcela Fixa - Juros
    /// 3. Novo Saldo Devedor = Saldo Anterior - Amortização
    public static func calculateNextInstallment(
        currentBalance: Double,
        monthlyInterestRate: Double,
        installmentValue: Double,
        installmentIndex: Int = 1,
        date: Date = Date()
    ) -> LoanMonthlyBreakdown {
        let cleanBalance = max(0.0, currentBalance)
        let cleanPMT = max(0.0, installmentValue)
        let i = max(0.0, monthlyInterestRate) / 100.0

        let interest = cleanBalance * i
        let amortization = max(0.0, min(cleanPMT - interest, cleanBalance))
        let newBalance = max(0.0, cleanBalance - amortization)

        return LoanMonthlyBreakdown(
            installmentIndex: installmentIndex,
            previousBalance: cleanBalance,
            interestAmount: interest,
            amortizationAmount: amortization,
            newBalance: newBalance,
            installmentDue: cleanPMT,
            calculationDate: date
        )
    }

    /// Conveniência calculando a competência a partir de um `LoanModel`.
    public static func calculateNextInstallment(
        for loan: LoanModel,
        installmentIndex: Int = 1,
        date: Date = Date()
    ) -> LoanMonthlyBreakdown {
        calculateNextInstallment(
            currentBalance: loan.balance,
            monthlyInterestRate: loan.monthlyInterestRate,
            installmentValue: loan.installmentValue,
            installmentIndex: installmentIndex,
            date: date
        )
    }

    // MARK: - 2. Motor de Evolução e Amortização Extraordinária (Descapitalização)

    /// Simula e calcula a amortização extraordinária de um empréstimo via descapitalização (trazer a valor presente):
    /// 1. Desconto do Principal: NovoSaldoDevedor = SaldoDevedorAtual - extraPayment (abatendo juros diários pró-rata se houver).
    /// 2. Modalidade A - Redução de Prazo: Mantém o valor da parcela e calcula o novo N:
    ///    $N = \frac{-\ln(1 - (\text{NovoSaldoDevedor} \times i)/\text{PMT})}{\ln(1 + i)}$
    ///    Arredonda N para o teto (`ceil(N - 1e-9)`).
    /// 3. Modalidade B - Redução de Parcela: Mantém o prazo restante e recalcula a nova prestação PMT:
    ///    $\text{PMT} = \frac{\text{NovoSaldoDevedor} \times i}{1 - (1 + i)^{-\text{PrazoRestante}}}$
    public static func simulateExtraAmortization(
        currentBalance: Double,
        monthlyInterestRate: Double,
        installmentValue: Double,
        currentRemainingInstallments: Int,
        extraPayment: Double,
        proRataInterest: Double = 0.0,
        mode: AmortizationRecalculationMode = .reduceTerm
    ) -> LoanAmortizationResult {
        let grossPayment = max(0.0, extraPayment)
        let cleanProRata = max(0.0, min(proRataInterest, grossPayment))

        // 1. Abate juros pró-rata do pagamento bruto antes de abater do principal
        let effectiveAmortization = max(0.0, grossPayment - cleanProRata)

        let cleanBalance = max(0.0, currentBalance)
        let newBalance = max(0.0, cleanBalance - effectiveAmortization)
        let i = max(0.0, monthlyInterestRate) / 100.0

        // Se o valor amortizado cobrir todo o Saldo Devedor (PV), ocorre Quitação Total imediata
        if newBalance <= 0.01 || effectiveAmortization >= cleanBalance {
            let totalSaved = max(0.0, Double(currentRemainingInstallments) * installmentValue - grossPayment)
            return LoanAmortizationResult(
                grossPayment: grossPayment,
                proRataInterest: cleanProRata,
                effectiveAmortization: min(effectiveAmortization, cleanBalance),
                previousBalance: cleanBalance,
                newBalance: 0.0,
                previousRemainingInstallments: currentRemainingInstallments,
                newRemainingInstallments: 0,
                eliminatedInstallmentsCount: currentRemainingInstallments,
                previousInstallmentAmount: installmentValue,
                newInstallmentAmount: 0.0,
                estimatedTotalInterestSaved: totalSaved,
                mode: mode
            )
        }

        var newRemaining = currentRemainingInstallments
        var newInstallment = installmentValue

        switch mode {
        case .reduceTerm:
            // Modalidade A - Redução de Prazo (Mantendo o Valor da Parcela)
            // N = -ln(1 - (PV * i) / PMT) / ln(1 + i)
            if i > 0.000001 && installmentValue > newBalance * i {
                let ratio = 1.0 - (newBalance * i) / installmentValue
                let calcN = -log(max(ratio, 0.000001)) / log(1.0 + i)
                newRemaining = max(1, min(Int(ceil(calcN - 1e-9)), currentRemainingInstallments))
            } else {
                newRemaining = max(1, Int(ceil((newBalance / max(installmentValue, 1.0)) - 1e-9)))
            }
            newInstallment = installmentValue

        case .reduceInstallment:
            // Modalidade B - Redução de Parcela (Mantendo o Prazo Atual)
            // PMT = PV * i / (1 - (1 + i)^(-n))
            let rem = max(currentRemainingInstallments, 1)
            if i > 0.000001 {
                newInstallment = (newBalance * i) / (1.0 - pow(1.0 + i, -Double(rem)))
            } else {
                newInstallment = newBalance / Double(rem)
            }
            newRemaining = rem
        }

        let eliminated = max(0, currentRemainingInstallments - newRemaining)
        let oldNominalFuture = Double(currentRemainingInstallments) * installmentValue
        let newNominalFuture = Double(newRemaining) * newInstallment
        let interestSaved = max(0.0, oldNominalFuture - (newNominalFuture + effectiveAmortization))

        return LoanAmortizationResult(
            grossPayment: grossPayment,
            proRataInterest: cleanProRata,
            effectiveAmortization: effectiveAmortization,
            previousBalance: cleanBalance,
            newBalance: newBalance,
            previousRemainingInstallments: currentRemainingInstallments,
            newRemainingInstallments: newRemaining,
            eliminatedInstallmentsCount: eliminated,
            previousInstallmentAmount: installmentValue,
            newInstallmentAmount: newInstallment,
            estimatedTotalInterestSaved: interestSaved,
            mode: mode
        )
    }

    /// Conveniência simulando amortização extraordinária a partir de um `LoanModel`.
    public static func simulateExtraAmortization(
        for loan: LoanModel,
        extraPayment: Double,
        proRataInterest: Double = 0.0,
        mode: AmortizationRecalculationMode = .reduceTerm
    ) -> LoanAmortizationResult {
        simulateExtraAmortization(
            currentBalance: loan.balance,
            monthlyInterestRate: loan.monthlyInterestRate,
            installmentValue: loan.installmentValue,
            currentRemainingInstallments: loan.remainingInstallments,
            extraPayment: extraPayment,
            proRataInterest: proRataInterest,
            mode: mode
        )
    }

    // MARK: - 3. Recálculo Inverso (Integridade e Rollback de Transações Casadas)

    /// Recalcula o prazo (N) ou a prestação (PMT) com base em um saldo restaurado
    /// (utilizado na exclusão de transações de amortização ou quitação para rollback atômico).
    public static func recalculate(
        balance: Double,
        monthlyInterestRate: Double,
        installmentValue: Double,
        currentRemainingInstallments: Int,
        mode: AmortizationRecalculationMode = .reduceTerm
    ) -> LoanRecalculationResult {
        let cleanBalance = max(0.0, balance)
        let i = max(0.0, monthlyInterestRate) / 100.0

        if cleanBalance <= 0.01 {
            return LoanRecalculationResult(
                balance: 0.0,
                remainingInstallments: 0,
                installmentValue: 0.0
            )
        }

        switch mode {
        case .reduceTerm:
            let newRemaining: Int
            if i > 0.000001 && installmentValue > cleanBalance * i {
                let ratio = 1.0 - (cleanBalance * i) / installmentValue
                let calcN = -log(max(ratio, 0.000001)) / log(1.0 + i)
                newRemaining = max(1, Int(ceil(calcN - 1e-9)))
            } else {
                newRemaining = max(1, Int(ceil((cleanBalance / max(installmentValue, 1.0)) - 1e-9)))
            }
            return LoanRecalculationResult(
                balance: cleanBalance,
                remainingInstallments: newRemaining,
                installmentValue: installmentValue
            )

        case .reduceInstallment:
            let rem = max(currentRemainingInstallments, 1)
            let newPMT: Double
            if i > 0.000001 {
                newPMT = (cleanBalance * i) / (1.0 - pow(1.0 + i, -Double(rem)))
            } else {
                newPMT = cleanBalance / Double(rem)
            }
            return LoanRecalculationResult(
                balance: cleanBalance,
                remainingInstallments: rem,
                installmentValue: newPMT
            )
        }
    }

    // MARK: - 4. Motor de Quitação (Payoff)

    /// Calcula o valor exato para quitação imediata:
    /// No empréstimo puro, a quitação NUNCA é a soma das parcelas restantes,
    /// mas rigorosamente o Saldo Devedor Atual a Valor Presente (PV).
    public static func calculatePayoffAmount(
        currentBalance: Double,
        monthlyInterestRate: Double,
        installmentValue: Double,
        remainingInstallments: Int
    ) -> Double {
        if currentBalance > 0.01 {
            return currentBalance
        }
        return LoanModel.calculatePresentValue(
            installment: installmentValue,
            monthlyRate: monthlyInterestRate,
            remaining: remainingInstallments
        )
    }
}
