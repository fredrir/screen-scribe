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

/// A model option offered in the provider settings UI.
struct ProviderModelOption: Identifiable, Equatable {
    let id: String
    let label: String
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

    var websiteURL: URL? {
        switch id {
        case "gemini":
            return URL(string: "https://aistudio.google.com/app/apikey")
        case "openai":
            return URL(string: "https://platform.openai.com/api-keys")
        case "openrouter":
            return URL(string: "https://openrouter.ai/keys")
        case "groq":
            return URL(string: "https://console.groq.com/keys")
        default:
            return nil
        }
    }

    var isLocal: Bool {
        id == "ollama" || id == "lmstudio"
    }

    var suggestedModels: [ProviderModelOption] {
        switch id {
        case "gemini":
            return Config.availableGeminiModels.map {
                ProviderModelOption(id: $0.id, label: "\($0.label)\($0.note.map { " (\($0))" } ?? "")")
            }
        case "openai":
            return [
                ProviderModelOption(id: "gpt-4o", label: "GPT-4o (Recommended)"),
                ProviderModelOption(id: "gpt-4o-mini", label: "GPT-4o Mini (Fast)"),
                ProviderModelOption(id: "o1", label: "o1 (Reasoning)"),
                ProviderModelOption(id: "o3-mini", label: "o3-mini (Fast Reasoning)")
            ]
        case "openrouter":
            return [
                ProviderModelOption(id: "openai/gpt-4o", label: "OpenAI: GPT-4o"),
                ProviderModelOption(id: "anthropic/claude-3.5-sonnet", label: "Anthropic: Claude 3.5 Sonnet"),
                ProviderModelOption(id: "google/gemini-2.5-flash", label: "Google: Gemini 2.5 Flash"),
                ProviderModelOption(id: "deepseek/deepseek-chat", label: "DeepSeek: V3")
            ]
        case "groq":
            return [
                ProviderModelOption(id: "llama-3.3-70b-versatile", label: "Llama 3.3 70B Versatile"),
                ProviderModelOption(id: "llama-3.1-8b-instant", label: "Llama 3.1 8B Instant")
            ]
        case "ollama":
            return [
                ProviderModelOption(id: "llama3.2", label: "llama3.2"),
                ProviderModelOption(id: "llava", label: "llava (Vision)")
            ]
        case "lmstudio":
            return [
                ProviderModelOption(id: "local-model", label: "local-model")
            ]
        default:
            return []
        }
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

extension AIProviderConfiguration {
    var matchingPreset: AIProviderPreset? {
        if kind == .gemini {
            return AIProviderPreset.all.first(where: { $0.id == "gemini" })
        }
        let url = baseURL.lowercased()
        let n = name.lowercased()
        if n == "openai" || url.contains("api.openai.com") {
            return AIProviderPreset.all.first(where: { $0.id == "openai" })
        }
        if n == "openrouter" || url.contains("openrouter.ai") {
            return AIProviderPreset.all.first(where: { $0.id == "openrouter" })
        }
        if n == "groq" || url.contains("api.groq.com") {
            return AIProviderPreset.all.first(where: { $0.id == "groq" })
        }
        if n == "ollama" || url.contains("11434") {
            return AIProviderPreset.all.first(where: { $0.id == "ollama" })
        }
        if n == "lm studio" || url.contains("1234") {
            return AIProviderPreset.all.first(where: { $0.id == "lmstudio" })
        }
        return nil
    }

    var isLocal: Bool {
        matchingPreset?.isLocal ?? false
    }

    var presetID: String {
        matchingPreset?.id ?? "custom"
    }
}

