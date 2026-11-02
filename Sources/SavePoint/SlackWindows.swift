import AppKit
import Foundation
import UserNotifications

/// The few moments of the day Slack is read. Everything here is configured in Settings.
struct SlackSchedule: Codable, Equatable {
    var enabled = true
    var minutes = 20
    /// Times per weekday, 1 = Monday … 7 = Sunday, as "HH:mm".
    /// Every two hours or so; Monday to Thursday the third one waits for lunch to end.
    var times: [Int: [String]] = [1: ["09:20", "11:20", "13:40", "15:40"], 2: ["09:20", "11:20", "13:40", "15:40"],
                                  3: ["09:20", "11:20", "13:40", "15:40"], 4: ["09:20", "11:20", "13:40", "15:40"],
                                  5: ["09:00", "11:00", "13:00", "15:00"]]
    /// End of the working day, per weekday, for the status after the last window.
    var dayEnds: [Int: String] = [1: "17:00", 2: "17:00", 3: "17:00", 4: "17:00", 5: "16:00"]
    var openSlack = true
    var quitSlack = false
    /// Between windows Slack stays open with its notifications paused until the next window.
    var focusBetweenWindows = true
    var setStatus = true
    var windowStatus = "Checking Slack"
    var windowEmoji = ":window:"
    /// Focus, not crunch: he is reachable, he just reads Slack in batches. Pinging him is fine.
    var focusStatus = "Focusing, will check Slack at {next}. Ping me if you need me"
    var focusEmoji = ":headphones:"
    /// After the last window: still deep work, with no time to come back. He decides when the day ends; never "off".
    var lastFocusStatus = "Focusing, will check Slack later. Ping me if you need me"

    static let key = "slackSchedule"

    static func load() -> SlackSchedule {
        guard let data = UserDefaults.standard.data(forKey: key),
              let s = try? JSONDecoder().decode(SlackSchedule.self, from: data) else { return SlackSchedule() }
        return s
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: Self.key) }
    }

    static func weekday(_ date: Date = .now) -> Int {
        (Calendar(identifier: .gregorian).component(.weekday, from: date) + 5) % 7 + 1
    }
}

