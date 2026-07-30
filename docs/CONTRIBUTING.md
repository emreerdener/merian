# Contributing to Naturebook 🦋

Thank you for your interest in contributing to Naturebook. Naturebook is the
public product; Merian remains the repository, Xcode project, target, module,
bundle, persistence, and backend engineering identity. Our goal is to build the
world's fastest, most resilient native iOS ecological identification engine.
Because Naturebook sits at the intersection of heavy edge-compute API inference,
hardware-accelerated LiDAR processing, and robust GDPR compliance, we enforce
stringent contribution guidelines.

## Code Architecture & Philosophy

Before contributing, please review our core architectural tenets. Refactoring code that violates these principles will not be merged.

1.  **Thermal Management is King**: iOS is hostile to apps that run the GPU and CPU concurrently at full load. Any feature added to the viewfinder MUST interface with `HardwareOrchestrator`. Frame rates must dynamically drop behind modals or when the device hits `.fair` or `.serious` thermal states.
2.  **Zero-OOM Edge Infrastructure**: Deno Edge Functions crash violently when handed 20MB Base64 strings. Naturebook processes media _exclusively_ via Gemini File URIs or Cloudflare R2 pointers. Do not attempt to reintroduce Base64 image bloat into the network payload arrays.
3.  **Offline-First Paradigm**: Network availability in the field is chaotic. Any user-generated action (e.g., snapping a photo) must first natively write to the `NWPathMonitor` SwiftData queue rather than awaiting network validations globally. Extension targets must stay lightweight: they may read explicit App Group snapshots, but must not open the app's SwiftData store or run scan reconciliation work.
4.  **Accessibility (a11y)**: If a feature presents visual data natively, it must possess native SwiftUI `.accessibilityLabel` arrays explicitly reading components in a human-friendly format (e.g., using `.combine` on Grid tables).
5.  **Public Brand Compatibility**: User-facing work must use Naturebook,
    Naturebook Pro, Naturebook AI, `naturebook.earth`, and `naturebook://`.
    Preserve stable Merian identifiers and indefinitely accept the documented
    legacy links. Read
    [`system-architecture/08-public-brand-compatibility.md`](./system-architecture/08-public-brand-compatibility.md)
    before changing display names, links, domains, identifiers, exports,
    attribution, support/legal copy, or release metadata.

## Setting Up the Development Environment

