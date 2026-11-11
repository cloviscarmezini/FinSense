// Sources/FinSense/Services/AuthService.swift
import Foundation
import Combine
import SwiftUI

@MainActor
public final class AuthService: ObservableObject {
    public static let shared = AuthService()

    @Published public var isAuthenticated: Bool = false
    @Published public var currentUser: UserSummary? = nil
    @Published public var isLoading: Bool = false
    @Published public var authErrorMessage: String? = nil

    private let tokenKey = "auth_access_token"
    private let refreshKey = "auth_refresh_token"
    private let userKey = "auth_current_user_json"
    private let backupTokenKey = "auth_access_token_backup"
    private let backupRefreshKey = "auth_refresh_token_backup"
    private let sessionActiveKey = "auth_session_is_active"

    private var ongoingRenewalTask: Task<Bool, Never>?
    private var autoRenewalCancellable: AnyCancellable?

    public var currentBaseURL: String {
        UserDefaults.standard.string(forKey: "cloud_sync_base_url") ?? "http://localhost:8080/api/v1"
    }

    private init() {
        restoreSession()
    }

    public func restoreSession() {
        let token = KeychainHelper.shared.read(key: tokenKey) ?? UserDefaults.standard.string(forKey: backupTokenKey)
        let refresh = KeychainHelper.shared.read(key: refreshKey) ?? UserDefaults.standard.string(forKey: backupRefreshKey)
        let isMarkedActive = UserDefaults.standard.bool(forKey: sessionActiveKey)

        let hasValidCredentials = (token != nil && !token!.isEmpty) || (refresh != nil && !refresh!.isEmpty) || isMarkedActive

        if hasValidCredentials {
            if let userJson = UserDefaults.standard.string(forKey: userKey),
               let data = userJson.data(using: .utf8),
               let user = try? JSONDecoder().decode(UserSummary.self, from: data) {
                self.currentUser = user
            }
            self.isAuthenticated = true

            let isRunningUnderTests = NSClassFromString("XCTestCase") != nil
            if !isRunningUnderTests {
                startAutoRenewalLoop()
                // Proactively renew tokens in background on app start
                Task { [weak self] in
                    await self?.renewTokens()
                }
            }
        } else {
            self.isAuthenticated = false
            self.currentUser = nil
            autoRenewalCancellable?.cancel()
        }
    }

    public var accessToken: String? {
        KeychainHelper.shared.read(key: tokenKey) ?? UserDefaults.standard.string(forKey: backupTokenKey)
    }

    public var refreshToken: String? {
        KeychainHelper.shared.read(key: refreshKey) ?? UserDefaults.standard.string(forKey: backupRefreshKey)
    }

    public func login(email: String, password: String, baseURL: String) async -> Bool {
        isLoading = true
        authErrorMessage = nil
        defer { isLoading = false }

        // Store preferred baseURL
        UserDefaults.standard.set(baseURL, forKey: "cloud_sync_base_url")

        do {
            let res = try await BackendAPIClient.shared.login(baseURL: baseURL, email: email, password: password)
            saveSession(res)
            return true
        } catch {
            authErrorMessage = error.localizedDescription
            return false
        }
    }

    public func register(fullName: String, email: String, password: String, baseURL: String) async -> Bool {
        isLoading = true
        authErrorMessage = nil
        defer { isLoading = false }

        UserDefaults.standard.set(baseURL, forKey: "cloud_sync_base_url")

        do {
            let res = try await BackendAPIClient.shared.register(baseURL: baseURL, fullName: fullName, email: email, password: password)
            saveSession(res)
            return true
        } catch {
            authErrorMessage = error.localizedDescription
            return false
        }
    }

    public func logout() {
        autoRenewalCancellable?.cancel()
        KeychainHelper.shared.delete(key: tokenKey)
        KeychainHelper.shared.delete(key: refreshKey)
        UserDefaults.standard.removeObject(forKey: tokenKey)
        UserDefaults.standard.removeObject(forKey: refreshKey)
        UserDefaults.standard.removeObject(forKey: backupTokenKey)
        UserDefaults.standard.removeObject(forKey: backupRefreshKey)
        UserDefaults.standard.removeObject(forKey: sessionActiveKey)
        UserDefaults.standard.removeObject(forKey: userKey)
        UserDefaults.standard.removeObject(forKey: "cloud_sync_last_revision")
        self.isAuthenticated = false
        self.currentUser = nil
    }

    public func saveSession(_ res: AuthResponse) {
        KeychainHelper.shared.save(key: tokenKey, value: res.accessToken)
        KeychainHelper.shared.save(key: refreshKey, value: res.refreshToken)
        UserDefaults.standard.set(res.accessToken, forKey: backupTokenKey)
        UserDefaults.standard.set(res.refreshToken, forKey: backupRefreshKey)
        UserDefaults.standard.set(true, forKey: sessionActiveKey)

        if let data = try? JSONEncoder().encode(res.user),
           let str = String(data: data, encoding: .utf8) {
            UserDefaults.standard.set(str, forKey: userKey)
        }
        self.currentUser = res.user
        self.isAuthenticated = true
        startAutoRenewalLoop()
    }

    @discardableResult
    public func renewTokens(baseURL: String? = nil) async -> Bool {
        if let existingTask = ongoingRenewalTask {
            return await existingTask.value
        }

        guard let refresh = refreshToken, !refresh.isEmpty else {
            // Critical unrecoverable condition: no refresh token available
            print("🚨 [AuthService] Sem refresh token disponível para renovação. Encerrando sessão.")
            logout()
            return false
        }

        let targetURL = baseURL ?? currentBaseURL

        let task = Task<Bool, Never> { @MainActor in
            defer { self.ongoingRenewalTask = nil }

            do {
                let res = try await BackendAPIClient.shared.refreshTokens(baseURL: targetURL, refreshToken: refresh)
                self.saveSession(res)
                return true
            } catch let apiError as NSError where apiError.domain == "FinSenseAPI" && (apiError.code == 401 || apiError.code == 403) {
                // Critical unrecoverable authentication rejection: refresh token expired or revoked
                print("🚨 [AuthService] Servidor rejeitou refresh token (\(apiError.code)). Sessão encerrada.")
                self.logout()
                return false
            } catch let urlError as URLError where urlError.code == .userAuthenticationRequired {
                // Critical unrecoverable 401 on refresh endpoint
                print("🚨 [AuthService] Endpoint de refresh retornou 401. Sessão encerrada.")
                self.logout()
                return false
            } catch {
                // Non-critical network, timeout, or server downtime error:
                // NEVER LOGOUT. Maintain perennial authentication across offline sessions.
                print("⚠️ [AuthService] Falha de conexão ao renovar token (\(error.localizedDescription)). Mantendo autenticação perene.")
                return false
            }
        }

        self.ongoingRenewalTask = task
        return await task.value
    }

    private func startAutoRenewalLoop() {
        autoRenewalCancellable?.cancel()
        guard NSClassFromString("XCTestCase") == nil else { return }
        // Proactively renew tokens every 15 minutes (900 seconds) while authenticated
        autoRenewalCancellable = Timer.publish(every: 900, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self, self.isAuthenticated else { return }
                Task {
                    await self.renewTokens()
                }
            }
    }
}
