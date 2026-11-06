import Foundation
import AppKit
import PDFKit

public struct ParsedStatementTransaction: Identifiable, Hashable, Codable {
    public var id: UUID
    public var date: Date
    public var rawDescription: String
    public var cleanTitle: String
    public var extractedDetails: String
    public var paymentMethod: String
    public var amount: Double
    public var type: TransactionType
    public var suggestedCategoryId: UUID?
    public var suggestedCategoryName: String
    public var rawLine: String
    public var occurrenceIndex: Int

    public init(
        id: UUID = UUID(),
        date: Date,
        rawDescription: String,
        cleanTitle: String,
        extractedDetails: String,
        paymentMethod: String,
        amount: Double,
        type: TransactionType,
        suggestedCategoryId: UUID?,
        suggestedCategoryName: String,
        rawLine: String,
        occurrenceIndex: Int
    ) {
        self.id = id
        self.date = date
        self.rawDescription = rawDescription
        self.cleanTitle = cleanTitle
        self.extractedDetails = extractedDetails
        self.paymentMethod = paymentMethod
        self.amount = abs(amount)
        self.type = type
        self.suggestedCategoryId = suggestedCategoryId
        self.suggestedCategoryName = suggestedCategoryName
        self.rawLine = rawLine
        self.occurrenceIndex = occurrenceIndex
    }
}

public enum StatementImportService {

    /// Extrai texto de um arquivo PDF, CSV ou TXT do macOS
    public static func extractText(from fileURL: URL) -> String {
        let accessed = fileURL.startAccessingSecurityScopedResource()
        defer {
            if accessed { fileURL.stopAccessingSecurityScopedResource() }
        }

        let ext = fileURL.pathExtension.lowercased()
        if ext == "pdf", let pdf = PDFDocument(url: fileURL) {
            var fullText = ""
            for pageIndex in 0..<pdf.pageCount {
                if let page = pdf.page(at: pageIndex), let pageText = page.string {
                    fullText += pageText + "\n"
                }
            }
            if !fullText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return fullText
            }
        }

