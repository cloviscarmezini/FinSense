// Sources/FinSense/Services/BackendAPIClient.swift
import Foundation

public final class BackendAPIClient {
    public static let shared = BackendAPIClient()
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 25.0
        config.timeoutIntervalForResource = 60.0
        config.waitsForConnectivity = false
        self.session = URLSession(configuration: config)
    }

    // MARK: - Autenticação
    public func login(baseURL: String, email: String, password: String) async throws -> AuthResponse {
        guard let url = URL(string: "\(baseURL)/auth/login") else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["email": email, "password": password])

        return try await sendRequest(req)
    }

    public func register(baseURL: String, fullName: String, email: String, password: String) async throws -> AuthResponse {
        guard let url = URL(string: "\(baseURL)/auth/register") else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "full_name": fullName,
            "email": email,
            "password": password
        ])

        return try await sendRequest(req)
    }

    public func refreshTokens(baseURL: String, refreshToken: String) async throws -> AuthResponse {
        guard let url = URL(string: "\(baseURL)/auth/refresh") else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["refresh_token": refreshToken])

        return try await sendRequest(req)
    }

    // MARK: - Core Two-Way Sync
    public func pushPull(baseURL: String, requestPayload: SyncPushPullRequest) async throws -> SyncPushPullResponse {
        guard let url = URL(string: "\(baseURL)/sync/push-pull") else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        if let token = await AuthService.shared.accessToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        req.httpBody = try encoder.encode(requestPayload)

        do {
            return try await sendRequest(req)
        } catch let error as URLError where error.code == .userAuthenticationRequired {
            // Tentativa de renovação transparente
            let renewed = await AuthService.shared.renewTokens(baseURL: baseURL)
            if renewed, let newToken = await AuthService.shared.accessToken {
                req.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")
                return try await sendRequest(req)
            } else {
                throw error
            }
        }
    }

    private func sendRequest<T: Decodable>(_ req: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: req)
        guard let httpRes = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        if httpRes.statusCode == 401 {
            throw URLError(.userAuthenticationRequired)
        }

        guard (200...299).contains(httpRes.statusCode) else {
            if let apiErr = try? JSONDecoder().decode(APIErrorResponse.self, from: data) {
                throw NSError(domain: "FinSenseAPI", code: httpRes.statusCode, userInfo: [NSLocalizedDescriptionKey: apiErr.error.message])
            }
            if let str = String(data: data, encoding: .utf8), !str.isEmpty {
                throw NSError(domain: "FinSenseAPI", code: httpRes.statusCode, userInfo: [NSLocalizedDescriptionKey: str])
            }
            throw URLError(.init(rawValue: httpRes.statusCode))
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: data)
    }
}
