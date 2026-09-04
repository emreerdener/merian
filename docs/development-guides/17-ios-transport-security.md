# iOS App Transport Security Contract

Naturebook uses the platform App Transport Security (ATS) defaults for the main
iOS application. The app has no global, media, web-content, local-network, or
domain-scoped transport exception. Every app-configured remote origin and every
backend-supplied remote media URL must be credential-free HTTPS before it is
handed to URLSession, AVFoundation, or SwiftUI image loading.

This contract follows Apple's
[guidance for preventing insecure network connections](https://developer.apple.com/documentation/security/preventing-insecure-network-connections).
Apple documents that
[`NSAllowsArbitraryLoads`](https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsallowsarbitraryloads)
disables ATS restrictions for most connections and requires App Review
justification. Naturebook does not use that exception.

## Source contract

- `apps/ios/Merian/Configuration/Info.plist` must not enable
  `NSAllowsArbitraryLoads`, `NSAllowsArbitraryLoadsForMedia`,
  `NSAllowsArbitraryLoadsInWebContent`, or `NSAllowsLocalNetworking` and must
  not contain `NSExceptionDomains`.
- `SUPABASE_URL` must resolve to a credential-free HTTPS origin. The tracked
  source plist may contain the Xcode build-setting placeholder; the archived
  plist may not.
- `SecureTransportPolicy` is the shared application boundary for untrusted or
  remotely supplied URL strings. `httpsURL(from:)` requires an HTTPS scheme, a
  nonempty host, and no embedded username or password.
- `localFileOrHTTPSURL(from:)` accepts app-owned local paths and file URLs, but
  admits only HTTPS when the input has a remote scheme.
- Signed R2 upload/download URLs, Edge endpoints, avatars, remote observation
  media, and reference media are validated at the boundary that first turns
  their string representation into a network URL. ATS remains the independent
  operating-system backstop.

## Supabase certificate-pinning boundary

Release builds add an application-layer pin check for `supabase.co` and its true
subdomains in
`apps/ios/Merian/Core/Network/Transport/PinnedNetworkTransport.swift`. The
delegate accepts a matching server-trust challenge only when all of these
conditions hold:

1. Apple's `SecTrustEvaluateWithError` accepts the trust using the URLSession
   hostname and certificate policies.
2. The evaluated certificate chain is readable.
3. At least one certificate's DER SHA-256 hash matches the maintained pin set.

Failure of any condition cancels the challenge. Suffix lookalikes such as
`not-supabase.co`, unrelated HTTPS origins such as signed R2 hosts, and
non-server-trust challenges retain platform handling. Pinning is intentionally
disabled in `DEBUG` builds so local test proxies remain usable; a Debug build is
therefore not Release pinning evidence.

The pin set retains the reviewed leaf plus intermediate fallback so a planned
leaf rotation can overlap app versions. Follow the source and
[Core Network rotation checklist](./09-core-managers.md#tls-certificate-pinning-meriantlsdelegate):
add a new pin before rollout, ship the overlap, and remove a stale pin only
after the old certificate is no longer served. Never weaken platform trust,
widen hostname admission, or fall back to default handling to recover from a pin
mismatch.

Do not add an exception to recover from an HTTP backend or media URL. Repair the
producer or origin. If a future product requirement genuinely cannot use HTTPS,
it needs a separately reviewed, narrowly scoped design, security review, App
Review justification, and an update to these executable validators before code
is merged.

## Executable validation

Run the source validator and its adversarial fixtures with:

```bash
make validate-ios-transport-security
make test-ios-transport-security
```

`scripts/validate-ios-transport-security.sh` parses the plist rather than
searching text. Its fixtures prove that each broad exception, domain exceptions,
HTTP/credentialed Supabase origins, and unresolved archived build settings fail
closed.

`PinnedNetworkTransportTests` independently verifies exact hostname admission,
valid pin encoding, intermediate fallback, rejection of missing, empty,
unmatched, or platform-untrusted chains, concurrent single-session creation, and
the Debug replacement seam. `CoreNetworkIntegrationArchitectureTests` keeps
session construction, `SecTrustEvaluateWithError`, the TLS delegate, and the
Release cancellation paths in their reviewed owner. These Swift tests do not
replace the plist/archive validators, and those validators do not prove pin
freshness.

The same check is part of `make test-ios-ci-tooling`, the generated-project
guardrail workflow, `scripts/validate-ios-archive.sh`, and
`scripts/validate-ios-exported-ipa.sh`. The archive and IPA validators inspect
the final main-app `Info.plist`, because a safe source plist is not evidence
that the built product retained the same configuration.

## Release evidence

The exact-SHA **iOS Build and Test** archive evidence must contain:

```json
{
  "transport_security": "ats-default"
}
```

Before TestFlight or App Store promotion, the release owner must also verify
that every configured production origin is HTTPS and that the signed Organizer
archive passes the same archive validator. The exact candidate must compile the
Release TLS branch and pass the pinned-transport and architecture suites; the
release owner must also confirm that the current Supabase chain is represented
by the reviewed overlap set. Any ATS exception, HTTP production origin, failed
platform trust, or unplanned pin mismatch is a release blocker.

## Regression coverage

The Swift tests cover HTTPS acceptance; rejection of HTTP, non-network schemes,
embedded credentials, and missing hosts; local-file compatibility; invalid
Supabase configuration; and rejection before the image loader dispatches an HTTP
request. The focused transport suite additionally covers the Release
platform-trust-plus-pin decision and exact Supabase domain boundary. The shell
fixtures independently prove source-, archive-, and exported-IPA enforcement.
