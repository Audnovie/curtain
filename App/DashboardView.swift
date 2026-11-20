// The main screen: every countdown as a card, two across.

import SwiftUI
import CurtainCore

struct DashboardView: View {
    @EnvironmentObject private var store: Store

    enum Sheet: Identifiable, Equatable {
        case new
        case detail(UUID)
        case edit(UUID)
        case settings

        var id: String {
            switch self {
            case .new: return "new"
            case .detail(let id): return "detail-\(id.uuidString)"
            case .edit(let id): return "edit-\(id.uuidString)"
            case .settings: return "settings"
            }
        }
    }

    @State private var sheet: Sheet?
    @State private var selecting = false
    @State private var selection: Set<UUID> = []
    @State private var confirmingDelete = false
    @State private var hidShareWarning = false

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack {
            // Cards tick once a minute, on the minute (or once a second when seconds are on).
            TimelineView(.periodic(from: Schedule.wholeMinute(Date()), by: store.state.settings.showSeconds ? 1 : 60)) { context in
                content(now: AppClock.now(scheduled: context.date))
            }
            .navigationTitle("Curtain")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if selecting {
                        Button("Done") { stopSelecting() }
                            .fontWeight(.semibold)
                            .accessibilityIdentifier("toolbar.done")
                    } else if !store.state.events.isEmpty {
                        Button("Select") { selecting = true }
                            .accessibilityIdentifier("toolbar.select")
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if !selecting {
                        Button { sheet = .settings } label: { Image(systemName: "gearshape") }
                            .accessibilityLabel("Settings")
                            .accessibilityIdentifier("toolbar.settings")
                        Button { sheet = .new } label: { Image(systemName: "plus") }
                            .accessibilityLabel("New countdown")
                            .accessibilityIdentifier("toolbar.new")
                    }
                }
            }
            .sheet(item: $sheet) { which in
                sheetView(which)
                    .environmentObject(store)
                    .environment(\.timeZone, AppClock.timeZone)
                    .environment(\.calendar, AppClock.calendar)
            }
            .onChange(of: store.openRequest) { _, _ in openRequested() }
            // A widget tap that launched the app arrives before this view is listening.
            .onAppear { openRequested() }
        }
    }

    /// Opens the countdown a widget asked for.
    private func openRequested() {
        guard let id = store.openRequest else { return }
        store.openRequest = nil
        // Don't pull an editor out from under unsaved changes.
        if let open = sheet {
            switch open {
            case .new, .edit: return
            case .detail, .settings: break
            }
        }
        stopSelecting()
        sheet = .detail(id)
    }

    private var deleteTitle: String {
        selection.count == 1 ? "Delete 1 countdown?" : "Delete \(selection.count) countdowns?"
    }

    private func stopSelecting() {
        selecting = false
        selection = []
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        let events = store.state.dashboardOrder(now: now, calendar: AppClock.calendar)
        ScrollView {
            VStack(spacing: 12) {
                if let notice = store.notice {
                    NoticeBanner(text: notice) { store.notice = nil }
                }
                if !store.location.shared && !hidShareWarning {
                    NoticeBanner(text: "Widgets can't see these countdowns yet. This copy of the app was installed without the folder it shares with its widgets (its app group), so a widget will say \u{201C}Open Curtain\u{201D}. It needs installing again with that group included.") {
                        hidShareWarning = true
                    }
                    .accessibilityIdentifier("notice.noshare")
                }
                if events.isEmpty {
                    emptyState
                } else {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(events) { event in
                            Button {
                                tap(event)
                            } label: {
                                EventCard(event: event, now: now, showSeconds: store.state.settings.showSeconds,
                                          selecting: selecting, selected: selection.contains(event.id))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("card." + event.name)
                        }
                    }
                }
            }
            .padding(.horizontal, 15)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .safeAreaInset(edge: .bottom) {
            if selecting {
                selectionBar(now: now)
            }
        }
    }

    private func tap(_ event: Event) {
        if selecting {
            if selection.contains(event.id) {
                selection.remove(event.id)
            } else {
                selection.insert(event.id)
            }
        } else {
            sheet = .detail(event.id)
        }
    }

    private func selectionBar(now: Date) -> some View {
        let finished = store.state.finishedIDs(now: now, calendar: AppClock.calendar)
        return HStack {
            Button("Select finished") { selection = finished }
                .disabled(finished.isEmpty)
                .accessibilityIdentifier("select.finished")
            Spacer()
            Button(role: .destructive) {
                confirmingDelete = true
            } label: {
                Text(selection.isEmpty ? "Delete" : "Delete (\(selection.count))")
                    .fontWeight(.semibold)
            }
            .disabled(selection.isEmpty)
            .accessibilityIdentifier("select.delete")
            .confirmationDialog(deleteTitle, isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    let ids = selection
                    store.update { $0.delete(ids: ids) }
                    stopSelecting()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This can't be undone.")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.bar)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "hourglass")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("No countdowns yet")
                .font(.title3.weight(.semibold))
            Text("Count down to something, or count up from it.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                sheet = .new
            } label: {
                Text("New countdown").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier("empty.new")
            Button {
                addDoneWork()
            } label: {
                Text("Add \u{201C}Done work\u{201D} with 5, 7 and 9 PM").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .accessibilityIdentifier("empty.donework")
        }
        .padding(.top, 60)
        .padding(.horizontal, 20)
    }

    /// A reusable end-of-shift countdown in one tap, then straight to choosing today's time.
    private func addDoneWork() {
        let now = AppClock.now
        let event = Event(name: "Done work", mode: .countdown, date: Schedule.wholeMinute(now), reusable: true,
                          usualTimes: [17 * 60, 19 * 60, 21 * 60], theme: store.state.settings.defaultTheme, createdAt: now)
        store.update { $0.upsert(event, now: now, calendar: AppClock.calendar) }
        sheet = .detail(event.id)
    }

    @ViewBuilder
    private func sheetView(_ which: Sheet) -> some View {
        switch which {
        case .new:
            let now = AppClock.now
            EventEditorView(event: Event(name: "", mode: .countdown,
                                         date: Schedule.defaultCountdownDate(now: now, calendar: AppClock.calendar),
                                         theme: store.state.settings.defaultTheme, createdAt: now),
                            isNew: true)
        case .edit(let id):
            if let event = store.state.event(id: id) {
                EventEditorView(event: event, isNew: false)
            } else {
                MissingView()
            }
        case .detail(let id):
            EventDetailView(eventID: id) { sheet = .edit(id) }
        case .settings:
            SettingsView()
        }
    }
}

/// A dismissible message at the top of the dashboard.
struct NoticeBanner: View {
    let text: String
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text(text)
                .font(.footnote)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.bold))
            }
            .accessibilityLabel("Dismiss")
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// Shown if a sheet outlives its countdown (it was deleted underneath it).
struct MissingView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 12) {
            Text("That countdown has been deleted.")
            Button("Close") { dismiss() }
        }
        .padding()
    }
}
