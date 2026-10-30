import SwiftUI
import RadialCore

/// Every slot, in dial order, with room to breathe.
///
/// Pages are dividers rather than a column, because "which page" is a property of the group,
/// not something to repeat on every row. The slot gutter keeps the bearing pip: the slot number
/// is the interface, it is what you type.
struct LibraryTabView: View {
    @ObservedObject var model: BookmarkListModel
    var onEdit: (Bookmark) -> Void

    @FocusState private var searchFocused: Bool

    private struct PageSection: Identifiable {
        let id: Int
        let rows: [Bookmark]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 56)
                .padding(.bottom, 26)
            content
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                Text(eyebrow)
                    .font(Palette.mono(11, .semibold))
                    .tracking(1.8)
                    .foregroundStyle(Palette.boneFaint)
                Text("Library")
                    .font(Palette.display(46, .semibold))
                    .tracking(-0.8)
                    .foregroundStyle(Palette.bone)
            }
            Spacer()
            searchField
        }
    }

    private var eyebrow: String {
        let count = model.bookmarks.count
        let pages = RadialPaging(total: count).pageCount
        return "\(count) SLOT\(count == 1 ? "" : "S") · \(pages) PAGE\(pages == 1 ? "" : "S")"
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(searchFocused ? Palette.signal : Palette.boneDim)
            TextField("", text: $model.searchText, prompt: hint("Find a slot"))
                .textFieldStyle(.plain)
                .font(Palette.display(16, .regular))
                .foregroundStyle(Palette.bone)
                .focused($searchFocused)
            if !model.searchText.isEmpty {
                Button {
                    model.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Palette.boneFaint)
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 14)
        .frame(width: searchFocused ? 360 : 290, height: 44)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(searchFocused ? Palette.hullLift : Palette.hull)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(searchFocused ? Palette.signal : Palette.rim, lineWidth: searchFocused ? 1.5 : 1)
        )
        .shadow(color: Palette.signal.opacity(searchFocused ? 0.2 : 0), radius: 14)
        .motion(Motion.springSoft, value: searchFocused)
        .motion(Motion.spring, value: model.searchText.isEmpty)
    }

    // MARK: - List

    @ViewBuilder
    private var content: some View {
        if model.bookmarks.isEmpty {
            emptyState
        } else if model.filtered.isEmpty {
            noResults
        } else {
            let sections = pageSections
            let showDividers = model.searchText.trimmingCharacters(in: .whitespaces).isEmpty
            let slots = slotIndex
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(sections) { section in
                        if showDividers {
                            pageDivider(section)
                        }
                        ForEach(section.rows) { bookmark in
                            LibraryRow(
                                bookmark: bookmark,
                                slot: slots[bookmark.id] ?? 0,
                                browserName: model.browserName,
                                isSelected: model.selectedID == bookmark.id,
                                onSelect: { model.selectedID = bookmark.id },
                                onOpen: { model.openBookmark(bookmark) },
                                onEdit: { onEdit(bookmark) },
                                onMove: { delta in
                                    withAnimation(Motion.springSoft) { model.moveSlot(of: bookmark, by: delta) }
                                },
                                onFront: {
                                    withAnimation(Motion.springSoft) { model.moveToFront(bookmark) }
                                },
                                onRemove: {
                                    withAnimation(Motion.springSoft) { model.remove(bookmark) }
                                }
                            )
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .offset(y: -12)),
                                removal: .opacity.combined(with: .offset(x: 40))
                            ))
                        }
                    }
                }
                .padding(.horizontal, 44)
                .padding(.top, 6)
                .padding(.bottom, 120)
            }
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.025),
                        .init(color: .black, location: 0.9),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }

    private var slotIndex: [UUID: Int] {
        var map: [UUID: Int] = [:]
        for (index, bookmark) in model.bookmarks.enumerated() {
            map[bookmark.id] = index + 1
        }
        return map
    }

    private var pageSections: [PageSection] {
        let slots = slotIndex
        var buckets: [Int: [Bookmark]] = [:]
        for bookmark in model.filtered {
            let slot = slots[bookmark.id] ?? 1
            buckets[(slot - 1) / RadialLayout.maxSlicesPerPage, default: []].append(bookmark)
        }
        return buckets.keys.sorted().map { PageSection(id: $0, rows: buckets[$0] ?? []) }
    }

    private func pageDivider(_ section: PageSection) -> some View {
        let first = section.id * RadialLayout.maxSlicesPerPage + 1
        let last = min((section.id + 1) * RadialLayout.maxSlicesPerPage, model.bookmarks.count)
        return HStack(spacing: 14) {
            Text("PAGE \(section.id + 1)")
                .font(Palette.mono(11, .semibold))
                .tracking(1.8)
            Text("slots \(first)–\(last)")
                .font(Palette.mono(11))
                .opacity(0.7)
            Rectangle()
                .fill(LinearGradient(
                    colors: [Palette.rimStrong, Color.clear],
                    startPoint: .leading,
                    endPoint: .trailing
                ))
                .frame(height: 1)
        }
        .foregroundStyle(Palette.boneFaint)
        .padding(.horizontal, 14)
        .padding(.top, section.id == 0 ? 4 : 24)
        .padding(.bottom, 10)
    }

    // MARK: - States

    private var emptyState: some View {
        VStack(spacing: 14) {
            MiniDial(filled: false)
                .frame(width: 150, height: 150)
                .opacity(0.55)
            Text("Your dial is empty")
                .font(Palette.display(22, .semibold))
                .foregroundStyle(Palette.bone)
            Text("Add a link with the + below, or import your Safari bookmarks.")
                .font(Palette.display(16, .regular))
                .foregroundStyle(Palette.boneDim)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 80)
    }

    private var noResults: some View {
        VStack(spacing: 14) {
            Text("Nothing matches “\(model.searchText)”")
                .font(Palette.display(20, .medium))
                .foregroundStyle(Palette.bone)
            Button("Clear the search") { model.searchText = "" }
                .buttonStyle(QuietButtonStyle(size: 14))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 80)
    }
}

