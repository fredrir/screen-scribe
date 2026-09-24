import Foundation

/// Service responsible for handling AI-powered content extraction via the Gemini API
@MainActor
struct GeminiService {
    private let runner: APIRequestRunner

    init(session: URLSession = .shared, maxRetries: Int = 3, initialDelay: UInt64 = 1_000_000_000) {
        runner = APIRequestRunner(session: session, maxRetries: maxRetries, initialDelay: initialDelay)
    }

    static func makeRequest(
        base64Image: String,
        apiKey: String,
        promptContent: String,
        model: String,
        baseURL: String = Config.defaultGeminiBaseURL
    ) throws -> URLRequest {
        guard !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIProviderError.invalidConfiguration("no model is set")
        }

        let payload: [String: Any] = [
            "contents": [[
                "parts": [
                    ["inline_data": [
                        "mime_type": "image/png",
                        "data": base64Image
                    ]]
                ]
            ]],
            "systemInstruction": [
                "parts": [
                    ["text": promptContent]
                ]
            ],
            "generationConfig": [
                "maxOutputTokens": 2048
            ]
        ]

        guard let url = URL(string: "\(Config.geminiEndpoint(for: model, baseURL: baseURL))?key=\(apiKey)") else {
            throw AIProviderError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        return request
    }

    /// Extract content from an image using a customizable prompt
    /// - Parameters:
    ///   - base64Image: The image encoded as base64 PNG
    ///   - apiKey: The Gemini API key
    ///   - promptContent: The system prompt to use for extraction
    ///   - model: The Gemini model to send the request to
    ///   - baseURL: The API root to send the request to
    /// - Returns: The extracted content as a string
    func extractContent(
        from base64Image: String,
        apiKey: String,
        promptContent: String,
        model: String,
        baseURL: String = Config.defaultGeminiBaseURL
    ) async throws -> String {
        guard !apiKey.isEmpty else {
            throw AIProviderError.apiKeyMissing
        }

        let request = try Self.makeRequest(
            base64Image: base64Image,
            apiKey: apiKey,
            promptContent: promptContent,
            model: model,
            baseURL: baseURL
        )

        let (data, response) = try await runner.data(for: request)
        guard response.statusCode == 200 else {
            throw AIProviderError.fromResponse(statusCode: response.statusCode, data: data)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let firstPart = parts.first,
              let text = firstPart["text"] as? String else {
            throw AIProviderError.parsingError
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func makeModelsRequest(apiKey: String, baseURL: String, pageToken: String?) throws -> URLRequest {
        guard var components = URLComponents(string: Config.geminiModelsEndpoint(baseURL: baseURL)) else {
            throw AIProviderError.invalidConfiguration("the base URL is not a valid http address")
        }
        components.queryItems = [URLQueryItem(name: "pageSize", value: "1000")]
            + (pageToken.map { [URLQueryItem(name: "pageToken", value: $0)] } ?? [])
        guard let url = components.url else {
            throw AIProviderError.invalidConfiguration("the base URL is not a valid http address")
        }

        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        return request
    }

    /// Reads one page of models, keeping those that support `generateContent`, the only method
    /// requests use. Gemini doesn't report which models accept images, so nothing else is filtered.
    static func parseModels(from data: Data) throws -> (models: [String], nextPageToken: String?) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIProviderError.parsingError
        }
        if let message = AIProviderError.message(in: json) {
            throw AIProviderError.apiError(message)
        }

        let entries = json["models"] as? [[String: Any]] ?? []
        let models = entries.compactMap { entry -> String? in
            guard let name = entry["name"] as? String,
                  (entry["supportedGenerationMethods"] as? [String])?.contains("generateContent") == true else {
                return nil
            }
            return name.hasPrefix("models/") ? String(name.dropFirst("models/".count)) : name
        }
        let nextPageToken = (json["nextPageToken"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        return (models, nextPageToken)
    }

    func fetchModels(apiKey: String, baseURL: String = Config.defaultGeminiBaseURL) async throws -> [String] {
        guard !apiKey.isEmpty else {
            throw AIProviderError.apiKeyMissing
        }

        var models: [String] = []
        var pageToken: String?
        repeat {
            let request = try Self.makeModelsRequest(apiKey: apiKey, baseURL: baseURL, pageToken: pageToken)
            let (data, response) = try await runner.data(for: request)
            guard response.statusCode == 200 else {
                throw AIProviderError.fromResponse(statusCode: response.statusCode, data: data)
            }
            let page = try Self.parseModels(from: data)
            models += page.models
            pageToken = page.nextPageToken
        } while pageToken != nil

        guard !models.isEmpty else {
            throw AIProviderError.apiError("the endpoint did not report any models")
        }
        return models.sorted()
    }
}

