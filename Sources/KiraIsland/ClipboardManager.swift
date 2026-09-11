import AppKit
import Foundation

struct ClipboardEntry: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let createdAt = Date()
}

@MainActor
final class ClipboardManager: ObservableObject {
    @Published private(set) var entries: [ClipboardEntry] = []

    private var timer: Timer?
    private var lastChangeCount = NSPasteboard.general.changeCount

    func start() {
        timer?.invalidate()
        lastChangeCount = NSPasteboard.general.changeCount
        timer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func copy(_ entry: ClipboardEntry) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.text, forType: .string)
        lastChangeCount = NSPasteboard.general.changeCount
    }

    func clear() {
        entries.removeAll()
    }

    private func poll() {
        let board = NSPasteboard.general
        guard board.changeCount != lastChangeCount else { return }
        lastChangeCount = board.changeCount

        guard let text = board.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return }

        if entries.first?.text == text { return }
        entries.insert(ClipboardEntry(text: text), at: 0)
        if entries.count > 8 { entries.removeLast(entries.count - 8) }
    }
}
