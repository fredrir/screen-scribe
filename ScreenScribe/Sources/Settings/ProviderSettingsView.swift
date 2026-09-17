import SwiftUI

/// Lets the user configure the active AI provider, credentials, and model in a clean, responsive layout.
@MainActor
struct ProviderSettingsView: View {
    @ObservedObject private var store = ProviderStore.shared

    @State private var models: [ProviderModelOption] = []
    @State private var isLoadingModels = false
    @State private var modelError: String?
    @State private var isCustomModelActive: Bool = false
    @State private var testStatus: TestStatus?

    private enum TestStatus: Equatable {
        case testing
        case success(String)
        case failure(String)
    }

    private var provider: AIProviderConfiguration { store.activeProvider }

    var body: some View {
        Form {
            Section {
                // Unified Provider Selection
                LabeledContent("Provider:") {
                    Picker("", selection: providerSelection) {
                        Section("Cloud Services") {
                            Text("Google Gemini").tag("gemini")
                            Text("OpenAI").tag("openai")
                            Text("OpenRouter").tag("openrouter")
                            Text("Groq").tag("groq")
                        }
                        Section("Local AI") {
                            Text("Ollama (Local)").tag("ollama")
                            Text("LM Studio (Local)").tag("lmstudio")
                        }
                        Section("Custom") {
                            ForEach(customProviders) { cp in
                                Text(cp.displayName).tag(cp.id.uuidString)
                            }
                            Text("+ Add Custom Provider…").tag("__add_custom__")
                        }
                    }
                    .labelsHidden()
                }

                // API Key
                if provider.kind.requiresAPIKey {
                    LabeledContent("API Key:") {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                SecureField(apiKeyPlaceholder, text: stringBinding(for: \.apiKey))
                                    .textFieldStyle(.roundedBorder)

                                if provider.kind == .gemini, !provider.resolvedAPIKey.isEmpty {
                                    Image(
                                        systemName: isGeminiKeyWellFormed
                                            ? "checkmark.circle.fill"
                                            : "exclamationmark.circle.fill"
                                    )
                                    .foregroundStyle(
                                        isGeminiKeyWellFormed ? Color.green : Color.orange
                                    )
                                    .help(
                                        isGeminiKeyWellFormed
                                            ? "API key format is valid"
                                            : "Expected 39 characters starting with AIza")
                                }

                                if let url = provider.matchingPreset?.websiteURL {
                                    Link("Get Key ↗", destination: url)
                                        .font(.caption)
                                        .buttonStyle(.link)
                                        .help("Open developer portal to get an API key")
                                }
                            }

                            if provider.kind == .gemini {
                                if provider.resolvedAPIKey.isEmpty
                                    && !provider.effectiveAPIKey.isEmpty
                                {
                                    Text("Using API key from Secrets.plist")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else if !provider.resolvedAPIKey.isEmpty && !isGeminiKeyWellFormed
                                {
                                    Text(
                                        "Google AI Studio keys typically start with 'AIza' (39 characters)."
                                    )
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                                }
                            }
                        }
                    }
                } else if provider.matchingPreset?.isLocal == true {
                    LabeledContent("API Key:") {
                        HStack {
                            Text("No API key required for local servers.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                    }
                }

                // Server URL
                if isLocalOrCustom {

                    TextField(placeholderBaseURL, text: stringBinding(for: \.baseURL))
                        .textFieldStyle(.roundedBorder)

                }

                // Model Selection
                LabeledContent("Model:") {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            if !availableModelOptions.isEmpty && !isCustomModelActive {
                                Picker("", selection: modelPickerBinding) {
                                    ForEach(availableModelOptions) { option in
                                        Text(option.label).tag(option.id)
                                    }
                                    Divider()
                                    Text("Custom Model…").tag("__custom__")
                                }
                                .labelsHidden()
                            } else {
                                TextField("Model identifier", text: stringBinding(for: \.model))
                                    .textFieldStyle(.roundedBorder)

                                if !availableModelOptions.isEmpty {
                                    Button("Presets") {
                                        isCustomModelActive = false
                                        if let first = availableModelOptions.first?.id {
                                            var updated = provider
                                            updated.model = first
                                            store.update(updated)
                                        }
                                    }
                                    .buttonStyle(.borderless)
                                    .font(.caption)
                                }
                            }

                            // Refresh button to fetch models from server
                            Button {
                                Task { await loadModels() }
                            } label: {
                                if isLoadingModels {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Image(systemName: "arrow.clockwise")
                                }
                            }
                            .buttonStyle(.borderless)
                            .disabled(isLoadingModels || provider.resolvedBaseURL.isEmpty)
                            .help("Fetch models from server")
                        }

                        if isCustomModelActive {
                            TextField(
                                "Enter custom model identifier", text: stringBinding(for: \.model)
                            )
                            .textFieldStyle(.roundedBorder)
                        }
                    }
                }

                // MARK: - 5. Test Connection & Feedback
                HStack(spacing: 12) {
                    Button {
                        Task { await testConnection() }
                    } label: {
                        HStack(spacing: 4) {
                            if case .testing = testStatus {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "bolt.badge.checkmark")
                            }
                            Text("Test Connection")
                        }
                    }
                    .disabled(isLoadingModels || (testStatus != nil && isTestingConnection))

                    if let status = testStatus {
                        switch status {
                        case .testing:
                            Text("Connecting…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        case .success(let message):
                            Label(message, systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                        case .failure(let message):
                            Label(message, systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.red)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Spacer()
                }
                .padding(.top, 4)

                if let modelError {
                    HStack {
                        Label(modelError, systemImage: "exclamationmark.circle")
                            .font(.caption)
                            .foregroundStyle(.red)
                        Spacer()
                        Button("Dismiss") {
                            self.modelError = nil
                        }
                        .buttonStyle(.borderless)
                        .font(.caption2)
                    }
                }
            } header: {
                Text("Configuration")
            }
        }
        .formStyle(.grouped)
        .onChange(of: store.activeProviderID) { _, _ in
            resetModelList()
            testStatus = nil
            syncCustomModelState()
        }
        .onAppear {
            syncCustomModelState()
        }
    }

    // MARK: - Helpers

    private var isTestingConnection: Bool {
        if case .testing = testStatus { return true }
        return false
    }

    private var isLocalOrCustom: Bool {
        provider.matchingPreset?.isLocal == true || provider.matchingPreset == nil
            || provider.matchingPreset?.id == "custom"
    }

    private var isGeminiKeyWellFormed: Bool {
        let key = provider.resolvedAPIKey
        return key.hasPrefix("AIza") && key.count == 39
    }

    private var placeholderBaseURL: String {
        let fallback = provider.kind.defaultBaseURL
        return fallback.isEmpty ? "https://example.com/v1" : fallback
    }

    private var apiKeyPlaceholder: String {
        if provider.kind == .gemini {
            return "AIzaSy..."
        }
        if provider.name.lowercased().contains("openai") {
            return "sk-..."
        }
        if provider.name.lowercased().contains("groq") {
            return "gsk_..."
        }
        if provider.name.lowercased().contains("openrouter") {
            return "sk-or-..."
        }
        return "Enter your API key"
    }

    private var customProviders: [AIProviderConfiguration] {
        store.providers.filter { p in
            guard let match = p.matchingPreset else { return true }
            return match.id == "custom" || p.name != match.name
        }
    }

    private var providerSelection: Binding<String> {
        Binding<String>(
            get: {
                if let preset = provider.matchingPreset, provider.name == preset.name {
                    return preset.id
                }
                return provider.id.uuidString
            },
            set: { newSelection in
                if newSelection == "__add_custom__" {
                    let custom = AIProviderConfiguration(
                        name: "Custom Endpoint",
                        kind: .openAICompatible,
                        baseURL: "https://api.example.com/v1",
                        apiKey: "",
                        model: "default"
                    )
                    let added = store.add(custom, activate: true)
                    store.setActiveProvider(added.id)
                    resetModelList()
                    return
                }

                if let preset = AIProviderPreset.all.first(where: { $0.id == newSelection }) {
                    if let existing = store.providers.first(where: {
                        $0.matchingPreset?.id == preset.id && $0.name == preset.name
                    }) {
                        store.setActiveProvider(existing.id)
                    } else {
                        let created = store.add(preset: preset, activate: true)
                        store.setActiveProvider(created.id)
                    }
                } else if let uuid = UUID(uuidString: newSelection) {
                    store.setActiveProvider(uuid)
                }
                resetModelList()
            }
        )
    }

    private var availableModelOptions: [ProviderModelOption] {
        var options: [ProviderModelOption] = []
        if let preset = provider.matchingPreset {
            options.append(contentsOf: preset.suggestedModels)
        }
        for m in models {
            if !options.contains(where: { $0.id == m.id }) {
                options.append(m)
            }
        }
        let current = provider.resolvedModel
        if !current.isEmpty && !options.contains(where: { $0.id == current })
            && !isCustomModelActive
        {
            options.append(ProviderModelOption(id: current, label: current))
        }
        return options
    }

    private var modelPickerBinding: Binding<String> {
        Binding<String>(
            get: {
                if isCustomModelActive { return "__custom__" }
                let current = provider.resolvedModel
                if availableModelOptions.contains(where: { $0.id == current }) {
                    return current
                }
                return "__custom__"
            },
            set: { newValue in
                if newValue == "__custom__" {
                    isCustomModelActive = true
                } else {
                    isCustomModelActive = false
                    var updated = provider
                    updated.model = newValue
                    store.update(updated)
                }
            }
        )
    }

    private func syncCustomModelState() {
        let current = provider.resolvedModel
        if availableModelOptions.isEmpty {
            isCustomModelActive = true
        } else if !current.isEmpty && !availableModelOptions.contains(where: { $0.id == current }) {
            isCustomModelActive = true
        } else {
            isCustomModelActive = false
        }
    }

    private func resetModelList() {
        models = []
        modelError = nil
    }

    private func loadModels() async {
        isLoadingModels = true
        modelError = nil
        defer { isLoadingModels = false }

        do {
            let loaded = try await AIProviderClient().availableModels(for: provider)
            guard provider.id == store.activeProviderID else { return }
            models = loaded
        } catch {
            guard provider.id == store.activeProviderID else { return }
            models = []
            modelError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func testConnection() async {
        testStatus = .testing

        if provider.kind.requiresAPIKey && provider.effectiveAPIKey.isEmpty {
            testStatus = .failure("API key is required.")
            return
        }

        if provider.resolvedBaseURL.isEmpty {
            testStatus = .failure("Server URL is required.")
            return
        }

        do {
            if provider.kind == .gemini {
                if !isGeminiKeyWellFormed {
                    testStatus = .failure(
                        "Invalid key format. Gemini keys start with 'AIza' (39 characters).")
                    return
                }
                testStatus = .success("Key format verified. Ready for requests!")
            } else {
                let loaded = try await AIProviderClient().availableModels(for: provider)
                models = loaded
                testStatus = .success(
                    "Connected! Loaded \(loaded.count) model\(loaded.count == 1 ? "" : "s").")
            }
        } catch {
            let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            testStatus = .failure(msg)
        }
    }

    private func binding<Value>(for field: WritableKeyPath<AIProviderConfiguration, Value>)
        -> Binding<Value>
    {
        Binding(
            get: { provider[keyPath: field] },
            set: { newValue in
                var updated = provider
                updated[keyPath: field] = newValue
                store.update(updated)
            }
        )
    }

    private func stringBinding(for field: WritableKeyPath<AIProviderConfiguration, String>)
        -> Binding<String>
    {
        binding(for: field)
            .trimmed()
    }
}

extension Binding where Value == String {
    fileprivate func trimmed() -> Binding<String> {
        Binding<String>(
            get: { wrappedValue },
            set: { newValue in
                wrappedValue = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        )
    }
}