1.  **Xcode**: Use Xcode 26.6 on macOS Tahoe 26.2 or later to match the
    [compiled CI and supported host baseline](https://developer.apple.com/xcode/system-requirements/).
    The app deploys to iOS 17.2+, but the codebase relies on Swift 6-era
    concurrency diagnostics and modern SDK APIs such as
    `AVCaptureEventInteraction`.
2.  **Supabase CLI**: For testing edge functions locally, you will need the Supabase CLI installed.
3.  **Project Generation**: `project.yml` is the source of truth. `Merian.xcodeproj` is committed for convenience, but you should regenerate it after changing targets, packages, entitlements, build settings, or source-group layout:
    ```bash
    cp Signing.local.example.xcconfig Signing.local.xcconfig
    cp Config.local.example.xcconfig Config.local.xcconfig
    make xcodegen
    open Merian.xcodeproj
    ```
    Set `MERIAN_DEVELOPMENT_TEAM` in `Signing.local.xcconfig` to your personal Apple Developer Team ID. Do not hardcode a real team ID into `project.yml` or the shared `Signing.xcconfig`.
4.  **Client Config**: App-facing runtime values live in `Config.xcconfig`, with ignored machine-local overrides in `Config.local.xcconfig`. These values ship in the app bundle and are not backend-only secrets. Backend secrets, including Gemini and service-role keys, belong only in Supabase Edge Function secrets. The tracked defaults currently target production Supabase, so Debug simulator launches warn and still connect; use local/staging overrides for routine work. Set `MERIAN_ALLOW_PRODUCTION_SUPABASE_IN_DEBUG_SIMULATOR=1` only for an intentional production smoke run, because it suppresses the warning without sandboxing writes or anonymous users. Release archives may warn while using a RevenueCat `test_` key; TestFlight/App Store export should use a production iOS key beginning with `appl_`.
5.  **Backend Operations**: Production Supabase deploys run through GitHub Actions using token-based CLI auth, not a developer's interactive local login. See [`docs/backend-and-data/06-supabase-deployment-runbook.md`](./backend-and-data/06-supabase-deployment-runbook.md) for the CI path, required secrets, and smoke checks. From the repo root, the local emergency fallback remains:
    ```bash
    make db-push
    make functions-deploy
    ```
    New migrations must not add top-level transaction controls or concurrent
    index DDL. Supabase CLI `2.109.1` owns migration transaction and history
    boundaries; top-level timeout guards use session `SET` plus matching
    `RESET`, never `SET LOCAL`. Large indexes use the runbook's supervised
    concurrent preflight. Historical applied files are immutable and are not
    templates. Read the
    [server credential and database safety
    contract](./backend-and-data/13-server-credentials-and-database-release-safety.md)
    before changing keys, RLS, grants, defaults, migrations, user FKs, or
    destructive queues.
6.  **TestFlight Release Prep**: Before archiving in Xcode, run `make prepare-ios-release VERSION=x.y.z` from the repo root. If you are ready to use production RevenueCat, pass `REVENUECAT_API_KEY=appl_...` or set the same key in ignored `Config.local.xcconfig` first. The command updates the tracked XcodeGen source, regenerates `Merian.xcodeproj`, and writes the local archive-prep marker. Release/TestFlight uses the normal advisory free-scan meter; unlimited meter bypasses are DEBUG-only and never change authoritative Supabase quota. RevenueCat purchase QA must open Settings → Plan directly and follow the documented Test Store/StoreKit/TestFlight matrix. See [`docs/development-guides/14-ios-release-versioning.md`](./development-guides/14-ios-release-versioning.md) and [`docs/features-and-hardware/02-revenue-and-identity.md`](./features-and-hardware/02-revenue-and-identity.md#prelaunch-purchase-testing).

## Testing Protocol

- **Swift/iOS**: All `@MainActor` lifecycle boundaries must not block the main
  thread. Before opening a pull request, run the source-level CI contracts:
  ```bash
  make validate-ios-project
  make validate-ios-versioning
  make validate-ios-migration-guardrails
  make test-ios-ci-tooling
  ```
  If a change adds, removes, moves, or retargets source code, also run:
  ```bash
  bash scripts/test-ios-project-source-membership.sh
  bash scripts/check-ios-project-source-membership.sh
  ```
  Those two membership commands require the Ruby `xcodeproj` gem, which is
  available on the hosted macOS runner. The portable Make target intentionally
  tests the scope detector, workflow contract, and result validator without
  requiring that macOS dependency.
  Relevant iOS, watch, Xcode project, configuration, and build-tooling changes
  then enter `.github/workflows/ios-build-and-test.yml`. Its macOS jobs compile
  both shared test bundles, execute the complete `merianTests` target, run the
  deterministic queued-scan completion UI smoke, and create an unsigned Release
  archive from the exact workflow SHA using only `Package.resolved` versions.
  Repository rules must require
  `iOS Build and Test / Production readiness`; do not require the conditional
  macOS jobs or replace the pull-request trigger with workflow-level path
  filters. The remainder of the UI suite, signed distribution, and physical
  hardware checks remain separate gates.
- **Supabase Functions and Tooling**: You must write and validate code natively
  using Deno testing frameworks. Before opening a PR targeting
  `services/supabase`, run:
  ```bash
  deno fmt --check services/supabase/functions services/supabase/scripts
  deno lint --config services/supabase/functions/deno.json \
    services/supabase/functions services/supabase/scripts
  make test-supabase-tooling
  (cd services/supabase/functions && deno task test)
  ```
  `services/supabase/functions/deno.json` owns reviewed dependency pins. Each
  deployable function has a generated local `deno.json` that uses the shared
  frozen `dependencies.lock`, matching the config Supabase discovers while
  building that function. From the repository root, validate and type-check
  that exact graph:
  ```bash
  deno run --allow-read=services/supabase \
    services/supabase/scripts/sync_function_deno_configs.ts --check
  deno run --allow-read=services/supabase \
    services/supabase/scripts/validate_function_dependencies.ts
  deno check --frozen \
    --config services/supabase/functions/<function>/deno.json \
    services/supabase/functions/<function>/index.ts
  ```
  `test_supabase_tooling.sh` discovers every standard script source and
  `_test.ts` file, including the ghost-user audit and cleanup suites, rather
  than maintaining a selected list. It also runs the isolated Identify DTO
  validator and every shell-tooling test. The planner test compares the
  complete `[functions.<name>]` set in `config.toml` with the complete set of
  discoverable function graphs. Add or retire the reported route correctly; do
  not maintain a numeric fleet-size assertion.
  New deployed functions should call `Deno.serve(...)` directly and avoid
  direct runtime URL/npm/JSR imports; route packages through the root manifest,
  regenerate function-local configs, and use local shared helpers such as
  `_shared/encoding.ts` where available. The fleet uses one exact Supabase SDK.
  Keep `_shared/claimsAuth.ts` out of `_shared/edgeHandler.ts` because claims
  verification is an opt-in route policy, not because it uses another SDK.
- **Internal Admin**: Before opening a pull request that changes `apps/admin`,
  and before deploying it, run the complete frozen production gate:
  ```bash
  cd apps/admin
  npm ci
  npm run audit:dependencies
  npm test
  npm run typecheck
  npm run build
  ```
  `Naturebook Admin Quality / test` reports for every pull request so it can be
  required by the repository ruleset. The separate admin Vercel project must
  add that GitHub Action as a required Deployment Check and hold production
  promotion until the exact commit passes. Never add a service-role/secret key,
  direct database URL, provider credential, computed `process.env` access, or
  whole-object environment access to this browser-facing project.
- **Database migrations**: Run `make validate-supabase-migrations` before a
  local reset or deployment. Migration SQL must be replayable by
  `supabase db start`; do not check in concurrent index DDL. For a
  zero-downtime index on a populated production table, follow the supervised
  pre-deploy procedure in the Supabase deployment runbook and keep an
  idempotent ordinary index statement for clean environments.
- **Destructive queues and migrations**: Before making historical rows newly
  actionable, audit their provenance and prove the SQL claim derives authority
  from the current durable workflow—not queue age/status alone. Add a live-owner
  veto test, an owner-isolation canary, aggregate post-deploy invariants, and a
  recovery/rollback contract. Incident documentation must separately report
  repository mitigation, production deployment, runtime verification, and data
  recovery.

## Submitting a Pull Request 🚀

1.  Fork the repository and create your feature branch: `git checkout -b feature/my-amazing-feature`.
2.  Format your code. Swift code must naturally adhere to Apple's general styling limits. TypeScript should be linted natively before committing.
3.  Commit your changes following standard imperative structures.
4.  Update docs and release notes for user-facing work. Use `CHANGELOG.md` for TestFlight/App Store/support notes and `apps/ios/Merian/Resources/Changelog/changelog.json` for curated in-app Settings notes. See [`docs/development-guides/12-in-app-changelog.md`](./development-guides/12-in-app-changelog.md).
5.  Push to the branch locally.
6.  Open a Pull Request describing the changes, explicitly mentioning if you changed any core network layer boundaries or AVFoundation settings.

We look forward to building this amazing open ecosystem with you!
