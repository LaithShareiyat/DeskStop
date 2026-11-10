import AppKit
import SwiftUI

/// The look shared by the menu bar panel and the Settings window: translucent
/// cards on the panel's background, hairline borders, an accent-tinted icon
/// column, and small uppercase section titles.
///
/// The background itself depends on the system. With Liquid Glass (macOS 26)
/// the panel and the Settings sidebar keep the system's glass. Before it, both
/// would sit on a thin translucent material that lets the wallpaper show
/// through, so there they are made solid (`systemDrawsLiquidGlass`).
///
/// Fills and borders are tuned per appearance. A card that reads in dark mode
/// at 7% white disappears on a light popover, so each token answers both.
enum PanelStyle {
    static let panelWidth: CGFloat = 340
    static let cardRadius: CGFloat = 10
    static let iconColumn: CGFloat = 22
    static let iconSpacing: CGFloat = 10
    static let rowHorizontalInset: CGFloat = 11
    static let rowVerticalInset: CGFloat = 9

    static func cardFill(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.07) : Color.white.opacity(0.55)
    }

    static func controlFill(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.09) : Color.black.opacity(0.05)
    }

    /// Card outlines. With Increase Contrast on (System Settings →
    /// Accessibility → Display) they are drawn about three times stronger.
    static func border(_ scheme: ColorScheme) -> Color {
        let increased = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        return scheme == .dark
            ? Color.white.opacity(increased ? 0.30 : 0.10)
            : Color.black.opacity(increased ? 0.22 : 0.08)
    }

    static func selectedFill(_ scheme: ColorScheme) -> Color {
        Color.accentColor.opacity(scheme == .dark ? 0.22 : 0.14)
    }

    static func hoverFill(_ scheme: ColorScheme) -> Color {
        Color.primary.opacity(scheme == .dark ? 0.10 : 0.07)
    }

    /// True when the system draws Liquid Glass: macOS 26 or later, in a build
    /// made with the macOS 26 SDK (which Swift 6.2 ships with). An app built
    /// with an older SDK keeps the old materials even on macOS 26.
    static var systemDrawsLiquidGlass: Bool {
        #if compiler(>=6.2)
        if #available(macOS 26, *) { return true }
        #endif
        return false
    }
}

// MARK: - Cards

private struct PanelCardModifier: ViewModifier {
    var padded: Bool
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: PanelStyle.cardRadius, style: .continuous)
        return content
            .padding(padded ? 10 : 0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(shape.fill(PanelStyle.cardFill(scheme)))
            // Clipped so a row's hover tint fills the row edge to edge and
            // still follows the card's rounded corners.
            .clipShape(shape)
            .overlay(shape.strokeBorder(PanelStyle.border(scheme), lineWidth: 0.7))
    }
}

extension View {
    /// Puts content on a rounded panel card. Pass `padded: false` for a card
    /// of rows that pad themselves (`panelRowInsets`).
    func panelCard(padded: Bool = true) -> some View {
        modifier(PanelCardModifier(padded: padded))
    }

    /// Standard insets for one row on a card.
    func panelRowInsets() -> some View {
        padding(.horizontal, PanelStyle.rowHorizontalInset)
            .padding(.vertical, PanelStyle.rowVerticalInset)
    }
}

// MARK: - Small pieces

/// Uppercase section heading; `trailing` holds an optional button.
struct PanelSectionTitle<Trailing: View>: View {
    let text: String
    let trailing: Trailing

    init(_ text: String, @ViewBuilder trailing: () -> Trailing) {
        self.text = text
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(text.uppercased())
                .font(.system(size: 10.5, weight: .semibold))
                .kerning(0.6)
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            trailing
        }
        .padding(.horizontal, 2)
    }
}

extension PanelSectionTitle where Trailing == EmptyView {
    init(_ text: String) {
        self.init(text) { EmptyView() }
    }
}

/// A recorded global shortcut, drawn as a small grey keycap next to the
/// action it triggers.
struct ShortcutPill: View {
    let text: String
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(PanelStyle.controlFill(scheme))
            )
            .accessibilityLabel("Shortcut \(text)")
    }
}

