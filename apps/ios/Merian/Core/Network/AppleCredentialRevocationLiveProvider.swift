import AuthenticationServices
import Foundation

/// Owns the Foundation observer token so cleanup never crosses the provider's
/// main-actor boundary from a nonisolated deinitializer.
private final class AppleRevocationObserverRegistration {
    private let notificationCenter: NotificationCenter
    private let observer: NSObjectProtocol

    init(
        notificationCenter: NotificationCenter,
        observer: NSObjectProtocol
    ) {
        self.notificationCenter = notificationCenter
        self.observer = observer
    }

    deinit {
        notificationCenter.removeObserver(observer)
    }
}

/// Contains the Apple SDK surface used by provider-neutral revocation
/// coordination.
@MainActor
final class AppleCredentialRevocationLiveProvider {
    private let notificationCenter: NotificationCenter
    private let provider: ASAuthorizationAppleIDProvider
    private var observerRegistration: AppleRevocationObserverRegistration?

    init(
        notificationCenter: NotificationCenter = NotificationCenter.default,
        provider: ASAuthorizationAppleIDProvider = .init()
    ) {
        self.notificationCenter = notificationCenter
        self.provider = provider
    }

    func startObserving(
        _ handler: @escaping @MainActor @Sendable () -> Void
    ) {
        stopObserving()
        let observer = notificationCenter.addObserver(
            forName: ASAuthorizationAppleIDProvider.credentialRevokedNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                handler()
            }
        }
        observerRegistration = AppleRevocationObserverRegistration(
            notificationCenter: notificationCenter,
            observer: observer
        )
    }

    func stopObserving() {
        observerRegistration = nil
    }

    func lookupCredentialState(
        forProviderSubject providerSubject: String
    ) async -> AppleCredentialRevocationLookupResult {
        await withCheckedContinuation { continuation in
            provider.getCredentialState(forUserID: providerSubject) { state, error in
                continuation.resume(
                    returning: Self.lookupResult(
                        for: state,
                        lookupFailed: error != nil
                    )
                )
            }
        }
    }

    nonisolated static func lookupResult(
        for state: ASAuthorizationAppleIDProvider.CredentialState,
        lookupFailed: Bool = false
    ) -> AppleCredentialRevocationLookupResult {
        if lookupFailed { return .lookupFailed }

        switch state {
        case .authorized:
            return .authorized
        case .revoked:
            return .revoked
        case .notFound:
            return .notFound
        case .transferred:
            return .transferred
        @unknown default:
            return .unknown
        }
    }
}
