@testable import Merian
import Testing

@Suite("Scan Milestone Policy")
struct ScanMilestonePolicyTests {
    @Test func progressMappingKeepsStandardBeforeChallengeAndUsesGoalPrompt() {
        let result = MilestoneFeedbackTestFixtures.progressResult(
            challengeCommonName: "   ",
            challengePrompt: "Bee or wasp"
        )

        let milestones = ScanMilestonePolicy.milestones(from: result)

        #expect(milestones.count == 2)
        #expect(milestones[0].tripTitle == "Backyard Safari")
        #expect(milestones[0].goalLabel == "Spider")
        #expect(milestones[0].title == "Spider goal complete")
        #expect(
            milestones[0].artwork
                == .bundledImage(name: "fieldtrip-backyard-spider")
        )
        #expect(
            milestones[0].destination
                == .fieldTrip(
                    templateId: "template-1",
                    checklistItemId: "item-1"
                )
        )
        #expect(milestones[1].tripTitle == "Summer pollinators")
        #expect(milestones[1].goalLabel == "Bee or wasp")
        #expect(
            milestones[1].artwork
                == .systemSymbol(name: "binoculars.fill")
        )
        #expect(
            milestones[1].destination
                == .fieldTripChallenge(challengeId: "challenge-1")
        )
    }

    @Test func progressMappingIgnoresUpdatesWithoutNewlyCompletedItems() {
        let result = MilestoneFeedbackTestFixtures.progressResult(
            standardIncludesNewItem: false
        )

        let milestones = ScanMilestonePolicy.milestones(from: result)

        #expect(milestones.count == 1)
        #expect(milestones[0].tripTitle == "Summer pollinators")
        #expect(
            milestones[0].destination
                == .fieldTripChallenge(challengeId: "challenge-1")
        )
    }

    @Test func scanIdentityTrimsAndNormalizesForDeduplication() {
        #expect(
            ScanMilestonePolicy.identity(for: "  SCAN-A  ")
                == ScanMilestoneIdentity(value: "SCAN-A", key: "scan-a")
        )
        #expect(ScanMilestonePolicy.identity(for: "  \n ") == nil)
    }
}
