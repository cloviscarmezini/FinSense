import Foundation

// MARK: - Evolução FinSense (Apple Pay Review, Regras de Conciliação, Patrimônio & Renda, FIRE, Reembolsos, Multimoeda)

public struct ReimbursableDebtorGroup: Identifiable, Hashable {
    public var id: String { debtorKey }
    public let debtorKey: String
    public let debtorDisplayName: String
    public let transactions: [FinancialTransaction]
    public let totalReceivableBRL: Double
    public let remainingReceivableBRL: Double
    public let receivedBRL: Double
}

extension FinancialDataStore {

    // MARK: - Feature 1 & 3: Revisão de Transações (Apple Pay) e Regras Determinísticas

    public var pendingReviewTransactions: [FinancialTransaction] {
        transactions
            .filter { $0.needsReview == true }
            .sorted { $0.date > $1.date }
    }

    public var pendingReviewCount: Int {
        transactions.reduce(0) { $0 + ($1.needsReview == true ? 1 : 0) }
    }

    /// Aplica a primeira regra determinística ativa (por prioridade) sobre uma transação.
    /// Retorna `true` se alguma regra casou e atualizou campos da transação.
    @discardableResult
    public func applyReconciliationRulesIfNeeded(to transaction: inout FinancialTransaction) -> Bool {
        guard let matched = ReconciliationRulesEngine.applyFirstMatch(rules: reconciliationRules, to: &transaction) else {
            return false
        }
        if !transaction.details.contains("[Regra:") {
            let prefix = "[Regra: \(matched.name)]"
            transaction.details = transaction.details.isEmpty ? prefix : "\(prefix) \(transaction.details)"
        }
        return true
    }

    public func approveTransactionReview(_ transactionId: UUID) {
        guard let idx = transactions.firstIndex(where: { $0.id == transactionId }) else { return }
        transactions[idx].needsReview = false
        let updated = transactions[idx]
        save()
        cloudSyncService?.recordLocalMutation(entityName: "financial_transactions", entityId: updated.id, operation: .update, entity: updated)
    }

    public func addReconciliationRule(_ rule: ReconciliationRule) {
        var item = rule
        item.updatedAt = Date()
        reconciliationRules.append(item)
        reconciliationRules.sort {
            $0.priority == $1.priority ? $0.createdAt < $1.createdAt : $0.priority < $1.priority
        }
        save()
        cloudSyncService?.recordLocalMutation(entityName: "reconciliation_rules", entityId: item.id, operation: .insert, entity: item)
    }

    public func updateReconciliationRule(_ rule: ReconciliationRule) {
        var item = rule
        item.updatedAt = Date()
        let op: SyncOperation
        if let idx = reconciliationRules.firstIndex(where: { $0.id == item.id }) {
            reconciliationRules[idx] = item
            op = .update
        } else {
            reconciliationRules.append(item)
            op = .insert
        }
        reconciliationRules.sort {
            $0.priority == $1.priority ? $0.createdAt < $1.createdAt : $0.priority < $1.priority
        }
        save()
        cloudSyncService?.recordLocalMutation(entityName: "reconciliation_rules", entityId: item.id, operation: op, entity: item)
    }

    public func deleteReconciliationRule(_ id: UUID) {
        reconciliationRules.removeAll { $0.id == id }
        save()
        cloudSyncService?.recordLocalMutation(entityName: "reconciliation_rules", entityId: id, operation: .delete)
    }

    @discardableResult
    public func createReconciliationRule(
        from transaction: FinancialTransaction,
        pattern: String? = nil,
        cleanName: String? = nil
    ) -> ReconciliationRule {
        var rule = ReconciliationRulesEngine.makeSuggestedRule(from: transaction, cleanName: cleanName)
        if let customPattern = pattern?.trimmingCharacters(in: .whitespacesAndNewlines), !customPattern.isEmpty {
            rule.matchPattern = customPattern
        }
        let nextPriority = (reconciliationRules.map(\.priority).max() ?? 0) + 10
        rule.priority = nextPriority
        addReconciliationRule(rule)
        return rule
    }

    // MARK: - Feature 4: Patrimônio (Assets), Fontes de Renda & Net Worth

