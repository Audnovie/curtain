// Choosing a countdown's colours: ready-made sets, your own with the system colour picker,
// or colours taken from a picture of your wallpaper.

import SwiftUI
import CurtainCore

/// A card with example content, to judge a colour set by.
struct ThemePreviewCard: View {
    let theme: Theme
    var name = "Done work"

    var body: some View {
        let event = Event(name: name, mode: .countdown, date: Date(timeIntervalSinceReferenceDate: 22_500),
                          theme: theme, createdAt: Date(timeIntervalSinceReferenceDate: 0))
        // Frozen at 6 hr, 15 min to go, so the preview doesn't move while colours are being picked.
        EventCard(event: event, now: Date(timeIntervalSinceReferenceDate: 0))
            .frame(maxWidth: 190)
    }
}

struct ThemePickerView: View {
    @EnvironmentObject private var store: Store
    @Binding var theme: Theme
    var sampleName = "Done work"

    private let columns = [GridItem(.adaptive(minimum: 68), spacing: 10)]

    var body: some View {
        List {
            Section {
                ThemePreviewCard(theme: theme, name: sampleName)
                    .frame(maxWidth: .infinity)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            Section("Ready-made") {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(Theme.presets, id: \.name) { preset in
                        swatchButton(preset)
                    }
                }
                .padding(.vertical, 4)
            }

            if !store.state.savedThemes.isEmpty {
                Section {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(Array(store.state.savedThemes.enumerated()), id: \.offset) { _, kept in
                            swatchButton(kept)
                                .contextMenu {
                                    Button("Remove", role: .destructive) {
                                        store.update { $0.forget(theme: kept) }
                                    }
                                }
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Kept")
                } footer: {
                    Text("Touch and hold one to remove it.")
                }
            }

            Section {
                NavigationLink {
                    WallpaperMatchView(theme: $theme, sampleName: sampleName)
                } label: {
                    Label("Match my wallpaper", systemImage: "photo.on.rectangle.angled")
                }
                .accessibilityIdentifier("theme.wallpaper")
            } footer: {
                Text("Takes the main colours from a screenshot of your Home Screen.")
            }

            Section {
                ColorPicker("Background", selection: backgroundBinding, supportsOpacity: false)
                Toggle("Blend into a second colour", isOn: blendBinding)
                if theme.background2 != nil {
                    ColorPicker("Second colour", selection: secondBinding, supportsOpacity: false)
                }
                ColorPicker("Text", selection: textBinding, supportsOpacity: false)
                ColorPicker("Blocks", selection: accentBinding, supportsOpacity: false)
                if !readable {
                    HStack {
                        Label("The text is hard to read on this background.", systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                        Spacer()
                        Button("Fix") { fixText() }
                            .buttonStyle(.borderless)
                    }
                }
                Button("Keep this colour set") {
                    store.update { $0.keep(theme: theme) }
                }
                .disabled(isKeptOrPreset)
                .accessibilityIdentifier("theme.keep")
            } header: {
                Text("Your own")
            } footer: {
                Text("The colour picker has a spectrum, a grid, sliders, and an eyedropper for lifting a colour off the screen. Lock Screen widgets don't use these colours: iOS tints those itself.")
            }
        }
        .navigationTitle("Colours")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func swatchButton(_ candidate: Theme) -> some View {
        let chosen = theme.sameColours(as: candidate)
        return Button {
            theme = candidate
        } label: {
            VStack(spacing: 4) {
                ThemeChip(theme: candidate, size: 44)
                    .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: chosen ? 3 : 0).padding(-4))
                Text(candidate.name)
                    .font(.caption2)
                    .lineLimit(1)
                    .foregroundStyle(chosen ? Color.primary : Color.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(candidate.name)
        .accessibilityAddTraits(chosen ? .isSelected : [])
        .accessibilityIdentifier("theme." + candidate.name)
    }

    private var readable: Bool {
        Contrast.ratio(theme.foreground, theme.background) >= Contrast.readable
            && Contrast.ratio(theme.foreground, theme.background2 ?? theme.background) >= Contrast.readable
    }

    private var isKeptOrPreset: Bool {
        Theme.presets.contains { $0.sameColours(as: theme) } || store.state.savedThemes.contains { $0.sameColours(as: theme) }
    }

    /// Any hand edit turns the set into a custom one.
    private func edit(_ change: (inout Theme) -> Void) {
        var t = theme
        change(&t)
        if !t.sameColours(as: theme) { t.name = "Custom" }
        theme = t
    }

    private func fixText() {
        edit { t in
            // Judge by whichever end of the blend is harder to read on.
            let white = min(Contrast.ratio(.white, t.background), Contrast.ratio(.white, t.background2 ?? t.background))
            let dark = min(Contrast.ratio(Contrast.darkText, t.background),
                           Contrast.ratio(Contrast.darkText, t.background2 ?? t.background))
            t.foreground = white >= dark ? .white : Contrast.darkText
            t.accent = Contrast.visibleAccent(t.accent, on: t.background)
        }
    }

    private var backgroundBinding: Binding<Color> {
        Binding(get: { theme.background.color }, set: { new in edit { $0.background = RGB(new) } })
    }

    private var secondBinding: Binding<Color> {
        Binding(get: { (theme.background2 ?? theme.background).color }, set: { new in edit { $0.background2 = RGB(new) } })
    }

    private var textBinding: Binding<Color> {
        Binding(get: { theme.foreground.color }, set: { new in edit { $0.foreground = RGB(new) } })
    }

    private var accentBinding: Binding<Color> {
        Binding(get: { theme.accent.color }, set: { new in edit { $0.accent = RGB(new) } })
    }

    private var blendBinding: Binding<Bool> {
        Binding(get: { theme.background2 != nil }, set: { on in
            edit { t in
                if on {
                    t.background2 = ColorMath.withLightness(t.background, max(0.05, ColorMath.lab(t.background).l - 0.08))
                } else {
                    t.background2 = nil
                }
            }
        })
    }
}
