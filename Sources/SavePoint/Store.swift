import Foundation
import SwiftUI

/// Reads ~/Library/Application Support/Save Point/today.json and keeps it current: the vault's renderer
/// rewrites that file on every Daily refresh, and the app picks it up within two seconds.
enum Paths {
    static let folder = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Save Point")
    static let dayFile = folder.appendingPathComponent("today.json")
}

@MainActor
final class Store: ObservableObject {
    static let dayFile = Paths.dayFile

    @Published private(set) var day: Day?
    @Published private(set) var error: String?
    @Published private(set) var updated: Date?
    @Published var failure: String?

    private var lastData: Data?
    private var timer: Timer?
    private var watcher: DispatchSourceFileSystemObject?

    init() {
        load()
        // The folder, not the file: the exporter replaces today.json atomically, so the file's
        // descriptor would go stale after the first write.
        try? FileManager.default.createDirectory(at: Paths.folder, withIntermediateDirectories: true)
        let fd = open(Paths.folder.path, O_EVTONLY)
        if fd >= 0 {
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete],
                                                                   queue: .main)
            source.setEventHandler { [weak self] in Task { @MainActor in self?.load() } }
            source.setCancelHandler { close(fd) }
            source.resume()
            watcher = source
        }
        // A safety net in every run loop mode, so it also ticks while a menu is open.
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in Task { @MainActor in self?.load() } }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Reads today.json when its bytes changed. A file that does not decode is retried on the
    /// next event and the error is shown, instead of silently keeping the old day.
    func load(force: Bool = false) {
        guard let data = try? Data(contentsOf: Self.dayFile) else {
            if day == nil { error = Self.dayFile.path }
            return
        }
        guard force || data != lastData else { return }
        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            day = try decoder.decode(Day.self, from: Self.withLinear(data))
            lastData = data
            error = nil
            updated = .now
        } catch {
            self.error = "\(Self.dayFile.lastPathComponent): \(error.localizedDescription)"
            report(self.error ?? "")
        }
    }

    /// Overlays Linear's state on every open line with an issue, before decoding: the Daily is the plan, Linear the state.
    /// A waiting line is Linear's too, so it goes back to open when its issue leaves Pending for inputs.
    private static func withLinear(_ data: Data) -> Data {
        guard var root = try? JSONSerialization.jsonObject(with: data) else { return data }
        let states = LinearStates.shared
        func walk(_ node: Any) -> Any {
            if var dict = node as? [String: Any] {
                if let issue = dict["issue"] as? String, ["open", "waiting"].contains(dict["status"] as? String) {
                    dict["status"] = MainActor.assumeIsolated({ states.status(of: issue) }) ?? "open"
                }
                for (k, v) in dict { dict[k] = walk(v) }
                return dict
            }
            if let list = node as? [Any] { return list.map(walk) }
            return node
        }
        root = walk(root)
        if var dict = root as? [String: Any], let queue = (dict["queue"] as? [[String: Any]])?.filter({ $0["status"] as? String != "waiting" }) {
            var progress: [String: Any] = ["done": queue.filter { $0["status"] as? String != "open" }.count, "total": queue.count]
            let frog = ((dict["layers"] as? [String: Any])?["main_quest"] as? [[String: Any]])?.first ?? dict["focus"] as? [String: Any]
            if let status = frog?["status"] as? String { progress["frog_done"] = status != "open" && status != "waiting" }
            dict["progress"] = progress
            root = dict
        }
        return (try? JSONSerialization.data(withJSONObject: root)) ?? data
    }

    func report(_ message: String) {
        failure = message
        Task {
            try? await Task.sleep(for: .seconds(8))
            if failure == message { failure = nil }
        }
    }

    var menuTitle: String {
        if let end = SlackWindows.shared.windowEndsAt, end > .now {
            return "🪟 \(max(1, Int(end.timeIntervalSinceNow / 60)))m"
        }
        guard let day else { return "☀️" }
        return "☀️ \(day.progress.done)/\(day.progress.total)"
    }
}