@MainActor
final class SlackWindows: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = SlackWindows()

    @Published var schedule = SlackSchedule.load() { didSet { schedule.save() } }
    @Published private(set) var windowEndsAt: Date?
    @Published var lastError: String?

    private var timer: Timer?
    private var fired: Set<String> = []
    private var syncedDay = Calendar.current.startOfDay(for: .now)
    private var endTask: Task<Void, Never>?

    func start() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        let extend = UNNotificationAction(identifier: "extend", title: L.extendWindow.text)
        let skip = UNNotificationAction(identifier: "skip", title: L.skipWindow.text)
        center.setNotificationCategories([UNNotificationCategory(identifier: "window", actions: [extend, skip],
                                                                 intentIdentifiers: [])])
        timer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        tick()
        syncStatus()
    }

    var isOpen: Bool { windowEndsAt.map { $0 > .now } ?? false }

    /// The next window today, if any.
    var next: String? {
        let now = Self.hm(.now)
        return (schedule.times[SlackSchedule.weekday()] ?? []).sorted().first { $0 > now }
    }

    private func tick() {
        guard schedule.enabled else { return }
        let today = Calendar.current.startOfDay(for: .now)
        if today != syncedDay {
            syncedDay = today
            syncStatus()
        }
        let now = Self.hm(.now)
        let day = today.timeIntervalSince1970
        for t in schedule.times[SlackSchedule.weekday()] ?? [] where t == now {
            let id = "\(day)-\(t)"
            if fired.insert(id).inserted { openWindow() }
        }
    }

    func openWindow(minutes: Int? = nil) {
        let length = minutes ?? schedule.minutes
        windowEndsAt = Date.now.addingTimeInterval(TimeInterval(length * 60))
        notify(L.windowStarts.text, L.windowStartsBody.text.replacingOccurrences(of: "{minutes}", with: "\(length)"),
               category: "window")
        if schedule.openSlack { open() }
        focus(until: nil)
        status(schedule.windowStatus.replacingOccurrences(of: "{minutes}", with: "\(length)"), schedule.windowEmoji,
               until: windowEndsAt)
        scheduleEnd()
    }

    func extend(by minutes: Int = 10) {
        guard let end = windowEndsAt else { return openWindow(minutes: minutes) }
        windowEndsAt = max(end, .now).addingTimeInterval(TimeInterval(minutes * 60))
        status(schedule.windowStatus.replacingOccurrences(of: "{minutes}", with: "\(minutes)"), schedule.windowEmoji,
               until: windowEndsAt)
        scheduleEnd()
    }

    func closeWindow() {
        endTask?.cancel()
        windowEndsAt = nil
        if schedule.quitSlack { quit() }
        let weekday = SlackSchedule.weekday()
        if let next {
            focus(until: Self.date(next))
            notify(L.windowEnds.text, L.windowEndsBody.text.replacingOccurrences(of: "{next}", with: next))
            status(schedule.focusStatus.replacingOccurrences(of: "{next}", with: next), schedule.focusEmoji,
                   until: Self.date(next))
        } else {
            focus(until: schedule.dayEnds[weekday].flatMap { Self.date($0) })
            notify(L.windowEnds.text, L.lastWindowBody.text)
            status(schedule.lastFocusStatus, schedule.focusEmoji, until: nil)
        }
    }

    private func scheduleEnd() {
        endTask?.cancel()
        guard let end = windowEndsAt else { return }
        endTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, end.timeIntervalSinceNow)))
            guard !Task.isCancelled else { return }
            self?.closeWindow()
        }
    }

    // MARK: Slack

    private func open() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.tinyspeck.slackmacgap") {
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        }
    }

    private func quit() {
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.tinyspeck.slackmacgap").forEach { $0.terminate() }
    }

    /// users.profile.set with the user's own token when there is one in the Keychain, the Raycast Slack extension otherwise.
    private func status(_ text: String, _ emoji: String, until: Date?) {
        guard schedule.setStatus else { return }
        guard let token = Keychain.get("slack-user-token") else { return raycastStatus(text, emoji, until: until) }
        var request = URLRequest(url: URL(string: "https://slack.com/api/users.profile.set")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        let profile: [String: Any] = ["status_text": text, "status_emoji": emoji,
                                      "status_expiration": Int(until?.timeIntervalSince1970 ?? 0)]
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["profile": profile])
        URLSession.shared.dataTask(with: request) { data, _, error in
            let reply = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            let problem = error?.localizedDescription ?? ((reply?["ok"] as? Bool) == true ? nil : reply?["error"] as? String)
            Task { @MainActor in self.lastError = problem.map { "Slack: \($0)" } }
        }.resume()
    }

    /// Slack's own pause between windows, through orca-summon's Raycast commands (Raycast's Slack app, dnd:write):
    /// paused until the next window, resumed when a window opens. No Slack app of ours, no token.
    private func focus(until: Date?) {
        guard schedule.focusBetweenWindows else { return }
        let base = "raycast://extensions/alejandro_ruiz_temina/orca-summon/"
        var url: URLComponents?
        if let until {
            let minutes = max(1, Int((until.timeIntervalSinceNow / 60).rounded(.up)))
            url = URLComponents(string: base + "slack-pause")
            url?.queryItems = [URLQueryItem(name: "arguments", value: "{\"minutes\":\"\(minutes)\"}"),
                               URLQueryItem(name: "launchType", value: "background")]
        } else {
            url = URLComponents(string: base + "slack-resume")
            url?.queryItems = [URLQueryItem(name: "launchType", value: "background")]
        }
        guard let link = url?.url, NSWorkspace.shared.urlForApplication(toOpen: link) != nil else {
            lastError = "Slack pause: Raycast is not installed"
            return
        }
        NSWorkspace.shared.open(link)
    }

    /// The Raycast Slack extension (mommertf/slack) sets the status with the user's own session: no Slack app to approve.
    private func raycastStatus(_ text: String, _ emoji: String, until: Date?) {
        let minutes = until.map { max(1, Int(($0.timeIntervalSinceNow / 60).rounded(.up))) } ?? 0
        let args = ["statusText": text, "emoji": emoji, "expiration": "\(minutes)"]
        guard let json = try? JSONSerialization.data(withJSONObject: args), let value = String(data: json, encoding: .utf8),
              var url = URLComponents(string: "raycast://extensions/mommertf/slack/set-status") else { return }
        url.queryItems = [URLQueryItem(name: "arguments", value: value)]
        guard let link = url.url, NSWorkspace.shared.urlForApplication(toOpen: link) != nil else {
            lastError = "Slack: no token and no Raycast to set the status"
            return
        }
        NSWorkspace.shared.open(link)
    }

    /// On launch, the status the schedule says it should have now, so a restart between windows does not leave it stale.
    private func syncStatus() {
        guard schedule.enabled else { return }
        let weekday = SlackSchedule.weekday()
        let times = (schedule.times[weekday] ?? []).sorted()
        guard !times.isEmpty else { return }
        let inWindow = times.contains { t in
            guard let start = Self.date(t) else { return false }
            return Date.now >= start && Date.now < start.addingTimeInterval(TimeInterval(schedule.minutes * 60))
        }
        guard !inWindow else { return }
        if let next {
            focus(until: Self.date(next))
            status(schedule.focusStatus.replacingOccurrences(of: "{next}", with: next), schedule.focusEmoji, until: Self.date(next))
        } else {
            status(schedule.lastFocusStatus, schedule.focusEmoji, until: nil)
        }
    }

    // MARK: Notifications

    private func notify(_ title: String, _ body: String, category: String? = nil) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let category { content.categoryIdentifier = category }
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler handler: @escaping (UNNotificationPresentationOptions) -> Void) {
        handler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler handler: @escaping () -> Void) {
        let action = response.actionIdentifier
        Task { @MainActor in
            switch action {
            case "extend": self.extend()
            case "skip": self.closeWindow()
            default: break
            }
            handler()
        }
    }

    // MARK: Time

    static func hm(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    static func date(_ hm: String) -> Date? {
        let parts = hm.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        return Calendar.current.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: .now)
    }
}
