import AppKit
import SwiftUI
import RadialCore

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var environment: AppEnvironment!
    private var radialController: RadialController!
    private var hotkey: GlobalHotkey!
    private var listModel: BookmarkListModel!
    private var settingsModel: SettingsModel!
    private var statusItem: NSStatusItem!
    private var managerWindow: NSWindow?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        environment = AppEnvironment()
        hotkey = GlobalHotkey()
        radialController = RadialController(store: environment.store, preferences: environment.preferences)
        listModel = BookmarkListModel(environment: environment)
        settingsModel = SettingsModel(environment: environment, hotkey: hotkey)

        radialController.onEmptyMenu = { [weak self] in
            self?.showManagerWindow()
        }
        settingsModel.onHotkeyChange = { [weak self] spec in
            self?.registerHotkey(spec) ?? false
        }
        settingsModel.onPreferencesChanged = { [weak self] preferences in
            self?.radialController.updatePreferences(preferences)
            self?.statusItem.button?.toolTip = "Safari Radial — \(preferences.hotkey.displayName)"
        }

        registerHotkey(environment.preferences.hotkey)
        setUpStatusItem()

        if environment.preferences.autoSyncOnLaunch {
            // Import silently; failures stay quiet at launch and surface in the window instead.
            _ = environment.syncFromSafari()
            listModel.reload()
        }

        // Nothing in the menu bar on first run would be confusing.
        if environment.store.count == 0 {
            showManagerWindow()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkey.unregister()
    }

    /// The app lives in the menu bar, so closing the last window must not quit it.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    // MARK: - Hotkey

    @discardableResult
    private func registerHotkey(_ spec: HotkeySpec) -> Bool {
        return hotkey.register(spec) { [weak self] in
            guard let self else { return }
            if self.radialController.isOpen {
                self.radialController.hotkeyWhileOpen()
            } else {
                self.radialController.present()
            }
        }
    }

    // MARK: - Status item

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            if let image = NSImage(systemSymbolName: "circle.hexagongrid.fill", accessibilityDescription: "Safari Radial") {
                image.isTemplate = true
                button.image = image
            } else {
                button.title = "◎"
            }
            button.toolTip = "Safari Radial — \(environment.preferences.hotkey.displayName)"
        }

        let menu = NSMenu()
        let openItem = NSMenuItem(title: "Open Radial Menu", action: #selector(openMenuFromMenuBar), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        menu.addItem(.separator())

        let manageItem = NSMenuItem(title: "Bookmarks…", action: #selector(showManagerWindow), keyEquivalent: "b")
        manageItem.target = self
        menu.addItem(manageItem)

        let syncItem = NSMenuItem(title: "Import from Safari", action: #selector(syncNow), keyEquivalent: "r")
        syncItem.target = self
        menu.addItem(syncItem)

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(showSettingsWindow), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let safariItem = NSMenuItem(title: "Edit Safari Bookmarks…", action: #selector(openSafariBookmarks), keyEquivalent: "")
        safariItem.target = self
        menu.addItem(safariItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Safari Radial", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc private func openMenuFromMenuBar() {
        radialController.present()
    }

    @objc private func syncNow() {
        listModel.syncFromSafari()
    }

    @objc private func openSafariBookmarks() {
        SafariLauncher.revealSafariBookmarks()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Windows

    @objc private func showManagerWindow() {
        if let managerWindow {
            managerWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            listModel.reload()
            return
        }

        let view = BookmarkManagerView(model: listModel, settings: settingsModel)
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Safari Radial"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 820, height: 620))
        window.center()
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(calibratedRed: 0.074, green: 0.078, blue: 0.094, alpha: 1)
        window.delegate = self
        managerWindow = window

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func showSettingsWindow() {
        if let settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            settingsModel.refresh()
            return
        }

        settingsModel.refresh()
        let view = SettingsView(model: settingsModel)
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        window.backgroundColor = NSColor(calibratedRed: 0.074, green: 0.078, blue: 0.094, alpha: 1)
        window.delegate = self
        settingsWindow = window

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        // Keep the window objects around: rebuilding SwiftUI state on each open is jarring.
        if let window = notification.object as? NSWindow, window === managerWindow {
            listModel.syncMessage = nil
        }
    }
}