    public func addAssetItem(_ asset: AssetItem) {
        var item = asset
        if item.valuationHistory.isEmpty && item.currentMarketValue > 0 {
            item.valuationHistory = [AssetValuationEntry(date: Date(), marketValue: item.currentMarketValue, notes: "Avaliação inicial")]
        }
        item.updatedAt = Date()
        assets.append(item)
        save()
        cloudSyncService?.recordLocalMutation(entityName: "asset_items", entityId: item.id, operation: .insert, entity: item)
    }

    public func updateAssetItem(_ asset: AssetItem, recordValuationNote: String? = nil) {
        var item = asset
        item.updatedAt = Date()
        let op: SyncOperation
        if let idx = assets.firstIndex(where: { $0.id == item.id }) {
            let oldVal = assets[idx].currentMarketValue
            if abs(oldVal - item.currentMarketValue) > 0.01 {
                item.valuationHistory.append(
                    AssetValuationEntry(
                        date: Date(),
                        marketValue: item.currentMarketValue,
                        notes: recordValuationNote ?? "Reavaliação"
                    )
                )
            }
            assets[idx] = item
            op = .update
        } else {
            assets.append(item)
            op = .insert
        }
        save()
        cloudSyncService?.recordLocalMutation(entityName: "asset_items", entityId: item.id, operation: op, entity: item)
    }

    public func deleteAssetItem(_ id: UUID) {
        assets.removeAll { $0.id == id }
        save()
        cloudSyncService?.recordLocalMutation(entityName: "asset_items", entityId: id, operation: .delete)
    }

    public func addIncomeSource(_ source: IncomeSource) {
        var item = source
        item.updatedAt = Date()
        incomeSources.append(item)
        save()
        cloudSyncService?.recordLocalMutation(entityName: "income_sources", entityId: item.id, operation: .insert, entity: item)
    }

    public func updateIncomeSource(_ source: IncomeSource) {
        var item = source
        item.updatedAt = Date()
        let op: SyncOperation
        if let idx = incomeSources.firstIndex(where: { $0.id == item.id }) {
            incomeSources[idx] = item
            op = .update
        } else {
            incomeSources.append(item)
            op = .insert
        }
        save()
        cloudSyncService?.recordLocalMutation(entityName: "income_sources", entityId: item.id, operation: op, entity: item)
    }

    public func deleteIncomeSource(_ id: UUID) {
        incomeSources.removeAll { $0.id == id }
        save()
        cloudSyncService?.recordLocalMutation(entityName: "income_sources", entityId: id, operation: .delete)
    }

    @discardableResult
    public func captureNetWorthSnapshot(for referenceDate: Date? = nil) -> NetWorthSnapshot {
        let snap = NetWorthEngine.buildCurrentMonthSnapshot(store: self, referenceDate: referenceDate)
        let op: SyncOperation
        let finalSnap: NetWorthSnapshot
        if let idx = netWorthSnapshots.firstIndex(where: { $0.yearMonthKey == snap.yearMonthKey }) {
            var existing = snap
            existing.id = netWorthSnapshots[idx].id
            existing.createdAt = netWorthSnapshots[idx].createdAt
            netWorthSnapshots[idx] = existing
            finalSnap = existing
            op = .update
        } else {
            netWorthSnapshots.append(snap)
            netWorthSnapshots.sort { $0.yearMonthKey < $1.yearMonthKey }
            finalSnap = snap
            op = .insert
        }
        save()
        cloudSyncService?.recordLocalMutation(entityName: "net_worth_snapshots", entityId: finalSnap.id, operation: op, entity: finalSnap)
        return finalSnap
    }

    public func netWorthOverview(fxRateProvider: ((String) -> Double)? = nil) -> NetWorthOverviewSummary {
        NetWorthEngine.calculateOverview(store: self, fxRateProvider: fxRateProvider)
    }

    // MARK: - Feature 5: Cenários FIRE

    public func saveFIREScenario(_ scenario: FIREPlanScenario) {
        var item = scenario
        item.updatedAt = Date()
        let op: SyncOperation
        if let idx = fireScenarios.firstIndex(where: { $0.id == item.id }) {
            fireScenarios[idx] = item
            op = .update
        } else {
            fireScenarios.append(item)
            op = .insert
        }
        save()
        cloudSyncService?.recordLocalMutation(entityName: "fire_scenarios", entityId: item.id, operation: op, entity: item)
    }

