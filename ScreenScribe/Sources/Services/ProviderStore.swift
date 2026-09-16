import Foundation

/// The list of configured AI providers, which one is active, and their persistence.
@MainActor
final class ProviderStore: ObservableObject {
    static let shared = ProviderStore()

    static let providersKey = "aiProviders"
    static let activeProviderKey = "activeProviderID"

    private let defaults: UserDefaults

    @Published private(set) var providers: [AIProviderConfiguration] {
        didSet { persistProviders() }
    }

    @Published var activeProviderID: UUID {
        didSet { defaults.set(activeProviderID.uuidString, forKey: Self.activeProviderKey) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let loaded = Self.loadProviders(from: defaults)
        let resolved = loaded.isEmpty ? [Self.migratedProvider(from: defaults)] : loaded
        providers = resolved

        let storedID = defaults.string(forKey: Self.activeProviderKey).flatMap(UUID.init(uuidString:))
        activeProviderID = resolved.first(where: { $0.id == storedID })?.id ?? resolved[0].id

        if loaded.isEmpty {
            persistProviders()
            defaults.set(activeProviderID.uuidString, forKey: Self.activeProviderKey)
        }
    }

    /// The provider requests are sent to, falling back to the first entry when the stored
    /// selection no longer exists.
    var activeProvider: AIProviderConfiguration {
        providers.first(where: { $0.id == activeProviderID }) ?? providers[0]
    }

    func provider(id: UUID) -> AIProviderConfiguration? {
        providers.first(where: { $0.id == id })
    }

    @discardableResult
    func add(_ provider: AIProviderConfiguration, activate: Bool = true) -> AIProviderConfiguration {
        var provider = provider
        provider.name = uniquifiedName(provider.name)
        providers.append(provider)
        if activate {
            activeProviderID = provider.id
        }
        return provider
    }

    @discardableResult
    func add(preset: AIProviderPreset, activate: Bool = true) -> AIProviderConfiguration {
        add(preset.makeProvider(), activate: activate)
    }

    func update(_ provider: AIProviderConfiguration) {
        guard let index = providers.firstIndex(where: { $0.id == provider.id }) else { return }
        providers[index] = provider
    }

    /// Removes a provider. The last remaining provider is kept so the app always has a target.
    func remove(id: UUID) {
        guard providers.count > 1,
              let index = providers.firstIndex(where: { $0.id == id }) else {
            return
        }

        providers.remove(at: index)
        if activeProviderID == id {
            activeProviderID = providers[0].id
        }
    }

    func setActiveProvider(_ id: UUID) {
        guard providers.contains(where: { $0.id == id }) else { return }
        activeProviderID = id
    }

    private func persistProviders() {
        guard let data = try? JSONEncoder().encode(providers) else { return }
        defaults.set(data, forKey: Self.providersKey)
    }

    /// Appends a counter to keep provider names distinguishable in the menu.
    private func uniquifiedName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? AIProviderKind.openAICompatible.displayName : trimmed
        guard providers.contains(where: { $0.displayName == base }) else {
            return base
        }

        var suffix = 2
        while providers.contains(where: { $0.displayName == "\(base) \(suffix)" }) {
            suffix += 1
        }
        return "\(base) \(suffix)"
    }

    private static func loadProviders(from defaults: UserDefaults) -> [AIProviderConfiguration] {
        guard let data = defaults.data(forKey: providersKey),
              let decoded = try? JSONDecoder().decode([AIProviderConfiguration].self, from: data) else {
            return []
        }
        return decoded
    }

    /// First launch after the single-provider release: carry the old Gemini settings over.
    private static func migratedProvider(from defaults: UserDefaults) -> AIProviderConfiguration {
        AIProviderConfiguration(
            name: AIProviderPreset.all[0].name,
            kind: .gemini,
            baseURL: Config.defaultGeminiBaseURL,
            apiKey: defaults.string(forKey: "geminiAPIKey") ?? "",
            model: Config.resolvedGeminiModelID(from: defaults.string(forKey: "geminiModel"))
        )
    }
}
