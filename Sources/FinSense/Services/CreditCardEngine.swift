import Foundation

/// Motor determinístico e exato de ciclo de faturamento, alocação de faturas, cálculo de limites
/// e divisão monetária sem perda de centavos para Cartões de Crédito no FinSense.
public enum CreditCardEngine {

    public struct AllocatedInvoiceCycle: Hashable, Sendable {
        public let year: Int
        public let month: Int
        public let yearMonthKey: Int
        public let closingDate: Date
        public let dueDate: Date
    }

    /// Sugere automaticamente o Melhor Dia de Compra a partir do Dia de Fechamento.
    public static func suggestedBestPurchaseDay(forClosingDay closingDay: Int) -> Int {
        let clamped = min(max(closingDay, 1), 31)
        return clamped >= 31 ? 1 : (clamped + 1)
    }

    /// Retorna a quantidade de dias em um mês específico.
    public static func daysInMonth(year: Int, month: Int, calendar: Calendar = .current) -> Int {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = 1
        guard let date = calendar.date(from: comps),
              let range = calendar.range(of: .day, in: .month, for: date) else {
            return 28
        }
        return range.count
    }

    /// Constrói uma data segura no meio do dia (12:00) ajustando dias como 29/30/31 ao último dia válido do mês.
    public static func clampedDate(year: Int, month: Int, day: Int, calendar: Calendar = .current) -> Date {
        let maxDay = daysInMonth(year: year, month: month, calendar: calendar)
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = min(max(day, 1), maxDay)
        comps.hour = 12
        comps.minute = 0
        comps.second = 0
        return calendar.date(from: comps) ?? Date()
    }

    /// Soma `offsetMonths` a um par (ano, mês) mantendo normalização de virada de ano.
    public static func addMonths(_ offsetMonths: Int, toYear year: Int, month: Int) -> (year: Int, month: Int, yearMonthKey: Int) {
        let totalMonths = (year * 12 + (month - 1)) + offsetMonths
        let resolvedYear = totalMonths >= 0 ? (totalMonths / 12) : ((totalMonths - 11) / 12)
        let resolvedMonth = ((totalMonths % 12) + 12) % 12 + 1
        return (resolvedYear, resolvedMonth, resolvedYear * 100 + resolvedMonth)
    }

    public static func yearMonthComponents(fromKey key: Int) -> (year: Int, month: Int) {
        let year = key / 100
        let month = max(1, min(12, key % 100))
        return (year, month)
    }

    /// Determina a fatura mensal (`year`, `month`, `yearMonthKey`, `closingDate`, `dueDate`) à qual uma compra na `purchaseDate` pertence.
    ///
    /// Regra determinística:
    /// 1. Compara o dia da compra ao `bestPurchaseDay` e `closingDay` do cartão para identificar o mês de fechamento do ciclo.
    ///    - Se `bestPurchaseDay > closingDay` (ex: fecha dia 25, melhor dia 26): compras com `dia >= bestPurchaseDay` entram no próximo fechamento.
    ///    - Se `bestPurchaseDay == closingDay` (ex: fecha dia 10, melhor dia 10): compras com `dia >= fechamento efetivo` entram no próximo fechamento.
    ///    - Se `bestPurchaseDay < closingDay` (ex: fecha dia 31, melhor dia 1): compras após o fechamento efetivo (`dia > fechamento efetivo`) entram no próximo fechamento.
    /// 2. A partir do mês de fechamento:
    ///    - Se `dueDay > closingDay` (ex: fecha 05, vence 12), o vencimento ocorre no mesmo mês do fechamento.
    ///    - Se `dueDay <= closingDay` (ex: fecha 25, vence 05), o vencimento ocorre no mês seguinte ao fechamento.
    ///    O identificador (`year`, `month`) da fatura sempre representa o mês/ano do vencimento ("Fatura de Dez/2026").
    public static func allocateInvoice(
        forPurchaseDate purchaseDate: Date,
        card: CreditCard,
        calendar: Calendar = .current
    ) -> AllocatedInvoiceCycle {
        let comps = calendar.dateComponents([.year, .month, .day], from: purchaseDate)
        let y = comps.year ?? 2026
        let m = comps.month ?? 1
        let d = comps.day ?? 1

        let dim = daysInMonth(year: y, month: m, calendar: calendar)
        let effectiveClosingDay = min(card.closingDay, dim)

        let rollsToNextClosingMonth: Bool
        if card.bestPurchaseDay > card.closingDay {
            rollsToNextClosingMonth = d >= card.bestPurchaseDay
        } else if card.bestPurchaseDay == card.closingDay {
            rollsToNextClosingMonth = d >= effectiveClosingDay
        } else {
            rollsToNextClosingMonth = d > effectiveClosingDay
        }

        let closingYM = rollsToNextClosingMonth ? addMonths(1, toYear: y, month: m) : (year: y, month: m, yearMonthKey: y * 100 + m)
        let dueYM = card.dueDay > card.closingDay
            ? closingYM
            : addMonths(1, toYear: closingYM.year, month: closingYM.month)

        let dates = closingAndDueDates(forInvoiceYear: dueYM.year, month: dueYM.month, card: card, calendar: calendar)
        return AllocatedInvoiceCycle(
            year: dueYM.year,
            month: dueYM.month,
            yearMonthKey: dueYM.yearMonthKey,
            closingDate: dates.closingDate,
            dueDate: dates.dueDate
        )
    }

