import SwiftUI

public struct AIChatSheetView: View {
    @ObservedObject public var store: FinancialDataStore
    @ObservedObject public var llmService: LocalLLMService
    @Environment(\.dismiss) private var dismiss

    @State private var inputPrompt: String = ""
    @State private var showClearHistoryConfirmation: Bool = false

    private let suggestedPrompts: [String] = [
        "Analise os dados de 01/01/2026 até 01/12/2026, faça uma projeção de quando entrarei em débito no futuro",
        "Usando como referência o meu modo de gastar e receitas, em quanto tempo devo pagar a dívida Cartão Mercado Pago?",
        "Qual é o panorama completo das minhas dívidas, empréstimos, investimentos e maiores despesas?"
    ]

    public init(store: FinancialDataStore, llmService: LocalLLMService) {
        self.store = store
        self.llmService = llmService
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Top bar
            HStack {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color(hex: "#6366F1"), Color(hex: "#8B5CF6")],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 38, height: 38)
                        Image(systemName: "sparkles.bubble.fill")
                            .foregroundStyle(.white)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Assistente Financeiro com LLM Local")
                            .font(.title3.bold())
                        Text("100% focado em finanças • Acesso em tempo real a todas as suas contas, transações, dívidas e contratos")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if let model = store.llmConfig.selectedModel {
                    Label(model.displayName, systemImage: "cpu.fill")
                        .font(.caption.bold())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.green.opacity(0.15)))
                        .foregroundStyle(.green)
                }

                Button("Limpar Histórico") {
                    showClearHistoryConfirmation = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Fechar") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }

            Divider()

            // Quick Prompt Chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(suggestedPrompts, id: \.self) { suggestion in
                        Button {
                            inputPrompt = suggestion
                            sendQuestion()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "sparkles")
                                    .font(.caption2)
                                Text(suggestion)
                                    .font(.caption)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: "#6366F1").opacity(0.12)))
                            .foregroundStyle(Color(hex: "#6366F1"))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Messages ScrollView
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(store.chatHistory) { msg in
                            chatBubble(msg)
                                .id(msg.id)
                        }

                        if llmService.isProcessingChat {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Analisando base de dados financeira...")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(10)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .onChange(of: store.chatHistory.count) { _, _ in
                    if let lastId = store.chatHistory.last?.id {
                        withAnimation {
                            proxy.scrollTo(lastId, anchor: .bottom)
                        }
                    }
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.08), lineWidth: 1))

            // Input Bar
            HStack(spacing: 10) {
                TextField(
                    "Pergunte ex: 'Analise os dados de 01/01/2026 até 01/12/2026, faça uma projeção de quando entrarei em débito no futuro'...",
                    text: $inputPrompt
                )
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    sendQuestion()
                }

                Button {
                    sendQuestion()
                } label: {
                    Label("Enviar", systemImage: "paperplane.fill")
                        .fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(hex: "#6366F1"))
                .disabled(inputPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || llmService.isProcessingChat)
            }
        }
        .padding(22)
        .frame(width: 820, height: 640)
        .alert("Confirmar Limpeza do Histórico", isPresented: $showClearHistoryConfirmation) {
            Button("Limpar Histórico", role: .destructive) {
                store.chatHistory = [
                    ChatMessage(
                        role: .assistant,
                        content: "Histórico limpo. Faça uma pergunta sobre suas finanças, projeções de débito ou quitação de dívidas!"
                    )
                ]
                store.save()
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Deseja realmente remover todas as mensagens do histórico de conversas com a IA local?")
        }
    }

    private func sendQuestion() {
        let q = inputPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        inputPrompt = ""
        Task {
            await llmService.sendUserQuestion(q, store: store)
        }
    }

    @ViewBuilder
    private func chatBubble(_ msg: ChatMessage) -> some View {
        HStack(alignment: .top) {
            if msg.role == .user {
                Spacer(minLength: 80)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(msg.content)
                        .font(.body)
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color(hex: "#6366F1"))
                        )
                        .foregroundStyle(.white)
                    Text(BRLFormatters.shortDate(msg.timestamp))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "cpu.fill")
                            .font(.caption)
                            .foregroundStyle(Color(hex: "#6366F1"))
                        Text(msg.modelUsed ?? "Assistente Financeiro Local")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                    }
                    Text(LocalizedStringKey(msg.content))
                        .font(.system(size: 13.5))
                        .textSelection(.enabled)
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.primary.opacity(0.05))
                        )
                }
                Spacer(minLength: 40)
            }
        }
    }
}
