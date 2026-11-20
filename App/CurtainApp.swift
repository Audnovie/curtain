// First build: a probe screen to learn how this simulator behaves before the real app goes in.
import SwiftUI
import WidgetKit
import CurtainCore

@main
struct CurtainApp: App {
    var body: some Scene {
        WindowGroup { ProbeView() }
    }
}

struct ProbeView: View {
    let start = Date()
    @State private var saveResult = "not tried"

    private var offsets: [(String, TimeInterval)] {
        [("in 6:16:40", 22600), ("in 6:00:00", 21600), ("in 0:59:10", 3550), ("in 0:10:30", 630),
         ("in 25:30:00", 91800), ("in 6d 9:20", 552000), ("ago 2:20:30", -8430), ("ago 0:10:59", -659),
         ("ago 3d 4:59", -277140)]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("shared: \(SharedContainer.location.shared ? "yes" : "no")").accessibilityIdentifier("probe.shared")
                Text("group: \(SharedContainer.location.group ?? "none")")
                Text(SharedContainer.location.file.path).font(.system(size: 9))
                Text("save: \(saveResult)").accessibilityIdentifier("probe.save")
                ForEach(offsets, id: \.0) { item in
                    HStack {
                        Text(item.0).frame(width: 110, alignment: .leading)
                        Text(start.addingTimeInterval(item.1), style: .relative)
                            .accessibilityIdentifier("probe.rel." + item.0)
                    }
                    .font(.system(size: 13))
                }
                ZStack {
                    LinearGradient(colors: [Color(red: 0.03, green: 0.1, blue: 0.33), Color(red: 0.2, green: 0.42, blue: 0.46)],
                                   startPoint: .top, endPoint: .bottom)
                    VStack(alignment: .leading, spacing: 14) {
                        LockRectFace(display: .sample(mode: .countdown)).frame(width: 160, height: 72)
                        LockRectFace(display: WidgetDisplay(title: "Done work", timeText: "Finished", bar: .empty,
                                                            state: .finished, mode: .countdown, hint: "Tap to set again"))
                            .frame(width: 160, height: 72)
                        InlineFace(display: .sample(mode: .since))
                    }
                    .foregroundStyle(.white)
                    .padding()
                }
                HStack {
                    HomeFace(display: .sample(mode: .countdown), theme: .ember)
                        .padding(15).frame(width: 158, height: 158).background(Theme.ember.fill)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    HomeFace(display: .sample(mode: .since), theme: .ocean)
                        .padding(15).frame(width: 158, height: 158).background(Theme.ocean.fill)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
            }
            .padding()
        }
        .onAppear {
            var state = AppState()
            let cal = Calendar.current
            state.upsert(Event(name: "Done work", mode: .countdown, date: Date().addingTimeInterval(22600),
                               reusable: true, usualTimes: [1020, 1140, 1260], createdAt: Date()), now: Date(), calendar: cal)
            do {
                try StateFile.save(state, to: SharedContainer.location.file)
                saveResult = "ok"
                WidgetCenter.shared.reloadAllTimelines()
            } catch {
                saveResult = "failed: \(error)"
            }
        }
    }
}
