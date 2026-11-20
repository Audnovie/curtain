// What opens when a card is tapped: the countdown up close, and for a reusable one,
// its usual times ready to tap.

import SwiftUI
import CurtainCore

struct EventDetailView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss

    let eventID: UUID
    let onEdit: () -> Void

    @State private var otherTime = AppClock.now
    @State private var remember = false
    @State private var confirmingDelete = false
    @State private var confirmingRestart = false

    var body: some View {
        NavigationStack {
            Group {
                if let event = store.state.event(id: eventID) {
                    list(event)
                } else {
                    MissingView()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit") { onEdit() }
                        .accessibilityIdentifier("detail.edit")
                }
            }
        }
    }

    private func list(_ event: Event) -> some View {
        List {
            Section {
                // The only part that ticks every second.
                TimelineView(.periodic(from: Schedule.wholeMinute(Date()), by: 1)) { context in
                    EventCard(event: event, now: AppClock.now(scheduled: context.date), showSeconds: true, large: true)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            if event.mode == .countdown && event.reusable {
                Section {
                    ForEach(event.usualTimes, id: \.self) { minute in
                        TimelineView(.periodic(from: Schedule.wholeMinute(Date()), by: 60)) { context in
                            usualTimeRow(minute, event: event, now: AppClock.now(scheduled: context.date))
                        }
                    }
                } header: {
                    Text("Set it to")
                } footer: {
                    if event.usualTimes.isEmpty {
                        Text("No usual times yet. Pick a time below and switch on \u{201C}Add to usual times\u{201D}.")
                    }
                }

                Section {
                    DatePicker("Another time", selection: $otherTime, displayedComponents: .hourAndMinute)
                        .accessibilityIdentifier("detail.othertime")
                    Toggle("Add to usual times", isOn: $remember)
                    Button("Set to this time") {
                        let minute = Schedule.minuteOfDay(of: otherTime, calendar: AppClock.calendar)
                        set(event, minute: minute, remember: remember)
                    }
                    .accessibilityIdentifier("detail.setother")
                }
            }

            if event.mode == .since {
                Section {
                    Button("Start again from now") { confirmingRestart = true }
                        .accessibilityIdentifier("detail.restart")
                        .confirmationDialog("Start \u{201C}\(event.name)\u{201D} again from now?",
                                            isPresented: $confirmingRestart, titleVisibility: .visible) {
                            Button("Start again") {
                                let now = AppClock.now
                                store.update { _ = $0.restartSince(id: event.id, from: now, now: now) }
                            }
                            Button("Cancel", role: .cancel) {}
                        }
                }
            }

            Section {
                Button("Delete", role: .destructive) { confirmingDelete = true }
                    .accessibilityIdentifier("detail.delete")
                    .confirmationDialog("Delete \u{201C}\(event.name)\u{201D}?", isPresented: $confirmingDelete,
                                        titleVisibility: .visible) {
                        Button("Delete", role: .destructive) {
                            store.update { $0.delete(ids: [event.id]) }
                            dismiss()
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("This can't be undone.")
                    }
            }
        }
    }

    private func usualTimeRow(_ minute: Int, event: Event, now: Date) -> some View {
        let date = Schedule.next(minuteOfDay: minute, after: now, calendar: AppClock.calendar)
        let running = !Display.isFinished(event, now: now, calendar: AppClock.calendar) && event.date == date
        return Button {
            set(event, minute: minute, remember: false)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Fmt.time(minuteOfDay: minute))
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.primary)
                    Text("\(Fmt.day(date, now: now)), \(Fmt.until(date, now: now))")
                        .font(.footnote)
                        .foregroundStyle(Color.secondary)
                }
                Spacer()
                Image(systemName: running ? "checkmark.circle.fill" : "play.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(running ? Color.green : Color.accentColor)
            }
        }
        .accessibilityIdentifier("usual.\(minute)")
    }

    /// Points the countdown at the next time the clock reads `minute`, and closes the sheet.
    private func set(_ event: Event, minute: Int, remember: Bool) {
        let now = AppClock.now
        let cal = AppClock.calendar
        let date = Schedule.next(minuteOfDay: minute, after: now, calendar: cal)
        store.update { _ = $0.setCountdown(id: event.id, to: date, remember: remember, now: now, calendar: cal) }
        dismiss()
    }
}
