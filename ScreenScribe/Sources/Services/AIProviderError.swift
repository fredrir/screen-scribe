import Foundation

/// Errors surfaced by the provider clients.
enum AIProviderError: Error, LocalizedError {
    case apiKeyMissing
    case apiKeyInvalid(String?)
    case apiError(String)
    case requestFailed(Error)
    case invalidResponse
    case invalidConfiguration(String)
    case imageProcessingFailed
    case networkError(Error)
    case parsingError

    var errorDescription: String? {
        switch self {
        case .apiKeyMissing:
            return "Missing API key"
        case .apiKeyInvalid(let message):
            guard let message, !message.isEmpty else { return "Invalid API key" }
            return "Invalid API key: \(message)"
        case .apiError(let message):
            return "API Error: \(message)"
        case .requestFailed(let error):
            return "Request failed: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid response from server"
        case .invalidConfiguration(let message):
            return "Invalid configuration: \(message)"
        case .imageProcessingFailed:
            return "Failed to process image"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .parsingError:
            return "Failed to parse response"
        }
    }
}

extension AIProviderError {
    /// Provider-supplied error text inside a JSON body, if any.
    static func message(in json: [String: Any]) -> String? {
        if let error = json["error"] as? [String: Any] {
            if let message = error["message"] as? String { return message }
            if let detail = error["detail"] as? String { return detail }
        }
        if let error = json["error"] as? String { return error }
        if let message = json["message"] as? String { return message }
        return nil
    }

    /// Builds an error for a failed HTTP response, preferring the provider's own message.
    static func fromResponse(statusCode: Int, data: Data) -> AIProviderError {
        var providerMessage: String?
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            providerMessage = message(in: json)
        }

        if statusCode == 401 || statusCode == 403 {
            return .apiKeyInvalid(providerMessage)
        }
        if let providerMessage {
            return .apiError(providerMessage)
        }
        return .apiError("API request failed with status \(statusCode)")
    }
}
