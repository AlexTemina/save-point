import AppKit
import Foundation

/// Everything that touches Orca goes through its CLI, the same way Orca Summon does.
enum Orca {
    static let cli = "/Applications/Orca.app/Contents/Resources/bin/orca"

    struct Worktree: Decodable {
        let id: String
        let path: String
        let displayName: String
        let isMainWorktree: Bool
        let isArchived: Bool
        let linkedLinearIssue: String?
        let linkedPR: Int?
        let isUnread: Bool?
        let workspaceStatus: String?
        let comment: String?
        let repoId: String?
        let parentWorktreeId: String?
    }

    struct Repo: Decodable { let id: String; let displayName: String }
    private struct Repos: Decodable { let repos: [Repo] }

    static func repos() throws -> [Repo] {
        try JSONDecoder().decode(Envelope<Repos>.self, from: run(["repo", "list", "--json"])).result.repos
    }

    /// The Linear issue a name starts with, the way worktrees (`ES-12279-mo-spike`) and agent tabs (`ES-12279 — Mo`) are named.
    static func issuePrefix(_ name: String) -> String? {
        let clean = AgentMonitor.stripGlyph(name)
        guard let m = clean.range(of: #"^[A-Za-z]+[0-9]*-\d+"#, options: .regularExpression) else { return nil }
        return clean[m].uppercased()
    }

    /// Whether a tab title names the issue anywhere: Claude retitles its tab from the session, so the id is not always first.
    static func mentions(_ title: String, _ issue: String) -> Bool {
        let pattern = "(^|[^A-Za-z0-9])" + NSRegularExpression.escapedPattern(for: issue) + "([^0-9]|$)"
        return title.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// The agent named after the issue: the tab whose title carries its id. The one that matters for the task.
    static func namedAgent(_ issue: String, in terminals: [Terminal]) -> Terminal? {
        terminals.filter { $0.connected && AgentMonitor.isAgent($0) && mentions($0.title ?? "", issue) }
            .max { ($0.lastOutputAt ?? 0) < ($1.lastOutputAt ?? 0) }
    }

    static func rename(_ terminal: String, to title: String) {
        _ = try? run(["terminal", "rename", "--terminal", terminal, "--title", title, "--json"])
    }

    struct Terminal: Decodable {
        let handle: String
        let worktreeId: String
        let connected: Bool
        let title: String?
        let agentIdentity: String?
        let lastOutputAt: Double?
        let tabId: String?
        let leafId: String?

        var paneKey: String? { tabId.flatMap { tab in leafId.map { "\(tab):\($0)" } } }
    }

    enum Failure: LocalizedError {
        case command(String)
        case noWorktree(String)
        var errorDescription: String? {
            switch self {
            case .command(let message): message
            case .noWorktree(let target): "No worktree for \(target), and no fallbackWorktree in \(Config.file.path)"
            }
        }
    }

    @discardableResult
    static func run(_ arguments: [String]) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: cli)
        process.arguments = arguments
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw Failure.command(message.isEmpty ? "orca \(arguments.first ?? "") failed" : message)
        }
        return data
    }

    private struct Envelope<T: Decodable>: Decodable { let result: T }
    private struct Worktrees: Decodable { let worktrees: [Worktree] }
    private struct Terminals: Decodable { let terminals: [Terminal] }

    static func worktrees() throws -> [Worktree] {
        let data = try run(["worktree", "list", "--json"])
        return try JSONDecoder().decode(Envelope<Worktrees>.self, from: data).result.worktrees.filter { !$0.isArchived }
    }

    static func terminals() throws -> [Terminal] {
        let data = try run(["terminal", "list", "--json"])
        return try JSONDecoder().decode(Envelope<Terminals>.self, from: data).result.terminals
    }

    /// Every worktree that belongs to the item: linked to its issue or PR, or named after them.
    static func candidates(for item: Item, in worktrees: [Worktree]) -> [Worktree] {
        let issue = item.issue?.lowercased()
        return worktrees.filter { w in
            if let issue, w.linkedLinearIssue?.lowercased() == issue || w.displayName.lowercased().contains(issue)
                || w.path.lowercased().contains(issue) { return true }
            if let pr = item.pr, w.linkedPR == pr || w.displayName.contains("\(pr)") || w.path.contains("\(pr)") { return true }
            return false
        }
    }

    static func worktree(for item: Item, in worktrees: [Worktree]) -> Worktree? {
        if let issue = item.issue?.lowercased() {
            if let w = worktrees.first(where: { $0.linkedLinearIssue?.lowercased() == issue }) { return w }
            if let w = worktrees.first(where: { $0.displayName.lowercased().contains(issue) }) { return w }
        }
        if let pr = item.pr {
            if let w = worktrees.first(where: { $0.linkedPR == pr }) { return w }
            if let w = worktrees.first(where: { $0.displayName.contains("\(pr)") }) { return w }
        }
        return nil
    }

    /// The live agent of the item's worktree, if there is one.
    static func agent(for item: Item) throws -> (Worktree, Terminal?)? {
        let all = try worktrees()
        let found = candidates(for: item, in: all)
        guard !found.isEmpty else { return nil }
        let live = try terminals().filter { $0.connected }
        // Prefer the worktree that has an agent, then the one Orca links to the issue or PR.
        for w in found {
            let mine = live.filter { $0.worktreeId == w.id }
            if let agent = mine.first(where: { $0.agentIdentity != nil || ($0.title ?? "").hasPrefix("✳") }) { return (w, agent) }
        }
        let primary = worktree(for: item, in: found) ?? found[0]
        return (primary, live.first { $0.worktreeId == primary.id })
    }

    static func focus(_ terminal: Terminal) throws {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Orca.app"))
        try run(["terminal", "switch", "--terminal", terminal.handle, "--json"])
    }

    static func send(_ text: String, to terminal: Terminal) throws {
        try focus(terminal)
        try run(["terminal", "send", "--terminal", terminal.handle, "--text", text, "--enter", "--json"])
    }

    /// A new Claude in the worktree. SAVEPOINT_ITEM rides along so the hook reports which item the session is for.
    static func newAgent(prompt: String, in worktree: Worktree, item: String? = nil, title: String? = nil) throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("savepoint-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("prompt.txt")
        try prompt.write(to: file, atomically: true, encoding: .utf8)
        let mode = Config.load().permissionMode
        let env = item.map { "SAVEPOINT_ITEM='\($0)' " } ?? ""
        let handle = try launch("\(env)claude --permission-mode \(mode) \"$(cat '\(file.path)')\"; rm -rf '\(dir.path)'", in: worktree)
        if let handle, let title { rename(handle, to: title) }
    }

    /// Brings back a closed Claude conversation in its worktree.
    static func resume(session: String, in worktree: Worktree, item: String) throws {
        let mode = Config.load().permissionMode
        try launch("SAVEPOINT_ITEM='\(item)' claude --permission-mode \(mode) --resume \(session)", in: worktree)
    }

    @discardableResult
    private static func launch(_ command: String, in worktree: Worktree) throws -> String? {
        struct Created: Decodable { struct Result: Decodable { struct T: Decodable { let handle: String }; let terminal: T }; let result: Result }
        NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Orca.app"))
        let data = try run(["terminal", "create", "--worktree", "id:\(worktree.id)", "--command", command, "--focus", "--json"])
        return (try? JSONDecoder().decode(Created.self, from: data))?.result.terminal.handle
    }

    /// The agent tab of a worktree that spoke last.
    static func latestAgent(in worktree: String, _ terminals: [Terminal]) -> Terminal? {
        terminals.filter { $0.worktreeId == worktree && $0.connected && AgentMonitor.isAgent($0) }
            .max { ($0.lastOutputAt ?? 0) < ($1.lastOutputAt ?? 0) }
    }

    /// The Orca terminal a reported session runs in.
    static func terminal(of session: Session, in terminals: [Terminal]) -> Terminal? {
        guard let pane = session.paneKey, !pane.isEmpty else { return nil }
        return terminals.first { $0.connected && $0.paneKey == pane }
    }

    /// Where an item without a worktree of its own gets started.
    static func fallback() throws -> Worktree {
        let path = Config.load().fallbackWorktree
        guard let path, let w = try worktrees().first(where: { $0.path == path }) else {
            throw Failure.noWorktree("this item")
        }
        return w
    }
}

/// ~/Library/Application Support/Save Point/config.json. Nothing personal lives in the code.
struct Config: Codable {
    var fallbackWorktree: String?
    var startPrompt: String = "Start working on {target}: {text}"
    var resumePrompt: String = "Continue with {target}: {text}"
    var permissionMode: String = "auto"

    static let file = Paths.folder.appendingPathComponent("config.json")

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fallbackWorktree = try c.decodeIfPresent(String.self, forKey: .fallbackWorktree)
        startPrompt = try c.decodeIfPresent(String.self, forKey: .startPrompt) ?? startPrompt
        resumePrompt = try c.decodeIfPresent(String.self, forKey: .resumePrompt) ?? resumePrompt
        permissionMode = try c.decodeIfPresent(String.self, forKey: .permissionMode) ?? permissionMode
    }

    static func load() -> Config {
        guard let data = try? Data(contentsOf: file),
              let config = try? JSONDecoder().decode(Config.self, from: data) else { return Config() }
        return config
    }

    func fill(_ template: String, _ item: Item) -> String {
        template.replacingOccurrences(of: "{target}", with: item.target ?? "")
            .replacingOccurrences(of: "{text}", with: item.text)
    }
}
