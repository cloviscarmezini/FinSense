import Foundation

public struct ReconciliationMatchOutcome: Sendable {
    public let matchedRule: ReconciliationRule
    public let appliedCategoryId: UUID?
    public let appliedCleanName: String?
    public let markedRecurring: Bool
    public let markedReimbursable: Bool
    public let reimbursableDebtor: String?
    public let markedIgnoreInConsolidated: Bool?
}

/// Motor determinístico de regras de conciliação.
/// Avalia regras ativas por prioridade crescente antes de acionar qualquer LLM local,
/// reduzindo latência e garantindo consistência determinística em importações e lançamentos Apple Pay.
public enum ReconciliationRulesEngine {
    public static func normalizeText(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func matches(
        rule: ReconciliationRule,
        name: String,
        details: String = "",
        rawStatementLine: String? = nil,
        amount: Double,
        accountId: UUID? = nil,
        creditCardId: UUID? = nil
    ) -> Bool {
        guard rule.isEnabled else { return false }
        let trimmedPattern = rule.matchPattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPattern.isEmpty else { return false }

        if let minAmt = rule.minAmount, abs(amount) + 0.0001 < minAmt {
            return false
        }
        if let maxAmt = rule.maxAmount, abs(amount) - 0.0001 > maxAmt {
            return false
        }
        if let reqAccId = rule.sourceAccountId, reqAccId != accountId {
            return false
        }
        if let reqCardId = rule.sourceCreditCardId, reqCardId != creditCardId {
            return false
        }

        let targetText: String = {
            switch rule.matchField {
            case .nameOrDetails:
                return "\(name) \(details)".trimmingCharacters(in: .whitespacesAndNewlines)
            case .nameOnly:
                return name
            case .rawStatementLine:
                return (rawStatementLine?.isEmpty == false ? rawStatementLine : "\(name) \(details)") ?? name
            }
        }()

        switch rule.matchOperator {
        case .contains:
            return normalizeText(targetText).contains(normalizeText(trimmedPattern))
        case .startsWith:
            return normalizeText(targetText).hasPrefix(normalizeText(trimmedPattern))
        case .equals:
            return normalizeText(name) == normalizeText(trimmedPattern) || normalizeText(targetText) == normalizeText(trimmedPattern)
        case .regex:
            guard let regex = try? NSRegularExpression(pattern: trimmedPattern, options: [.caseInsensitive]) else {
                return false
            }
            let nsRange = NSRange(targetText.startIndex..<targetText.endIndex, in: targetText)
            return regex.firstMatch(in: targetText, options: [], range: nsRange) != nil
        }
    }

    public static func firstMatch(
        rules: [ReconciliationRule],
        name: String,
        details: String = "",
        rawStatementLine: String? = nil,
        amount: Double,
        accountId: UUID? = nil,
        creditCardId: UUID? = nil
    ) -> ReconciliationMatchOutcome? {
        let sortedRules = rules
            .filter(\.isEnabled)
            .sorted { a, b in
                if a.priority == b.priority {
                    return a.createdAt < b.createdAt
                }
                return a.priority < b.priority
            }

        for rule in sortedRules {
            if matches(
                rule: rule,
                name: name,
                details: details,
                rawStatementLine: rawStatementLine,
                amount: amount,
                accountId: accountId,
                creditCardId: creditCardId
            ) {
                return ReconciliationMatchOutcome(
                    matchedRule: rule,
                    appliedCategoryId: rule.targetCategoryId,
                    appliedCleanName: rule.cleanName.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 },
                    markedRecurring: rule.markRecurring ?? false,
                    markedReimbursable: rule.markReimbursable ?? false,
                    reimbursableDebtor: rule.reimbursableDebtor,
                    markedIgnoreInConsolidated: rule.markIgnoreInConsolidated
                )
            }
        }
        return nil
    }

    public static func applyFirstMatch(
        rules: [ReconciliationRule],
        to transaction: inout FinancialTransaction
    ) -> ReconciliationRule? {
        guard let outcome = firstMatch(
            rules: rules,
            name: transaction.name,
            details: transaction.details,
            rawStatementLine: transaction.rawStatementLine,
            amount: transaction.amount,
            accountId: transaction.accountId,
            creditCardId: transaction.creditCardId
        ) else {
            return nil
        }

        if let catId = outcome.appliedCategoryId {
            transaction.categoryId = catId
        }
        if let clean = outcome.appliedCleanName {
            transaction.name = clean
        }
        if outcome.markedRecurring {
            transaction.recurrenceMode = .recurring
            if transaction.recurrenceFrequency == nil {
                transaction.recurrenceFrequency = .monthly
            }
        }
        if outcome.markedReimbursable {
            transaction.isReimbursable = true
            if transaction.reimbursableDebtor == nil || transaction.reimbursableDebtor?.isEmpty == true {
                transaction.reimbursableDebtor = outcome.reimbursableDebtor
            }
            if transaction.reimbursableAmount == nil {
                transaction.reimbursableAmount = transaction.amount
            }
        }
        if let ignoreFlag = outcome.markedIgnoreInConsolidated {
            transaction.ignoreInConsolidated = ignoreFlag
        }
        return outcome.matchedRule
    }

    public static func makeSuggestedRule(from transaction: FinancialTransaction, cleanName: String? = nil) -> ReconciliationRule {
        let baseToken = (transaction.rawStatementLine?.isEmpty == false ? transaction.rawStatementLine! : transaction.name)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return ReconciliationRule(
            name: "Regra: \(cleanName ?? transaction.name)",
            priority: 10,
            isEnabled: true,
            matchField: .nameOrDetails,
            matchOperator: .contains,
            matchPattern: baseToken,
            targetCategoryId: transaction.categoryId,
            cleanName: cleanName ?? transaction.name,
            markRecurring: transaction.recurrenceMode == .recurring ? true : nil,
            markReimbursable: transaction.isReimbursable == true ? true : nil,
            reimbursableDebtor: transaction.reimbursableDebtor
        )
    }
}
