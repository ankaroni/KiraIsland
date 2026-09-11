import SwiftUI
import AppKit

@main
struct KiraIslandApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var islandController: IslandWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let controller = IslandWindowController()
        islandController = controller
        controller.show()

        print("✅ Kira Island started")
    }
}
