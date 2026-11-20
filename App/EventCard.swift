// One countdown as a card: name, the big number, the small line, the bar.

import SwiftUI
import CurtainCore

struct EventCard: View {
    let event: Event
    let now: Date
    var showSeconds = false
    /// Larger type, for the top of the detail sheet.
    var large = false
    var selecting = false
    var selected = false

    var body: some View {
        let cal = AppClock.calendar
        let card = Display.card(event: event, now: now, showSeconds: showSeconds, calendar: cal)
        let waiting = card.state == .finished && event.reusable
        let theme = event.theme
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .top, spacing: 5) {
                Text(event.name)
                    .font(.system(size: large ? 20 : 17, weight: .semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                if event.reusable && !selecting {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .bold))
                        .opacity(0.8)
                        .accessibilityLabel("Reusable")
                }
            }
            Spacer(minLength: 10)
            Text(waiting ? "Not running" : card.big)
                .font(.system(size: large ? 44 : 30, weight: .heavy, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            if !card.detail.isEmpty {
                Text(card.detail)
                    .font(.system(size: large ? 20 : 15, weight: .semibold, design: .rounded))
                    .opacity(0.85)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Text(large ? Fmt.longCaption(event, now: now) : Fmt.cardCaption(event, now: now))
                .font(.system(size: large ? 14 : 12, weight: .medium))
                .opacity(0.75)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            let bar = Display.bar(event: event, now: now, calendar: cal)
            if bar.blocks > 0 {
                BarView(bar: bar, fill: theme.accent.color, track: theme.accent.color.opacity(0.28),
                        height: large ? 24 : 18, blockWidth: large ? 12 : 9, spacing: 4)
                    .padding(.top, 4)
            }
        }
        .foregroundStyle(theme.foreground.color)
        .padding(large ? 20 : 14)
        .frame(maxWidth: .infinity, minHeight: large ? 190 : 150, alignment: .topLeading)
        .background(theme.fill)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .opacity(card.state == .finished && !event.reusable && !selecting ? 0.62 : 1)
        .overlay(alignment: .topTrailing) {
            if selecting {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white, selected ? Color.accentColor : Color.black.opacity(0.25))
                    .shadow(radius: 2)
                    .padding(8)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selecting && selected ? .isSelected : [])
    }
}

/// A small round sample of a colour set.
struct ThemeChip: View {
    let theme: Theme
    var size: CGFloat = 28

    var body: some View {
        ZStack {
            Circle().fill(theme.fill)
            Circle().fill(theme.accent.color).frame(width: size * 0.3, height: size * 0.3)
        }
        .frame(width: size, height: size)
        .overlay(Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 1))
        .accessibilityHidden(true)
    }
}