    public func deleteFIREScenario(_ id: UUID) {
        fireScenarios.removeAll { $0.id == id }
        save()
        cloudSyncService?.recordLocalMutation(entityName: "fire_scenarios", entityId: id, operation: .delete)
    }

    // MARK: - Feature 6: Gestão de Reembolsos e "A Receber"

    public var openReimbursableTransactions: [FinancialTransaction] {
        transactions
            .filter { $0.type == .expense && $0.isReimbursable == true && $0.isReimbursementSettled != true }
            .sorted { $0.date > $1.date }
    }

    public var allReimbursableTransactions: [FinancialTransaction] {
        transactions
            .filter { $0.type == .expense && $0.isReimbursable == true }
            .sorted { $0.date > $1.date }
    }

    public var totalPendingReceivablesBRL: Double {
        openReimbursableTransactions.reduce(0.0) { partial, tx in
            partial + (tx.remainingReimbursableAmount * effectiveExchangeRateToBRL(for: tx))
        }
    }

    public func reimbursableGroupsByDebtor(includeSettled: Bool = false) -> [ReimbursableDebtorGroup] {
        let source = includeSettled ? allReimbursableTransactions : openReimbursableTransactions
        var grouped: [String: (display: String, txs: [FinancialTransaction], totalBRL: Double, remBRL: Double, recBRL: Double)] = [:]
        for tx in source {
            let rawDebtor = (tx.reimbursableDebtor ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let display = rawDebtor.isEmpty ? "Terceiro não informado" : rawDebtor
            let key = display.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR")).lowercased()
            let rate = effectiveExchangeRateToBRL(for: tx)
            let tot = tx.effectiveReimbursableAmount * rate
            let rem = tx.remainingReimbursableAmount * rate
            let rec = (tx.reimbursementReceivedAmount ?? 0.0) * rate

            if var existing = grouped[key] {
                existing.txs.append(tx)
                existing.totalBRL += tot
                existing.remBRL += rem
                existing.recBRL += rec
                grouped[key] = existing
            } else {
                grouped[key] = (display, [tx], tot, rem, rec)
            }
        }
        return grouped.map { key, val in
            ReimbursableDebtorGroup(
                debtorKey: key,
                debtorDisplayName: val.display,
                transactions: val.txs.sorted { $0.date > $1.date },
                totalReceivableBRL: val.totalBRL,
                remainingReceivableBRL: val.remBRL,
                receivedBRL: val.recBRL
            )
        }
        .sorted { $0.remainingReceivableBRL > $1.remainingReceivableBRL }
    }

    /// Registra recebimento total ou parcial de um reembolso (inclusive valores maiores que o previsto):
    /// credita a conta escolhida sem inflar categoria de receita em gráficos (`transactionOrigin == .reimbursementReceipt`).
    /// Quando `finalizeReimbursement == true`, encerra a pendência ajustando `reimbursableAmount` para que eventual
    /// diferença não recebida permaneça contabilizada como gasto próprio do usuário nos orçamentos/gráficos.
    @discardableResult
    public func registerReimbursementSettlement(
        forTransactionId txId: UUID,
        receivedAmount: Double,
        accountId: UUID,
        date: Date = Date(),
        notes: String = "",
        finalizeReimbursement: Bool = false
    ) -> FinancialTransaction? {
        guard let idx = transactions.firstIndex(where: { $0.id == txId }),
              receivedAmount >= 0,
              (receivedAmount > 0.001 || finalizeReimbursement),
              let acc = account(for: accountId) else {
            return nil
        }

        let original = transactions[idx]
        let expectedTotal = original.effectiveReimbursableAmount
        let alreadyReceived = original.reimbursementReceivedAmount ?? 0.0
        let cleanReceived = abs(receivedAmount)
        let newTotalReceived = alreadyReceived + cleanReceived
        let shouldSettle = finalizeReimbursement || (newTotalReceived + 0.01 >= expectedTotal)

        transactions[idx].reimbursementReceivedAmount = newTotalReceived
        transactions[idx].isReimbursementSettled = shouldSettle
        if shouldSettle {
            transactions[idx].reimbursableAmount = min(original.amount, newTotalReceived)
        }
        let updatedOrig = transactions[idx]

        var createdReceipt: FinancialTransaction? = nil
        if cleanReceived > 0.001 {
            let catId = fallbackCategoryId(for: .income, matchingSubstring: "Reembolso")
            let debtorLabel = (original.reimbursableDebtor?.isEmpty == false ? original.reimbursableDebtor! : "Terceiro")
            let receiptRate = acc.currencyCode.uppercased() == "BRL" ? 1.0 : ExchangeRateService.shared.rateToBRL(for: acc.currencyCode)
            let receiptTx = FinancialTransaction(
                name: "Reembolso: \(original.name)",
                details: notes.isEmpty ? "Acerto de \(debtorLabel) ref. lançamento de \(BRLFormatters.shortDate(original.date))" : notes,
                amount: cleanReceived,
                date: date,
                type: .income,
                isPaid: true,
                categoryId: catId,
                accountId: acc.id,
                ignoreInConsolidated: false,
                transactionOrigin: .reimbursementReceipt,
                linkedEntityID: original.id,
                currencyCode: acc.currencyCode,
                exchangeRateToBRL: acc.currencyCode.uppercased() == "BRL" ? nil : receiptRate
            )
            transactions.append(receiptTx)
            createdReceipt = receiptTx
        }

        sortTransactions()
        save()
        cloudSyncService?.recordLocalMutation(entityName: "financial_transactions", entityId: updatedOrig.id, operation: .update, entity: updatedOrig)
        if let receiptTx = createdReceipt {
            cloudSyncService?.recordLocalMutation(entityName: "financial_transactions", entityId: receiptTx.id, operation: .insert, entity: receiptTx)
        }
        return createdReceipt ?? updatedOrig
    }

    // MARK: - Feature: Seleção de Fatura para Despesa no Cartão

    public func defaultCreditCardInvoiceKey(forPurchaseDate purchaseDate: Date, card: CreditCard) -> Int {
        let baseAlloc = CreditCardEngine.allocateInvoice(forPurchaseDate: purchaseDate, card: card, calendar: calendar)
        var candidate = (year: baseAlloc.year, month: baseAlloc.month, yearMonthKey: baseAlloc.yearMonthKey)
        for offset in 0..<12 {
            let ym = CreditCardEngine.addMonths(offset, toYear: baseAlloc.year, month: baseAlloc.month)
            let existingPaid = creditCardInvoices.first(where: {
                $0.creditCardId == card.id && $0.yearMonthKey == ym.yearMonthKey
            })?.isPaid ?? false
            if !existingPaid {
                candidate = ym
                break
            }
        }
        return candidate.yearMonthKey
    }

    public func selectableCreditCardInvoices(
        for card: CreditCard,
        purchaseDate: Date,
        additionalKey: Int? = nil
    ) -> [(yearMonthKey: Int, label: String, cycle: CreditCardEngine.AllocatedInvoiceCycle)] {
        let baseAlloc = CreditCardEngine.allocateInvoice(forPurchaseDate: purchaseDate, card: card, calendar: calendar)
        var keys = Set<Int>()
        for offset in -3...18 {
            keys.insert(CreditCardEngine.addMonths(offset, toYear: baseAlloc.year, month: baseAlloc.month).yearMonthKey)
        }
        for inv in creditCardInvoices where inv.creditCardId == card.id {
            keys.insert(inv.yearMonthKey)
        }
        if let additionalKey {
            keys.insert(additionalKey)
        }

        return keys.sorted().map { ymKey in
            let c = CreditCardEngine.yearMonthComponents(fromKey: ymKey)
            let dates = CreditCardEngine.closingAndDueDates(forInvoiceYear: c.year, month: c.month, card: card, calendar: calendar)
            let cycle = CreditCardEngine.AllocatedInvoiceCycle(
                year: c.year,
                month: c.month,
                yearMonthKey: ymKey,
                closingDate: dates.closingDate,
                dueDate: dates.dueDate
            )
            let invSummary = invoiceSummary(for: card.id, year: c.year, month: c.month)
            let statusTag = invSummary?.status.rawValue ?? "Aberta"
            let fullLabel = "\(CreditCardEngine.fullInvoiceLabel(year: c.year, month: c.month)) • Venc. \(BRLFormatters.shortDate(dates.dueDate)) (\(statusTag))"
            return (yearMonthKey: ymKey, label: fullLabel, cycle: cycle)
        }
    }

    // MARK: - Feature 2 & 7: Criação com Reembolso, Multimoeda e Revisão (Quick-Add / Editor)

    @discardableResult
    public func createExtendedTransaction(
        name: String,
        details: String = "",
        amount: Double,
        date: Date,
        type: TransactionType,
        isPaid: Bool = true,
        categoryId: UUID,
        accountId: UUID,
        attachmentPath: String? = nil,
        attachmentName: String? = nil,
        ignoreInConsolidated: Bool = false,
        recurrenceMode: TransactionRecurrenceMode = .single,
        installmentsOrMonthsCount: Int = 1,
        recurrenceFrequency: RecurrenceFrequency = .monthly,
        creditCardId: UUID? = nil,
        creditCardInvoiceYearMonthKey: Int? = nil,
        currencyCode: String? = nil,
        exchangeRateToBRL: Double? = nil,
        isReimbursable: Bool = false,
        reimbursableAmount: Double? = nil,
        reimbursableDebtor: String? = nil,
        reimbursementExpectedDate: Date? = nil,
        needsReview: Bool? = nil,
        sourceApp: String? = nil
    ) -> [FinancialTransaction] {
        let created = createTransaction(
            name: name,
            details: details,
            amount: amount,
            date: date,
            type: type,
            isPaid: isPaid,
            categoryId: categoryId,
            accountId: accountId,
            attachmentPath: attachmentPath,
            attachmentName: attachmentName,
            ignoreInConsolidated: ignoreInConsolidated,
            recurrenceMode: recurrenceMode,
            installmentsOrMonthsCount: installmentsOrMonthsCount,
            recurrenceFrequency: recurrenceFrequency,
            referenceNow: effectiveCurrentDate,
            creditCardId: creditCardId,
            creditCardInvoiceYearMonthKey: creditCardInvoiceYearMonthKey
        )

        let resolvedCurrency = (currencyCode?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? currencyCode!.uppercased()
            : (account(for: accountId)?.currencyCode ?? "BRL")
        let lockedRate: Double? = {
            if resolvedCurrency == "BRL" { return nil }
            if let r = exchangeRateToBRL, r > 0 { return r }
            return ExchangeRateService.shared.rateToBRL(for: resolvedCurrency)
        }()

        let totalAmount = max(0.01, abs(amount))
        let ratio = isReimbursable
            ? min(1.0, max(0.0, (reimbursableAmount ?? totalAmount) / totalAmount))
            : 0.0

        var mutatedIds: Set<UUID> = []
        for createdTx in created {
            if let idx = transactions.firstIndex(where: { $0.id == createdTx.id }) {
                transactions[idx].currencyCode = resolvedCurrency
                transactions[idx].exchangeRateToBRL = lockedRate
                if isReimbursable && type == .expense {
                    transactions[idx].isReimbursable = true
                    transactions[idx].reimbursableAmount = (transactions[idx].amount * ratio * 100.0).rounded() / 100.0
                    transactions[idx].reimbursableDebtor = reimbursableDebtor?.trimmingCharacters(in: .whitespacesAndNewlines)
                    transactions[idx].reimbursementExpectedDate = reimbursementExpectedDate
                    transactions[idx].reimbursementReceivedAmount = 0.0
                    transactions[idx].isReimbursementSettled = false
                }
                if let needsReview {
                    transactions[idx].needsReview = needsReview
                }
                if let sourceApp {
                    transactions[idx].sourceApp = sourceApp
                }
                mutatedIds.insert(transactions[idx].id)
            }
        }

        if !mutatedIds.isEmpty {
            save()
            for id in mutatedIds {
                if let updated = transactions.first(where: { $0.id == id }) {
                    cloudSyncService?.recordLocalMutation(entityName: "financial_transactions", entityId: updated.id, operation: .update, entity: updated)
                }
            }
        }
        return transactions.filter { mutatedIds.contains($0.id) }
    }
}
