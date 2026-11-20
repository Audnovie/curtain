// What the widgets look like. These views take everything they draw as plain values, so the app
// can show the same faces in its own "See the widgets" screen and the tests can photograph them.

import SwiftUI
import WidgetKit
import CurtainCore

/// The row of blocks: one per hour (or day, week, ...), the last one partly filled from the bottom.
struct BarView: View {
    let bar: Bar
    var fill: Color
    var track: Color
    var height: CGFloat = 22
    var blockWidth: CGFloat = 10
    var spacing: CGFloat = 5

    var body: some View {
        // Up to a dozen blocks keep their shape; more than that squeeze together to fit.
        HStack(spacing: bar.blocks > 12 ? 2 : spacing) {
            ForEach(0..<max(bar.blocks, 0), id: \.self) { i in
                BlockView(level: i < bar.full ? 1 : bar.partial, fill: fill, track: track, height: height)
                    .frame(minWidth: 3, maxWidth: blockWidth)
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

struct BlockView: View {
    let level: Double
    let fill: Color
    let track: Color
    let height: CGFloat

    var body: some View {
        ZStack(alignment: .bottom) {
            Rectangle().fill(track)
            Rectangle().fill(fill).frame(height: CGFloat(max(0, min(1, level))) * height)
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
    }
}

/// The time line of a face: our own words, or (only if iOS was late fetching the next stretch
/// of a long countdown) a clock text that iOS keeps counting by itself.
struct TimeText: View {
    let text: String
    let live: Date?

    var body: some View {
        if let live = live {
            Text(live, style: .relative)
        } else {
            Text(text)
        }
    }
}

/// The Lock Screen widget: name, time, blocks. iOS draws Lock Screen widgets in one tint of its
/// own choosing, so this only decides how bright each part is.
struct LockRectFace: View {
    let display: WidgetDisplay
    var live: Date? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(display.title)
                .font(.system(size: 12, weight: .bold))
                .textCase(.uppercase)
                .opacity(0.65)
                .lineLimit(1)
            TimeText(text: display.timeText, live: live)
                .font(.system(size: 15, weight: .semibold))
                .textCase(.uppercase)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if display.bar.blocks > 0 {
                BarView(bar: display.bar, fill: .white, track: .white.opacity(0.28), height: 24)
                    .widgetAccentable()
            } else if let hint = display.hint {
                Text(hint)
                    .font(.system(size: 12, weight: .medium))
                    .opacity(0.65)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }
}

/// The single line above the Lock Screen clock.
struct InlineFace: View {
    let display: WidgetDisplay
    var live: Date? = nil

    var body: some View {
        if display.state == .empty {
            Text(display.timeText)
        } else if let live = live {
            Text("\(display.title) · ") + Text(live, style: .relative)
        } else {
            Text("\(display.title) · \(display.timeText)")
        }
    }
}

/// The Home Screen widget, small or medium, in the countdown's own colours.
struct HomeFace: View {
    let display: WidgetDisplay
    let theme: Theme
    /// A line such as "Ends 9:00 PM". Medium size only.
    var caption: String? = nil
    var wide = false
    var live: Date? = nil
    /// False when iOS tints the widget itself (the Tinted and Clear Home Screen looks).
    var fullColour = true

    var body: some View {
        let text = fullColour ? theme.foreground.color : Color.white
        let blocks = fullColour ? theme.accent.color : Color.white
        VStack(alignment: .leading, spacing: 3) {
            Text(display.title)
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(1)
                .opacity(0.9)
            Spacer(minLength: 2)
            if let live = live {
                Text(live, style: .relative)
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .widgetAccentable()
            } else {
                Text(display.primaryText)
                    .font(.system(size: wide ? 34 : 30, weight: .heavy, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .widgetAccentable()
                if !display.secondaryText.isEmpty {
                    Text(display.secondaryText)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .opacity(0.85)
                        .lineLimit(1)
                }
            }
            if display.bar.blocks == 0, let hint = display.hint {
                Text(hint)
                    .font(.system(size: 12, weight: .medium))
                    .opacity(0.75)
                    .lineLimit(1)
            }
            if wide, let caption = caption {
                Text(caption)
                    .font(.system(size: 12, weight: .medium))
                    .opacity(0.7)
                    .lineLimit(1)
            }
            if display.bar.blocks > 0 {
                BarView(bar: display.bar, fill: blocks, track: blocks.opacity(0.28),
                        height: wide ? 20 : 18, blockWidth: wide ? 12 : 9, spacing: 4)
                    .widgetAccentable()
                    .padding(.top, 2)
            }
        }
        .foregroundStyle(text)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }
}
