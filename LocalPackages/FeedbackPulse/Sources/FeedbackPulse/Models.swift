//
//  Models.swift
//  FeedbackPulse
//
//  Data models for the FeedbackPulse SDK
//

import Foundation

// MARK: - Sentiment

/// Feedback sentiment options
public enum FeedbackSentiment: String, Codable {
    case positive = "positive"
    case neutral = "neutral"
    case negative = "negative"
}

// MARK: - Rating Type

/// Rating type options for feedback submission
public enum RatingType: String, Codable {
    case thumbs = "thumbs"
    case emoji = "emoji"
    case stars = "stars"
    case nps = "nps"
}

// MARK: - Environment

/// Environment for feedback submission
public enum FeedbackEnvironment: String {
    case production = "production"
    case development = "development"
}

// MARK: - Response

/// Response from feedback submission
public struct FeedbackResponse: Codable {
    /// The unique ID of the submitted feedback.
    /// Vendored fix: the API returns this as a JSON number, but the stock SDK
    /// typed it as `String`, which made a *successful* submission fail to decode
    /// (and be reported to the app as a failure). Typed as `Int` to match the API.
    public let feedbackId: Int

    /// Status message. Made optional for resilience if the server omits it.
    public let message: String?

    private enum CodingKeys: String, CodingKey {
        case feedbackId = "feedback_id"
        case message
    }
}

// MARK: - Errors

/// Errors that can occur during feedback submission
public enum FeedbackError: Error, LocalizedError {
    case notConfigured
    case networkError(Error)
    case invalidResponse
    case noData
    case encodingError
    case decodingError
    case unauthorized
    case rateLimited
    case httpError(Int)

    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "FeedbackPulse SDK is not configured. Call FeedbackPulse.configure(apiKey:) first."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid response from server"
        case .noData:
            return "No data received from server"
        case .encodingError:
            return "Failed to encode request"
        case .decodingError:
            return "Failed to decode response"
        case .unauthorized:
            return "Invalid API key"
        case .rateLimited:
            return "Rate limit exceeded. Please try again later."
        case .httpError(let code):
            return "HTTP error: \(code)"
        }
    }
}
