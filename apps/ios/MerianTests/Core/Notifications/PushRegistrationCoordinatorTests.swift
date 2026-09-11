import Testing

@testable import Merian

@MainActor
struct PushRegistrationCoordinatorTests {
    @Test("A changed registration arriving in flight runs afterward")
    func changedTrailingRegistrationRuns() async {
        let gate = NotificationAsyncGate()
        var registrations: [PushRegistrationRequest] = []
        let coordinator = makeCoordinator { request in
            registrations.append(request)
            if registrations.count == 1 {
                await gate.suspend()
            }
        }
        let first = request(token: "first", exploreEnabled: false)
        let second = request(token: "second", exploreEnabled: true)

        let firstSync = Task { await coordinator.synchronize(first, reason: "first") }
        await waitUntil { gate.entryCount == 1 }
        var secondStarted = false
        let secondSync = Task {
            secondStarted = true
            await coordinator.synchronize(second, reason: "second")
        }
        await waitUntil { secondStarted }
        gate.resume()
        await firstSync.value
        await secondSync.value

        #expect(registrations == [first, second])
    }

    @Test("Only the newest changed trailing registration is retained")
    func newestTrailingRegistrationWins() async {
        let gate = NotificationAsyncGate()
        var registrations: [PushRegistrationRequest] = []
        let coordinator = makeCoordinator { request in
            registrations.append(request)
            if registrations.count == 1 {
                await gate.suspend()
            }
        }
        let first = request(token: "first", exploreEnabled: false)
        let superseded = request(token: "second", exploreEnabled: false)
        let latest = request(token: "third", exploreEnabled: true)

        let firstSync = Task { await coordinator.synchronize(first, reason: "first") }
        await waitUntil { gate.entryCount == 1 }
        var supersededStarted = false
        let supersededSync = Task {
            supersededStarted = true
            await coordinator.synchronize(
                superseded,
                reason: "superseded"
            )
        }
        await waitUntil { supersededStarted }
        var latestStarted = false
        let latestSync = Task {
            latestStarted = true
            await coordinator.synchronize(latest, reason: "latest")
        }
        await waitUntil { latestStarted }
        gate.resume()
        await firstSync.value
        await supersededSync.value
        await latestSync.value

        #expect(registrations == [first, latest])
    }

    @Test("An equal trailing registration coalesces after success")
    func equalTrailingRegistrationCoalesces() async {
        let gate = NotificationAsyncGate()
        var registrationCount = 0
        let coordinator = makeCoordinator { _ in
            registrationCount += 1
            if registrationCount == 1 {
                await gate.suspend()
            }
        }
        let registration = request(token: "same", exploreEnabled: true)

        let firstSync = Task {
            await coordinator.synchronize(registration, reason: "first")
        }
        await waitUntil { gate.entryCount == 1 }
        var secondStarted = false
        let secondSync = Task {
            secondStarted = true
            await coordinator.synchronize(registration, reason: "second")
        }
        await waitUntil { secondStarted }
        gate.resume()
        await firstSync.value
        await secondSync.value

        #expect(registrationCount == 1)
    }

    @Test("An equal trailing registration retries after failure")
    func equalTrailingRegistrationRetriesAfterFailure() async {
        let gate = NotificationAsyncGate()
        var registrationCount = 0
        var failureReasons: [String] = []
        let coordinator = PushRegistrationCoordinator(
            dependencies: .init(
                service: PushRegistrationService { _ in
                    registrationCount += 1
                    if registrationCount == 1 {
                        await gate.suspend()
                        throw NotificationTestError.expected
                    }
                },
                reportFailure: { reason, _ in
                    failureReasons.append(reason)
                }
            )
        )
        let registration = request(token: "same", exploreEnabled: true)

        let firstSync = Task {
            await coordinator.synchronize(registration, reason: "first")
        }
        await waitUntil { gate.entryCount == 1 }
        var retryStarted = false
        let retrySync = Task {
            retryStarted = true
            await coordinator.synchronize(registration, reason: "retry")
        }
        await waitUntil { retryStarted }
        gate.resume()
        await firstSync.value
        await retrySync.value

        #expect(registrationCount == 2)
        #expect(failureReasons == ["first"])
    }

    @Test("An equal registration for a new account is not coalesced")
    func equalCrossAccountRegistrationRuns() async {
        let gate = NotificationAsyncGate()
        var registrations: [PushRegistrationRequest] = []
        let coordinator = makeCoordinator { request in
            registrations.append(request)
            if registrations.count == 1 {
                await gate.suspend()
            }
        }
        let first = request(
            accountScopeID: "account-a",
            token: "same",
            exploreEnabled: true
        )
        let second = request(
            accountScopeID: "account-b",
            token: "same",
            exploreEnabled: true
        )

        let firstSync = Task {
            await coordinator.synchronize(first, reason: "first-account")
        }
        await waitUntil { gate.entryCount == 1 }
        var secondStarted = false
        let secondSync = Task {
            secondStarted = true
            await coordinator.synchronize(second, reason: "second-account")
        }
        await waitUntil { secondStarted }
        gate.resume()
        await firstSync.value
        await secondSync.value

        #expect(registrations == [first, second])
    }

    private func makeCoordinator(
        register: @escaping @MainActor (
            PushRegistrationRequest
        ) async throws -> Void
    ) -> PushRegistrationCoordinator {
        PushRegistrationCoordinator(
            dependencies: .init(
                service: PushRegistrationService(register: register),
                reportFailure: { _, _ in }
            )
        )
    }

    private func request(
        accountScopeID: String = "account-test",
        token: String,
        exploreEnabled: Bool
    ) -> PushRegistrationRequest {
        PushRegistrationRequest(
            accountScopeID: accountScopeID,
            deviceToken: token,
            environment: "sandbox",
            exploreEnabled: exploreEnabled,
            commentMentionsEnabled: true,
            communityIdentificationsEnabled: true
        )
    }
}
