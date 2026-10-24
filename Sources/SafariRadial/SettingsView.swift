import SwiftUI
import RadialCore

/// Settings. The shortcut is the first thing here because it is the only thing most people
/// will ever change: everything else already behaves sensibly out of the box.
struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    @State private var isRecording = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Rectangle().fill(Palette.rim).frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    shortcutSection
                    openingSection
                    dialSection
                    safariSection
                    aboutSection
                }
                .padding(24)
            }
        }
        .background(Palette.void)
        .frame(width: 460, height: 600)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Settings")
                .font(Palette.display(17, .semibold))
                .foregroundStyle(Palette.bone)
            Spacer()
            Text("Safari Radial")
                .font(Palette.mono(10))
                .foregroundStyle(Palette.boneFaint)
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    // MARK: - Shortcut

    private var shortcutSection: some View {
        section("Shortcut") {
            HStack(spacing: 10) {
                // The recorder is the control itself: click it and press the new keys.
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Palette.hull)
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(
                                    isRecording ? Palette.signal : Palette.rim,
                                    lineWidth: isRecording ? 1.5 : 1
                                )
                        )

                    if isRecording {
                        HotkeyRecorder(
                            isRecording: $isRecording,
                            current: model.preferences.hotkey,
                            onCapture: { spec in model.setHotkey(spec) }
                        )
                    } else {
                        Text(model.preferences.hotkey.displayName)
                            .font(Palette.mono(13, .semibold))
                            .foregroundStyle(Palette.bone)
                    }
                }
                .frame(width: 132, height: 32)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.spring(response: 0.24, dampingFraction: 0.76)) {
                        isRecording = true
                    }
                }
                .help("Click, then press the keys you want")

                Button(isRecording ? "Cancel" : "Change") {
                    withAnimation(.spring(response: 0.24, dampingFraction: 0.76)) {
                        isRecording.toggle()
                    }
                }
                .buttonStyle(QuietButtonStyle())

                Spacer()

                Button("Reset to ⌘E") {
                    model.setHotkey(.default)
                }
                .buttonStyle(QuietButtonStyle(tint: Palette.boneDim))
                .disabled(model.preferences.hotkey == .default)
            }

            if let error = model.hotkeyError {
                notice(error, tone: .bad, icon: "exclamationmark.triangle.fill")
            } else if let conflict = model.conflict {
                // A system-wide hot key wins over the frontmost app, so a collision is a real
                // trade-off, not a bug. Major collisions get a warning and a one-click fix.
                notice(
                    "\(model.preferences.hotkey.displayName) \(conflict.description) in \(conflict.owner).",
                    tone: conflict.severity == .major ? .warn : .quiet,
                    icon: conflict.severity == .major ? "exclamationmark.triangle.fill" : "info.circle"
                )
                HStack(spacing: 6) {
                    Button("Use \(model.suggestedHotkey.displayName)") {
                        model.setHotkey(model.suggestedHotkey)
                    }
                    .buttonStyle(QuietButtonStyle(tint: Palette.signal))
                    Text("avoids the clash")
                        .font(Palette.display(10.5, .regular))
                        .foregroundStyle(Palette.boneFaint)
                }
            } else {
                Text("Works anywhere. Press it again to close the dial.")
                    .font(Palette.display(10.5, .regular))
                    .foregroundStyle(Palette.boneFaint)
            }
        }
    }

    // MARK: - Opening

    private var openingSection: some View {
        section("Opening links") {
            // The browser first, because it decides which tab targets are even possible.
            HStack(spacing: 10) {
                Text("Open in")
                    .font(Palette.display(12, .regular))
                    .foregroundStyle(Palette.bone)
                    .frame(width: 62, alignment: .leading)
                Picker("", selection: Binding(
                    get: { model.preferences.browserBundleID },
                    set: { bundleID in
                        model.setBrowser(Browser.browser(forBundleID: bundleID))
                    }
                )) {
                    ForEach(model.installedBrowsers) { browser in
                        Text(browser.name).tag(browser.bundleID)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text(openSummary)
                .font(Palette.display(10.5, .regular))
                .foregroundStyle(Palette.boneFaint)
                .fixedSize(horizontal: false, vertical: true)

            Picker("", selection: Binding(
                get: { model.preferences.openIn },
                set: { model.setOpenTarget($0) }
            )) {
                ForEach(Preferences.OpenTarget.allCases, id: \.self) { target in
                    Text(target.displayName).tag(target)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if model.preferences.openIn != .newTab && model.targetIsHonoured {
                Text("Uses AppleScript, so macOS asks once for permission to control \(model.preferences.browser.name). Falls back to a new tab if denied.")
                    .font(Palette.display(10.5, .regular))
                    .foregroundStyle(Palette.boneFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }

            toggle("Open in the background", isOn: model.preferences.openInBackground, action: model.setBackground)
            toggle("Start at login", isOn: model.preferences.launchAtLogin, action: model.setLaunchAtLogin)
        }
    }

    /// One sentence describing exactly what will happen, naming the browser.
    ///
    /// Built from the same `OpenPlan` the launcher uses, so the promise and the behaviour
    /// cannot drift. It is also where an unscriptable browser is admitted: the description
    /// says "opens in a new tab in Firefox" rather than promising a target that browser
    /// cannot be asked for.
    private var openSummary: String {
        OpenPlan.description(for: model.preferences.openIn, in: model.preferences.browser)
            + (model.preferences.openInBackground ? ", in the background." : ".")
    }

    // MARK: - Dial

    private var dialSection: some View {
        section("The dial") {
            toggle("Print slot numbers inside the dial", isOn: model.preferences.showNumbers, action: model.setShowNumbers)

            HStack(spacing: 10) {
                Text("Size")
                    .font(Palette.display(12, .regular))
                    .foregroundStyle(Palette.bone)
                Slider(
                    value: Binding(
                        get: { model.preferences.menuRadius },
                        set: { model.setMenuRadius($0) }
                    ),
                    in: 140...320
                )
                Text("\(Int(model.preferences.menuRadius))")
                    .font(Palette.mono(10.5))
                    .foregroundStyle(Palette.boneDim)
                    .frame(width: 28, alignment: .trailing)
                    .monospacedDigit()
            }
        }
    }

    // MARK: - Safari

    private var safariSection: some View {
        section("Safari import") {
            HStack(spacing: 7) {
                Circle()
                    .fill(model.hasFullDiskAccess ? Palette.mint : Palette.boneFaint)
                    .frame(width: 6, height: 6)
                Text(model.hasFullDiskAccess ? "Full Disk Access granted" : "Full Disk Access not granted")
                    .font(Palette.display(12, .medium))
                    .foregroundStyle(Palette.bone)
            }

            Text("Optional. Only the Safari import needs it. Adding links by hand, reordering, the shortcut and every setting work without it.")
                .font(Palette.display(10.5, .regular))
                .foregroundStyle(Palette.boneFaint)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button("Open Full Disk Access") { model.openFullDiskAccessSettings() }
                    .buttonStyle(QuietButtonStyle())
                Button("Import now") { model.syncFromSafari() }
                    .buttonStyle(QuietButtonStyle())
                    .disabled(!model.hasFullDiskAccess)
            }

            toggle("Refresh from Safari at launch", isOn: model.preferences.autoSyncOnLaunch, action: model.setAutoSync)
                .disabled(!model.hasFullDiskAccess)
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        section("How the dial works") {
            Text("Nine slots per page. Press 1–9 to open one, ← → to change page, Esc to close.")
                .font(Palette.display(10.5, .regular))
                .foregroundStyle(Palette.boneFaint)
                .fixedSize(horizontal: false, vertical: true)
            Text("Bookmarks live in ~/Library/Application Support/SafariRadial")
                .font(Palette.mono(9.5))
                .foregroundStyle(Palette.boneFaint)
                .textSelection(.enabled)
        }
    }

    // MARK: - Pieces

    private enum NoticeTone { case bad, warn, quiet }

    private func notice(_ text: String, tone: NoticeTone, icon: String) -> some View {
        let colour: Color
        switch tone {
        case .bad: colour = Palette.alarm
        case .warn: colour = Palette.signal
        case .quiet: colour = Palette.boneDim
        }
        return HStack(alignment: .top, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .padding(.top, 1)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(Palette.display(10.5, .medium))
        .foregroundStyle(colour)
    }

    private func toggle(_ label: String, isOn: Bool, action: @escaping (Bool) -> Void) -> some View {
        Toggle(label, isOn: Binding(get: { isOn }, set: action))
            .toggleStyle(.switch)
            .controlSize(.small)
            .font(Palette.display(12, .regular))
            .foregroundStyle(Palette.bone)
    }

    private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(Palette.display(11.5, .semibold))
                .foregroundStyle(Palette.bone.opacity(0.85))
            content()
        }
    }
}
