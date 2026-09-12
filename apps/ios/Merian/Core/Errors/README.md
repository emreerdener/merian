# Core Errors

`Core/Errors` owns cross-domain error values that are part of the iOS app's
shared internal API.

`MerianError.swift` defines the stable localized taxonomy used across network,
inference, subscription, and hardware boundaries. It contains no retry,
connectivity, presentation, logging, or recovery policy. Those decisions stay
with the consuming domain; scan transport classification lives in
`Core/Data/OfflineSync/Policies/ScanConnectivityFailurePolicy.swift`.

Feature-specific customer-safe copy and endpoint DTO errors remain with their
feature or transport owner. Do not turn this directory into an error-handling
workflow or a catch-all result-model package.

`CoreUtilitiesArchitectureTests` freezes `Core/Errors/MerianError.swift` as the
exact declaration owner and keeps the retired Utilities path absent.
