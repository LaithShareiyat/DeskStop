import SwiftUI

/// Settings → General → Choose Picture: the macOS wallpapers and colours on
/// this Mac to hide icons behind, or a picture file of the user's own.
/// Clicking one uses it straight away.
struct PictureGallery: View {
    /// The picture in use, outlined.
    let selected: URL?
    let choose: (URL) -> Void
    let chooseFile: () -> Void
    let cancel: () -> Void

    private let wallpapers = MacWallpapers.pictures()
    private let colours = MacWallpapers.colours()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Choose a Picture")
                    .font(.system(size: 15, weight: .semibold))
                Text("Your desktop icons will be hidden behind it.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(20)

            Divider()

            ScrollViewReader { scroller in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        section("macOS wallpapers", wallpapers)
                        section("Colours", colours)
                        Text("Only wallpapers already on this Mac are listed. macOS downloads the others when you choose them in System Settings › Wallpaper.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(20)
                }
                // The picture in use can be far down the list.
                .onAppear {
                    if let selected { scroller.scrollTo(selected.path, anchor: .center) }
                }
            }

            Divider()

            HStack {
                Button("Choose File", action: chooseFile)
                Spacer()
                Button("Cancel", action: cancel)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(16)
        }
        .frame(width: 620, height: 540)
    }

    @ViewBuilder
    private func section(_ title: String, _ items: [MacWallpapers.Item]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 128), spacing: 14)], spacing: 14) {
                    ForEach(items) { item in
                        PictureTile(item: item, isSelected: item.url.path == selected?.path) {
                            choose(item.url)
                        }
                        .id(item.id)
                    }
                }
            }
        }
    }
}

private struct PictureTile: View {
    let item: MacWallpapers.Item
    let isSelected: Bool
    let action: () -> Void

    @State private var preview: CGImage?

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.secondary.opacity(0.15))
                    .overlay {
                        if let preview {
                            Image(decorative: preview, scale: 2)
                                .resizable()
                                .scaledToFill()
                        }
                    }
                    .frame(height: 76)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.12),
                                          lineWidth: isSelected ? 3 : 1))
                Text(item.name)
                    .font(.system(size: 11))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(item.name)
        .accessibilityLabel(item.name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .task(id: item.url) {
            let url = item.url
            preview = await Task.detached(priority: .userInitiated) {
                HiddenIconsCover.thumbnail(at: url, maxPixelSize: 320)
            }.value
        }
    }
}
