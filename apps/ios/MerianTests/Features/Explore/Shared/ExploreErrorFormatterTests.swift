import Foundation
@testable import Merian
import Testing

@Suite("Explore Error Formatter Tests")
struct ExploreErrorFormatterTests {
    @Test func taskAndURLSessionCancellationsAreSilent() {
        #expect(ExploreErrorFormatter.isCancellation(CancellationError()))
        #expect(ExploreErrorFormatter.isCancellation(URLError(.cancelled)))
        #expect(!ExploreErrorFormatter.isCancellation(URLError(.timedOut)))
    }

    @Test func duplicateScanPrimaryKeyErrorsUseShareRecoveryCopy() {
        let message = ExploreErrorFormatter.message(for: MerianError.httpError(
            statusCode: 409,
            message: "duplicate key value violates unique constraint \"scans_pkey\""
        ))

        #expect(message == "This scan is already saved. Try sharing again.")
    }

    @Test func jsonWrappedDuplicateScanErrorsAreSanitized() {
        let rawMessage = #"{"error":"duplicate key value violates unique constraint \"scans_pkey\""}"#

        let message = ExploreErrorFormatter.message(for: MerianError.httpError(
            statusCode: 409,
            message: rawMessage
        ))

        #expect(message == "This scan is already saved. Try sharing again.")
    }

    @Test func friendlyApiErrorsPassThrough() {
        let message = ExploreErrorFormatter.message(for: MerianError.httpError(
            statusCode: 409,
            message: "Only biological scans can be shared to Explore."
        ))

        #expect(message == "Only biological scans can be shared to Explore.")
    }

    @Test func technicalPersistenceErrorsUseGenericPersistenceCopy() {
        let message = ExploreErrorFormatter.message(for: MerianError.httpError(
            statusCode: 400,
            message: "null value in column \"species_id\" violates not-null constraint"
        ))

        #expect(message == "We couldn’t finish that. Please try again.")
    }

    @Test func stagedMediaConstraintErrorsUseSharePreparationCopy() {
        let rawMessage = "createStagedScanMediaAssets: new row violates check "
            + "constraint \"scan_media_assets_kind_check\""
        let message = ExploreErrorFormatter.message(for: MerianError.httpError(
            statusCode: 500,
            message: rawMessage
        ))

        #expect(
            message
                == "We couldn’t prepare this media for sharing. Please try again."
        )
    }

    @Test func emptyHttpErrorsUseGenericCopy() {
        let message = ExploreErrorFormatter.message(for: MerianError.httpError(
            statusCode: 400,
            message: "   "
        ))

        #expect(message == "Something went wrong. Please try again.")
    }

    @Test func titledMessagesPreserveSanitizedBody() {
        let message = ExploreErrorFormatter.titledMessage(
            "Couldn’t share to Explore",
            for: MerianError.httpError(
                statusCode: 409,
                message: "duplicate key value violates unique constraint \"scans_pkey\""
            )
        )

        #expect(
            message
                == "Couldn’t share to Explore\nThis scan is already saved. Try sharing again."
        )
    }

    @Test func serviceRoleErrorsUseCustomerFacingAvailabilityCopy() {
        let message = ExploreErrorFormatter.titledMessage(
            "Couldn’t share to Explore",
            for: MerianError.httpError(
                statusCode: 500,
                message: "Failed to sync public author identity: "
                    + "service_role authorization required"
            )
        )

        #expect(
            message
                == "Couldn’t share to Explore\nExplore is temporarily unavailable. Please try again in a few minutes."
        )
    }

    @Test func platformFunctionNotFoundUsesCustomerFacingAvailabilityCopy() {
        let message = ExploreErrorFormatter.titledMessage(
            "Couldn’t share to Explore",
            for: MerianError.httpError(
                statusCode: 404,
                message: #"{"code":"NOT_FOUND","message":"Requested function was not found"}"#
            )
        )

        #expect(
            message
                == "Couldn’t share to Explore\nExplore is temporarily unavailable. Please try again in a few minutes."
        )
    }

    @Test func classifiedPlatformRouteFailureUsesCustomerFacingAvailabilityCopy() {
        #expect(
            ExploreErrorFormatter.message(for: MerianError.edgeFunctionUnavailable)
                == "Explore is temporarily unavailable. Please try again in a few minutes."
        )
    }

    @Test func speciesStatsUsesContextualTemporaryServiceCopy() {
        #expect(
            ExploreErrorFormatter.speciesStatsMessage(
                for: MerianError.edgeFunctionUnavailable
            )
                == "Live observation statistics are temporarily unavailable. Please try again later."
        )
    }

    @Test func recentActivityUsesContextualTemporaryServiceCopy() {
        #expect(
            ExploreErrorFormatter.recentActivityMessage(
                for: MerianError.edgeFunctionUnavailable
            )
                == "Recent activity is temporarily unavailable. Please try again in a few minutes."
        )
    }

    @Test func missingCloudScansUseCustomerFacingSyncCopy() {
        let message = ExploreErrorFormatter.titledMessage(
            "Couldn’t share to Explore",
            for: MerianError.httpError(
                statusCode: 404,
                message: #"{"error":"Scan not found.","code":"not_found"}"#
            )
        )

        #expect(
            message
                == "Couldn’t share to Explore\nThis observation is still syncing. Please wait a moment and try sharing again."
        )
    }

    @Test func fieldTripDetailHidesBackendIdentifierValidation() {
        let message = ExploreErrorFormatter.fieldTripDetailMessage(
            for: MerianError.httpError(
                statusCode: 400,
                message: "template_id must be a valid UUID."
            )
        )

        #expect(
            message
                == "We couldn’t find this field trip. Please go back and choose another outing."
        )
    }

    @Test func fieldTripDetailPreservesHelpfulMessages() {
        let message = ExploreErrorFormatter.fieldTripDetailMessage(
            for: MerianError.httpError(
                statusCode: 404,
                message: "This field trip is no longer available."
            )
        )

        #expect(message == "This field trip is no longer available.")
    }
}
