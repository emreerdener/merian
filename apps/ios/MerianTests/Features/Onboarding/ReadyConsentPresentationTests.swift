@testable import Merian
import SwiftUI
import XCTest

final class ReadyConsentPresentationTests: XCTestCase {
    func testReadyStepMatchesStoredConsentCopyAndPurposeBeforeConsent() {
        let disclosure = ReadyStepView.disclosure
        let consent = ReadyStepView.consentStatement
        let adult = ReadyStepView.adultStatement
        let analytics = ReadyStepView.analyticsStatement

        XCTAssertEqual(ReadyStepView.title, "One last step")
        XCTAssertEqual(disclosure, ConsentPolicy.geminiDisclosureText)
        XCTAssertEqual(consent, ConsentPolicy.combinedAcceptanceText)
        XCTAssertEqual(adult, ConsentPolicy.adultConfirmationText)
        XCTAssertEqual(analytics, ConsentPolicy.analyticsDisclosureText)
        for switchStatement in [adult, consent, analytics] {
            XCTAssertFalse(
                switchStatement.hasSuffix("."),
                "Ready-step switch statements must not end with periods"
            )
        }

        let completeSurface = [disclosure, consent, adult, analytics]
            .joined(separator: " ")
        for requiredDisclosure in [
            "observation data",
            "terms",
            "Google Gemini",
            "AI-powered identification",
            "18 or older",
            "usage and diagnostics",
            "improve Naturebook"
        ] {
            XCTAssertTrue(
                completeSurface.contains(requiredDisclosure),
                "Ready-step disclosure must identify its recipient, data, and purpose: \(requiredDisclosure)"
            )
        }
    }

    func testEveryReadySwitchCombinationKeepsAnalyticsOptional() {
        for adultConfirmed in [false, true] {
            for geminiAllowed in [false, true] {
                for analyticsAllowed in [false, true] {
                    XCTAssertEqual(
                        ReadyStepView.canStartScanning(
                            adultConfirmed: adultConfirmed,
                            geminiAllowed: geminiAllowed,
                            analyticsAllowed: analyticsAllowed
                        ),
                        adultConfirmed && geminiAllowed
                    )
                }
            }
        }
    }

    func testReadyTermsLinkTargetsTheFullTermsOfService() throws {
        let statement = ReadyStepView.linkedConsentStatement
        let termsRange = try XCTUnwrap(statement.range(of: "terms"))

        XCTAssertEqual(statement[termsRange].link, ReadyStepView.termsURL)
        XCTAssertTrue(ReadyStepView.termsURL.absoluteString.hasSuffix("/terms"))
    }

    func testReadyRequiredConsentStatementsEndWithRedAsterisk() throws {
        let statements = [
            ReadyStepView.appendingRequiredIndicator(
                to: AttributedString(ReadyStepView.adultStatement)
            ),
            ReadyStepView.linkedConsentStatement
        ]

        for statement in statements {
            XCTAssertTrue(
                String(statement.characters)
                    .hasSuffix(ReadyStepView.requiredIndicator)
            )
            let indicatorRange = try XCTUnwrap(statement.range(of: "*"))
            XCTAssertEqual(
                statement[indicatorRange].foregroundColor,
                Color.red
            )
        }

        XCTAssertFalse(ReadyStepView.analyticsStatement.hasSuffix("*"))
    }
}
