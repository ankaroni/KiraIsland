import Foundation

@MainActor
final class IslandState: ObservableObject {
    enum Tab: String, CaseIterable, Identifiable {
        case home, audio, clipboard, timer
        var id: String { rawValue }
    }

    @Published var isExpanded = false
    @Published var selectedTab: Tab = .home
    @Published var isPinned = false
}
