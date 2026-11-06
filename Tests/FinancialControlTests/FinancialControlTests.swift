import XCTest
@testable import FinancialControl

@MainActor
final class FinancialControlTests: XCTestCase {

    private func makeIsolatedStore(seedStatement: Bool = false) -> FinancialDataStore {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("FinancialControlTests_\(UUID().uuidString)")
        return FinancialDataStore(customDirectory: tempDir, seedStatementOnFirstLaunch: seedStatement)
    }

    func testItauStatementParsingAndDeduplication() {
        let store = makeIsolatedStore(seedStatement: false)
        let itauAccount = store.accounts.first!

        // 1. Testa filtro Apenas Despesas
        let expensesOnly = StatementImportService.parseStatementText(
            SampleItauStatementData.rawOCRText,
            categories: store.categories,
            filterMode: .expensesOnly
        )
        XCTAssertFalse(expensesOnly.isEmpty)
        XCTAssertTrue(expensesOnly.allSatisfy { $0.type == .expense })

        // 2. Testa filtro Apenas Receitas
        let incomesOnly = StatementImportService.parseStatementText(
            SampleItauStatementData.rawOCRText,
            categories: store.categories,
            filterMode: .incomesOnly
        )
        XCTAssertFalse(incomesOnly.isEmpty)
        XCTAssertTrue(incomesOnly.allSatisfy { $0.type == .income })

        // 3. Testa modo Híbrido e deduplicação
        let hybrid = StatementImportService.parseStatementText(
            SampleItauStatementData.rawOCRText,
            categories: store.categories,
            filterMode: .hybrid
        )
        XCTAssertEqual(hybrid.count, expensesOnly.count + incomesOnly.count)

        let firstImport = store.importParsedTransactions(hybrid, intoAccountId: itauAccount.id, filterMode: .hybrid)
        XCTAssertEqual(firstImport.addedCount, hybrid.count)
        XCTAssertEqual(firstImport.skippedDuplicatesCount, 0)

        // Importar novamente o mesmo relatório não deve duplicar nenhuma transação
        let secondImport = store.importParsedTransactions(hybrid, intoAccountId: itauAccount.id, filterMode: .hybrid)
        XCTAssertEqual(secondImport.addedCount, 0)
        XCTAssertEqual(secondImport.skippedDuplicatesCount, hybrid.count)
    }

    func testInstallmentRepeatedAndIgnoreInConsolidatedTransactions() {
        let store = makeIsolatedStore(seedStatement: false)
        let acc = store.accounts.first!
        let expCat = store.categories(for: .expense).first!

        let initialAccountBal = store.currentBalance(forAccount: acc.id)

        // 1. Transação ignorada no consolidado não altera o saldo
        store.createTransaction(
            name: "Registro Informativo",
            amount: 500.0,
            date: Date(),
            type: .expense,
            isPaid: true,
            categoryId: expCat.id,
            accountId: acc.id,
            ignoreInConsolidated: true
        )
        XCTAssertEqual(store.currentBalance(forAccount: acc.id), initialAccountBal, accuracy: 0.01)

        // 2. Despesa parcelada (valor cheio de R$ 1.200 em 4x = 4 parcelas de R$ 300)
        let installments = store.createTransaction(
            name: "Notebook",
            amount: 1200.0,
            date: Date(),
            type: .expense,
            isPaid: true,
            categoryId: expCat.id,
            accountId: acc.id,
            ignoreInConsolidated: false,
            recurrenceMode: .installment,
            installmentsOrMonthsCount: 4
        )
        XCTAssertEqual(installments.count, 4)
        let sumInstallments = installments.reduce(0.0) { $0 + $1.amount }
        XCTAssertEqual(sumInstallments, 1200.0, accuracy: 0.01)

        // 3. Despesa repetida (mesmo valor de R$ 150 repetido em 3 meses)
        let repeated = store.createTransaction(
            name: "Academia",
            amount: 150.0,
            date: Date(),
            type: .expense,
            isPaid: true,
            categoryId: expCat.id,
            accountId: acc.id,
            ignoreInConsolidated: false,
            recurrenceMode: .repeated,
            installmentsOrMonthsCount: 3
        )
        XCTAssertEqual(repeated.count, 3)
        XCTAssertTrue(repeated.allSatisfy { abs($0.amount - 150.0) < 0.01 })
    }

