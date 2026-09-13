enum FieldTripProgressPresentation {
    static func completedCount(for update: FieldTripProgressUpdate) -> Int {
        update.creditedCompletedCount ?? update.completedCount
    }

    static func targetCount(for update: FieldTripProgressUpdate) -> Int {
        update.creditedTargetCount ?? update.targetCount
    }

    static func completedCount(
        for update: FieldTripChallengeProgressUpdate
    ) -> Int {
        update.creditedCompletedCount ?? update.completedCount
    }

    static func targetCount(
        for update: FieldTripChallengeProgressUpdate
    ) -> Int {
        update.creditedTargetCount ?? update.targetCount
    }
}

extension FieldTripProgressUpdate {
    var toastCompletedCount: Int {
        FieldTripProgressPresentation.completedCount(for: self)
    }

    var toastTargetCount: Int {
        FieldTripProgressPresentation.targetCount(for: self)
    }
}

extension FieldTripChallengeProgressUpdate {
    var toastCompletedCount: Int {
        FieldTripProgressPresentation.completedCount(for: self)
    }

    var toastTargetCount: Int {
        FieldTripProgressPresentation.targetCount(for: self)
    }
}
