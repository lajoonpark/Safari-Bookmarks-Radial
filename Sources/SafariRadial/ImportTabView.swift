import SwiftUI
import AppKit

/// Safari import, in one place.
///
/// This explanation used to be spread across the header, the footer, Settings and onboarding.
/// The honest framing stays: Full Disk Access is optional, and the cost of skipping it is
/// nothing but this tab.
struct ImportTabView: View {
    @ObservedObject var model: BookmarkListModel
    var onDone: () -> Void

    @State private var granted = false
    @State private var imported = false

    var body: some View {
        VStack(spacing: 22) {
            LockBadge(open: granted)

            Text(title)
                .font(Palette.display(40, .semibold))
                .tracking(-0.6)
                .foregroundStyle(Palette.bone)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text(detail)
                .font(Palette.display(17, .regular))
                .lineSpacing(3)
                .foregroundStyle(Palette.boneDim)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
                .fixedSize(horizontal: false, vertical: true)

            buttons
                .padding(.top, 6)

            if imported, let message = model.syncMessage {
                HStack(spacing: 8) {
                    Image(systemName: message.isError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                    Text(message.text)
                }
                .font(Palette.display(15, .medium))
                .foregroundStyle(message.isError ? Palette.alarm : Palette.mint)
                .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 40)
        .motion(Motion.springSoft, value: granted)
        .motion(Motion.springSoft, value: imported)
        .onAppear {
            granted = model.hasFullDiskAccess
            imported = false
        }
        // Granting happens in System Settings; checking again when the user comes back is what
        // lets the lock open without a reload button.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            granted = model.hasFullDiskAccess
        }
    }

    private var title: String {
        if imported { return "Up to date" }
        return granted ? "Safari is connected" : "Bring your Safari\nbookmarks along"
    }

    private var detail: String {
        if imported { return "Your existing slots never moved. New links were added after them." }
        return granted
            ? "Import now and your Safari bookmarks join the dial. Slots you already arranged keep their place."
            : "Safari keeps them behind a macOS permission. It's optional: the dial, reordering and every setting work without it."
    }

    @ViewBuilder
    private var buttons: some View {
        if imported {
            Button("See the dial", action: onDone)
                .buttonStyle(SignalButtonStyle(size: 15))
        } else if granted {
            Button {
                model.syncFromSafari()
                imported = true
            } label: {
                Label("Import from Safari", systemImage: "arrow.down.to.line")
            }
            .buttonStyle(SignalButtonStyle(size: 15))
        } else {
            HStack(spacing: 12) {
                Button("Open Full Disk Access") { model.openFullDiskAccessSettings() }
                    .buttonStyle(SignalButtonStyle(size: 15))
                Button("Not now", action: onDone)
                    .buttonStyle(QuietButtonStyle(size: 15))
            }
        }
    }
}

/// A brass padlock that opens when access is granted.
private struct LockBadge: View {
    let open: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 30, style: .continuous)
        Image(systemName: open ? "lock.open.fill" : "lock.fill")
            .font(.system(size: 50, weight: .semibold))
            .foregroundStyle(Palette.signalInk)
            .contentTransition(.symbolEffect(.replace))
            .frame(width: 112, height: 112)
            .background(shape.fill(Brass.plate))
            .overlay(shape.strokeBorder(Brass.edge, lineWidth: 0.5))
            .brassSheen(in: shape)
            .shadow(color: Color.black.opacity(0.55), radius: 22, y: 14)
            .scaleEffect(open ? 1.04 : 1)
            .motion(Motion.spring, value: open)
    }
}
