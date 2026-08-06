# iOS App Transport Security Contract

Naturebook uses the platform App Transport Security (ATS) defaults for the
main iOS application. The app has no global, media, web-content, local-network,
or domain-scoped transport exception. Every app-configured remote origin and
every backend-supplied remote media URL must be credential-free HTTPS before it
is handed to URLSession, AVFoundation, or SwiftUI image loading.

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

Do not add an exception to recover from an HTTP backend or media URL. Repair
the producer or origin. If a future product requirement genuinely cannot use
HTTPS, it needs a separately reviewed, narrowly scoped design, security review,
App Review justification, and an update to these executable validators before
code is merged.

## Executable validation

Run the source validator and its adversarial fixtures with:

```bash
make validate-ios-transport-security
make test-ios-transport-security
```

`scripts/validate-ios-transport-security.sh` parses the plist rather than
searching text. Its fixtures prove that each broad exception, domain
exceptions, HTTP/credentialed Supabase origins, and unresolved archived build
settings fail closed.

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
archive passes the same archive validator. Any ATS exception or HTTP production
origin is a release blocker.

## Regression coverage

The Swift tests cover HTTPS acceptance; rejection of HTTP, non-network schemes,
embedded credentials, and missing hosts; local-file compatibility; invalid
Supabase configuration; and rejection before the image loader dispatches an
HTTP request. The shell fixtures independently prove source-, archive-, and
exported-IPA enforcement.
