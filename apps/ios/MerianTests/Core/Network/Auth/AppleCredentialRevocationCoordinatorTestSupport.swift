import Foundation
@testable import Merian

actor AppleRevocationLookupController {
    private struct Request {
        let continuation: CheckedContinuation<
            AppleCredentialRevocationLookupResult,
            Never
        >
    }

    private var requests: [Request] = []
    private var requestedSubjects: [String] = []

    func lookup(
        _ providerSubject: String
    ) async -> AppleCredentialRevocationLookupResult {
        requestedSubjects.append(providerSubject)
        return await withCheckedContinuation { continuation in
            requests.append(
                Request(
                    continuation: continuation
                )
            )
        }
    }

    func waitUntilRequestCount(_ expectedCount: Int) async {
        while requestedSubjects.count < expectedCount {
            await Task.yield()
        }
    }

    func requestCount() -> Int {
        requestedSubjects.count
    }

    func subjects() -> [String] {
        requestedSubjects
    }

    func resolveNext(
        with result: AppleCredentialRevocationLookupResult
    ) {
        precondition(!requests.isEmpty, "No credential lookup is pending.")
        let request = requests.removeFirst()
        request.continuation.resume(returning: result)
    }
}

@MainActor
final class AppleRevocationCoordinatorHarness {
    let firstIdentity = AppleCredentialRevocationIdentity(
        session: AuthTransitionSession(
            userID: UUID(
                uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"
            )!,
            isAnonymous: false
        ),
        providerSubject: "apple-subject-a"
    )
    let secondIdentity = AppleCredentialRevocationIdentity(
        session: AuthTransitionSession(
            userID: UUID(
                uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB"
            )!,
            isAnonymous: false
        ),
        providerSubject: "apple-subject-b"
    )

    let lookups = AppleRevocationLookupController()
    var hasActiveTransition = false
    var currentIdentity: AppleCredentialRevocationIdentity?
    var beforeClearAdmission: (() -> Void)?
    var shouldDeferClear = false
    private(set) var clearAdmissionCount = 0
    private(set) var clearCount = 0
    private(set) var diagnostics: [AppleCredentialRevocationDiagnostic] = []

    func dependencies() -> AppleCredentialRevocationDependencies {
        AppleCredentialRevocationDependencies(
            session: .init(
                hasActiveTransition: {
                    self.hasActiveTransition
                },
                currentIdentity: {
                    self.currentIdentity
                }
            ),
            operations: .init(
                lookupCredentialState: { providerSubject in
                    await self.lookups.lookup(providerSubject)
                },
                clearLocalSessionIfCurrent: { expectedIdentity in
                    self.clearAdmissionCount += 1
                    self.beforeClearAdmission?()
                    guard !self.hasActiveTransition,
                          self.currentIdentity == expectedIdentity else {
                        return .contextChanged
                    }
                    guard !self.shouldDeferClear else {
                        return .deferred
                    }
                    self.clearCount += 1
                    self.currentIdentity = nil
                    return .cleared
                }
            ),
            diagnose: { diagnostic in
                self.diagnostics.append(diagnostic)
            }
        )
    }
}
