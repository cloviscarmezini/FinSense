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

    private init() {
        restoreSession()
    }

    private func restoreSession() {
        if let token = KeychainHelper.shared.read(key: tokenKey), !token.isEmpty {
            if let userJson = UserDefaults.standard.string(forKey: userKey),
               let data = userJson.data(using: .utf8),
               let user = try? JSONDecoder().decode(UserSummary.self, from: data) {
                self.currentUser = user
                self.isAuthenticated = true
            } else {
                self.isAuthenticated = true
            }
        } else {
            self.isAuthenticated = false
            self.currentUser = nil
        }
    }

    public var accessToken: String? {
        KeychainHelper.shared.read(key: tokenKey)
    }

    public var refreshToken: String? {
        KeychainHelper.shared.read(key: refreshKey)
    }

    public func login(email: String, password: String, baseURL: String) async -> Bool {
        isLoading = true
        authErrorMessage = nil
        defer { isLoading = false }

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
        KeychainHelper.shared.delete(key: tokenKey)
        KeychainHelper.shared.delete(key: refreshKey)
        UserDefaults.standard.removeObject(forKey: userKey)
        UserDefaults.standard.removeObject(forKey: "cloud_sync_last_revision")
        self.isAuthenticated = false
        self.currentUser = nil
    }

    public func saveSession(_ res: AuthResponse) {
        KeychainHelper.shared.save(key: tokenKey, value: res.accessToken)
        KeychainHelper.shared.save(key: refreshKey, value: res.refreshToken)
        if let data = try? JSONEncoder().encode(res.user),
           let str = String(data: data, encoding: .utf8) {
            UserDefaults.standard.set(str, forKey: userKey)
        }
        self.currentUser = res.user
        self.isAuthenticated = true
    }

    public func renewTokens(baseURL: String) async -> Bool {
        guard let refresh = refreshToken else {
            logout()
            return false
        }

        do {
            let res = try await BackendAPIClient.shared.refreshTokens(baseURL: baseURL, refreshToken: refresh)
            saveSession(res)
            return true
        } catch {
            logout()
            return false
        }
    }
}
