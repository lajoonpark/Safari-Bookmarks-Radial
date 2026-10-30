import SwiftUI
import AppKit
import RadialCore

/// The quickest way to get one link onto the dial.
///
/// The menu bar item used to lead to the manager window, which meant a full window, a reload
/// and a scroll for what is usually "paste the thing I just copied". This is a small panel
/// with the caret already blinking in the link field: paste, Return, gone.
struct QuickAddView: View {
    @ObservedObject var model: BookmarkListModel
    var onClose: () -> Void

    @State private var url = ""
    @State private var title = ""
    @State private var error: String?
    @State private var added: SlotToast?
    @FocusState private var focus: Field?

    private enum Field { case link, name }

    private struct SlotToast: Equatable {
        let slot: Int
        let title: String
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let added {
                confirmation(added)
            } else {
                form
            }
        }
        .frame(width: 420)
        .background(Palette.void)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(added == nil ? Palette.signal : Palette.mint)
                .frame(height: 2)
                .animation(.easeOut(duration: 0.18), value: added == nil)
        }
        .onExitCommand(perform: onClose)
        .onAppear {
            // The clipboard is the reason this panel exists, so use it before asking.
            if let pasted = QuickAddView.linkFromClipboard(), url.isEmpty {
                url = pasted
                title = QuickAddView.suggestedTitle(for: pasted)
                focus = .name
            } else {
                focus = .link
            }
        }
    }

    // MARK: - Form

    private var form: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("New slot")
                    .font(Palette.display(15, .semibold))
                    .foregroundStyle(Palette.bone)
                Spacer()
                Text("next slot · page \(nextSlotPage)")
                    .font(Palette.mono(9.5, .medium))
                    .foregroundStyle(Palette.boneFaint)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("LINK")
                    .font(Palette.mono(9, .medium))
                    .foregroundStyle(Palette.boneFaint)
                HStack(spacing: 0) {
                    Text("https://")
                        .font(Palette.mono(12.5))
                        .foregroundStyle(Palette.boneFaint)
                    TextField("", text: $url, prompt: hint("paste a link, or type a domain"))
                        .textFieldStyle(.plain)
                        .font(Palette.mono(12.5))
                        .foregroundStyle(Palette.bone)
                        .focused($focus, equals: .link)
                        .onSubmit(commit)
                        .onChange(of: url) { _, _ in
                            if error != nil { error = nil }
                        }
                }
                .padding(.horizontal, 10)
                .frame(height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Palette.hull)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(error == nil ? Palette.rim : Palette.alarm, lineWidth: 1)
                )
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("DIAL LABEL")
                    .font(Palette.mono(9, .medium))
                    .foregroundStyle(Palette.boneFaint)
                TextField("", text: $title, prompt: hint("Optional — defaults to the domain"))
                    .textFieldStyle(.plain)
                    .font(Palette.display(12.5, .regular))
                    .foregroundStyle(Palette.bone)
                    .focused($focus, equals: .name)
                    .onSubmit(commit)
                    .padding(.horizontal, 10)
                    .frame(height: 32)
                    .hullPanel(radius: 7)
            }

            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(Palette.display(11, .medium))
                    .foregroundStyle(Palette.alarm)
                    .transition(.opacity)
            }

            HStack(spacing: 8) {
                Spacer()
                Button("Cancel", action: onClose)
                    .buttonStyle(QuietButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button("Add to dial", action: commit)
                    .buttonStyle(SignalButtonStyle(isEnabled: canCommit))
                    .disabled(!canCommit)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .animation(.spring(response: 0.3, dampingFraction: 0.84), value: error)
    }

    private var canCommit: Bool {
        Bookmark.normalizedURL(url) != nil
    }

    private var nextSlotPage: Int {
        (model.store.count) / RadialLayout.maxSlicesPerPage + 1
    }

    private func commit() {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let failure = model.add(title: title, url: trimmed) {
            withAnimation { error = failure }
            focus = .link
            return
        }
        // `model.add` reloads, so the new count is the slot the bookmark just landed in.
        withAnimation(.spring(response: 0.34, dampingFraction: 0.78)) {
            added = SlotToast(
                slot: model.store.count,
                title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? (Bookmark.normalizedURL(trimmed)?.host ?? trimmed)
                    : title
            )
        }
        // Long enough to read, short enough not to feel like a dialog.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            onClose()
        }
    }

    // MARK: - Confirmation

    private func confirmation(_ toast: SlotToast) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Palette.mint.opacity(0.16))
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Palette.mint)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text("Added to slot \(toast.slot)")
                    .font(Palette.display(13.5, .semibold))
                    .foregroundStyle(Palette.bone)
                Text(toast.title)
                    .font(Palette.mono(11))
                    .foregroundStyle(Palette.boneDim)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(20)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - Clipboard

    /// Only http(s) links are worth pre-filling; a stray sentence in the clipboard would just
    /// have to be deleted.
    static func linkFromClipboard() -> String? {
        guard let raw = NSPasteboard.general.string(forType: .string) else { return nil }
        return Bookmark.normalizedURL(raw)?.absoluteString
    }

    /// A readable default label from the URL path: "/openai/codex" becomes "Codex".
    static func suggestedTitle(for urlString: String) -> String {
        guard let url = URL(string: urlString) else { return "" }
        let last = url.pathComponents.last { $0 != "/" && !$0.isEmpty }
        guard let last, last.count > 1, last.count <= 28 else { return "" }
        return last
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }
}

/// Panel for the quick-add form. Sized to fit its content and centred on the pointer's screen,
/// so it behaves like a HUD rather than a document window.
final class QuickAddPanel: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init(content: NSViewController) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 240),
            styleMask: [.titled, .fullSizeContentView, .closable],
            backing: .buffered,
            defer: false
        )
        contentViewController = content
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        backgroundColor = Palette.nsVoid
        appearance = NSAppearance(named: .darkAqua)
        level = .floating
        isReleasedWhenClosed = false
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        animationBehavior = .utilityWindow
    }
}
