extension FieldTripScanContribution {
    var destination: CaptureGoalDestination? {
        switch sourceKind {
        case .standardOuting:
            guard let destinationTemplateId, let destinationChecklistItemId else { return nil }
            return .fieldTrip(
                templateId: destinationTemplateId,
                checklistItemId: destinationChecklistItemId
            )
        case .event:
            guard let destinationChallengeId else { return nil }
            return .fieldTripChallenge(challengeId: destinationChallengeId)
        }
    }
}
