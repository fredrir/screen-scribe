import Foundation
import Carbon
import SwiftUI

@MainActor
final class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    @Published var textShortcut: ShortcutMonitor.KeyboardShortcut? {
        didSet {
            ShortcutPreferences.save(textShortcut, forKey: "textShortcut", defaults: .standard)
            ShortcutMonitor.shared.setShortcut(textShortcut, for: .visionOCR)
        }
    }

    @Published var defaultPromptShortcut: ShortcutMonitor.KeyboardShortcut? {
        didSet {
            ShortcutPreferences.save(defaultPromptShortcut, forKey: "defaultPromptShortcut", defaults: .standard)
            ShortcutMonitor.shared.setShortcut(defaultPromptShortcut, for: .defaultPrompt)
        }
    }

    @Published var selectedModel: String {
        didSet {
            UserDefaults.standard.set(selectedModel, forKey: "geminiModel")
        }
    }

    private init() {
        textShortcut = ShortcutPreferences.load(forKey: "textShortcut", defaultKeyCode: kVK_ANSI_T)
        defaultPromptShortcut = ShortcutPreferences.load(forKey: "defaultPromptShortcut", defaultKeyCode: kVK_ANSI_L, legacyKey: "latexShortcut")

        let storedModel = UserDefaults.standard.string(forKey: "geminiModel")
        let resolvedModel = Config.resolvedGeminiModelID(from: storedModel)
        selectedModel = resolvedModel
        if let migratedModel = Config.persistedGeminiModelMigration(from: storedModel) {
            UserDefaults.standard.set(migratedModel, forKey: "geminiModel")
        }

        ShortcutMonitor.shared.setShortcut(textShortcut, for: .visionOCR)
        ShortcutMonitor.shared.setShortcut(defaultPromptShortcut, for: .defaultPrompt)
    }
}

// A stored JSON null means deliberately unassigned; a missing key means first launch.
struct ShortcutPreferences {
    static func save(_ shortcut: ShortcutMonitor.KeyboardShortcut?, forKey key: String, defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(shortcut) else { return }
        defaults.set(data, forKey: key)
    }

    static func load(forKey key: String, defaultKeyCode: Int, legacyKey: String? = nil,
                     defaults: UserDefaults = .standard) -> ShortcutMonitor.KeyboardShortcut? {
        if let data = defaults.data(forKey: key) {
            do {
                return try JSONDecoder().decode(ShortcutMonitor.KeyboardShortcut?.self, from: data)
            } catch {
                // Recover malformed preferences with the default below.
            }
        }
        if defaults.object(forKey: key) == nil, let legacyKey,
           let data = defaults.data(forKey: legacyKey),
           let legacy = try? JSONDecoder().decode(ShortcutMonitor.KeyboardShortcut.self, from: data) {
            save(legacy, forKey: key, defaults: defaults)
            defaults.removeObject(forKey: legacyKey)
            return legacy
        }
        return ShortcutMonitor.KeyboardShortcut(keyCode: defaultKeyCode, modifiers: .command)
    }
}
