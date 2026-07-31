# iOS Release Versioning and TestFlight Publishing

Naturebook has one supported path for a distributable iOS build: manually
dispatch **iOS TestFlight Publisher** in GitHub Actions. Xcode Organizer,
`agvtool`, tracked release-prep commits, Fastlane beta lanes, and separate
“export the newest archive” operations are not release procedures.

The current release train is tracked as `MARKETING_VERSION: 1.0.3` in
`project.yml`. Change that value in an ordinary reviewed pull request only when
starting a new public version train. `CURRENT_PROJECT_VERSION` in that file is
a repository floor used by development and validation builds; it is not edited
for each beta candidate. The publisher injects the allocated build at archive
time into the app, Explore widget, Messages extension, and watch app.

Apple associates an upload with the bundle ID, marketing version, and build
number. Naturebook deliberately uses a globally increasing build number across
marketing versions. See Apple's current
[build upload guidance](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/).

The stable design and trust-boundary rationale live in the
[iOS release publisher architecture](../system-architecture/09-ios-release-publisher.md).
This document is the operator source of truth.

## Contract at a Glance

| Concern | Repository policy |
|---|---|
| Marketing version | Reviewed `MARKETING_VERSION` release train in `project.yml` |
| Development build | Tracked `CURRENT_PROJECT_VERSION` floor; no per-beta commits |
| Distribution build | Next global number allocated by the serialized publisher |
| Source | Clean, protected `main` HEAD that passed the exact-SHA compiled gate |
| Archive | One signed archive invocation per allocated build |
| Export | `manageAppVersionAndBuildNumber=false`; Xcode may not renumber |
| Evidence | Source fingerprint, archive identity, IPA SHA-256, tags, and receipt |
| Failed archive | Keep the reservation and allocate a higher build next time |
| Upload retry | Same hash-verified IPA, only after App Store Connect says `Failed` |
| Promotion | One processed binary through internal/external TestFlight and App Review |

Gaps in the global build sequence are expected. Reusing an identity for rebuilt
or changed bytes is forbidden. Promotion uses the same processed binary through
internal TestFlight, external TestFlight, and App Review.

## One-Time Repository and Apple Setup

A repository administrator and release manager must complete this setup before
the first live candidate and repeat the verification after changing repository
rules, Apple credentials, signing assets, or the publisher workflow.

### Protected Main and Required CI

Protect `main` and require exactly this stable check for pull requests and the
merge queue:

```text
iOS Build and Test / Production readiness
```

