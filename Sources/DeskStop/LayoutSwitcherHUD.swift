import AppKit
import SwiftUI

/// The overlay Restore Next Layout shows in the middle of the screen, in the
/// spirit of Command-Tab: a tile for each of the display setup's layouts, the
/// one about to be restored highlighted. Each press of the shortcut moves the
/// highlight on, looping back to the first; the highlighted layout is restored
/// once the presses stop (`PresetActionsController.cyclePresets`).
///
/// It never takes focus or clicks: it is a borderless, non-activating panel
/// that ignores the mouse, so the app the user is in stays frontmost.
final class LayoutSwitcherHUD {
    static let shared = LayoutSwitcherHUD()

    struct Tile: Identifiable, Equatable {
        let id: UUID
        let name: String
        let isAutoRestore: Bool
    }

    private let model = Model()
    private lazy var panel: NSPanel = makePanel()
    private var hideWork: DispatchWorkItem?

    final class Model: ObservableObject {
        @Published var setupName = ""
        @Published var setupSymbol = "display"
        @Published var tiles: [Tile] = []
        @Published var selected: UUID?
        @Published var restoring = false
    }

    /// Shows the overlay with `selected` highlighted, or updates it if it is
    /// already up.
    func show(setupName: String, setupSymbol: String, tiles: [Tile], selected: UUID) {
        hideWork?.cancel()
        model.setupName = setupName
        model.setupSymbol = setupSymbol
        model.tiles = tiles
        model.selected = selected
        model.restoring = false
        placeOnActiveScreen()
        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { $0.duration = 0.12; panel.animator().alphaValue = 1 }
        }
    }

    /// The restore has started: say so briefly, then fade out.
    func finish() {
        model.restoring = true
        let work = DispatchWorkItem { [weak self] in self?.hide() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    func hide() {
        hideWork?.cancel()
        guard panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.18; panel.animator().alphaValue = 0 },
                                             completionHandler: { [weak self] in self?.panel.orderOut(nil) })
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: LayoutSwitcherView(model: model))
        panel.contentView = host
        return panel
    }

    /// Centred on the screen the pointer is on, a little above the middle,
    /// where the system's own switcher sits.
    private func placeOnActiveScreen() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame, let content = panel.contentView else { return }
        content.layoutSubtreeIfNeeded()
        let size = content.fittingSize
        let origin = NSPoint(x: frame.midX - size.width / 2,
                             y: frame.midY - size.height / 2 + frame.height * 0.08)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }
}

private struct LayoutSwitcherView: View {
    @ObservedObject var model: LayoutSwitcherHUD.Model

    /// Beyond this many, tiles wrap onto further rows rather than running off
    /// the screen.
    private let perRow = 6

    private var rows: [[LayoutSwitcherHUD.Tile]] {
        stride(from: 0, to: model.tiles.count, by: perRow).map {
            Array(model.tiles[$0..<min($0 + perRow, model.tiles.count)])
        }
    }

    private var selectedName: String {
        model.tiles.first { $0.id == model.selected }?.name ?? ""
    }

    var body: some View {
        VStack(spacing: 14) {
            Label(model.setupName, systemImage: model.setupSymbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            VStack(spacing: 10) {
                ForEach(rows.indices, id: \.self) { index in
                    HStack(spacing: 10) {
                        ForEach(rows[index]) { tile in
                            TileView(tile: tile, isSelected: tile.id == model.selected)
                        }
                    }
                }
            }
            Text(model.restoring
                 ? "Restoring \u{201C}\(selectedName)\u{201D}"
                 : "Press again for the next layout")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .background(HUDBackground())
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .fixedSize()
        .animation(.easeOut(duration: 0.12), value: model.selected)
    }
}

private struct TileView: View {
    let tile: LayoutSwitcherHUD.Tile
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 4) {
            // The auto-restore star sits just under the icon, above the name.
            // Every tile keeps its space, so names stay on one line across
            // the row.
            VStack(spacing: 1) {
                Image(systemName: "square.grid.3x3.fill")
                    .font(.system(size: 30, weight: .regular))
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .frame(width: 56, height: 36)
                Image(systemName: "star.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.accentColor)
                    .frame(height: 11)
                    .opacity(tile.isAutoRestore ? 1 : 0)
                    .accessibilityLabel("Auto-restore layout")
                    .accessibilityHidden(!tile.isAutoRestore)
            }
            Text(tile.name)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .primary : .secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 88)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? Color.primary.opacity(0.14) : Color.clear)
        )
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The dark translucent material macOS uses for its own overlays.
private struct HUDBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
