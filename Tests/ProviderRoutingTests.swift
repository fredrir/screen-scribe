import Foundation

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

@main
struct ProviderRoutingTests {
    @MainActor
    static func main() async {
        checkModelResolution()
        checkValidation()
        checkGeminiModelCatalog()

        do {
            try await checkAvailableModels()
        } catch {
            fputs("FAIL: \(error)\n", stderr)
            exit(1)
        }

        print("ProviderRoutingTests passed")
    }

    private static func gemini(model: String) -> AIProviderConfiguration {
        AIProviderConfiguration(
            name: "Gemini",
            kind: .gemini,
            baseURL: Config.defaultGeminiBaseURL,
            apiKey: "AIza-test",
            model: model
        )
    }

    @MainActor
    private static func checkModelResolution() {
        expect(AIProviderClient.resolvedModel(for: gemini(model: "gemini-3.6-flash")) == "gemini-3.7-flash",
               "Retired Gemini models should be migrated")
        expect(AIProviderClient.resolvedModel(for: gemini(model: "")) == Config.defaultGeminiModelID,
               "Providers without a model should fall back to the type default")

        let compatible = AIProviderConfiguration(
            name: "Ollama",
            kind: .openAICompatible,
            baseURL: "http://localhost:11434/v1",
            model: "llama3.2"
        )
        expect(AIProviderClient.resolvedModel(for: compatible) == "llama3.2",
               "OpenAI-compatible models should be passed through untouched")

        print("  model resolution ok")
    }

    @MainActor
    private static func checkValidation() {
        expect(gemini(model: "gemini-3.7-flash").validationIssues.isEmpty,
               "A complete Gemini provider should be valid")

        var keyless = gemini(model: "gemini-3.7-flash")
        keyless.apiKey = ""
        if Config.geminiAPIKey().isEmpty {
            expect(keyless.validationIssues.contains("API key is required."),
                   "Gemini providers without a key should be rejected")
        }

        var unnamed = gemini(model: "gemini-3.7-flash")
        unnamed.name = "   "
        expect(unnamed.validationIssues.contains("Name is required."),
               "Providers should need a name")

        var incompatible = gemini(model: "")
        incompatible.baseURL = "ftp://example.com"
        let issues = incompatible.validationIssues
        expect(issues.contains("Base URL must be an http or https address."),
               "Base URLs must be http or https addresses")
        expect(issues.contains("Model is required."), "Providers should need a model")

        let local = AIProviderConfiguration(
            name: "LM Studio",
            kind: .openAICompatible,
            baseURL: "http://localhost:1234/v1",
            apiKey: "",
            model: "local-model"
        )
        expect(local.validationIssues.isEmpty,
               "Local OpenAI-compatible endpoints should not require an API key")
        expect(local.effectiveAPIKey == "", "Non-Gemini providers should not borrow the bundled key")

        print("  validation ok")
    }

    private static func checkGeminiModelCatalog() {
        expect(Config.availableGeminiModels.contains(where: { $0.id == Config.defaultGeminiModelID }),
               "The default Gemini model should be part of the catalog")
        expect(Config.geminiEndpoint(for: "gemini-3.7-flash", baseURL: "https://proxy.example.com/")
               == "https://proxy.example.com/v1beta/models/gemini-3.7-flash:generateContent",
               "Custom Gemini base URLs should be supported without doubling slashes")
        expect(Config.geminiEndpoint(for: "gemini-3.7-flash") ==
               "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.7-flash:generateContent",
               "The default Gemini endpoint should be unchanged")
    }

    @MainActor
    private static func checkAvailableModels() async throws {
        let models = try await AIProviderClient().availableModels(for: gemini(model: "gemini-3.7-flash"))
        expect(models.map(\.id) == Config.availableGeminiModels.map(\.id),
               "Gemini should offer the bundled model catalog")
        expect(models.allSatisfy { !$0.label.isEmpty }, "Catalog entries should be labelled")

        print("  available models ok")
    }
}