Do not require the conditional macOS jobs individually. They correctly report
as skipped when an unrelated pull request needs only the stable final decision.
The full setup and verification procedure is in
[Repository Rule Setup](./08-testing-strategy.md#repository-rule-setup).

The repository or organization Actions policy must allow the publisher's
declared `actions: read` and `contents: write` permissions. Keep the workflow
manual-only and preserve its global `ios-testflight-publisher` concurrency
group with `cancel-in-progress: false`.

### Immutable Release Tags

Configure repository tag rules for all three namespaces:

```text
ios-build-allocations/*
ios-builds/*
ios-uploads/*
```

The policy must allow the publisher to create a new tag, but prevent ordinary
updates, force-pushes, and deletions. Do not grant a broad bypass that lets a
second automation or routine maintainer rewrite release history. Losing an
allocation tag can make an archived-but-never-uploaded build appear reusable.

The namespaces have separate purposes:

| Namespace | Type | Meaning |
|---|---|---|
| `ios-build-allocations/<build>` | Lightweight | Global number was reserved before archive |
| `ios-builds/<version>-<build>` | Annotated | Signed candidate maps to source/archive/IPA identity |
| `ios-uploads/<version>-<build>` | Annotated | Transporter succeeded for that exact IPA |

Never delete a reservation because a build failed. That gap is the durable
record that the number must not be selected again.

### Apple and GitHub Credentials

Create an App Store Connect API key with the least privilege that can inspect
builds and upload this app. Retain its issuer ID, key ID, and original `.p8`
file in the approved credential manager. Export an active Apple Distribution
certificate together with its private key as a password-protected `.p12`.
Confirm the explicit App ID `app.merian.Merian` and its required capabilities
exist for the permanent Merian bundle identity.

Configure these GitHub Actions secrets:

| Secret | Required value |
|---|---|
| `ASC_APP_ID` | Numeric Apple ID for the existing App Store Connect app |
| `ASC_TEAM_ID` | Ten-character Apple Developer team ID |
| `ASC_KEY_ID` | App Store Connect API key ID |
| `ASC_ISSUER_ID` | App Store Connect issuer UUID |
| `ASC_PRIVATE_KEY_P8_BASE64` | Base64 of the original API private-key bytes |
| `IOS_DISTRIBUTION_CERTIFICATE_P12_BASE64` | Base64 of the distribution certificate and private key |
| `IOS_DISTRIBUTION_CERTIFICATE_PASSWORD` | Password protecting that `.p12` |

Candidate creation requires all seven values. Existing-candidate upload modes
do not import the distribution certificate, but they still need the App Store
Connect values. The workflow writes credentials only to runner-temporary files,
does not echo them, unsets inherited secret values before repository code runs,
and removes the files and temporary keychain on exit.

The tracked Release configuration must resolve the production RevenueCat iOS
SDK key beginning with `appl_`. The publisher rejects a Test Store key or a
placeholder. Apple signing and App Store Connect credentials are server-side CI
secrets; do not add them to tracked or local app-facing `.xcconfig` files.

### Setup Verification

Run the portable release contracts from a clean checkout:

```bash
make validate-ios-project
make validate-ios-versioning
make test-ios-ci-tooling
```

Then manually dispatch **iOS TestFlight Publisher** on `main` with action
`plan` and a numeric `latest_asc_build`. Verify it creates only the 30-day plan
artifact described below and creates no release tags. Do not use a live
candidate as a setup probe.

## Version and Build Policy

### Marketing-Version Trains

`MARKETING_VERSION` is the customer-visible semantic version. Keep it unchanged
for every beta in one public train. Use a patch train for compatible fixes, a
minor train for a planned customer-facing feature release, and a major train
only for an intentional compatibility/product transition. Do not put beta or
release-candidate suffixes in `MARKETING_VERSION`; TestFlight stage and the
globally increasing integer build identify prerelease iterations.

To start a new train:

1. Open a normal pull request that changes `MARKETING_VERSION` in `project.yml`.
2. Do not reset or lower `CURRENT_PROJECT_VERSION`.
3. Add the new reviewed source under `apps/ios/AppStore/ReleaseNotes/` and update
   `CHANGELOG.md`; update the bundled in-app changelog when appropriate.
4. Run `make xcodegen` and commit the generated project update.
5. Run the project, versioning, and publisher contract checks.
6. Merge normally and wait for compiled CI on the final exact `main` SHA.
7. Let the publisher allocate the next global build for the new train.

Changing only the marketing version does not authorize a build-number reset.
Raise the tracked build floor only in a reviewed exceptional change that must
skip a known range; never use floor changes as routine beta increments.

### Global Build Allocation

The workflow has the global concurrency group `ios-testflight-publisher` with
`cancel-in-progress: false`. The publisher also takes a local atomic lock.
Together these prevent overlapping writers in the supported workflow.

Immediately before the sole distributable archive, the publisher computes:

```text
tracked floor       = CURRENT_PROJECT_VERSION in project.yml
tag floor           = highest ios-build-allocations/<number> tag
repository baseline = max(tracked floor, tag floor)
next build          = max(App Store Connect latest, repository baseline) + 1
```

App Store Connect cannot know about an archive that failed before upload, so
the durable tag floor is required. The workflow pushes
`ios-build-allocations/<next build>` before invoking `xcodebuild archive`. If
the archive, export, or evidence publication fails, that reservation remains
and creates an allowed gap. A later attempt receives a new number.

There is no manual `BUILD=N` live override. Candidate and upload modes reject
an operator-supplied App Store Connect maximum and query the service directly.
A collision while pushing the reservation—including Git reporting an
equal-value ref as already up to date—fails before archive begins.

## Daily Development and CI

Debug builds, unit tests, pull requests, and unsigned validation archives use
the tracked baseline and never query App Store Connect, reserve an allocation,
or consume a build number.

```bash
make xcodegen
make validate-ios-versioning
make test-ios-versioning
make test-ios-publisher-workflow
```

`.github/workflows/ios-build-and-test.yml` passes
`MERIAN_IOS_VALIDATION_ARCHIVE=1` to its unsigned Release archive. The archive
preflight requires the exact `GITHUB_SHA`, a clean checkout, and the unchanged
tracked version/build. It also requires signing to be disabled with no identity
or team, so that flag cannot authorize a signed publisher archive.

Before a new candidate is allowed, the publisher finds a successful **iOS
Build and Test** run for the exact selected SHA and verifies these jobs all
succeeded:

1. `Full iOS unit tests`
2. `Current-SHA Release archive`
3. `Production readiness`

A green parent, a byte-similar checkout, or an out-of-scope run is not enough.
Manually dispatch **iOS Build and Test** on the intended ref first when needed.
The publisher itself is not a required pull-request check and must never run
automatically.

## Read-Only Planning

Use the latest global build shown in App Store Connect as a read-only anchor:

```bash
make plan-ios-beta LATEST_ASC_BUILD=275
```

The command writes an ignored JSON plan under `build/ios-publisher/plans/`. It
does not create or push a Git tag, change source, archive, export, sign, or
upload. The plan shows the tentative allocation, source revision and
fingerprint, single-archive intent, immutable export setting, IPA validation,
and same-binary promotion policy.

The GitHub workflow's `plan` action has the same no-write contract and retains:

```text
ios-beta-publisher-plan-<run_id>-attempt-<attempt>
```

for 30 days. Plan mode accepts an operator-supplied App Store Connect value
because it has no external side effects. It is a point-in-time estimate, not a
reservation, and can become stale as soon as another build is allocated or
accepted.

## Publisher Actions and Authorization

Dispatch `.github/workflows/ios-testflight-publisher.yml` from protected
`main`. Every action rejects other refs and requires the checkout, selected
`origin/main`, and workflow SHA to be identical. In practice, publish the
current protected `main` HEAD; do not attempt to publish a historical commit or
a branch-modified workflow.

| Action | Result | Required inputs |
|---|---|---|
| `plan` | Read-only allocation-to-upload plan | Numeric `latest_asc_build` |
| `candidate` | Reserve, archive once, export, and retain; no upload | `external_state_confirmation` = `RESERVE BUILD` |
| `upload` | Create a new candidate and upload its exact IPA | `RESERVE BUILD` and `UPLOAD TO APP STORE CONNECT` confirmations |
| `upload-existing` | Upload a retained untouched candidate without rebuilding | Source run, exact artifact name, and upload confirmation |
| `retry-upload` | Retry an attempted identical IPA after definitive failure | Source run, exact artifact name, upload confirmation, and `FAILED CONFIRMED` |

Leave inputs unrelated to the selected action blank. Candidate and upload
actions create durable Git refs, so they require explicit external-state
authorization. Upload actions additionally require a separate unmistakable
upload confirmation. Never add a `push`, `pull_request`, `merge_group`,
schedule, or reusable-workflow trigger to this publisher.

## Routine Candidate Procedure

### Before Dispatch

1. Confirm the intended commit is the current protected `main` HEAD.
2. Confirm **iOS Build and Test** succeeded on that exact SHA and ran both macOS
   jobs rather than reporting a scope-only success.
3. Review `CHANGELOG.md`, the current App Store release-note source, product
   metadata, privacy/export-compliance answers, and stage-specific QA gates.
4. Confirm no publisher run is active or queued. Do not cancel an older run to
   make a newer run start sooner.
5. Confirm Apple credentials, the distribution certificate, provisioning
   capabilities, and production RevenueCat configuration are current.

### Create and Retain a Candidate

Use `candidate` when the release manager wants to inspect and preserve a signed
binary before authorizing an upload:

1. Open **Actions → iOS TestFlight Publisher → Run workflow**.
2. Select branch `main` and action `candidate`.
3. Enter `RESERVE BUILD` in `external_state_confirmation`.
4. Leave upload, failed-upload, source-run, artifact, and plan inputs blank.
5. Dispatch once and wait for a terminal result.

A successful run retains this 90-day artifact:

```text
ios-beta-candidate-<run_id>-attempt-<attempt>
```

It contains exactly one `evidence.json` and one exported IPA. It does not have
an upload receipt. Record the run URL, run ID, artifact name, version/build,
source SHA, source fingerprint, archive identity, and IPA SHA-256 in the release
record.

### Create and Upload Directly

Use `upload` only when the same dispatch is already authorized to reserve and
send a new candidate:

1. Select action `upload` on branch `main`.
2. Enter `RESERVE BUILD` in `external_state_confirmation`.
3. Enter `UPLOAD TO APP STORE CONNECT` in `upload_confirmation`.
4. Leave source-run, artifact, failed-upload, and plan inputs blank.
5. Dispatch once. Do not start another run while Transporter or App Store
   Connect status is unresolved.

The output uses the same candidate artifact name. Its evidence status is
`uploaded` only after Transporter succeeds and the durable upload receipt is
recorded.

### Upload a Retained Candidate

To upload a successful untouched `candidate` later:

1. Copy the numeric run ID and exact
   `ios-beta-candidate-<run_id>-attempt-<attempt>` artifact name from the source
   publisher run.
2. Select action `upload-existing` on branch `main`.
3. Set `source_run_id` and `candidate_artifact_name` to those exact values.
4. Enter `UPLOAD TO APP STORE CONNECT` in `upload_confirmation`.
5. Leave `external_state_confirmation`, `latest_asc_build`, and
   `failed_upload_confirmation` blank.

The workflow downloads the retained files, verifies the annotated evidence tag
and IPA hash, revalidates the signed IPA, and invokes Transporter without
archiving or exporting again.

## Archive, Export, and Evidence

The publisher never edits or regenerates the checkout after CI proof, so it has
no runtime XcodeGen dependency. It archives from a clean exact Git SHA using
the reviewed generated project and passes
`CURRENT_PROJECT_VERSION=<allocated build>` as an Xcode build-setting override.
The shared settings and plist inheritance inject one marketing version and
build into all four shipped components.

The Release preflight rejects a distributable archive unless publisher mode,
the workflow concurrency assertion, exact source SHA, source fingerprint,
tracked marketing version, allocated build, and production RevenueCat config
all agree. Manual Organizer and ad-hoc Release archives fail here.

The archive receives these processed `Info.plist` values:

- `MERIAN_SOURCE_REVISION`: exact source commit
- `MERIAN_SOURCE_FINGERPRINT`: exact nonignored source snapshot
- `MERIAN_SOURCE_STATE`: `clean`

After the one archive invocation, validation checks the main app, widget,
Messages extension, watch app, bundle ID, source fields, and version/build. A
content manifest over every archive path, mode, symlink target, and file digest
produces `archive_identity`. Export verifies that identity before and after
`xcodebuild -exportArchive` so a changed archive is rejected.

The generated export options always contain:

```xml
<key>manageAppVersionAndBuildNumber</key>
<false/>
```

IPA validation reopens the ZIP, requires one root app, rejects duplicate
entries, verifies all embedded component versions/builds and main-app source
provenance, and hashes the IPA before and after inspection. Only the stable
final `ipa_sha256` is accepted.

### Evidence Fields

Each candidate's `evidence.json` records:

| Field | Required meaning |
|---|---|
| `status` | `candidate`, `upload_attempted`, or `uploaded` |
| `version` and `build` | App Store Connect identity |
| `source_revision` | Exact protected source SHA |
| `source_fingerprint` and `source_state` | Complete nonignored snapshot and `clean` state |
| `green_workflow_run_id` | Exact-SHA compiled assurance run |
| `archive_identity` and `archive_invocations` | Content identity and the value `1` |
| `ipa_sha256` | Stable final signed IPA identity |
| `manageAppVersionAndBuildNumber` | The value `false` |
| `allocation_tag` and `evidence_tag` | Durable repository identities |
| `retry_policy` and `promotion_policy` | Identical-IPA retry and same-binary promotion rules |
| Upload timestamps/receipt hash | Present after an upload attempt or success as applicable |

The complete mapping is:

```text
marketing version + allocated build
    -> source SHA + source fingerprint + clean state
    -> exact-SHA compiled CI run
    -> archive identity (one archive invocation)
    -> final IPA SHA-256
    -> Transporter receipt hash after successful upload
```

### Artifact Chain and Retention

| Artifact | Retention | Use |
|---|---:|---|
| `ios-beta-publisher-plan-<run>-attempt-<attempt>` | 30 days | Read-only plan; never a reservation |
| `ios-beta-candidate-<run>-attempt-<attempt>` | 90 days | New candidate IPA/evidence and optional direct-upload log |
| `ios-beta-upload-receipt-<run>-attempt-<attempt>` | 90 days | Existing-candidate attempt, updated evidence, exact IPA, and log |

Immediately before any existing-candidate Transporter call, the publisher
changes the downloaded evidence status to `upload_attempted`. The source
candidate artifact remains immutable. Therefore, if an attempt fails, the
receipt artifact from that attempt—not the original candidate artifact—is the
source for a possible authorized retry. Always use that run and artifact as the
source for any authorized retry.

Copy the exact IPA, evidence, receipt log, run URL, and artifact name to the
approved release artifact store when the release record must outlive GitHub's
90-day retention. Preserve bytes and filenames; verify the IPA hash after the
copy. The current workflow still requires a source Actions run and artifact for
`upload-existing` or `retry-upload`. If it has expired, allocate a new candidate
unless a separately reviewed tooling change restores the evidence-verified
artifact path.

### Verify Downloaded Evidence

After downloading and expanding the artifact into a dedicated directory:

```bash
RELEASE_EVIDENCE=/path/to/evidence.json
RELEASE_IPA=/path/to/Naturebook.ipa
jq '{status, version, build, source_revision, source_fingerprint, green_workflow_run_id, archive_identity, archive_invocations, ipa_sha256, allocation_tag, evidence_tag}' "$RELEASE_EVIDENCE"
EXPECTED_IPA_SHA="$(jq -r '.ipa_sha256' "$RELEASE_EVIDENCE")"
ACTUAL_IPA_SHA="$(shasum -a 256 "$RELEASE_IPA" | awk 'NR == 1 { print $1 }')"
test "$ACTUAL_IPA_SHA" = "$EXPECTED_IPA_SHA"
```

Fetch and inspect the immutable mappings without changing them:

```bash
git fetch --tags
RELEASE_VERSION="$(jq -r '.version' "$RELEASE_EVIDENCE")"
RELEASE_BUILD="$(jq -r '.build' "$RELEASE_EVIDENCE")"
git show "ios-builds/${RELEASE_VERSION}-${RELEASE_BUILD}"
git for-each-ref --format='%(contents)' "refs/tags/ios-builds/${RELEASE_VERSION}-${RELEASE_BUILD}"
```

After a successful upload, inspect
`ios-uploads/${RELEASE_VERSION}-${RELEASE_BUILD}` the same way and confirm App
Store Connect shows the identical version/build. The upload tag means
Transporter returned success; App Store Connect processing and release
acceptance remain separate gates.

## Retry Decision Procedure

Gaps are harmless and expected. Identity reuse is not.

| Situation | Required action |
|---|---|
| Archive/export/validation failed after reservation | Keep the reservation; run a new candidate and allocate a higher build |
| Upload outcome unknown, processing, or missing from the UI | Do not retry or rebuild; determine App Store Connect status |
| App Store Connect definitively reports upload `Failed` | `retry-upload` may send the evidence-verified identical IPA |
| Candidate was deliberately created without upload | `upload-existing` sends that retained IPA |
| Transporter succeeded but durable upload-tag publication failed | Treat the build as consumed; open an incident and reconcile evidence—do not upload again |
| Any source, dependency, build configuration, signing/export configuration, or rebuilt bytes differ | Allocate a new build and archive once again |
| Tester group or release stage changes | Select/promote the already uploaded build; do not rebuild |

For a definitive App Store Connect `Failed` result:

1. Open the failed `upload-existing`, `retry-upload`, or direct `upload` run.
2. Use its retained artifact containing evidence with status
   `upload_attempted`, the exact IPA, and the attempt log. A direct `upload` run
   retains those files under its candidate artifact name; an existing upload
   retains them under its upload-receipt artifact name.
3. Confirm App Store Connect—not only a local Transporter exit—shows `Failed`.
4. Dispatch `retry-upload` with that run ID and exact artifact name.
5. Enter `UPLOAD TO APP STORE CONNECT` and `FAILED CONFIRMED`.
6. Leave reservation and plan inputs blank.

The retry rechecks the evidence tag, IPA SHA-256, and signed IPA metadata. It
never reserves, archives, or exports. If the bytes are unavailable or any hash
differs, do not reconstruct the IPA; create a higher build.

## TestFlight and App Review Promotion

Once App Store Connect finishes processing, verify the displayed version/build
matches `evidence.json` and the immutable tags. Then move one binary through
the stages:

1. Complete export-compliance and beta metadata for the processed build.
2. Select that build for the approved internal TestFlight group.
3. Run the physical-device smoke matrix and record device/OS/build results.
4. Add the same processed build to external TestFlight when ready; submit that
   build for Beta App Review when Apple requires it.
5. After beta acceptance, select that same build for the App Store version and
   App Review.

No promotion stage gets a new archive or IPA. A code, dependency,
configuration, entitlement, or signing change is a new candidate with a higher
global build. Apple's current
[TestFlight overview](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/)
documents tester and beta-review behavior.

Before broad distribution, retain:

- publisher run URL and exact-SHA green CI run URL;
- candidate/upload artifact names and their retention deadline;
- version/build, source SHA, source fingerprint, and archive identity;
- final IPA SHA-256 and upload receipt-log SHA-256;
- allocation, evidence, and upload tag names;
- App Store Connect processing/acceptance observation;
- internal/external tester groups and Beta App Review status;
- physical-device, purchase/restore, push, and critical scan-flow evidence.

## Signing and Product Gates

The publisher proves artifact identity; it does not replace release acceptance.
Before distributing broadly:

1. Confirm the explicit App ID `app.merian.Merian` has required capabilities.
2. Inspect the retained signed IPA's app entitlements and require production
   APS. Expand the already validated IPA into a dedicated temporary directory:

   ```bash
   RELEASE_IPA=/path/to/Naturebook.ipa
   SIGNING_CHECK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/naturebook-signing.XXXXXX")"
   ditto -x -k "$RELEASE_IPA" "$SIGNING_CHECK_DIR"
   codesign -d --entitlements - \
     "$SIGNING_CHECK_DIR/Payload/Merian.app"
   ```

   Record the reviewed values, then discard the temporary expansion without
   retaining profiles or unrelated signed metadata in release notes.

3. Open the production paywall and verify RevenueCat's current offering maps
   both `pro_week` and `pro_annual` to App Store Connect products.
4. Complete purchase, restore, webhook, push-notification, camera, microphone,
   offline replay, and critical scan-flow smoke tests appropriate to the stage.
5. Confirm no Debug-only UI-test seed marker or free-scan override is present.

Simulator StoreKit or RevenueCat Test Store success does not replace the
TestFlight sandbox and webhook checks. Follow
[`02-revenue-and-identity.md`](../features-and-hardware/02-revenue-and-identity.md)
and the
[RevenueCat webhook release gate](../backend-and-data/06-supabase-deployment-runbook.md#revenuecat-webhook-release-gate).

## Failure Triage

| Failure | Operator response |
|---|---|
| No successful exact-SHA iOS run | Manually dispatch **iOS Build and Test** on final `main`; do not bypass the gate |
| Publisher rejects the ref/SHA | Merge through protected `main` and publish its current HEAD |
| Another publisher holds the lock or concurrency slot | Wait for its terminal result; do not delete locks or cancel to overlap writers |
| App Store Connect lookup/authentication fails before reservation | Correct or rotate credentials, rerun a read-only plan, then dispatch again |
| Allocation push collides | Treat the other reservation as authoritative and dispatch again for a recalculated higher build |
| Archive fails after reservation | Preserve logs and the tag; fix source/tooling and create a new higher candidate |
| Archive or IPA identity validation fails | Quarantine the output; never upload, patch, rename, or relabel it |
| Evidence-tag push fails | Do not upload the candidate; preserve artifacts, investigate tag policy, and allocate a higher candidate |
| Transporter exits unsuccessfully | Preserve the receipt artifact and determine App Store Connect state before deciding on retry |
| Transporter succeeds but upload-tag push fails | Treat the upload as consumed; preserve logs and open an evidence-reconciliation incident |
| App Store Connect remains processing | Wait and monitor; processing delay is not definitive failure |
| Artifact approaches expiry | Copy it to the approved release store and record the verified hash before expiry |
| Any immutable release tag is missing or mutated | Freeze publishing, preserve remote/local evidence, and open an incident |

An upload with unknown status is treated as consumed until App Store Connect
proves it failed. A failed runner or missing UI refresh is not enough to assert
`FAILED CONFIRMED`.

## Emergency Stop and Recovery

When release identity, credentials, or repository rules are suspect:

1. Stop new publisher dispatches and preserve the active run's logs/artifacts.
2. Cancel a live run only when continued external effects are riskier than an
   incomplete run. If a reservation may already exist, keep it permanently.
3. Revoke or rotate the App Store Connect key and distribution certificate when
   compromise is possible; do not expose them for local recovery.
4. Disable the publisher workflow temporarily if dispatch must be prevented.
5. Preserve all allocation/evidence/upload tags and App Store Connect records.
6. Open an incident that separately records repository remediation, Apple-side
   state, evidence reconciliation, and production/tester recovery.
7. Re-enable only after reviewed remediation, portable contracts, exact-SHA CI,
   and a read-only plan succeed.

Never “roll back” by deleting a tag, lowering the tracked floor, reusing a build
number, or rebuilding an old IPA. Removing a beta from tester access or pausing
a release is an App Store Connect action; corrected bytes still require a new
globally higher candidate.

## Naturebook Apple Distribution Metadata Gate

For the public rebrand release, update the existing app listing; do not create a
new App Store Connect app record or bundle identifier. In Apple Developer
Certificates, Identifiers & Profiles, ensure there is exactly one explicit App
ID for `app.merian.Merian`, with description `Naturebook iOS (Merian)`.

Confirm these App Store Connect values before submitting:

| Field | Required value |
|---|---|
| Public app name | Naturebook |
| Bundle ID | `app.merian.Merian` |
| Primary category | Reference |
| Secondary category | Education |
| Marketing URL | `https://naturebook.earth` |
| Support URL | `https://naturebook.earth/support` |
| Privacy policy URL | `https://naturebook.earth/privacy` |
| Subscription/IAP localization | Naturebook Pro |

Do not change product IDs, entitlement IDs, RevenueCat offering identifiers,
or the App Store Connect app record. Use
[`15-naturebook-rebrand-rollout.md`](./15-naturebook-rebrand-rollout.md) as the
release checklist and
[`08-public-brand-compatibility.md`](../system-architecture/08-public-brand-compatibility.md)
as the permanent identifier contract.

## Documentation and Change Ownership

Any pull request that changes release policy, workflow inputs, evidence fields,
tag namespaces, artifact names, retention, signing, export, or retry behavior
must update all affected documentation and tests in the same change:

| Source | Ownership |
|---|---|
| `project.yml` | Reviewed marketing train and development build floor |
| `.github/workflows/ios-testflight-publisher.yml` | Sole manual distribution entry point and permissions |
| `scripts/publish-ios-beta.sh` and validators | Allocation, archive/export, identity, upload, and retry enforcement |
| This runbook | Canonical operator procedure |
| `09-ios-release-publisher.md` | Stable architecture and trust boundaries |
| `08-testing-strategy.md` | CI and portable contract coverage |
| `CHANGELOG.md` | Human release, QA, support, and TestFlight history |
| `apps/ios/AppStore/ReleaseNotes/<version>.md` | Reviewed App Store metadata source |
| `changelog.json` | Curated in-app customer notes |
| `docs/incidents/` | Failures, evidence limits, remediation, and closure gates |

Run at minimum:

```bash
make test-ios-ci-tooling
make validate-ios-versioning
git diff --check
```

The agent entry at `apps/ios/.agents/workflows/deploy_testflight.md` is only a
pointer into this source of truth. It must not grow an independent deployment
procedure.
