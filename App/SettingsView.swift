// Settings, plus a place to see the widgets and check that they can read the app's data.

import SwiftUI
import CurtainCore

struct SettingsView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Show seconds on cards", isOn: secondsBinding)
                        .accessibilityIdentifier("settings.seconds")
                } footer: {
                    Text("With seconds off, a card rounds up to the minute, the same as the widgets: at 6:50 a countdown to 7:00 says 10 mins. Widgets never show seconds.")
                }

                Section {
                    NavigationLink {
                        ThemePickerView(theme: defaultThemeBinding, sampleName: "New countdown")
                    } label: {
                        HStack {
                            Text("Colours for new countdowns")
                            Spacer()
                            ThemeChip(theme: store.state.settings.defaultTheme)
                        }
                    }
                }

                Section {
                    NavigationLink("See the widgets") {
                        WidgetGalleryView()
                    }
                    .accessibilityIdentifier("settings.gallery")
                    TimelineView(.periodic(from: Schedule.wholeMinute(Date()), by: 60)) { context in
                        widgetStatus(now: AppClock.now(scheduled: context.date))
                    }
                } header: {
                    Text("Widgets")
                } footer: {
                    Text("To add one: touch and hold the Lock Screen, tap Customize, then Lock Screen, then the row under the clock, and choose Curtain. To pick which countdown it shows, tap the widget while still customizing. On the Home Screen: touch and hold an empty spot, tap Edit, then Add Widget.")
                }

                Section {
                    LabeledContent("Version", value: version)
                    LabeledContent("Saved", value: "On this iPhone only")
                } header: {
                    Text("About")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    /// Whether the widgets can see what the app saves, and when one last looked.
    @ViewBuilder
    private func widgetStatus(now: Date) -> some View {
        if !store.location.shared {
            Label("Widgets can't see this app's countdowns. The app was installed without its shared folder (its app group).",
                  systemImage: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(.orange)
                .accessibilityIdentifier("settings.widgetstatus")
        } else if let note = WidgetNote.read(from: store.location) {
            let minutes = TimeMath.unitsPassed(since: note.at, now: now, precision: .minutes)
            let ago = minutes == 0 ? "just now" : Display.compact(TimeMath.split(minutes, precision: .minutes)) + " ago"
            LabeledContent("A widget last updated", value: ago)
                .accessibilityIdentifier("settings.widgetstatus")
        } else {
            LabeledContent("A widget last updated", value: "Not yet")
                .accessibilityIdentifier("settings.widgetstatus")
        }
    }

    private var secondsBinding: Binding<Bool> {
        Binding(get: { store.state.settings.showSeconds },
                set: { on in store.update { $0.settings.showSeconds = on } })
    }

    private var defaultThemeBinding: Binding<Theme> {
        Binding(get: { store.state.settings.defaultTheme },
                set: { theme in store.update { $0.settings.defaultTheme = theme } })
    }
}

/// The widget faces, drawn in the app with the same code the widgets use.
struct WidgetGalleryView: View {
    @EnvironmentObject private var store: Store
    @State private var chosen: UUID?

    var body: some View {
        TimelineView(.periodic(from: Schedule.wholeMinute(Date()), by: 60)) { context in
            gallery(now: AppClock.now(scheduled: context.date))
        }
        .navigationTitle("Widgets")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func gallery(now: Date) -> some View {
        let cal = AppClock.calendar
        let events = store.state.dashboardOrder(now: now, calendar: cal)
        let event = events.first { $0.id == chosen } ?? events.first
        let display = event.map { Display.widget(event: $0, now: now, calendar: cal) } ?? .sample(mode: .countdown)
        let theme = event?.theme ?? store.state.settings.defaultTheme
        return List {
            if events.count > 1 {
                Section {
                    Picker("Countdown", selection: Binding(get: { event?.id }, set: { chosen = $0 })) {
                        ForEach(events) { e in
                            Text(e.name).tag(Optional(e.id))
                        }
                    }
                }
            }

            Section {
                LockScreenMock(now: now) {
                    InlineFace(display: display)
                } rect: {
                    LockRectFace(display: display)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            } header: {
                Text("Lock Screen")
            } footer: {
                Text("iOS tints Lock Screen widgets itself, to suit your wallpaper. The line above the clock is a second, smaller widget.")
            }

            Section {
                HStack(spacing: 12) {
                    homeTile(HomeFace(display: display, theme: theme), theme: theme, width: 158)
                    Spacer(minLength: 0)
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                .listRowBackground(Color.clear)
                homeTile(HomeFace(display: display, theme: theme,
                                  caption: event.map { Fmt.longCaption($0, now: now) }, wide: true),
                         theme: theme, width: 338)
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)
            } header: {
                Text("Home Screen")
            }

            Section {
                ForEach(WidgetGalleryView.moments, id: \.0) { moment in
                    HStack {
                        Text(moment.0).font(.footnote).foregroundStyle(.secondary).frame(width: 96, alignment: .leading)
                        LockRectFace(display: moment.1)
                            .foregroundStyle(.white)
                            .frame(width: 160, height: 72)
                            .padding(10)
                            .background(LockScreenMock<EmptyView, EmptyView>.wallpaper)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .environment(\.colorScheme, .dark)
                }
            } header: {
                Text("Other moments")
            }
        }
    }

    private func homeTile<Content: View>(_ content: Content, theme: Theme, width: CGFloat) -> some View {
        content
            .padding(15)
            .frame(width: width, height: 158)
            .background(theme.fill)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    /// Examples of the states a Lock Screen widget goes through.
    static let moments: [(String, WidgetDisplay)] = [
        ("A full shift", WidgetDisplay(title: "Done work", timeText: "8 hr", bar: Bar(unit: .hour, full: 8, partial: 0),
                                      state: .running, mode: .countdown)),
        ("Last hour", WidgetDisplay(title: "Done work", timeText: "42 min", bar: Bar(unit: .hour, full: 0, partial: 0.7),
                                   state: .running, mode: .countdown)),
        ("Ended", WidgetDisplay(title: "Done work", timeText: "Finished", bar: .empty, state: .finished, mode: .countdown,
                               hint: "Tap to set again")),
        ("Days away", WidgetDisplay(title: "Holiday", timeText: "12 days, 5 hr",
                                   bar: Bar(unit: .day, full: 12, partial: 5.0 / 24.0), state: .running, mode: .countdown)),
        ("Time since", WidgetDisplay(title: "New phone", timeText: "3 days, 4 hr",
                                    bar: Bar(unit: .day, full: 3, partial: 4.0 / 24.0), state: .running, mode: .since)),
    ]
}

/// A stand-in Lock Screen: wallpaper, date line, clock, and the widget row under it.
struct LockScreenMock<Inline: View, Rect: View>: View {
    let now: Date
    @ViewBuilder let inline: () -> Inline
    @ViewBuilder let rect: () -> Rect

    static var wallpaper: LinearGradient {
        LinearGradient(colors: [Color(red: 0.03, green: 0.09, blue: 0.33), Color(red: 0.15, green: 0.36, blue: 0.44)],
                       startPoint: .top, endPoint: .bottom)
    }

    var body: some View {
        VStack(spacing: 4) {
            inline()
                .font(.system(size: 17, weight: .semibold))
                .lineLimit(1)
            Text(Fmt.time(now).replacingOccurrences(of: " AM", with: "").replacingOccurrences(of: " PM", with: ""))
                .font(.system(size: 78, weight: .semibold, design: .rounded))
                .opacity(0.9)
            HStack {
                rect()
                    .frame(width: 160, height: 72)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 28)
            .padding(.top, 4)
        }
        .foregroundStyle(.white)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
        .background(LockScreenMock.wallpaper)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .environment(\.colorScheme, .dark)
    }
}
