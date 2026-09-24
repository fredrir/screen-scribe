import Foundation

/// The server reports image support, and none of its models have it.
enum VisionModelListError: Error, LocalizedError {
    case noVisionModels

    var errorDescription: String? {
        "None of this endpoint's models accept images."
    }
}

/// Finds the models on an OpenAI-compatible server that accept images. Plain `/models` responses
/// rarely say, so this falls back to the native APIs of LiteLLM, LM Studio and Ollama.
struct VisionModelDiscovery {
    let runner: APIRequestRunner
    let baseURL: String
    let apiKey: String

    /// Vision model IDs, or nil when the server doesn't report image support at all.
    func visionModels(modelsResponse: Data, modelIDs: [String]) async -> [String]? {
        if let models = Self.parseInlineVisionModels(from: modelsResponse) {
            return models
        }

        async let liteLLM = get(OpenAICompatibleEndpoint.modelInfo(baseURL: baseURL))
        async let lmStudio = get(OpenAICompatibleEndpoint.serverRoute(baseURL: baseURL, path: "api/v1/models"))
        async let lmStudioLegacy = get(OpenAICompatibleEndpoint.serverRoute(baseURL: baseURL, path: "api/v0/models"))
        async let ollama = ollamaVisionModels(modelIDs)

        if let data = await liteLLM, let models = Self.parseLiteLLMVisionModels(from: data) {
            return models
        }
        if let data = await lmStudio, let models = Self.parseLMStudioVisionModels(from: data) {
            return models
        }
        if let data = await lmStudioLegacy, let models = Self.parseLMStudioVisionModels(from: data) {
            return models
        }
        return await ollama
    }

    /// OpenRouter reports `architecture.input_modalities`, Mistral reports `capabilities.vision`.
    static func parseInlineVisionModels(from data: Data) -> [String]? {
        visionModels(in: entries(in: data, key: "data"), idKey: "id") { entry in
            if let modalities = (entry["architecture"] as? [String: Any])?["input_modalities"] as? [String] {
                return modalities.contains("image")
            }
            return capabilitiesVision(of: entry)
        }
    }

    /// LiteLLM's `/model/info` reports `model_info.supports_vision`.
    static func parseLiteLLMVisionModels(from data: Data) -> [String]? {
        visionModels(in: entries(in: data, key: "data"), idKey: "model_name") { entry in
            (entry["model_info"] as? [String: Any])?["supports_vision"] as? Bool
        }
    }

    /// LM Studio's `/api/v1/models` reports `capabilities.vision`; the older `/api/v0/models`
    /// reports `type: "vlm"`.
    static func parseLMStudioVisionModels(from data: Data) -> [String]? {
        visionModels(in: entries(in: data, key: "models"), idKey: "key", supportsVision: capabilitiesVision)
            ?? visionModels(in: entries(in: data, key: "data"), idKey: "id") { entry in
                (entry["type"] as? String).map { $0 == "vlm" }
            }
    }

    /// Ollama's `/api/show` lists capabilities such as `["completion", "vision"]`.
    static func parseOllamaSupportsVision(from data: Data) -> Bool? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let capabilities = json["capabilities"] as? [String] else {
            return nil
        }
        return capabilities.contains("vision")
    }

    private static func capabilitiesVision(of entry: [String: Any]) -> Bool? {
        (entry["capabilities"] as? [String: Any])?["vision"] as? Bool
    }

    private static func entries(in data: Data, key: String) -> [[String: Any]] {
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        return json?[key] as? [[String: Any]] ?? []
    }

    /// Nil when no entry says either way, so the caller can try another source.
    private static func visionModels(
        in entries: [[String: Any]],
        idKey: String,
        supportsVision: ([String: Any]) -> Bool?
    ) -> [String]? {
        var reported = false
        var models: Set<String> = []
        for entry in entries {
            guard let id = entry[idKey] as? String, let vision = supportsVision(entry) else { continue }
            reported = true
            if vision { models.insert(id) }
        }
        return reported ? models.sorted() : nil
    }

    /// Ollama only reports capabilities per model, so each one is looked up.
    private func ollamaVisionModels(_ modelIDs: [String]) async -> [String]? {
        guard let url = OpenAICompatibleEndpoint.serverRoute(baseURL: baseURL, path: "api/show") else {
            return nil
        }

        var models: [String] = []
        for (index, id) in modelIDs.enumerated() {
            let supportsVision = await post(url, body: ["model": id]).flatMap(Self.parseOllamaSupportsVision)
            // The first answer decides whether this is an Ollama server at all.
            if supportsVision == nil && index == 0 { return nil }
            if supportsVision == true { models.append(id) }
        }
        return models
    }

    private func get(_ url: URL?) async -> Data? {
        guard let url else { return nil }
        return await send(URLRequest(url: url))
    }

    private func post(_ url: URL, body: [String: String]) async -> Data? {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return await send(request)
    }

    /// Probes are best effort: a failure only means the server doesn't speak that API.
    private func send(_ request: URLRequest) async -> Data? {
        var request = request
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        guard let (data, response) = try? await runner.data(for: request),
              response.statusCode == 200 else {
            return nil
        }
        return data
    }
}
