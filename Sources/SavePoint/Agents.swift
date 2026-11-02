import Foundation
import SwiftUI

/// What the agents of one worktree are doing. First from Claude itself: `scripts/agent-state-hook.sh`, a
/// Claude Code hook, writes each session's state to `sessions/<id>.json` on every turn. Sessions started
/// before the hook existed fall back to Orca's terminal signals:
/// - a Claude terminal whose title starts with a spinner is working; `✳` or no glyph at all means it is waiting;
/// - `lastOutputAt` tells a live spinner from one that froze;
/// - Orca's unread flag says an agent finished and nobody looked yet. It is the only signal for
///   "needs you": `lastOutputAt` also moves when Orca redraws a terminal, so it cannot tell a
///   finished agent from a repainted one.
enum AgentState: String {
    case thinking, needsYou, idle, stuck, none

    var rank: Int {
        switch self {
        case .needsYou: 4
        case .stuck: 3
        case .thinking: 2
        case .idle: 1
        case .none: 0
        }
    }
}

struct AgentStatus: Equatable {
    var state: AgentState
    var agents: Int
    var working: Int
    var lastOutput: Date?
    var title: String?
}

@MainActor
final class AgentMonitor: ObservableObject {
    static let shared = AgentMonitor()

    /// A spinner with no output for this long is shown as possibly stuck.
    nonisolated static let stuckAfter: TimeInterval = 10 * 60

    @Published private(set) var byWorktree: [String: AgentStatus] = [:]
    @Published private(set) var worktrees: [Orca.Worktree] = []
    @Published private(set) var sessions: [Session] = []
    @Published private(set) var terminals: [Orca.Terminal] = []
    @Published private(set) var repos: [Orca.Repo] = []
    @Published private(set) var lastPoll: Date?
    @Published private(set) var error: String?

    private var timer: Timer?
    private var polling = false

    func start() {
        poll()
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in Task { @MainActor in self?.poll() } }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// The most relevant agent state among all the item's worktrees: one waiting for you beats one
    /// thinking, which beats an idle one.
    func status(for item: Item) -> AgentStatus? {
        if let link = Links.get(item), let session = sessions.first(where: { $0.id == link.session }) {
            return Self.fromHooks([session], unread: false, terminals: [])
        }
        if let issue = item.issue, let t = Orca.namedAgent(issue, in: terminals) {
            return terminalStatus(t)
        }
        return Orca.candidates(for: item, in: worktrees)
            .compactMap { byWorktree[$0.id] }
            .filter { $0.state != .none }
            .max { $0.state.rank < $1.state.rank }
    }

    func poll() {
        guard !polling else { return }
        polling = true
        DispatchQueue.global(qos: .utility).async {
            let result = Result { (try Orca.worktrees(), try Orca.terminals()) }
            let sessions = Session.readAll()
            let repos = (try? Orca.repos()) ?? []
            Task { @MainActor in
                self.polling = false
                switch result {
                case .success(let (worktrees, terminals)):
                    self.worktrees = worktrees
                    self.sessions = sessions
                    self.terminals = terminals.filter(\.connected)
                    if !repos.isEmpty { self.repos = repos }
                    Links.adopt(sessions)
                    self.byWorktree = Self.derive(worktrees, terminals, sessions: sessions, now: .now)
                    self.error = nil
                    self.lastPoll = .now
                case .failure(let error):
                    self.error = error.localizedDescription
                }
                self.writeDiagnostics()
            }
        }
    }

