// Making a new countdown, or changing one.

import SwiftUI
import CurtainCore

struct EventEditorView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss

    let isNew: Bool
    @State private var draft: Event
    @State private var newUsualTime: Date
    @State private var confirmingDelete = false

    init(event: Event, isNew: Bool) {
        self.isNew = isNew
        _draft = State(initialValue: event)
        // The "add a usual time" wheel starts at 5:00 PM.
        let cal = AppClock.calendar
        let five = cal.date(bySettingHour: 17, minute: 0, second: 0, of: AppClock.now) ?? AppClock.now
        _newUsualTime = State(initialValue: five)
    }

    private var canBeReusable: Bool { draft.mode == .countdown && !draft.allDay }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    EventCard(event: draft.normalized(calendar: AppClock.calendar), now: AppClock.now)
                        .frame(maxWidth: 190)
                        .frame(maxWidth: .infinity)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                Section {
                    TextField(draft.mode == .countdown ? "Name, like Done work" : "Name, like New job", text: $draft.name)
                        .accessibilityIdentifier("editor.name")
                    Picker("Kind", selection: $draft.mode) {
                        Text("Countdown").tag(EventMode.countdown)
                        Text("Time since").tag(EventMode.since)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("editor.kind")
                }

                Section {
                    Toggle("All day", isOn: $draft.allDay)
                    if draft.mode == .countdown {
                        DatePicker("Ends", selection: $draft.date,
                                   displayedComponents: draft.allDay ? [.date] : [.date, .hourAndMinute])
                            .accessibilityIdentifier("editor.date")
                    } else {
                        DatePicker("Began", selection: $draft.date, in: ...AppClock.now,
                                   displayedComponents: draft.allDay ? [.date] : [.date, .hourAndMinute])
                            .accessibilityIdentifier("editor.date")
                    }
                } footer: {
                    if draft.mode == .countdown && Display.isFinished(draft.normalized(calendar: AppClock.calendar),
                                                                      now: AppClock.now, calendar: AppClock.calendar) {
                        Text("That time has already passed, so this will show as finished.")
                    }
                }

                if canBeReusable {
                    Section {
                        Toggle("Reusable", isOn: $draft.reusable)
                            .accessibilityIdentifier("editor.reusable")
                        if draft.reusable {
                            ForEach(draft.usualTimes, id: \.self) { minute in
                                HStack {
                                    Text(Fmt.time(minuteOfDay: minute))
                                    Spacer()
                                    Button {
                                        draft.usualTimes.removeAll { $0 == minute }
                                    } label: {
                                        Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                                    }
                                    .buttonStyle(.borderless)
                                    .accessibilityLabel("Remove \(Fmt.time(minuteOfDay: minute))")
                                }
                            }
                            if draft.usualTimes.count < Event.maxUsualTimes {
                                HStack {
                                    DatePicker("Usual time", selection: $newUsualTime, displayedComponents: .hourAndMinute)
                                    Button("Add") {
                                        let minute = Schedule.minuteOfDay(of: newUsualTime, calendar: AppClock.calendar)
                                        draft.usualTimes = Schedule.tidy(usualTimes: draft.usualTimes + [minute])
                                    }
                                    .buttonStyle(.borderless)
                                    .accessibilityIdentifier("editor.addusual")
                                }
                            }
                        }
                    } footer: {
                        Text("A reusable countdown stays on the dashboard when it ends. Tap it and pick one of its usual times to start it again.")
                    }
                }

                Section {
                    NavigationLink {
                        ThemePickerView(theme: $draft.theme, sampleName: draft.name.isEmpty ? "Countdown" : draft.name)
                    } label: {
                        HStack {
                            Text("Colours")
                            Spacer()
                            Text(draft.theme.name).foregroundStyle(.secondary)
                            ThemeChip(theme: draft.theme)
                        }
                    }
                    .accessibilityIdentifier("editor.colours")
                }

                if !isNew {
                    Section {
                        Button("Delete", role: .destructive) { confirmingDelete = true }
                    }
                }
            }
            .navigationTitle(isNew ? "New" : "Edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .accessibilityIdentifier("editor.save")
                }
            }
            .onChange(of: draft.mode) { _, mode in
                let now = AppClock.now
                if mode == .since && draft.date > now {
                    // A "time since" can't begin in the future.
                    draft.date = Schedule.wholeMinute(now)
                } else if mode == .countdown && isNew && draft.date <= now {
                    draft.date = Schedule.defaultCountdownDate(now: now, calendar: AppClock.calendar)
                }
            }
            .confirmationDialog("Delete \u{201C}\(draft.name)\u{201D}?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    store.update { $0.delete(ids: [draft.id]) }
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This can't be undone.")
            }
        }
    }

    private func save() {
        let now = AppClock.now
        let event = draft
        store.update { $0.upsert(event, now: now, calendar: AppClock.calendar) }
        dismiss()
    }
}
