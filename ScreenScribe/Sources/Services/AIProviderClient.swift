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

    func extractContent(
        from base64Image: String,
        promptContent: String,
        provider: AIProviderConfiguration
    ) async throws -> String {
        let model = provider.resolvedModel
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

    /// The provider's own model list, narrowed to vision models when the provider reports them.
    func availableModels(for provider: AIProviderConfiguration) async throws -> [String] {
        let baseURL = provider.resolvedBaseURL.isEmpty ? provider.kind.defaultBaseURL : provider.resolvedBaseURL
        let apiKey = provider.effectiveAPIKey

        switch provider.kind {
        case .gemini:
            return try await geminiService.fetchModels(apiKey: apiKey, baseURL: baseURL)
        case .openAICompatible:
            return try await openAIService.fetchModels(baseURL: baseURL, apiKey: apiKey)
        }
    }
}
