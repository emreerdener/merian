import Combine

@MainActor
final class InsightCarouselVideoPlaybackCoordinator {
    private let pauseForFullscreenPresentationSubject:
        PassthroughSubject<Void, Never>
    let pauseForFullscreenPresentationPublisher: AnyPublisher<Void, Never>

    init() {
        let subject = PassthroughSubject<Void, Never>()
        pauseForFullscreenPresentationSubject = subject
        pauseForFullscreenPresentationPublisher = subject.eraseToAnyPublisher()
    }

    func pauseForFullscreenPresentation() {
        pauseForFullscreenPresentationSubject.send()
    }
}
