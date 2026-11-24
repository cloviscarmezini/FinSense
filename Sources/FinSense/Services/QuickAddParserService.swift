import Foundation

public struct QuickAddDraft: Sendable {
    public var cleanTitle: String
    public var amount: Double
    public var type: TransactionType
    public var date: Date
    public var categoryId: UUID
    public var targetAccountId: UUID?
    public var targetCreditCardId: UUID?
    public var installmentsCount: Int
    public var recurrenceMode: TransactionRecurrenceMode
    public var isReimbursable: Bool
    public var reimbursableAmount: Double?
    public var reimbursableDebtor: String?
    public var currencyCode: String
    public var usedAI: Bool

    public init(
        cleanTitle: String,
        amount: Double,
        type: TransactionType = .expense,
        date: Date = Date(),
        categoryId: UUID,
        targetAccountId: UUID? = nil,
        targetCreditCardId: UUID? = nil,
        installmentsCount: Int = 1,
        recurrenceMode: TransactionRecurrenceMode = .single,
        isReimbursable: Bool = false,
        reimbursableAmount: Double? = nil,
        reimbursableDebtor: String? = nil,
        currencyCode: String = "BRL",
        usedAI: Bool = false
    ) {
        self.cleanTitle = cleanTitle
        self.amount = amount
        self.type = type
        self.date = date
        self.categoryId = categoryId
        self.targetAccountId = targetAccountId
        self.targetCreditCardId = targetCreditCardId
        self.installmentsCount = max(1, installmentsCount)
        self.recurrenceMode = recurrenceMode
        self.isReimbursable = isReimbursable
        self.reimbursableAmount = reimbursableAmount
        self.reimbursableDebtor = reimbursableDebtor
        self.currencyCode = currencyCode
        self.usedAI = usedAI
    }
}

