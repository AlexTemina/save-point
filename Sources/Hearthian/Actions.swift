import AppKit
import Foundation

/// What a row can do. Orca calls run off the main thread; failures surface in the store.
@MainActor
enum Actions {
    static weak var store: Store?

    static func open(_ item: Item) {
        if let link = item.links.first { open(link) }
    }

    static func open(_ link: Link) {
        if let url = URL(string: link.url) { NSWorkspace.shared.open(url) }
    }

    /// The item becomes the active one of its planet.
    static func activate(_ item: Item) {
        Journey.shared.activate(item, in: store?.day)
    }

    /// Links the item to a session by hand: one from the menu, or an id pasted from the clipboard.
    static func link(_ item: Item, to session: String) {
        let worktrees = AgentMonitor.shared.worktrees
        guard let s = Session.readAll().first(where: { $0.id == session }),
              let worktree = Session.owners([s], worktrees)[s.id] else { return store?.report(L.noSessionInClipboard.text) ?? () }
        Links.set(item, session: s.id, worktree: worktree)
    }

    /// How a session reads in the menu: the agent's tab title, then its worktree.
    static func label(of session: Session) -> String {
        let monitor = AgentMonitor.shared
        let worktree = Session.owners([session], monitor.worktrees)[session.id]
            .flatMap { id in monitor.worktrees.first { $0.id == id }?.displayName } ?? session.cwd
        guard let tab = Orca.terminal(of: session, in: monitor.terminals)?.title else {
            return "\(worktree) · \(session.id.prefix(8))"
        }
        return "\(AgentMonitor.stripGlyph(tab)) — \(worktree)"
    }

    static func copy(_ item: Item) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.md, forType: .string)
    }

    /// 1. The agent tab named after the item's issue.
    /// 2. Else the item's linked Claude session: its terminal, or the conversation resumed if it closed.
    /// 3. Else the live agent in the item's worktree (by issue or PR), which becomes the linked one.
    /// 4. Else a new agent: in that worktree, or /start-task from the fallback one when there is an issue.
    /// Agents launched here carry HEARTHIAN_ITEM, so the hook links them on the next poll.
    static func jump(_ item: Item) {
        activate(item)
        perform {
            let config = Config.load()
            let key = item.linkKey
            let worktrees = try Orca.worktrees()
            let terminals = try Orca.terminals().filter(\.connected)
            let sessions = Session.readAll()

            // The tab named after the issue wins over the link: the link may be the session that ran /start-task.
            if let issue = item.issue, let t = Orca.namedAgent(issue, in: terminals) {
                if let s = sessions.first(where: { $0.paneKey == t.paneKey && $0.alive }) {
                    Links.set(item, session: s.id, worktree: t.worktreeId)
                }
                return try Orca.focus(t)
            }

            if let link = Links.get(item) {
                let session = sessions.first { $0.id == link.session }
                if let s = session, s.alive {
                    // Never resume a live session: that opens a second tab on the same conversation.
                    if let t = Orca.terminal(of: s, in: terminals) ?? Orca.latestAgent(in: link.worktree, terminals) {
                        return try Orca.focus(t)
                    }
                } else if let w = worktrees.first(where: { $0.id == link.worktree }) {
                    return try Orca.resume(session: link.session, in: w, item: key)
                } else {
                    Links.forget(item)
                }
            }

            guard let (worktree, _) = try Orca.agent(for: item) else {
                // HEARTHIAN_ITEM links the agent started here, so the next click comes back to it when /start-task
                // keeps the work in this session. When it opens a worktree, that agent's named tab wins above.
                guard item.target != nil else { return try Orca.newAgent(prompt: item.text, in: try Orca.fallback(), item: key) }
                return try Orca.newAgent(prompt: config.fill(config.startPrompt, item), in: try Orca.fallback(), item: key)
            }
            let owner = Session.owners(sessions, worktrees)
            let live = sessions.filter { owner[$0.id] == worktree.id && $0.alive }.sorted { $0.at > $1.at }
            if let s = live.first(where: { Orca.terminal(of: $0, in: terminals) != nil }), let t = Orca.terminal(of: s, in: terminals) {
                Links.set(item, session: s.id, worktree: worktree.id)
                return try Orca.focus(t)
            }
            if let t = terminals.first(where: { $0.worktreeId == worktree.id && AgentMonitor.isAgent($0) }) {
                return try Orca.focus(t)
            }
            try Orca.newAgent(prompt: config.fill(config.resumePrompt, item), in: worktree, item: key,
                              title: item.issue.map { "\($0) — \(item.heading.replacingOccurrences(of: "\($0) — ", with: ""))" })
        }
    }

    /// A message for the live agent of the item's worktree. No live agent: a new one gets it.
    static func message(_ text: String, to item: Item) {
        activate(item)
        perform {
            if let link = Links.get(item), let s = Session.readAll().first(where: { $0.id == link.session }), s.alive,
               let t = Orca.terminal(of: s, in: try Orca.terminals()) {
                return try Orca.send(text, to: t)
            }
            if let (worktree, terminal) = try Orca.agent(for: item) {
                if let terminal { try Orca.send(text, to: terminal) } else {
                    try Orca.newAgent(prompt: text, in: worktree, item: item.linkKey)
                }
            } else {
                let config = Config.load()
                try Orca.newAgent(prompt: "\(config.fill(config.startPrompt, item))\n\n\(text)", in: try Orca.fallback(), item: item.linkKey)
            }
        }
    }

    /// Always a fresh agent, in the item's worktree or the fallback one.
    static func newAgent(_ prompt: String, for item: Item) {
        activate(item)
        perform {
            let worktree = try Orca.agent(for: item)?.0 ?? Orca.fallback()
            try Orca.newAgent(prompt: prompt, in: worktree, item: item.linkKey)
        }
    }

    static func startPrompt(for item: Item) -> String {
        let config = Config.load()
        return config.fill(config.startPrompt, item)
    }

    /// The robot's path, in bb.
    static func openInBB(_ item: Item) {
        activate(item)
        perform { try BB.open(item) }
    }

    private static func perform(_ work: @escaping @Sendable () throws -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            do { try work() } catch {
                let message = error.localizedDescription
                Task { @MainActor in store?.report(message) }
            }
        }
    }
}
