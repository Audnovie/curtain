import XCTest
@testable import CurtainCore

final class StoreTests: XCTestCase {
    let cal = toronto()
    let now = at(2026, 11, 19, 14, 44, 10)

    private func sample() -> AppState {
        var state = AppState()
        state.upsert(countdown("Done work", to: at(2026, 11, 19, 21, 0), reusable: true, usual: [1260, 1020, 1140]),
                     now: now, calendar: cal)
        state.upsert(since("Moved in", from: at(2026, 11, 1), allDay: true), now: now, calendar: cal)
        state.settings.showSeconds = true
        state.settings.defaultTheme = .ocean
        state.keep(theme: Theme(name: "From wallpaper", background: RGB("#071A55"), foreground: .white, accent: RGB("#5572C2")))
        return state
    }

    func testSavedFileRoundTrip() throws {
        let state = sample()
        let data = try StateFile.encode(state)
        XCTAssertEqual(try StateFile.decode(data), state)
        // Readable by a person: colours as hex, dates as text.
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains("\"#071A55\""), text)
        XCTAssertTrue(text.contains("\"2026-11-20T02:00:00Z\""), text)
        XCTAssertTrue(text.contains("\"usualTimes\""), text)
    }

    func testSaveAndLoadOnDisk() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("curtain-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("nested/" + StateFile.fileName)
        XCTAssertEqual(StateFile.load(from: url), .missing)
        let state = sample()
        try StateFile.save(state, to: url)
        XCTAssertEqual(StateFile.load(from: url), .loaded(state))

        try Data("not json".utf8).write(to: url)
        guard case .unreadable = StateFile.load(from: url) else { return XCTFail("garbage was accepted") }

        try Data("{\"version\": 99, \"events\": []}".utf8).write(to: url)
        guard case .unreadable(let why) = StateFile.load(from: url) else { return XCTFail("a newer format was accepted") }
        XCTAssertTrue(why.contains("newer"), why)
    }

    func testOlderAndDamagedFilesStillLoad() throws {
        let json = """
        {
          "version": 1,
          "somethingFromTheFuture": true,
          "events": [
            { "id": "11111111-1111-1111-1111-111111111111", "name": "Bare", "date": "2026-11-20T02:00:00Z" },
            { "id": "not-an-id", "name": "Broken", "date": "2026-11-20T02:00:00Z" },
            { "id": "22222222-2222-2222-2222-222222222222", "name": "Odd", "mode": "since", "date": "2026-11-01T04:00:00Z",
              "usualTimes": [5000, 60, 60], "theme": { "background": "#0B5FA5" }, "extra": 1 }
          ]
        }
        """
        let state = try StateFile.decode(Data(json.utf8))
        XCTAssertEqual(state.events.map { $0.name }, ["Bare", "Odd"])
        let bare = state.events[0]
        XCTAssertEqual(bare.mode, .countdown)
        XCTAssertEqual(bare.date, at(2026, 11, 19, 21, 0))
        XCTAssertFalse(bare.reusable)
        XCTAssertEqual(bare.theme, .ember)
        XCTAssertEqual(bare.createdAt, bare.date)
        let odd = state.events[1]
        XCTAssertEqual(odd.mode, .since)
        XCTAssertEqual(odd.usualTimes, [60])
        XCTAssertEqual(odd.theme.background, RGB("#0B5FA5"))
        XCTAssertEqual(odd.theme.foreground, .white)
        XCTAssertEqual(odd.theme.name, "Custom")
        XCTAssertEqual(state.settings, Settings())
        XCTAssertTrue(state.savedThemes.isEmpty)
    }

    func testAddingTidiesWhatWasTyped() {
        var state = AppState()
        var e = countdown("   Done work   ", to: at(2026, 11, 19, 21, 0, 42), reusable: true, usual: [1260, 1020, 1020])
        e.createdAt = now
        state.upsert(e, now: now, calendar: cal)
        XCTAssertEqual(state.events.count, 1)
        XCTAssertEqual(state.events[0].name, "Done work")
        XCTAssertEqual(state.events[0].date, at(2026, 11, 19, 21, 0))
        XCTAssertEqual(state.events[0].usualTimes, [1020, 1260])
        XCTAssertEqual(state.events[0].updatedAt, now)

        // Saving it again replaces it and keeps when it was first made.
        var edited = state.events[0]
        edited.name = String(repeating: "x", count: 90)
        let later = now.addingTimeInterval(500)
        state.upsert(edited, now: later, calendar: cal)
        XCTAssertEqual(state.events.count, 1)
        XCTAssertEqual(state.events[0].name.count, Event.maxNameLength)
        XCTAssertEqual(state.events[0].createdAt, now)
        XCTAssertEqual(state.events[0].updatedAt, later)

        // No name: it gets one. All-day and "time since" can't be reusable.
        state.upsert(Event(name: "  ", mode: .since, date: at(2026, 11, 19, 9, 0, 30), reusable: true, usualTimes: [60], createdAt: now),
                     now: now, calendar: cal)
        XCTAssertEqual(state.events[1].name, "Time since")
        XCTAssertFalse(state.events[1].reusable)
        XCTAssertTrue(state.events[1].usualTimes.isEmpty)
        XCTAssertEqual(state.events[1].date, at(2026, 11, 19, 9, 0))
        state.upsert(countdown("Trip", to: at(2026, 12, 25, 15, 30), reusable: true, allDay: true, usual: [60]), now: now, calendar: cal)
        XCTAssertEqual(state.events[2].date, at(2026, 12, 25))
        XCTAssertFalse(state.events[2].reusable)
    }

    func testSettingAReusableCountdown() {
        var state = sample()
        let id = state.events[0].id
        let seven = Schedule.next(minuteOfDay: 19 * 60, after: now, calendar: cal)
        XCTAssertTrue(state.setCountdown(id: id, to: seven, remember: false, now: now, calendar: cal))
        XCTAssertEqual(state.events[0].date, at(2026, 11, 19, 19, 0))
        XCTAssertEqual(state.events[0].usualTimes, [1020, 1140, 1260])

        // A new time, remembered.
        XCTAssertTrue(state.setCountdown(id: id, to: at(2026, 11, 20, 18, 30, 15), remember: true, now: now, calendar: cal))
        XCTAssertEqual(state.events[0].date, at(2026, 11, 20, 18, 30))
        XCTAssertEqual(state.events[0].usualTimes, [1020, 1110, 1140, 1260])
        // Remembering one it already has changes nothing.
        XCTAssertTrue(state.setCountdown(id: id, to: at(2026, 11, 21, 17, 0), remember: true, now: now, calendar: cal))
        XCTAssertEqual(state.events[0].usualTimes, [1020, 1110, 1140, 1260])

        XCTAssertFalse(state.setCountdown(id: UUID(), to: seven, remember: true, now: now, calendar: cal))
        XCTAssertFalse(state.setCountdown(id: state.events[1].id, to: seven, remember: true, now: now, calendar: cal))
        XCTAssertTrue(state.restartSince(id: state.events[1].id, from: at(2026, 11, 19, 14, 44, 10), now: now))
        XCTAssertEqual(state.events[1].date, at(2026, 11, 19, 14, 44))
        XCTAssertFalse(state.events[1].allDay)
        XCTAssertFalse(state.restartSince(id: id, from: now, now: now))

        // A full list of usual times still takes the newest one.
        var full = AppState()
        full.upsert(countdown(to: at(2026, 11, 19, 21, 0), reusable: true, usual: Array(stride(from: 60, to: 60 * 9, by: 60))),
                    now: now, calendar: cal)
        XCTAssertEqual(full.events[0].usualTimes.count, Event.maxUsualTimes)
        full.setCountdown(id: full.events[0].id, to: at(2026, 11, 19, 22, 15), remember: true, now: now, calendar: cal)
        XCTAssertEqual(full.events[0].usualTimes.count, Event.maxUsualTimes)
        XCTAssertTrue(full.events[0].usualTimes.contains(22 * 60 + 15))
    }

    func testFinishedOnesAndDeleting() {
        var state = AppState()
        let old1 = countdown("Old 1", to: at(2026, 11, 15, 21, 0))
        let old2 = countdown("Old 2", to: at(2026, 11, 12, 21, 0))
        let reusableOld = countdown("Done work", to: at(2026, 11, 18, 21, 0), reusable: true, usual: [1260])
        let running = countdown("Soon", to: at(2026, 11, 19, 21, 0))
        let pastDay = countdown("Trip", to: at(2026, 11, 18), allDay: true)
        let today = countdown("Party", to: at(2026, 11, 19), allDay: true)
        let counting = since(from: at(2026, 11, 1, 9, 0))
        for e in [old1, old2, reusableOld, running, pastDay, today, counting] { state.upsert(e, now: now, calendar: cal) }

        let finished = state.finishedIDs(now: now, calendar: cal)
        XCTAssertEqual(finished, [old1.id, old2.id, pastDay.id])

        state.delete(ids: finished)
        XCTAssertEqual(Set(state.events.map { $0.name }), ["Done work", "Soon", "Party", "Started"])
        state.delete(ids: [])
        XCTAssertEqual(state.events.count, 4)
        XCTAssertNil(state.event(id: old1.id))
        XCTAssertEqual(state.event(id: running.id)?.name, "Soon")
    }

    func testDashboardOrder() {
        var state = AppState()
        var work = countdown("Done work", to: at(2026, 11, 18, 21, 0), reusable: true, usual: [1260])
        work.createdAt = at(2026, 11, 2)
        var gym = countdown("Gym", to: at(2026, 11, 19, 18, 0), reusable: true, usual: [1080])
        gym.createdAt = at(2026, 11, 5)
        let soon = countdown("Soon", to: at(2026, 11, 19, 16, 0))
        let later = countdown("Later", to: at(2026, 12, 25), allDay: true)
        let older = since("Older", from: at(2026, 10, 1, 9, 0))
        let newer = since("Newer", from: at(2026, 11, 10, 9, 0))
        let done1 = countdown("Done first", to: at(2026, 11, 12, 21, 0))
        let done2 = countdown("Done second", to: at(2026, 11, 15, 21, 0))
        for e in [done1, older, later, gym, newer, soon, done2, work] { state.upsert(e, now: now, calendar: cal) }
        XCTAssertEqual(state.dashboardOrder(now: now, calendar: cal).map { $0.name },
                       ["Done work", "Gym", "Soon", "Later", "Newer", "Older", "Done second", "Done first"])
        XCTAssertEqual(state.defaultEvent(mode: .countdown, now: now, calendar: cal)?.name, "Done work")
        XCTAssertEqual(state.defaultEvent(mode: .since, now: now, calendar: cal)?.name, "Newer")
        XCTAssertNil(AppState().defaultEvent(mode: .since, now: now, calendar: cal))
    }

    func testKeptColourSets() {
        var state = AppState()
        let a = Theme(name: "A", background: RGB("#071A55"), foreground: .white, accent: RGB("#5572C2"))
        var sameColours = a
        sameColours.name = "A again"
        state.keep(theme: a)
        state.keep(theme: .ocean)
        state.keep(theme: sameColours)
        XCTAssertEqual(state.savedThemes.map { $0.name }, ["A again", "Ocean"])
        state.forget(theme: a)
        XCTAssertEqual(state.savedThemes.map { $0.name }, ["Ocean"])
        for i in 0..<40 {
            state.keep(theme: Theme(name: "T\(i)", background: RGB(r: Double(i) / 40, g: 0.2, b: 0.4), foreground: .white, accent: .white))
        }
        XCTAssertEqual(state.savedThemes.count, AppState.maxSavedThemes)
        XCTAssertEqual(state.savedThemes[0].name, "T39")
    }
}

