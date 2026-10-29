import XCTest
@testable import JBLCompanion

/// Fixtures (`Fixtures/Assertions_DNDOn.json`/`Assertions_DNDOff.json`) are real
/// `~/Library/DoNotDisturb/DB/Assertions.json` captures taken directly from the developer's own
/// Mac before/after toggling Do Not Disturb — `FocusModeWatcher`'s own doc comment has the full
/// story on why this file (not `SetFocusFilterIntent`) is the detection mechanism.
final class FocusModeWatcherTests: XCTestCase {
    private func fixtureURL(_ name: String) -> URL {
        Bundle(for: Self.self).url(forResource: name, withExtension: "json")!
    }

    func testIsDoNotDisturbActive_whenAssertionRecordPresent_returnsTrue() {
        let url = fixtureURL("Assertions_DNDOn")
        XCTAssertTrue(FocusModeWatcher.isDoNotDisturbActive(assertionsFileURL: url))
    }

    func testIsDoNotDisturbActive_whenNoAssertionRecord_returnsFalse() {
        let url = fixtureURL("Assertions_DNDOff")
        XCTAssertFalse(FocusModeWatcher.isDoNotDisturbActive(assertionsFileURL: url))
    }

    func testIsDoNotDisturbActive_whenFileMissing_returnsFalse() {
        let url = URL(fileURLWithPath: "/tmp/does-not-exist-\(UUID().uuidString).json")
        XCTAssertFalse(FocusModeWatcher.isDoNotDisturbActive(assertionsFileURL: url))
    }

    func testIsDoNotDisturbActive_whenFileIsMalformedJSON_returnsFalse() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("malformed-\(UUID().uuidString).json")
        try "not json".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertFalse(FocusModeWatcher.isDoNotDisturbActive(assertionsFileURL: url))
    }

    func testStartAndStop_doesNotCrash() {
        let watcher = FocusModeWatcher(assertionsFileURL: fixtureURL("Assertions_DNDOff"))
        watcher.start()
        watcher.stop()
    }
}
