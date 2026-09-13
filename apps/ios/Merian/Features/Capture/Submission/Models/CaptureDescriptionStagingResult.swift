/// An empty editor is valid at submission; rejected nonempty text must stay recoverable.
enum CaptureDescriptionStagingResult: Equatable {
    case emptyDraft
    case staged
    case rejected
}
