import Foundation
import Observation

@MainActor
@Observable
final class DescribeInputViewModel {
    struct DictationResultSink {
        let yield: @MainActor (_ transcription: String) -> Void
    }

    struct Dependencies {
        let startDictation: @MainActor (
            _ resultSink: DictationResultSink
        ) async throws -> Bool
        let stopDictation: @MainActor () -> Void
        let waitForSubjectInference: @MainActor () async throws -> Void
        let inferSubjectId: @MainActor (_ text: String) -> String?
    }

    private(set) var isDictationSessionActive = false
    private(set) var pendingSubjectInferenceText: String?

    @ObservationIgnored private let dependencies: Dependencies
    @ObservationIgnored private var subjectInferenceTask: Task<Void, Never>?
    @ObservationIgnored private var subjectInferenceGeneration = 0
    @ObservationIgnored private var dictationStartupTask: Task<Void, Never>?
    @ObservationIgnored private var priorDictationStartupTask: Task<Void, Never>?
    @ObservationIgnored private var priorDictationStartupGeneration: Int?
    @ObservationIgnored private var dictationStartupGeneration: Int?
    @ObservationIgnored private var activeDictationGeneration: Int?
    @ObservationIgnored private var dictationGeneration = 0

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func promptFlowDidChange() {
        invalidateSubjectInference()
    }

    func descriptionDidChange(
        text: String,
        isReanalysis: Bool,
        isFunnelActive: Bool,
        shouldApplySubject: @escaping @MainActor () -> Bool,
        onDescriptionEmptied: @escaping @MainActor () -> Void,
        onSubjectInferred: @escaping @MainActor (_ subjectId: String) -> Void
    ) {
        invalidateSubjectInference()
        guard !isReanalysis else { return }

        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            onDescriptionEmptied()
            return
        }
        guard !isFunnelActive else { return }

