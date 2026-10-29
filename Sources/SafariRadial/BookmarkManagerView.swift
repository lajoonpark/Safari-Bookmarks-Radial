import SwiftUI
import RadialCore

/// The bookmark window: a ledger of slots, in the exact order the dial presents them.
///
/// Structure over cards. Rows are separated by hairlines and share one left-hand slot gutter,
/// because the slot number *is* the interface — it is what you type. Boxing each row would
/// turn nine slots of muscle memory into nine unrelated cards.
struct BookmarkManagerView: View {
    @ObservedObject var model: BookmarkListModel
    @ObservedObject var settings: SettingsModel
    var onOpenSettings: () -> Void = {}

    @State private var newTitle = ""
    @State private var newURL = ""
    @State private var errorText: String?
    @State private var editing: Bookmark?
    @State private var hoveredID: UUID?

    @FocusState private var urlFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            addBar
            hairline
            columnHeader
            content
            hairline
            footer
        }
        .background(Palette.void)
        .frame(minWidth: 760, minHeight: 560)
        .sheet(item: $editing) { bookmark in
            EditBookmarkSheet(bookmark: bookmark) { title, url in
                model.update(id: bookmark.id, title: title, url: url)
            }
        }
        .onChange(of: model.focusRequest) { _ in
            // A request from the menu bar ("New Bookmark…") should land the caret in the field.
            urlFocused = true
        }
    }

    private var hairline: some View {
        Rectangle().fill(Palette.rim).frame(height: 1)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 18) {
            MiniDial()
                .frame(width: 92, height: 92)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text("Safari Radial")
                        .font(Palette.display(23, .semibold))
                        .foregroundStyle(Palette.bone)
                        .tracking(-0.4)
                    Circle()
                        .fill(Palette.signal)
                        .frame(width: 6, height: 6)
                        .offset(y: -1)
                }
                Text(statusLine)
                    .font(Palette.mono(10.5))
                    .foregroundStyle(Palette.boneDim)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 7) {
                HStack(spacing: 8) {
                    searchField
                    Button {
                        model.syncFromSafari()
                    } label: {
                        Label("Import from Safari", systemImage: "arrow.down.to.line")
                            .font(Palette.display(12, .medium))
                    }
                    .buttonStyle(QuietButtonStyle())
                    .help("Add your Safari bookmarks here, keeping the slots you already arranged")

                    Button(action: onOpenSettings) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(QuietButtonStyle())
                    .help("Settings — change the shortcut that opens the dial")
                }
                Text(model.hasFullDiskAccess ? "Safari access granted" : "Safari import is off")
                    .font(Palette.mono(9.5))
                    .foregroundStyle(model.hasFullDiskAccess ? Palette.mint.opacity(0.8) : Palette.boneFaint)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.horizontal, 26)
        .padding(.top, 20)
        .padding(.bottom, 16)
    }

    /// Built from real counts, not filler: the number of slots is the whole promise of the app.
    private var statusLine: String {
        let count = model.bookmarks.count
        guard count > 0 else { return "No slots filled yet" }
        let paging = RadialPaging(total: count)
        let slots = "\(count) slot\(count == 1 ? "" : "s")"
        let pages = paging.pageCount == 1 ? "one page" : "\(paging.pageCount) pages"
        return "\(slots) · \(pages) · \(settings.preferences.hotkey.displayName) opens the dial"
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Palette.boneFaint)
            TextField("", text: $model.searchText, prompt: hint("Find a slot"))
                .textFieldStyle(.plain)
                .font(Palette.display(12, .regular))
                .foregroundStyle(Palette.bone)
                .frame(width: 118)
        }
        .padding(.horizontal, 9)
        .frame(height: 28)
        .hullPanel(radius: 7)
    }

    // MARK: - Add

    private var addBar: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .bottom, spacing: 8) {
                VStack(alignment: .leading, spacing: 5) {
                    fieldLabel("NAME")
                    TextField("", text: $newTitle, prompt: hint("Name (optional)"))
                        .textFieldStyle(.plain)
                        .font(Palette.display(12.5, .regular))
                        .foregroundStyle(Palette.bone)
                        .padding(.horizontal, 10)
                        .frame(height: 32)
                        .hullPanel(radius: 7)
                }
                .frame(width: 208)

                VStack(alignment: .leading, spacing: 5) {
                    fieldLabel("LINK")
                    HStack(spacing: 0) {
                        Text("https://")
                            .font(Palette.mono(12))
                            .foregroundStyle(Palette.boneFaint)
                        TextField("", text: $newURL, prompt: hint("paste a link, or type a domain"))
                            .textFieldStyle(.plain)
                            .font(Palette.display(12.5, .regular))
                            .foregroundStyle(Palette.bone)
                            .focused($urlFocused)
                            .onSubmit(commitNew)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 32)
                    .hullPanel(radius: 7)
                }

                Button("Add bookmark", action: commitNew)
                    .buttonStyle(SignalButtonStyle(isEnabled: canCommit))
                    .disabled(!canCommit)
                    .padding(.bottom, 1)
            }

            if let errorText {
                Label(errorText, systemImage: "exclamationmark.triangle.fill")
                    .font(Palette.display(11, .medium))
                    .foregroundStyle(Palette.alarm)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 26)
        .padding(.bottom, 16)
        .animation(.spring(response: 0.3, dampingFraction: 0.82), value: errorText)
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(Palette.mono(9, .medium))
            .tracking(0.8)
            .foregroundStyle(Palette.boneDim)
            .padding(.leading, 2)
    }

    private var canCommit: Bool {
        !newURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func commitNew() {
        let trimmed = newURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let error = model.add(title: newTitle, url: trimmed) {
            errorText = error
            return
        }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
            errorText = nil
            newTitle = ""
            newURL = ""
        }
        urlFocused = true
    }

    // MARK: - Columns

    private var columnHeader: some View {
        HStack(spacing: 14) {
            Text("SLOT")
                .frame(width: 30, alignment: .trailing)
            Text("BOOKMARK")
            Spacer(minLength: 0)
            Text("PAGE")
                .frame(width: 56, alignment: .trailing)
        }
        .font(Palette.mono(9, .medium))
        .foregroundStyle(Palette.boneFaint)
        .padding(.horizontal, 26)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    // MARK: - Rows

    @ViewBuilder
    private var content: some View {
        if model.bookmarks.isEmpty {
            emptyState
        } else if model.filtered.isEmpty {
            noResults
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(model.filtered) { bookmark in
                        row(for: bookmark)
                    }
                }
                .padding(.bottom, 8)
            }
        }
    }

    private func row(for bookmark: Bookmark) -> some View {
        let slot = model.slotNumber(for: bookmark)
        let isActive = hoveredID == bookmark.id || model.selectedID == bookmark.id
        let page = slot.map { ($0 - 1) / RadialLayout.maxSlicesPerPage + 1 } ?? 0

        return HStack(spacing: 14) {
            SlotGutter(
                slot: slot ?? 0,
                sliceIndex: slot.map { ($0 - 1) % RadialLayout.maxSlicesPerPage },
                emphasised: isActive
            )
            .frame(width: 30, alignment: .trailing)

            Text(bookmark.displayTitle)
                .font(Palette.display(13, .medium))
                .foregroundStyle(Palette.bone)
                .lineLimit(1)
                .frame(width: 168, alignment: .leading)

            Text(bookmark.host.isEmpty ? bookmark.url : bookmark.host)
                .font(Palette.mono(10.5))
                .foregroundStyle(Palette.boneDim)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 8)

            Text("\(page)")
                .font(Palette.mono(10.5, .medium))
                .foregroundStyle(isActive ? Palette.boneDim : Palette.boneFaint)
                .frame(width: 20, alignment: .trailing)

            HStack(spacing: 1) {
                iconButton("chevron.up", help: "Move up one slot") {
                    model.moveSlot(of: bookmark, by: -1)
                }
                iconButton("chevron.down", help: "Move down one slot") {
                    model.moveSlot(of: bookmark, by: 1)
                }
                iconButton("arrow.up.right", help: "Open in \(model.browserName)") {
                    model.openBookmark(bookmark)
                }
                iconButton("pencil", help: "Edit") {
                    editing = bookmark
                }
                iconButton("xmark", help: "Remove", tint: Palette.alarm) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                        model.remove(bookmark)
                    }
                }
            }
            .frame(width: 124, alignment: .trailing)
            .opacity(isActive ? 1 : 0)
            .animation(.easeOut(duration: 0.12), value: isActive)
        }
        .padding(.horizontal, 26)
        .frame(height: 42)
        .background(rowBackground(isActive: isActive))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(isActive ? Palette.signal : Color.clear)
                .frame(width: 2)
        }
        .overlay(alignment: .top) {
            Rectangle().fill(Palette.rim.opacity(0.55)).frame(height: 1)
        }
        .contentShape(Rectangle())
        .onTapGesture { model.selectedID = bookmark.id }
        .onHover { hovering in
            hoveredID = hovering ? bookmark.id : (hoveredID == bookmark.id ? nil : hoveredID)
        }
        .contextMenu {
            Button("Open in \(model.browserName)") { model.openBookmark(bookmark) }
            Button("Edit…") { editing = bookmark }
            Divider()
            Button("Move to slot 1") { model.moveToFront(bookmark) }
            Divider()
            Button("Remove", role: .destructive) { model.remove(bookmark) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Slot \(slot ?? 0), \(bookmark.displayTitle), page \(page)")
    }

    @ViewBuilder
    private func rowBackground(isActive: Bool) -> some View {
        if isActive {
            LinearGradient(
                colors: [Palette.signal.opacity(0.12), Palette.signal.opacity(0.02)],
                startPoint: .leading,
                endPoint: .trailing
            )
        } else {
            Color.clear
        }
    }

    private func iconButton(
        _ systemName: String,
        help: String,
        tint: Color = Palette.boneDim,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            MiniDial(filled: false)
                .frame(width: 120, height: 120)
                .opacity(0.55)
            Text("Your dial is empty")
                .font(Palette.display(15, .semibold))
                .foregroundStyle(Palette.bone)
            Text("Add a link above, or import your Safari bookmarks.\nThe first nine fill page one.")
                .font(Palette.display(11.5, .regular))
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .foregroundStyle(Palette.boneDim)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noResults: some View {
        VStack(spacing: 8) {
            Text("Nothing matches “\(model.searchText)”")
                .font(Palette.display(13, .medium))
                .foregroundStyle(Palette.bone)
            Button("Clear the search") { model.searchText = "" }
                .buttonStyle(QuietButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 10) {
            if let message = model.syncMessage {
                HStack(spacing: 6) {
                    Image(systemName: message.isError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                        .font(.system(size: 10, weight: .semibold))
                    Text(message.text)
                        .font(Palette.display(11, .medium))
                }
                .foregroundStyle(message.isError ? Palette.alarm : Palette.mint)
                .transition(.opacity)
            } else {
                Text("Row order is the dial. Row 1 sits at twelve o'clock.")
                    .font(Palette.display(11, .regular))
                    .foregroundStyle(Palette.boneFaint)
            }

            Spacer()

            if !model.hasFullDiskAccess {
                // Worded so it cannot be misread as a requirement.
                Button("Import needs Full Disk Access") {
                    model.openFullDiskAccessSettings()
                }
                .buttonStyle(QuietButtonStyle(tint: Palette.boneDim))
                .help("Optional. Only the Safari import needs this; everything else works without it.")
            }

            HStack(spacing: 6) {
                KeyCap(text: "⌘N")
                Text("add").font(Palette.display(10.5, .regular)).foregroundStyle(Palette.boneFaint)
                KeyCap(text: "⌘,")
                Text("settings").font(Palette.display(10.5, .regular)).foregroundStyle(Palette.boneFaint)
            }
        }
        .padding(.horizontal, 26)
        .frame(height: 40)
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: model.syncMessage)
    }
}

// MARK: - Edit sheet

/// Title plus link, with live validation. Small enough that a sheet is the right surface.
struct EditBookmarkSheet: View {
    let bookmark: Bookmark
    let onSave: (String, String) -> String?

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var url: String
    @State private var error: String?

    init(bookmark: Bookmark, onSave: @escaping (String, String) -> String?) {
        self.bookmark = bookmark
        self.onSave = onSave
        _title = State(initialValue: bookmark.title)
        _url = State(initialValue: bookmark.url)
    }

    private var isValid: Bool { Bookmark.normalizedURL(url) != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Edit slot")
                    .font(Palette.display(16, .semibold))
                    .foregroundStyle(Palette.bone)
                Text(bookmark.host.isEmpty ? bookmark.url : bookmark.host)
                    .font(Palette.mono(10))
                    .foregroundStyle(Palette.boneFaint)
            }

            field("Name", placeholder: "Shown on the dial", text: $title)
            field("Link", placeholder: "https://…", text: $url)

            if !url.isEmpty && !isValid {
                Text("Needs to be an http or https address.")
                    .font(Palette.display(10.5, .medium))
                    .foregroundStyle(Palette.alarm)
            }
            if let error {
                Text(error)
                    .font(Palette.display(10.5, .medium))
                    .foregroundStyle(Palette.alarm)
            }

            HStack(spacing: 8) {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(QuietButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    if let message = onSave(title, url) {
                        error = message
                    } else {
                        dismiss()
                    }
                }
                .buttonStyle(SignalButtonStyle(isEnabled: isValid))
                .disabled(!isValid)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 400)
        .background(Palette.void)
    }

    private func field(_ label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(Palette.mono(9, .medium))
                .foregroundStyle(Palette.boneFaint)
            TextField("", text: text, prompt: hint(placeholder))
                .textFieldStyle(.plain)
                .font(Palette.display(12.5, .regular))
                .foregroundStyle(Palette.bone)
                .padding(.horizontal, 10)
                .frame(height: 30)
                .hullPanel(radius: 7)
        }
    }
}

