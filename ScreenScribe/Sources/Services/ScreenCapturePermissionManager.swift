import Foundation
import CoreGraphics
import AppKit
import Combine
import ScreenCaptureKit

@MainActor
final class ScreenCapturePermissionManager: ObservableObject {
    static let shared = ScreenCapturePermissionManager()

    @Published private(set) var hasPermission: Bool = false

    private let preflight: () -> Bool
    private let requestAccess: () async throws -> Void
    private var permissionCheckTimer: Timer?
    private var isRequesting = false

    init(
        preflight: @escaping () -> Bool = { CGPreflightScreenCaptureAccess() },
        requestAccess: @escaping () async throws -> Void = {
            _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        }
    ) {
        self.preflight = preflight
        self.requestAccess = requestAccess
        hasPermission = preflight()
    }

    /// Only preflight is safe to call without a user-initiated access request.
    func startMonitoringWithoutPrompt() async {
        if !checkPermission() {
            startPolling()
        }
    }

    /// ScreenCaptureKit may show the system prompt. Never call it from polling.
    @discardableResult
    func requestPermissionInteractively() async -> Bool {
        guard !isRequesting else { return false }
        if checkPermission() { return true }

        isRequesting = true
        defer { isRequesting = false }
        do {
            try await requestAccess()
            hasPermission = true
            stopPolling()
            return true
        } catch {
            Logger.log(.error, "Screen capture access request failed: \(error.localizedDescription)")
            // Access may have changed while the request was in flight.
            if checkPermission() { return true }
            startPolling()
            return false
        }
    }

    /// Read the current system status, including permission revoked in Settings.
    func checkPermission() -> Bool {
        hasPermission = preflight()
        if hasPermission {
            stopPolling()
        }
        return hasPermission
    }

    private func startPolling() {
        guard permissionCheckTimer == nil else { return }
        permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                _ = self?.checkPermission()
            }
        }
    }

    func stopPolling() {
        permissionCheckTimer?.invalidate()
        permissionCheckTimer = nil
    }

    func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}
