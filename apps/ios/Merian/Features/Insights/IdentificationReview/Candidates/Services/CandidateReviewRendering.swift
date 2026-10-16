struct CandidateReviewRendering {
    var images = SimilarSpeciesImageDependencies { _ in .init(images: [], commonName: nil) }
    var feedback = IdentificationReviewFeedbackDependencies()
    static let live = Self(images: .live, feedback: .live)
}
