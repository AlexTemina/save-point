import SwiftUI

@main
struct SavePointApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @StateObject private var store = Store()
    @StateObject private var settings = AppSettings.shared

    var body: some Scene {
        Window("Save Point", id: "main") {
            MainWindow(store: store)
                .environmentObject(settings)
                .frame(minWidth: 760, minHeight: 620)
                .onAppear { Actions.store = store }
        }
        .defaultSize(width: 1040, height: 820)

        MenuBarExtra {
            MenuContent(store: store)
                .environmentObject(settings)
                .onAppear { Actions.store = store }
        } label: {
            MenuLabel(store: store)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView().environmentObject(settings)
        }
    }
}

/// Closing the window keeps Save Point alive in the menu bar; the Dock icon brings the window back.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            SlackWindows.shared.start()
            AgentMonitor.shared.start()
            LinearStates.shared.start()
        }
    }
}

/// The menu bar title: the day's progress, or the minutes left in a Slack window.
struct MenuLabel: View {
    @ObservedObject var store: Store
    @ObservedObject private var windows = SlackWindows.shared
    @State private var tick = Date.now
    private let clock = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        Text(store.menuTitle).id(tick).onReceive(clock) { tick = $0 }
    }
}
