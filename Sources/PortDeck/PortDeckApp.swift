import SwiftUI

@main
struct PortDeckApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var deck = Deck.shared

    var body: some Scene {
        MenuBarExtra {
            MenuView().environment(deck)
        } label: {
            Image(systemName: "server.rack")
            if deck.activeCount > 0 { Text(String(deck.activeCount)) }
        }
        .menuBarExtraStyle(.window)

        Window("PortDeck", id: "main") {
            MainWindow().environment(deck)
        }
        .defaultSize(width: 820, height: 560)
        .defaultLaunchBehavior(.suppressed)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillTerminate(_ notification: Notification) {
        guard UserDefaults.standard.object(forKey: "stopOnQuit") as? Bool ?? true else { return }
        MainActor.assumeIsolated { Deck.shared.stopAll(wait: 3) }
    }
}
