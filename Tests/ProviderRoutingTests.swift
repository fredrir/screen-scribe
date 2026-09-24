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
    static func main() {
        checkValidation()
        checkPresetsStartWithoutModel()
        checkGeminiEndpoints()
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
            model: "local-model",
            presetID: "lmstudio"
        )
        expect(local.validationIssues.isEmpty,
               "Local OpenAI-compatible endpoints should not require an API key")
        expect(local.effectiveAPIKey == "", "Non-Gemini providers should not borrow the bundled key")

        print("  validation ok")
    }

    /// Models come from the provider, so no preset should pick one up front.
    private static func checkPresetsStartWithoutModel() {
        expect(AIProviderPreset.all.allSatisfy { $0.makeProvider().model.isEmpty },
               "New providers should start without a model")
        expect(AIProviderPreset.all.allSatisfy { $0.makeProvider().presetID == $0.id },
               "New providers should remember their preset")
    }

    private static func checkGeminiEndpoints() {
        expect(Config.geminiEndpoint(for: "gemini-3.7-flash", baseURL: "https://proxy.example.com/")
               == "https://proxy.example.com/v1beta/models/gemini-3.7-flash:generateContent",
               "Custom Gemini base URLs should be supported without doubling slashes")
        expect(Config.geminiEndpoint(for: "gemini-3.7-flash") ==
               "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.7-flash:generateContent",
               "The default Gemini endpoint should be unchanged")
        expect(Config.geminiModelsEndpoint(baseURL: "https://proxy.example.com/")
               == "https://proxy.example.com/v1beta/models",
               "The Gemini model list should sit under the same API root")
    }
}
