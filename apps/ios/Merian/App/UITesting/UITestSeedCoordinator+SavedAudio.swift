#if DEBUG
import Foundation
import SwiftUI

extension UITestSeedCoordinator {
    /// Domain-only rendering fixture. Persistence and execution are covered by native integration tests.
    @MainActor static func savedAudioChooserModel() -> CaptureAudioSavedRequestsModel? {
        guard isEnabled, ProcessInfo.processInfo.arguments.contains("-seedSavedAudioChooser") else { return nil }
        let owner = UUID(), parent = UUID(), source = UUID()
        guard let a = UUID(uuidString: "00000000-0000-4000-8000-000000000051"),
              let b = UUID(uuidString: "00000000-0000-4000-8000-000000000052") else { return nil }
        let rows: [ObservationAudioSavedStatus.Summary] = [
            .init(identity: .init(observationID: parent, sourceAnalysisID: source, analysisID: a, ownerID: owner), phase: .heldConsumed),
            .init(identity: .init(observationID: parent, sourceAnalysisID: source, analysisID: b, ownerID: owner), phase: .heldUnconsumed)
        ]
        return .init(status: .init(isCurrent: { true }, page: { _, _, _ in .init(items: rows, next: nil, omittedCount: 1) }),
            openResume: { identity in
                guard rows.contains(where: { $0.identity == identity }) else { throw ObservationHistoryError.unavailable }
                return .init(resume: { current in
                    guard current() else { throw ObservationHistoryError.accountChanged }
                    return .unavailable
                })
            }, isPresented: { true })
    }
}

/// Debug plus UITesting plus an explicit launch argument; ordinary App access stays nil.
struct SavedAudioChooserUITestPresentation: ViewModifier {
    @State private var model = UITestSeedCoordinator.savedAudioChooserModel()
    func body(content: Content) -> some View {
        content.sheet(isPresented: Binding(get: { model != nil }, set: { if !$0 { model?.close(); model = nil } })) {
            if let model { CaptureAudioSavedRequestsSheet(model: model) }
        }
    }
}
#endif
