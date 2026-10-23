import SwiftUI
import AppKit
import RadialCore

/// First run, three steps.
///
/// The middle step exists because Safari import genuinely needs Full Disk Access and that is
/// the kind of permission request people abandon an app over. So it is offered as an explicit
/// choice, with the cost of skipping stated plainly: the app is complete without it.
struct OnboardingView: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        VStack(spacing: 0) {
            TopBar(step: model.step)
            HStack(spacing: 0) {
                art
                content
            }
            .frame(height: 372)
            Rectangle().fill(Palette.rim).frame(height: 1)
            footer
        }
        .background(Palette.void)
        .frame(width: 760)
    }

    // MARK: - Art

    private var art: some View {
        ZStack {
            LinearGradient(
                colors: [Palette.voidRaised, Palette.void],
                startPoint: .top,
                endPoint: .bottom
            )
            RadialGradient(
                colors: [Palette.signal.opacity(0.10), Color.clear],
                center: .init(x: 0.5, y: 0.32),
                startRadius: 8,
                endRadius: 160
            )
            Group {
                switch model.step {
                case .welcome: WelcomeMark()
                case .safari: SafariMark()
                case .ready: ReadyMark()
                }
            }
            .transition(.opacity.combined(with: .scale(scale: 0.94)))
            .animation(.spring(response: 0.45, dampingFraction: 0.8), value: model.step)
        }
        .frame(width: 252)
        .overlay(alignment: .trailing) {
            Rectangle().fill(Palette.rim).frame(width: 1)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(model.step.eyebrow)
                .font(Palette.mono(9.5, .medium))
                .foregroundStyle(Palette.signal)
                .tracking(0.8)

            Text(model.step.title)
                .font(Palette.display(24, .semibold))
                .foregroundStyle(Palette.bone)
                .tracking(-0.3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 9)

            Group {
                switch model.step {
                case .welcome: welcomeCopy
                case .safari: safariCopy
                case .ready: readyCopy
                }
            }
            .padding(.top, 12)

            Spacer(minLength: 12)

            actions
        }
        .padding(.horizontal, 30)
        .padding(.top, 26)
        .padding(.bottom, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var welcomeCopy: some View {
        VStack(alignment: .leading, spacing: 12) {
            paragraph(
                "Every bookmark you actually use, on one ring, at your cursor. Press the shortcut anywhere and the dial appears where your pointer already is, so nothing moves."
            )
            HStack(spacing: 6) {
                KeyCap(text: model.hotkeyDisplay)
                Text("opens the dial")
                    .font(Palette.display(11.5, .regular))
                    .foregroundStyle(Palette.boneDim)
            }
            paragraph(
                "Then press 1–9, or click a wedge. Esc closes it without opening anything.",
                dim: true
            )
        }
    }

    private var safariCopy: some View {
        VStack(alignment: .leading, spacing: 12) {
            paragraph(
                "Safari stores bookmarks in a system-protected file. Reading it needs Full Disk Access. You can grant it now, or skip it and never think about it again."
            )
            VStack(alignment: .leading, spacing: 4) {
                Text("Full Disk Access is optional")
                    .font(Palette.display(12, .semibold))
                    .foregroundStyle(Palette.bone)
                Text("Adding links by hand, reordering, the shortcut, and every setting work exactly the same without it. It only switches on this one import button.")
                    .font(Palette.display(11, .regular))
                    .foregroundStyle(Palette.boneDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, 12)
            .overlay(alignment: .leading) {
                Rectangle().fill(Palette.signal).frame(width: 2)
            }
        }
    }

    private var readyCopy: some View {
        VStack(alignment: .leading, spacing: 12) {
            paragraph(model.hasBookmarks
                ? "Your dial is ready. Press the shortcut anywhere to open it, then a number to fire a slot."
                : "Your dial is ready and empty — that is fine. Add links in the main window, or import from Safari later if you change your mind."
            )
            HStack(spacing: 14) {
                tip("Esc", "closes")
                tip("← →", "page")
                tip("1–9", "open")
            }
        }
    }

    private func tip(_ key: String, _ label: String) -> some View {
        HStack(spacing: 5) {
            KeyCap(text: key, compact: true)
            Text(label)
                .font(Palette.display(10.5, .regular))
                .foregroundStyle(Palette.boneFaint)
        }
    }

    private func paragraph(_ text: String, dim: Bool = false) -> some View {
        Text(text)
            .font(Palette.display(12.5, .regular))
            .lineSpacing(3)
            .foregroundStyle(dim ? Palette.boneFaint : Palette.boneDim)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Actions

    private var actions: some View {
        HStack(spacing: 9) {
            switch model.step {
            case .welcome:
                Button("Show me the dial") { model.advance() }
                    .buttonStyle(SignalButtonStyle())
                Button("Skip") { model.finish() }
                    .buttonStyle(QuietButtonStyle(tint: Palette.boneDim))
            case .safari:
                Button("Open Full Disk Access") { model.requestFullDiskAccess() }
                    .buttonStyle(SignalButtonStyle())
                Button("Not now") { model.advance() }
                    .buttonStyle(QuietButtonStyle())
            case .ready:
                Button("Start using it") { model.finish() }
                    .buttonStyle(SignalButtonStyle())
            }
            Spacer()
            StepPips(step: model.step)
        }
    }

    private var footer: some View {
        HStack {
            Text(model.step.footerHint)
                .font(Palette.display(10.5, .regular))
                .foregroundStyle(Palette.boneFaint)
            Spacer()
            if model.step != .welcome {
                Button("Back") { model.goBack() }
                    .buttonStyle(QuietButtonStyle(tint: Palette.boneDim))
            }
        }
        .padding(.horizontal, 22)
        .frame(height: 46)
    }
}

// MARK: - Chrome

private struct TopBar: View {
    let step: OnboardingStep

    var body: some View {
        HStack(spacing: 7) {
            // Real traffic lights live above this in the window's title bar; these are only
            // a hint that this is a window, so they stay subtle and inert.
            ForEach(0..<3, id: \.self) { _ in
                Circle().fill(Palette.bone.opacity(0.10)).frame(width: 8, height: 8)
            }
            Spacer()
            Text(step.windowTitle)
                .font(Palette.display(11, .medium))
                .foregroundStyle(Palette.boneFaint)
            Spacer()
            Circle().fill(Color.clear).frame(width: 8, height: 8)
        }
        .padding(.horizontal, 14)
        .frame(height: 34)
        .background(Palette.chromeTop)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Palette.rim).frame(height: 1)
        }
    }
}

private struct StepPips: View {
    let step: OnboardingStep

    var body: some View {
        HStack(spacing: 5) {
            ForEach(OnboardingStep.allCases, id: \.self) { candidate in
                Capsule()
                    .fill(candidate.rawValue <= step.rawValue ? Palette.signal : Palette.bone.opacity(0.15))
                    .frame(width: 20, height: 3)
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.82), value: step)
    }
}

// MARK: - Art marks

/// Step 1: the dial itself, mid-sweep. The product's whole idea in one shape.
private struct WelcomeMark: View {
    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height) - 60
            let layout = RadialLayout(sliceCount: 8, centerRadius: side * 0.15, outerRadius: side * 0.5)
            ZStack {
                ForEach(0..<8, id: \.self) { index in
                    MiniSlice(layout: layout, index: index, lit: index == 1)
                }
                Circle()
                    .fill(Palette.void)
                    .overlay(Circle().strokeBorder(Palette.rimStrong, lineWidth: 1))
                    .frame(width: layout.centerRadius * 2, height: layout.centerRadius * 2)
                Circle()
                    .fill(Palette.signal)
                    .frame(width: 3, height: 3)
            }
            .frame(width: side * 1.1, height: side * 1.1)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
    }
}

