import Foundation

enum OpenAICompatibleEndpoint {
    static func chatCompletions(baseURL: String) -> URL? {
        resolve(baseURL: baseURL, path: "chat/completions")
    }

    static func models(baseURL: String) -> URL? {
        resolve(baseURL: baseURL, path: "models")
    }

    static func modelInfo(baseURL: String) -> URL? {
        resolve(baseURL: baseURL, path: "model/info")
    }

    static func serverRoute(baseURL: String, path: String) -> URL? {
        guard var components = validatedComponents(baseURL) else { return nil }

        var segments = components.path.split(separator: "/").map(String.init)
        if segments.last?.lowercased() == "v1" {
            segments.removeLast()
        }
        components.path = "/" + (segments + [path]).joined(separator: "/")
        components.query = nil
        components.fragment = nil
        return components.url
    }

    private static func validatedComponents(_ baseURL: String) -> URLComponents? {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
            let components = URLComponents(string: trimmed),
            let scheme = components.scheme?.lowercased(),
            scheme == "http" || scheme == "https",
            let host = components.host,
            !host.isEmpty
        else {
            return nil
        }
        return components
    }

    private static func resolve(baseURL: String, path: String) -> URL? {
        guard var components = validatedComponents(baseURL) else { return nil }

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

@MainActor
struct OpenAICompatibleService {
    private let runner: APIRequestRunner

    static let maxOutputTokens = 2048

    init(session: URLSession = .shared, maxRetries: Int = 3, initialDelay: UInt64 = 1_000_000_000) {
        runner = APIRequestRunner(
            session: session, maxRetries: maxRetries, initialDelay: initialDelay)
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
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "image_url",
                            "image_url": ["url": "data:image/png;base64,\(base64Image)"],
                        ]
                    ],
                ],
            ],
            "max_tokens": maxOutputTokens,
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

    static func parseContent(from data: Data) throws -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIProviderError.parsingError
        }
        if let message = AIProviderError.message(in: json) {
            throw AIProviderError.apiError(message)
        }
        guard
            let message = (json["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any]
        else {
            throw AIProviderError.parsingError
        }

        let text: String?
        if let content = message["content"] as? String {
            text = content
        } else if let parts = message["content"] as? [[String: Any]] {
            text = parts.compactMap { $0["text"] as? String }.joined()
        } else {
            text = nil
        }

        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty
        else {
            throw AIProviderError.parsingError
        }
        return trimmed
    }

    static func parseModels(from data: Data) throws -> [String] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIProviderError.parsingError
        }
        if let message = AIProviderError.message(in: json) {
            throw AIProviderError.apiError(message)
        }
        guard let entries = json["data"] as? [[String: Any]],
            !entries.isEmpty
        else {
            throw AIProviderError.apiError("the endpoint did not report any models")
        }

        return entries.compactMap { $0["id"] as? String }.sorted()
    }

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

    func fetchModels(baseURL: String, apiKey: String) async throws -> [String] {
        let request = try Self.makeModelsRequest(baseURL: baseURL, apiKey: apiKey)
        let (data, response) = try await runner.data(for: request)
        guard response.statusCode == 200 else {
            throw AIProviderError.fromResponse(statusCode: response.statusCode, data: data)
        }
        let modelIDs = try Self.parseModels(from: data)

        let discovery = VisionModelDiscovery(runner: runner, baseURL: baseURL, apiKey: apiKey)
        guard
            let visionModels = await discovery.visionModels(
                modelsResponse: data, modelIDs: modelIDs)
        else {
            return modelIDs
        }
        guard !visionModels.isEmpty else {
            throw VisionModelListError.noVisionModels
        }
        return visionModels
    }
}
