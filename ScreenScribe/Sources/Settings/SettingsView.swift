import SwiftUI
import Carbon

@MainActor
private final class ShortcutRecorder: ObservableObject {
    @Published var action: ShortcutAction?
    @Published var error: String?
    private var monitor: Any?

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        action = nil
        ShortcutMonitor.shared.suspendForRecording(false)
    }

    func start(_ action: ShortcutAction, save: @escaping (ShortcutMonitor.KeyboardShortcut?) -> String?) {
        stop()
        self.action = action
        error = nil
        ShortcutMonitor.shared.suspendForRecording(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self else { return event }
            guard event.type == .keyDown else {
                self.stop()
                return event
            }
            if event.isARepeat { return nil }
            let shortcut = ShortcutMonitor.KeyboardShortcut(keyCode: Int(event.keyCode), modifiers: event.modifierFlags)
            if shortcut.modifiers.isEmpty && event.keyCode == kVK_Escape {
                self.stop()
            } else if shortcut.modifiers.isEmpty && (event.keyCode == kVK_Delete || event.keyCode == kVK_ForwardDelete) {
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

private struct ShortcutRecorderButton: View {
    let label: String
    let action: ShortcutAction
    let shortcut: ShortcutMonitor.KeyboardShortcut?
    let otherShortcut: ShortcutMonitor.KeyboardShortcut?
    let save: (ShortcutMonitor.KeyboardShortcut?) -> Void
    @ObservedObject var recorder: ShortcutRecorder
    @ObservedObject private var monitor = ShortcutMonitor.shared

    private var isRecording: Bool { recorder.action == action }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
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
                    Text(isRecording ? "Press shortcut…" : (shortcut?.description ?? "Not set"))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityLabel("\(label): \(isRecording ? "recording" : shortcut?.description ?? "not set")")
                Button {
                    recorder.stop()
                    save(nil)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .disabled(shortcut == nil && !isRecording)
                .help("Clear shortcut")
                .accessibilityLabel("Clear \(label)")
            }
            if let error = isRecording ? recorder.error : monitor.registrationErrors[action] {
                Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct SettingsView: View {
    @StateObject private var recorder = ShortcutRecorder()
    @StateObject private var settings = SettingsManager.shared

    var body: some View {
        Form {
            Section {
                ProviderSettingsView()
            } header: {
                Text("API Configuration")
            }

            Section {
                LabeledContent("Text Shortcut:") {
                    ShortcutRecorderButton(
                        label: "Text Shortcut", action: .visionOCR,
                        shortcut: settings.textShortcut, otherShortcut: settings.defaultPromptShortcut,
                        save: { settings.textShortcut = $0 }, recorder: recorder
                    )
                    .frame(width: 200)
                }

                LabeledContent("Default Prompt:") {
                    ShortcutRecorderButton(
                        label: "Default Prompt Shortcut", action: .defaultPrompt,
                        shortcut: settings.defaultPromptShortcut, otherShortcut: settings.textShortcut,
                        save: { settings.defaultPromptShortcut = $0 }, recorder: recorder
                    )
                    .frame(width: 200)
                }
            } header: {
                Text("Keyboard Shortcuts")
            }

            Section {
                PromptListView()
                    .frame(height: 280)
            } header: {
                Text("Prompts")
            }
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 700)
        .onReceive(DistributedNotificationCenter.default().publisher(for: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String))) { _ in
            recorder.objectWillChange.send()
        }
        .onDisappear { recorder.stop() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in recorder.stop() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in recorder.stop() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { _ in recorder.stop() }
    }
}

#Preview {
    SettingsView()
}
