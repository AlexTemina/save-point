import ServiceManagement
import SwiftUI

enum Page: Hashable {
    case planet(Planet)
    case today, matrix, parallel, decisions, notToday, agents
    case section(String)
}

struct MainWindow: View {
    @ObservedObject var store: Store
    @ObservedObject private var monitor = AgentMonitor.shared
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject private var journey = Journey.shared
    @AppStorage("showAllPlanets") private var showAllPlanets = true
    @State private var page: Page? = .planet(.mainQuest)

    var body: some View {
        NavigationSplitView {
            sidebar.navigationSplitViewColumnWidth(min: 200, ideal: 230)
        } detail: {
            if let day = store.day {
                detail(day, page ?? .planet(journey.current))
                    .id(page)
                    .onAppear { journey.sync(day); page = .planet(journey.current) }
            } else {
                DayView(store: store, compact: false)
            }
        }
        .onChange(of: journey.current) { _, planet in page = .planet(planet) }
        .onChange(of: page) { _, value in if case .planet(let p) = value, p != journey.current { journey.current = p } }
        .navigationTitle(store.day?.eyebrow ?? "Save Point")
        .navigationSubtitle(store.updated.map { "\(L.updatedAt.text) \(SlackWindows.hm($0))" } ?? "")
        .toolbar {
            ToolbarItem {
                Button { store.load(force: true) } label: { Label(L.reload.text, systemImage: "arrow.clockwise") }
                    .keyboardShortcut("r")
                    .help(L.reload.text)
            }
        }
        .overlay(alignment: .bottom) { failure }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        List(selection: $page) {
            if let day = store.day {
                Section("Save Point") {
                    ForEach(Planet.allCases.filter { showAllPlanets || $0 == journey.current }) { planet in
                        planetRow(planet, day)
                    }
                }
                Section {
                    row(.today, L.appTitle.text, "doc.text", "\(day.progress.done)/\(day.progress.total)")
                    if let matrix = day.matrix, !matrix.quadrants.isEmpty {
                        row(.matrix, L.matrix.text, "square.grid.2x2", nil)
                    }
                    if !day.parallel.isEmpty { row(.parallel, L.parallel.text, "cpu", "\(day.parallel.count)") }
                    if !day.decisions.isEmpty {
                        row(.decisions, L.decisions.text, "questionmark.bubble", "\(day.decisions.filter(\.isOpen).count)")
                    }
                    if !day.notToday.isEmpty { row(.notToday, L.notToday.text, "moon.zzz", "\(day.notToday.count)") }
                }
                Section(L.agents.text) {
                    row(.agents, L.agents.text, "cpu", agentBadge)
                }
                Section(L.map.text) {
                    ForEach(day.sections) { section in
                        let isTimeline = section.title.hasPrefix("🧭")
                        row(.section(section.title), isTimeline ? L.timeline.text : stripIcon(section.title),
                            symbol(for: section.title),
                            isTimeline ? "\(section.items.count)" : "\(section.items.filter(\.isOpen).count)")
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            if let day = store.day {
                HStack(spacing: 10) {
                    ProgressRing(fraction: day.progress.fraction)
                        .scaleEffect(0.8).frame(width: 38, height: 38)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(day.next?.text ?? "✓").font(.caption.weight(.semibold)).lineLimit(2)
                        Text(L.next.text).font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(12)
            }
        }
    }

    private func planetRow(_ planet: Planet, _ day: Day) -> some View {
        let item = planet == .mainQuest ? journey.frog(day) : journey.activeItem(planet, day)
        let state = item.flatMap { $0.isOpen ? monitor.status(for: $0)?.state : nil }
        let open = journey.items(planet, day).filter(\.isOpen).count
        return HStack(spacing: 8) {
            Image(systemName: planet.icon).foregroundStyle(planet.tone).frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(planet.name).font(.body.weight(planet == journey.current ? .bold : .regular))
                if let item { Text(item.heading).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            }
            Spacer()
            if let state, state != .none, state != .idle {
                StatusDot(color: dot(state), size: 9)
            }
            if planet != .mainQuest { Text("\(open)").font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
        }
        .tag(Page.planet(planet))
    }

    private func dot(_ state: AgentState) -> Color {
        switch state {
        case .thinking: .blue
        case .needsYou: .orange
        case .stuck: .gray
        default: .clear
        }
    }

    private var agentBadge: String? {
        let waiting = AgentMonitor.shared.byWorktree.values.filter { $0.state == .needsYou }.count
        return waiting > 0 ? "\(waiting)" : nil
    }

    private func row(_ value: Page, _ title: String, _ icon: String, _ badge: String?) -> some View {
        Label(title, systemImage: icon)
            .badge(badge.map { Text($0) })
            .tag(value)
    }

    private func stripIcon(_ title: String) -> String {
        let parts = title.split(separator: " ", maxSplits: 1)
        guard parts.count == 2, parts[0].unicodeScalars.allSatisfy({ !$0.properties.isAlphabetic }) else { return title }
        return String(parts[1])
    }

    private func symbol(for title: String) -> String {
        switch title.first {
        case "🧭": "point.topleft.down.to.point.bottomright.curvepath"
        case "🔴": "exclamationmark.circle"
        case "⏳": "hourglass"
        case "🟢": "bolt.circle"
        case "📅": "calendar"
        case "🌙": "moon.stars"
        case "🏆": "trophy"
        case "🎯": "scope"
        default: "list.bullet"
        }
    }

    // MARK: Detail

    @ViewBuilder
    private func detail(_ day: Day, _ page: Page) -> some View {
        switch page {
        case .planet(let planet):
            PlanetView(store: store, planet: planet)
        case .today:
            DayView(store: store, compact: true)
        case .parallel:
            list(L.parallel.text, day.parallel)
        case .decisions:
            list(L.decisions.text, day.decisions)
        case .matrix:
            MatrixView(matrix: day.matrix)
        case .agents:
            AgentsView(monitor: AgentMonitor.shared)
        case .notToday:
            list(L.notToday.text, day.notToday)
        case .section(let title):
            let items = day.sections.first(where: { $0.title == title })?.items ?? []
            if title.hasPrefix("🧭") { TimelineView(events: items.compactMap(Event.init)) } else { list(title, items) }
        }
    }

    private func list(_ title: String, _ items: [Item]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(stripIcon(title)).font(.system(size: 24, weight: .bold, design: .rounded))
                Card(title: nil) { ForEach(items) { ItemRow(item: $0) } }
            }
            .padding(24)
            .frame(maxWidth: 820, alignment: .leading)
        }
    }


    @ViewBuilder private var failure: some View {
        if let failure = store.failure {
            Label(failure, systemImage: "exclamationmark.triangle.fill")
                .font(.caption).padding(10)
                .background(.red.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
                .padding(12)
        }
    }
}

struct MatrixView: View {
    @EnvironmentObject private var settings: AppSettings
    let matrix: Matrix?

    private let tones: [String: Color] = ["Q1": .red, "Q2": .purple, "Q3": .orange, "Q4": .gray]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(L.matrix.text).font(.system(size: 24, weight: .bold, design: .rounded))
                if let split = matrix?.split { Text(split).font(.callout.monospacedDigit()).foregroundStyle(.secondary) }
                Grid(horizontalSpacing: 14, verticalSpacing: 14) {
                    let q = matrix?.quadrants ?? []
                    ForEach(Array(stride(from: 0, to: q.count, by: 2)), id: \.self) { i in
                        GridRow {
                            quadrant(q[i])
                            if i + 1 < q.count { quadrant(q[i + 1]) } else { Color.clear }
                        }
                    }
                }
            }
            .padding(24)
        }
    }

    private func quadrant(_ q: Quadrant) -> some View {
        let tone = tones[q.id] ?? .secondary
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(q.id).font(.system(size: 13, weight: .heavy, design: .rounded)).foregroundStyle(tone)
                Text(q.title.capitalized).font(.headline)
                Spacer()
                Text(q.axis).font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            ForEach(q.items) { ItemRow(item: $0) }
        }
        .padding(.vertical, 12).padding(.horizontal, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .tonalCard(tone, strong: q.id == "Q2")
    }
}

struct TimelineView: View {
    @EnvironmentObject private var settings: AppSettings
    let events: [Event]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(L.timeline.text).font(.system(size: 24, weight: .bold, design: .rounded)).padding(.bottom, 16)
                ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                    HStack(alignment: .top, spacing: 12) {
                        Text(event.time)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .trailing)
                            .padding(.top, 5)
                        VStack(spacing: 0) {
                            Image(systemName: event.symbol)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 28, height: 28)
                                .background(StatusDot(color: color(event), size: 28))
                            if index < events.count - 1 {
                                Rectangle().fill(Color.secondary.opacity(0.2)).frame(width: 2).frame(maxHeight: .infinity)
                            }
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            ItemRow(item: Item(text: event.text, md: event.item.md, status: "open", size: nil, tags: [],
                                               links: event.item.links, issue: event.item.issue, pr: event.item.pr),
                                    showActions: false, showStatus: false)
                        }
                        .padding(.bottom, 10)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 820, alignment: .leading)
        }
    }

    private func color(_ event: Event) -> Color {
        switch event.mark {
        case "❌": .red
        case "↔", "↔️": .blue
        default: .green
        }
    }
}

/// Start at login through the system's own Login Items.
enum LoginItem {
    static var isOn: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("Save Point login item: \(error.localizedDescription)")
        }
    }
}