// MARK: - Mini dial

/// The window's mark: the compass, small enough to sit in a header.
///
/// Drawn from `CompassMetrics` and `RadialLayout` rather than shipped as an asset, so the mark
/// can never drift from the real instrument — and so the app has a recognisable object in its
/// window instead of a generic icon.
struct MiniDial: View {
    var filled = true

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            Canvas { context, size in
                let metrics = CompassMetrics(cardRadius: side * 0.36)
                let centre = CGPoint(x: size.width / 2, y: size.height / 2)
                let card = RadialLayout(
                    sliceCount: RadialLayout.maxSlicesPerPage,
                    centerRadius: metrics.hubRadius,
                    outerRadius: metrics.sectorOutset
                )

                // Case.
                context.fill(
                    Path(ellipseIn: CGRect(
                        x: centre.x - metrics.caseRadius,
                        y: centre.y - metrics.caseRadius,
                        width: metrics.caseRadius * 2,
                        height: metrics.caseRadius * 2
                    )),
                    with: .color(CompassTheme.brassMid.swiftUI())
                )
                // Card.
                context.fill(
                    Path(ellipseIn: CGRect(
                        x: centre.x - metrics.cardRadius,
                        y: centre.y - metrics.cardRadius,
                        width: metrics.cardRadius * 2,
                        height: metrics.cardRadius * 2
                    )),
                    with: .color(CompassTheme.paper.swiftUI())
                )

                // Wedges, with the first lit when the dial has contents.
                for index in 0..<RadialLayout.maxSlicesPerPage {
                    let lit = filled && index == 0
                    let drawn = card.drawableRange(of: index, inset: card.step * 0.05)
                    var path = Path()
                    let steps = 8
                    for step in 0...steps {
                        let angle = drawn.start + drawn.sweep * CGFloat(step) / CGFloat(steps)
                        let point = card.point(radius: metrics.sectorOutset, angle: angle)
                        let screen = CGPoint(x: centre.x + point.x, y: centre.y + point.y)
                        step == 0 ? path.move(to: screen) : path.addLine(to: screen)
                    }
                    for step in stride(from: steps, through: 0, by: -1) {
                        let angle = drawn.start + drawn.sweep * CGFloat(step) / CGFloat(steps)
                        let point = card.point(radius: metrics.sectorInset, angle: angle)
                        path.addLine(to: CGPoint(x: centre.x + point.x, y: centre.y + point.y))
                    }
                    path.closeSubpath()
                    context.fill(path, with: .color(lit
                        ? CompassTheme.vermilion.swiftUI(alpha: 0.30)
                        : CompassTheme.ink.swiftUI(alpha: 0.06)))
                    context.stroke(path, with: .color(lit
                        ? CompassTheme.vermilion.swiftUI(alpha: 0.90)
                        : CompassTheme.ink.swiftUI(alpha: 0.20)), lineWidth: 0.8)
                }

                // Needle, pointing at the first slot.
                var needle = Path()
                let tip = CGPoint(x: centre.x, y: centre.y - metrics.cardRadius * 0.60)
                needle.move(to: tip)
                needle.addLine(to: CGPoint(x: centre.x - side * 0.030, y: centre.y + metrics.cardRadius * 0.42))
                needle.addLine(to: CGPoint(x: centre.x + side * 0.030, y: centre.y + metrics.cardRadius * 0.42))
                needle.closeSubpath()
                context.fill(needle, with: .color(CompassTheme.vermilion.swiftUI().opacity(filled ? 1 : 0.30)))

                // Hub.
                context.fill(
                    Path(ellipseIn: CGRect(
                        x: centre.x - metrics.hubRadius,
                        y: centre.y - metrics.hubRadius,
                        width: metrics.hubRadius * 2,
                        height: metrics.hubRadius * 2
                    )),
                    with: .color(CompassTheme.brassDark.swiftUI())
                )
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Slot gutter

/// The row's slot number, with the slot's *bearing* on the dial behind it.
///
/// At 26pt a wedge is unreadable — the old design drew all nine and they collapsed into a
/// smudge. What still reads at this size is a single pip at the slot's own bearing, which is
/// the one thing a plain table cannot say: where this bookmark sits.
struct SlotGutter: View {
    let slot: Int
    /// Slice index within its own page, or nil for a row with no slot.
    let sliceIndex: Int?
    var sliceCount = RadialLayout.maxSlicesPerPage
    var emphasised = false

    private var isLit: Bool { sliceIndex != nil }

    private var helpText: String {
        guard let sliceIndex else { return "No slot" }
        return "Slot \(slot) — bearing \(sliceIndex + 1) of \(sliceCount) on the dial"
    }

    var body: some View {
        ZStack {
            if let sliceIndex {
                GeometryReader { proxy in
                    let side = min(proxy.size.width, proxy.size.height)
                    Canvas { context, size in
                        let centre = CGPoint(x: size.width / 2, y: size.height / 2)
                        let ring = RadialLayout(
                            sliceCount: max(2, sliceCount),
                            centerRadius: side * 0.30,
                            outerRadius: side * 0.44,
                            hubGap: side * 0.035
                        )
                        context.stroke(
                            Path(ellipseIn: CGRect(
                                x: centre.x - ring.outerRadius,
                                y: centre.y - ring.outerRadius,
                                width: ring.outerRadius * 2,
                                height: ring.outerRadius * 2
                            )),
                            with: .color(Palette.bone.opacity(0.16)),
                            lineWidth: 1
                        )
                        let bearing = ring.centerAngle(of: sliceIndex)
                        let pip = ring.point(radius: ring.outerRadius, angle: bearing)
                        context.fill(
                            Path(ellipseIn: CGRect(
                                x: centre.x + pip.x - 2.6,
                                y: centre.y + pip.y - 2.6,
                                width: 5.2,
                                height: 5.2
                            )),
                            with: .color(emphasised ? Palette.signal : Palette.bone.opacity(0.85))
                        )
                    }
                    .frame(width: side, height: side)
                    .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                }
            }
            Text("\(slot)")
                .font(Palette.mono(isLit ? 8.5 : 12.5, isLit ? .semibold : .medium))
                .foregroundStyle(isLit
                    ? (emphasised ? Palette.bone : Palette.boneDim)
                    : Palette.boneFaint)
                .monospacedDigit()
        }
        .frame(width: 26, height: 26)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: emphasised)
        .help(helpText)
    }
}
