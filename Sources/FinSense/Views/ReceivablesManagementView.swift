import SwiftUI

/// Tela dedicada à Gestão de Reembolsos e "A Receber" (Feature 6), agrupada por devedor.
public struct ReceivablesManagementView: View {
    @ObservedObject public var store: FinancialDataStore

    @State private var includeSettled: Bool = false
    @State private var settlingTransaction: FinancialTransaction? = nil

    public init(store: FinancialDataStore) {
        self.store = store
    }

    public var body: some View {
        let groups = store.reimbursableGroupsByDebtor(includeSettled: includeSettled)
        let pendingTotal = store.totalPendingReceivablesBRL

        VStack(alignment: .leading, spacing: 18) {
            // Header + Resumo
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Reembolsos & Valores a Receber")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                    Text("Controle gastos reembolsáveis sem distorcer seus orçamentos e dê baixa quando o terceiro pagar.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Toggle("Mostrar quitados", isOn: $includeSettled)
                    .toggleStyle(.switch)

                VStack(alignment: .trailing, spacing: 2) {
                    Text("Total Pendente a Receber")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(BRLFormatters.currency(pendingTotal))
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(pendingTotal > 0 ? Color(hex: "#F59E0B") : Color(hex: "#10B981"))
                        .monospacedDigit()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
            }

            if groups.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "person.2.badge.gearshape.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text(includeSettled ? "Nenhum gasto reembolsável cadastrado" : "Nenhum reembolso em aberto")
                        .font(.headline)
                    Text("Marque qualquer despesa em conta ou cartão como \"Reembolsável / A Receber\" para acompanhá-la por devedor aqui.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .controlBackgroundColor)))
            } else {
                ScrollView {
                    LazyVStack(spacing: 14) {
                        ForEach(groups) { group in
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Label(group.debtorDisplayName, systemImage: "person.crop.circle.fill")
                                        .font(.headline)
                                    Spacer()
                                    if group.receivedBRL > 0.01 {
                                        Text("Já recebido: \(BRLFormatters.currency(group.receivedBRL))")
                                            .font(.caption)
                                            .foregroundStyle(Color(hex: "#10B981"))
                                    }
                                    Text("Falta receber: \(BRLFormatters.currency(group.remainingReceivableBRL))")
                                        .font(.subheadline.bold().monospacedDigit())
                                        .foregroundStyle(group.remainingReceivableBRL > 0.01 ? Color(hex: "#F59E0B") : Color(hex: "#10B981"))
                                }

                                Divider()

                                ForEach(group.transactions) { tx in
                                    let isSettled = tx.isReimbursementSettled == true
                                    HStack(spacing: 12) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            HStack(spacing: 6) {
                                                Text(tx.name)
                                                    .font(.subheadline.weight(.semibold))
                                                if isSettled {
                                                    Text("Quitado")
                                                        .font(.caption2.bold())
                                                        .padding(.horizontal, 6)
                                                        .padding(.vertical, 2)
                                                        .background(Capsule().fill(Color.green.opacity(0.16)))
                                                        .foregroundStyle(.green)
                                                }
                                            }
                                            Text("Compra em \(BRLFormatters.shortDate(tx.date)) • Total gasto: \(BRLFormatters.currency(tx.amount, currencyCode: tx.effectiveCurrencyCode))")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }

                                        Spacer()

                                        VStack(alignment: .trailing, spacing: 2) {
                                            Text("Reembolso: \(BRLFormatters.currency(tx.effectiveReimbursableAmount, currencyCode: tx.effectiveCurrencyCode))")
                                                .font(.caption.weight(.semibold))
                                            if !isSettled {
                                                Text("Restante: \(BRLFormatters.currency(tx.remainingReimbursableAmount, currencyCode: tx.effectiveCurrencyCode))")
                                                    .font(.caption2.bold())
                                                    .foregroundStyle(Color(hex: "#F59E0B"))
                                            }
                                        }

                                        if !isSettled {
                                            Button {
                                                settlingTransaction = tx
                                            } label: {
                                                Label("Registrar Recebimento", systemImage: "checkmark.circle.fill")
                                            }
                                            .buttonStyle(.borderedProminent)
                                            .tint(Color(hex: "#10B981"))
                                            .controlSize(.small)
                                        }
                                    }
                                    .padding(10)
                                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .windowBackgroundColor)))
                                }
                            }
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
                        }
                    }
                }
            }
        }
        .padding(24)
        .sheet(item: $settlingTransaction) { tx in
            ReimbursementSettlementSheet(store: store, transaction: tx)
        }
    }
}

public struct ReimbursementSettlementSheet: View {
    @ObservedObject public var store: FinancialDataStore
    public let transaction: FinancialTransaction
    @Environment(\.dismiss) private var dismiss

    @State private var amountText: String = ""
    @State private var selectedAccountId: UUID = UUID()
    @State private var settlementDate: Date = Date()
    @State private var notes: String = ""

    public init(store: FinancialDataStore, transaction: FinancialTransaction) {
        self.store = store
        self.transaction = transaction
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Registrar Recebimento de Reembolso")
                .font(.title3.bold())
            Text("\"\(transaction.name)\" • Devedor: \(transaction.reimbursableDebtor ?? "Terceiro") • Restante: \(BRLFormatters.currency(transaction.remainingReimbursableAmount, currencyCode: transaction.effectiveCurrencyCode))")
                .font(.caption)
                .foregroundStyle(.secondary)

            Form {
                TextField("Valor Recebido (total ou parcial)", text: $amountText)
                Picker("Conta que Recebeu o Dinheiro", selection: $selectedAccountId) {
                    ForEach(store.accounts) { acc in
                        Text("\(acc.name) (\(acc.currencyCode))").tag(acc.id)
                    }
                }
                DatePicker("Data do Recebimento", selection: $settlementDate, displayedComponents: [.date])
                TextField("Observações (Opcional)", text: $notes)
            }
            .formStyle(.grouped)

            Text("Obs: O valor entra no saldo da conta sem inflar gráficos de Salário/Receita.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Cancelar") { dismiss() }
                Button("Confirmar Recebimento") {
                    let cleanVal = BRLFormatters.parseCurrencyInput(amountText)
                    guard cleanVal > 0 else { return }
                    _ = store.registerReimbursementSettlement(
                        forTransactionId: transaction.id,
                        receivedAmount: cleanVal,
                        accountId: selectedAccountId,
                        date: settlementDate,
                        notes: notes
                    )
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(hex: "#10B981"))
            }
        }
        .padding(20)
        .frame(width: 470, height: 360)
        .onAppear {
            amountText = String(format: "%.2f", transaction.remainingReimbursableAmount)
            selectedAccountId = store.accounts.first?.id ?? UUID()
        }
    }
}
