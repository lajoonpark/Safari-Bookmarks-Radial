import SwiftUI
import RadialCore

/// Home. One object and one sentence: the compass, and what it holds.
///
/// Phase 2 shows the existing mini-dial at hero size, tilting toward the cursor, so the layout
/// can be judged in the real window. Phase 3 swaps it for the live, hoverable compass.
struct DialTabView: View {
    @ObservedObject var model: BookmarkListModel
    @ObservedObject var settings: SettingsModel
    @ObservedObject var tracker: PointerTracker
    var onOpenDial: () -> Void
    var onAdd: () -> Void

    @State private var arrived = false

    var body: some View {
        HStack(spacing: 24) {
            copy
                .frame(maxWidth: .infinity, alignment: .leading)
            compass
                .frame(width: 480, height: 480)
        }
        .padding(.leading, 64)
        .padding(.trailing, 40)
        .onAppear {
            arrived = false
            withAnimation(.spring(response: 1.0, dampingFraction: 0.62).delay(0.1)) {
                arrived = true
            }
        }
    }

    // MARK: - Copy

    private var copy: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(eyebrow)
                .font(Palette.mono(11, .semibold))
                .tracking(1.8)
                .foregroundStyle(Palette.boneFaint)

            headline
                .font(Palette.display(56, .semibold))
                .tracking(-1)
                .foregroundStyle(Palette.bone)
                .lineSpacing(0)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 18)

            Text(subtitle)
                .font(Palette.display(17, .regular))
                .foregroundStyle(Palette.boneDim)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 16)

            HStack(spacing: 10) {
                Button {
                    onOpenDial()
                } label: {
                    Label("Try the dial", systemImage: "scope")
                }
                .buttonStyle(SignalButtonStyle(size: 15))

                Button {
                    onAdd()
                } label: {
                    Label("Add a link", systemImage: "plus")
                }
                .buttonStyle(QuietButtonStyle(size: 15))
            }
            .padding(.top, 30)

            HStack(spacing: 14) {
                HStack(spacing: 6) {
                    ForEach(Array(hotkeyParts.enumerated()), id: \.offset) { _, part in
                        PhysicalKey(text: part)
                    }
                }
                Text("opens the dial, anywhere")
                    .font(Palette.display(15, .regular))
                    .foregroundStyle(Palette.boneFaint)
            }
            .padding(.top, 54)
        }
    }

    private var eyebrow: String {
        let count = model.bookmarks.count
        guard count > 0 else { return "EMPTY DIAL" }
        let pages = RadialPaging(total: count).pageCount
        return "\(count) SLOT\(count == 1 ? "" : "S") · \(pages) PAGE\(pages == 1 ? "" : "S")"
    }

    /// "Eight slots, one turn of the dial." with the middle in italic vermilion-orange.
    private var headline: Text {
        let count = model.bookmarks.count
        guard count > 0 else {
            return Text("Nothing here ") + Text("yet.").italic().foregroundColor(Palette.signal)
        }
        let noun = count == 1 ? "slot" : "slots"
        return Text("\(Self.words(count)) \(noun), ")
            + Text("one turn").italic().foregroundColor(Palette.signal)
            + Text(" of the dial.")
    }

    private var subtitle: String {
        model.bookmarks.isEmpty
            ? "Add your first link, or import your Safari bookmarks, and it appears here."
            : "Press the shortcut anywhere and the dial opens under your cursor. Nine slots to a page."
    }

    /// Modifier symbols become their own keys; whatever follows is one more.
    private var hotkeyParts: [String] {
        let name = settings.preferences.hotkey.displayName
        let modifiers: Set<Character> = ["⌘", "⌃", "⌥", "⇧"]
        var parts: [String] = []
        var rest = ""
        for character in name {
            if modifiers.contains(character) && rest.isEmpty {
                parts.append(String(character))
            } else {
                rest.append(character)
            }
        }
        if !rest.isEmpty { parts.append(rest) }
        return parts
    }

    private static func words(_ count: Int) -> String {
        let names = ["No", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine",
                     "Ten", "Eleven", "Twelve", "Thirteen", "Fourteen", "Fifteen", "Sixteen"]
        return count < names.count ? names[count] : "\(count)"
    }

    // MARK: - Compass

    private var compass: some View {
        // Tilts away from the cursor, with weight: the spring lags the pointer a little.
        let tiltX = Double(0.5 - tracker.unit.y) * 26 + 10
        let tiltY = Double(tracker.unit.x - 0.5) * 30
        return ZStack {
            // Contact shadow, so the instrument sits on the desk instead of floating.
            Ellipse()
                .fill(RadialGradient(
                    colors: [Color.black.opacity(0.65), Color.clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: 210
                ))
                .frame(width: 420, height: 290)
                .blur(radius: 12)
                .offset(x: CGFloat(-tiltY) * 1.4, y: 180 + CGFloat(tiltX) * 1.2)

            MiniDial()
                .frame(width: 420, height: 420)
                .shadow(color: Color.black.opacity(0.5), radius: 24, y: 18)
                .rotation3DEffect(.degrees(tiltX), axis: (x: 1, y: 0, z: 0), perspective: 0.55)
                .rotation3DEffect(.degrees(tiltY), axis: (x: 0, y: 1, z: 0), perspective: 0.55)
        }
        .scaleEffect(arrived ? 1 : 0.72)
        .rotationEffect(.degrees(arrived ? 0 : -40))
        .opacity(arrived ? 1 : 0)
        .animation(.spring(response: 0.7, dampingFraction: 0.78), value: tracker.unit)
    }
}
