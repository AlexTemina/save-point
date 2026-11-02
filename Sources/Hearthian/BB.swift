import AppKit
import Foundation

/// bb, the other agent app, through its CLI. The robot's path, in bb, counting only Claude threads:
/// 1. The thread that names the item's issue.
/// 2. Else the thread that moved last in the item's Orca worktree.
/// 3. Else a new thread in that worktree, with the resume prompt.
/// 4. Else a new thread in the fallback worktree: /start-task when there is a target, the item's text when not.
enum BB {
    static let cli = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".bb/bin/bb").path
    static let app = URL(fileURLWithPath: "/Applications/bb.app")
    static let provider = "claude-code"

    struct Thread: Decodable {
        let id: String
        let providerId: String?
        let title: String?
        let titleFallback: String?
        let environmentBranchName: String?
        let environmentPath: String?
        let updatedAt: Double?
    }

    struct Project: Decodable {
        struct Source: Decodable { let path: String? }
        let id: String
        let sources: [Source]
    }

    static func threads() throws -> [Thread] {
        try JSONDecoder().decode([Thread].self, from: run(["thread", "list", "--json"])).filter { $0.providerId == provider }
    }

    /// The thread that names the issue in its title or branch, the one that moved last.
    static func thread(for item: Item, in threads: [Thread]) -> Thread? {
        guard let issue = item.issue else { return nil }
        return threads.filter { t in
            [t.title, t.titleFallback, t.environmentBranchName].contains { Orca.mentions($0 ?? "", issue) }
        }
        .max { ($0.updatedAt ?? 0) < ($1.updatedAt ?? 0) }
    }

    static func open(_ item: Item) throws {
        NSWorkspace.shared.open(app)
        let threads = try threads()
        if let t = thread(for: item, in: threads) { return try show(t.id) }
        let config = Config.load()
        if let (worktree, _) = try Orca.agent(for: item) {
            if let t = threads.filter({ $0.environmentPath == worktree.path }).max(by: { ($0.updatedAt ?? 0) < ($1.updatedAt ?? 0) }) {
                return try show(t.id)
            }
            let title = item.issue.map { "\($0) — \(item.heading.replacingOccurrences(of: "\($0) — ", with: ""))" }
            return try show(spawn(config.fill(config.resumePrompt, item), in: worktree.path, title: title))
        }
        guard let path = config.fallbackWorktree else { throw Orca.Failure.noWorktree("this item") }
        let prompt = item.target == nil ? item.text : config.fill(config.startPrompt, item)
        try show(spawn(prompt, in: path, title: nil))
    }

    static func show(_ thread: String) throws {
        try run(["thread", "open", thread, "--json"])
    }

    /// A new thread on the folder as it is, in the bb project of its repository.
    static func spawn(_ prompt: String, in path: String, title: String?) throws -> String {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("hearthian-bb-\(UUID().uuidString).txt")
        try prompt.write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }
        // Claude, as the robot: without it bb takes the project's remembered provider, which can be Codex.
        var arguments = ["thread", "spawn", "--provider", provider, "--prompt-file", file.path, "--environment", path, "--json"]
        if let project = try project(for: path) { arguments += ["--project", project] }
        if let title { arguments += ["--title", title] }
        if let mode = permissionMode(Config.load().permissionMode) { arguments += ["--permission-mode", mode] }
        return try JSONDecoder().decode(Thread.self, from: run(arguments)).id
    }

    /// The project whose source is the folder's repository: an Orca worktree shares its main checkout's .git.
    static func project(for path: String) throws -> String? {
        let projects = try JSONDecoder().decode([Project].self, from: run(["project", "list", "--json"]))
        let root = repositoryRoot(path)
        return projects.first { p in p.sources.contains { $0.path == path || $0.path == root } }?.id
    }

    static func repositoryRoot(_ path: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", path, "rev-parse", "--path-format=absolute", "--git-common-dir"]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()
        guard (try? process.run()) != nil else { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0, let dir = String(data: data, encoding: .utf8) else { return nil }
        return URL(fileURLWithPath: dir.trimmingCharacters(in: .whitespacesAndNewlines)).deletingLastPathComponent().path
    }

    /// Claude's permission modes in bb's words. One bb does not have is left to the project's default.
    static func permissionMode(_ claude: String) -> String? {
        switch claude {
        case "auto": "auto"
        case "acceptEdits": "accept-edits"
        case "bypassPermissions": "full"
        default: nil
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
            throw Orca.Failure.command(message.isEmpty ? "bb \(arguments.first ?? "") failed" : message)
        }
        return data
    }
}
