import Observation

@MainActor
@Observable
final class FieldTripTemplateDetailViewModel {
    struct Dependencies {
        let loadById: @MainActor (_ templateId: String) async throws -> FieldTripTemplate
        let loadBySlug: @MainActor (_ slug: String) async throws -> FieldTripTemplate
        let start: @MainActor (_ templateId: String) async throws -> FieldTripTemplate
        let stop: @MainActor (_ userFieldTripId: String) async throws -> FieldTripTemplate
        let reset: @MainActor (_ userFieldTripId: String) async throws -> FieldTripTemplate
        let loadCommunity: @MainActor (_ templateId: String) async throws -> [FieldTripRecentPublication]
        let successFeedback: @MainActor () -> Void
        let errorFeedback: @MainActor () -> Void
        let progressDidChange: @MainActor () -> Void
        let detailErrorMessage: @MainActor (Error) -> String
        let mutationErrorMessage: @MainActor (Error) -> String
    }

    var template: FieldTripTemplate?
    var communityPreview: [FieldTripRecentPublication] = []
    var isLoading = false
    var isStarting = false
    var isStopping = false
    var isResetting = false
    var isLoadingCommunityPreview = false
    var errorMessage: String?
    var toastMessage: ToastPayload?

    private let reference: FieldTripTemplateReference
    private let dependencies: Dependencies

    init(
        reference: FieldTripTemplateReference,
        dependencies: Dependencies = .live
    ) {
        self.reference = reference
        self.dependencies = dependencies
    }

    var isLifecycleMutating: Bool {
        isStarting || isStopping || isResetting
    }

    func load(
        force: Bool,
        onTemplateLoaded: (FieldTripTemplate) -> Void = { _ in }
    ) async {
        guard force || template == nil else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let loadedTemplate: FieldTripTemplate
            switch reference {
            case .id(let templateId):
                loadedTemplate = try await dependencies.loadById(templateId)
            case .slug(let slug):
                loadedTemplate = try await dependencies.loadBySlug(slug)
            }
            template = loadedTemplate
            onTemplateLoaded(loadedTemplate)
            await loadCommunityPreview(templateId: loadedTemplate.templateId)
        } catch {
            errorMessage = dependencies.detailErrorMessage(error)
        }
    }

    func start(_ template: FieldTripTemplate) async {
        guard !isLifecycleMutating else { return }
        let wasStopped = template.isStopped
        isStarting = true
        errorMessage = nil
        defer { isStarting = false }

        do {
            self.template = try await dependencies.start(template.templateId)
            dependencies.successFeedback()
            if wasStopped {
                toastMessage = .success("Field trip resumed.")
            }
            dependencies.progressDidChange()
        } catch {
            dependencies.errorFeedback()
            toastMessage = .error(dependencies.mutationErrorMessage(error))
        }
    }

    func stop(_ template: FieldTripTemplate) async {
        guard !isLifecycleMutating,
              let progress = template.activeProgress,
              !progress.isComplete else { return }
        isStopping = true
        defer { isStopping = false }

        do {
            self.template = try await dependencies.stop(progress.userFieldTripId)
            dependencies.successFeedback()
            toastMessage = .success("Field trip stopped. Your progress is saved.")
            dependencies.progressDidChange()
        } catch {
            dependencies.errorFeedback()
            toastMessage = .error(dependencies.mutationErrorMessage(error))
        }
    }

    func reset(_ template: FieldTripTemplate) async {
        guard !isLifecycleMutating,
              let progress = template.viewerProgress,
              !progress.isComplete,
              progress.publicationId == nil else { return }
        isResetting = true
        defer { isResetting = false }

        do {
            self.template = try await dependencies.reset(progress.userFieldTripId)
            dependencies.successFeedback()
            toastMessage = .success("Field trip reset.")
            dependencies.progressDidChange()
        } catch {
            dependencies.errorFeedback()
            toastMessage = .error(dependencies.mutationErrorMessage(error))
        }
    }

    private func loadCommunityPreview(templateId: String) async {
        isLoadingCommunityPreview = true
        defer { isLoadingCommunityPreview = false }

        communityPreview = (try? await dependencies.loadCommunity(templateId)) ?? []
    }
}
