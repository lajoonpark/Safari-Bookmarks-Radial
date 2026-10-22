import SwiftUI
import RadialCore

/// The main window: manage the bookmarks, in the exact order the radial presents them.
struct BookmarkManagerView: View {
    @ObservedObject var model: BookmarkListModel
    @ObservedObject var settings: SettingsModel

    @State private var newTitle = ""
    @State private var newURL = ""
    @State private var errorText: String?
    @State private var editing: Bookmark?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Palette.stroke)
            addBar
            Divider().overlay(Palette.stroke)
            content
            Divider().overlay(Palette.stroke)
            footer
        }
        .background(Palette.background)
        .frame(minWidth: 720, minHeight: 520)
        .sheet(item: $editing) { bookmark in
            EditBookmarkSheet(bookmark: bookmark) { title, url in
                model.update(id: bookmark.id, title: title, url: url)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Safari Radial")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Palette.primaryText)
                Text(subtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.secondaryText)
            }
            Spacer()
            searchField
            Button {
                model.syncFromSafari()
            } label: {
                Label("Import from Safari", systemImage: "arrow.down.circle")
            }
            .buttonStyle(SpringyButtonStyle())
            .help("Pull in your current Safari bookmarks, keeping existing positions")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var subtitle: String {
        let count = model.bookmarks.count
        guard count > 0 else { return "No bookmarks yet" }
        let pages = RadialPaging(total: count).pageCount
        let pageText = pages == 1 ? "1 page" : "\(pages) pages"
        let hotkey = settings.preferences.hotkey.displayName
        return "\(count) bookmark\(count == 1 ? "" : "s") · \(pageText) · press \(hotkey) anywhere"
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Palette.tertiaryText)
            TextField("Search", text: $model.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Palette.primaryText)
                .frame(width: 130)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Palette.stroke, lineWidth: 1)
        )
    }

    // MARK: - Add

    private var addBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField("Title (optional)", text: $newTitle)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(fieldBackground)
                    .frame(width: 190)

                TextField("Paste a link, e.g. github.com/openai", text: $newURL)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(fieldBackground)
                    .onSubmit(commitNew)

                Button("Add", action: commitNew)
                    .buttonStyle(AccentButtonStyle())
                    .disabled(newURL.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if let errorText {
                Label(errorText, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.danger)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .animation(.spring(response: 0.32, dampingFraction: 0.8), value: errorText)
    }

    private var fieldBackground: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Palette.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Palette.stroke, lineWidth: 1)
            )
    }

    private func commitNew() {
        let trimmedURL = newURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty else { return }
        if let error = model.add(title: newTitle, url: trimmedURL) {
            errorText = error
            return
        }
        errorText = nil
        newTitle = ""
        newURL = ""
    }

    // MARK: - List

    @ViewBuilder
    private var content: some View {
        if model.bookmarks.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { offset, bookmark in
                        row(for: bookmark, displayIndex: offset)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            }
        }
    }

    /// Visible rows, tagged with their real slot so search results keep the true number.
    private var rows: [Bookmark] { model.filtered }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "circle.hexagongrid")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(Palette.tertiaryText)
            Text("Your radial is empty")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Palette.primaryText)
            Text("Import from Safari, or add a link above.\nThe first nine fill page one.")
                .font(.system(size: 11.5))
                .multilineTextAlignment(.center)
                .foregroundStyle(Palette.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func row(for bookmark: Bookmark, displayIndex: Int) -> some View {
        let slot = model.slotNumber(for: bookmark)
        let isSelected = model.selectedID == bookmark.id

        return HStack(spacing: 12) {
            slotBadge(slot)

            VStack(alignment: .leading, spacing: 2) {
                Text(bookmark.displayTitle)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Palette.primaryText)
                    .lineLimit(1)
                Text(bookmark.url)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Palette.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            if !bookmark.folder.isEmpty {
                Text(bookmark.folder)
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.tertiaryText)
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(Color.white.opacity(0.06))
                    )
            }

            Spacer(minLength: 6)

            HStack(spacing: 4) {
                iconButton("chevron.up", help: "Move up") {
                    model.moveSlot(of: bookmark, by: -1)
                }
                .disabled(displayIndex == 0)

                iconButton("chevron.down", help: "Move down") {
                    model.moveSlot(of: bookmark, by: 1)
                }
                .disabled(displayIndex == rows.count - 1)

                iconButton("arrow.up.right.square", help: "Open in Safari") {
                    model.openBookmark(bookmark)
                }
                iconButton("pencil", help: "Edit") {
                    editing = bookmark
                }
                iconButton("trash", help: "Remove", tint: Palette.danger) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        model.remove(bookmark)
                    }
                }
            }
            .opacity(isSelected ? 1 : 0.62)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? Palette.surfaceRaised : Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isSelected ? Palette.accent.opacity(0.55) : Palette.stroke, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { model.selectedID = bookmark.id }
        .onHover { hovering in
            if hovering { model.selectedID = bookmark.id }
        }
        .contextMenu {
            Button("Open in Safari") { model.openBookmark(bookmark) }
            Button("Edit…") { editing = bookmark }
            Divider()
            Button("Remove", role: .destructive) { model.remove(bookmark) }
        }
    }

    private func slotBadge(_ slot: Int?) -> some View {
        // Slots 1–9 are what you actually type, so they get the loud treatment.
        let inFirstPage = (slot ?? 99) <= RadialLayout.maxSlicesPerPage
        return Text(slot.map(String.init) ?? "–")
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(inFirstPage ? Palette.primaryText : Palette.tertiaryText)
            .frame(width: 26, height: 22)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(inFirstPage ? Color.white.opacity(0.10) : Color.white.opacity(0.03))
            )
    }

    private func iconButton(_ systemName: String, help: String, tint: Color = Palette.secondaryText,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 24, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 10) {
            if let message = model.syncMessage {
                Label(message.text, systemImage: message.isError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(message.isError ? Palette.danger : Palette.success)
                    .transition(.opacity)
            } else {
                Text("Order is the layout — slice 1 is the first row.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Palette.tertiaryText)
            }

            Spacer()

            if !model.hasFullDiskAccess {
                Button("Grant Full Disk Access") {
                    model.openFullDiskAccessSettings()
                }
                .buttonStyle(SpringyButtonStyle(tint: Palette.accentWarm.opacity(0.22)))
                .help("Safari's bookmark file is protected by macOS; the app needs this permission to read it")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: model.syncMessage)
    }
}

/// Small edit sheet. Deliberately minimal: title plus URL, live URL validation.
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

    private var isValid: Bool {
        Bookmark.normalizedURL(url) != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Edit bookmark")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Palette.primaryText)

            VStack(alignment: .leading, spacing: 6) {
                Text("Title")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Palette.secondaryText)
                TextField("Title", text: $title)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Link")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Palette.secondaryText)
                TextField("https://…", text: $url)
                    .textFieldStyle(.roundedBorder)
                if !url.isEmpty && !isValid {
                    Text("Needs to be an http or https address.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Palette.danger)
                }
            }

            if let error {
                Text(error)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Palette.danger)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(SpringyButtonStyle())
                Button("Save") {
                    if let message = onSave(title, url) {
                        error = message
                    } else {
                        dismiss()
                    }
                }
                .buttonStyle(AccentButtonStyle(isEnabled: isValid))
                .disabled(!isValid)
            }
        }
        .padding(20)
        .frame(width: 380)
        .background(Palette.background)
    }
}
