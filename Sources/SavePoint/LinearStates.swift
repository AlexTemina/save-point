import Foundation

/// The state of every Linear issue in today's plan, read through `orca linear issue` and kept in
/// linear.json next to today.json. Linear owns task state: the Daily only says which issues and in
/// what order, so an open line whose issue is closed shows as done here and in export-daily.
@MainActor
final class LinearStates: ObservableObject {
    static let shared = LinearStates()

    struct Entry: Codable, Equatable { let name: String; let type: String; let at: TimeInterval }

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

    nonisolated private static func fetch(_ issue: String) -> Entry? {
        struct Reply: Decodable {
            struct Result: Decodable { let issue: Issue }
            struct Issue: Decodable { let state: State }
            struct State: Decodable { let name: String; let type: String }
            let result: Result
        }
        guard let data = try? Orca.run(["linear", "issue", "--id", issue, "--json"]),
              let reply = try? JSONDecoder().decode(Reply.self, from: data) else { return nil }
        return Entry(name: reply.result.issue.state.name, type: reply.result.issue.state.type, at: Date.now.timeIntervalSince1970)
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