/// "BETA" capsule for experimental features.
struct BetaBadge: View {
    var body: some View {
        Text("BETA")
            .font(.system(size: 8.5, weight: .bold))
            .kerning(0.3)
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(Capsule().fill(Color.accentColor.opacity(0.16)))
            .accessibilityLabel("Beta")
    }
}

/// Fixed-width SF Symbol at the start of a row, so titles line up.
struct PanelRowIcon: View {
    let symbol: String
    var tint: Color = .accentColor

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: PanelStyle.iconColumn)
            .accessibilityHidden(true)
    }
}

/// A row's title (with optional BETA badge) over an optional caption.
struct PanelRowText: View {
    let title: String
    var caption: String?
    var captionColor: Color = .secondary
    var badge: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if badge { BetaBadge() }
            }
            if let caption, !caption.isEmpty {
                Text(caption)
                    .font(.system(size: 11))
                    .foregroundStyle(captionColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Mouse-over tint behind a clickable row. It fills the whole row; the card
/// clips it to its rounded corners, so a one-row card highlights entirely.
struct PanelRowHighlight: View {
    let isVisible: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Rectangle()
            .fill(isVisible ? PanelStyle.hoverFill(scheme) : Color.clear)
    }
}

/// Card for an on/off setting, with its switch on the right.
struct PanelToggleCard: View {
    let symbol: String
    let title: String
    var caption: String?
    var shortcut: String?
    var badge = false
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: PanelStyle.iconSpacing) {
            PanelRowIcon(symbol: symbol)
            PanelRowText(title: title, caption: caption, badge: badge)
            Spacer(minLength: 6)
            if let shortcut { ShortcutPill(text: shortcut) }
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .panelRowInsets()
        .panelCard(padded: false)
    }
}

/// Card that opens a window or runs an action. A chevron on the right marks
/// the cards that open a window; an action that just happens has none.
struct PanelNavigationCard: View {
    let symbol: String
    let title: String
    var caption: String?
    var shortcut: String?
    var badge = false
    var opensWindow = true
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: PanelStyle.iconSpacing) {
                PanelRowIcon(symbol: symbol)
                PanelRowText(title: title, caption: caption, badge: badge)
                Spacer(minLength: 6)
                if let shortcut { ShortcutPill(text: shortcut) }
                if opensWindow {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .panelRowInsets()
            .background(PanelRowHighlight(isVisible: hovering))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .panelCard(padded: false)
    }
}

/// Collapsible heading for one display setup's configurations, showing how
/// many it holds.
struct PanelDisclosureHeader: View {
    let title: String
    let count: Int
    @Binding var isExpanded: Bool

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) { isExpanded.toggle() }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                Text(title.uppercased())
                    .font(.system(size: 10.5, weight: .semibold))
                    .kerning(0.6)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 6)
                Text("\(count)")
                    .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Color.accentColor)
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
    }
}

/// Settings or Quit, at the bottom of the panel.
struct PanelFooterButton: View {
    let title: String
    let symbol: String
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme
    @State private var hovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 12, weight: .medium))
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 30)
                .background(shape.fill(hovering ? PanelStyle.hoverFill(scheme) : PanelStyle.cardFill(scheme)))
                .overlay(shape.strokeBorder(PanelStyle.border(scheme), lineWidth: 0.7))
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .onHover { hovering = $0 }
    }
}

/// The app's mark: the same three-by-three grid as the app icon.
struct BrandMark: View {
    var size: CGFloat = 15

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "square.grid.3x3.fill")
                .font(.system(size: size, weight: .semibold))
            Text("DeskStop")
                .font(.system(size: size, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(.primary)
        .accessibilityElement(children: .combine)
    }
}

/// The app icon on a dark squircle, for Settings' About page.
struct BrandBadge: View {
    var size: CGFloat = 64

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.16), Color(white: 0.05)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            Image(systemName: "square.grid.3x3")
                .font(.system(size: size * 0.46, weight: .medium))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
        .accessibilityHidden(true)
    }
}