        if let utf8 = try? String(contentsOf: fileURL, encoding: .utf8) {
            return utf8
        }
        if let latin1 = try? String(contentsOf: fileURL, encoding: .isoLatin1) {
            return latin1
        }
        return ""
    }

    /// Analisa o texto bruto do extrato (no formato do anexo Itaú ou CSV/TXT) e separa transações
    /// por tipo (receita / despesa), categoria e máximo de detalhes sobre cada item.
    public static func parseStatementText(
        _ rawText: String,
        categories: [CategoryItem],
        filterMode: StatementImportFilterMode = .hybrid
    ) -> [ParsedStatementTransaction] {
        let lines = rawText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        // Regex para linhas de extrato: dd/MM/yyyy <descrição> <valor ex: -1.234,56 ou 5.237,00>
        let pattern = #"^(\d{2}/\d{2}/\d{4})\s+(.+?)\s+(-?\d{1,3}(?:\.\d{3})*,\d{2})$"#
        let regex = try? NSRegularExpression(pattern: pattern, options: [])

        var occurrenceCounter: [String: Int] = [:]
        var results: [ParsedStatementTransaction] = []

        for line in lines {
            let upper = line.uppercased()

            // Ignora linhas de saldo diário ou cabeçalhos
            if upper.contains("SALDO DO DIA") ||
               upper.contains("SALDO ANTERIOR") ||
               upper.contains("SALDO EM CONTA") ||
               upper.contains("LIMITE DA CONTA") ||
               upper.hasPrefix("PERÍODO DE VISUALIZAÇÃO") ||
               upper.hasPrefix("PERIODO DE VISUALIZACAO") ||
               upper.hasPrefix("DATA LANÇAMENTOS") ||
               upper.hasPrefix("DATA LANCAMENTOS") {
                continue
            }

            let nsLine = line as NSString
            guard let match = regex?.firstMatch(in: line, options: [], range: NSRange(location: 0, length: nsLine.length)),
                  match.numberOfRanges == 4 else {
                // Tenta formato CSV (data;descricao;valor)
                if let csvParsed = parseCSVLine(line, categories: categories, occurrenceCounter: &occurrenceCounter) {
                    if matchesFilter(csvParsed.type, filterMode: filterMode) {
                        results.append(csvParsed)
                    }
                }
                continue
            }

            let dateStr = nsLine.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)
            let rawDesc = nsLine.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespaces)
            let valStr = nsLine.substring(with: match.range(at: 3)).trimmingCharacters(in: .whitespaces)

            if rawDesc.uppercased().contains("SALDO DO DIA") {
                continue
            }

            guard let date = BRLFormatters.shortDateFormatter.date(from: dateStr),
                  let signedValue = BRLFormatters.parseAmount(valStr),
                  abs(signedValue) > 0.0001 else {
                continue
            }

            let txType: TransactionType = signedValue < 0 ? .expense : .income
            if !matchesFilter(txType, filterMode: filterMode) {
                continue
            }

            let normalizedLineKey = "\(dateStr)|\(rawDesc.uppercased())|\(String(format: "%.2f", signedValue))"
            let nextOccurrence = (occurrenceCounter[normalizedLineKey] ?? 0) + 1
            occurrenceCounter[normalizedLineKey] = nextOccurrence

            let analysis = analyzeTransactionDetailsAndCategory(
                rawDescription: rawDesc,
                postingDateString: dateStr,
                amount: abs(signedValue),
                type: txType,
                categories: categories
            )

            results.append(
                ParsedStatementTransaction(
                    date: date,
                    rawDescription: rawDesc,
                    cleanTitle: analysis.cleanTitle,
                    extractedDetails: analysis.details,
                    paymentMethod: analysis.paymentMethod,
                    amount: abs(signedValue),
                    type: txType,
                    suggestedCategoryId: analysis.category?.id,
                    suggestedCategoryName: analysis.category?.name ?? (txType == .expense ? "Outras Despesas" : "Outras Receitas"),
                    rawLine: "\(dateStr) \(rawDesc) \(valStr)",
                    occurrenceIndex: nextOccurrence
                )
            )
        }

        return results
    }

    private static func matchesFilter(_ type: TransactionType, filterMode: StatementImportFilterMode) -> Bool {
        switch filterMode {
        case .hybrid: return true
        case .expensesOnly: return type == .expense
        case .incomesOnly: return type == .income
        }
    }

    private static func parseCSVLine(
        _ line: String,
        categories: [CategoryItem],
        occurrenceCounter: inout [String: Int]
    ) -> ParsedStatementTransaction? {
        let parts = line.components(separatedBy: ";")
        guard parts.count >= 3 else { return nil }
        let dateStr = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let rawDesc = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        let valStr = parts[2].trimmingCharacters(in: .whitespacesAndNewlines)

        if rawDesc.uppercased().contains("SALDO DO DIA") { return nil }
        guard let date = BRLFormatters.shortDateFormatter.date(from: dateStr),
              let signedValue = BRLFormatters.parseAmount(valStr),
              abs(signedValue) > 0.0001 else {
            return nil
        }

        let txType: TransactionType = signedValue < 0 ? .expense : .income
        let normalizedLineKey = "\(dateStr)|\(rawDesc.uppercased())|\(String(format: "%.2f", signedValue))"
        let nextOccurrence = (occurrenceCounter[normalizedLineKey] ?? 0) + 1
        occurrenceCounter[normalizedLineKey] = nextOccurrence

        let analysis = analyzeTransactionDetailsAndCategory(
            rawDescription: rawDesc,
            postingDateString: dateStr,
            amount: abs(signedValue),
            type: txType,
            categories: categories
        )

        return ParsedStatementTransaction(
            date: date,
            rawDescription: rawDesc,
            cleanTitle: analysis.cleanTitle,
            extractedDetails: analysis.details,
            paymentMethod: analysis.paymentMethod,
            amount: abs(signedValue),
            type: txType,
            suggestedCategoryId: analysis.category?.id,
            suggestedCategoryName: analysis.category?.name ?? "Outros",
            rawLine: "\(dateStr) \(rawDesc) \(valStr)",
            occurrenceIndex: nextOccurrence
        )
    }

    // MARK: - Deep Statement Item Analyzer (Merchant, Channel, Original Date, Category)

    public static func analyzeTransactionDetailsAndCategory(
        rawDescription: String,
        postingDateString: String,
        amount: Double,
        type: TransactionType,
        categories: [CategoryItem]
    ) -> (cleanTitle: String, details: String, paymentMethod: String, category: CategoryItem?) {
        let upper = rawDescription.uppercased()
        var paymentMethod = "Movimentação Bancária"
        var cleanTitle = rawDescription
        var extraNotes: [String] = []

        // Detecta data de compra original embutida no final da descrição (ex: "PAY WANDO 31/10" liquidado em 03/11/2026)
        var embeddedPurchaseDayMonth: String? = nil
        if let range = rawDescription.range(of: #"\d{2}/\d{2}$"#, options: .regularExpression) {
            embeddedPurchaseDayMonth = String(rawDescription[range])
        }

        // Identifica modalidade da operação no padrão Itaú / Bancos Brasileiros
        if upper.hasPrefix("PIX QRS ") {
            paymentMethod = "PIX QR Code"
            let merchant = String(rawDescription.dropFirst("PIX QRS ".count))
                .replacingOccurrences(of: #"\d{2}/\d{2}$"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            cleanTitle = prettifyMerchantName(merchant, fallback: rawDescription)
            extraNotes.append("Pagamento instantâneo via PIX QR Code")
        } else if upper.hasPrefix("PIX TRANSF ") {
            paymentMethod = type == .income ? "PIX Recebido" : "PIX Enviado"
            let person = String(rawDescription.dropFirst("PIX TRANSF ".count))
                .replacingOccurrences(of: #"\d{2}/\d{2}$"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            cleanTitle = type == .income ? "PIX Recebido: \(person.capitalized)" : "PIX Enviado: \(person.capitalized)"
            extraNotes.append("Transferência PIX (\(person.capitalized))")
        } else if upper.hasPrefix("DEV PIX ") {
            paymentMethod = "Estorno / Devolução PIX"
            let origin = String(rawDescription.dropFirst("DEV PIX ".count))
                .replacingOccurrences(of: #"\d{2}/\d{2}$"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            cleanTitle = "Reembolso PIX: \(prettifyMerchantName(origin, fallback: origin))"
            extraNotes.append("Devolução/estorno de transação PIX")
        } else if upper.hasPrefix("PAY ") {
            paymentMethod = "Cartão Débito / Apple Pay"
            let merchant = String(rawDescription.dropFirst("PAY ".count))
                .replacingOccurrences(of: #"\d{2}/\d{2}$"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            cleanTitle = prettifyMerchantName(merchant, fallback: rawDescription)
            extraNotes.append("Compra presencial/cartão (PAY)")
        } else if upper.hasPrefix("PAG BOLETO ") {
            paymentMethod = "Pagamento de Boleto"
            let issuer = String(rawDescription.dropFirst("PAG BOLETO ".count)).trimmingCharacters(in: .whitespaces)
            cleanTitle = "Boleto: \(prettifyMerchantName(issuer, fallback: issuer))"
            extraNotes.append("Liquidação de boleto bancário")
        } else if upper.hasPrefix("PAGAMENTOCONTA ") {
            paymentMethod = "Pagamento de Concessionária"
            let util = String(rawDescription.dropFirst("PAGAMENTOCONTA ".count)).trimmingCharacters(in: .whitespaces)
            cleanTitle = "Conta: \(prettifyMerchantName(util, fallback: util))"
            extraNotes.append("Pagamento de conta de consumo/concessionária")
        } else if upper.hasPrefix("DA ") {
            paymentMethod = "Débito Automático"
            let provider = String(rawDescription.dropFirst("DA ".count)).trimmingCharacters(in: .whitespaces)
            cleanTitle = "Débito Automático: \(prettifyMerchantName(provider, fallback: provider))"
            extraNotes.append("Cobrança recorrente em débito automático")
        } else if upper.contains("APLICACAO COFRINHOS") {
            paymentMethod = "Aplicação em Cofrinhos"
            cleanTitle = "Aplicação Cofrinhos Itaú"
            extraNotes.append("Aporte automático/manual na reserva Cofrinhos")
        } else if upper.contains("RESGATE COFRINHOS") {
            paymentMethod = "Resgate de Cofrinhos"
            cleanTitle = "Resgate Cofrinhos Itaú"
            extraNotes.append("Resgate da reserva Cofrinhos para conta corrente")
        } else if upper.contains("APLICACAO CDB") {
            paymentMethod = "Aplicação em CDB"
            cleanTitle = "Aplicação CDB DI"
            extraNotes.append("Investimento em CDB pós-fixado DI")
        } else if upper.contains("RESGATE CDB") {
            paymentMethod = "Resgate de CDB"
            cleanTitle = "Resgate CDB DI"
            extraNotes.append("Resgate de CDB DI para conta corrente")
        } else if upper.contains("REND PAGO APLIC") {
            paymentMethod = "Rendimento Automático"
            cleanTitle = "Rendimento Aplicação Automática"
            extraNotes.append("Rendimento creditado em conta")
        }

        if let embedded = embeddedPurchaseDayMonth, !postingDateString.hasPrefix(embedded) {
            extraNotes.append("Data da operação original: \(embedded)")
        }
        extraNotes.append("Lançamento original: \(rawDescription)")

        let candidateCategories = categories.filter { $0.type == type }
        var matchedCategory: CategoryItem? = nil

        // Regras semânticas de alta precisão para os itens do extrato Itaú e gerais
        let semanticRules: [(keywords: [String], categorySubstring: String)] = [
            (["APLICACAO COFRINHOS", "APLICACAO CDB"], "Aplicações"),
            (["RESGATE COFRINHOS", "RESGATE CDB"], "Resgate"),
            (["REND PAGO"], "Rendimentos"),
            (["DEV PIX"], "Reembolso"),
            (["DELTA", "SAMS"], "Supermercado"),
            (["99 FOOD", "IFOOD", "KFC", "PIZZI", "DOCER", "ACAIF", "CACAU", "BACIO", "FRANG", "MACAR", "CEVAD", "SOPHI", "WANDO", "MR MI", "KCOWO", "MAJO", "CAPPT"], "Alimentação"),
            (["BBZ ADMINISTRACAO", "CONDOMI", "CASA", "OBRAM"], "Moradia"),
            (["CPFL", "COMGAS", "S.PIRACICAB"], "Energia"),
            (["VIVO", "CLARO", "TELEFONICA"], "Telefonia"),
            (["UBER", "MOBIFACIL"], "Transporte"),
            (["AUTO", "AUTOZ", "POSTO"], "Combustível"),
            (["MARKETP", "AMAZON", "HAVAN", "PAGAR ME", "LOJAS", "VOLLU", "L4U", "MP R", "58.269.906"], "Compras"),
            (["COBAS", "AGROM"], "Pets"),
            (["VSTP EDUCAC"], "Educação"),
            (["EVO V"], "Saúde"),
            (["BRADESCARD"], "Cartão de Crédito"),
            (["PIX TRANSF"], type == .income ? "PIX Recebido" : "Transferências")
        ]

        for rule in semanticRules {
            if rule.keywords.contains(where: { upper.contains($0) }) {
                if let found = candidateCategories.first(where: { $0.name.localizedCaseInsensitiveContains(rule.categorySubstring) }) {
                    matchedCategory = found
                    break
                }
            }
        }

        // Se não bateu nas regras prioritárias, verifica as keywords cadastradas nas categorias do usuário
        if matchedCategory == nil {
            for cat in candidateCategories {
                if cat.keywords.contains(where: { !$0.isEmpty && upper.contains($0.uppercased()) }) {
                    matchedCategory = cat
                    break
                }
            }
        }

        if matchedCategory == nil {
            matchedCategory = candidateCategories.first(where: { $0.name.localizedCaseInsensitiveContains("Outr") })
                ?? candidateCategories.first
        }

        return (
            cleanTitle: cleanTitle,
            details: extraNotes.joined(separator: " • "),
            paymentMethod: paymentMethod,
            category: matchedCategory
        )
    }

    private static func prettifyMerchantName(_ raw: String, fallback: String) -> String {
        let u = raw.uppercased()
        if u.contains("DELTA") { return "Supermercados Delta" }
        if u.contains("BBZ ADMINISTRACAO") { return "Condomínio BBZ Administração" }
        if u.contains("CPFL") { return "CPFL Energia Paulista" }
        if u.contains("S.PIRACICAB") { return "SEMAE Piracicaba (Água)" }
        if u.contains("COMGAS") { return "Comgás" }
        if u.contains("CLARO CELULAR") { return "Claro Celular" }
        if u.contains("VIVO-SP") { return "Vivo Fibra / Móvel (\(raw))" }
        if u.contains("TELEFONICA") { return "Vivo / Telefônica Brasil" }
        if u.contains("MOBIFACIL") { return "MobiFácil Passagens" }
        if u.contains("UBER") { return "Uber" }
        if u.contains("99 FOOD") { return "99Food Delivery" }
        if u.contains("IFOOD") { return "iFood Delivery" }
        if u.contains("COBAS") { return "Cobasi Pet Shop" }
        if u.contains("AGROM") { return "Agropecuária / Pet" }
        if u.contains("HAVAN") { return "Lojas Havan" }
        if u.contains("SAMS") { return "Sam's Club" }
        if u.contains("CACAU") { return "Cacau Show" }
        if u.contains("BACIO") { return "Bacio di Latte" }
        if u.contains("KFC") { return "KFC Restaurante" }
        if u.contains("AMAZON") { return "Amazon.com.br" }
        if u.contains("VSTP EDUCAC") { return "VSTP Educação" }
        if u.contains("BRADESCARD") { return "Fatura Cartão Bradescard" }
        if u.contains("MARKETP") { return "Mercado Livre / Marketplace" }
        if u.contains("PAGAR ME") { return "Pagar.me Pagamentos" }
        if u.contains("AUTOZ") || u == "AUTO" { return "Posto / Automotivo (\(raw))" }
        if u.contains("POSTO") { return "Posto de Combustível" }
        if u.contains("OBRAM") { return "Obramax Construção" }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}

// MARK: - Complete Attached Itaú Statement Data (Pages 1 to 4 of user's PDF)

public enum SampleItauStatementData {
    public static let rawOCRText: String = """
    CLOVIS CARMEZINI JUNIOR 396.520.318-52 agência: 0731 conta: 080047-0
    saldo em conta Limite da Conta utilizado Limite da Conta disponível Limite da Conta total *
    R$ 3.855,67 R$ 0,00 R$ 0,00 R$ 0,00
    extrato conta / lançamentos
    período de visualização: 06/09/2026 até 05/11/2026 emitido em: 05/11/2026 10:48:44
    data lançamentos valor (R$) saldo (R$)
    05/11/2026 SALDO DO DIA 3.855,67
    05/11/2026 PIX QRS PIX Marketp05/11 -44,99
    04/11/2026 PIX TRANSF CLOVIS 04/11 5.237,00
    04/11/2026 PAY DELTA 04/11 -12,00
    04/11/2026 PAG BOLETO BBZ ADMINISTRACAO DE CONDOMI -750,88
    04/11/2026 PIX QRS CPFL PAULIS04/11 -270,41
    04/11/2026 PAY AUTOZ 04/11 -92,97
    04/11/2026 APLICACAO COFRINHOS -714,00
    04/11/2026 RESGATE COFRINHOS 865,55
    04/11/2026 APLICACAO COFRINHOS -865,00
    04/11/2026 SALDO DO DIA 3.900,65
    03/11/2026 PAGAMENTOCONTA S.PIRACICAB -68,00
    03/11/2026 PAY WANDO 31/10 -154,50
    03/11/2026 PAY OBRAM 01/11 -135,32
    03/11/2026 PIX TRANSF JEFFERS02/11 -200,00
    03/11/2026 PAY MR MI 02/11 -75,87
    03/11/2026 PAY Pizzi 03/11 -39,00
    03/11/2026 PAY AUTO 03/11 -100,00
    03/11/2026 RESGATE COFRINHOS 40,01
    03/11/2026 RESGATE COFRINHOS 500,00
    03/11/2026 DA CLARO CELULAR 8 -29,90
    03/11/2026 DA VIVO-SP 13784367 -111,00
    03/11/2026 DA VIVO-SP 13783279 -80,47
    03/11/2026 SALDO DO DIA 503,36
    30/10/2026 PIX QRS Pagar Me Pa30/10 -50,00
    30/10/2026 PIX QRS PIX Marketp30/10 -35,89
    30/10/2026 SALDO DO DIA 957,41
    29/10/2026 PIX QRS UBER DO BRA29/10 -18,94
    29/10/2026 PIX TRANSF CLOVIS 29/10 1.361,00
    29/10/2026 PAGAMENTOCONTA CPFL -290,94
    29/10/2026 PIX QRS MOBIFACIL S29/10 -131,06
    29/10/2026 DEV PIX MOBIFACIL S29/10 113,78
    29/10/2026 PIX QRS MOBIFACIL S29/10 -131,06
    29/10/2026 DEV PIX MOBIFACIL S29/10 113,78
    29/10/2026 PAY MP R 29/10 -30,00
    29/10/2026 PAY Uber 29/10 -15,95
    29/10/2026 SALDO DO DIA 1.043,30
    28/10/2026 RESGATE COFRINHOS 200,01
    28/10/2026 PAY 62 02 28/10 -84,00
    28/10/2026 PAY Fabio 28/10 -21,00
    28/10/2026 PAY Elain 28/10 -25,00
    28/10/2026 PAY DOCER 28/10 -29,00
    28/10/2026 PAY POSTO 28/10 -86,00
    28/10/2026 RESGATE COFRINHOS 300,01
    28/10/2026 PIX QRS MOBIFACIL S28/10 -227,56
    28/10/2026 SALDO DO DIA 72,69
    27/10/2026 PAY CASA 27/10 -29,16
    27/10/2026 SALDO DO DIA 45,23
    26/10/2026 PIX QRS TELEFONICA 24/10 -64,00
    26/10/2026 PIX TRANSF BRENDA 24/10 1.000,00
    26/10/2026 APLICACAO COFRINHOS -1.000,00
    26/10/2026 RESGATE COFRINHOS 1.000,00
    26/10/2026 APLICACAO COFRINHOS -1.000,00
    26/10/2026 PIX QRS 99 FOOD24/10 -52,65
    26/10/2026 PIX QRS 99 FOOD LTD25/10 -57,59
    26/10/2026 PAY AGROM 26/10 -74,40
    26/10/2026 PIX QRS MOBIFACIL S26/10 -210,86
    26/10/2026 SALDO DO DIA 74,39
    23/10/2026 PAY 60388 23/10 -20,48
    23/10/2026 SALDO DO DIA 533,89
    22/10/2026 PIX TRANSF CLOVIS 22/10 557,81
    22/10/2026 PAY DELTA 22/10 -49,15
    22/10/2026 PAY Kcowo 22/10 -10,00
    22/10/2026 SALDO DO DIA 554,37
    21/10/2026 PIX TRANSF CLOVIS 21/10 -20,00
    21/10/2026 PAY MAHDR 21/10 -3,00
    21/10/2026 SALDO DO DIA 55,71
    20/10/2026 PAY DELTA 20/10 -17,02
    20/10/2026 PAY DELTA 20/10 -5,97
    20/10/2026 PAY AUTO 20/10 -120,00
    20/10/2026 SALDO DO DIA 78,71
    19/10/2026 PAY JIM C 17/10 -15,00
    19/10/2026 PAY MIKA 17/10 -52,00
    19/10/2026 PAY EVO V 17/10 -82,00
    19/10/2026 RESGATE COFRINHOS 400,01
    19/10/2026 PIX QRS 99 FOOD17/10 -59,81
    19/10/2026 PIX TRANSF Michel 17/10 -190,00
    19/10/2026 PAY SOPHI 17/10 -17,99
    19/10/2026 PAY KFC S 17/10 -19,90
    19/10/2026 PAY CEVAD 17/10 -17,00
    19/10/2026 PAY SP PI 17/10 -28,90
    19/10/2026 RESGATE COFRINHOS 450,09
    19/10/2026 PIX TRANSF DANIELE18/10 82,00
    19/10/2026 PAY CASA 18/10 -37,92
    19/10/2026 PAY COBAS 18/10 -258,29
    19/10/2026 PAY DELTA 19/10 -11,99
    19/10/2026 DA COMGAS 46147195 -158,46
    19/10/2026 SALDO DO DIA 221,70
    16/10/2026 PAY Pizzi 16/10 -26,00
    16/10/2026 PIX TRANSF BRENDA 16/10 -50,00
    16/10/2026 SALDO DO DIA 238,86
    15/10/2026 RESGATE COFRINHOS 99,68
    15/10/2026 APLICACAO COFRINHOS -850,00
    15/10/2026 PIX QRS 58.269.906 15/10 -10,00
    15/10/2026 PAY HAVAN 15/10 -62,98
    15/10/2026 PIX TRANSF BRENDA 15/10 -112,00
    15/10/2026 SALDO DO DIA 314,86
    14/10/2026 PAY DELTA 14/10 -8,42
    14/10/2026 PIX TRANSF BRENDA 14/10 -130,00
    14/10/2026 PIX TRANSF CLOVIS 14/10 1.000,00
    14/10/2026 SALDO DO DIA 1.250,16
    13/10/2026 PIX TRANSF CLOVIS 10/10 -5,00
    13/10/2026 RESGATE COFRINHOS 500,01
    13/10/2026 PAG BOLETO BANCO BRADESCARD S A -500,00
    13/10/2026 PAY AcaiF 11/10 -40,00
    13/10/2026 PAY AUTO 11/10 -80,00
    13/10/2026 RESGATE COFRINHOS 500,01
    13/10/2026 PAY DELTA 12/10 -25,31
    13/10/2026 PIX QRS IFOOD.COM A12/10 -100,27
    13/10/2026 PIX QRS IFOOD.COM A12/10 -55,00
    13/10/2026 RESGATE COFRINHOS 70,79
    13/10/2026 PAY DELTA 12/10 -8,49
    13/10/2026 SALDO DO DIA 388,58
    08/10/2026 PAY MAJO 08/10 -53,00
    08/10/2026 PAY SAMS 08/10 -249,93
    08/10/2026 PAY CACAU 08/10 -30,44
    08/10/2026 PIX QRS 99 FOOD LTD08/10 -46,42
    08/10/2026 SALDO DO DIA 131,84
    07/10/2026 PAY FRANG 07/10 -49,50
    07/10/2026 PAY CASA 07/10 -35,00
    07/10/2026 PAY 67714 07/10 -32,00
    07/10/2026 SALDO DO DIA 511,63
    06/10/2026 PIX TRANSF BRENDA 06/10 900,00
    06/10/2026 RESGATE CDB DI 1.172,14
    06/10/2026 APLICACAO COFRINHOS -1.170,00
    06/10/2026 APLICACAO COFRINHOS -900,00
    06/10/2026 PIX TRANSF MIGUEL 06/10 -95,50
    06/10/2026 PIX TRANSF CLOVIS 06/10 211,58
    06/10/2026 PAY CAPPT 06/10 -7,00
    06/10/2026 PAY DELTA 06/10 -10,34
    06/10/2026 SALDO DO DIA 628,13
    05/10/2026 PIX QRS 99 FOOD03/10 -35,75
    05/10/2026 PAY L4U L 03/10 -137,69
    05/10/2026 PAY MACAR 03/10 -65,98
    05/10/2026 PAY Bacio 03/10 -29,95
    05/10/2026 PAY VOLLU 03/10 -22,99
    05/10/2026 PAY LOJAS 03/10 -52,96
    05/10/2026 PAY Kcowo 05/10 -10,00
    05/10/2026 PIX QRS AMAZON COM 05/10 -89,99
    05/10/2026 SALDO DO DIA 527,25
    02/10/2026 PIX TRANSF CLOVIS 02/10 3.900,00
    02/10/2026 PIX TRANSF BRENDA 02/10 -681,88
    02/10/2026 PIX QRS VSTP EDUCAC02/10 -996,00
    02/10/2026 APLICACAO CDB DI -1.172,00
    02/10/2026 PIX QRS 99 FOOD LTD02/10 -50,63
    02/10/2026 PAY 60388 02/10 -19,96
    02/10/2026 PAY 60388 02/10 -6,99
    02/10/2026 SALDO DO DIA 972,56
    15/09/2026 PIX TRANSF CLOVIS 15/09 -450,00
    15/09/2026 REND PAGO APLIC AUT MAIS 0,02
    15/09/2026 SALDO DO DIA 0,02
    05/09/2026 SALDO DO DIA 450,00
    """

    public static func ensureSamplePDFExists(in directory: URL) -> URL {
        let pdfURL = directory.appendingPathComponent("Extrato_Itau_2026_Anexo.pdf")
        if !FileManager.default.fileExists(atPath: pdfURL.path) {
            let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 595, height: 2400))
            textView.string = rawOCRText
            textView.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
            let pdfData = textView.dataWithPDF(inside: textView.bounds)
            try? pdfData.write(to: pdfURL)
        }
        return pdfURL
    }
}
