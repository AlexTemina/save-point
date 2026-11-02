import SwiftUI

/// The two layers of attention: the Misión principal and the Misiones secundarias.
enum Planet: Int, CaseIterable, Identifiable, Codable {
    case mainQuest = 1, sideQuests
    var id: Int { rawValue }

    @MainActor var name: String {
        switch self {
        case .mainQuest: L.layerMain.text
        case .sideQuests: L.layerSide.text
        }
    }

    var icon: String {
        switch self {
        case .mainQuest: "flame.fill"
        case .sideQuests: "circle.bottomhalf.filled"
        }
    }

    var tone: Color {
        switch self {
        case .mainQuest: .orange
        case .sideQuests: .purple
        }
    }

    @MainActor var role: String {
        switch self {
        case .mainQuest: L.roleFrog.text
        case .sideQuests: L.roleWhileFrog.text
        }
    }

    var below: Planet? { Planet(rawValue: rawValue + 1) }
    var above: Planet? { Planet(rawValue: rawValue - 1) }
}

/// Where he is and what is active on each planet. Local to this Mac, one record per day.
@MainActor
final class Journey: ObservableObject {
    static let shared = Journey()

    @Published var current: Planet = .mainQuest { didSet { save() } }
    @Published private var active: [Int: String] = [:]
    @Published private var frogOverride: String?
    @Published private(set) var forcedDescents: [String] = []
    @Published private var started: Set<String> = []
    private var date = ""

    func sync(_ day: Day) {
        guard day.date != date else { return }
        date = day.date
        let saved = UserDefaults.standard.dictionary(forKey: "journey-\(day.date)") ?? [:]
        current = Planet(rawValue: saved["current"] as? Int ?? 1) ?? .mainQuest
        active = (saved["active"] as? [String: String] ?? [:]).reduce(into: [:]) { r, kv in
            if let k = Int(kv.key) { r[k] = kv.value }
        }
        frogOverride = saved["frog"] as? String
        forcedDescents = saved["forced"] as? [String] ?? []
        started = Set(saved["started"] as? [String] ?? [])
    }

    private func save() {
        guard !date.isEmpty else { return }
        var record: [String: Any] = ["current": current.rawValue,
                                     "active": Dictionary(uniqueKeysWithValues: active.map { ("\($0.key)", $0.value) }),
                                     "forced": forcedDescents, "started": Array(started)]
        if let frogOverride { record["frog"] = frogOverride }
        UserDefaults.standard.set(record, forKey: "journey-\(date)")
    }

    // MARK: Items

    func items(_ planet: Planet, _ day: Day) -> [Item] {
        if let quests = day.quests {
            switch planet {
            case .mainQuest: return frog(day).map { [$0] } ?? []
            case .sideQuests: return quests.side.filter { $0.md != frog(day)?.md && !$0.isWaiting }
            }
        }
        if let layers = day.layers {
            switch planet {
            case .mainQuest: return frog(day).map { [$0] } ?? []
            case .sideQuests: return (layers.sideQuests + layers.collectibles).filter { $0.md != frog(day)?.md && !$0.isWaiting }
            }
        }
        switch planet {
        case .mainQuest: return day.focus.map { [$0] } ?? []
        case .sideQuests: return (day.queue + day.decisions + day.parallel).filter { !$0.isWaiting }
        }
    }

    /// What left Brittle Hollow because it waits on someone else, in the Daily's order.
    func waiting(_ day: Day) -> [Item] {
        (day.quests?.side ?? day.layers?.sideQuests ?? day.queue + day.decisions + day.parallel).filter(\.isWaiting)
    }

    func frog(_ day: Day) -> Item? {
        if let id = frogOverride, let promoted = (day.quests?.side ?? day.layers?.sideQuests ?? day.queue).first(where: { $0.md == id }) {
            return promoted
        }
        let main = day.quests?.main ?? day.layers?.mainQuest ?? []
        return main.first(where: \.isOpen) ?? main.first ?? day.focus
    }

    func activeItem(_ planet: Planet, _ day: Day) -> Item? {
        let list = items(planet, day)
        if let id = active[planet.rawValue], let item = list.first(where: { $0.md == id && $0.isOpen }) { return item }
        return list.first(where: \.isOpen)
    }

    func nextItem(_ planet: Planet, _ day: Day) -> Item? {
        let list = items(planet, day)
        let current = activeItem(planet, day)
        return list.first { $0.isOpen && $0.md != current?.md }
    }

    func planet(of item: Item, _ day: Day) -> Planet? {
        Planet.allCases.first { items($0, day).contains { $0.md == item.md } }
    }

    // MARK: Moves

    func activate(_ item: Item, in day: Day?) {
        guard let day, let planet = planet(of: item, day), planet != .mainQuest else { return }
        active[planet.rawValue] = item.md
        started.insert(item.md)
        save()
    }

    func isStarted(_ item: Item) -> Bool { started.contains(item.md) }

    /// The frog is done: the chosen Brittle Hollow item becomes the frog.
    func promote(_ item: Item) {
        frogOverride = item.md
        active[Planet.sideQuests.rawValue] = nil
        current = .mainQuest
        save()
    }

    func descend(from planet: Planet, forced reason: String? = nil) {
        guard let below = planet.below else { return }
        if let reason { forcedDescents.append("\(SlackWindows.hm(.now)) \(planet.name) → \(below.name): \(reason)") }
        current = below
    }

    func ascend(to planet: Planet) { current = planet }
}