    /// Calcula as datas exatas de fechamento e vencimento para uma fatura identificada pelo mês/ano de vencimento.
    public static func closingAndDueDates(
        forInvoiceYear year: Int,
        month: Int,
        card: CreditCard,
        calendar: Calendar = .current
    ) -> (closingDate: Date, dueDate: Date) {
        let dueDate = clampedDate(year: year, month: month, day: card.dueDay, calendar: calendar)
        let closingYM = card.dueDay > card.closingDay
            ? (year: year, month: month, yearMonthKey: year * 100 + month)
            : addMonths(-1, toYear: year, month: month)
        let closingDate = clampedDate(year: closingYM.year, month: closingYM.month, day: card.closingDay, calendar: calendar)
        return (closingDate, dueDate)
    }

    /// Calcula o estado atual da fatura (`Aberta`, `Fechada` ou `Paga`) considerando a data de referência.
    public static func invoiceStatus(
        isPaid: Bool,
        invoiceYear: Int,
        invoiceMonth: Int,
        card: CreditCard,
        referenceNow: Date = Date(),
        calendar: Calendar = .current
    ) -> CreditCardInvoiceStatus {
        if isPaid {
            return .paid
        }

        let dates = closingAndDueDates(forInvoiceYear: invoiceYear, month: invoiceMonth, card: card, calendar: calendar)
        let todayStart = calendar.startOfDay(for: referenceNow)
        let closingStart = calendar.startOfDay(for: dates.closingDate)

        // Quando bestPurchaseDay > closingDay, o dia de fechamento ainda aceita compras até o fim do dia;
        // a fatura vira "Fechada" a partir do dia seguinte ao fechamento (bestPurchaseDay).
        let closedCutoffStart: Date = {
            if card.bestPurchaseDay > card.closingDay {
                return calendar.date(byAdding: .day, value: 1, to: closingStart) ?? closingStart
            } else if card.bestPurchaseDay == card.closingDay {
                return closingStart
            } else {
                return calendar.date(byAdding: .day, value: 1, to: closingStart) ?? closingStart
            }
        }()

        return todayStart >= closedCutoffStart ? .closed : .open
    }

    /// Divide um valor total em `count` parcelas exatas em centavos (`Int`).
    /// Qualquer diferença residual de divisão (ex: R$ 100,00 em 3x -> R$ 0,01) é absorvida integralmente na 1ª parcela.
    public static func splitInstallmentsExactCents(totalAmount: Double, count: Int) -> [Double] {
        let cleanCount = max(1, count)
        let totalCents = Int((abs(totalAmount) * 100.0).rounded())
        let baseCents = totalCents / cleanCount
        let remainderCents = totalCents % cleanCount

        var result: [Double] = []
        result.reserveCapacity(cleanCount)
        for index in 0..<cleanCount {
            let cents = index == 0 ? (baseCents + remainderCents) : baseCents
            result.append(Double(cents) / 100.0)
        }
        return result
    }

    /// Soma exata em centavos para evitar ruído binário de `Double` nos totais de fatura e limite.
    public static func exactSum(_ values: [Double]) -> Double {
        let totalCents = values.reduce(0) { acc, val in
            acc + Int((val * 100.0).rounded())
        }
        return Double(totalCents) / 100.0
    }

    /// Formata rótulo curto da fatura (ex: "Dez/26").
    public static func shortInvoiceLabel(year: Int, month: Int, calendar: Calendar = .current) -> String {
        let date = clampedDate(year: year, month: month, day: 15, calendar: calendar)
        return BRLFormatters.shortMonthYearFormatter.string(from: date).capitalized.replacingOccurrences(of: ".", with: "")
    }

    /// Formata rótulo completo da fatura (ex: "Dezembro 2026").
    public static func fullInvoiceLabel(year: Int, month: Int, calendar: Calendar = .current) -> String {
        let date = clampedDate(year: year, month: month, day: 15, calendar: calendar)
        return BRLFormatters.monthYear(date)
    }
}
