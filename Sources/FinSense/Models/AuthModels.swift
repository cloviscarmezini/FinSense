// Sources/FinSense/Models/AuthModels.swift
import Foundation

public struct UserSummary: Codable, Identifiable, Hashable {
    public let id: UUID
    public let email: String
    public let fullName: String

    public init(id: UUID, email: String, fullName: String) {
        self.id = id
        self.email = email
        self.fullName = fullName
    }

    enum CodingKeys: String, CodingKey {
        case id, email
        case fullName = "full_name"
    }
}

public struct AuthResponse: Codable {
    public let accessToken: String
    public let refreshToken: String
    public let tokenType: String
    public let expiresIn: Int
    public let user: UserSummary

    public init(accessToken: String, refreshToken: String, tokenType: String, expiresIn: Int, user: UserSummary) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.tokenType = tokenType
        self.expiresIn = expiresIn
        self.user = user
    }

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case user
    }
}

public struct UserMeResponse: Codable {
    public let id: UUID
    public let email: String
    public let fullName: String
    public let isActive: Bool
    public let createdAt: String

    public init(id: UUID, email: String, fullName: String, isActive: Bool, createdAt: String) {
        self.id = id
        self.email = email
        self.fullName = fullName
        self.isActive = isActive
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id, email
        case fullName = "full_name"
        case isActive = "is_active"
        case createdAt = "created_at"
    }
}

public struct APIErrorResponse: Codable {
    public struct ErrorDetail: Codable {
        public let code: String
        public let message: String
        public let statusCode: Int

        enum CodingKeys: String, CodingKey {
            case code, message
            case statusCode = "status_code"
        }
    }
    public let error: ErrorDetail
}
