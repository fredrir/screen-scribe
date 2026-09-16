import Foundation

/// Endpoint URLs for providers that speak the OpenAI protocol.
enum OpenAICompatibleEndpoint {
    /// `/chat/completions` for a base URL such as `https://api.openai.com/v1`.
    static func chatCompletions(baseURL: String) -> URL? {
        resolve(baseURL: baseURL, path: "chat/completions")
    }

    /// `/models` for a base URL such as `https://api.openai.com/v1`.
    static func models(baseURL: String) -> URL? {
        resolve(baseURL: baseURL, path: "models")
    }

    /// Resolves an endpoint from a base URL, tolerating trailing slashes, a missing `/v1` prefix
    /// and URLs that already point at the endpoint itself.
    private static func resolve(baseURL: String, path: String) -> URL? {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host,
              !host.isEmpty else {
            return nil
        }

        let existingPath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if existingPath.isEmpty {
            components.path = "/v1/\(path)"
        } else if existingPath.hasSuffix(path) {
            components.path = "/\(existingPath)"
        } else {
            components.path = "/\(existingPath)/\(path)"
        }
        components.query = nil
        components.fragment = nil
        return components.url
    }
}

/// Client for endpoints implementing the OpenAI chat completions protocol, including OpenAI,
/// OpenRouter, Groq, Ollama and LM Studio.
@MainActor
struct OpenAICompatibleService {
    private let runner: APIRequestRunner

    /// Output token ceiling sent with every request.
    static let maxOutputTokens = 2048

    init(session: URLSession = .shared, maxRetries: Int = 3, initialDelay: UInt64 = 1_000_000_000) {
        runner = APIRequestRunner(session: session, maxRetries: maxRetries, initialDelay: initialDelay)
    }

    static func makeRequest(
        base64Image: String,
        promptContent: String,
        model: String,
        baseURL: String,
        apiKey: String
    ) throws -> URLRequest {
        let model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else {
            throw AIProviderError.invalidConfiguration("no model is set")
        }
        guard let url = OpenAICompatibleEndpoint.chatCompletions(baseURL: baseURL) else {
            throw AIProviderError.invalidConfiguration("the base URL is not a valid http address")
        }

        let payload: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": promptContent],
                ["role": "user", "content": [
                    ["type": "image_url", "image_url": ["url": "data:image/png;base64,\(base64Image)"]]
                ]]
            ],
            "max_tokens": maxOutputTokens
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        return request
    }

    static func makeModelsRequest(baseURL: String, apiKey: String) throws -> URLRequest {
        guard let url = OpenAICompatibleEndpoint.models(baseURL: baseURL) else {
            throw AIProviderError.invalidConfiguration("the base URL is not a valid http address")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    /// Reads the assistant message out of a chat completions response.
    static func parseContent(from data: Data) throws -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIProviderError.parsingError
        }
        if let message = AIProviderError.message(in: json) {
            throw AIProviderError.apiError(message)
        }
        guard let message = (json["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any] else {
            throw AIProviderError.parsingError
        }

        let text: String?
        if let content = message["content"] as? String {
            text = content
        } else if let parts = message["content"] as? [[String: Any]] {
            // Some gateways answer with content parts instead of a plain string.
            text = parts.compactMap { $0["text"] as? String }.joined()
        } else {
            text = nil
        }

        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            throw AIProviderError.parsingError
        }
        return trimmed
    }

    /// Reads the model identifiers out of a `/models` response.
    static func parseModels(from data: Data) throws -> [String] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIProviderError.parsingError
        }
        if let message = AIProviderError.message(in: json) {
            throw AIProviderError.apiError(message)
        }
        guard let entries = json["data"] as? [[String: Any]],
              !entries.isEmpty else {
            throw AIProviderError.apiError("the endpoint did not report any models")
        }

        return entries.compactMap { $0["id"] as? String }.sorted()
    }

    /// Extract content from an image using a customizable prompt.
    func extractContent(
        from base64Image: String,
        promptContent: String,
        model: String,
        baseURL: String,
        apiKey: String
    ) async throws -> String {
        let request = try Self.makeRequest(
            base64Image: base64Image,
            promptContent: promptContent,
            model: model,
            baseURL: baseURL,
            apiKey: apiKey
        )
        let (data, response) = try await runner.data(for: request)
        guard response.statusCode == 200 else {
            throw AIProviderError.fromResponse(statusCode: response.statusCode, data: data)
        }

        return try Self.parseContent(from: data)
    }

    /// Lists the models the endpoint reports.
    func fetchModels(baseURL: String, apiKey: String) async throws -> [String] {
        let request = try Self.makeModelsRequest(baseURL: baseURL, apiKey: apiKey)
        let (data, response) = try await runner.data(for: request)
        guard response.statusCode == 200 else {
            throw AIProviderError.fromResponse(statusCode: response.statusCode, data: data)
        }

        return try Self.parseModels(from: data)
    }
}