// MARK: - Row

private struct LibraryRow: View {
    let bookmark: Bookmark
    let slot: Int
    let browserName: String
    let isSelected: Bool
    let onSelect: () -> Void
    let onOpen: () -> Void
    let onEdit: () -> Void
    let onMove: (Int) -> Void
    let onFront: () -> Void
    let onRemove: () -> Void

    @State private var hovering = false

    private var sliceIndex: Int { (slot - 1) % RadialLayout.maxSlicesPerPage }
    private var lit: Bool { hovering || isSelected }

    var body: some View {
        HStack(spacing: 20) {
            SlotGutter(slot: slot, sliceIndex: sliceIndex, emphasised: lit)
                .scaleEffect(1.3)
                .frame(width: 38, height: 38)

            monogram

            VStack(alignment: .leading, spacing: 3) {
                Text(bookmark.displayTitle)
                    .font(Palette.display(19, .semibold))
                    .foregroundStyle(Palette.bone)
                    .lineLimit(1)
                Text(bookmark.host.isEmpty ? bookmark.url : bookmark.host)
                    .font(Palette.mono(12.5))
                    .foregroundStyle(Palette.boneDim)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 12)

            HStack(spacing: 2) {
                IconButton(systemName: "arrow.up.right", help: "Open in \(browserName)", action: onOpen)
                IconButton(systemName: "pencil", help: "Edit", action: onEdit)
                Menu {
                    Button("Move up") { onMove(-1) }
                    Button("Move down") { onMove(1) }
                    Button("Move to slot 1", action: onFront)
                    Divider()
                    Button("Remove", role: .destructive, action: onRemove)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Palette.boneDim)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("More")
            }
            .opacity(lit ? 1 : 0)
            .offset(x: lit ? 0 : 10)
        }
        .padding(.horizontal, 14)
        .frame(height: 68)
        .background(rowBackground)
        .overlay(alignment: .leading) {
            Capsule()
                .fill(Palette.signal)
                .frame(width: 3)
                .padding(.vertical, 14)
                .scaleEffect(y: lit ? 1 : 0)
        }
        .shadow(color: Color.black.opacity(hovering ? 0.4 : 0), radius: 16, y: 10)
        .offset(y: hovering ? -2 : 0)
        .padding(.bottom, 6)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: onSelect)
        .motion(Motion.spring, value: hovering)
        .motion(Motion.spring, value: isSelected)
        .contextMenu {
            Button("Open in \(browserName)", action: onOpen)
            Button("Edit…", action: onEdit)
            Divider()
            Button("Move to slot 1", action: onFront)
            Divider()
            Button("Remove", role: .destructive, action: onRemove)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Slot \(slot), \(bookmark.displayTitle)")
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(LinearGradient(
                colors: lit
                    ? [Palette.signal.opacity(0.13), Palette.hull.opacity(0.85)]
                    : [Color.clear, Color.clear],
                startPoint: .leading,
                endPoint: UnitPoint(x: 0.45, y: 0.5)
            ))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(lit ? Palette.rim : Color.clear, lineWidth: 1)
            )
    }

    /// A brass tile with the site's initial: recognisable at a glance, and entirely offline.
    private var monogram: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return Text(initial)
            .font(Palette.display(20, .bold))
            .foregroundStyle(Palette.signalInk)
            .frame(width: 42, height: 42)
            .background(shape.fill(Brass.plate))
            .overlay(shape.strokeBorder(Brass.edge, lineWidth: 0.5))
            .shadow(color: Color.black.opacity(0.4), radius: 5, y: 3)
            .rotationEffect(.degrees(hovering ? -6 : 0))
            .scaleEffect(hovering ? 1.08 : 1)
    }

    private var initial: String {
        let source = bookmark.displayTitle
        if let first = source.first(where: { $0.isLetter || $0.isNumber }) {
            return String(first).uppercased()
        }
        return "•"
    }
}