final class ProvisioningProfileTests: XCTestCase {
    private func profile(_ groups: String) -> Data {
        // The real thing is binary signing data around a property list, like this.
        var data = Data([0x30, 0x82, 0x1F, 0x00, 0xFF, 0x00, 0x3C])
        data.append(Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>AppIDName</key>
            <string>Curtain</string>
            <key>Entitlements</key>
            <dict>
                <key>application-identifier</key>
                <string>ABCDE12345.io.github.audnovie.curtain</string>
                \(groups)
            </dict>
            <key>TeamName</key>
            <string>Someone</string>
        </dict>
        </plist>
        """.utf8))
        data.append(Data([0x00, 0xA0, 0x82, 0x0D, 0x3C, 0x2F]))
        return data
    }

    func testGroupsAreReadFromAProfile() {
        let renamed = profile("""
        <key>com.apple.security.application-groups</key>
        <array>
            <string>group.io.github.audnovie.curtain.ABCDE12345</string>
            <string>group.other</string>
        </array>
        """)
        XCTAssertEqual(ProvisioningProfile.appGroups(in: renamed),
                       ["group.io.github.audnovie.curtain.ABCDE12345", "group.other"])
    }

    func testProfilesWithoutGroupsAndRubbish() {
        XCTAssertEqual(ProvisioningProfile.appGroups(in: profile("")), [])
        XCTAssertEqual(ProvisioningProfile.appGroups(in: Data()), [])
        XCTAssertEqual(ProvisioningProfile.appGroups(in: Data("no list in here".utf8)), [])
        XCTAssertEqual(ProvisioningProfile.appGroups(in: Data("<?xml never closed".utf8)), [])
        XCTAssertEqual(ProvisioningProfile.appGroups(in: Data("<?xml version=\"1.0\"?><plist><array/></plist>".utf8)), [])
    }
}
