import Foundation

/// Modalidade do Empréstimo: Convencional (Pessoal) ou Consignado em Folha de Pagamento.
public enum LoanType: String, Codable, CaseIterable, Identifiable, Hashable {
    case personal = "Pessoal"
    case payrollDeductible = "Consignado"

    public var id: String { rawValue }

    public var isPayrollDeductible: Bool {
        self == .payrollDeductible
    }
}

/// Modelo especializado para Empréstimos Convencionais e Empréstimos Consignados.
/// Diferente do financiamento imobiliário (que possui TR, taxa administrativa e seguros MIP/DFI),
/// os empréstimos pessoal e consignado operam com parcelas fixas puras (Tabela Price pré-fixada),
/// onde a prestação mensal (PMT) é rigorosamente composta apenas por Amortização do Principal + Juros de Remuneração.
public struct LoanModel: Identifiable, Codable, Hashable {
    public var id: UUID

    /// Saldo Devedor Atual / Valor Presente (PV) - Capital real devido sem juros futuros não incorridos.
    public var balance: Double

    /// Taxa de Juros Mensal real aplicada no contrato (% a.m., ex: 2.0087).
    public var monthlyInterestRate: Double

    /// Valor Fixo da Parcela (PMT).
    public var installmentValue: Double

    /// Quantidade de parcelas restantes (N).
    public var remainingInstallments: Int

    /// Quantidade total de parcelas contratadas.
    public var totalInstallments: Int

    /// Modalidade de crédito (.personal ou .payrollDeductible).
    public var loanType: LoanType

    /// Data de contratação / formalização.
    public var startDate: Date?

    /// Data do último vencimento ou competência.
    public var lastBillingDate: Date?

    /// Observações adicionais.
    public var notes: String

    // MARK: - Propriedades Derivadas e Cálculos Price

    /// Taxa de juros mensal em formato decimal (ex: 2.0087% -> 0.020087).
    public var monthlyRateDecimal: Double {
        monthlyInterestRate / 100.0
    }

    /// Taxa de juros anual nominal proporcional (% a.a. = i_mensal * 12).
    public var annualRateNominalPercentage: Double {
        monthlyInterestRate * 12.0
    }

    /// Juros do mês atual calculados estritamente sobre o Saldo Devedor:
    /// $\text{Juros} = \text{Saldo Devedor} \times i$
    public var currentMonthlyInterest: Double {
        balance * monthlyRateDecimal
    }

    /// Fração de Amortização Real do mês atual na Tabela Price pura:
    /// $\text{Amortização} = \text{Parcela} - \text{Juros}$
    public var currentMonthlyAmortization: Double {
        max(0.0, installmentValue - currentMonthlyInterest)
    }

    /// Soma Nominal das parcelas restantes (fluxo futuro total contratado se pago mês a mês).
    public var totalNominalRemaining: Double {
        Double(remainingInstallments) * installmentValue
    }

    /// Economia estimada de juros futuros se o contrato for quitado hoje:
    /// $\text{Economia} = \text{Soma Nominal Futura} - \text{Saldo Devedor Atual}$
    public var futureInterestSavedIfSettledNow: Double {
        max(0.0, totalNominalRemaining - balance)
    }

    /// Indicador de débito garantido direto em folha de pagamento / contracheque.
    public var isPayrollDeductible: Bool {
        loanType.isPayrollDeductible
    }

    // MARK: - Inicializador

    public init(
        id: UUID = UUID(),
        balance: Double,
        monthlyInterestRate: Double,
        installmentValue: Double,
        remainingInstallments: Int,
        totalInstallments: Int? = nil,
        loanType: LoanType = .personal,
        startDate: Date? = nil,
        lastBillingDate: Date? = nil,
        notes: String = ""
    ) {
        self.id = id
        self.balance = abs(balance)
        self.monthlyInterestRate = max(monthlyInterestRate, 0.0)
        self.installmentValue = abs(installmentValue)
        self.remainingInstallments = max(remainingInstallments, 0)
        self.totalInstallments = max(totalInstallments ?? remainingInstallments, 1)
        self.loanType = loanType
        self.startDate = startDate
        self.lastBillingDate = lastBillingDate
        self.notes = notes
    }

    // MARK: - Funções Matemáticas Estáticas (Tabela Price Pura)

    /// Calcula o Valor Presente (PV) descapitalizado a partir do fluxo de parcelas:
    /// $PV = \text{PMT} \times \frac{1 - (1 + i)^{-n}}{i}$
    public static func calculatePresentValue(installment: Double, monthlyRate: Double, remaining: Int) -> Double {
        let i = monthlyRate / 100.0
        let pmt = max(0.0, installment)
        let n = max(0, remaining)
        guard n > 0 else { return 0.0 }
        guard i > 0.000001 else { return pmt * Double(n) }
        return pmt * (1.0 - pow(1.0 + i, -Double(n))) / i
    }

    /// Calcula o Valor da Prestação Fixa (PMT) na Tabela Price pura:
    /// $\text{PMT} = \frac{PV \times i}{1 - (1 + i)^{-n}}$
    public static func calculateInstallment(balance: Double, monthlyRate: Double, totalInstallments: Int) -> Double {
        let i = monthlyRate / 100.0
        let pv = max(0.0, balance)
        let n = max(1, totalInstallments)
        guard i > 0.000001 else { return pv / Double(n) }
        return (pv * i) / (1.0 - pow(1.0 + i, -Double(n)))
    }

    /// Calcula a quantidade de parcelas (N) necessárias para amortizar um saldo devedor com uma dada prestação e taxa:
    /// $N = \frac{-\ln(1 - (PV \times i)/\text{PMT})}{\ln(1 + i)}$
    public static func calculateRemainingInstallments(balance: Double, monthlyRate: Double, installment: Double) -> Int {
        let i = monthlyRate / 100.0
        let pv = max(0.0, balance)
        let pmt = max(0.0, installment)
        guard pv > 0.01 && pmt > 0.01 else { return 0 }
        guard i > 0.000001 else { return max(1, Int(ceil((pv / pmt) - 1e-9))) }
        guard pmt > pv * i else { return 999 } // Parcela menor que os juros: dívida perpétua
        let ratio = 1.0 - (pv * i) / pmt
        let calcN = -log(max(ratio, 0.000001)) / log(1.0 + i)
        return max(1, Int(ceil(calcN - 1e-9)))
    }
}
