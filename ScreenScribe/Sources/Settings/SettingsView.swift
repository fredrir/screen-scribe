import Carbon
import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case provider = "Provider"
    case shortcuts = "Shortcuts"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .provider: return "AI Provider"
        case .shortcuts: return "Shortcuts"
        }
    }

    var icon: String {
        switch self {
        case .provider: return "sparkles"
        case .shortcuts: return "command"
        }
    }
}

@MainActor
final class ShortcutRecorder: ObservableObject {
    @Published var action: ShortcutAction?
    @Published var error: String?
    private var monitor: Any?

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        action = nil
        ShortcutMonitor.shared.suspendForRecording(false)
    }

    func start(
        _ action: ShortcutAction, save: @escaping (ShortcutMonitor.KeyboardShortcut?) -> String?
    ) {
        stop()
        self.action = action
        error = nil
        ShortcutMonitor.shared.suspendForRecording(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: [
            .keyDown, .leftMouseDown, .rightMouseDown,
        ]) { [weak self] event in
            guard let self else { return event }
            guard event.type == .keyDown else {
                self.stop()
                return event
            }
            if event.isARepeat { return nil }
            let shortcut = ShortcutMonitor.KeyboardShortcut(
                keyCode: Int(event.keyCode), modifiers: event.modifierFlags)
            if shortcut.modifiers.isEmpty && event.keyCode == kVK_Escape {
                self.stop()
            } else if shortcut.modifiers.isEmpty
                && (event.keyCode == kVK_Delete || event.keyCode == kVK_ForwardDelete)
            {
                self.error = save(nil)
                self.stop()
            } else if let error = shortcut.validationError {
                self.error = error
            } else if let error = save(shortcut) {
                self.error = error
            } else {
                self.stop()
            }
            return nil
        }
    }
}

struct ShortcutRecorderButton: View {
    let label: String
    let action: ShortcutAction
    let shortcut: ShortcutMonitor.KeyboardShortcut?
    let otherShortcut: ShortcutMonitor.KeyboardShortcut?
    let save: (ShortcutMonitor.KeyboardShortcut?) -> Void
    @ObservedObject var recorder: ShortcutRecorder
    @ObservedObject private var monitor = ShortcutMonitor.shared

    private var isRecording: Bool { recorder.action == action }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Button {
                    if isRecording {
                        recorder.stop()
                    } else {
                        recorder.start(action) { candidate in
                            if let candidate, candidate == otherShortcut {
                                return "Shortcut assigned to another action"
                            }
                            save(candidate)
                            return nil
                        }
                    }
                } label: {
                    HStack {
                        if isRecording {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 8, height: 8)
                        }
                        Text(
                            isRecording
                                ? "Press keys…" : (shortcut?.description ?? "Record Shortcut")
                        )
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
                .buttonStyle(.bordered)
                .accessibilityLabel(
                    "\(label): \(isRecording ? "recording" : shortcut?.description ?? "not set")")

                Button {
                    recorder.stop()
                    save(nil)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .disabled(shortcut == nil && !isRecording)
                .help("Clear shortcut")
                .accessibilityLabel("Clear \(label)")
            }

            if let error = isRecording ? recorder.error : monitor.registrationErrors[action] {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct ShortcutsSettingsView: View {
    @ObservedObject var recorder: ShortcutRecorder
    @ObservedObject private var settings = SettingsManager.shared
    @ObservedObject private var providerStore = ProviderStore.shared

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Text Recognition (Vision OCR)")
                                .fontWeight(.medium)
                            Text(
                                "Fast offline OCR using Apple Vision. Extracts plain text directly to clipboard without AI."
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        ShortcutRecorderButton(
                            label: "Text Shortcut", action: .visionOCR,
                            shortcut: settings.textShortcut,
                            otherShortcut: settings.defaultPromptShortcut,
                            save: { settings.textShortcut = $0 }, recorder: recorder
                        )
                        .frame(width: 170)
                    }

                    Divider()

                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Default AI Extraction")
                                .fontWeight(.medium)
                            Text(
                                "Captures a screen region and extracts LaTeX using \(providerStore.activeProvider.displayName)."
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        ShortcutRecorderButton(
                            label: "Default Prompt Shortcut", action: .defaultPrompt,
                            shortcut: settings.defaultPromptShortcut,
                            otherShortcut: settings.textShortcut,
                            save: { settings.defaultPromptShortcut = $0 }, recorder: recorder
                        )
                        .frame(width: 170)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Global Hotkeys")
            }
        }
        .formStyle(.grouped)
    }
}

struct SettingsView: View {
    @StateObject private var recorder = ShortcutRecorder()
    @State private var selectedTab: SettingsTab = .provider

    var body: some View {
        VStack(spacing: 0) {
            // Segmented Tab Picker
            Picker("", selection: $selectedTab) {
                ForEach(SettingsTab.allCases) { tab in
                    Label(tab.title, systemImage: tab.icon).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider()

            // Active Tab Content
            Group {
                switch selectedTab {
                case .provider:
                    ProviderSettingsView()
                case .shortcuts:
                    ShortcutsSettingsView(recorder: recorder)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 520, minHeight: 460)
        .onReceive(
            DistributedNotificationCenter.default().publisher(
                for: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String))
        ) { _ in
            recorder.objectWillChange.send()
        }
        .onDisappear { recorder.stop() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) {
            _ in recorder.stop()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)
        ) { _ in recorder.stop() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { _ in
            recorder.stop()
        }
    }
}

#Preview {
    SettingsView()
}
