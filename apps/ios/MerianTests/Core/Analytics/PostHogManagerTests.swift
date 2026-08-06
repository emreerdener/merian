@testable import Merian
import PostHog
import XCTest

@MainActor
final class PostHogManagerTests: XCTestCase {
    func testTransportGateRejectsInsecureOrCredentialedHosts() {
        let gate = PostHogConsentNetworkGate.shared

        XCTAssertNil(gate.register(host: "http://posthog.example.test"))
        XCTAssertNil(
            gate.register(host: "https://user:secret@posthog.example.test")
        )
        XCTAssertNotNil(gate.register(host: "https://posthog.example.test"))
    }

    var postHogManager: PostHogManager!

    override func setUp() async throws {
        postHogManager = PostHogManager.shared
        postHogManager.reset()
    }

    override func tearDown() async throws {
        // Reset state so tests run deterministically
        postHogManager.reset()
        postHogManager = nil
    }

    func testManagerInitializationAndBindings() {
        XCTAssertNotNil(postHogManager)

        XCTAssertFalse(postHogManager.hasConsent)
        XCTAssertFalse(postHogManager.isCaptureEnabled)

        // Identity is rejected while analytics permission is absent.
        postHogManager.identifyUser(userId: "testing_bound_uuid")

        postHogManager.setConsentGranted(true, userId: "testing_bound_uuid")
        XCTAssertTrue(postHogManager.hasConsent)

        postHogManager.reset()
        XCTAssertFalse(postHogManager.hasConsent)
        XCTAssertFalse(postHogManager.isCaptureEnabled)
    }

    func testWithdrawalClosesTransportBeforeResetAndPreservesShutdownOrder() {
        let sdk = PostHogSDKSpy()
        let manager = PostHogManager(
            sdk: sdk,
            projectToken: { "test-posthog-token" },
            host: "https://posthog.example.test",
            shouldBypassSDK: { false }
        )

        manager.setConsentGranted(true, userId: "first-account")
        XCTAssertTrue(PostHogConsentNetworkGate.shared.isOpen)
        XCTAssertTrue(sdk.setupUsesConsentProtocol)
        XCTAssertTrue(sdk.setupUsesSessionTransportId)

        sdk.calls.removeAll()
        manager.setConsentGranted(false, userId: nil)

        XCTAssertEqual(sdk.calls, [.reset, .optOut, .close])
        XCTAssertTrue(sdk.gateWasClosedAtReset)
        XCTAssertFalse(PostHogConsentNetworkGate.shared.isOpen)
        XCTAssertFalse(manager.hasConsent)
        XCTAssertFalse(manager.isCaptureEnabled)

        manager.capture("must_be_dropped")
        manager.setConsentGranted(false, userId: nil)
        XCTAssertEqual(sdk.calls, [.reset, .optOut, .close])
    }

    func testDirectAccountTransitionShutsDownBeforeIdentifyingNewAccount() {
        let sdk = PostHogSDKSpy()
        let manager = PostHogManager(
            sdk: sdk,
            projectToken: { "test-posthog-token" },
            host: "https://posthog.example.test",
            shouldBypassSDK: { false }
        )

        manager.setConsentGranted(true, userId: "first-account")
        sdk.calls.removeAll()
        sdk.identifiedUserIds.removeAll()

        manager.setConsentGranted(true, userId: "second-account")

        XCTAssertEqual(
            sdk.calls,
            [.reset, .optOut, .close, .setup, .optIn, .identify]
        )
        XCTAssertTrue(sdk.gateWasClosedAtReset)
        XCTAssertEqual(sdk.identifiedUserIds.count, 1)
        manager.setConsentGranted(false, userId: nil)
    }

