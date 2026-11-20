// "Match my wallpaper": pick a screenshot, get colour sets made from its main colours.
// iOS doesn't let apps see the wallpaper, so the person shows it to the app instead.
// The picture is only looked at here; nothing but the chosen colours is saved.

import SwiftUI
import PhotosUI
import UIKit
import ImageIO
import CurtainCore

struct WallpaperMatchView: View {
    @EnvironmentObject private var store: Store
    @Binding var theme: Theme
    var sampleName = "Done work"

    @State private var item: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var swatches: [Swatch] = []
    @State private var suggestions: [Theme] = []
    @State private var failed = false
    @State private var loading: Task<Void, Never>?

    var body: some View {
        List {
            Section {
                if AppClock.arguments.contains("-UITestWallpaper") {
                    // UI tests can't reach into the photo library, so they get a built-in picture.
                    Button("Choose a screenshot or photo") { use(UIImage(named: "TestWallpaper")) }
                        .accessibilityIdentifier("wallpaper.choose")
                } else {
                    PhotosPicker(selection: $item, matching: .images) {
                        Label(image == nil ? "Choose a screenshot or photo" : "Choose a different picture",
                              systemImage: "photo.on.rectangle")
                    }
                    .accessibilityIdentifier("wallpaper.choose")
                }
                if failed {
                    Text("That picture couldn't be read. Try a screenshot.")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            } footer: {
                Text("A screenshot of your Home Screen works best. The picture isn't kept, only the colours you choose.")
            }

            if let image = image {
                Section {
                    preview(image)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                Section("Colours in the picture") {
                    HStack(spacing: 10) {
                        ForEach(Array(swatches.enumerated()), id: \.offset) { index, swatch in
                            Button {
                                theme = Palette.theme(named: "From wallpaper", background: swatch.color,
                                                      accentFrom: accent(avoiding: swatch.color))
                            } label: {
                                Circle()
                                    .fill(swatch.color.color)
                                    .frame(width: 40, height: 40)
                                    .overlay(Circle().strokeBorder(Color.primary.opacity(0.2), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Colour \(index + 1)")
                            .accessibilityIdentifier("wallpaper.swatch.\(index)")
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Colour sets") {
                    ForEach(Array(suggestions.enumerated()), id: \.offset) { index, suggestion in
                        Button {
                            var chosen = suggestion
                            chosen.name = "From wallpaper"
                            theme = chosen
                        } label: {
                            HStack(spacing: 12) {
                                ThemeChip(theme: suggestion, size: 34)
                                Text(suggestion.name).foregroundStyle(Color.primary)
                                Spacer()
                                if theme.sameColours(as: suggestion) {
                                    Image(systemName: "checkmark").fontWeight(.semibold)
                                }
                            }
                        }
                        .accessibilityIdentifier("wallpaper.set.\(index)")
                    }
                }

                Section {
                    Button("Keep this colour set") {
                        store.update { $0.keep(theme: theme) }
                    }
                    .disabled(store.state.savedThemes.contains { $0.sameColours(as: theme) })
                    .accessibilityIdentifier("wallpaper.keep")
                } footer: {
                    Text("Kept sets show up under Colours for every countdown.")
                }
            }
        }
        .navigationTitle("Match my wallpaper")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: item) { _, picked in
            guard let picked = picked else { return }
            // Only the newest pick counts.
            loading?.cancel()
            loading = Task {
                let data = try? await picked.loadTransferable(type: Data.self)
                // A photo can be very large. It is shrunk off the main thread, without ever
                // being opened at full size, and only the small copy is kept.
                let small = await Task.detached(priority: .userInitiated) {
                    data.flatMap { Picture.thumbnail(from: $0) }
                }.value
                if Task.isCancelled { return }
                use(small)
            }
        }
    }

    /// The picture with a Home Screen widget drawn over it in the current colours.
    private func preview(_ image: UIImage) -> some View {
        ZStack {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(height: 250)
                .frame(maxWidth: .infinity)
                .clipped()
            HomeFace(display: .sample(mode: .countdown), theme: theme)
                .padding(15)
                .frame(width: 158, height: 158)
                .background(theme.fill)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityLabel("How the widget would look on this picture")
    }

    /// A colour from the picture for the blocks, different from the background.
    private func accent(avoiding background: RGB) -> RGB? {
        let lab = ColorMath.lab(background)
        return swatches.map { $0.color }
            .filter { ColorMath.lab($0).distance(to: lab) >= 0.12 }
            .max { ColorMath.lab($0).chroma < ColorMath.lab($1).chroma }
    }

    private func use(_ picked: UIImage?) {
        guard let picked = picked, let pixels = Picture.pixels(of: picked) else {
            failed = true
            return
        }
        let found = Palette.extract(pixels: pixels, width: Picture.side, height: Picture.side)
        failed = found.isEmpty
        image = picked
        swatches = found
        suggestions = Palette.suggestions(from: found)
    }

}

/// Picture handling that needs nothing on screen, so it can run off the main thread.
enum Picture {
    static let side = 100

    /// A copy no more than 1000 pixels on its longer side, made without opening the picture at
    /// full size.
    static func thumbnail(from data: Data) -> UIImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: 1000,
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let small = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: small)
    }

    /// The picture shrunk to a small square of plain RGBA bytes, which is all the colour search needs.
    static func pixels(of image: UIImage) -> [UInt8]? {
        guard let cg = image.cgImage, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        let drawn: Bool = bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8,
                                          bytesPerRow: side * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        return drawn ? bytes : nil
    }
}
