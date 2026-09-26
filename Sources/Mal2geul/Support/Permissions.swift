import AppKit
import AVFoundation
import Combine
import ServiceManagement

/// Microphone and Accessibility access, plus shortcut clashes. Polled while settings are open.
final class Permissions: ObservableObject {
    static let shared = Permissions()

    @Published private(set) var microphone: AVAuthorizationStatus = .notDetermined
    /// Needed to find the caret and to type into other apps.
    @Published private(set) var accessibility = false
    /// Name of the macOS shortcut that uses the same keys as ours, if any.
    @Published private(set) var shortcutConflict: String?

    private var timer: Timer?

    private init() { refresh() }

    var allGranted: Bool { microphone == .authorized && accessibility }

    func refresh() {
        let microphone = AVCaptureDevice.authorizationStatus(for: .audio)
        if microphone != self.microphone { self.microphone = microphone }
        let accessibility = AXIsProcessTrusted()
        if accessibility != self.accessibility { self.accessibility = accessibility }
        let conflict = SystemShortcuts.conflict(with: Preferences.shared.shortcut)
        if conflict != shortcutConflict { shortcutConflict = conflict }
    }

    func watch(_ enabled: Bool) {
        timer?.invalidate()
        timer = nil
        guard enabled else { return }
        refresh()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func requestMicrophone() {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined else {
            openPrivacySettings("Privacy_Microphone")
            return
        }
        AVCaptureDevice.requestAccess(for: .audio) { _ in
            DispatchQueue.main.async { self.refresh() }
        }
    }

    func requestAccessibility() {
        // The prompt also adds mal2geul to the list, so the user only has to flip the switch.
        Permissions.promptForAccessibility()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            self.openPrivacySettings("Privacy_Accessibility")
        }
    }

    static func promptForAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    private func openPrivacySettings(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// "Open at login", through the system's login item service.
enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    /// Returns a short note for the user when something needs their attention.
    static func setEnabled(_ enabled: Bool) -> String? {
        do {
            if enabled {
                try SMAppService.mainApp.register()
                if SMAppService.mainApp.status == .requiresApproval {
                    SMAppService.openSystemSettingsLoginItems()
                    return "시스템 설정에서 허용해 주세요"
                }
            } else {
                try SMAppService.mainApp.unregister()
            }
            return nil
        } catch {
            Log.info("login item: \(error.localizedDescription)")
            return "설정하지 못했어요"
        }
    }
}
