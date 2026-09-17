import Foundation

/// Routes requests to the client matching a provider's protocol.
@MainActor
struct AIProviderClient {
    private let geminiService: GeminiService
    private let openAIService: OpenAICompatibleService

    init() {
        geminiService = GeminiService()
        openAIService = OpenAICompatibleService()
    }

    /// The model a request for this provider should use, applying Gemini's model migration rules.
    static func resolvedModel(for provider: AIProviderConfiguration) -> String {
        if provider.resolvedModel.isEmpty {
            return provider.kind.defaultModel
        }
        switch provider.kind {
        case .gemini:
            return Config.resolvedGeminiModelID(from: provider.resolvedModel)
        case .openAICompatible:
            return provider.resolvedModel
        }
    }

    func extractContent(
        from base64Image: String,
        promptContent: String,
        provider: AIProviderConfiguration
    ) async throws -> String {
        let model = Self.resolvedModel(for: provider)
        let baseURL = provider.resolvedBaseURL.isEmpty ? provider.kind.defaultBaseURL : provider.resolvedBaseURL
        let apiKey = provider.effectiveAPIKey

        switch provider.kind {
        case .gemini:
            return try await geminiService.extractContent(
                from: base64Image,
                apiKey: apiKey,
                promptContent: promptContent,
                model: model,
                baseURL: baseURL
            )
        case .openAICompatible:
            return try await openAIService.extractContent(
                from: base64Image,
                promptContent: promptContent,
                model: model,
                baseURL: baseURL,
                apiKey: apiKey
            )
        }
    }

    /// Models offered in the settings UI: a bundled catalog for Gemini, a network lookup otherwise.
    func availableModels(for provider: AIProviderConfiguration) async throws -> [ProviderModelOption] {
        switch provider.kind {
        case .gemini:
            return Config.availableGeminiModels.map { ProviderModelOption(id: $0.id, label: $0.label) }
        case .openAICompatible:
            let baseURL = provider.resolvedBaseURL.isEmpty ? provider.kind.defaultBaseURL : provider.resolvedBaseURL
            return try await openAIService.fetchModels(baseURL: baseURL, apiKey: provider.effectiveAPIKey)
                .map { ProviderModelOption(id: $0, label: $0) }
        }
    }
}
