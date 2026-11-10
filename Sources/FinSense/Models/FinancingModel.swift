import Foundation

/// Indexador monetário de correção do saldo devedor do financiamento imobiliário.
public enum FinancingIndexation: String, Codable, CaseIterable, Identifiable, Hashable {
    case tr = "TR (Taxa Referencial)"
    case ipca = "IPCA"
    case fixed = "Prefixado"

    public var id: String { rawValue }

    public var shortLabel: String {
        switch self {
        case .tr: return "TR"
        case .ipca: return "IPCA"
        case .fixed: return "Fixo"
        }
    }
}

/// Modelo especializado para Financiamentos Imobiliários e de Veículos (SFH/SFI - Padrão CAIXA Econômica Federal).
/// No financiamento imobiliário, a parcela NÃO é um valor fixo simples: ela é a composição de 4 variáveis fundamentais:
/// 1. Amortização do Principal (fração que reduz a dívida)
/// 2. Juros de Remuneração (calculados sobre o Saldo Devedor atualizado)
/// 3. Seguros Obrigatórios (MIP - Morte e Invalidez Permanente + DFI - Danos Físicos ao Imóvel)
/// 4. Taxa de Administração (Taxa fixa mensal de manutenção do contrato)
public struct FinancingModel: Identifiable, Codable, Hashable {
    public var id: UUID

    /// Saldo Devedor Teórico Atual (Dívida Real)
    public var balance: Double

    /// Taxa de Juros Nominal Contratual Anual (ex: 8.51 representa 8,51% a.a.).
    /// IMPORTANTE: NÃO armazene taxa mensal arredondada. A taxa mensal é sempre derivada dinamicamente.
    public var annualNominalInterestRate: Double

    /// Sistema de Amortização (foco em .price / Tabela Price)
    public var amortizationSystem: AmortizationSystem

    /// Indexador de correção monetária do saldo (.tr, .ipca, .fixed)
    public var indexationRate: FinancingIndexation

    /// Taxa de Administração fixa mensal (ex: R$ 25,00)
    public var adminFee: Double

    /// Seguros MIP e DFI mensais (diminuem proporcionalmente com a evolução do Saldo Devedor)
    public var insuranceFee: Double

    /// Quantidade total de parcelas contratadas (ex: 360 meses)
    public var totalInstallments: Int

    /// Quantidade de parcelas remanescentes futuras (ex: 332 meses)
    public var remainingInstallments: Int

    /// Valor Total da Parcela cobrada atualmente (ex: R$ 2.658,04)
    public var totalInstallmentAmount: Double

    /// Data do último vencimento ou competência
    public var lastBillingDate: Date?

    /// Taxa de juros mensal nominal em formato decimal:
    /// $\text{Taxa Mensal Decimal} = \frac{\text{annualNominalInterestRate}}{12 \times 100}$
    public var monthlyNominalRateDecimal: Double {
        (annualNominalInterestRate / 12.0) / 100.0
    }

    /// Taxa de juros mensal nominal em percentual (% a.m. ex: 8.51 / 12 = 0.7091667% a.m.)
    public var monthlyNominalRatePercentage: Double {
        annualNominalInterestRate / 12.0
    }

    /// Parcela Base Price (Amortização + Juros).
    /// Base Price = Parcela Total - Seguros - Taxas
    public var baseInstallmentPrice: Double {
        max(0.0, totalInstallmentAmount - insuranceFee - adminFee)
    }

    /// Juros do mês atual calculados estritamente sobre o Saldo Devedor:
    /// $\text{Juros} = \text{Saldo Devedor} \times \left(\frac{\text{annualNominalInterestRate}}{12 \times 100}\right)$
    public var currentMonthlyInterest: Double {
        balance * monthlyNominalRateDecimal
    }

    /// Fração de Amortização Real do mês atual na Tabela Price:
    /// $\text{Amortização} = \text{Parcela Base Price} - \text{Juros}$
    public var currentMonthlyAmortization: Double {
        max(0.0, baseInstallmentPrice - currentMonthlyInterest)
    }

    public init(
        id: UUID = UUID(),
        balance: Double,
        annualNominalInterestRate: Double,
        amortizationSystem: AmortizationSystem = .price,
        indexationRate: FinancingIndexation = .tr,
        adminFee: Double = 25.0,
        insuranceFee: Double = 86.27,
        totalInstallments: Int = 360,
        remainingInstallments: Int = 332,
        totalInstallmentAmount: Double = 2658.04,
        lastBillingDate: Date? = nil
    ) {
        self.id = id
        self.balance = abs(balance)
        self.annualNominalInterestRate = abs(annualNominalInterestRate)
        self.amortizationSystem = amortizationSystem
        self.indexationRate = indexationRate
        self.adminFee = abs(adminFee)
        self.insuranceFee = abs(insuranceFee)
        self.totalInstallments = max(totalInstallments, 1)
        self.remainingInstallments = max(remainingInstallments, 0)
        self.totalInstallmentAmount = abs(totalInstallmentAmount)
        self.lastBillingDate = lastBillingDate
    }
}