    func testSubsequentOptInCreatesANewTransportAndReidentifiesTheAccount() {
        let sdk = PostHogSDKSpy()
        let manager = PostHogManager(
            sdk: sdk,
            projectToken: { "test-posthog-token" },
            host: "https://posthog.example.test",
            shouldBypassSDK: { false }
        )

        manager.setConsentGranted(true, userId: "first-account")
        manager.setConsentGranted(false, userId: nil)
        sdk.calls.removeAll()

        manager.setConsentGranted(true, userId: "first-account")

        XCTAssertEqual(sdk.calls, [.setup, .optIn, .identify])
        XCTAssertEqual(sdk.setupTransportIds.count, 2)
        XCTAssertNotEqual(
            sdk.setupTransportIds.first,
            sdk.setupTransportIds.last,
            "A new grant must never reopen the withdrawn SDK session"
        )
        XCTAssertEqual(sdk.identifiedUserIds.count, 2)
        XCTAssertEqual(
            sdk.identifiedUserIds.first,
            sdk.identifiedUserIds.last,
            "The renewed session must identify the same pseudonymous account"
        )
        manager.setConsentGranted(false, userId: nil)
    }

    func testWithdrawalDuringConfigurationLeavesTransportClosedAndSkipsSetup() {
        let sdk = PostHogSDKSpy()
        var withdrawDuringTokenRead: (() -> Void)?
        let manager = PostHogManager(
            sdk: sdk,
            projectToken: {
                withdrawDuringTokenRead?()
                return "test-posthog-token"
            },
            host: "https://posthog.example.test",
            shouldBypassSDK: { false }
        )
        withdrawDuringTokenRead = {
            manager.setConsentGranted(false, userId: nil)
        }

        manager.setConsentGranted(true, userId: "first-account")

        XCTAssertTrue(sdk.calls.isEmpty)
        XCTAssertFalse(PostHogConsentNetworkGate.shared.isOpen)
        XCTAssertFalse(manager.hasConsent)
        XCTAssertFalse(manager.isConfigured)
        XCTAssertFalse(manager.isCaptureEnabled)
    }

    func testAccountSwitchInvalidatesConfigurationAlreadyInProgress() {
        let sdk = PostHogSDKSpy()
        var switchAccountDuringTokenRead: (() -> Void)?
        let manager = PostHogManager(
            sdk: sdk,
            projectToken: {
                let pendingSwitch = switchAccountDuringTokenRead
                switchAccountDuringTokenRead = nil
                pendingSwitch?()
                return "test-posthog-token"
            },
            host: "https://posthog.example.test",
            shouldBypassSDK: { false }
        )
        switchAccountDuringTokenRead = {
            manager.setConsentGranted(true, userId: "second-account")
        }

        manager.setConsentGranted(true, userId: "first-account")

        XCTAssertEqual(sdk.calls, [.setup, .optIn, .identify])
        XCTAssertEqual(sdk.identifiedUserIds.count, 1)
        XCTAssertTrue(manager.hasConsent)
        XCTAssertTrue(manager.isConfigured)
        XCTAssertTrue(manager.isCaptureEnabled)
        manager.setConsentGranted(false, userId: nil)
    }

    func testClosedTransportRejectsPostHogRequestWithoutDownstreamConnection() async throws {
        let gate = PostHogConsentNetworkGate.shared
        let transportId = try XCTUnwrap(
            gate.register(host: "https://posthog.example.test")
        )
        gate.close()
        PostHogDownstreamURLProtocol.reset()

        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpAdditionalHeaders = [
            PostHogConsentNetworkGate.transportHeader: transportId
        ]
        configuration.protocolClasses = [
            PostHogConsentURLProtocol.self,
            PostHogDownstreamURLProtocol.self
        ]
        let session = URLSession(configuration: configuration)
        let request = URLRequest(
            url: URL(string: "https://posthog.example.test/flags")!
        )

        do {
            _ = try await session.data(for: request)
            XCTFail("A closed PostHog transport must reject the request locally")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .cancelled)
        } catch {
            XCTFail("Unexpected transport error: \(error)")
        }
        XCTAssertEqual(PostHogDownstreamURLProtocol.requestCount, 0)

