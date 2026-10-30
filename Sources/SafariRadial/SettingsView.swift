import SwiftUI
import RadialCore

/// Settings, as a tab of the manager window rather than a window of their own.
///
/// The shortcut is first because it is the only thing most people will ever change: everything
/// else already behaves sensibly out of the box.
struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    var onOpenImport: () -> Void = {}

    @State private var isRecording = false
    @State private var recorderHover = false

    var body: some View {
        HStack(alignment: .top, spacing: 44) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("PREFERENCES")
                        .font(Palette.mono(11, .semibold))
                        .tracking(1.8)
                        .foregroundStyle(Palette.boneFaint)
                    Text("Settings")
                        .font(Palette.display(46, .semibold))
                        .tracking(-0.8)
                        .foregroundStyle(Palette.bone)
                        .padding(.bottom, 12)

                    shortcutCard
                    openingCard
                    dialCard
                    startupCard
                    aboutLine
                }
                .padding(.bottom, 80)
            }
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.02),
                        .init(color: .black, location: 0.92),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            preview
                .frame(width: 320)
        }
        .padding(.leading, 56)
        .padding(.trailing, 44)
        .onAppear { model.refresh() }
    }

    // MARK: - Preview

    /// Size feedback while you drag. Phase 3 swaps the mini-dial for the live compass.
    private var preview: some View {
        let radius = model.preferences.menuRadius
        let side = 180 + (radius - 140) / 180 * 120
        return VStack(spacing: 18) {
            MiniDial()
                .frame(width: CGFloat(side), height: CGFloat(side))
                .shadow(color: Color.black.opacity(0.5), radius: 18, y: 12)
                .motion(Motion.springSoft, value: Int(radius))
            Text("LIVE PREVIEW")
                .font(Palette.mono(11, .semibold))
                .tracking(1.8)
                .foregroundStyle(Palette.boneFaint)
        }
        .frame(maxWidth: .infinity, minHeight: 420)
        .padding(.top, 60)
    }

    // MARK: - Shortcut

    private var shortcutCard: some View {
        card("Shortcut") {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Open the dial")
                        .font(Palette.display(17, .regular))
                        .foregroundStyle(Palette.bone)
                    Text("Works anywhere. Press it again to close.")
                        .font(Palette.display(13.5, .regular))
                        .foregroundStyle(Palette.boneDim)
                }
                Spacer(minLength: 12)
                recorder
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
                HStack(spacing: 10) {
                    Button("Use \(model.suggestedHotkey.displayName)") {
                        model.setHotkey(model.suggestedHotkey)
                    }
                    .buttonStyle(QuietButtonStyle(tint: Palette.signal, size: 13))
                    Text("avoids the clash")
                        .font(Palette.display(13, .regular))
                        .foregroundStyle(Palette.boneFaint)
                }
            }

            if model.preferences.hotkey != .default {
                Button("Reset to ⌘E") { model.setHotkey(.default) }
                    .buttonStyle(QuietButtonStyle(tint: Palette.boneDim, size: 13))
            }
        }
    }

    /// The recorder is the control itself: click it and press the new keys.
    private var recorder: some View {
        let shape = RoundedRectangle(cornerRadius: 11, style: .continuous)
        return ZStack {
            shape.fill(Palette.void)
            shape.strokeBorder(isRecording ? Palette.signal : Palette.rim, lineWidth: isRecording ? 1.5 : 1)

            if isRecording {
                HotkeyRecorder(
                    isRecording: $isRecording,
                    current: model.preferences.hotkey,
                    onCapture: { spec in model.setHotkey(spec) }
                )
            } else {
                Text(model.preferences.hotkey.displayName)
                    .font(Palette.mono(16, .semibold))
                    .foregroundStyle(Palette.bone)
            }
        }
        .frame(width: 140, height: 44)
        .shadow(color: Palette.signal.opacity(isRecording ? 0.35 : 0), radius: 14)
        .scaleEffect(recorderHover ? 1.04 : 1)
        .contentShape(Rectangle())
        .onHover { recorderHover = $0 }
        .onTapGesture {
            withAnimation(Motion.spring) { isRecording = true }
        }
        .motion(Motion.snap, value: recorderHover)
        .help("Click, then press the keys you want")
    }

    // MARK: - Opening

    private var openingCard: some View {
        card("Opening links") {
            HStack(spacing: 16) {
                Text("Open in")
                    .font(Palette.display(17, .regular))
                    .foregroundStyle(Palette.bone)
                Spacer(minLength: 12)
                Picker("", selection: Binding(
                    get: { model.preferences.browserBundleID },
                    set: { bundleID in model.setBrowser(Browser.browser(forBundleID: bundleID)) }
                )) {
                    ForEach(model.installedBrowsers) { browser in
                        Text(browser.name).tag(browser.bundleID)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()
            }

            BrassSegmented(
                options: Preferences.OpenTarget.allCases,
                title: { $0.displayName },
                selection: Binding(
                    get: { model.preferences.openIn },
                    set: { model.setOpenTarget($0) }
                )
            )

            Text(openSummary)
                .font(Palette.display(13.5, .regular))
                .foregroundStyle(Palette.boneDim)
                .fixedSize(horizontal: false, vertical: true)

            if model.preferences.openIn != .newTab && model.targetIsHonoured {
                Text("Uses AppleScript, so macOS asks once for permission to control \(model.preferences.browser.name). Falls back to a new tab if denied.")
                    .font(Palette.display(13, .regular))
                    .foregroundStyle(Palette.boneFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }

            toggle(
                "Keep the current tab focused",
                detail: "Open links in the background.",
                isOn: model.preferences.openInBackground,
                action: model.setBackground
            )
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

    private var dialCard: some View {
        card("The dial") {
            HStack(spacing: 16) {
                Text("Size")
                    .font(Palette.display(17, .regular))
                    .foregroundStyle(Palette.bone)
                Spacer(minLength: 12)
                BrassSlider(
                    value: Binding(
                        get: { model.preferences.menuRadius },
                        set: { model.setMenuRadius($0) }
                    ),
                    range: 140...320
                )
                .frame(width: 220)
                Text("\(Int(model.preferences.menuRadius))")
                    .font(Palette.mono(14))
                    .foregroundStyle(Palette.boneDim)
                    .frame(width: 36, alignment: .trailing)
                    .monospacedDigit()
            }
            // The compass needs far more room than the old flat dial did, so the slider is an
            // upper bound rather than a promise. Saying so is better than silently shrinking the
            // instrument on the screens that cannot fit it.
            Text("The open compass is tall. On smaller screens it opens a little smaller than this.")
                .font(Palette.display(13, .regular))
                .foregroundStyle(Palette.boneFaint)
                .fixedSize(horizontal: false, vertical: true)

            toggle(
                "Print slot numbers",
                detail: "Inside each wedge of the dial.",
                isOn: model.preferences.showNumbers,
                action: model.setShowNumbers
            )
        }
    }

    // MARK: - Startup

    private var startupCard: some View {
        card("Startup & Safari") {
            toggle("Start at login", detail: nil, isOn: model.preferences.launchAtLogin, action: model.setLaunchAtLogin)

            toggle(
                "Re-read Safari on launch",
                detail: model.hasFullDiskAccess
                    ? "Full Disk Access is granted."
                    : "Needs Full Disk Access, which is optional.",
                isOn: model.preferences.autoSyncOnLaunch,
                action: model.setAutoSync
            )
            .disabled(!model.hasFullDiskAccess)
            .opacity(model.hasFullDiskAccess ? 1 : 0.55)

            Button("Open the Import tab", action: onOpenImport)
                .buttonStyle(QuietButtonStyle(tint: Palette.boneDim, size: 13))
        }
    }

    private var aboutLine: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Nine slots per page. 1–9 opens one, ← → turns the page, Esc closes.")
                .font(Palette.display(13.5, .regular))
                .foregroundStyle(Palette.boneFaint)
            Text("Bookmarks live in ~/Library/Application Support/SafariRadial")
                .font(Palette.mono(11))
                .foregroundStyle(Palette.boneFaint)
                .textSelection(.enabled)
        }
        .padding(.top, 6)
        .padding(.horizontal, 4)
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
        return HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .padding(.top, 2)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(Palette.display(13.5, .medium))
        .foregroundStyle(colour)
    }

    private func toggle(
        _ label: String,
        detail: String?,
        isOn: Bool,
        action: @escaping (Bool) -> Void
    ) -> some View {
        Toggle(isOn: Binding(get: { isOn }, set: action)) {
            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(Palette.display(17, .regular))
                    .foregroundStyle(Palette.bone)
                if let detail {
                    Text(detail)
                        .font(Palette.display(13.5, .regular))
                        .foregroundStyle(Palette.boneDim)
                }
            }
        }
        .toggleStyle(BrassToggleStyle())
    }

    private func card<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title.uppercased())
                .font(Palette.mono(11, .semibold))
                .tracking(1.8)
                .foregroundStyle(Palette.boneFaint)
            content()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Palette.hull.opacity(0.9)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Palette.rim, lineWidth: 1))
    }
}
