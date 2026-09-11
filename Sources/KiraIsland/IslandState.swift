import Combine
import Foundation

@MainActor
final class IslandState: ObservableObject {
    enum Tab: String, CaseIterable, Identifiable {
        case home, audio, clipboard, timer
        var id: String { rawValue }
    }

    @Published var isExpanded = false
    @Published var selectedTab: Tab = .home
    @Published var isPinned: Bool {
        didSet {
            UserDefaults.standard.set(isPinned, forKey: Self.pinDefaultsKey)
        }
    }

    private static let pinDefaultsKey = "KiraIsland.isPinned"

    init() {
        isPinned = UserDefaults.standard.bool(forKey: Self.pinDefaultsKey)
    }
}
