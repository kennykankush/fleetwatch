import Foundation

/// Connects a cloud account from inside the app instead of sending you to a
/// terminal.
///
/// This drives `rclone config create --non-interactive`, which is rclone's
/// documented protocol for exactly this: rather than printing questions, it
/// returns each one as JSON — help text, a default, the allowed answers — and
/// the caller renders it however it likes, then replies with
/// `--continue --state … --result …`. The conversation ends when rclone
/// returns an empty `State`.
///
/// The sign-in itself still happens on the provider's own page: at the OAuth
/// step rclone opens the browser and waits, and the resulting token is written
/// to the user's `rclone.conf`. Fleetwatch never sees a password or a token —
/// it only asks the questions and reports when the flow is done.
public enum RcloneConfig {
    /// One permitted answer to a question.
    public struct Choice: Sendable, Hashable, Identifiable {
        public let value: String
        public let help: String
        public var id: String { value }
        public init(value: String, help: String) { self.value = value; self.help = help }
    }

    /// A question rclone wants answered before it can finish the remote.
    public struct Question: Sendable, Hashable {
        /// Opaque token that must be handed back with the answer.
        public let state: String
        public let name: String
        public let help: String
        public let defaultValue: String
        public let choices: [Choice]
        /// Only `choices` are valid — no free text.
        public let exclusive: Bool
        public let required: Bool
        public let isPassword: Bool
        public let isBool: Bool
        /// Set when the previous answer was rejected; show it with the question.
        public let error: String

        public init(state: String, name: String, help: String, defaultValue: String,
                    choices: [Choice], exclusive: Bool, required: Bool,
                    isPassword: Bool, isBool: Bool, error: String) {
            self.state = state; self.name = name; self.help = help
            self.defaultValue = defaultValue; self.choices = choices
            self.exclusive = exclusive; self.required = required
            self.isPassword = isPassword; self.isBool = isBool; self.error = error
        }

        /// A human label for the field, since rclone's `Name` is snake_case.
        public var label: String {
            name.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    public enum Step: Sendable, Hashable {
        case ask(Question)
        case finished
    }

    /// A backend rclone knows how to talk to.
    public struct Provider: Sendable, Hashable, Identifiable {
        public let name: String          // "onedrive"
        public let description: String   // "Microsoft OneDrive"
        public var id: String { name }
        public init(name: String, description: String) {
            self.name = name; self.description = description
        }
    }

    /// The consumer cloud drives worth showing first. Everything else rclone
    /// supports still appears below — this is ordering, not a whitelist.
    static let preferred = ["drive", "onedrive", "dropbox", "box", "pcloud",
                            "mega", "protondrive", "iclouddrive", "jottacloud",
                            "koofr", "b2", "s3"]

    /// Every backend the installed rclone supports (~69), preferred ones first.
    public static func providers() async -> [Provider] {
        guard let out = try? await CloudProbe.run(["config", "providers"]) else { return [] }
        return sort(parseProviders(out))
    }

    public static func parseProviders(_ json: String) -> [Provider] {
        guard let rows = decode(json) as? [[String: Any]] else { return [] }
        return rows.compactMap { row in
            guard let name = row["Name"] as? String, !name.isEmpty else { return nil }
            // Hidden backends are internal plumbing, not destinations.
            if let hide = row["Hide"] as? Bool, hide { return nil }
            let desc = (row["Description"] as? String) ?? name
            return Provider(name: name, description: desc)
        }
    }

    static func sort(_ list: [Provider]) -> [Provider] {
        list.sorted { a, b in
            let ia = preferred.firstIndex(of: a.name) ?? Int.max
            let ib = preferred.firstIndex(of: b.name) ?? Int.max
            if ia != ib { return ia < ib }
            return a.description.localizedCaseInsensitiveCompare(b.description) == .orderedAscending
        }
    }

    // MARK: the conversation

    /// Opens the flow. Note this already writes a stub remote, so a flow the
    /// user walks away from must be cleaned up with `cancel`.
    public static func begin(remote: String, backend: String) async throws -> Step {
        try await step(["config", "create", remote, backend, "--non-interactive"])
    }

    /// Answers the current question and returns the next one.
    ///
    /// At the OAuth step this does not return until the browser round-trip
    /// finishes, so callers should show that they're waiting on the provider.
    public static func answer(remote: String, backend: String,
                              state: String, result: String) async throws -> Step {
        try await step(["config", "create", remote, backend, "--non-interactive",
                        "--continue", "--state", state, "--result", result])
    }

    /// Removes a half-configured remote when the user backs out.
    public static func cancel(remote: String) async {
        _ = try? await CloudProbe.run(["config", "delete", remote])
    }

    private static func step(_ args: [String]) async throws -> Step {
        let out = try await CloudProbe.run(args)
        return try parseStep(out)
    }

    /// rclone writes its multi-line `Help` text with **raw newlines inside
    /// JSON string values**, which RFC 8259 forbids and `JSONSerialization`
    /// rejects outright. Escape control characters that occur inside string
    /// literals so the payload can actually be decoded.
    static func repairJSON(_ raw: String) -> String {
        var out = ""
        out.reserveCapacity(raw.count + 128)
        var inString = false
        var escaped = false
        for ch in raw {
            if escaped { out.append(ch); escaped = false; continue }
            switch ch {
            case "\\" where inString: out.append(ch); escaped = true
            case "\"": inString.toggle(); out.append(ch)
            case "\n" where inString: out.append("\\n")
            case "\r" where inString: out.append("\\r")
            case "\t" where inString: out.append("\\t")
            default: out.append(ch)
            }
        }
        return out
    }

    static func decode(_ raw: String) -> Any? {
        guard let data = raw.data(using: .utf8) else { return nil }
        if let obj = try? JSONSerialization.jsonObject(with: data) { return obj }
        guard let repaired = repairJSON(raw).data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: repaired)
    }