    /// agents.json next to today.json: what the monitor saw on its last poll, for debugging.
    private func writeDiagnostics() {
        let rows = worktrees.compactMap { w -> [String: Any]? in
            guard let s = byWorktree[w.id], s.state != .none else { return nil }
            return ["worktree": w.displayName, "state": s.state.rawValue, "agents": s.agents, "working": s.working,
                    "unread": w.isUnread ?? false, "title": s.title ?? ""]
        }
        let out: [String: Any] = ["at": ISO8601DateFormatter().string(from: .now), "error": error ?? NSNull(),
                                  "worktrees": worktrees.count, "agents": rows]
        if let data = try? JSONSerialization.data(withJSONObject: out, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: Paths.folder.appendingPathComponent("agents.json"))
        }
    }

    nonisolated static func derive(_ worktrees: [Orca.Worktree], _ terminals: [Orca.Terminal], sessions: [Session] = [],
                                   now: Date) -> [String: AgentStatus] {
        var out: [String: AgentStatus] = [:]
        let owner = Session.owners(sessions, worktrees)
        for w in worktrees {
            let agents = terminals.filter { $0.worktreeId == w.id && $0.connected && isAgent($0) }
            let reported = sessions.filter { owner[$0.id] == w.id }
            // A worktree marked completed on Orca's board is finished work: its agents do not count.
            if w.workspaceStatus != "completed", !reported.isEmpty {
                out[w.id] = fromHooks(reported, unread: w.isUnread == true, terminals: agents)
                continue
            }
            guard !agents.isEmpty, w.workspaceStatus != "completed" else {
                out[w.id] = AgentStatus(state: .none, agents: 0, working: 0, lastOutput: nil, title: nil)
                continue
            }
            let last = agents.compactMap(\.lastOutputAt).max().map { Date(timeIntervalSince1970: $0 / 1000) }
            let spinning = agents.filter { !isWaiting($0) }
            let live = spinning.filter { t in
                guard let at = t.lastOutputAt else { return false }
                return now.timeIntervalSince(Date(timeIntervalSince1970: at / 1000)) < stuckAfter
            }
            let state: AgentState
            if w.isUnread == true && live.isEmpty {
                state = .needsYou
            } else if !live.isEmpty {
                state = .thinking
            } else if !spinning.isEmpty {
                state = .stuck
            } else {
                state = .idle
            }
            let shown = (live.first ?? agents.max { ($0.lastOutputAt ?? 0) < ($1.lastOutputAt ?? 0) })?.title
            out[w.id] = AgentStatus(state: state, agents: agents.count, working: live.count, lastOutput: last,
                                    title: shown.map(stripGlyph))
        }
        return out
    }

    /// Claude said it: working, waiting for a permission or an answer, or done with its turn. A session whose
    /// process died while working is stuck; a finished turn needs you until you answer or two hours pass.
    nonisolated static func fromHooks(_ sessions: [Session], unread: Bool, terminals: [Orca.Terminal]) -> AgentStatus {
        let working = sessions.filter { $0.state == "working" && $0.alive }
        let state: AgentState
        if sessions.contains(where: { $0.state == "needsYou" && $0.alive }) {
            state = .needsYou
        } else if !working.isEmpty {
            state = .thinking
        } else if sessions.contains(where: { ($0.state == "working" && !$0.alive) || $0.state == "failed" }) {
            state = .stuck
        } else {
            // A finished turn waits for you; after two hours untouched it is just idle.
            let recent = sessions.contains { $0.state == "done" && Date.now.timeIntervalSince1970 - $0.at < 2 * 3600 }
            state = unread || recent ? .needsYou : .idle
        }
        let title = terminals.max { ($0.lastOutputAt ?? 0) < ($1.lastOutputAt ?? 0) }?.title
        let last = sessions.map(\.at).max().map { Date(timeIntervalSince1970: $0) }
        return AgentStatus(state: state, agents: sessions.count, working: working.count, lastOutput: last,
                           title: title.map(stripGlyph))
    }

    /// One agent tab's state: its hook session when it has reported, else its title and output.
    func terminalStatus(_ t: Orca.Terminal) -> AgentStatus {
        let last = t.lastOutputAt.map { Date(timeIntervalSince1970: $0 / 1000) }
        if let s = sessions.first(where: { $0.paneKey != nil && $0.paneKey == t.paneKey }) {
            var status = Self.fromHooks([s], unread: false, terminals: [t])
            status.lastOutput = last ?? status.lastOutput
            return status
        }
        let live = last.map { Date.now.timeIntervalSince($0) < Self.stuckAfter } ?? false
        let state: AgentState = Self.isWaiting(t) ? .idle : live ? .thinking : .stuck
        return AgentStatus(state: state, agents: 1, working: state == .thinking ? 1 : 0, lastOutput: last,
                           title: t.title.map(Self.stripGlyph))
    }

    nonisolated static func isAgent(_ t: Orca.Terminal) -> Bool {
        t.agentIdentity != nil || (t.title ?? "").hasPrefix("✳")
    }

    /// Working means a spinner glyph in front of the title. `✳` is waiting, and since Claude Code 2.1.304 a
    /// waiting session drops the glyph altogether, so a title that starts with a letter is waiting too.
    nonisolated static func isWaiting(_ t: Orca.Terminal) -> Bool {
        let title = t.title ?? ""
        guard let first = title.unicodeScalars.first else { return true }
        return title.hasPrefix("✳") || first.properties.isAlphabetic || CharacterSet.decimalDigits.contains(first)
    }

    nonisolated static func stripGlyph(_ title: String) -> String {
        guard let first = title.unicodeScalars.first, !first.properties.isAlphabetic, !CharacterSet.decimalDigits.contains(first)
        else { return title }
        return String(title.drop(while: { !$0.isLetter && !$0.isNumber })).trimmingCharacters(in: .whitespaces)
    }
}

/// One Claude session as its hook last reported it.
struct Session: Decodable {
    var id = ""
    let state: String
    let cwd: String
    let pid: Int32
    let worktreeId: String?
    let paneKey: String?
    let item: String?
    let at: TimeInterval