        let generation = subjectInferenceGeneration
        let dependencies = dependencies
        pendingSubjectInferenceText = text
        subjectInferenceTask = Task { [weak self] in
            do {
                try await dependencies.waitForSubjectInference()
            } catch {
                self?.finishSubjectInference(generation: generation)
                return
            }

            guard !Task.isCancelled,
                  let self,
                  self.subjectInferenceGeneration == generation,
                  shouldApplySubject() else {
                self?.finishSubjectInference(generation: generation)
                return
            }

            let subjectId = dependencies.inferSubjectId(text)
            finishSubjectInference(generation: generation)
            if let subjectId {
                onSubjectInferred(subjectId)
            }
        }
    }

    func dictationRequestDidChange(
        isRequested: Bool,
        baseText: String,
        onTranscript: @escaping @MainActor (_ composedText: String) -> Void,
        onRequestEnded: @escaping @MainActor () -> Void
    ) {
        if isRequested {
            startDictation(
                baseText: baseText,
                onTranscript: onTranscript,
                onRequestEnded: onRequestEnded
            )
        } else {
            stopDictationSession(
                isRequested: false,
                isRecording: false,
                isStarting: false,
                onRequestEnded: onRequestEnded
            )
        }
    }

    func speechRecordingDidChange(
        isRecording: Bool,
        isRequested: Bool,
        onRequestEnded: @escaping @MainActor () -> Void
    ) {
        guard !isRecording, isRequested else { return }
        invalidateDictationSession()
        onRequestEnded()
    }

    func stopDictation(
        isRequested: Bool,
        isRecording: Bool,
        isStarting: Bool,
        onRequestEnded: @escaping @MainActor () -> Void
    ) {
        stopDictationSession(
            isRequested: isRequested,
            isRecording: isRecording,
            isStarting: isStarting,
            onRequestEnded: onRequestEnded
        )
    }

    func stopAll(
        isRequested: Bool,
        isRecording: Bool,
        isStarting: Bool,
        onRequestEnded: @escaping @MainActor () -> Void
    ) {
        invalidateSubjectInference()
        stopDictationSession(
            isRequested: isRequested,
            isRecording: isRecording,
            isStarting: isStarting,
            onRequestEnded: onRequestEnded
        )
    }

    private func startDictation(
        baseText: String,
        onTranscript: @escaping @MainActor (_ composedText: String) -> Void,
        onRequestEnded: @escaping @MainActor () -> Void
    ) {
        guard !isDictationSessionActive else { return }

        let priorStartupTask = priorDictationStartupTask
        priorDictationStartupTask = nil
        priorDictationStartupGeneration = nil
        dictationGeneration &+= 1
        let generation = dictationGeneration
        activeDictationGeneration = generation
        dictationStartupGeneration = generation
        isDictationSessionActive = true
        let dependencies = dependencies

        dictationStartupTask = Task { [weak self] in
            defer {
                self?.finishDictationStartup(generation: generation)
            }

            if let priorStartupTask {
                await priorStartupTask.value
            }
            guard !Task.isCancelled,
                  let self,
                  self.activeDictationGeneration == generation,
                  self.isDictationSessionActive else {
                return
            }

            do {
                let didStart = try await dependencies.startDictation(
                    DictationResultSink { [weak self] transcription in
                        guard let self,
                              self.activeDictationGeneration == generation,
                              self.isDictationSessionActive,
                              let composedText = DescribeTextComposer.dictationText(
                                  baseText: baseText,
                                  transcription: transcription
                              ) else {
                            return
                        }
                        onTranscript(composedText)
                    }
                )
                guard !Task.isCancelled,
                      self.activeDictationGeneration == generation,
                      self.isDictationSessionActive else {
                    if didStart {
                        dependencies.stopDictation()
                    }
                    return
                }
                guard didStart else {
                    guard self.finishDictationSession(
                        generation: generation
                    ) else {
                        return
                    }
                    onRequestEnded()
                    return
                }
            } catch {
                guard self.finishDictationSession(generation: generation) else {
                    return
                }
                onRequestEnded()
            }
        }
    }

    private func stopDictationSession(
        isRequested: Bool,
        isRecording: Bool,
        isStarting: Bool,
        onRequestEnded: @escaping @MainActor () -> Void
    ) {
        let shouldStop = isDictationSessionActive
            || dictationStartupTask != nil
            || isRequested
            || isRecording
            || isStarting
        guard shouldStop else { return }

        let hadPendingStartup = invalidateDictationSession()
        if !hadPendingStartup {
            dependencies.stopDictation()
        }
        onRequestEnded()
    }

    private func invalidateSubjectInference() {
        subjectInferenceGeneration &+= 1
        subjectInferenceTask?.cancel()
        subjectInferenceTask = nil
        pendingSubjectInferenceText = nil
    }

    private func finishSubjectInference(generation: Int) {
        guard subjectInferenceGeneration == generation else { return }
        subjectInferenceTask = nil
        pendingSubjectInferenceText = nil
    }

    private func finishDictationStartup(generation: Int) {
        if dictationStartupGeneration == generation {
            dictationStartupTask = nil
            dictationStartupGeneration = nil
        }
        if priorDictationStartupGeneration == generation {
            priorDictationStartupTask = nil
            priorDictationStartupGeneration = nil
        }
    }

    @discardableResult
    private func finishDictationSession(generation: Int) -> Bool {
        guard activeDictationGeneration == generation else { return false }
        isDictationSessionActive = false
        activeDictationGeneration = nil
        if dictationStartupGeneration == generation {
            dictationStartupTask = nil
            dictationStartupGeneration = nil
        }
        return true
    }

    @discardableResult
    private func invalidateDictationSession() -> Bool {
        dictationGeneration &+= 1
        activeDictationGeneration = nil
        isDictationSessionActive = false
        let hadPendingStartup = dictationStartupTask != nil
        if let dictationStartupTask {
            dictationStartupTask.cancel()
            priorDictationStartupTask = dictationStartupTask
            priorDictationStartupGeneration = dictationStartupGeneration
        }
        dictationStartupTask = nil
        dictationStartupGeneration = nil
        return hadPendingStartup
    }
}