    /// `{"State": …, "Option": {…}, "Error": …}`. An empty `State` means the
    /// remote is configured; empty output means rclone had nothing left to ask.
    ///
    /// Unparseable output **throws** rather than reporting success: silently
    /// treating a reply we couldn't read as "done" is how a remote ends up
    /// half-configured, with a token but no drive.
    public static func parseStep(_ json: String) throws -> Step {
        let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .finished }
        guard let obj = decode(trimmed) as? [String: Any] else {
            throw CloudProbe.ProbeError.failed(
                "Couldn't read rclone's reply:\n\(trimmed.prefix(400))")
        }

        let state = (obj["State"] as? String) ?? ""
        guard !state.isEmpty else { return .finished }
        guard let option = obj["Option"] as? [String: Any] else {
            // A state with nothing to ask means rclone wants to be called
            // again with an empty answer, not that the flow is over.
            return .ask(Question(state: state, name: "", help: "", defaultValue: "",
                                 choices: [], exclusive: false, required: false,
                                 isPassword: false, isBool: false,
                                 error: (obj["Error"] as? String) ?? ""))
        }

        let choices: [Choice] = (option["Examples"] as? [[String: Any]] ?? []).compactMap {
            guard let v = $0["Value"] as? String else { return nil }
            return Choice(value: v, help: ($0["Help"] as? String) ?? v)
        }
        let type = (option["Type"] as? String)?.lowercased() ?? "string"

        return .ask(Question(
            state: state,
            name: (option["Name"] as? String) ?? "",
            help: ((option["Help"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            defaultValue: (option["DefaultStr"] as? String) ?? "",
            choices: choices,
            exclusive: (option["Exclusive"] as? Bool) ?? false,
            required: (option["Required"] as? Bool) ?? false,
            isPassword: ((option["IsPassword"] as? Bool) ?? false) || ((option["Sensitive"] as? Bool) ?? false),
            isBool: type == "bool",
            error: (obj["Error"] as? String) ?? ""
        ))
    }
}
