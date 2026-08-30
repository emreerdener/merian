enum ComplimentaryPlanDetailContext {
    case hidden
    case results
    case settings

    var showsDetails: Bool {
        self != .hidden
    }
}
