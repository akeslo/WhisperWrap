import Foundation

/// Installs the running app bundle into an Applications folder. Copy goes to a temp name next
/// to the destination, is verified (Info.plist, executable, codesign), then swapped in, so a
/// failed or interrupted move never leaves a partial bundle at the real path.
enum AppMover {
    struct MoveError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// Gatekeeper runs quarantined apps opened from their download folder from a randomized
    /// read-only mount (App Translocation).
    static func isTranslocated(_ url: URL) -> Bool {
        url.path.contains("/AppTranslocation/")
    }

    static func isOnMountedVolume(_ url: URL) -> Bool {
        url.path.hasPrefix("/Volumes/")
    }

    static func isInApplicationsFolder(_ url: URL) -> Bool {
        let path = url.resolvingSymlinksInPath().path
        let userApps = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path
        return path.hasPrefix("/Applications/") || path.hasPrefix(userApps + "/")
    }

    /// The real on-disk location of a translocated bundle (e.g. ~/Downloads/WhisperWrap.app).
    /// Private Security SPI, looked up at runtime the same way LetsMove does; nil if unavailable.
    static func originalURL(forTranslocated url: URL) -> URL? {
        typealias Fn = @convention(c) (CFURL, UnsafeMutablePointer<Unmanaged<CFError>?>?) -> Unmanaged<CFURL>?
        guard let handle = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_LAZY),
              let sym = dlsym(handle, "SecTranslocateCreateOriginalPathForURL") else { return nil }
        let fn = unsafeBitCast(sym, to: Fn.self)
        return fn(url as CFURL, nil)?.takeRetainedValue() as URL?
    }

    /// Copies `source` into `directory`, replacing any existing bundle of the same name.
    /// Returns the installed URL. Throws without touching an existing install if anything fails.
    @discardableResult
    static func install(from source: URL, into directory: URL) throws -> URL {
        let fm = FileManager.default
        let destination = directory.appendingPathComponent(source.lastPathComponent)
        let staging = directory.appendingPathComponent(".\(source.lastPathComponent).\(UUID().uuidString).tmp")
        defer { try? fm.removeItem(at: staging) }

        // ditto preserves symlinks, xattrs and signatures inside frameworks.
        try run("/usr/bin/ditto", [source.path, staging.path])
        // Notarized app: clear quarantine so the new copy isn't translocated again.
        _ = try? run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", staging.path])
        try verify(staging)

        if fm.fileExists(atPath: destination.path) {
            _ = try fm.replaceItemAt(destination, withItemAt: staging)
        } else {
            try fm.moveItem(at: staging, to: destination)
        }
        try verify(destination)
        return destination
    }

    /// Same as `install` but through an administrator prompt, for a non-writable /Applications.
    static func installWithAdminPrivileges(from source: URL, into directory: URL) throws -> URL {
        let destination = directory.appendingPathComponent(source.lastPathComponent)
        let staging = directory.appendingPathComponent(".\(source.lastPathComponent).admin.tmp")
        let old = directory.appendingPathComponent(".\(source.lastPathComponent).old")
        func q(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let script = [
            "rm -rf \(q(staging.path)) \(q(old.path))",
            "/usr/bin/ditto \(q(source.path)) \(q(staging.path))",
            "/usr/bin/xattr -dr com.apple.quarantine \(q(staging.path)) || true",
            "/usr/bin/codesign --verify --deep --strict \(q(staging.path))",
            "if [ -e \(q(destination.path)) ]; then mv \(q(destination.path)) \(q(old.path)); fi",
            "mv \(q(staging.path)) \(q(destination.path))",
            "rm -rf \(q(old.path))",
        ].joined(separator: " && ") + " || { rm -rf \(q(staging.path)); exit 1; }"
        let apple = "do shell script \"\(script.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\" with administrator privileges"
        try run("/usr/bin/osascript", ["-e", apple])
        try verify(destination)
        return destination
    }

    static func verify(_ bundle: URL) throws {
        let fm = FileManager.default
        let plist = bundle.appendingPathComponent("Contents/Info.plist")
        guard let info = NSDictionary(contentsOf: plist),
              let exe = info["CFBundleExecutable"] as? String,
              fm.isExecutableFile(atPath: bundle.appendingPathComponent("Contents/MacOS/\(exe)").path)
        else { throw MoveError(message: "The copied app is incomplete (missing Info.plist or executable).") }
        do {
            try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", bundle.path])
        } catch {
            throw MoveError(message: "The copied app failed its code signature check: \(error.localizedDescription)")
        }
    }

    @discardableResult
    static func run(_ tool: String, _ args: [String]) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        try p.run()
        let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            throw MoveError(message: "\((tool as NSString).lastPathComponent) failed: \(out.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        return out
    }
}
