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
}

