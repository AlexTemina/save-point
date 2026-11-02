import Foundation

/// The state of every Linear issue in today's plan, read through `orca linear issue` and kept in
/// linear.json next to today.json. Linear owns task state: the Daily only says which issues and in
/// what order, so an open line whose issue is closed shows as done here and in export-daily.
@MainActor
final class LinearStates: ObservableObject {
    static let shared = LinearStates()

    struct Entry: Codable, Equatable {
        let name: String
        let type: String
        let at: TimeInterval
        var qa: [QA]? = nil
        var children: [Sub]? = nil
    }

    /// A sub-issue as cached: export-daily turns its state into a status.
    struct Sub: Codable, Equatable { let issue: String; let title: String; let url: String; let name: String; let type: String; let qa: [QA] }

    nonisolated static let file = Paths.folder.appendingPathComponent("linear.json")

    @Published private(set) var byIssue: [String: Entry] = LinearStates.read()

    private var timer: Timer?
    private var polling = false

    func start() {
        guard timer == nil else { return }
        poll()
        let timer = Timer(timeInterval: 90, repeats: true) { [weak self] _ in Task { @MainActor in self?.poll() } }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func poll() {
        guard !polling, let day = Self.today() else { return }
        let issues = Array(Set(day.allItems.compactMap(\.issue) + (day.contract?.tres.flatMap(\.issues) ?? [])))
        guard !issues.isEmpty else { return }
        polling = true
        DispatchQueue.global(qos: .utility).async {
            var found: [String: Entry] = [:]
            let lock = NSLock()
            DispatchQueue.concurrentPerform(iterations: issues.count) { i in
                guard let entry = Self.fetch(issues[i]) else { return }
                lock.lock(); found[issues[i]] = entry; lock.unlock()
            }
            Task { @MainActor in
                self.polling = false
                let merged = self.byIssue.merging(found) { _, new in new }
                guard merged != self.byIssue else { return }
                self.byIssue = merged
                if let data = try? JSONEncoder().encode(merged) { try? data.write(to: Self.file, options: .atomic) }
                Actions.store?.load(force: true)
            }
        }
    }

    /// A goal of the week is met when every issue it names is closed in Linear.
    func done(_ goal: Contract.Goal) -> Bool {
        goal.done || (!goal.issues.isEmpty && goal.issues.allSatisfy { ["completed", "canceled"].contains(byIssue[$0]?.type ?? "") })
    }

    /// Linear's verdict on a line that the Daily leaves open: done when the issue is completed, dropped when cancelled,
    /// waiting while it is in Pending for inputs.
    func status(of issue: String) -> String? {
        if byIssue[issue]?.name == "Pending for inputs" { return "waiting" }
        return switch byIssue[issue]?.type {
        case "completed": "done"
        case "canceled": "dropped"
        default: nil
        }
    }

    private struct Issue: Decodable {
        struct State: Decodable { let name: String; let type: String }
        let identifier: String?
        let title: String?
        let url: String?
        let description: String?
        let state: State
    }

    nonisolated private static func fetch(_ issue: String) -> Entry? {
        struct Reply: Decodable { struct Result: Decodable { let issue: Issue }; let result: Result }
        struct Children: Decodable { struct Result: Decodable { let issues: [Issue] }; let result: Result }
        guard let data = try? Orca.run(["linear", "issue", "--id", issue, "--json"]),
              let reply = try? JSONDecoder().decode(Reply.self, from: data) else { return nil }
        let found = reply.result.issue
        var subs: [Sub]? = nil
        if let data = try? Orca.run(["linear", "list-issues", "--parent-id", issue, "--json"]),
           let list = try? JSONDecoder().decode(Children.self, from: data) {
            subs = list.result.issues.compactMap { c in
                guard let id = c.identifier else { return nil }
                return Sub(issue: id, title: c.title ?? id, url: c.url ?? "", name: c.state.name, type: c.state.type, qa: qa(c.description))
            }.sorted { $0.issue < $1.issue }
        }
        return Entry(name: found.state.name, type: found.state.type, at: Date.now.timeIntervalSince1970,
                     qa: qa(found.description), children: subs)
    }

    /// The checks of a `## QA` section, one per top-level bullet, continuation lines joined.
    nonisolated static func qa(_ description: String?) -> [QA] {
        guard let description else { return [] }
        var checks: [QA] = []
        var inside = false
        for raw in description.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#") { inside = line.lowercased().hasPrefix("## qa"); continue }
            guard inside, !line.isEmpty else { continue }
            if raw.hasPrefix("- ") || raw.hasPrefix("* ") {
                var text = String(line.dropFirst(2))
                var done = false
                if text.hasPrefix("[ ] ") { text = String(text.dropFirst(4)) }
                else if text.lowercased().hasPrefix("[x] ") { text = String(text.dropFirst(4)); done = true }
                checks.append(QA(text: text, done: done))
            } else if let last = checks.popLast() {
                checks.append(QA(text: last.text + " " + line, done: last.done))
            }
        }
        return checks
    }

    /// Today's plan as the exporter wrote it, without any overlay: only its issues matter here.
    nonisolated private static func today() -> Day? {
        guard let data = try? Data(contentsOf: Paths.dayFile) else { return nil }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try? decoder.decode(Day.self, from: data)
    }

    nonisolated private static func read() -> [String: Entry] {
        guard let data = try? Data(contentsOf: file), let entries = try? JSONDecoder().decode([String: Entry].self, from: data)
        else { return [:] }
        return entries
    }
}