    private enum CodingKeys: String, CodingKey { case state, cwd, pid, worktreeId, paneKey, item, at }

    var alive: Bool { pid > 0 && kill(pid, 0) == 0 }

    static let folder = Paths.folder.appendingPathComponent("sessions")

    /// Every reported session. A dead session is dropped, unless it died working less than an hour ago: that one is stuck.
    static func readAll() -> [Session] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }.compactMap { url in
            guard let data = try? Data(contentsOf: url), var s = try? JSONDecoder().decode(Session.self, from: data) else { return nil }
            s.id = url.deletingPathExtension().lastPathComponent
            if !s.alive && (s.state != "working" || Date.now.timeIntervalSince1970 - s.at > 3600) {
                try? FileManager.default.removeItem(at: url)
                return nil
            }
            return s
        }
    }

    /// The worktree of each session: Orca's own id when the hook saw it, else the worktree whose path holds the cwd.
    static func owners(_ sessions: [Session], _ worktrees: [Orca.Worktree]) -> [String: String] {
        var out: [String: String] = [:]
        for s in sessions {
            if let id = s.worktreeId, !id.isEmpty, worktrees.contains(where: { $0.id == id }) {
                out[s.id] = id
            } else if let w = worktrees.filter({ s.cwd == $0.path || s.cwd.hasPrefix($0.path + "/") })
                .max(by: { $0.path.count < $1.path.count }) {
                out[s.id] = w.id
            }
        }
        return out
    }
}

/// A small pill with the agent state of an item's worktree.
struct AgentPill: View {
    @EnvironmentObject private var settings: AppSettings
    let status: AgentStatus

    var body: some View {
        if status.state != .none {
            HStack(spacing: 4) {
                icon
                Text(label).font(.system(size: 10.5, weight: .semibold, design: .rounded))
            }
            .padding(.horizontal, 6).padding(.vertical, 2)
            .foregroundStyle(color)
            .background(color.opacity(0.14), in: Capsule())
            .help(status.title ?? "")
        }
    }

    @ViewBuilder private var icon: some View {
        switch status.state {
        case .thinking: ProgressView().controlSize(.mini).scaleEffect(0.7).frame(width: 10, height: 10)
        case .needsYou: Image(systemName: "bell.fill").font(.system(size: 9))
        case .stuck: Image(systemName: "questionmark.circle.fill").font(.system(size: 9))
        default: Image(systemName: "moon.fill").font(.system(size: 9))
        }
    }

    private var label: String {
        switch status.state {
        case .thinking: status.working > 1 ? "\(L.agentThinking.text) ×\(status.working)" : L.agentThinking.text
        case .needsYou: L.agentNeedsYou.text
        case .stuck: L.agentStuck.text
        case .idle: L.agentIdle.text
        case .none: ""
        }
    }

    private var color: Color {
        switch status.state {
        case .thinking: .blue
        case .needsYou: .orange
        case .stuck: .gray
        default: .secondary
        }
    }
}

/// Every agent open in Orca, project by project (the vault and alan-apps), worktrees nested under their parent,
/// each with its agent tabs and what they are doing. The agent named after the worktree's issue is the main one.
struct AgentsView: View {
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject var monitor: AgentMonitor

    static let projects = ["vault", "alan-apps"]
    /// Worktrees that live without an issue on purpose (also any whose name starts with 🚫, the automation ones).
    static let special: Set<String> = ["main", "daily", "auditor"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(L.agents.text).font(.system(size: 24, weight: .bold, design: .rounded))
                    Spacer()
                    if let at = monitor.lastPoll { Text("\(L.updatedAt.text) \(Self.time(at))").font(.caption).foregroundStyle(.secondary) }
                }
                if let error = monitor.error { Text(error).font(.caption).foregroundStyle(.red) }
                ForEach(Self.projects, id: \.self) { name in
                    if let repo = monitor.repos.first(where: { $0.displayName == name }) {
                        Card(title: name, icon: "folder") {
                            ForEach(roots(of: repo.id), id: \.id) { tree($0, depth: 0) }
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 900, alignment: .leading)
        }
    }

    private func worktrees(of repo: String) -> [Orca.Worktree] {
        monitor.worktrees.filter { $0.repoId == repo || $0.id.hasPrefix(repo + "::") }
    }

    private func roots(of repo: String) -> [Orca.Worktree] {
        let all = worktrees(of: repo)
        let ids = Set(all.map(\.id))
        return all.filter { $0.parentWorktreeId.map { !ids.contains($0) } ?? true }.sorted(by: order)
    }

    /// What hangs from "🚫 Don't remove" is special and stays out of the list.
    private func children(of w: Orca.Worktree) -> [Orca.Worktree] {
        guard !w.displayName.localizedCaseInsensitiveContains("don't remove") else { return [] }
        return monitor.worktrees.filter { $0.parentWorktreeId == w.id }.sorted(by: order)
    }

