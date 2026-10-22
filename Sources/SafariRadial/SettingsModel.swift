import SwiftUI
import AppKit
import ServiceManagement
import RadialCore

final class SettingsModel: ObservableObject {
    @Published private(set) var preferences: Preferences
    @Published var hotkeyError: String?

    private let environment: AppEnvironment
    private let hotkey: GlobalHotkey
    /// Re-registers the shortcut; the app delegate owns the handler.
    var onHotkeyChange: ((HotkeySpec) -> Bool)?
    /// Fired after any preference change so the radial picks up new settings immediately.
    var onPreferencesChanged: ((Preferences) -> Void)?

    init(environment: AppEnvironment, hotkey: GlobalHotkey) {
        self.environment = environment
        self.hotkey = hotkey
        self.preferences = environment.preferences
    }

    func refresh() {
        preferences = environment.preferences
    }

    var conflict: HotkeyConflicts.Conflict? {
        HotkeyConflicts.conflict(for: preferences.hotkey)
    }

    var suggestedHotkey: HotkeySpec {
        HotkeyConflicts.saferAlternative(to: preferences.hotkey)
    }

    func setHotkey(_ spec: HotkeySpec) {
        guard spec.isValid else {
            hotkeyError = "Include at least one of ⌘, ⌃ or ⌥."
            return
        }
        // Re-selecting the active shortcut is a no-op, not a conflict with ourselves.
        guard spec == preferences.hotkey || hotkey.isAvailable(spec) else {
            hotkeyError = "\(spec.displayName) is already taken by another app."
            return
        }
        let applied = onHotkeyChange?(spec) ?? false
        guard applied else {
            hotkeyError = "Could not register \(spec.displayName)."
            return
        }
        hotkeyError = nil
        mutate { $0.hotkey = spec }
    }

    func setOpenTarget(_ target: Preferences.OpenTarget) {
        mutate { $0.openIn = target }
    }

    func setBackground(_ value: Bool) {
        mutate { $0.openInBackground = value }
    }

    func setAutoSync(_ value: Bool) {
        mutate { $0.autoSyncOnLaunch = value }
    }

    func setShowNumbers(_ value: Bool) {
        mutate { $0.showNumbers = value }
    }

    func setMenuRadius(_ value: Double) {
        mutate { $0.menuRadius = value }
    }

    func setLaunchAtLogin(_ value: Bool) {
        LaunchAtLogin.setEnabled(value)
        mutate { $0.launchAtLogin = value }
    }

    private func mutate(_ block: (inout Preferences) -> Void) {
        environment.updatePreferences(block)
        preferences = environment.preferences
        onPreferencesChanged?(preferences)
    }
}

/// Registering as a login item, without a bundled helper.
enum LaunchAtLogin {
    static func setEnabled(_ enabled: Bool) {
        // SMLoginItemSetEnabled needs a bundled helper, which is overkill here. SMAppService
        // is available on macOS 13+, which is this app's floor.
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    _ = try SMAppServiceRegistrar.register()
                } else {
                    try SMAppServiceRegistrar.unregister()
                }
            } catch {
                NSLog("SafariRadial: login item update failed: \(error.localizedDescription)")
            }
        }
    }
}

/// Thin wrapper so the rest of the code does not import ServiceManagement everywhere.
enum SMAppServiceRegistrar {
    static func register() throws -> Bool {
        if #available(macOS 13.0, *) {
            try SMAppService.mainApp.register()
            return true
        }
        return false
    }

    static func unregister() throws {
        if #available(macOS 13.0, *) {
            try SMAppService.mainApp.unregister()
        }
    }
}
