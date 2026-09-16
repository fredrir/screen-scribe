import Foundation

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

@main
struct ProviderStoreTests {
    @MainActor
    static func main() {
        let suiteName = "ScreenScribeProviderStoreTests"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fputs("FAIL: Could not create an isolated defaults suite\n", stderr)
            exit(1)
        }
        defaults.removePersistentDomain(forName: suiteName)

        checkMigration(defaults: defaults)
        checkCRUD(defaults: defaults)
        print("ProviderStoreTests passed")
    }

    /// Settings saved by the Gemini-only release should become the first provider.
    @MainActor
    private static func checkMigration(defaults: UserDefaults) {
        defaults.set("legacy-key", forKey: "geminiAPIKey")
        defaults.set("gemini-3.5-flash", forKey: "geminiModel")

        let store = ProviderStore(defaults: defaults)
        expect(store.providers.count == 1, "A fresh install should start with one provider")

        let migrated = store.activeProvider
        expect(migrated.name == "Gemini", "The migrated provider should be named after the preset")
        expect(migrated.kind == .gemini, "The migrated provider should speak the Gemini protocol")
        expect(migrated.baseURL == Config.defaultGeminiBaseURL,
               "The migrated provider should use the default Gemini endpoint")
        expect(migrated.apiKey == "legacy-key", "The stored API key should be carried over")
        expect(migrated.model == "gemini-3.7-flash",
               "The stored model should be migrated to the current catalog entry")

        expect(defaults.data(forKey: ProviderStore.providersKey) != nil,
               "The migrated provider should be persisted")
        expect(defaults.string(forKey: ProviderStore.activeProviderKey) == migrated.id.uuidString,
               "The active provider should be persisted")

        let reloaded = ProviderStore(defaults: defaults)
        expect(reloaded.providers.count == 1, "Migration should only run once")
        expect(reloaded.providers[0].id == migrated.id, "The reloaded provider should be the same one")

        print("  migration ok")
    }

    @MainActor
    private static func checkCRUD(defaults: UserDefaults) {
        let store = ProviderStore(defaults: defaults)
        let gemini = store.activeProvider

        let duplicate = store.add(preset: AIProviderPreset.all[0])
        expect(store.providers.count == 2, "Adding a provider should append it")
        expect(duplicate.name == "Gemini 2", "Duplicate names should be made unique")
        expect(store.activeProviderID == duplicate.id, "Added providers should become active")

        let openAI = store.add(preset: AIProviderPreset.all[1])
        expect(openAI.kind == .openAICompatible, "The OpenAI preset should be an OpenAI-compatible provider")
        expect(openAI.baseURL == "https://api.openai.com/v1", "The preset should prefill the base URL")

        var edited = openAI
        edited.name = "Work"
        edited.model = "gpt-4o-mini"
        edited.apiKey = "sk-work"
        store.update(edited)
        expect(store.provider(id: openAI.id)?.name == "Work", "Updates should be stored")
        expect(store.provider(id: openAI.id)?.model == "gpt-4o-mini", "Model updates should be stored")
        expect(store.activeProvider.name == "Work", "The active provider should reflect updates")

        store.setActiveProvider(gemini.id)
        expect(store.activeProviderID == gemini.id, "The active provider should be switchable")

        store.setActiveProvider(UUID())
        expect(store.activeProviderID == gemini.id, "Unknown providers should not be activated")

        store.remove(id: duplicate.id)
        expect(store.providers.count == 2, "Providers should be removable")
        expect(store.activeProviderID == gemini.id, "Removing another provider should keep the selection")

        store.remove(id: gemini.id)
        expect(store.providers.count == 1, "Removing the active provider should fall back to the first")
        expect(store.activeProviderID == openAI.id, "The remaining provider should become active")

        store.remove(id: openAI.id)
        expect(store.providers.count == 1, "The last provider should never be removed")

        let reloaded = ProviderStore(defaults: defaults)
        expect(reloaded.providers.count == 1, "Providers should survive a reload")
        expect(reloaded.activeProvider.id == openAI.id, "The active selection should survive a reload")
        expect(reloaded.activeProvider.name == "Work", "Provider edits should survive a reload")
        expect(reloaded.activeProvider.apiKey == "sk-work", "Credentials should survive a reload")

        print("  CRUD ok")
    }
}
