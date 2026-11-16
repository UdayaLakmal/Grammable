// Grammable — Copyright (C) 2026 Udaya Lakmal — GPL-3.0-or-later

import Foundation

/// GUI apps launched from Finder get a minimal PATH, so CLIs installed with
/// npm, Homebrew, bun, volta or nvm are invisible. This resolves the user's real
/// login-shell PATH once and uses it to find and run agent CLIs.
public final class ShellEnvironment: @unchecked Sendable {
    public static let shared = ShellEnvironment()

    private let lock = NSLock()
    private var cachedPath: String?

    public var path: String {
        lock.lock(); defer { lock.unlock() }
        if let cachedPath { return cachedPath }
        let resolved = Self.resolvePath()
        cachedPath = resolved
        return resolved
    }

    /// Forget the cached PATH (e.g. after the user installs a CLI).
    public func reset() {
        lock.lock(); cachedPath = nil; lock.unlock()
    }

    public var environment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = path
        env["NO_COLOR"] = "1"
        env["TERM"] = "dumb"
        return env
    }

    /// Finds an executable by explicit path or by searching the resolved PATH.
    public func findExecutable(_ name: String, customPath: String? = nil) -> String? {
        let fm = FileManager.default
        if let customPath = customPath?.trimmingCharacters(in: .whitespaces), !customPath.isEmpty {
            let expanded = (customPath as NSString).expandingTildeInPath
            return fm.isExecutableFile(atPath: expanded) ? expanded : nil
        }
        for dir in path.split(separator: ":") {
            let candidate = (String(dir) as NSString).appendingPathComponent(name)
            if fm.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }

    private static func resolvePath() -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var dirs: [String] = []

        if let shellPath = loginShellPath() {
            dirs += shellPath.split(separator: ":").map(String.init)
        }
        // Common install locations, in case the shell config is unusual.
        dirs += [
            "\(home)/.local/bin", "\(home)/.claude/local", "/opt/homebrew/bin", "/usr/local/bin",
            "\(home)/.npm-global/bin", "\(home)/.bun/bin", "\(home)/.volta/bin", "\(home)/.cargo/bin",
            "\(home)/Library/pnpm", "/usr/bin", "/bin", "/usr/sbin", "/sbin",
        ]
        // Latest nvm node, if any.
        let nvm = "\(home)/.nvm/versions/node"
        if let versions = try? FileManager.default.contentsOfDirectory(atPath: nvm) {
            for v in versions.sorted().reversed() { dirs.append("\(nvm)/\(v)/bin") }
        }

        var seen = Set<String>()
        return dirs.filter { !$0.isEmpty && seen.insert($0).inserted }.joined(separator: ":")
    }

    private static func loginShellPath() -> String? {
        var shell = "/bin/zsh"
        if let pw = getpwuid(getuid()), let sh = pw.pointee.pw_shell {
            let s = String(cString: sh)
            if !s.isEmpty { shell = s }
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        // -l loads login profiles, -i loads interactive rc files (where nvm etc. live).
        process.arguments = ["-l", "-i", "-c", "printf '__GRAMMABLE_PATH__%s__END__' \"$PATH\""]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return nil }

        let deadline = Date().addingTimeInterval(4)
        while process.isRunning && Date() < deadline { usleep(20_000) }
        if process.isRunning { process.terminate(); return nil }

        let data = out.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8),
              let start = text.range(of: "__GRAMMABLE_PATH__"),
              let end = text.range(of: "__END__", range: start.upperBound..<text.endIndex)
        else { return nil }
        return String(text[start.upperBound..<end.lowerBound])
    }
}