        let unrelatedRequest = URLRequest(
            url: URL(string: "https://api.example.test/status")!
        )
        _ = try? await session.data(for: unrelatedRequest)
        XCTAssertEqual(
            PostHogDownstreamURLProtocol.requestCount,
            1,
            "The closed gate must intercept only the configured PostHog host"
        )

        gate.open(transportId: transportId)
        _ = try? await session.data(for: request)
        XCTAssertEqual(PostHogDownstreamURLProtocol.requestCount, 2)
        gate.close()
        session.invalidateAndCancel()
    }

    func testOldTransportRemainsClosedAfterNewTransportOpens() async throws {
        let gate = PostHogConsentNetworkGate.shared
        let oldTransportId = try XCTUnwrap(
            gate.register(host: "https://posthog.example.test")
        )
        let oldConfiguration = URLSessionConfiguration.ephemeral
        oldConfiguration.httpAdditionalHeaders = [
            PostHogConsentNetworkGate.transportHeader: oldTransportId
        ]
        oldConfiguration.protocolClasses = [
            PostHogConsentURLProtocol.self,
            PostHogDownstreamURLProtocol.self
        ]
        let oldSession = URLSession(configuration: oldConfiguration)
        let request = URLRequest(
            url: URL(string: "https://posthog.example.test/flags")!
        )

        gate.open(transportId: oldTransportId)
        gate.close()
        let newTransportId = try XCTUnwrap(
            gate.register(host: "https://posthog.example.test")
        )
        gate.open(transportId: newTransportId)
        PostHogDownstreamURLProtocol.reset()

        do {
            _ = try await oldSession.data(for: request)
            XCTFail("A new grant must not reopen an old SDK session")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .cancelled)
        }
        XCTAssertEqual(PostHogDownstreamURLProtocol.requestCount, 0)

        gate.close()
        oldSession.invalidateAndCancel()
    }
}

private final class PostHogSDKSpy: PostHogSDKClient {
    enum Call: Equatable {
        case setup
        case reset
        case optOut
        case close
        case identify
        case capture
        case optIn
    }

    var calls: [Call] = []
    var identifiedUserIds: [String] = []
    var gateWasClosedAtReset = false
    var setupUsesConsentProtocol = false
    var setupUsesSessionTransportId = false
    var setupTransportIds: [String] = []

    func setup(_ configuration: PostHogConfig) {
        calls.append(.setup)
        setupUsesConsentProtocol = configuration.urlSessionConfiguration?
            .protocolClasses?
            .contains(where: {
                ObjectIdentifier($0)
                    == ObjectIdentifier(PostHogConsentURLProtocol.self)
            }) == true
        let transportId = configuration.urlSessionConfiguration?
            .httpAdditionalHeaders?[PostHogConsentNetworkGate.transportHeader]
            as? String
        setupUsesSessionTransportId = transportId != nil
        if let transportId {
            setupTransportIds.append(transportId)
        }
    }

    func reset() {
        calls.append(.reset)
        gateWasClosedAtReset = !PostHogConsentNetworkGate.shared.isOpen
    }

    func optOut() {
        calls.append(.optOut)
    }

    func close() {
        calls.append(.close)
    }

    func identify(_ userId: String) {
        calls.append(.identify)
        identifiedUserIds.append(userId)
    }

    func capture(_ event: String, properties: [String: Any]) {
        calls.append(.capture)
    }

    func optIn() {
        calls.append(.optIn)
    }
}

private final class PostHogDownstreamURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var _requestCount = 0

    static var requestCount: Int {
        lock.withLock { _requestCount }
    }

    static func reset() {
        lock.withLock { _requestCount = 0 }
    }

    // URLProtocol's Objective-C entry points require class dispatch.
    // swiftlint:disable:next static_over_final_class
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host?.hasSuffix(".example.test") == true
    }

    // swiftlint:disable:next static_over_final_class
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.lock.withLock { Self._requestCount += 1 }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(
            self,
            didReceive: response,
            cacheStoragePolicy: .notAllowed
        )
        client?.urlProtocol(self, didLoad: Data("{}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
