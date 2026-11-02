## November 2 — CPM verification and admission consuming boundary

Status: storage preparation and private durable verification start are
implemented with narrow local qualification. A private verification-to-admission
coordinator and JPEG/still-PNG/still-WebP/HEVC-still-item consuming verifier
increments are implemented but uninstalled. Remaining HEIF forms and the atomic
admission bridge remain unimplemented and inactive. This amendment applies the
current CPM assignment to the existing
[S0/IC-1 owners](initial-completion-history-interface-2026-10-11.md#2-minimum-dependency-s0-and-checkpoint-boundary).
It does not qualify the initial submission journey or change release controls.

The first coding checkpoint extends the existing staging and receipt composites
with a closed `server_prepared_v3` / `client_prepared_photo_v1` discriminator
and bounded verification, retained-role, capacity-predecessor and
original-deadline fields. The legacy receipt constructor explicitly fills its
discriminator before whole-row insertion. Existing canonical proof bytes,
required legacy fields, receipt-proof constraints and transaction witnesses
remain intact: the CPM branch still cannot be stored. The shape helper confers
no verification or funding authority. See the
[storage migration](../../services/supabase/migrations/20261102100657_prepare_initial_cpm_admission_storage.sql)
and
[shape tests](../../services/supabase/tests/initial_cpm_admission_storage.sql).

Local checkpoint evidence covers 554 static migration tests and three selected
database catalogs (1,213 assertions), plus one committed legacy admission on the
502-migration baseline upgraded to 503 migrations. Its original receipt, legacy
row, fixed-time handoff and funding hashes remained equal; retained recovery and
committed C1 cancellation passed after upgrade. Evidence is retained under
`.artifacts/native-app-capture-handoff-20261020/cpm-admission-storage01/` and
`cpm-admission-upgrade01/`. This is narrow storage/legacy compatibility
evidence, not a full catalog, concurrency, verifier, CPM admission or native
journey gate.

The existing inactive `cpmPhotoWriteObservation.ts` read owner now hashes each
chunk synchronously with incremental SHA-256, before requesting the next chunk.
It no longer retains the full chunk list or allocates an aggregate media buffer.
Its original role byte limits, 4,096-chunk and 32-consecutive-empty limits,
single GET, deadline/cancellation behavior and final lifecycle recheck remain
unchanged. This uses the characterization's incremental hash mechanism without
installing its test runtime or replaying the completed GAC-1 campaign. It proves
neither structural admissibility nor physical cancellation settlement; no
whole-worker memory/CPU qualification or admission authority follows.

The inactive
[verification-start migration](../../services/supabase/migrations/20261102113843_prepare_initial_cpm_verification_start.sql)
adds one attempt identity, start time and snapshot digest to the existing
intent. The fixed begin routine owns account/deletion/scan serialization, then
capacity, registry and attempt locks. It requires the complete saved cohort with
positive live write closures. A protected transaction-bound context authorizes
exactly one intent update; the row guard consumes it before nested work and
independently checks the cohort, absence of funding and current eligibility. No
API role can insert that context. It must be consumed before commit, and its
constraint must remain deferred while begin runs; immediate constraints fail
closed.

Snapshots and intent-image digests normalize timestamps to UTC microseconds.
Only the first committed start may return a fresh acknowledgement. Repeated or
uncertain starts remain held without renewed read authority, even after the
original deadline. The coordinator must wait for commit before media I/O; no SQL
lock spans a GET. This start state is neither a byte-verification result nor an
admission receipt. There is no public grant, installed verifier or new funding
path. Source review cleared timestamp and raw/nested writer corrections. Fresh
replay of 504 migrations and four focused catalogs passed 1,492 assertions. The
first six-schedule run passed 43 session commands, but review found that two
start-before-retirement schedules did not explicitly assert a fresh start. A
corrected run on another fresh owned replay passed all six schedules and 43
session commands with those assertions and an explicit no-admission invariant.
Separate-connection held recovery preserved the intent image. Both runs remain
retained with their distinct claims. See the
[focused catalog](../../services/supabase/tests/initial_cpm_photo_intents.sql).

A populated 503-to-504 upgrade passed 11 checks for one normally committed
legacy operation: its original intent fields, full receipt, fixed-time handoff
and funding hashes remained equal; actual retained recovery and public C1
cancellation committed afterward. Independent review verified source hashes and
disposal. This is narrow compatibility evidence, not physical transfer proof.

The
[expiry harness](../../services/supabase/scripts/test_initial_cpm_verification_expiry.py)
creates three closed cohorts normally, then coherently ages the linked saved
clocks and recomputes their dependent digests in one exclusive disposable-only
fixture transaction. Submitted content and identities remain equal; constraints
stay active and the three exact immutability triggers are restored and checked.
The initial setup failed because trigger restoration preceded the deferred
constraint flush. The corrected fresh run passed: committed-start recovery stays
held with an unchanged aged intent image; a structurally valid expired cohort
cannot start; status expiry retires the cohort and blocks later start/binding
without funding or losing retained-source liability. This proves recovery from
an aged committed fixture, not real elapsed-time behavior or byte equality with
the pre-aging acknowledgement. Evidence for both runs and the populated upgrade
is retained under `.artifacts/native-app-capture-handoff-20261020/` in
`cpm-verification-expiry01/`, `cpm-verification-expiry02/` and
`cpm-verification-upgrade01/`. The complete consuming journey remains open.

The private
[coordinator](../../services/supabase/functions/_shared/initialAnalysis/cpmPhotoAdmission.ts)
first reconciles the exact saved identity. Only conclusive absence permits one
begin attempt; only its fresh committed `started` acknowledgement permits one
complete-cohort verifier invocation. It validates the saved ordered snapshot and
closed verifier evidence before one admission attempt, then reconciles the
receipt. Unknown recovery, start, verification or admission never authorizes a
successor, repeated media read or automatic re-admission. A durable held start
on a later invocation cannot restart verification. Submitted candidate and
assignment strings are copied before the first await.

The coordinator reserves five seconds for receipt reconciliation within the
smaller of its managed 30-second aggregate budget and original admission window;
parent budgets remain authoritative. Retained admission can still be recovered
after that original window expires. Its
[injected tests](../../services/supabase/functions/_shared/initialAnalysis/cpmPhotoAdmission_test.ts)
exercise uncertainty, ordered evidence, caller cancellation, managed
work-deadline expiry, parent/window reserve refusal and near-deadline commit
recovery. They do not inspect physical media or prove resource release,
throughput, SQL atomicity or complete-cohort feasibility within that budget. The
verifier's structural boolean is trusted only from the fixed server composition
bound to the saved profile and build; it is never client proof. No route imports
this coordinator. Neither production bridge, public grant nor activation is
installed.

The private
[photo consuming adapter](../../services/supabase/functions/_shared/initialAnalysis/cpmPhotoVerification.ts)
now joins that coordinator to the existing exact-byte storage observation and
shared JPEG marker/table/scan, PNG chunk and WebP container inspectors. It
preflights every ordered role before storage I/O, resolves server-owned policy
by both saved profile and verifier-build digests, and checks the complete
cohort/account/deletion/retirement fences around the existing per-object checks.
One scratch buffer sized to the largest declared role (at most 32 MiB) is reused
serially and cleared on exit. The reader hashes and copies each chunk before
another read; shared-memory chunks are rejected. Only exact length/hash followed
by successful container inspection and final current checks can produce
complete-cohort evidence for the coordinator's one admission attempt. No partial
proof escapes.

Dimension bounds must come from the fixed server verifier catalog; no catalog or
profile is installed here. Existing public-photo and video-frame consumers
retain their 12 MiB/8192-edge/40-million-pixel defaults. CPM originals retain
their 32 MiB bound and use the explicit saved-build dimension policy. Private
metadata is preserved as opaque bounded segments, not decoded or certified safe
for public sharing. These checks frame JPEG entropy; they do not decode pixels
or establish client recipe execution. Synthetic one/two-photo and 32
MiB-original cases cover actual reader/parser composition, not provider traffic,
worker memory/CPU limits, physical cancellation settlement, SQL atomicity or
real-app feasibility.

The same inactive verifier owner now includes a trusted bootstrap catalog
constructor. It copies all supplied entries (at most sixteen) before its first
await, validates each nonsecret backend through the existing saved-source
backend decoder, and resolves only the exact saved profile digest, verifier
build digest, backend generation and backend configuration digest. Returned
metadata and all role dimensions are frozen. Duplicate tuples, conflicting
limits for one build, or multiple builds for one profile are rejected. No
current-selection fallback, remote flag or environment loader is provided.

This constructor consumes reviewed identities; it does not derive or certify an
executable-build digest, install SQL profiles or prove cross-deployment catalog
immutability. Those remain deployment-composition and qualification obligations.
Within the current coordinator, retained receipt recovery and held starts never
consult this catalog. A missing fresh tuple fails before media I/O and cannot
renew verification. The injected tests exercise this actual consumer ordering,
bootstrap/result mutation resistance and backend digest validation. They do not
qualify an installed policy, physical resources, SQL admission or app journeys.

The first JPEG increment is now extended in the same owner, renamed from
`cpmPhotoJpegVerification` to `cpmPhotoVerification`, to accept still-PNG
originals with JPEG-only AI/display derivatives. The shared
[PNG inspector](../../services/supabase/functions/_shared/analysisHistory/pngContainer.ts)
extracts the existing public-photo parser's signature, CRC, critical-chunk
order, palette/color/depth, dimensions, consecutive IDAT and zlib-header checks.
Its framing follows the [PNG specification](https://www.w3.org/TR/png-3/).
Unknown critical chunks and nonconforming chunk names are rejected. Private
ancillary chunks are retained as opaque CRC-checked payloads; their metadata
semantics and compressed contents are not decoded. Public-photo callers retain
their existing closed metadata policy and limits. This is neither complete
deflate/pixel validation nor metadata sanitization. APNG chunks are explicitly
held pending a qualified animation policy; still-image verification cannot
silently interpret them as a single photo.

Still-WebP originals now use the same consumer with JPEG-only derivatives. The
shared
[WebP inspector](../../services/supabase/functions/_shared/analysisHistory/webpContainer.ts)
extracts the existing video-frame RIFF/image-header checks while retaining that
caller's strict two-chunk, opaque-frame policy. Its explicit private-still
policy follows the
[WebP container specification](https://developers.google.com/speed/webp/docs/riff_container):
exact RIFF size and padding, at most 4096 chunks, one image, bounded matching
canvas/bitstream dimensions, ordered reconstruction chunks, declared metadata
presence and bounded alpha headers/raw lengths. Metadata and unknown payloads
remain opaque. Lossless alpha hints are not decoded-transparency proof.
Animation and scaled VP8 remain unqualified and are held. Neither compressed
alpha/entropy validity nor pixels, metadata semantics, sanitization or recipe
execution is established. Synthetic complete-cohort cases and existing native
WebP fixtures exercise this composition; they do not qualify worker resources or
real-app submission.

The same consumer now reads HEIC/HEIF originals through a bounded
[HEVC still-item inspector](../../services/supabase/functions/_shared/analysisHistory/heifContainer.ts).
It requires supported HEVC still brands, one identified primary `hvc1` or
single-level `grid` item, associated dimensions/configuration, bounded
item/property/reference counts, nonoverlapping self-contained `mdat`/`idat`
extents and codec/NAL header framing. It allows opaque Exif/XMP items and
bounded thumbnail/metadata references; it rejects external/protected items,
nested-derived/non-alpha auxiliary/sequence/other-codec forms and split
coded-image extents. Unknown properties and unsupported brands remain held.
Dimensions are declared `ispe` dimensions, not independently decoded SPS or
pixel dimensions; the pixel budget covers the sum of coded-item declarations.
This is not HEVC parameter-set/entropy/pixel validity, metadata semantics or
full HEIF qualification. Format field references are the
[HEIF item-location reference](https://github.com/nokiatech/heif/blob/master/srcs/common/itemlocationbox.cpp)
and
[HEVC configuration implementation](https://github.com/strukturag/libheif/blob/master/libheif/codecs/hevc_boxes.cc);
no native library or provider dependency is installed.

Synthetic single/two-photo cohorts cover narrow/wide item IDs, file/inline
locations, 64-bit bounds, opaque metadata, malformed links/properties/extents
and codec framing. Two frozen macOS 26.6.2 ImageIO fixtures now cover a 64×48
direct HEVC image (`iloc` v0) and a 1024×768 four-tile grid (`iloc` v1),
generated from deterministic nonpersonal RGB patterns and decoded locally back
to PNG at expected dimensions. The
[fixture generator](../../services/supabase/functions/_shared/analysisHistory/testing/generateHeifFixtures.py)
requires a fresh local output directory; test runs consume the
[frozen bytes and hashes](../../services/supabase/functions/_shared/analysisHistory/fixtures/heif-native-containers.json).
Repeated local generation matched these bytes; cross-OS/hardware byte identity
is not promised. Restricted encoding first failed with hardware-service access
errors; failed logs remain retained alongside successful authorized local runs.

Observed compatibility brands (`miaf`, `MiPr`, `MiHB`, `MiHE`), fixed-size
`clli` declarations and exactly one empty self-contained `dref`/`url` entry are
now accepted; this does not certify MIAF/HDR semantics. Single-level grid
validation binds descriptor size to `ispe`, distinct ordered `dimg` targets to
coded tiles, and tile counts/dimensions to canvas coverage without surplus
rows/columns. Tiles must share one configuration property and have no transform;
nested grids and broader tile-configuration/transform semantics remain held. The
[HEIF grid implementation reference](https://github.com/strukturag/libheif/blob/master/libheif/image-items/grid.cc)
provides the descriptor field layout. Every coded tile counts toward the same
pixel budget even when the output canvas is smaller. This is structural
validation, not decoded-pixel, codec-profile or recipe proof.

A subsequent local increment adds two ImageIO fixtures with deterministic alpha
ramps at the same dimensions: a separate direct alpha image and a separate alpha
grid. This brings the frozen corpus to four fixtures. The verifier permits one
hidden alpha image linked by `auxl` to the primary, with an essential `auxC`
property naming `urn:mpeg:hevc:2015:auxid:1`. Its dimensions and ordered
rotation/mirror declarations must match the primary. Alpha tiles are monochrome,
disjoint from primary tiles and count toward the same coded-pixel budget.
Codec-specific auxiliary subtype bytes remain opaque and bounded to 4096 bytes;
this is declaration/framing validation, not decoded-alpha proof. The
[auxiliary property implementation reference](https://github.com/strukturag/libheif/blob/master/libheif/box.cc)
describes the type string and trailing subtype layout. Other auxiliary types,
nested grids and unqualified configurations stay held. Positive synthetic
thumbnail relations cover narrow/wide item IDs and their additional resource
cost; orientation mutation cases cover matching quarter turns and rejection of
mismatched declarations, without claiming camera-orientation rendering coverage.

Camera `fileDataRepresentation()` and imported originals do not guarantee either
observed layout. Broader camera/import corpus, non-alpha auxiliary images, other
accepted forms and fixed profile decisions remain required before activation.
Unsupported forms are held after the once-only read, never retried
automatically. No conversion or reduced product vocabulary is implied. The
atomic admission bridge and coordinated retention/funding/C1 remain pending.

The next implementation increment couples actual complete-cohort verification
directly to a CPM-specific atomic admission branch. Allocation, successful
upload, `live_object` write closure and status `found` are individually
insufficient. The existing admission constructor requires assignment v3 and a
coherent server preparation outcome; CPM assignment v1 must not be relabeled to
satisfy it. Generic CPM admission denials stay in place outside the separately
validated branch. Reuse the original assignment, source registry, admission
ledger/seal, funding and cancellation owners, with no parallel engine or funding
path.

The admission coordinator now derives a prepared schema-2/binding-4 submission
projection after complete-cohort verification and before its one admission call.
`submission_canonical` is the exact saved `content_canonical` string, whose
inner content version remains 1. Its digest stays in the existing
`merian.initial-analysis.cpm-photo-content.v1` domain. `descriptions_canonical`
is the canonical ordered `contexts` array of `text_utf8_base64` objects, hashed
in the distinct `merian.initial-analysis.cpm-photo-contexts.v1` domain. Empty
arrays/entries, NUL, BOM, normalization and order remain distinct. All photo
roles and recipe provenance remain in the exact submission; this projection does
not certify recipe execution.

The private, ungranted
[SQL projection](../../services/supabase/migrations/20261102163622_prepare_initial_cpm_submission_projection.sql)
revalidates the saved candidate/assignment pair and derives the same fields. The
consuming coordinator and SQL share an independent synthetic fixture. These
version assignments reserve the CPM admission representation; no existing
submission constraint, legacy receipt proof, accepted reader or funding/C1 owner
accepts this branch yet. SQL admission must derive these fields from locked
saved rows and compare them with complete verified evidence, never trust a
caller-selected projection. The coherent stage/receipt/retention/funding/C1
implementation remains required before relaxing any legacy denial. No
activation, public grant, persistence or successful admission follows from this
pure helper.

The consuming implementation must establish these contracts together:

- Verification binds the saved candidate/content/assignment, the complete
  ordered source/AI/display cohort, exact immutable generations, full-byte
  length/hash/type, structural policy and verifier build, and irreversible write
  closure. Signature plausibility and byte equality do not prove structural
  admissibility. An outstanding upload must not replace verified bytes.
- Supporting text retains the existing `text_utf8_base64` representation through
  admission and completion. Decode only at prompt/native consumption; preserve
  empty entries, BOM, NUL and normalization distinctions. The old JSONB
  description-string path cannot store decoded NUL. Description evidence and its
  History reader therefore need an explicit versioned CPM branch, without
  reinterpreting accepted legacy descriptions.
- Fresh verification/admission obey the original nonrenewable admission window.
  Exact recovery of already committed receipts remains possible afterward.
  Admitted operations, results awaiting settlement and retained completed
  results keep their media references. Cleanup retirement permanently prevents
  later binding, independently of cleanup-token expiry.
- Admission freezes original configuration and funding but grants no inference.
  Later S0 dispatch must be one transaction composing the existing invocation
  and quota owners with the permanent one-time transition. Its fresh
  acknowledgement supplies the exact invocation consumed by execution. Calling
  `prepareAccountedIdentification` around a second authorization boundary is not
  a valid composition. Generic initial-operation barriers remain intact.
- Provider quota commits at dispatch; applicable complimentary consumption
  follows successful completion. Proven-unused cancellation stays with C1.
  Unknown grant/result outcomes cannot refund or reacquire through a generic
  quota lease. Accounting-report success is not durable result evidence, and
  report failure must not discard a known result or authorize another inference.

Complete structural format coverage remains a concrete integration dependency.
The shared
[`inspectJpegContainer`](../../services/supabase/functions/_shared/analysisHistory/jpegContainer.ts)
provides bounded JPEG structure checks, with metadata policy supplied by its
consumer; it does not decode pixels. Existing public-photo and video-frame
validators impose different format, metadata, dimensions and byte limits and
cannot serve as CPM acceptance. The JPEG/still-PNG/still-WebP increment above
does not fully qualify HEIC/HEIF, PNG/WebP animation or scaled VP8, installed
policy or the atomic admission branch. Complete the CPM policy and adapters with
the consuming verification/admission branch, reuse applicable parser primitives,
and qualify exact bytes, format rejection, cancellation and resource limits
locally. Do not silently remove accepted source formats or replace structural
checks with the existing signature-only initial validator.

The later result writer and decoder must jointly define a fixed versioned
Identify-result storage projection. Specify exact fractional-field and arbitrary
UTF-8 representations, preserve absent/null and array ordering, and derive scan
and native projections from the same saved result. Do not pass raw fractional
Identify JSON through the integer-only private canonical codec or accept an
independent caller-supplied scan projection. Encoded storage, including
expansion, must fit the existing 1 MiB result, 64 KiB provenance and 16 KiB
receipt ceilings. This remains a field-level implementation obligation, not an
implemented codec.

S0 dispatch/result/completion and exact status recovery follow the inactive
verification/admission increment together; minimal native delivery and atomic
receiving-to-retained promotion follow those owners. Missing durable output
stays held. Known original output may enter settlement-only recovery without
fresh dispatch. Later selection and user edits cannot be overwritten by an
initial-completion replay. Full photo, reanalysis, audio/video, RUX and
cumulative acceptance remain required before deletion/export and redesign.

The effective database contract makes three additional changes inseparable from
that first increment:

- `initial_admission_statement_contract`, `initial_admission_member_images`,
  `materialize_initial_admission` and their immediate/deferred guards currently
  enumerate exact M1 rows and binding v3. CPM needs a closed variant with exact
  expected before/after images and complete witness consumption; adding an
  unregistered side write is not atomic admission.
- CPM capacity currently has only `pending`/`released`, and cohort validation
  describes unfunded preparation or terminal retirement. An admitted owner must
  retain the original physical-byte liability and satisfy deferred cohort
  checks; neither deleting registry rows nor relabeling capacity as released is
  a retained-media transfer. Existing role-map/write-attempt foreign keys and
  retirement triggers remain part of that transition and its cancellation path.
- Preserve outer owner/advisory/scan/history/lifecycle ordering, then CPM's
  fail-fast capacity lock before registry/attempt locks. A row trigger must not
  acquire the outer owner scope after those inner locks. Both race orders need
  actual qualification; source inspection alone does not establish safety.

A fresh local replay of all 502 current migrations supplied effective routine,
permission, trigger, constraint/FK, column, index and policy evidence for the
write-set review. It verified an empty inactive database and was disposed after
inspection. This is schema evidence, not consuming-writer, race or journey
qualification. The initial local startup failed because Docker was unavailable;
that failed attempt is retained separately. No hosted state was accessed.

## October 29 — inactive durable closure candidate

The
[database contract](../backend-and-data/04-database-schema.md#inactive-cpm-durable-write-closure--october-29)
now owns policy-bound live/marker closure metadata and its validation status.
This supersedes the earlier no-closure implementation checkpoint below without
qualifying a storage protocol, installing a coordinator or issuer, releasing
capacity, or completing the app journey. Source review found a raw-update
backend-revocation gap; targeted reproduction confirmed it, the repaired guard
and tests passed source review, then all 176 catalogs / 7,166 assertions and
seven closure plus five existing write-hold concurrency schedules passed on
exact local replays. All release controls and the approved milestone sequence
remain unchanged.

## October 29 — native pre-transfer reservation candidate

The inactive native owner now persists one exact reserved, not-started role with
aggregate transfer-copy accounting and held restart recovery. Engine source
review, corrected cheap preflight and focused native qualification passed (28
methods / 67 cases reconciled across the retained runs). The
[current scan contract](../backend-and-data/16-scan-ingestion-reliability-and-recovery.md#october-29--inactive-single-role-transfer-reservation-candidate)
owns this transition and supersedes earlier statements that reservation is
wholly unimplemented. Source access, transfer lifetime, backend
capability/closure and full journeys remain unqualified. This adds no external
or release authority and does not change the approved milestone sequence.

## October 29 — native v2 transport candidate

The inactive native owner and authenticated adapter now support explicitly
reserved v2 create/status. That owner/transport checkpoint passed Engine review
and 17 methods / 49 cases. The inactive Capture composition now selects v2 and
passed focused native qualification: 9 methods / 22 cases. Engine cleared
production; the corrected test-macro failure remains retained. The ordinary
factory remains disabled. The
[scan transport contract](../backend-and-data/16-scan-ingestion-reliability-and-recovery.md#october-29--native-v2-transport-integration-candidate)
owns dispatch, durable reservation, exact recovery and remaining integration.

## October 29 — native enrichment implementation candidate

The inactive reservation and receipt-enrichment writer passed focused native
qualification: 13 methods / 38 cases. The
[canonical transition contract](../backend-and-data/16-scan-ingestion-reliability-and-recovery.md#native-allocation-enrichment-inactive-candidate)
owns legacy byte preservation, whole-graph accounting, exact recovery and
remaining transport integration. Earlier “enrichment is next” statements below
record the preceding checkpoint. Ordinary HTTP requests remain v1; transfer and
full journey acceptance remain open. Release holds are unchanged.

## October 29 — inactive role projection checkpoint

The
[v2 allocation contract](../backend-and-data/05-api-contracts.md#october-29--versioned-photo-allocation-role-projection-inactive)
adds an ordered, bounded source/AI/display reference-to-object mapping on the
same authenticated create/status endpoint and an inactive native decoder. This
is a transfer prerequisite, not a transfer capability. Existing native requests
and persisted receipts remain v1. Durable monotonic enrichment with
metadata/revision reservation is next; original candidate, assignment digest and
both clocks must survive status recovery unchanged. Upload/signing, remote
closure, verification, admission/execution/result/history and full journey
acceptance remain open.

## October 29 — inactive outstanding-write hold candidate

The
[database schema contract](../backend-and-data/04-database-schema.md#inactive-cpm-outstanding-write-accounting--october-29)
records the new permanent attempt and conservative capacity hold through
cancellation/private erasure/account deletion. Exact recovery never renews a
clock. This database-owner-only increment has no signer, API grant or closure
settlement. Engine source review, 100 focused assertions and five concurrency
schedules passed. The subsequent private canonical encoder optimization passed
all 176 catalogs / 7,130 assertions and the five write-hold concurrency
schedules on its exact replay, with 170 differential assertions and measured
finalization cost reduction. The canonical contract retains both earlier expiry
failures and the unchanged-deadline evidence. Earlier allocation-only
restrictions remain historical. Transfer, byte verification,
admission/execution/result/history, reanalysis, audio/video, RUX and final
acceptance remain open. PR116, deployment and later-sequence controls are
unchanged.

## October 29 — Capture allocation caller qualified locally

Local checkpoint `2685d18b2` connects the inactive Capture submission caller to
explicit allocation and typed exact saved recovery. Focused validation passed 10
methods / 34 cases with unchanged native/project inputs; Engine source review
found no blocker. The
[scan-ingestion contract](../backend-and-data/16-scan-ingestion-reliability-and-recovery.md)
owns the current behavior, evidence and retained failed attempt. This supersedes
earlier planned/pending caller and recovery statements below. The preceding
Release qualifies its earlier allocation-writer scope, not this caller change.

Next is original/AI/display transfer and verification under the existing CPM
lifetime/accounting contract, then admission/execution/result/history. The
AI-only receiving readback does not implement that complete transfer. Ordinary
installation remains disabled. Initial photo/reanalysis/full-photo, audio/video,
RUX and final acceptance remain open; the unrelated Auth architecture failure,
PR116 freeze, deployment hold and approved later sequence are unchanged.

The required local task-termination primitive is now implemented in the existing
pinned transport and qualified at 18 methods / 20 cases; see the
[scan-ingestion contract](../backend-and-data/16-scan-ingestion-reliability-and-recovery.md).
This supersedes the planned primitive below, without qualifying media-owner
integration, physical copies, transfer reservations or remote write closure.

## October 28 — allocation facade integration candidate

The local authenticated `initial-photo-allocation` facade now connects the
closed app request to the existing service-only CPM create/status owners.
[API contracts](../backend-and-data/05-api-contracts.md#october-28--initial-photo-allocation-http-candidate)
is the canonical home for the minimal receipt, exact-candidate recovery, privacy
and terminal-hold semantics. Engine agreed that the full assignment stays
server-private and both actions carry the exact saved candidate so the existing
assignment validator can run without another privileged lookup.

The receiving slot is the native durable lifecycle owner. Allocation attempt
state needs an additive SwiftData migration and must not mutate Prepared or
reuse the release-start sidecar. Persist-before-send, status-only uncertainty
recovery and release/abandon fences remain unimplemented. No app caller,
activation, deployment, upload, funding, execution, result or history
qualification is implied by this facade. Earlier no-route notes describe the
historical checkpoints below.

## October 28 — initial photo live preflight composition checkpoint

The inactive draft factory carries the existing network preflight dependency
through preparation into the retained submission session. The direct submission
factory shares that dependency. Fresh photo admission uses the existing required
consent synchronization and account-bound read, with the session's frozen
selection validator checked around consent/discovery and again at immutable
save. Saved slots bypass both fresh consent synchronization and recipient
discovery; this local recovery does not authorize execution. The existing
reanalysis paths reuse the same private consent helper with unchanged checks.

This supersedes the earlier injected-seam notes below that describe live
consent/endpoint composition as unimplemented. Those notes retain the earlier
candidate's validation evidence. Engine source review found no blocking
production issue; its mock server-minimum finding was corrected before native
execution. Focused Debug validation passed 23 methods / 46 cases, with all 3,035
native/project pins unchanged and no structured runtime warnings. Swift/Python
size-policy parity, full iOS tooling and changed-Markdown checks also passed.
Earlier failed static attempts and the unexecuted mock fixture remain retained.
This is local checkpoint evidence, not a new Release or full-journey pass. No
wire shape, funding rule, automatic retry, activation or deployment changes.
Allocation, execution/result, explicit history enrollment and the complete
photo/reanalysis journey remain open.

## Retained preflight-to-save integration — locally qualified checkpoint

The native original owner now retains the preflight await within the same
account cancellation/drain operation as discovery and staging. Fresh metadata
and ordered pair intents are checked before the read; receiving locks are
acquired afterward. Existing stage validation rejects changed metadata or a
concurrent saved slot, and the injected current authorization is checked again
synchronously immediately before the immutable save. Saved slots, including
legacy nil expectations, bypass fresh recipient discovery and preserve their
identity and bytes.

Capture's submission session supplies the typed shape using its exact frozen
selection and the owner-minted observation ID. This is an injected local
integration seam: ordinary app composition still installs no preflight
dependency. Live consent synchronization/endpoint wiring, allocation, execution,
results and history remain open. New tests target identity binding, saved/legacy
replay, ambiguous save recovery, account shutdown drainage, stale selection and
revoked or recovery-only authorization. Engine source review found no blocking
production issue. The corrected local Debug run passed 36 methods / 62 cases,
with all 3,035 native/project pins unchanged and no structured runtime warnings.
An omitted extension inventory was corrected before launch; an initial test
assertion compile failure and its test-only repair remain retained. This is
focused shared-checkout validation, not a new Release, full photo journey or
feature activation.

## Native photo preflight integration — current working increment

A typed `IdentificationPreflightInput` initializer now derives the existing
photo-profile shape from the receiving observation ID, selected-photo count and
bounded frozen contexts. It does not synthesize a legacy Identify body or send
context text. Existing description eligibility rules are evaluated without
rewriting the saved text. Zero-photo and out-of-profile counts are rejected;
this adds no fresh text-only path or changes to the RPC payload.

This increment has no production caller. Focused native tests passed 11 methods
/ 11 cases with no source drift or structured runtime warnings, and the full iOS
tooling gate passed. Engine scoped review found no blocking defect.
Owner/session integration and full-journey qualification remain open. The next
integration must keep preflight inside retained account cancellation/drain
ownership and outside receiving locks, revalidate exact selection and consent
through save, and bypass fresh recipient discovery for saved slots. No
admission, upload, funding, execution or activation is enabled.

## October 28 — native admission persistence candidate

The inactive native candidate now stores the validated protocol 3/protocol 6/
processor expectation in the existing V2 receiving envelope and consumer intent
binding. Omitted fields preserve historical bytes; V1 rejects a present field.
Retries with a supplied different expectation fail, while omission recovers the
saved expectation unchanged. Release-origin reconstruction preserves it and
existing reservation calculations include the encoded payload. The native
candidate digest binds this saved value and exact content bytes independently of
the existing content-only digest.

Engine source and test-delta reviews found no blocking defect. Focused native
Debug evidence, combining unchanged passing cases with the corrected test rerun,
qualifies 26 methods / 45 cases without source drift or structured runtime
warnings. The original test lifecycle failure and inventory correction remain
retained. The added persisted test extends through one-photo release cleanup and
cold terminal recovery, with funding assertions. Fixed historical V2 codec
coverage uses explicitly non-admissible placeholder blobs; it is not historical
full-graph acceptance. Two-photo cleanup, fault injection, full app journeys and
new Release qualification remain open. There is no live allocation caller:
future integration must bind preflight to the saved logical identity before
allocation I/O, revalidate current authorization, and preserve all existing
lifecycle and account fences. This local snapshot is descriptive and cannot
authorize I/O.

## October 28 — inactive SQL owner integration checkpoint

The local `20261027230332_prepare_initial_cpm_photo_intents.sql` now extends the
existing create/status, cancellation and erasure owners with a separate CPM
branch. Independent codec, runtime and follow-up source reviews are complete.
Fresh local replay of 494 migrations, 61 focused allocation assertions and
three-session capacity contention passed. The complete 175-file catalog gate
passed with 6921 reported assertions after the reviewed index, merge-policy and
fixture repairs. The fixture uses a distinct cleanup operation and synthetic
account; original deadlines and allowances remain unchanged. No application
caller or installed profile is added.

The candidate uses a distinct immutable CPM profile, installation target and
selection, while reusing retained assets, policy/provider resolution, consent,
entitlement projection and the permanent source registry. Allocation binds all
three roles for each photo, a millisecond-aligned original clock and a fixed
30-minute deadline. Recovery reads the saved assignment before current
configuration or eligibility, so it cannot silently renew that deadline.

Private capacity reservations serialize the two-per-owner and sixteen-global
pending limits and reserve the sum of every declared role occurrence. The
allocation-only state admits no write capability or retained completion. It may
release a reservation only after terminal cancellation/deletion and permanent
retirement of every role, with no execution grant or admission and durable
`never_issued` evidence. Owner erasure detaches the private account reference.
An indexed owner reference participates in the existing identity-merge preserve
policy. Pending and released rows retain their original owner and hold that
owner's merge until account erasure detaches the reference; unrelated merges are
not globally blocked. Future write issuance, uncertain remote closure and
retained-completion accounting require a coordinated extension before any such
path is enabled; this candidate does not qualify those states or substitute
local drainage for remote closure.

Legacy finalization/execution/proof and media admission paths remain closed to
CPM. The existing generic upload signer does not target this registry or issue
CPM capabilities. Focused local tests cover exact replay, capacity
rollback/contention, raw-write denial and synthetic erasure. Cross-owner erasure
ordering, legacy concurrency and complete app journeys remain open. The first
aggregate catalog run caught a missing full owner index and merge-reference
classification; both were repaired and reviewed. A later complete run exposed
the missing C1 private-child registration. The candidate now registers all six
possible role mappings with the existing cancellation inventory, deterministic
image ordering, prestate/merge locks and admission/cancellation/handoff guards.
Capacity remains a surviving accounting record, outside private erasure. This
repair passed fresh replay, independent source review and 89 handoff-owner
checks, including committed transfer and transferred C1 cleanup. The complete
catalog gate also passed on the corrected exact seal inventory. Legacy handoff
now accounts for the empty FK child statement and snapshot without expanding
event, frame or byte limits. Nonempty CPM mappings remain explicitly denied from
handoff. The catalog also exposed a legacy exact-1MiB admission timing failure.
A later diagnostic passed all three encoding cases under the unchanged deadline,
with most time in final admission checks; that passing run is not a fix or full
timing qualification. Ordinary activation, PR116 and the deployment hold remain
unchanged.

## October 27 — prior codec-only implementation checkpoint

The unfinished allocation increment now has separate closed candidate,
assignment and recovery metadata schemas under `initialAnalysis`. These helpers
have no production caller. They do not allocate an intent, reserve capacity,
select a profile, issue a write ticket, verify bytes or fund execution. The SQL
migration remains an uncommitted implementation candidate; passing its codec
tests does not finish the coordinated allocation/recovery increment below.

The candidate wraps exact `content_canonical` plus the saved client protocol
`3`, identification protocol `6` and expected processor permission. Its separate
`cpm-photo-candidate.v1` digest binds all of those fields. Native integration
must persist the expectation before allocation I/O; retry cannot obtain a
replacement expectation from current UI state. The original content schema and
digest remain independent and unchanged.

The assignment schema binds candidate and content digests, scan/package
identity, millisecond creation and expiry clocks separated by exactly 30
minutes, frozen server configuration, and a complete role mapping. The mapping
is in photo ordinal order, with source, AI and display in that order for each
photo. Every entry contains its exact declared logical reference, length, digest
and type, plus a distinct server object identity. Equal bytes never collapse
occurrences. The preparation metadata binds separate CPM profile/installation
and verifier build digests, selector/backend generations, the existing backend
installation, `P1-L1` and `cpm_photo_contexts_v1`. These are bounded saved
claims until the owning SQL transaction compares them with the actual immutable
catalogs and current eligibility. They cannot borrow legacy transformation
qualification.

Server configuration includes an explicit output language; there is no client
language field or decoder default. The resolver must obtain it from the selected
server profile. The schema preserves existing policy/provider/protocol field
semantics and restricts this branch to photo input profiles. Structural decoding
does not prove live consent, entitlement, eligibility, ownership or object
bytes.

Recovery metadata currently has two closed outcomes: `allocated`, containing the
exact canonical assignment and its digest, and `terminal_held`, containing the
scan identity and a bounded `not_found`, `expired` or `cancelled` reason. Both
carry `authority: none`. The decoder requires an explicit saved assignment
argument: `null` only when no first allocation acknowledgement was saved, or the
exact original canonical string otherwise. Once saved, a different valid clock,
configuration, destination or backend generation is rejected. When that first
acknowledgement is missing, only server recovery can establish the original
assignment. A terminal/not-found reply never permits replacement or fresh
execution. Verification and admitted outcomes are rejected until their own
coordinated implementation exists.

The new assignment digest uses
`merian.initial-analysis.cpm-photo-assignment.v1\n` followed by exact canonical
UTF-8 bytes. Callers must strictly parse before using the SQL digest helper; it
does not validate its input. Legacy digest domains and stored branches remain
unchanged. The executable JSON schemas are the field authority. These private
metadata additions do not change the generated public Identify DTO block or
introduce Swift, web or admin consumers. Native saved-candidate persistence and
response mapping remain required before app integration.

## October 27 — inactive Swift producer checkpoint

`SharedMediaNativePhotoContent` now implements the saved-value projection under
Core/Data/SharedMediaStorage. Its Prepared initializer validates the complete
saved envelope and explicitly requires preparedV2/version 2; it derives the
cohort and supporting values from that same envelope. A typed claim initializer
shares the same closed validation and private schema-specific canonical writer.
It has no wire decoder, live route, current-state authority, media I/O or
production caller. Immutable canonical Data and an unverified domain digest are
its only outputs. The receiving owner remains responsible for current account,
held-state, original-retention and exact persisted-identity checks at
consumption.

Source review and focused native compilation/parity validation passed: seven
methods / twenty cases, with no source drift across 3,033 native/project pins
and no structured runtime warnings. This is shared-checkout Debug validation,
not a new Release or full app-journey qualification. Independent host checks
bind both the existing Deno golden fixture and a scalar-escaping vector to the
Swift expected digests. The passing native tests cover exact byte/digest parity,
text order and normalization distinctions, recipe bits, bounds and role
uniqueness, plus actual saved Prepared mapping, reordered frozen positions,
inconsistent identities and otherwise-valid V1 rejection. These claims concern
declaration construction only; complete CPM consumption and all app-journey
acceptance remain open.

# Initial photo CPM content declaration v1

Status: October 27, 2026. The pure inactive content-codec design was reviewed by
Engine in turn 01a17f2c-63d1-7750-b6f8-21c4eb4e7345. The local implementation
candidate is `initialAnalysis/cpmPhotoContent.ts`, with the closed executable
`cpm-photo-content-schema-v1.json` as its field authority. Source review cleared
this pure-codec scope. Ten focused tests and the full Edge suite passed (3416
tests / 598 steps, with 532 tests explicitly ignored). Recursive type,
format/lint, config/dependency and documentation checks passed. Tooling coverage
completed across retained runs: 521 standard tests, 157 isolated evaluator
tests, 20 and 21 DTO tests, one archive test and 21 shell tests. The original
tooling commands remain failed: a stale V59 recovery guide was corrected to the
existing V66 implementation, and a synthetic PTY test required terminal access.
Its five-scenario rerun and all remaining shell tests passed without repeating
the completed suites. This is shared-checkout validation, not isolated-source,
native parity or runtime acceptance. No live owner or route imports it; no SQL,
Swift DTO or provider adapter is installed. This closes only the
content-declaration slice, not the complete CPM admission contract.
Server-preparation M1/M2 and historical recovery remain unchanged.

## Existing inputs and actual gaps

`SharedMediaNativeReceivingIntent.Prepared.observationID` is the initial server
scan/logical operation ID. Its operationID is local receiving, queueID is local
job correlation, bindingID is local consumer identity and generation is the
native inference fence. They are not alternate server inference identities. The
frozen cohort supplies ordered derivative intents, exact supporting bytes,
original identity and recipe. Readback supplies AI bytes only. The existing
initialAnalysis source assignment expects server-preparation proof and cannot
consume these as equivalent evidence.

The native supporting value stores an ordered contexts array and separate photo
presentation. It does not store an interleaved photo/text chronology or frozen
language/location/client inference options. ObservationContext.serialized()
trims text; the new mapping must not call it after freeze. Capture product and
provider composition must not silently invent chronology or fetch current UI
options to fill missing values. This is a concrete consuming-contract issue, not
permission for another queue or funding owner.

## Content-only v1 encoding

Use contract `client_prepared_media_v1`, content schema version 1 and photo
profile `P1-L1`. This slice admits one or two photos, optional exact text and no
client inference overrides. It does not declare audio/video unsupported by the
product: those remain later required profiles and cannot fall back to legacy
fresh admission. No endpoint, SQL signature, active route or eligibility is
allocated by this content codec.

Reuse initialAnalysis/canonical.ts sorted ASCII-key JSON, safe integers, exact
Unicode scalar strings, duplicate/extra/missing field rejection and the 1 MiB
serialized metadata ceiling. Use a separate SHA-256 domain:
`merian.initial-analysis.cpm-photo-content.v1\n` followed by exact canonical
UTF-8 bytes. Do not change legacy canonical domains or label this digest
verified.

Closed top-level fields:

| Field            | Proposed content                                  |
| ---------------- | ------------------------------------------------- |
| contract         | literal client_prepared_media_v1                  |
| version          | integer 1                                         |
| kind             | literal initial_photo                             |
| resource_profile | literal P1-L1                                     |
| scan_id          | lowercase canonical UUID from saved observationID |
| package_id       | lowercase canonical UUID from frozen packageID    |
| photos           | ordered array of 1–2 photo records                |
| contexts         | ordered array of 0–64 exact submitted contexts    |

Each photo has ordinal (0-based consecutive), source, ai, display and recipe.
Each role has logical reference_id, byte_count, sha256 and
declared_content_type. Logical IDs map to original.reference.referenceID /
intent.ai.referenceID / intent.display.referenceID; no server object ID or
generation is present. Association is explicit by containment; equal hashes
never deduplicate or reorder entries. Logical reference IDs are distinct across
these initial selected photos; physical sharing is a server reference decision,
never a hash-based client decision. All logical role IDs are distinct; the
current native recipe always creates separate roles. No source-version identity
is fabricated for initial capture. Reanalysis gets a separately reviewed
discriminator/shape with its exact selected source version.

Declared content type is a bounded nonempty scalar string, at most 128 UTF-8
bytes. A syntactically valid declaration is not a supported input profile or
proof of MIME/framing. Actual eligible original formats, AI/display JPEG rules,
byte-verifier build and provider compatibility remain explicit server profile
requirements; a codec cannot silently accept a format for execution.

Recipe is client provenance only: format (nativeStillImageV1 or
nativeCameraStillV1), is_pro, crop_display_size_bits (nullable), quarter_turns,
scale_bits, offset_x_bits, offset_y_bits, camera_vertical_center_bits
(nullable). Floating values use exactly 16 lowercase hex digits of their IEEE754
binary64 bit pattern. This preserves frozen finite values, including signed
zero, without a second decimal normalization changing their identity. Validate
the same finite/range/null combinations as SharedMediaNativePreparationRecipe.
Never serialize the enclosing native derivative/preparation blob: it includes
local file tokens, filesystem proofs and owner identifiers irrelevant to wire
permission. A later consuming builder must use the exact saved recipe only.

Each context has text_utf8_base64, canonical padded RFC4648 of exact strict
UTF-8 bytes. This avoids silently losing native-accepted NUL or altering Unicode
normalization through legacy scalar-string restrictions. Decode before applying
native-equivalent limits: 8192 scalars and 16384 UTF-16 units each; 32000 total
UTF-16 units; at most 64 entries. Preserve empty and whitespace-only entries and
order. Do not trim, combine, infer text/photo interleaving or take current
notes. The provider compositor must explicitly agree how the two ordered arrays
are serialized before consuming this manifest; this codec alone makes no
chronology claim. The serialized 1 MiB ceiling still includes base64 expansion.

Per-role limits match P1-L1: original 32 MiB each/64MiB cohort, AI 5 MiB cohort,
display 4 MiB each/8MiB cohort. Counts are positive safe integers, hashes
lowercase 64 hex, UUIDs canonical. Six objects maximum for this photo-only
slice. Total role bytes plus serialized metadata must remain within 96 MiB; no
limit changes. The codec neither buffers media nor qualifies decoder/worker
memory.

## Separate authority and consuming owner

The server recomputes the content digest from the closed declaration. A future
binding, separately versioned/domain-separated, combines authenticated owner,
scan, original unfunded intent identity, immutable assignment, content digest,
fixed logical-role-to-object/generation mapping, approved types, authority
revision and original deadline. No owner ID/URL/storage key/expiry/provider or
funding selection comes from this client content. Content never contains this
binding or receipt, preventing circular digests.

Complete byte verification must consume owned immutable original/AI/display
objects, full length/hash and bounded admissibility proof under the original
intent. It yields byte verification, not server transformation. Existing
initialAnalysis admission/accounting then atomically consumes the complete
new-branch proof; no M1/M2 placeholder and no dispatch from replay. Unknown
create/upload/verification/admission/provider outcomes recover exact saved
identity; no reminting, auto reupload, repeat AI, refund inference or deadline
renewal. The 30-minute intent and existing IVI-1 bounded authority clocks remain
policy; this slice does not implement or qualify their enforcement.

Original upload must use a narrow capability under the existing native original
owner/receiving locks with before/after-await and final physical/identity seals.
One bounded transfer at a time, at most 32 MiB original staging, included in 192
MiB temporary accounting. No all-originals Data array or broadened AI
projection. The future lifetime includes URLSession copies and uncertain
transfer cleanup; until that is proved, there is no upload adapter or server
receipt claim.

Completion preserves initial result and immutable evidence via existing owners;
explicit history enrollment remains a later action under IC-1 section 6. A
consumer-kind flip cannot replace the atomic native successor proof.

## Implementation boundary and remaining agreement

The pure, inactive content schema/validator under initialAnalysis has golden
vectors for one/two photos, exact text (including NUL/non-BMP/whitespace),
bit-pattern recipes, bounds, order, multiplicity, unknown fields/versions and
private-field rejection. A Swift mapping is a separate compiled checkpoint
consuming the saved native values; no new runtime state, route, SQL or provider
authority follows from codec tests.

Before any adapter can consume it: agree native/server text composition and
explicit option absence; close allocation/verification/admission/recovery
versioned fields, exact clocks/caller/lock/retirement ownership and response
semantics; prove original-transfer lifetime; preserve original funding rules.
Hosted feasibility, device and installed UI, full initial-photo result/history,
reanalysis, audio/video, RUX and final acceptance remain open. This proposal
does not claim that the complete CPM admission contract is closed.

## October 27 consuming-contract design checkpoint

The Engine source trace in turn 01a17f61-3450-7790-9c6b-ff4a3daa6c0a identifies
the existing owners below. Source/design review in turn
01a17f67-60af-72f1-8626-40e4286fc3d7 cleared this checkpoint with the
local-drain versus remote-write clarification below. This section proposes the
consuming branch; it is not an implemented wire schema, expanded catalog audit,
native transfer proof or permission to install an adapter. The content codec and
Swift producer above remain the only qualified new implementations.

### Frozen provider composition

Use the separately versioned composition policy `cpm_photo_contexts_v1` in the
immutable server assignment. Provider image evidence consists only of the AI
derivatives, in frozen photo ordinal order. Original and display objects are
retained evidence; they are not additional provider images. After those images,
emit one supporting-context section containing a JSON array of the exact decoded
context strings, in context order. Empty entries, whitespace, BOM, Unicode
normalization distinctions and NUL survive JSON escaping. An empty contexts
array emits `[]`; it cannot turn this into a text-only request. The section
describes observation-wide supporting descriptions and conveys no photo
association or interleaved chronology. Actual provider serialization and prompt
policy must bind this version and be tested before dispatch.

Client language, location and inference overrides are explicitly absent in this
version. Never fill them from mutable UI, parent records, account/session
preferences or legacy defaults during recovery. Where the provider requires an
output language or other policy value, the server must select it through the
existing configuration owner and freeze it in the assignment. Unsupported
assignment/configuration combinations fail before allocation. Recipe `is_pro`
does not select entitlement, funding, model or configuration.

### Coordinated lifecycle branch

Extend the existing initial-analysis lifecycle with an explicit CPM branch.
Historical candidate/assignment/preparation/proof versions retain their exact
semantics. A missing or unknown CPM discriminator cannot select fresh legacy
admission. The following are required binding groups, not a new public DTO;
their executable field names, types and closed response schemas must be added
with the owning implementation and cross-language fixtures.

| Boundary                  | Existing owner                                                                                                  | Required CPM binding and transition                                                                                                                                                                                                                                                                                                                                                                                                                            |
| ------------------------- | --------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Unfunded intent           | `create_initial_preparation_intent`, `lock_initial_preparation_scope`, `assert_initial_preparation_unfunded`    | Authenticated owner and saved native observation/scan ID, exact canonical content and recomputed domain digest, permanent operation fence, explicit branch version. Exact recovery precedes allocation; changed content conflicts.                                                                                                                                                                                                                             |
| Assignment and allocation | `resolve_initial_media_preparation_assignment`, `create_initial_media_preparation`                              | One saved assignment binding content, resource/verifier/composition versions, frozen server configuration and consent/authority witnesses, original creation/admission deadline and the complete ordered role mapping. Each role binds logical reference, object identity/backend generation, expected length/hash/type and ordinal. No source-only mapping or hash deduplication. Capacity includes all fixed roles and potential physical/late-write copies. |
| Verification              | `verifyAndRetainInitialMedia` and its claim/settlement/exact-read owners                                        | A new byte-verification receipt binds the same assignment/content, every exact original/AI/display generation and verified full-byte facts, verifier build/profile and original deadline. A partial cohort, client declaration or storage metadata is insufficient. It attests bytes/admissibility, never client recipe execution or server transformation.                                                                                                    |
| Admission and funding     | `create_initial_admission_stage`, `materialize_initial_admission`, ledger/seal/finish and existing quota owners | One transaction compares exact expected owner/intent/assignment/receipt/role rows, checks live account/deletion/authority fences and original deadlines, retains all evidence, and invokes original funding once. It returns the existing operation's admitted identity. Rollback cannot leave partial capacity, reference or funding transitions.                                                                                                             |
| Recovery and retirement   | Preparation status, admitted recovery, C1 cancellation and permanent object registries                          | Recover committed admission first. Otherwise return only exact saved intent/assignment/receipt state under the same identity. Retirement closes admission/writes and records every destination and outstanding write; cancellation does not erase its cleanup authority. Unknown outcomes stay held.                                                                                                                                                           |

The current stage expects assignment v3 and coherent server preparation/outcome;
it cannot consume CPM by relabeling M1/M2. The public
`finalize_initial_preparation` also has a media-source denial; an adapter must
not bypass it by calling internal stage helpers. Add the CPM branch coherently
through the authenticated service boundary, transaction guards and recovery
projection. Keep canonical contexts as base64 in PostgreSQL JSON/private
declaration storage: decoded NUL cannot enter PostgreSQL TEXT or be laundered
through a pretend legacy scalar input.

Freeze the new branch's nonrenewable 30-minute admission deadline once, at
intent allocation. This does not modify the historical 300-second branch.
Assignment/consent/configuration authority must remain valid at admission; the
intent lifetime cannot extend their validity. Write tickets expire no later than
that deadline and are at most ten minutes; each native object transfer has at
most five minutes. A refreshed ticket requires positive closure of the preceding
write and uses the same fixed object/generation. Local task termination proves
local drainage only. Ticket refresh, verification and admission separately
require remote closure: no outstanding write capability or accepted late write
may alter a verified generation. Verification seals that generation against
further writes; no ticket refresh may reopen it. Unknown remote writes keep
their cleanup liability even after the local task has drained.
Verification/admission cannot extend staging. Existing downstream provider
grant/execution/completion clocks remain enforced by their owners after
admission. Status and cleanup may continue after expiry; expiry is not proof of
write completion, absent liability, refund or permission to dispatch again.

Recovery replies need closed, versioned alternatives for saved-unfunded,
saved-verification, admitted and terminal-held states, with exact immutable
identity comparisons. A status-not-found response is not a replacement permit.
Lost allocation, PUT, verification or admission acknowledgements never mint a
new scan, assignment, object generation or funding reservation. Privileged
owner/registry facts stay server-side; client receipts contain only their
necessary bounded opaque identities, versions and exact binding digests.

### Native transfer lifetime and accounting

`SharedMediaNativeOriginalOwner.readReceivedAppPhotos` already owns the queue
and observation locks and scoped receiving workflow. Its current readback
returns AI bytes only. `SharedMediaNativeOriginalIO.preparePhoto` checks the
original's descriptor/binding/epoch before and after its private URL use;
`readCompletedPair` seals derivative reads with completion proofs. Reuse these
owners and their current account/store/received-state/physical checks for
transfer. No caller receives an unowned URL or all-originals Data array.

The unchanged 192 MiB temporary limit is subdivided into 96 MiB acquisition, 64
MiB preparation and **32 MiB transfer/export**, enforced in
`SharedMediaStoragePolicy.Totals.includeBudget`. One 32 MiB original therefore
does not leave space for a second full staging copy in the transfer subpool.
Existing durable original bytes remain charged once; every additional physical
copy and unmaterialized allocation is separately reserved. Memory buffers also
need an explicit peak bound; copy-on-write is not a proof of absent copies. Do
not borrow another subpool or lower supported input limits to fit an upload.

The consuming transport must serialize one role at a time, reserve through the
existing common allocation authority before reading/dispatch, and retain the
reservation and original reference until task termination and exact cleanup are
positively known. A descriptor-bound stream or file-backed transfer must prove
its actual staging/copy behavior fits the existing subpool at the maximum legal
original size; selecting such an API alone is not that proof. Native source
validation repeats after awaited boundaries and before acknowledging a role.
Reuse the same assignment/object after uncertainty; do not start the next role
or release unknown transfer liability just because a client await ended.

`PinnedNetworkDataTaskState.cancel`/`finish` deliberately resume the caller
before URLSession necessarily acknowledges cancellation. They are appropriate
deadline behavior, but not a transfer-drained receipt. The CPM path needs a
separate task-termination/drain witness within the existing transport owner,
without weakening prompt cancellation for other requests. Account transition,
deletion and native shutdown must join that drain before releasing media or
capacity. Restart must reconstruct unresolved transfer/cleanup liability; no
saved reservation authorizes automatic reupload. The current native owner has no
qualified original-upload capability, and mixed-owner allocator acceptance
remains open under the native ownership agreement.

### Required acceptance before consumption

1. Executable CPM request/assignment/verification/recovery schemas and SQL
   parity, private-field rejection, byte-exact text/provider composition and
   explicit option absence; existing legacy replay vectors remain passing.
2. Lost replies at allocation, write, verification and admission; exact saved
   recovery and changed-content/role/order/generation denial on both sides of
   admission, without renewed clocks, allocation or funding.
3. Full maximum-size cohort verification, immutable destinations, bounded
   ingress/retention including oversize and late writes, and no invented
   transformation proof. Existing `mediaBinding.ts` budgets do not cover this
   cohort; use branch-specific limits without changing legacy constants.
4. Atomic original-funding rollback, both cancellation/deletion race orders,
   irreversible retirement and exact late-write cleanup inventory. Review
   expanded effective SQL functions/triggers, then run disposable catalog,
   privilege and deterministic concurrency gates for the candidate.
5. Native reservation/drain/restart tests, maximum-original transfer budget,
   account/deletion/physical identity races, exact saved request replay and
   preservation of later user selections. URLSession timeout is not cleanup.

These are direct submission requirements. They add no new scheduler, queue,
funding system or lifecycle owner. Passing source review does not qualify hosted
storage behavior, native memory/disk lifetime, installed app journeys, result
persistence/history handoff or reanalysis. External-operation holds and the
approved media/RUX/later-feature sequence remain unchanged.

The first implementation increment is inactive CPM intent allocation **and exact
recovery together**. Add their closed candidate/assignment/recovery schemas with
SQL/Deno parity; atomically freeze the complete assignment and ordered role
mapping under the existing intent owner and register every destination with its
retirement authority. Exact replay returns saved identities even after current
configuration changes, and cannot renew the original deadline. Include expiry,
terminal fences, cancellation/deletion races and rollback tests. This increment
issues no upload, verification, funding or provider authority. Native original
transfer follows under the separately required lifetime proof.

## Revision 2 review clarification

Physical original asset IDs may be shared behind distinct logical references.
Use reference_id, not asset_id, as the role identifier; preserve both ordered
occurrences even when their physical native asset or hashes match. The native
builder still compares exact saved asset generations locally; this content
projection supplies no remote physical-sharing authority. Strict UTF-8 decode
must preserve a leading BOM (TextDecoder ignoreBOM:true) and reject invalid or
noncanonical base64. Independent synthetic text/bit vectors are retained in
photo-cpm-encoding-vectors01.json. They are encoding examples, not test passes.

## Exact mapping and qualification boundary

Photo ordinal comes from frozen cohort entry position. Acquisition ordinal, UUID
sorting and presentation-array order are not substitutes. Context order is
independent. Recipe bits are the unsigned binary64 pattern, most-significant hex
digit first, never native memory byte order. is_pro is provenance only. The
digest validates and snapshots canonical text synchronously before awaiting
SHA-256; it retains no caller-mutable object through that await. An unverified
content digest is not a server-issued verification receipt or dispatch grant.

The executable Deno schema is the field authority. The future Swift mapper must
prove parity using these exact golden/denial vectors and compile against saved
native values before consumption. No Identify DTO generator block changes
because no public Identify shape changes. The web and admin surfaces have no
producer or consumer of this private declaration. Allocation/verification and
recovery schemas remain separately unimplemented; a passing pure codec cannot
install an adapter or bypass their review and qualification.
