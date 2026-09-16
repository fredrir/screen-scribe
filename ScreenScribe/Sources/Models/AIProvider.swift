import Foundation

/// The wire protocol a provider speaks.
enum AIProviderKind: String, Codable, CaseIterable, Identifiable {
    case gemini
    case openAICompatible

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .gemini: return "Google Gemini"
        case .openAICompatible: return "OpenAI-compatible"
        }
    }

    /// Shown in the settings editor to explain what the selected type can talk to.
    var summary: String {
        switch self {
        case .gemini:
            return "Google's generateContent API."
        case .openAICompatible:
            return "Any endpoint exposing /chat/completions, such as OpenAI, OpenRouter, Groq, Ollama or LM Studio."
        }
    }

    /// Endpoint used when a provider of this kind has no base URL yet.
    var defaultBaseURL: String {
        switch self {
        case .gemini: return Config.defaultGeminiBaseURL
        case .openAICompatible: return ""
        }
    }

    /// Model used when a provider of this kind has no model yet.
    var defaultModel: String {
        switch self {
        case .gemini: return Config.defaultGeminiModelID
        case .openAICompatible: return ""
        }
    }

    /// Local OpenAI-compatible servers usually accept requests without credentials.
    var requiresAPIKey: Bool {
        switch self {
        case .gemini: return true
        case .openAICompatible: return false
        }
    }
}

/// A saved provider: protocol, endpoint, credentials and the model requests use.
struct AIProviderConfiguration: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var kind: AIProviderKind
    var baseURL: String
    var apiKey: String
    var model: String

    init(
        id: UUID = UUID(),
        name: String,
        kind: AIProviderKind,
        baseURL: String,
        apiKey: String = "",
        model: String = ""
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
    }

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? kind.displayName : trimmed
    }

    var resolvedBaseURL: String {
        baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var resolvedAPIKey: String {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Key requests should use: the configured value, or the bundled secret for Gemini.
    @MainActor
    var effectiveAPIKey: String {
        if !resolvedAPIKey.isEmpty {
            return resolvedAPIKey
        }
        guard kind == .gemini else { return "" }
        return Config.geminiAPIKey()
    }

    var resolvedModel: String {
        model.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Problems that would make a request fail. Empty when the provider is ready to use.
    @MainActor
    var validationIssues: [String] {
        var issues: [String] = []

        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append("Name is required.")
        }
        if resolvedBaseURL.isEmpty {
            issues.append("Base URL is required.")
        } else if !Self.isUsableBaseURL(resolvedBaseURL) {
            issues.append("Base URL must be an http or https address.")
        }
        if kind.requiresAPIKey && effectiveAPIKey.isEmpty {
            issues.append("API key is required.")
        }
        if resolvedModel.isEmpty {
            issues.append("Model is required.")
        }

        return issues
    }

    /// True when the text parses into an absolute http(s) URL with a host.
    static func isUsableBaseURL(_ baseURL: String) -> Bool {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host,
              !host.isEmpty else {
            return false
        }
        return true
    }
}

/// Template used by the settings UI to create a new provider entry.
struct AIProviderPreset: Identifiable, Equatable {
    let id: String
    let name: String
    let kind: AIProviderKind
    let baseURL: String
    let model: String

    func makeProvider() -> AIProviderConfiguration {
        AIProviderConfiguration(name: name, kind: kind, baseURL: baseURL, apiKey: "", model: model)
    }

    static let all: [AIProviderPreset] = [
        AIProviderPreset(
            id: "gemini",
            name: "Gemini",
            kind: .gemini,
            baseURL: Config.defaultGeminiBaseURL,
            model: Config.defaultGeminiModelID
        ),
        AIProviderPreset(
            id: "openai",
            name: "OpenAI",
            kind: .openAICompatible,
            baseURL: "https://api.openai.com/v1",
            model: "gpt-4o"
        ),
        AIProviderPreset(
            id: "openrouter",
            name: "OpenRouter",
            kind: .openAICompatible,
            baseURL: "https://openrouter.ai/api/v1",
            model: "openai/gpt-4o"
        ),
        AIProviderPreset(
            id: "groq",
            name: "Groq",
            kind: .openAICompatible,
            baseURL: "https://api.groq.com/openai/v1",
            model: "llama-3.3-70b-versatile"
        ),
        AIProviderPreset(
            id: "ollama",
            name: "Ollama",
            kind: .openAICompatible,
            baseURL: "http://localhost:11434/v1",
            model: "llama3.2"
        ),
        AIProviderPreset(
            id: "lmstudio",
            name: "LM Studio",
            kind: .openAICompatible,
            baseURL: "http://localhost:1234/v1",
            model: "local-model"
        ),
        AIProviderPreset(
            id: "custom",
            name: "Custom",
            kind: .openAICompatible,
            baseURL: "",
            model: ""
        ),
    ]
}
