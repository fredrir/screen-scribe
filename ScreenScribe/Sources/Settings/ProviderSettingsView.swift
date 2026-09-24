import SwiftUI

@MainActor
struct ProviderSettingsView: View {
    @ObservedObject private var store = ProviderStore.shared
    #if DEBUG
        @ObservedObject private var injectionObserver = InjectionObserver.shared
    #endif

    @State private var models: [String] = []
    @State private var isLoadingModels = false
    @State private var modelError: String?
    @State private var isCustomModelActive: Bool = false
    @State private var testStatus: TestStatus?
    @State private var nameDraft = ""
    @State private var nameDraftProviderID: UUID?
    @FocusState private var isNameFocused: Bool
    @State private var providerPendingDeletion: AIProviderConfiguration?

    private enum TestStatus: Equatable {
        case testing
        case success(String)
        case failure(String)
    }

    private var provider: AIProviderConfiguration { store.activeProvider }

    var body: some View {
        Form {
            Section {
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

                if provider.isCustom {
                    LabeledContent("Name:") {
                        HStack(spacing: 8) {
                            TextField(
                                "Name",
                                text: $nameDraft,
                                prompt: Text(AIProviderPreset.custom.name)
                            )
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .focused($isNameFocused)
                            .onSubmit(commitNameDraft)

                            Button {
                                providerPendingDeletion = provider
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .disabled(store.providers.count <= 1)
                            .help("Delete this endpoint")
                        }
                    }
                }

                if provider.requiresAPIKey {
                    LabeledContent("API Key:") {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                SecureField(
                                    "API Key",
                                    text: stringBinding(for: \.apiKey),
                                    prompt: Text(apiKeyPlaceholder)
                                )
                                .labelsHidden()
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
                } else if provider.isLocal {
                    LabeledContent("API Key:") {
                        HStack {
                            Text("No API key required for local servers.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                    }
                }

                if isLocalOrCustom {
                    LabeledContent("API Endpoint:") {
                        TextField(
                            "Server URL",
                            text: stringBinding(for: \.baseURL),
                            prompt: Text(placeholderBaseURL)
                        )
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                    }

                }

                LabeledContent("Model:") {
                    HStack(spacing: 8) {
                        if !models.isEmpty && !isCustomModelActive {
                            Picker("", selection: modelPickerBinding) {
                                if provider.resolvedModel.isEmpty {
                                    Text("Select a model").tag("")
                                }
                                ForEach(modelOptions, id: \.self) { model in
                                    Text(model).tag(model)
                                }
                                Divider()
                                Text("Custom Model…").tag(Self.customModelTag)
                            }
                            .labelsHidden()
                        } else {
                            TextField("Model identifier", text: stringBinding(for: \.model))
                                .textFieldStyle(.roundedBorder)

                            if !models.isEmpty {
                                Button("Show List") {
                                    isCustomModelActive = false
                                }
                                .buttonStyle(.borderless)
                                .font(.caption)
                            }
                        }

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
                        .disabled(isLoadingModels || !canLoadModels)
                        .help("Reload models from the provider")
                    }
                }

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
        .confirmationDialog(
            "Delete \"\(providerPendingDeletion?.displayName ?? "")\"?",
            isPresented: isConfirmingDeletion,
            presenting: providerPendingDeletion
        ) { pending in
            Button("Delete", role: .destructive) {
                store.remove(id: pending.id)
            }
        } message: { _ in
            Text("Its endpoint URL, API key and model will be removed.")
        }
        .onChange(of: store.activeProviderID) { _, _ in
            commitNameDraft()
            resetModelList()
            testStatus = nil
        }
        .onChange(of: isNameFocused) { _, isFocused in
            if !isFocused { commitNameDraft() }
        }
        .onAppear(perform: loadNameDraft)
        .onDisappear(perform: commitNameDraft)
        .task(id: modelListSource) {
            guard canLoadModels else { return }
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await loadModels()
        }
    }

    private var isTestingConnection: Bool {
        if case .testing = testStatus { return true }
        return false
    }

    private var isLocalOrCustom: Bool {
        provider.isLocal || provider.isCustom
    }

    private var isConfirmingDeletion: Binding<Bool> {
        Binding(
            get: { providerPendingDeletion != nil },
            set: { if !$0 { providerPendingDeletion = nil } }
        )
    }

    private func loadNameDraft() {
        nameDraft = provider.name
        nameDraftProviderID = provider.id
    }

    private func commitNameDraft() {
        if let id = nameDraftProviderID {
            store.rename(id: id, to: nameDraft)
        }
        loadNameDraft()
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
        switch provider.presetID {
        case "openai": return "sk-..."
        case "groq": return "gsk_..."
        default: return "sk-or-..."
        }
    }

    private var customProviders: [AIProviderConfiguration] {
        store.providers.filter(\.isCustom)
    }

    private var providerSelection: Binding<String> {
        Binding<String>(
            get: {
                provider.isCustom ? provider.id.uuidString : provider.presetID
            },
            set: { newSelection in
                if newSelection == "__add_custom__" {
                    let added = store.add(preset: .custom, activate: true)
                    store.setActiveProvider(added.id)
                    resetModelList()
                    return
                }

                if let preset = AIProviderPreset.all.first(where: { $0.id == newSelection }) {
                    if let existing = store.providers.first(where: { $0.presetID == preset.id }) {
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

    private static let customModelTag = "__custom__"

    private var modelOptions: [String] {
        let current = provider.resolvedModel
        guard !current.isEmpty, !models.contains(current) else { return models }
        return models + [current]
    }

    private var modelPickerBinding: Binding<String> {
        Binding<String>(
            get: { provider.resolvedModel },
            set: { newValue in
                if newValue == Self.customModelTag {
                    isCustomModelActive = true
                } else {
                    var updated = provider
                    updated.model = newValue
                    store.update(updated)
                }
            }
        )
    }

    private var canLoadModels: Bool {
        let baseURL =
            provider.resolvedBaseURL.isEmpty
            ? provider.kind.defaultBaseURL : provider.resolvedBaseURL
        let hasKey = !provider.requiresAPIKey || !provider.effectiveAPIKey.isEmpty
        return AIProviderConfiguration.isUsableBaseURL(baseURL) && hasKey
    }

    private var modelListSource: [String] {
        [provider.id.uuidString, provider.resolvedBaseURL, provider.effectiveAPIKey]
    }

    private func resetModelList() {
        models = []
        modelError = nil
        isCustomModelActive = false
    }

    private func loadModels() async {
        let providerID = provider.id
        isLoadingModels = true
        modelError = nil
        defer { isLoadingModels = false }

        do {
            let loaded = try await AIProviderClient().availableModels(for: provider)
            guard !Task.isCancelled, providerID == store.activeProviderID else { return }
            models = loaded
            isCustomModelActive = false
        } catch {
            guard !Task.isCancelled, providerID == store.activeProviderID else { return }
            models = []
            modelError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func testConnection() async {
        testStatus = .testing

        if provider.requiresAPIKey && provider.effectiveAPIKey.isEmpty {
            testStatus = .failure("API key is required.")
            return
        }

        if provider.resolvedBaseURL.isEmpty {
            testStatus = .failure("Server URL is required.")
            return
        }

        if provider.kind == .gemini && !isGeminiKeyWellFormed {
            testStatus = .failure(
                "Invalid key format. Gemini keys start with 'AIza' (39 characters).")
            return
        }

        do {
            let loaded = try await AIProviderClient().availableModels(for: provider)
            models = loaded
            testStatus = .success(
                "Connected! Loaded \(loaded.count) model\(loaded.count == 1 ? "" : "s").")
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
