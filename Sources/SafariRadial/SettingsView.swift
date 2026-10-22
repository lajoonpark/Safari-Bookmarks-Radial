import SwiftUI
import RadialCore

struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    @State private var isRecording = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    shortcutSection
                    behaviourSection
                    appearanceSection
                    aboutSection
                }
                .padding(20)
            }
        }
        .background(Palette.background)
        .frame(width: 420, height: 560)
    }

    // MARK: - Shortcut

    private var shortcutSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Shortcut")

            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Palette.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .strokeBorder(
                                    isRecording ? Palette.accent : Palette.stroke,
                                    lineWidth: isRecording ? 1.5 : 1
                                )
                        )

                    if isRecording {
                        HotkeyRecorder(
                            isRecording: $isRecording,
                            current: model.preferences.hotkey,
                            onCapture: { spec in
                                model.setHotkey(spec)
                            }
                        )
                    } else {
                        Text(model.preferences.hotkey.displayName)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(Palette.primaryText)
                    }
                }
                .frame(height: 34)
                .frame(maxWidth: 150)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                        isRecording = true
                    }
                }
                .help("Click, then press the shortcut you want")

                Button(isRecording ? "Cancel" : "Change") {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                        isRecording.toggle()
                    }
                }
                .buttonStyle(SpringyButtonStyle())

                Spacer()
            }

            if let error = model.hotkeyError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Palette.danger)
            } else if let conflict = model.conflict {
                // Shadowing ⌘R is a deliberate trade-off the user should opt into knowingly.
                VStack(alignment: .leading, spacing: 5) {
                    Label(
                        "\(model.preferences.hotkey.displayName) usually \(conflict.description) in \(conflict.owner).",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.system(size: 10.5))
                    .foregroundStyle(Palette.accentWarm)
                    .fixedSize(horizontal: false, vertical: true)

                    Button("Use \(model.suggestedHotkey.displayName) instead") {
                        model.setHotkey(model.suggestedHotkey)
                    }
                    .buttonStyle(SpringyButtonStyle(tint: Palette.accentWarm.opacity(0.18)))
                    .font(.system(size: 10.5))
                }
            } else {
                Text("Opens the menu at your cursor. Press it again to close.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Palette.tertiaryText)
            }

            HStack(spacing: 6) {
                ForEach(HotkeySpec.suggestions.dropFirst().indices, id: \.self) { index in
                    let spec = HotkeySpec.suggestions[index]
                    Button(spec.displayName) {
                        model.setHotkey(spec)
                    }
                    .buttonStyle(SpringyButtonStyle(tint: Color.white.opacity(0.06)))
                    .font(.system(size: 11))
                }
                Spacer()
            }
        }
    }

    // MARK: - Behaviour

    private var behaviourSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Opening links")

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

            if model.preferences.openIn != .newTab {
                Text("Uses AppleScript, so macOS will ask once for permission to control Safari. Falls back to a new tab if denied.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Palette.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Toggle("Open in the background", isOn: Binding(
                get: { model.preferences.openInBackground },
                set: { model.setBackground($0) }
            ))
            .toggleStyle(.switch)
            .font(.system(size: 12))
            .foregroundStyle(Palette.primaryText)

            Toggle("Refresh from Safari at launch", isOn: Binding(
                get: { model.preferences.autoSyncOnLaunch },
                set: { model.setAutoSync($0) }
            ))
            .toggleStyle(.switch)
            .font(.system(size: 12))
            .foregroundStyle(Palette.primaryText)

            Toggle("Start at login", isOn: Binding(
                get: { model.preferences.launchAtLogin },
                set: { model.setLaunchAtLogin($0) }
            ))
            .toggleStyle(.switch)
            .font(.system(size: 12))
            .foregroundStyle(Palette.primaryText)
        }
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Menu")

            Toggle("Show slice numbers", isOn: Binding(
                get: { model.preferences.showNumbers },
                set: { model.setShowNumbers($0) }
            ))
            .toggleStyle(.switch)
            .font(.system(size: 12))
            .foregroundStyle(Palette.primaryText)

            HStack {
                Text("Size")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.primaryText)
                Slider(
                    value: Binding(
                        get: { model.preferences.menuRadius },
                        set: { model.setMenuRadius($0) }
                    ),
                    in: 140...320
                )
                Text("\(Int(model.preferences.menuRadius))")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Palette.secondaryText)
                    .frame(width: 30, alignment: .trailing)
            }
        }
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("About")
            Text("Nine slices per page. Use ← → to page, 1–9 to fire a slice, Esc or the centre ✕ to close.")
                .font(.system(size: 10.5))
                .foregroundStyle(Palette.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
            Text("Bookmarks are stored in ~/Library/Application Support/SafariRadial.")
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(Palette.tertiaryText)
                .textSelection(.enabled)
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 9.5, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(Palette.tertiaryText)
    }
}
