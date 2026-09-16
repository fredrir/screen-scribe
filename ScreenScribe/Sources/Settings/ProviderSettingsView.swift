import SwiftUI

/// Lets the user pick the active provider and edit its endpoint, credentials and model.
@MainActor
struct ProviderSettingsView: View {
    @ObservedObject private var store = ProviderStore.shared

    @State private var models: [ProviderModelOption] = []
    @State private var isLoadingModels = false
    @State private var modelError: String?

    private var provider: AIProviderConfiguration { store.activeProvider }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LabeledContent("Provider:") {
                HStack(spacing: 6) {
                    Picker("", selection: $store.activeProviderID) {
                        ForEach(store.providers) { option in
                            Text(option.displayName).tag(option.id)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 220)

                    Menu {
                        ForEach(AIProviderPreset.all) { preset in
                            Button(preset.name) {
                                _ = store.add(preset: preset)
                                resetModelList()
                            }
                        }
                    } label: {
                        Image(systemName: "plus.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help("Add a provider")

                    Button {
                        store.remove(id: provider.id)
                        resetModelList()
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .disabled(store.providers.count <= 1)
                    .help("Remove this provider")
                }
            }

            LabeledContent("Name:") {
                TextField("Provider name", text: stringBinding(for: \.name))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 330)
            }

            LabeledContent("Type:") {
                Picker("", selection: kindBinding) {
                    ForEach(AIProviderKind.allCases) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                .labelsHidden()
                .frame(width: 330)
            }

            Text(provider.kind.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            LabeledContent("Base URL:") {
                TextField(placeholderBaseURL, text: stringBinding(for: \.baseURL))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 330)
            }

            LabeledContent("API Key:") {
                HStack(spacing: 6) {
                    SecureField(provider.kind.requiresAPIKey ? "Enter your API key" : "Optional", text: stringBinding(for: \.apiKey))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 300)

                    if provider.kind == .gemini, !provider.resolvedAPIKey.isEmpty {
                        Image(systemName: isGeminiKeyWellFormed ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(isGeminiKeyWellFormed ? Color.green : Color.red)
                    }
                }
            }

            Text(apiKeyHint)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            LabeledContent("Model:") {
                HStack(spacing: 6) {
                    TextField("Model identifier", text: stringBinding(for: \.model))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)

                    Button("Load Models") {
                        Task { await loadModels() }
                    }
                    .disabled(isLoadingModels || provider.resolvedBaseURL.isEmpty)

                    if isLoadingModels {
                        ProgressView().controlSize(.small)
                    }
                }
            }

            if !availableModels.isEmpty {
                LabeledContent("Available:") {
                    Picker("", selection: stringBinding(for: \.model)) {
                        ForEach(availableModels) { option in
                            Text(option.label).tag(option.id)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 330)
                }
            }

            if let modelError {
                Text(modelError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !validationIssues.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(validationIssues, id: \.self) { issue in
                        Text(issue)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .onChange(of: store.activeProviderID) { _, _ in resetModelList() }
    }

    private var validationIssues: [String] { provider.validationIssues }

    private var isGeminiKeyWellFormed: Bool {
        let key = provider.resolvedAPIKey
        return key.hasPrefix("AIza") && key.count == 39
    }

    private var placeholderBaseURL: String {
        let fallback = provider.kind.defaultBaseURL
        return fallback.isEmpty ? "https://example.com/v1" : fallback
    }

    private var apiKeyHint: String {
        if provider.kind == .gemini {
            if provider.resolvedAPIKey.isEmpty && !provider.effectiveAPIKey.isEmpty {
                return "Using the API key from Secrets.plist."
            }
            return "Google AI Studio keys start with AIza."
        }
        return "Optional — sent as a Bearer token when set."
    }

    /// Models offered in the picker, keeping the configured model selectable.
    private var availableModels: [ProviderModelOption] {
        let current = provider.resolvedModel
        guard !current.isEmpty, !models.contains(where: { $0.id == current }) else {
            return models
        }
        return [ProviderModelOption(id: current, label: current)] + models
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

    /// Writes edits straight back into the active provider.
    private func binding<Value>(for field: WritableKeyPath<AIProviderConfiguration, Value>) -> Binding<Value> {
        Binding(
            get: { provider[keyPath: field] },
            set: { newValue in
                var updated = provider
                updated[keyPath: field] = newValue
                store.update(updated)
            }
        )
    }

    private func stringBinding(for field: WritableKeyPath<AIProviderConfiguration, String>) -> Binding<String> {
        binding(for: field)
            .trimmed()
    }

    /// Switching type resets the URL to the new type's default and fills in a model if none is set.
    private var kindBinding: Binding<AIProviderKind> {
        Binding(
            get: { provider.kind },
            set: { kind in
                guard kind != provider.kind else { return }
                var updated = provider
                updated.kind = kind
                if updated.resolvedBaseURL.isEmpty || updated.baseURL == provider.kind.defaultBaseURL {
                    updated.baseURL = kind.defaultBaseURL
                }
                if updated.resolvedModel.isEmpty {
                    updated.model = kind.defaultModel
                }
                store.update(updated)
                resetModelList()
            }
        )
    }
}

private extension Binding where Value == String {
    /// Drops whitespace around edits so pasted keys and URLs are stored cleanly.
    func trimmed() -> Binding<String> {
        Binding<String>(
            get: { wrappedValue },
            set: { newValue in
                wrappedValue = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        )
    }
}
