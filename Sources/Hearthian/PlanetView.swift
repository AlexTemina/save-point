import SwiftUI

/// One planet: who you are working on, what comes next, the rest of the list, and the way down or up.
struct PlanetView: View {
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject var store: Store
    @ObservedObject private var journey = Journey.shared
    @ObservedObject private var monitor = AgentMonitor.shared
    let planet: Planet
    var compact = false

    @State private var askingReason = false
    @State private var reason = ""

    var body: some View {
        if let day = store.day {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header(day)
                    if let up = waitingAbove(day) { waitingBanner(up) }
                    content(day)
                    moves(day)
                }
                .padding(compact ? 16 : 24)
                .frame(maxWidth: 860, alignment: .leading)
            }
            .onAppear { journey.sync(day) }
        }
    }

    // MARK: Header

    private func header(_ day: Day) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: planet.icon)
                .font(.system(size: compact ? 20 : 26, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: compact ? 42 : 54, height: compact ? 42 : 54)
                .background(StatusDot(color: planet.tone, size: compact ? 42 : 54))
            VStack(alignment: .leading, spacing: 2) {
                Text(planet.name).font(.system(size: compact ? 20 : 26, weight: .bold, design: .rounded))
                Text(planet.role).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            if planet == .brittleHollow || planet == .giantsDeep {
                let list = journey.items(planet, day)
                Text("\(list.filter { !$0.isOpen }.count)/\(list.count)").font(.title3.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Content

    @ViewBuilder
    private func content(_ day: Day) -> some View {
        let list = journey.items(planet, day)
        if list.isEmpty {
            Text(L.nothingHere.text).foregroundStyle(.secondary).padding(.vertical, 20)
        } else if planet == .timberHearth {
            frog(day)
        } else {
            if let active = journey.activeItem(planet, day) {
                spotlight(L.activeNow.text, active, strong: true)
                if let next = journey.nextItem(planet, day) { spotlight(L.nextUp.text, next, strong: false) }
            } else {
                Label(L.layerDone.text, systemImage: "checkmark.seal.fill").foregroundStyle(.green).font(.headline)
            }
            if !compact {
                rail(list, active: journey.activeItem(planet, day))
            }
        }
        if planet == .brittleHollow, !compact, !journey.waiting(day).isEmpty {
            Card(title: L.waiting.text, icon: "hourglass") {
                ForEach(journey.waiting(day)) { ItemRow(item: $0) }
            }
        }
    }

    private func frog(_ day: Day) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let contract = day.contract { ContractCard(contract: contract) }
            if let frog = journey.frog(day) {
                spotlight(L.activeNow.text, frog, strong: true)
                let rest = (day.layers?.timberHearth ?? []).filter { $0.md != frog.md }
                if !rest.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L.nextUp.text.uppercased()).font(.system(size: 10.5, weight: .heavy)).tracking(0.8)
                            .foregroundStyle(.secondary)
                        ForEach(rest) { ItemRow(item: $0) }
                    }
                }
                if !frog.isOpen, let next = journey.items(.brittleHollow, day).first(where: \.isOpen) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L.frogDone.text).font(.headline)
                        Button { journey.promote(next) } label: {
                            Label("\(L.promoteNext.text): \(next.heading)", systemImage: "arrow.up.circle.fill")
                        }
                        .buttonStyle(FilledButtonStyle(tint: Planet.timberHearth.tone))
                    }
                    .padding(14)
                    .tonalCard(.green, radius: 12)
                }
            }
            if !day.slots.isEmpty {
                HStack(spacing: 8) {
                    ForEach(day.slots) { slot in
                        Label("\(slot.time) \(slot.title)", systemImage: "clock").font(.caption)
                            .padding(.horizontal, 9).padding(.vertical, 5)
                            .tonalChip()
                    }
                }
            }
        }
    }

    private func spotlight(_ label: String, _ item: Item, strong: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased()).font(.system(size: 10.5, weight: .heavy)).tracking(0.8)
                .foregroundStyle(strong ? planet.tone : .secondary).padding(.horizontal, 10)
            ItemRow(item: item)
        }
        .padding(.vertical, 10).padding(.horizontal, 6)
        .tonalCard(strong ? planet.tone : nil, strong: strong)
    }

    /// Every item in its priority order, a green ball once it is done, the active one marked.
    private func rail(_ list: [Item], active: Item?) -> some View {
        Card(title: L.everything.text, trailing: "\(list.filter { !$0.isOpen }.count)/\(list.count)") {
            ForEach(list) { item in
                HStack(alignment: .top, spacing: 0) {
                    StatusDot(color: ballColor(item), filled: !item.isOpen || item.md == active?.md, check: item.status == "done", size: 16)
                        .padding(.top, 11)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 6) {
                            if let badge = kindBadge(item) { badge }
                            if item.isOpen && item.md != active?.md && journey.isStarted(item) {
                                Label(L.underway.text, systemImage: "play.circle.fill").font(.caption2.weight(.bold)).foregroundStyle(planet.tone)
                            }
                        }
                        .padding(.leading, 10).padding(.top, 4)
                        ItemRow(item: item, showStatus: false)
                    }
                    if item.isOpen && item.md != active?.md {
                        Button { Actions.activate(item) } label: {
                            Image(systemName: "play.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .offset(x: 1)
                                .frame(width: 26, height: 26)
                                .background(FilledSurface(tint: planet.tone))
                        }
                        .buttonStyle(.plain).help(L.makeActive.text).padding(.top, 8)
                    }
                }
            }
        }
    }

    private func ballColor(_ item: Item) -> Color {
        switch item.status {
        case "done": .green
        case "dropped": .red
        case "open": planet.tone
        default: .orange
        }
    }

    private func kindBadge(_ item: Item) -> AnyView? {
        switch item.kind {
        case "decision": AnyView(Label(L.kindDecision.text, systemImage: "questionmark.bubble.fill").font(.caption2.weight(.bold)).foregroundStyle(.pink))
        case "auto": AnyView(Label(L.kindAuto.text, systemImage: "cpu").font(.caption2.weight(.bold)).foregroundStyle(.blue))
        default: nil
        }
    }

    // MARK: Moves

    private func waitingAbove(_ day: Day) -> Planet? {
        var p = planet.above
        while let up = p {
            if let item = up == .timberHearth ? journey.frog(day) : journey.activeItem(up, day),
               item.isOpen, monitor.status(for: item)?.state == .needsYou { return up }
            p = up.above
        }
        return nil
    }

    private func waitingBanner(_ up: Planet) -> some View {
        Button { journey.ascend(to: up) } label: {
            HStack {
                Image(systemName: "bell.badge.fill")
                Text("\(L.waitingAbove.text) \(up.name)").font(.callout.weight(.semibold))
                Spacer()
                Image(systemName: "arrow.up.circle.fill")
            }
            .padding(12)
            .foregroundStyle(.white)
            .background(FilledSurface(tint: up.tone, radius: 12))
        }
        .buttonStyle(.plain)
    }

    /// Going down needs an agent thinking on this planet's active task; going up is always open.
    private func canDescend(_ day: Day) -> Bool {
        guard let item = planet == .timberHearth ? journey.frog(day) : journey.activeItem(planet, day) else { return true }
        return !item.isOpen || monitor.status(for: item)?.state == .thinking
    }

    @ViewBuilder
    private func moves(_ day: Day) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                if let up = planet.above {
                    Button { journey.ascend(to: up) } label: {
                        Label("\(L.ascendTo.text) \(up.name)", systemImage: "arrow.up")
                    }
                }
                Spacer()
                if let below = planet.below {
                    Button { journey.descend(from: planet) } label: {
                        Label("\(L.descendTo.text) \(below.name)", systemImage: "arrow.down.to.line")
                    }
                    .buttonStyle(FilledButtonStyle(tint: below.tone))
                    .disabled(!canDescend(day))
                }
            }
            if planet.below != nil && !canDescend(day) {
                HStack {
                    Text(L.descendLocked.text).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button(L.descendAnyway.text) { askingReason = true }.buttonStyle(.link).font(.caption)
                }
                if askingReason {
                    HStack {
                        TextField(L.whyDescend.text, text: $reason).textFieldStyle(.roundedBorder)
                        Button(L.send.text) {
                            journey.descend(from: planet, forced: reason)
                            reason = ""; askingReason = false
                        }
                        .disabled(reason.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
        .padding(.top, 6)
    }
}

/// The week at a glance: Las Tres with their Linear state, and what each day of the Alan week delivered.
struct ContractCard: View {
    @ObservedObject private var linear = LinearStates.shared
    let contract: Contract

    var body: some View {
        Card(title: L.week.text, icon: "calendar", trailing: "\(contract.tres.filter(linear.done).count)/\(contract.tres.count)") {
            if !contract.confirmed {
                Label(L.contractUnconfirmed.text, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold)).foregroundStyle(.orange).padding(.horizontal, 10)
            }
            ForEach(contract.tres) { goal in
                HStack(alignment: .top, spacing: 10) {
                    StatusDot(color: linear.done(goal) ? .green : Planet.timberHearth.tone, filled: linear.done(goal),
                              check: linear.done(goal), size: 15)
                        .padding(.top, 2)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(goal.n). \(goal.text)").font(.callout).fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 6) {
                            ForEach(goal.links, id: \.self) { link in
                                Button(link.title.components(separatedBy: " — ").first ?? link.title) { Actions.open(link) }
                                    .buttonStyle(.plain).font(.caption2.weight(.semibold)).tonalChip()
                            }
                        }
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 3)
            }
            VStack(spacing: 4) {
                ForEach(contract.days) { row in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(mark(row) ?? "·").font(.caption).frame(width: 16)
                        Text(row.day).font(.caption.weight(.semibold))
                            .foregroundStyle(isToday(row) ? .primary : .secondary)
                            .frame(width: 48, alignment: .leading)
                        if let note = note(row) {
                            Text(note).font(.caption).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .tonalChip(tint(row))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(isToday(row) ? Planet.timberHearth.tone : .clear, lineWidth: 1))
                    .help([row.una, row.parallels].compactMap { $0 }.joined(separator: "\n"))
                }
            }
            .padding(.horizontal, 10).padding(.top, 4)
        }
    }

    /// The outcome opens with its verdict emoji, the rest is the note, in markdown.
    private func mark(_ row: Contract.DayRow) -> String? {
        row.outcome?.trimmingCharacters(in: .whitespaces).first.map(String.init)
    }

    private func note(_ row: Contract.DayRow) -> AttributedString? {
        guard let outcome = row.outcome?.trimmingCharacters(in: .whitespaces), outcome.count > 1 else { return nil }
        let rest = String(outcome.dropFirst()).trimmingCharacters(in: .whitespaces)
        return (try? AttributedString(markdown: rest)) ?? AttributedString(rest)
    }

    private func tint(_ row: Contract.DayRow) -> Color? {
        switch mark(row) { case "✅": .green; case "❌": .red; default: nil }
    }

    private func isToday(_ row: Contract.DayRow) -> Bool {
        row.day.hasSuffix(" \(Calendar.current.component(.day, from: .now))")
    }
}
