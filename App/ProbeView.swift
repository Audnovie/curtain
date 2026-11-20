// Not part of the app. A screen the UI tests open (-UITestProbe) to see exactly what iOS's own
// self-updating clock text prints on this version of iOS. The widgets lean on that text, and it
// is Apple's to change, so the tests write down what it says.

#if DEBUG
import SwiftUI
import CurtainCore

struct ProbeView: View {
    let start = Date()

    /// Seconds from `start`. The odd 50 seconds leave time to read the text before it ticks.
    private let relative: [(String, TimeInterval)] = [
        ("in-0h-0m-50s", 50), ("in-1h-0m-50s", 3650), ("in-2h-0m-50s", 7250), ("in-5h-15m-50s", 18950),
        ("in-23h-59m-50s", 86390), ("in-24h-0m-50s", 86450), ("in-25h-0m-50s", 90050), ("in-48h-0m-50s", 172850),
        ("in-7d-0h-0m-50s", 604850), ("in-8d-5h-30m", 711000), ("in-40d-3h", 3466800),
        ("ago-1h-0m-10s", -3610), ("ago-2h-20m-30s", -8430), ("ago-25h-30m", -91800), ("ago-9d-2h-30m", -786600),
    ]

    private let offsets: [(String, TimeInterval)] = [
        ("in-0h-0m-50s", 50), ("in-0h-10m-50s", 650), ("in-2h-0m-50s", 7250), ("in-5h-15m-50s", 18950),
        ("ago-2h-20m-30s", -8430),
    ]

    private var reference: Date { start.addingTimeInterval(18950) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 5) {
                Text("probe").accessibilityIdentifier("probe.ready")
                ForEach(relative, id: \.0) { item in
                    HStack {
                        Text(item.0).frame(width: 150, alignment: .leading)
                        Text(start.addingTimeInterval(item.1), style: .relative)
                            .accessibilityIdentifier("probe.relative." + item.0)
                    }
                }
                HStack {
                    Text("upper case").frame(width: 150, alignment: .leading)
                    Text(reference, style: .relative)
                        .textCase(.uppercase)
                        .accessibilityIdentifier("probe.upper")
                }
                ForEach(offsets, id: \.0) { item in
                    HStack {
                        Text("offset " + item.0).frame(width: 150, alignment: .leading)
                        Text(.currentDate, format: SystemFormatStyle.DateOffset(
                            to: start.addingTimeInterval(item.1), allowedFields: [.hour, .minute],
                            maxFieldCount: 2, sign: .never))
                            .accessibilityIdentifier("probe.offset." + item.0)
                    }
                }
                faces
            }
            .font(.system(size: 12))
            .padding()
        }
    }

    /// The widget faces with iOS's counting text in them, as a widget draws them for most of a day.
    private var faces: some View {
        let down = WidgetDisplay.sample(mode: .countdown)
        let up = WidgetDisplay.sample(mode: .since)
        return VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 12) {
                InlineFace(display: down, live: reference)
                    .font(.system(size: 17, weight: .semibold))
                    .accessibilityIdentifier("probe.face.inline")
                HStack(spacing: 12) {
                    LockRectFace(display: down, live: reference)
                        .frame(width: 160, height: 72)
                        .accessibilityIdentifier("probe.face.lock")
                    LockRectFace(display: up, live: start.addingTimeInterval(-8430))
                        .frame(width: 160, height: 72)
                        .accessibilityIdentifier("probe.face.lock-since")
                }
            }
            .foregroundStyle(.white)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LockScreenMock<EmptyView, EmptyView>.wallpaper)
            .environment(\.colorScheme, .dark)
            HStack(spacing: 12) {
                tile(HomeFace(display: down, theme: .ember, live: reference), theme: .ember, width: 158)
                    .accessibilityIdentifier("probe.face.home")
                tile(HomeFace(display: down, theme: .ocean), theme: .ocean, width: 158)
            }
            tile(HomeFace(display: down, theme: .ember, caption: "Ends 9:00 PM", wide: true, live: reference),
                 theme: .ember, width: 338)
                .accessibilityIdentifier("probe.face.home-wide")
        }
    }

    private func tile<Content: View>(_ content: Content, theme: Theme, width: CGFloat) -> some View {
        content
            .padding(15)
            .frame(width: width, height: 158)
            .background(theme.fill)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}
#endif
