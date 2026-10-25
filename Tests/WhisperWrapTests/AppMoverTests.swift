import XCTest
@testable import WhisperWrap

final class AppMoverTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("AppMoverTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func makeBundle(in dir: URL, marker: String) throws -> URL {
        let app = dir.appendingPathComponent("Fake.app")
        let macos = app.appendingPathComponent("Contents/MacOS")
        try FileManager.default.createDirectory(at: macos, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: macos.appendingPathComponent("Fake"))
        let info: NSDictionary = ["CFBundleExecutable": "Fake", "CFBundleIdentifier": "test.fake.\(marker)", "CFBundlePackageType": "APPL"]
        info.write(to: app.appendingPathComponent("Contents/Info.plist"), atomically: true)
        try AppMover.run("/usr/bin/codesign", ["--force", "--sign", "-", app.path])
        try AppMover.run("/usr/bin/xattr", ["-w", "com.apple.quarantine", "0083;00000000;Safari;", app.path])
        return app
    }

    func testInstallReplacesExistingAndStripsQuarantine() throws {
        let src = root.appendingPathComponent("src"), dst = root.appendingPathComponent("Applications")
        try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dst, withIntermediateDirectories: true)
        _ = try AppMover.install(from: try makeBundle(in: root.appendingPathComponent("old"), marker: "old"), into: dst)
        let installed = try AppMover.install(from: try makeBundle(in: src, marker: "new"), into: dst)

        let info = NSDictionary(contentsOf: installed.appendingPathComponent("Contents/Info.plist"))
        XCTAssertEqual(info?["CFBundleIdentifier"] as? String, "test.fake.new")
        XCTAssertThrowsError(try AppMover.run("/usr/bin/xattr", ["-p", "com.apple.quarantine", installed.path]))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dst.path), ["Fake.app"], "no staging leftovers")
    }

    func testBrokenBundleLeavesExistingInstallUntouched() throws {
        let dst = root.appendingPathComponent("Applications")
        try FileManager.default.createDirectory(at: dst, withIntermediateDirectories: true)
        _ = try AppMover.install(from: try makeBundle(in: root.appendingPathComponent("good"), marker: "good"), into: dst)
        let broken = try makeBundle(in: root.appendingPathComponent("bad"), marker: "bad")
        try FileManager.default.removeItem(at: broken.appendingPathComponent("Contents/MacOS/Fake"))

        XCTAssertThrowsError(try AppMover.install(from: broken, into: dst))
        let info = NSDictionary(contentsOf: dst.appendingPathComponent("Fake.app/Contents/Info.plist"))
        XCTAssertEqual(info?["CFBundleIdentifier"] as? String, "test.fake.good")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dst.path), ["Fake.app"])
    }

    func testLocationDetection() {
        XCTAssertTrue(AppMover.isTranslocated(URL(fileURLWithPath: "/private/var/folders/x/AppTranslocation/ABC/d/W.app")))
        XCTAssertTrue(AppMover.isOnMountedVolume(URL(fileURLWithPath: "/Volumes/WhisperWrap/W.app")))
        XCTAssertTrue(AppMover.isInApplicationsFolder(URL(fileURLWithPath: "/Applications/W.app")))
        XCTAssertFalse(AppMover.isInApplicationsFolder(URL(fileURLWithPath: "/Users/x/Downloads/W.app")))
    }
}