/// Step 2: a shield, because the step is about a permission — and a lock that is deliberately
/// open at the bottom, since the app does not need it.
private struct SafariMark: View {
    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .strokeBorder(Palette.bone.opacity(0.10), lineWidth: 1)
                    .frame(width: 104, height: 104)
                Circle()
                    .strokeBorder(Palette.signal.opacity(0.34), lineWidth: 1)
                    .frame(width: 74, height: 74)
                Image(systemName: "safari.fill")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(Palette.signal)
            }
            Text("safari")
                .font(Palette.mono(10, .medium))
                .foregroundStyle(Palette.boneFaint)
                .tracking(1)
        }
    }
}

/// Step 3: nine slots, filled. The thing you are about to use.
private struct ReadyMark: View {
    var body: some View {
        VStack(spacing: 10) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { column in
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(index(row, column) == 0
                                ? Palette.signal.opacity(0.26)
                                : Palette.bone.opacity(0.06))
                            .overlay(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .strokeBorder(
                                        index(row, column) == 0
                                            ? Palette.signal.opacity(0.8)
                                            : Palette.bone.opacity(0.12),
                                        lineWidth: 1
                                    )
                            )
                            .frame(width: 34, height: 26)
                            .overlay(
                                Text("\(index(row, column) + 1)")
                                    .font(Palette.mono(9.5, .medium))
                                    .foregroundStyle(index(row, column) == 0
                                        ? Palette.signal
                                        : Palette.boneFaint)
                            )
                    }
                }
            }
        }
    }

    private func index(_ row: Int, _ column: Int) -> Int { row * 3 + column }
}