    func testInvestmentsContributionAndConsolidatedToggle() {
        let store = makeIsolatedStore(seedStatement: false)
        let itau = store.accounts[0]
        let santander = store.accounts[1]

        store.addInvestment(
            name: "CDB Especial",
            groupName: "CDB Santander",
            investmentAccountId: santander.id,
            initialBalance: 0.0,
            showInConsolidated: true
        )
        let inv = store.investments.last!
        let beforeAccountBal = store.currentBalance(forAccount: itau.id)

        store.contributeToInvestment(
            investmentId: inv.id,
            amount: 200.0,
            sourceAccountId: itau.id,
            investmentAccountId: santander.id
        )

        // Tirou da conta de origem e adicionou no investimento
        XCTAssertEqual(store.currentBalance(forAccount: itau.id), beforeAccountBal - 200.0, accuracy: 0.01)
        let updatedInv = store.investments.first(where: { $0.id == inv.id })!
        XCTAssertEqual(updatedInv.balance, 200.0, accuracy: 0.01)

        let consolidatedWithInv = store.totalConsolidatedPatrimonyNow
        store.toggleInvestmentConsolidated(inv.id)
        let consolidatedWithoutInv = store.totalConsolidatedPatrimonyNow
        XCTAssertEqual(consolidatedWithInv - consolidatedWithoutInv, 200.0, accuracy: 0.01)
    }

    func testDebtNegotiationPaymentRemovesCardAndCreatesTransaction() {
        let store = makeIsolatedStore(seedStatement: false)
        let acc = store.accounts.first!
        let debt = store.activeDebts.first!
        let originalCount = store.activeDebts.count
        let beforeBal = store.currentBalance(forAccount: acc.id)

        store.payDebt(
            debtId: debt.id,
            fromAccountId: acc.id,
            negotiatedAmount: 1200.0
        )

        XCTAssertEqual(store.activeDebts.count, originalCount - 1)
        XCTAssertEqual(store.currentBalance(forAccount: acc.id), beforeBal - 1200.0, accuracy: 0.01)
    }

    func testLoanWithPastStartDateCreatesOnlyFutureTransactionsAndCalculatesPayoff() {
        let store = makeIsolatedStore(seedStatement: false)
        let acc = store.accounts.first!
        let cal = Calendar.current
        let now = BRLFormatters.shortDateFormatter.date(from: "06/11/2026")!
        let startSixMonthsAgo = cal.date(byAdding: .month, value: -6, to: now)!

        let contract = store.createCreditContract(
            kind: .loan,
            name: "Consignado Teste",
            loanSubtype: .consignado,
            amortizationSystem: .price,
            totalContractedAmount: 12000.0,
            installmentAmount: 600.0,
            billingDay: 15,
            totalInstallments: 24,
            monthlyInterestRate: 1.80,
            startDate: startSixMonthsAgo,
            accountId: acc.id,
            referenceDate: now
        )

        XCTAssertEqual(contract.pastInstallmentsElapsedAtCreation, 6)
        let generatedFutureTxs = store.unpaidTransactions(forContract: contract.id)
        XCTAssertEqual(generatedFutureTxs.count, 18)
        XCTAssertTrue(generatedFutureTxs.allSatisfy { $0.date >= cal.startOfDay(for: now) })

        let nominal = store.remainingNominalAmount(for: contract)
        let projectedPayoff = store.projectedPayoffAmount(for: contract)
        XCTAssertEqual(nominal, 18.0 * 600.0, accuracy: 0.01)
        XCTAssertLessThan(projectedPayoff, nominal)
        XCTAssertGreaterThan(projectedPayoff, 0)
    }

    func testAIChatProjectionsAndInsufficientDataHandling() {
        // Caso 1: Sem transações -> deve informar que não tem dados suficientes
        let emptyStore = makeIsolatedStore(seedStatement: false)
        let noDataReply = LocalLLMService.generateFinancialResponse(
            for: "Usando como referência o meu modo de gastar e receitas, em quanto tempo devo pagar a dívida Cartão Mercado Pago?",
            store: emptyStore,
            modelLabel: "TestModel"
        )
        XCTAssertTrue(noDataReply.localizedCaseInsensitiveContains("Não há dados suficientes"))

        // Caso 2: Com extrato Itaú carregado -> analisa dívida e analisa projeção de período
        let populatedStore = makeIsolatedStore(seedStatement: true)
        let debtReply = LocalLLMService.generateFinancialResponse(
            for: "Usando como referência o meu modo de gastar e receitas, em quanto tempo devo pagar a dívida Cartão Mercado Pago?",
            store: populatedStore,
            modelLabel: "TestModel"
        )
        XCTAssertTrue(debtReply.localizedCaseInsensitiveContains("Cartão Mercado Pago"))

        let projectionReply = LocalLLMService.generateFinancialResponse(
            for: "Analise os dados de 01/01/2026 até 01/12/2026, faça uma projeção de quando entrarei em débito no futuro",
            store: populatedStore,
            modelLabel: "TestModel"
        )
        XCTAssertTrue(projectionReply.localizedCaseInsensitiveContains("01/01/2026"))
        XCTAssertTrue(projectionReply.localizedCaseInsensitiveContains("01/12/2026"))
    }
}
