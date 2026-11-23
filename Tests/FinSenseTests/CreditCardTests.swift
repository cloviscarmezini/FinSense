import XCTest
@testable import FinSense

@MainActor
final class CreditCardTests: XCTestCase {

    private func makeIsolatedStore() -> (FinancialDataStore, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("CreditCardTests_\(UUID().uuidString)")
        let store = FinancialDataStore(customDirectory: dir, seedStatementOnFirstLaunch: false)
        return (store, dir)
    }

    @discardableResult
    private func addBankAccount(in store: FinancialDataStore, name: String, initialBalance: Double) -> BankAccount {
        store.addAccount(
            name: name,
            bankPresetId: "itau",
            customImagePath: nil,
            iconSymbol: "building.columns.fill",
            colorHex: "#EC7000",
            initialBalance: initialBalance
        )
        return store.accounts.last!
    }

    private func makeDate(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.current
        return cal.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    // MARK: - 1. Alocação por Dia de Fechamento, Virada de Mês e Virada de Ano

    func testClosingDayAllocationAndYearRollover() {
        let (store, _) = makeIsolatedStore()
        let bank = addBankAccount(in: store, name: "Itaú CC", initialBalance: 10_000)
        let card = store.addCreditCard(
            name: "Cartão Principal",
            totalLimit: 8_000,
            closingDay: 25,
            dueDay: 5,
            defaultPaymentAccountId: bank.id
        )

        XCTAssertEqual(card.bestPurchaseDay, 26, "Melhor dia deve ser sugerido como closingDay + 1")

        // Compra antes do fechamento (24/11/2026) -> Fecha em Nov, vence em 05/12/2026 (Fatura Dez/2026)
        let beforeClosing = CreditCardEngine.allocateInvoice(forPurchaseDate: makeDate(2026, 11, 24), card: card)
        XCTAssertEqual(beforeClosing.year, 2026)
        XCTAssertEqual(beforeClosing.month, 12)
        XCTAssertEqual(beforeClosing.yearMonthKey, 202612)

        // Compra NO dia do fechamento (25/11/2026, melhor dia 26 -> fecha 25/12, vence 05/01/2027) -> Fatura Jan/2027 (ou Dez quando >=26)
        let afterBestPurchase = CreditCardEngine.allocateInvoice(forPurchaseDate: makeDate(2026, 11, 26), card: card)
        XCTAssertEqual(afterBestPurchase.year, 2027)
        XCTAssertEqual(afterBestPurchase.month, 1)
        XCTAssertEqual(afterBestPurchase.yearMonthKey, 202701)

        // Virada de ano: compra em 26/12/2026 (após fechamento 25/12) -> Fecha Jan/2027, vence 05/02/2027
        let yearRollover = CreditCardEngine.allocateInvoice(forPurchaseDate: makeDate(2026, 12, 26), card: card)
        XCTAssertEqual(yearRollover.year, 2027)
        XCTAssertEqual(yearRollover.month, 2)
        XCTAssertEqual(yearRollover.yearMonthKey, 202702)

        // Clamping em fevereiro com fechamento dia 31 -> 28/02/2026 fecha em Fev e vence 10/03/2026 (Mar/2026)
        let endMonthCard = CreditCard(name: "Fim Mês", totalLimit: 5_000, closingDay: 31, dueDay: 10)
        XCTAssertEqual(endMonthCard.bestPurchaseDay, 1)
        let febEnd = CreditCardEngine.allocateInvoice(forPurchaseDate: makeDate(2026, 2, 28), card: endMonthCard)
        XCTAssertEqual(febEnd.yearMonthKey, 202603)
    }

    // MARK: - 2. Divisão Exata em Centavos e Distribuição em Faturas Futuras

    func testInstallmentsExactCentDivisionAcrossInvoices() {
        let (store, _) = makeIsolatedStore()
        let bank = addBankAccount(in: store, name: "Conta", initialBalance: 5_000)
        let card = store.addCreditCard(
            name: "Nubank",
            totalLimit: 3_000,
            closingDay: 25,
            dueDay: 5,
            defaultPaymentAccountId: bank.id
        )
        let catId = store.categories.first(where: { $0.type == .expense })!.id

        let split = CreditCardEngine.splitInstallmentsExactCents(totalAmount: 100.00, count: 3)
        XCTAssertEqual(split, [33.34, 33.33, 33.33])
        XCTAssertEqual(CreditCardEngine.exactSum(split), 100.00, accuracy: 0.0001)

        let created = store.createTransaction(
            name: "Compra Parcelada",
            amount: 100.00,
            date: makeDate(2026, 11, 10),
            type: .expense,
            isPaid: false,
            categoryId: catId,
            accountId: card.id,
            recurrenceMode: .installment,
            installmentsOrMonthsCount: 3,
            referenceNow: makeDate(2026, 11, 10),
            creditCardId: card.id
        )

        XCTAssertEqual(created.count, 3)
        XCTAssertEqual(created[0].amount, 33.34, accuracy: 0.001)
        XCTAssertEqual(created[1].amount, 33.33, accuracy: 0.001)
        XCTAssertEqual(created[2].amount, 33.33, accuracy: 0.001)
        XCTAssertEqual(created.map { $0.creditCardInvoiceYearMonthKey }, [202612, 202701, 202702])

        XCTAssertEqual(store.invoiceSummary(for: card.id, year: 2026, month: 12)?.totalAmount ?? -1, 33.34, accuracy: 0.001)
        XCTAssertEqual(store.invoiceSummary(for: card.id, year: 2027, month: 1)?.totalAmount ?? -1, 33.33, accuracy: 0.001)
        XCTAssertEqual(store.invoiceSummary(for: card.id, year: 2027, month: 2)?.totalAmount ?? -1, 33.33, accuracy: 0.001)

        XCTAssertEqual(store.usedLimit(for: card.id), 100.00, accuracy: 0.001)
        XCTAssertEqual(store.availableLimit(for: card.id), 2_900.00, accuracy: 0.001)
    }

    // MARK: - 3. Regra de Ouro: Competência vs. Caixa (Zero Contagem Dupla)

    func testCompetenceVsCashGoldenRuleZeroDoubleCounting() {
        let (store, _) = makeIsolatedStore()
        let bank = addBankAccount(in: store, name: "Itaú", initialBalance: 10_000)
        // Fecha dia 5, Vence dia 15 -> compra 02/11/2026 entra na fatura Nov/2026 com vencimento em 15/11/2026 (MESMO mês!)
        let card = store.addCreditCard(
            name: "Cartão Mesmo Mês",
            totalLimit: 5_000,
            closingDay: 5,
            dueDay: 15,
            defaultPaymentAccountId: bank.id
        )
        let foodCat = store.categories.first(where: { $0.type == .expense })!
        let novDate = makeDate(2026, 11, 2)

        // Teto de orçamento na categoria de R$ 1.000,00
        store.setCategoryProvision(
            categoryId: foodCat.id,
            estimatedAmount: 1_000,
            for: novDate,
            repeatForFutureMonths: false
        )

        store.createTransaction(
            name: "Supermercado Cartão",
            amount: 600,
            date: novDate,
            type: .expense,
            isPaid: false,
            categoryId: foodCat.id,
            accountId: card.id,
            referenceNow: novDate,
            creditCardId: card.id
        )

        // Deve existir a compra no cartão + 1 projeção de pagamento de fatura no banco
        let cardTxs = store.transactions.filter(\.isCreditCardExpense)
        let invoicePayTxs = store.transactions.filter(\.isCreditCardInvoicePayment)
        XCTAssertEqual(cardTxs.count, 1)
        XCTAssertEqual(invoicePayTxs.count, 1)
        XCTAssertEqual(invoicePayTxs.first?.amount ?? -1, 600, accuracy: 0.01)
        XCTAssertEqual(invoicePayTxs.first?.accountId, bank.id)

        // 1) Conta bancária hoje NÃO foi debitada pela compra no cartão (saldo realizado = 10.000)
        XCTAssertEqual(store.currentBalance(forAccount: bank.id), 10_000, accuracy: 0.01)
        XCTAssertEqual(store.availableLimit(for: card.id), 4_400, accuracy: 0.01)

        // 2) Despesa em Competência (gráficos de categoria, despesa mensal, orçamento, KPI) = 600 (JAMAIS 1.200!)
        XCTAssertEqual(store.monthlyExpense(for: novDate), 600, accuracy: 0.01)
        let breakdown = store.categoryBreakdown(for: novDate, type: .expense)
        XCTAssertEqual(breakdown.reduce(0.0) { $0 + $1.total }, 600, accuracy: 0.01)
        XCTAssertEqual(store.realizedFreeBudgetExpense(forCategory: foodCat.id, in: novDate), 600, accuracy: 0.01)

        let kpi = store.buildUnifiedFinancialKPISummary(referenceDate: novDate, isAnnual: false)
        XCTAssertEqual(kpi.recordedExpense, 600, accuracy: 0.01)
        // Orçamento de 1.000 já consumiu 600 -> restam 400 de teto
        XCTAssertEqual(kpi.remainingBudgetsAndQuotas, 400, accuracy: 0.01)

        // 3) Caixa projetado ao final do mês DEBITA o pagamento de fatura (600) + orçamentos restantes (400) = 9.000, sem dupla contagem da compra!
        XCTAssertEqual(kpi.projectedAccountBalance, 9_400, accuracy: 0.01)
        XCTAssertEqual(kpi.balanceIfAllBudgetsConsumed, 9_000, accuracy: 0.01)
    }

    // MARK: - 4. Atualização Dinâmica da Fatura ao Editar ou Excluir Lançamentos

    func testDynamicInvoicePaymentUpdatesOnEditAndDelete() {
        let (store, _) = makeIsolatedStore()
        let bank = addBankAccount(in: store, name: "Nubank Conta", initialBalance: 5_000)
        let card = store.addCreditCard(
            name: "Cartão Teste",
            totalLimit: 4_000,
            closingDay: 20,
            dueDay: 1,
            defaultPaymentAccountId: bank.id
        )
        let catId = store.categories.first(where: { $0.type == .expense })!.id

        let t1 = store.createTransaction(
            name: "Farmácia",
            amount: 200,
            date: makeDate(2026, 11, 5),
            type: .expense,
            isPaid: false,
            categoryId: catId,
            accountId: card.id,
            referenceNow: makeDate(2026, 11, 5),
            creditCardId: card.id
        ).first!

        let t2 = store.createTransaction(
            name: "Restaurante",
            amount: 150,
            date: makeDate(2026, 11, 10),
            type: .expense,
            isPaid: false,
            categoryId: catId,
            accountId: card.id,
            referenceNow: makeDate(2026, 11, 10),
            creditCardId: card.id
        ).first!

        func decInvoicePayment() -> FinancialTransaction? {
            store.transactions.first { $0.isCreditCardInvoicePayment && $0.creditCardInvoiceYearMonthKey == 202612 }
        }
        func janInvoicePayment() -> FinancialTransaction? {
            store.transactions.first { $0.isCreditCardInvoicePayment && $0.creditCardInvoiceYearMonthKey == 202701 }
        }

        XCTAssertEqual(decInvoicePayment()?.amount ?? -1, 350, accuracy: 0.01)

        // Edita t1 de R$ 200 para R$ 275 -> Fatura Dez sobe para R$ 425
        var editedT1 = t1
        editedT1.amount = 275
        store.updateTransaction(editedT1, scope: .onlyThis)
        XCTAssertEqual(decInvoicePayment()?.amount ?? -1, 425, accuracy: 0.01)

        // Move t2 para após fechamento (25/11) -> sai de Dez (275) e gera fatura Jan/2027 (150)
        var movedT2 = t2
        movedT2.date = makeDate(2026, 11, 25)
        store.updateTransaction(movedT2, scope: .onlyThis)
        XCTAssertEqual(decInvoicePayment()?.amount ?? -1, 275, accuracy: 0.01)
        XCTAssertEqual(janInvoicePayment()?.amount ?? -1, 150, accuracy: 0.01)

        // Exclui t1 -> fatura Dez chega a R$ 0 e a projeção é removida automaticamente
        store.deleteTransaction(t1.id, scope: .onlyThis)
        XCTAssertNil(decInvoicePayment())
        XCTAssertEqual(store.usedLimit(for: card.id), 150, accuracy: 0.01)
    }

    // MARK: - 5. Ciclo de Vida da Fatura, "Pagar Fatura" e Restauração de Limite

    func testInvoiceLifecycleAndPaymentRestoresLimit() {
        let (store, _) = makeIsolatedStore()
        let bankPrimary = addBankAccount(in: store, name: "Conta 1", initialBalance: 3_000)
        let bankSecondary = addBankAccount(in: store, name: "Conta 2", initialBalance: 5_000)
        let card = store.addCreditCard(
            name: "Santander",
            totalLimit: 2_000,
            closingDay: 15,
            dueDay: 25,
            defaultPaymentAccountId: bankPrimary.id
        )
        let catId = store.categories.first(where: { $0.type == .expense })!.id

        store.createTransaction(
            name: "Notebook Acessório",
            amount: 800,
            date: makeDate(2026, 10, 10),
            type: .expense,
            isPaid: false,
            categoryId: catId,
            accountId: card.id,
            referenceNow: makeDate(2026, 10, 10),
            creditCardId: card.id
        )

        // Status antes de 15/10 = Aberta; após 15/10 = Fechada
        let statusOpen = CreditCardEngine.invoiceStatus(isPaid: false, invoiceYear: 2026, invoiceMonth: 10, card: card, referenceNow: makeDate(2026, 10, 12))
        let statusClosed = CreditCardEngine.invoiceStatus(isPaid: false, invoiceYear: 2026, invoiceMonth: 10, card: card, referenceNow: makeDate(2026, 10, 18))
        XCTAssertEqual(statusOpen, CreditCardInvoiceStatus.open)
        XCTAssertEqual(statusClosed, CreditCardInvoiceStatus.closed)
        XCTAssertEqual(store.availableLimit(for: card.id), 1_200, accuracy: 0.01)

        // Pagar Fatura utilizando bankSecondary
        let paidOk = store.payCreditCardInvoice(
            cardId: card.id,
            year: 2026,
            month: 10,
            fromAccountId: bankSecondary.id,
            amount: 800,
            paymentDate: makeDate(2026, 10, 22)
        )
        XCTAssertTrue(paidOk)

        let summaryAfterPay = store.invoiceSummary(for: card.id, year: 2026, month: 10)
        XCTAssertEqual(summaryAfterPay?.status, CreditCardInvoiceStatus.paid)
        XCTAssertEqual(store.currentBalance(forAccount: bankPrimary.id), 3_000, accuracy: 0.01)
        XCTAssertEqual(store.currentBalance(forAccount: bankSecondary.id), 4_200, accuracy: 0.01)
        // Limite restaurado ao pagar a fatura
        XCTAssertEqual(store.usedLimit(for: card.id), 0, accuracy: 0.01)
        XCTAssertEqual(store.availableLimit(for: card.id), 2_000, accuracy: 0.01)

        // Ao excluir a transação de pagamento de fatura, volta a ficar não-paga
        if let payTxId = summaryAfterPay?.paymentTransactionId {
            store.deleteTransaction(payTxId, scope: .onlyThis)
            XCTAssertNotEqual(store.invoiceSummary(for: card.id, year: 2026, month: 10)?.status, CreditCardInvoiceStatus.paid)
            XCTAssertEqual(store.currentBalance(forAccount: bankSecondary.id), 5_000, accuracy: 0.01)
        }
    }

    // MARK: - 6. Persistência, Exportação/Importação e Reset Seletivo

    func testPersistenceExportImportAndReset() throws {
        let (store, dir) = makeIsolatedStore()
        let bank = addBankAccount(in: store, name: "BB", initialBalance: 2_000)
        let card = store.addCreditCard(
            name: "Ourocard",
            totalLimit: 6_000,
            closingDay: 18,
            dueDay: 28,
            defaultPaymentAccountId: bank.id
        )
        let catId = store.categories.first(where: { $0.type == .expense })!.id

        store.createTransaction(
            name: "Passagem",
            amount: 1_200,
            date: makeDate(2026, 11, 5),
            type: .expense,
            isPaid: false,
            categoryId: catId,
            accountId: card.id,
            referenceNow: makeDate(2026, 11, 5),
            creditCardId: card.id
        )

        // Recarrega do disco
        let reloaded = FinancialDataStore(customDirectory: dir, seedStatementOnFirstLaunch: false)
        XCTAssertEqual(reloaded.creditCards.count, 1)
        XCTAssertEqual(reloaded.creditCards.first?.name, "Ourocard")
        XCTAssertEqual(reloaded.usedLimit(for: card.id), 1_200, accuracy: 0.01)

        // Exporta e reimporta para uma segunda store vazia
        let archive = try XCTUnwrap(reloaded.exportFullDatabaseArchive(compress: true))

        let (destStore, _) = makeIsolatedStore()
        destStore.resetSelectedData(Set(ResetDataTarget.allCases))
        let package = try destStore.prepareDatabaseImportPackage(from: archive)
        XCTAssertEqual(package.totalCount(for: .creditCards), 1)
        let importRes = destStore.executeSelectiveDatabaseImportSync(
            package: package,
            selectedTargets: Set(ExportDataTarget.allCases)
        )
        XCTAssertEqual(importRes.importedCreditCards, 1)
        XCTAssertEqual(destStore.creditCards.count, 1)
        XCTAssertEqual(destStore.usedLimit(for: card.id), 1_200, accuracy: 0.01)

        // Granular JSON export contendo apenas Cartões & Faturas + Transações em uma store limpa
        let granularData = try XCTUnwrap(reloaded.exportGranularDatabaseJSON(targets: [.creditCards, .transactions]))
        let (granularStore, _) = makeIsolatedStore()
        granularStore.resetSelectedData(Set(ResetDataTarget.allCases))
        let granularPkg = try granularStore.prepareDatabaseImportPackage(from: granularData)
        XCTAssertEqual(granularPkg.totalCount(for: .accounts), 0)
        XCTAssertEqual(granularPkg.totalCount(for: .creditCards), 1)
        _ = granularStore.executeSelectiveDatabaseImportSync(
            package: granularPkg,
            selectedTargets: [.creditCards, .transactions]
        )
        XCTAssertEqual(granularStore.creditCards.count, 1)
        XCTAssertEqual(granularStore.usedLimit(for: card.id), 1_200, accuracy: 0.01)

        // JSON review drafts preserva creditCardId
        let drafts = try granularStore.parseImportableExpensesFromJSON(data: granularData)
        XCTAssertTrue(drafts.contains { $0.creditCardId == card.id })

        // Reset exclusivo de cartões limpa cartões e faturas mantendo contas bancárias intactas
        destStore.resetSelectedData([.creditCards])
        XCTAssertFalse(destStore.accounts.isEmpty)
        XCTAssertTrue(destStore.creditCards.isEmpty)
        XCTAssertTrue(destStore.creditCardInvoices.isEmpty)

        destStore.resetSelectedData([.accounts])
        XCTAssertTrue(destStore.accounts.isEmpty)
    }
}