/// Interpretador instantâneo de linguagem natural para a Barra Rápida Global (Quick-Add)
/// com suporte a parcelas ("3x"), cartão/conta destino, moedas ("USD", "EUR") e reembolso ("reembolsável Empresa").
public enum QuickAddParserService {
    public static func normalize(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR"))
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @MainActor
    public static func parse(_ rawInput: String, store: FinancialDataStore) -> QuickAddDraft {
        let trimmed = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        var working = trimmed
        let normFull = normalize(trimmed)

        // 1. Tipo (receita vs despesa)
        let isIncome = normFull.contains("recebi") || normFull.contains("receita ") ||
            normFull.hasPrefix("receita") || normFull.contains("salario") ||
            normFull.contains("freela") || normFull.contains("dividendo")
        let txType: TransactionType = isIncome ? .income : .expense

        // 2. Moeda explícita (com fronteira de palavra para evitar falso positivo em palavras como "merCADo")
        var currencyCode = "BRL"
        let symbolCurrencies: [(symbol: String, code: String)] = [
            ("US$", "USD"), ("U$", "USD"), ("€", "EUR"), ("£", "GBP"), ("C$", "CAD"), ("A$", "AUD"), ("¥", "JPY")
        ]
        for entry in symbolCurrencies {
            if working.localizedCaseInsensitiveContains(entry.symbol) {
                currencyCode = entry.code
                working = working.replacingOccurrences(of: entry.symbol, with: " ", options: .caseInsensitive)
                break
            }
        }
        if currencyCode == "BRL" {
            let wordCurrencies: [(tokens: [String], code: String)] = [
                (["usd", "dolar", "dolares", "dólar", "dólares"], "USD"),
                (["eur", "euro", "euros"], "EUR"),
                (["gbp", "libra", "libras"], "GBP"),
                (["cad"], "CAD"),
                (["chf", "franco"], "CHF"),
                (["aud"], "AUD"),
                (["jpy", "iene", "ienes"], "JPY")
            ]
            for entry in wordCurrencies {
                for token in entry.tokens {
                    let pat = #"(?i)(?:^|\s)"# + NSRegularExpression.escapedPattern(for: token) + #"(?:\s|$)"#
                    if let rx = try? NSRegularExpression(pattern: pat),
                       let match = rx.firstMatch(in: working, range: NSRange(working.startIndex..<working.endIndex, in: working)),
                       let rFull = Range(match.range(at: 0), in: working) {
                        currencyCode = entry.code
                        working.replaceSubrange(rFull, with: " ")
                        break
                    }
                }
                if currencyCode != "BRL" { break }
            }
        }

        // 3. Parcelas ("em 3x", "3x", "10 parcelas")
        var installmentsCount = 1
        let instPatterns = [
            #"(?i)\b(?:em\s+)?(\d{1,2})\s*x\b"#,
            #"(?i)\b(\d{1,2})\s*parcelas?\b"#
        ]
        for pat in instPatterns {
            if let regex = try? NSRegularExpression(pattern: pat),
               let m = regex.firstMatch(in: working, range: NSRange(working.startIndex..<working.endIndex, in: working)),
               m.numberOfRanges >= 2,
               let rFull = Range(m.range(at: 0), in: working),
               let rNum = Range(m.range(at: 1), in: working),
               let count = Int(working[rNum]), count >= 2, count <= 36 {
                installmentsCount = count
                working.removeSubrange(rFull)
                break
            }
        }

        // 4. Valor monetário (ex: 185 | 185,50 | 1.200,00 | R$ 250)
        var parsedAmount = 0.0
        let cleanForAmt = working.replacingOccurrences(of: "R$", with: "", options: .caseInsensitive)
        if let amtRegex = try? NSRegularExpression(pattern: #"\b(\d{1,3}(?:\.\d{3})*(?:,\d{1,2})|\d+(?:[.,]\d{1,2})?)\b"#),
           let match = amtRegex.firstMatch(in: cleanForAmt, range: NSRange(cleanForAmt.startIndex..<cleanForAmt.endIndex, in: cleanForAmt)),
           let rAmt = Range(match.range(at: 1), in: cleanForAmt) {
            let amtStr = String(cleanForAmt[rAmt])
            parsedAmount = BRLFormatters.parseAmount(amtStr) ?? 0.0
            if let origRange = working.range(of: amtStr) {
                working.removeSubrange(origRange)
            }
        }

        // 5. Reembolsável / A Receber ("reembolsavel empresa" / "reembolso joao")
        var isReimbursable = false
        var debtor: String? = nil
        if let reimbRegex = try? NSRegularExpression(pattern: #"(?i)\b(reembols[aá]vel|reembolso|a receber)(?:\s+(?:de|da|do|pela|pelo|para)?\s*([a-zA-ZÀ-ÿ0-9_\- ]{2,28}))?"#),
           let match = reimbRegex.firstMatch(in: working, range: NSRange(working.startIndex..<working.endIndex, in: working)),
           let rFull = Range(match.range(at: 0), in: working) {
            isReimbursable = true
            if match.numberOfRanges > 2,
               let rDeb = Range(match.range(at: 2), in: working) {
                let candidate = String(working[rDeb]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !candidate.isEmpty {
                    debtor = candidate.capitalized
                }
            }
            working.removeSubrange(rFull)
        }

        // 6. Cartão de Crédito ou Conta destino (matching case/diacritic-insensitive)
        var matchedCard: CreditCard? = nil
        var matchedAccount: BankAccount? = nil
        let normWorking = normalize(working)

        let sortedCards = store.creditCards.sorted { $0.name.count > $1.name.count }
        for card in sortedCards {
            let cardNorm = normalize(card.name)
            if !cardNorm.isEmpty && (normFull.contains(cardNorm) || normWorking.contains(cardNorm)) {
                matchedCard = card
                working = removeCaseInsensitiveToken(card.name, from: working)
                break
            }
            if !card.lastFourDigits.isEmpty && normFull.contains(card.lastFourDigits) {
                matchedCard = card
                break
            }
        }

        if matchedCard == nil {
            let sortedAccounts = store.accounts.sorted { $0.name.count > $1.name.count }
            for acc in sortedAccounts {
                let accNorm = normalize(acc.name)
                if !accNorm.isEmpty && (normFull.contains(accNorm) || normWorking.contains(accNorm)) {
                    matchedAccount = acc
                    working = removeCaseInsensitiveToken(acc.name, from: working)
                    break
                }
            }
        }

        // Fallback se mencionou "cartao" ou "credito" mas não bateu nome exato
        if matchedCard == nil && matchedAccount == nil && (normFull.contains("cartao") || installmentsCount >= 2) {
            matchedCard = store.creditCards.first
        }
        if matchedCard == nil && matchedAccount == nil {
            matchedAccount = store.accounts.first
        }

        // 7. Limpeza do título
        let fillerWords = ["em", "no", "na", "do", "da", "de", "para", "por", "r$", "via", "com", "cartao"]
        var tokens = working
            .replacingOccurrences(of: "r$", with: "", options: .caseInsensitive)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        while let first = tokens.first, fillerWords.contains(normalize(first)) {
            tokens.removeFirst()
        }
        while let last = tokens.last, fillerWords.contains(normalize(last)) {
            tokens.removeLast()
        }
        let cleanTitleRaw = tokens.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanTitle = cleanTitleRaw.isEmpty
            ? (txType == .income ? "Receita Rápida" : "Despesa Rápida")
            : cleanTitleRaw.prefix(1).uppercased() + cleanTitleRaw.dropFirst()

        // 8. Regras determinísticas + inferência de categoria
        let fallbackCatId = store.fallbackCategoryId(for: txType)
        let analyzed = StatementImportService.analyzeTransactionDetailsAndCategory(
            rawDescription: trimmed,
            postingDateString: BRLFormatters.shortDate(store.effectiveCurrentDate),
            amount: parsedAmount,
            type: txType,
            categories: store.categories
        )

        var resolvedCategoryId = analyzed.category?.id ?? fallbackCatId
        var finalTitle = cleanTitle
        var finalReimbursable = isReimbursable
        var finalDebtor = debtor

        if let ruleOutcome = ReconciliationRulesEngine.firstMatch(
            rules: store.reconciliationRules,
            name: cleanTitle,
            details: trimmed,
            rawStatementLine: trimmed,
            amount: parsedAmount,
            accountId: matchedAccount?.id,
            creditCardId: matchedCard?.id
        ) {
            if let catId = ruleOutcome.appliedCategoryId {
                resolvedCategoryId = catId
            }
            if let ruleClean = ruleOutcome.appliedCleanName {
                finalTitle = ruleClean
            }
            if ruleOutcome.markedReimbursable {
                finalReimbursable = true
                if finalDebtor == nil {
                    finalDebtor = ruleOutcome.reimbursableDebtor
                }
            }
        }

        if let matchedAccount, currencyCode == "BRL" && matchedAccount.currencyCode != "BRL" {
            currencyCode = matchedAccount.currencyCode
        }

        return QuickAddDraft(
            cleanTitle: finalTitle,
            amount: parsedAmount,
            type: txType,
            date: store.effectiveCurrentDate,
            categoryId: resolvedCategoryId,
            targetAccountId: matchedCard == nil ? matchedAccount?.id : nil,
            targetCreditCardId: txType == .expense ? matchedCard?.id : nil,
            installmentsCount: txType == .expense ? installmentsCount : 1,
            recurrenceMode: (txType == .expense && installmentsCount >= 2) ? .installment : .single,
            isReimbursable: finalReimbursable,
            reimbursableAmount: finalReimbursable ? parsedAmount : nil,
            reimbursableDebtor: finalDebtor,
            currencyCode: currencyCode,
            usedAI: false
        )
    }

    private static func removeCaseInsensitiveToken(_ token: String, from text: String) -> String {
        let normToken = normalize(token)
        guard !normToken.isEmpty else { return text }
        let parts = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        let filtered = parts.filter { word in
            !normToken.components(separatedBy: " ").contains(normalize(word)) || normalize(word).count < 3
        }
        return filtered.joined(separator: " ")
    }
}
