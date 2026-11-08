// Sources/FinSense/Views/AuthFormSheetView.swift
import SwiftUI

public enum AuthSheetMode {
    case login, register
}

public struct AuthFormSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding public var mode: AuthSheetMode
    public let baseURL: String

    @State private var fullName: String = ""
    @State private var email: String = ""
    @State private var password: String = ""

    @ObservedObject private var authService = AuthService.shared

    public init(mode: Binding<AuthSheetMode>, baseURL: String) {
        self._mode = mode
        self.baseURL = baseURL
    }

    public var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text(mode == .login ? "Entrar na Conta" : "Criar Conta FinSense")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Button("Cancelar") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }

            if let errorMsg = authService.authErrorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(errorMsg)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.red.opacity(0.1)))
            }

            VStack(spacing: 12) {
                if mode == .register {
                    TextField("Nome Completo", text: $fullName)
                        .textFieldStyle(.roundedBorder)
                }

                TextField("E-mail", text: $email)
                    .textFieldStyle(.roundedBorder)

                SecureField("Senha (mínimo 6 caracteres)", text: $password)
                    .textFieldStyle(.roundedBorder)
            }

            Button {
                Task {
                    let success: Bool
                    if mode == .login {
                        success = await authService.login(email: email, password: password, baseURL: baseURL)
                    } else {
                        success = await authService.register(fullName: fullName, email: email, password: password, baseURL: baseURL)
                    }
                    if success {
                        dismiss()
                    }
                }
            } label: {
                if authService.isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Text(mode == .login ? "Entrar" : "Criar Conta")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(authService.isLoading || email.isEmpty || password.isEmpty || (mode == .register && fullName.isEmpty))

            HStack {
                Text(mode == .login ? "Ainda não tem conta?" : "Já possui conta?")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button(mode == .login ? "Criar conta" : "Entrar") {
                    mode = (mode == .login ? .register : .login)
                    authService.authErrorMessage = nil
                }
                .font(.caption)
            }
        }
        .padding(24)
        .frame(width: 380)
    }
}
