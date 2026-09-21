import Observation
import UIKit

@MainActor
@Observable
final class FieldChatImageStackModel {
    let media: [FieldChatMedia]
    private(set) var selectedID: String?
    private(set) var images: [String: UIImage] = [:]
    private(set) var failedIDs: Set<String> = []
    @ObservationIgnored private var loadGeneration = 0
    @ObservationIgnored private var wasOnline: Bool?
    @ObservationIgnored private var pendingSelection: (id: String, feedback: () -> Void)?
    @ObservationIgnored private let dependencies: FieldChatImageDependencies

    init(media: [FieldChatMedia], dependencies: FieldChatImageDependencies) {
        self.media = FieldChatMedia.orderedUnique(media)
        selectedID = self.media.first?.id
        self.dependencies = dependencies
    }

    var availableMedia: [FieldChatMedia] { media.filter { !failedIDs.contains($0.id) } }
    var selectedIndex: Int { availableMedia.firstIndex { $0.id == selectedID } ?? 0 }
    var selectedMedia: FieldChatMedia? { availableMedia.first { $0.id == selectedID } }

    /// Only explicit, committed user navigation requests feedback.
    func move(by offset: Int, onSelection: @escaping () -> Void) {
        let available = availableMedia
        guard available.count > 1, offset != 0 else { return }
        let target = (selectedIndex + offset % available.count + available.count) % available.count
        guard available[target].id != selectedID else { return }
        loadGeneration += 1
        selectedID = available[target].id
        pendingSelection = (available[target].id, onSelection)
        retainWindow()
        if images[available[target].id] != nil {
            completeUserSelection(for: available[target].id)
        }
    }

    func loadWindow(isOnline: Bool) async {
        loadGeneration += 1
        let generation = loadGeneration
        if wasOnline == false && isOnline {
            failedIDs.removeAll()
            if selectedID == nil { selectedID = media.first?.id }
        }
        wasOnline = isOnline
        guard !Task.isCancelled else { return }

        // A failed leading image promotes the next candidate without user feedback.
        while let current = selectedMedia {
            if images[current.id] == nil {
                let image = await dependencies.load(current.source, 600)
                guard !Task.isCancelled, generation == loadGeneration else { return }
                if let image {
                    images[current.id] = image
                } else {
                    pendingSelection = nil
                    let previousIndex = selectedIndex
                    failedIDs.insert(current.id)
                    let available = availableMedia
                    selectedID = available.isEmpty ? nil : available[min(previousIndex, available.count - 1)].id
                    retainWindow()
                    continue
                }
            }
            completeUserSelection(for: current.id)
            break
        }

        retainWindow()
        // Recompute after each failure so all three visible slots receive an image.
        while let neighbor = stackMedia.first(where: { images[$0.id] == nil }) {
            let image = await dependencies.load(neighbor.source, 600)
            guard !Task.isCancelled, generation == loadGeneration else { return }
            if let image {
                images[neighbor.id] = image
            } else {
                failedIDs.insert(neighbor.id)
            }
        }
        retainWindow()
    }

    var stackMedia: [FieldChatMedia] {
        let available = availableMedia
        guard !available.isEmpty else { return [] }
        return (0..<min(3, available.count)).map {
            available[(selectedIndex + $0) % available.count]
        }
    }

    private func retainWindow() {
        let ids = Set(stackMedia.map(\.id))
        images = images.filter { ids.contains($0.key) }
    }

    private func completeUserSelection(for id: String) {
        guard let pending = pendingSelection, pending.id == id else { return }
        pendingSelection = nil
        pending.feedback()
    }
}