// MARK: - Step model

enum OnboardingStep: Int, CaseIterable {
    case welcome = 0
    case safari
    case ready

    var windowTitle: String {
        switch self {
        case .welcome: return "Welcome to Safari Radial"
        case .safari: return "Safari import"
        case .ready: return "You are all set"
        }
    }

    var eyebrow: String {
        switch self {
        case .welcome: return "STEP 1 OF 3"
        case .safari: return "STEP 2 OF 3 · OPTIONAL"
        case .ready: return "STEP 3 OF 3"
        }
    }

    var title: String {
        switch self {
        case .welcome: return "Nine things,\none gesture."
        case .safari: return "Bring your Safari\nbookmarks along"
        case .ready: return "Your dial is ready"
        }
    }

    var footerHint: String {
        switch self {
        case .welcome: return "You can reopen this tour from the menu bar at any time."
        case .safari: return "Nothing here is required to start using the app."
        case .ready: return "Reopen this tour from the menu bar whenever you want."
        }
    }
}

final class OnboardingModel: ObservableObject {
    @Published private(set) var step: OnboardingStep = .welcome
    @Published private(set) var hasBookmarks: Bool

    let hotkeyDisplay: String
    private let environment: AppEnvironment
    var onFinish: (() -> Void)?

    init(environment: AppEnvironment, hotkey: HotkeySpec, hasBookmarks: Bool) {
        self.environment = environment
        self.hotkeyDisplay = hotkey.displayName
        self.hasBookmarks = hasBookmarks
    }

    func advance() {
        guard let next = OnboardingStep(rawValue: step.rawValue + 1) else {
            finish()
            return
        }
        step = next
    }

    func goBack() {
        guard let previous = OnboardingStep(rawValue: step.rawValue - 1) else { return }
        step = previous
    }

    /// Opens the right System Settings pane and moves on, so the user is never stuck on it.
    func requestFullDiskAccess() {
        openFullDiskAccessSettings()
        advance()
    }

    private func openFullDiskAccessSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles",
        ]
        for string in urls {
            if let url = URL(string: string), NSWorkspace.shared.open(url) { return }
        }
    }

    func finish() {
        environment.updatePreferences {
            $0.hasCompletedOnboarding = true
        }
        onFinish?()
    }
}

/// The nine-slot mark used in the manager window and on the welcome step.
struct MiniSlice: View {
    let layout: RadialLayout
    let index: Int
    let lit: Bool

    var body: some View {
        let drawn = layout.drawableRange(of: index, inset: 0.05)
        ZStack {
            WedgeShape(layout: layout, drawn: drawn)
                .fill(lit ? Palette.signal.opacity(0.26) : Palette.bone.opacity(0.055))
            WedgeShape(layout: layout, drawn: drawn)
                .stroke(lit ? Palette.signal.opacity(0.85) : Palette.bone.opacity(0.14), lineWidth: 0.9)
        }
    }
}

struct WedgeShape: Shape {
    let layout: RadialLayout
    let drawn: (start: CGFloat, sweep: CGFloat)

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let segments = 8
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        func point(radius: CGFloat, angle: CGFloat) -> CGPoint {
            let p = layout.point(radius: radius, angle: angle)
            return CGPoint(x: centre.x + p.x, y: centre.y + p.y)
        }
        path.move(to: point(radius: layout.outerRadius, angle: drawn.start))
        for step in 1...segments {
            let t = CGFloat(step) / CGFloat(segments)
            path.addLine(to: point(radius: layout.outerRadius, angle: drawn.start + drawn.sweep * t))
        }
        for step in stride(from: segments, through: 0, by: -1) {
            let t = CGFloat(step) / CGFloat(segments)
            path.addLine(to: point(radius: layout.innerRadius, angle: drawn.start + drawn.sweep * t))
        }
        path.closeSubpath()
        return path
    }
}
