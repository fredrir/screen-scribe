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
    /// The preset this provider was created from, so renaming or re-pointing it never reclassifies it.
    var presetID: String

    init(
        id: UUID = UUID(),
        name: String,
        kind: AIProviderKind,
        baseURL: String,
        apiKey: String = "",
        model: String = "",
        presetID: String = AIProviderPreset.custom.id
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
        self.presetID = presetID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        kind = try container.decode(AIProviderKind.self, forKey: .kind)
        baseURL = try container.decode(String.self, forKey: .baseURL)
        apiKey = try container.decode(String.self, forKey: .apiKey)
        model = try container.decode(String.self, forKey: .model)
        presetID = try container.decodeIfPresent(String.self, forKey: .presetID)
            ?? Self.legacyPresetID(name: name, kind: kind)
    }

    /// Providers saved before `presetID` existed counted as a preset only while they kept its name.
    private static func legacyPresetID(name: String, kind: AIProviderKind) -> String {
        let preset = AIProviderPreset.all.first { $0.name == name && $0.kind == kind && $0 != .custom }
        return preset?.id ?? AIProviderPreset.custom.id
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

    /// Whether requests to this provider are expected to carry an API key.
    /// Cloud services and custom endpoints require one; local servers do not.
    var requiresAPIKey: Bool {
        if kind == .gemini { return true }
        if let preset = matchingPreset, preset.isLocal { return false }
        return true
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
        if requiresAPIKey && effectiveAPIKey.isEmpty {
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

    func makeProvider() -> AIProviderConfiguration {
        AIProviderConfiguration(name: name, kind: kind, baseURL: baseURL, presetID: id)
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

    static let all: [AIProviderPreset] = [
        AIProviderPreset(
            id: "gemini",
            name: "Gemini",
            kind: .gemini,
            baseURL: Config.defaultGeminiBaseURL
        ),
        AIProviderPreset(
            id: "openai",
            name: "OpenAI",
            kind: .openAICompatible,
            baseURL: "https://api.openai.com/v1"
        ),
        AIProviderPreset(
            id: "openrouter",
            name: "OpenRouter",
            kind: .openAICompatible,
            baseURL: "https://openrouter.ai/api/v1"
        ),
        AIProviderPreset(
            id: "groq",
            name: "Groq",
            kind: .openAICompatible,
            baseURL: "https://api.groq.com/openai/v1"
        ),
        AIProviderPreset(
            id: "ollama",
            name: "Ollama",
            kind: .openAICompatible,
            baseURL: "http://localhost:11434/v1"
        ),
        AIProviderPreset(
            id: "lmstudio",
            name: "LM Studio",
            kind: .openAICompatible,
            baseURL: "http://localhost:1234/v1"
        ),
        custom,
    ]

    static let custom = AIProviderPreset(
        id: "custom",
        name: "Custom Endpoint",
        kind: .openAICompatible,
        baseURL: ""
    )
}

extension AIProviderConfiguration {
    var matchingPreset: AIProviderPreset? {
        AIProviderPreset.all.first { $0.id == presetID }
    }

    var isLocal: Bool {
        matchingPreset?.isLocal ?? false
    }

    var isCustom: Bool {
        presetID == AIProviderPreset.custom.id
    }
}

