import Foundation

/// One thing that starts (or could start) automatically.
public struct StartupItem: Sendable, Identifiable, Hashable {
    public enum Kind: String, Sendable, Codable, CaseIterable {
        case loginItem = "Login Item"
        case userAgent = "Your Agents"
        case globalAgent = "System Agents"
        case daemon = "Daemons"
    }

    public var id: String { path }
    public let kind: Kind
    /// Human name — login item name or launchd label.
    public let name: String
    /// What it actually runs, in plain words (program name).
    public let runs: String
    /// Full program path or app path — the honest detail line.
    public let programPath: String
    /// The plist path (launchd) or app path (login items).
    public let path: String
    public let enabled: Bool
    public let keepAlive: Bool
    /// Currently loaded with a live PID.
    public let runningPID: Int?
    /// User-domain items can be toggled without privileges.
    public var togglable: Bool { kind == .userAgent || kind == .loginItem }

    public init(kind: Kind, name: String, runs: String, programPath: String, path: String,
                enabled: Bool, keepAlive: Bool, runningPID: Int?) {
        self.kind = kind
        self.name = name
        self.runs = runs
        self.programPath = programPath
        self.path = path
        self.enabled = enabled
        self.keepAlive = keepAlive
        self.runningPID = runningPID
    }
}

/// Enumerates everything that auto-starts: login items, LaunchAgents (user
/// and global), and LaunchDaemons.
public struct StartupCatalog: Sendable {
    public init() {}

    public func collect() -> [StartupItem] {
        var items: [StartupItem] = []
        let pids = Self.loadedPIDs()

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        items += Self.launchdItems(dir: "\(home)/Library/LaunchAgents", kind: .userAgent, pids: pids)
        items += Self.launchdItems(dir: "/Library/LaunchAgents", kind: .globalAgent, pids: pids)
        items += Self.launchdItems(dir: "/Library/LaunchDaemons", kind: .daemon, pids: pids)
        items += Self.loginItems()

        return items
    }

    // MARK: launchd plists

    private static func launchdItems(dir: String, kind: StartupItem.Kind, pids: [String: Int]) -> [StartupItem] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: dir) else { return [] }

        return files.compactMap { file -> StartupItem? in
            guard file.contains(".plist") else { return nil }
            let path = "\(dir)/\(file)"
            let disabledByName = file.contains(".DISABLED")

            guard let data = fm.contents(atPath: path),
                  let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
            else {
                return StartupItem(kind: kind, name: file, runs: "unreadable plist", programPath: path,
                                   path: path, enabled: !disabledByName, keepAlive: false, runningPID: nil)
            }

            let label = plist["Label"] as? String ?? file.replacingOccurrences(of: ".plist", with: "")
            let program = plist["Program"] as? String
                ?? (plist["ProgramArguments"] as? [String])?.first
                ?? "?"
            let args = (plist["ProgramArguments"] as? [String])?.dropFirst().joined(separator: " ") ?? ""
            let disabledByKey = plist["Disabled"] as? Bool ?? false

            return StartupItem(
                kind: kind,
                name: label,
                runs: URL(fileURLWithPath: program).lastPathComponent + (args.isEmpty ? "" : " \(args)"),
                programPath: program,
                path: path,
                enabled: !(disabledByName || disabledByKey),
                keepAlive: (plist["KeepAlive"] as? Bool ?? false) || plist["KeepAlive"] is [String: Any],
                runningPID: pids[label]
            )
        }
    }

    /// label → PID for currently loaded user-domain jobs.
    private static func loadedPIDs() -> [String: Int] {
        guard let output = run("/bin/launchctl", ["list"]) else { return [:] }
        var pids: [String: Int] = [:]
        for line in output.split(separator: "\n").dropFirst() {
            let cols = line.split(separator: "\t", maxSplits: 2)
            guard cols.count == 3, let pid = Int(cols[0]) else { continue }
            pids[String(cols[2])] = pid
        }
        return pids
    }

    // MARK: Login items (via System Events — triggers an Automation prompt once)

    private static func loginItems() -> [StartupItem] {
        let script = #"tell application "System Events" to get {name, path} of every login item"#
        guard let output = run("/usr/bin/osascript", ["-e", script]), !output.isEmpty else { return [] }

        // osascript prints "name1, name2, ..., path1, path2, ..."
        let parts = output.split(separator: ", ").map(String.init)
        guard parts.count >= 2, parts.count.isMultiple(of: 2) else { return [] }
        let half = parts.count / 2

        return (0..<half).map { i in
            let name = parts[i]
            let appPath = parts[half + i]
            return StartupItem(
                kind: .loginItem,
                name: name,
                runs: URL(fileURLWithPath: appPath).lastPathComponent,
                programPath: appPath,
                path: appPath,
                enabled: true,
                keepAlive: false,
                runningPID: nil
            )
        }
    }

    static func run(_ tool: String, _ args: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }
}

/// Reversible startup mutations for user-togglable items. Every action
/// returns a plain-words description for the Ledger.
public struct StartupActions: Sendable {
    public init() {}

    /// Disable a user LaunchAgent: bootout + rename to `.DISABLED-<date>`.
    /// Fully reversible by `enable`.
    public func disable(_ item: StartupItem) throws -> String {
        guard item.kind == .userAgent else { throw ActionError.notTogglable }
        let uid = getuid()
        _ = StartupCatalog.run("/bin/launchctl", ["bootout", "gui/\(uid)/\(item.name)"])

        let date = Date.now.formatted(.iso8601.year().month().day().dateSeparator(.dash))
        let newPath = item.path + ".DISABLED-\(date)"
        try FileManager.default.moveItem(atPath: item.path, toPath: newPath)
        return "Disabled agent \(item.name) — plist renamed, job booted out"
    }

    /// Re-enable a previously disabled user LaunchAgent.
    public func enable(_ item: StartupItem) throws -> String {
        guard item.kind == .userAgent, let range = item.path.range(of: ".DISABLED") else {
            throw ActionError.notTogglable
        }
        let originalPath = String(item.path[..<range.lowerBound])
        try FileManager.default.moveItem(atPath: item.path, toPath: originalPath)
        let uid = getuid()
        _ = StartupCatalog.run("/bin/launchctl", ["bootstrap", "gui/\(uid)", originalPath])
        return "Re-enabled agent \(item.name)"
    }

    /// Remove a login item (System Events; the app itself is untouched).
    public func removeLoginItem(_ item: StartupItem) throws -> String {
        guard item.kind == .loginItem else { throw ActionError.notTogglable }
        let script = "tell application \"System Events\" to delete login item \"\(item.name)\""
        guard StartupCatalog.run("/usr/bin/osascript", ["-e", script]) != nil else {
            throw ActionError.failed
        }
        return "Removed login item \(item.name) — the app itself is untouched"
    }

    public enum ActionError: Error {
        case notTogglable
        case failed
    }
}