    private func order(_ a: Orca.Worktree, _ b: Orca.Worktree) -> Bool {
        if a.isMainWorktree != b.isMainWorktree { return a.isMainWorktree }
        return a.displayName.localizedStandardCompare(b.displayName) == .orderedAscending
    }

    private func agents(in w: Orca.Worktree) -> [Orca.Terminal] {
        let issue = Orca.issuePrefix(w.displayName) ?? w.linkedLinearIssue?.uppercased()
        return monitor.terminals.filter { $0.worktreeId == w.id && AgentMonitor.isAgent($0) }
            .sorted { a, b in
                let am = issue.map { Orca.mentions(a.title ?? "", $0) } ?? false
                let bm = issue.map { Orca.mentions(b.title ?? "", $0) } ?? false
                return am != bm ? am : (a.lastOutputAt ?? 0) > (b.lastOutputAt ?? 0)
            }
    }

    private func tree(_ w: Orca.Worktree, depth: Int) -> AnyView {
        let issue = Orca.issuePrefix(w.displayName) ?? w.linkedLinearIssue?.uppercased()
        let missing = Orca.issuePrefix(w.displayName) == nil && !w.isMainWorktree && !Self.special.contains(w.displayName)
            && !w.displayName.hasPrefix("🚫")
        return AnyView(VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: depth == 0 ? "square.stack.3d.up" : "arrow.turn.down.right").font(.caption).foregroundStyle(.secondary)
                Text(w.displayName).font(.system(size: 13, weight: .bold))
                if missing { Chip(text: L.noIssue.text).foregroundStyle(.orange) }
                Spacer()
                if let status = monitor.byWorktree[w.id], status.state != .none { AgentPill(status: status) }
            }
            ForEach(agents(in: w), id: \.handle) { t in
                let status = monitor.terminalStatus(t)
                let main = issue.map { Orca.mentions(t.title ?? "", $0) } ?? false
                Button { try? Orca.focus(t) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: main ? "star.fill" : "circle.fill").font(.system(size: main ? 9 : 5))
                            .foregroundStyle(main ? .yellow : .secondary).frame(width: 12)
                        Text(AgentMonitor.stripGlyph(t.title ?? "")).font(.callout).lineLimit(1)
                        Spacer()
                        Text(status.lastOutput.map(Self.ago) ?? "").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        AgentPill(status: status)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.leading, 22)
            }
            ForEach(children(of: w), id: \.id) { tree($0, depth: depth + 1) }
                .padding(.leading, 16)
        }
        .padding(.vertical, 4).padding(.horizontal, 10))
    }

    static func time(_ d: Date) -> String { SlackWindows.hm(d) }

    static func ago(_ d: Date) -> String {
        let s = Int(Date.now.timeIntervalSince(d))
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s / 60)m" }
        return "\(s / 3600)h"
    }
}

/// Which Claude session works on which item, so a click goes back to that conversation and never searches again.
/// Kept in UserDefaults across days: an issue keeps its session until the session is gone for good.
enum Links {
    struct Link: Codable { let session: String; let worktree: String }

    private static let key = "itemSessions"

    private static func all() -> [String: Link] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let links = try? JSONDecoder().decode([String: Link].self, from: data) else { return [:] }
        return links
    }

    static func get(_ item: Item) -> Link? { all()[item.linkKey] }

    static func set(_ item: Item, session: String, worktree: String) { set(item.linkKey, Link(session: session, worktree: worktree)) }

    static func forget(_ item: Item) { set(item.linkKey, nil) }

    private static func set(_ key: String, _ link: Link?) {
        var links = all()
        links[key] = link
        if let data = try? JSONEncoder().encode(links) { UserDefaults.standard.set(data, forKey: Self.key) }
    }

    /// A session Save Point launched carries its item in SAVEPOINT_ITEM: the hook reports it and it is linked here.
    static func adopt(_ sessions: [Session]) {
        for s in sessions {
            guard let item = s.item, !item.isEmpty, let worktree = s.worktreeId, !worktree.isEmpty,
                  all()[item]?.session != s.id else { continue }
            set(item, Link(session: s.id, worktree: worktree))
        }
    }
}

extension Item {
    /// Stable across edits of the line: the issue, else the PR, else a hash of the heading without status icons.
    var linkKey: String {
        if let issue { return issue }
        if let pr { return "pr-\(pr)" }
        var hash: UInt64 = 1469598103934665603
        for byte in heading.trimmingCharacters(in: .whitespaces).utf8 { hash = (hash ^ UInt64(byte)) &* 1099511628211 }
        return "t-" + String(hash, radix: 16)
    }
}
