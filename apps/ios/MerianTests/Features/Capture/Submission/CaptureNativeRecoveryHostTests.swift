import Foundation
import Testing
@testable import Merian

@Suite("Native recovery Capture host", .serialized)
@MainActor
struct CaptureNativeRecoveryHostTests {
    @Test func ordinaryCompositionDoesNotAdmitNativeRecovery() {
        let dependencies = CaptureSubmissionDependencies.live(diContainer: .preview)
        #expect(dependencies.nativeRecoveryFactory == nil)
        #expect(CaptureNativeRecoveryModel.app(ownerID: UUID(), diContainer: .preview) == nil)
    }

    @Test(arguments: ["occupied", "dismissing", "blocked", "capturing"])
    func unavailableHostDoesNotConstructOrRead(_ reason: String) {
        let owner = UUID()
        var constructed = 0
        let vm = viewModel(ownerID: owner, blocked: { reason == "blocked" }) { _ in
            constructed += 1
            return .init(ownerID: owner, isCurrent: { true }) { Issue.record("Unexpected read"); return [] }
        }
        if reason == "occupied" || reason == "dismissing" { vm.activeSheet = .profile }
        if reason == "dismissing" { vm.dismissActivePresentation() }
        if reason == "capturing" { vm.isCapturing = true }
        vm.presentNativeRecovery()
        #expect(constructed == 0 && vm.nativeRecoveryModel == nil)
    }

    @Test(arguments: ["close", "accountGeneration", "routeGeneration", "library"])
    func invalidationCannotRestoreLatePresentationOrChangeDraft(_ reason: String) async throws {
        let owner = UUID(), entered = ImageFocusEngineTests.Signal(), release = ImageFocusEngineTests.Signal()
        var current = true, blocked = false, reads = 0
        let model = CaptureNativeRecoveryModel(ownerID: owner, isCurrent: { current }) {
            reads += 1; await entered.open(); await release.wait(); return []
        }
        let vm = viewModel(ownerID: owner, blocked: { blocked }) { _ in model }
        vm.descriptionDraft = .init(freeText: "Keep this later draft")
        let generation = vm.draftSession.generation
        vm.presentNativeRecovery()
        #expect(vm.activeSheet == .nativeRecovery && vm.nativeRecoveryModel === model && reads == 0)
        let task = Task { await model.open() }
        await entered.wait()
        vm.presentNativeRecovery()
        #expect(reads == 1)
        switch reason {
        case "accountGeneration": current = false; vm.handleDraftAccountChange()
        case "routeGeneration": vm.handleRouteAccountGenerationChanged()
        case "library": blocked = true; vm.handleDraftAccountChange()
        default: vm.dismissActivePresentation()
        }
        #expect(vm.nativeRecoveryModel == nil && vm.activeSheet == nil && model.state == .closed)
        await release.open(); await task.value
        #expect(model.state == .closed && vm.nativeRecoveryModel == nil)
        #expect(vm.descriptionDraft.freeText == "Keep this later draft" && vm.draftSession.generation == generation)
    }

    @Test func dismissalUsesExistingRouteBarrierAndFreshPresentation() async throws {
        let owner = UUID()
        var models: [CaptureNativeRecoveryModel] = []
        let vm = viewModel(ownerID: owner) { _ in
            let model = CaptureNativeRecoveryModel(ownerID: owner, isCurrent: { true }) { [] }
            models.append(model); return model
        }
        vm.presentNativeRecovery()
        await models[0].open()
        vm.dismissNativeRecovery()
        vm.presentNativeRecovery()
        #expect(models.count == 1 && vm.isRootPresentationDismissing)
        #expect(vm.handleRootSheetDismissed() == .nativeRecovery)
        vm.presentNativeRecovery()
        #expect(models.count == 2 && models[0].state == .closed && models[1].state == .closed)
        #expect(vm.nativeRecoveryModel === models[1])
        vm.dismissNativeRecovery()
    }

    func viewModel(ownerID: UUID, blocked: @escaping @MainActor @Sendable () -> Bool = { false },
                   factory: @escaping @MainActor (UUID) -> CaptureNativeRecoveryModel?) -> CaptureWorkspaceViewModel {
        let base = CaptureWorkspaceDependencies.live(diContainer: .preview)
        let submission = CaptureSubmissionDependencies(context: base.submission.context,
            admission: .init(isOnline: { Issue.record("Network admission"); return false },
                canStartLocally: { _ in Issue.record("Funding admission"); return false },
                preview: { _ in Issue.record("Admission preview"); return .unavailable },
                accountID: { ownerID }, isLibraryAccessBlocked: blocked),
            deferredContext: base.submission.deferredContext, nativeRecoveryFactory: factory)
        let dependencies = CaptureWorkspaceDependencies(scan: base.scan, submission: submission, controls: base.controls,
            navigation: base.navigation, stagingToolbar: base.stagingToolbar, prepareImage: { _ in nil },
            prepareHistoricalAudio: { _ in nil }, externalImageImports: base.externalImageImports,
            downloadRefinementImage: { _ in nil }, prewarmConnections: {}, sharedExplorePostId: { _ in nil },
            captureGoalAccountId: { $0?.uuidString }, requestNotificationAuthorization: { _ in }, feedback: base.feedback)
        return .init(diContainer: .preview, dependencies: dependencies, prewarmHeadersOnInit: false)
    }
}
