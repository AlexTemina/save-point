import Foundation

struct Link: Codable, Hashable {
    let title: String
    let url: String
}

struct Item: Codable, Hashable, Identifiable {
    var id: String { md }
    let text: String
    let md: String
    let status: String
    let size: String?
    let tags: [String]
    let links: [Link]
    let issue: String?
    let pr: Int?
    var kind: String? = nil
    /// Quest fields: who and what it is, its step in the Misión principal, the agents on it, its sub-issues and QA.
    var title: String? = nil
    var labels: [String]? = nil
    var step: Int? = nil
    var agents: [Item]? = nil
    var children: [Child]? = nil
    var qa: [QA]? = nil

    var isOpen: Bool { status == "open" }

    /// In Pending for inputs: out of the queue until someone else answers.
    var isWaiting: Bool { status == "waiting" }

    var icon: String {
        switch status {
        case "done": "✅"
        case "moved": "↪️"
        case "snoozed": "💤"
        case "skipped": "⏭️"
        case "dropped": "❌"
        case "waiting": "⏳"
        default: "○"
        }
    }

    /// What identifies the work in Orca: a Linear issue, else a PR number.
    var target: String? { issue ?? pr.map { "#\($0)" } }

    /// The Linear issue or PR the line is about: its first link.
    var primary: Link? { links.first }

    /// The line without its leading link, when the line starts with it.
    var detail: String? {
        guard let title = primary?.title, text.hasPrefix(title) else { return primary == nil ? nil : text }
        let rest = text.dropFirst(title.count).trimmingCharacters(in: CharacterSet(charactersIn: ":,.;—- ").union(.whitespaces))
        return rest.isEmpty ? nil : rest.prefix(1).uppercased() + rest.dropFirst()
    }

    var heading: String { primary?.title ?? text }
}

/// One sub-issue of a quest that is a Linear parent.
struct Child: Codable, Hashable, Identifiable {
    var id: String { issue }
    let issue: String
    let title: String
    let url: String?
    let status: String?
    let qa: [QA]?
}

/// One check of an issue's `## QA` section.
struct QA: Codable, Hashable {
    let text: String
    let done: Bool
}

/// The day as quests: every quest a Linear issue. Events are meetings, never quests.
struct Quests: Codable {
    let main: [Item]
    let side: [Item]
    let events: [Item]
    let unlinked: [String]
}

/// A timeline line, `HH:MM ✅ what happened`.
struct Event: Identifiable, Hashable {
    let id: String
    let time: String
    let mark: String
    let item: Item

    init?(_ item: Item) {
        let parts = item.text.split(separator: " ", maxSplits: 2).map(String.init)
        guard parts.count == 3, parts[0].count == 5, parts[0].dropFirst(2).first == ":" else { return nil }
        id = item.md
        time = parts[0]
        mark = parts[1]
        self.item = item
    }

    var text: String { item.text.split(separator: " ", maxSplits: 2).dropFirst(2).joined() }

    /// What kind of event it is, from the words in it.
    var symbol: String {
        let t = text.lowercased()
        if mark == "↔" || mark == "↔️" { return "arrow.down.right.circle.fill" }
        if mark == "❌" { return "xmark.octagon.fill" }
        if t.contains("review") { return "checkmark.bubble.fill" }
        if t.contains("merge") || t.contains("pr ") || t.contains("prs") { return "arrow.triangle.merge" }
        if t.contains("auditor") || t.contains("apply") { return "binoculars.fill" }
        if t.contains("standup") || t.contains("slack") || t.contains("mensaje") || t.contains("contestad") || t.contains("message") { return "bubble.left.and.bubble.right.fill" }
        if t.contains("reunión") || t.contains("meeting") || t.contains("café") || t.contains("coffee") { return "person.2.fill" }
        if t.contains("spike") || t.contains("agente") || t.contains("agent") || t.contains("commit") { return "hammer.fill" }
        if t.contains("done") || t.contains("cerrad") || t.contains("closed") { return "checkmark.seal.fill" }
        if t.contains("feedback") || t.contains("shoutout") { return "hand.thumbsup.fill" }
        return "circle.fill"
    }
}

struct Quadrant: Codable, Identifiable {
    let id: String
    let title: String
    let axis: String
    let items: [Item]
}

struct Matrix: Codable {
    let quadrants: [Quadrant]
    let split: String?
}

struct Slot: Codable, Hashable, Identifiable {
    var id: String { time + title }
    let time: String
    let title: String
    let text: String
}

struct DaySection: Codable, Identifiable {
    var id: String { title }
    let title: String
    let items: [Item]
}

struct Progress: Codable {
    let done: Int
    let total: Int
    let frogDone: Bool?

    /// The frog makes the day, so it weighs a third of the ring and the rest of the queue shares the other two thirds.
    static let frogWeight = 0.33

    var fraction: Double {
        let queue = total == 0 ? 0 : Double(done) / Double(total)
        guard let frogDone else { return queue }
        let frog = frogDone ? 1.0 : 0
        return total == 0 ? frog : Self.frogWeight * frog + (1 - Self.frogWeight) * queue
    }
}

struct Day: Codable {
    let date: String
    let eyebrow: String
    let week: String?
    let focus: Item?
    let slots: [Slot]
    let queue: [Item]
    let parallel: [Item]
    let decisions: [Item]
    let whileWaiting: String?
    let notToday: [Item]
    let sections: [DaySection]
    let matrix: Matrix?
    let layers: Layers?
    let quests: Quests?
    let contract: Contract?
    let progress: Progress

    var next: Item? { queue.first(where: \.isOpen) }

    /// Every task line of the day's plan, wherever it sits.
    var allItems: [Item] {
        [focus].compactMap { $0 } + queue + parallel + decisions + notToday + sections.flatMap(\.items)
            + (quests.map { $0.main + $0.side } ?? [])
    }
}


struct Layers: Codable {
    let mainQuest: [Item]
    let sideQuests: [Item]
    let collectibles: [Item]
}


/// The week's contract (Alan week, Wednesday to Tuesday): Las Tres and how each day served them.
struct Contract: Codable {
    struct Goal: Codable, Identifiable {
        var id: Int { n }
        let n: Int
        let text: String
        let links: [Link]
        let issues: [String]
        let done: Bool
    }
    struct DayRow: Codable, Identifiable {
        var id: String { day }
        let day: String
        let una: String?
        let serves: String?
        let outcome: String?
        let parallels: String?
    }
    let date: String
    let title: String?
    let confirmed: Bool
    let tres: [Goal]
    let days: [DayRow]
}
