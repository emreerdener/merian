# Three Complimentary Pro Scans

This document is the normative product and engineering contract for replacing
the introductory calendar trial with three lifetime complimentary Naturebook Pro
scans per account. Product summaries, API references, route READMEs, and
operations guides may restate parts of this contract, but they must not weaken
the invariants here.

## Release status

The repository contains the
[forward schema migration](../../services/supabase/migrations/20260802235833_three_complimentary_pro_scans.sql),
dual-mode backend, reservation-safe protocol-3 iOS client, admin telemetry, tests, and
[owner-only cutover script](../../services/supabase/scripts/cutover_complimentary_entitlements.sql).
Applying the migration does **not** activate the new offer: it creates
`internal.entitlement_rollout_config` in `legacy_trial` mode with client
protocol enforcement disabled. Production remains on legacy behavior until an
operator completes the ordered rollout and atomically selects `complimentary`
mode with required protocol `3`. A transitional configuration requiring `2`
accepts supported clients presenting protocols 2–3 until the verified build is
required atomically.

Do not describe the complimentary offer as live merely because its code or
migration exists. The authoritative rollout procedure is
[`06-supabase-deployment-runbook.md`](./06-supabase-deployment-runbook.md#complimentary-pro-scan-entitlement-rollout).

## Product contract

- Every existing and future account receives one fixed grant of three
  complimentary Pro scans. Credits do not expire with time.
- Customer-facing copy calls these simply **Pro scans** or **included Pro
  scans**. Counters use “3 Pro scans remain” and “1 Pro scan remains”; the word
  “complimentary” is reserved for internal identifiers, telemetry, admin, and
  engineering documentation.
- The existing free daily Flash scan is separate. A new account can therefore
  receive three Pro-funded results and one Flash-funded result on its first day.
- Selection is automatic: paid Pro wins first, then a complimentary Pro credit,
  then the free policy. A user cannot manually preserve a credit by choosing
  Flash while a credit is available.
- A Flash-compatible, single-evidence observation falls back to the daily free
  policy when no complimentary scan is available to start. Video,
  multi-item/mixed observations, and Pro-only actions return an upgrade-required
  outcome instead of being silently degraded.
- A valid completed result consumes a credit even when the subject is
  non-biological. A stored Pro result remains fully viewable after the final
  credit is consumed.
- The paid **7 Day Pass**, annual subscription, product identifiers, and
  purchase copy are unchanged. A paid pass is not a complimentary credit.

### Consent is not scan capacity

Current adult, Terms, and Google Gemini evidence is a prerequisite to every
provider-backed plan, including a new account's first included Pro or daily
Flash scan. `internal.require_current_ai_consent(...)` runs inside
`reserve_ai_quota(...)` before entitlement selection, credit holds, or provider
counters. Its `403 ai_consent_required` result therefore means only that the
active account cannot prove the required disclosure bundle; it is not a
zero-balance state and consumes no included Pro or Flash allowance.

Product, support, telemetry, and client routing must use stable error codes
rather than interpreting the RPC name. Actual capability exhaustion uses
`402 pro_required`; daily provider exhaustion uses
`429 ai_quota_daily_exceeded`. A newly onboarded account must upload and refetch
its account-owned consent evidence before its first Identify request. See the
[first-scan consent-policy incident](../incidents/2026-08-first-scan-consent-policy-retry-loop.md).

The plan values have distinct meanings:

| Plan                | Current use                                                                                                |
| ------------------- | ---------------------------------------------------------------------------------------------------------- |
| `pro_paid`          | Active subscription, lifetime purchase, grace period, or paid 7 Day Pass represented by durable paid state |
| `pro_complimentary` | Current functional Pro access from an available complimentary credit or an active hold                     |
| `free`              | Neither paid nor functionally complimentary; a compatible primary scan may use the daily Flash policy      |
| `pro_trial`         | Historical reservations, usage events, filters, and reports only after cutover                             |

`current_tier = "pro"` means functional access. `is_paid = true` means paid
status. Public Pro badges, billing work, and paid-account protections must use
paid status rather than functional access.

## Ledger and derived balances

`internal.complimentary_scan_usage` is a private lifetime ledger with primary
key `(user_id, client_scan_id)`. The original `client_scan_id` is the analysis
linkage for the user action; no second analysis identifier exists. Each row is
in exactly one state:

| State      | Meaning                                                                                    | Credit effect                                            |
| ---------- | ------------------------------------------------------------------------------------------ | -------------------------------------------------------- |
| `held`     | One accepted analysis owns a credit while its result is unresolved                         | Prevents another analysis from starting with that credit |
| `consumed` | The scan and all required media are durably complete                                       | Permanently uses one grant unit                          |
| `released` | Proven terminal failure, paid-before-completion, or merge-cap settlement returned the hold | Can be reacquired idempotently when policy permits       |

There is no mutable balance column. For a grant `G = 3`:

```text
scans_remaining          = max(G - consumed_count, 0)
scans_available_to_start = max(G - consumed_count - held_count, 0)
in_flight_count          = held_count
```

`scans_remaining` includes in-flight credits. Starting a new Pro-funded scan
must use `scans_available_to_start`, not `current_tier` or `scans_remaining`. An
active hold can retain functional Pro access for related non-scan features while
providing no capacity for a fourth analysis.

Ledger changes increment the protected `users.complimentary_entitlement_epoch`;
the existing entitlement trigger folds that change into the account's monotonic
`entitlement_version`. The rollout singleton's `mode_version` is also included,
allowing one global cutover to supersede every legacy snapshot without rewriting
all user rows.

## Reservation and lock order

`public.reserve_ai_quota(...)` is service-only. For primary scan operations it
accepts the original analysis UUID, server-derived Flash-fallback eligibility,
client protocol, and an authenticated-internal-replay flag. It performs the
following transactionally:

1. Authenticate the service-only caller and require the active account's
   current adult, Terms, and all-version Gemini-head grant.
2. Lock `public.users` for the authenticated owner.
3. Read the rollout fence and resolve active paid state.
4. Reuse the exact classification and ledger linkage of an active idempotent
   reservation, if one exists.
5. Otherwise resolve paid Pro, legacy behavior, an existing analysis hold, a
   newly acquired complimentary hold, or eligible Flash fallback—in that order.
6. Select the database-owned policy/model and reserve the independent
   UTC-day/user/IP provider counters.

The global database lock order begins with the user row, followed by quota,
ledger, ingestion job/advisory, scan, and media rows as required by the owning
orchestrator. External provider work occurs outside database transactions.
RevenueCat mutations and Ghost-account merges follow the same user-first
boundary. New routines must not introduce a ledger-first or scan-first path.

Paid scans create no hold and do not consume or erase historical complimentary
usage. A subscription activated while a complimentary scan is in flight causes
that hold to be released during successful final settlement. Previously consumed
credits are not restored retroactively.

## Linkage, retries, and replay

- Foreground retries keep the same `client_scan_id` and analysis linkage.
- Server replay invokes `/identify-multimodal` with that same analysis UUID and
  an authenticated replay marker. Its provider-quota request UUID can be
  attempt-specific, but it cannot acquire a second complimentary hold.
- Enrichment, Field Chat, moderation, and provider subcalls link to the original
  analysis when relevant; they do not create primary-scan credits.
- A replay of a consumed result reports how the stored result was funded but
  does not perform another consumption transition.
- Retryable or ambiguous outcomes remain `held`. A thrown network or database
  response is not proof that a durable write failed.

## Completion and terminal settlement

`public.complete_scan_ingestion_with_entitlement(...)` is the only service
completion entry point after cutover. It locks the user first, enters the
completion fence, invokes the existing canonical media/scan finalizer, settles
the ledger, derives the post-settlement entitlement, attaches optional response
metadata, and stores the enriched success envelope. Trigger fences prevent a
lower-level job update or old completion RPC from bypassing this orchestrator.

A hold is consumed only after the owner scan and every required image, audio, or
playback-video artifact are durable and the ingestion generation is complete.
`already_complete` is idempotent. If paid status became active before this
point, the hold is released with `paid_before_completion` instead.

`public.fail_scan_ingestion_terminal(...)` is the only service terminalization
entry point after cutover. It locks the user before ingestion rows, marks the
generation terminal, releases a still-held credit, returns the current
entitlement, and never refunds provider counters.

| Outcome                                                                                | Complimentary settlement                                    |
| -------------------------------------------------------------------------------------- | ----------------------------------------------------------- |
| Durable biological or valid non-biological result with required media                  | Consume                                                     |
| Proven terminal provider, policy, malformed-response, setup, media, or service failure | Release                                                     |
| Retryable failure                                                                      | Keep held                                                   |
| Ambiguous provider, persistence, media, or settlement outcome                          | Keep held until recovery proves success or terminal failure |
| Purchase before durable completion                                                     | Release during completion                                   |
| Idempotent replay of a durable result                                                  | Preserve existing settlement                                |

Terminal settlement errors must propagate. Callers may log context, but they
must not swallow an error and then write `failed_terminal` directly. Replay
exhaustion, media reconciliation, deletion, and compatibility setup failures all
route through the user-first terminal orchestrator.

## Provider quota is independent

The complimentary ledger represents the user's three usable results. The AI
quota reservation represents provider cost and abuse limits. They are settled
separately:

- Commit provider quota immediately before an attempted provider call.
- Preserve provider daily/rate/cost counters after an attempted call, including
  when a proven terminal outcome later releases the user's hold.
- Refund provider quota only for a proven no-provider path under the existing
  fenced reservation rules.
- Never infer a provider refund from `credit_released = true`.

This separation prevents provider traffic from becoming unmetered while still
returning a user-facing credit when no usable result can exist.

## Public entitlement and scan response contracts

Authenticated clients call `public.get_my_entitlement()` for their own account.
It returns one row:

```json
{
  "current_plan": "pro_complimentary",
  "current_tier": "pro",
  "is_paid": false,
  "scans_remaining": 3,
  "scans_available_to_start": 2,
  "in_flight_count": 1,
  "entitlement_version": 42
}
```

Successful scan envelopes may add:

```json
{
  "entitlement": {
    "user_id": "authenticated-owner-uuid",
    "plan_used": "pro_complimentary",
    "credit_consumed": true,
    "entitlement_after": {
      "current_plan": "pro_complimentary",
      "current_tier": "pro",
      "is_paid": false,
      "scans_remaining": 2,
      "scans_available_to_start": 2,
      "in_flight_count": 0,
      "entitlement_version": 43
    }
  }
}
```

The entire `entitlement` member is additive and optional. Historical stored
envelopes without it remain valid. `plan_used` retains the original server
funding class. `credit_consumed` says whether the durable result is backed by a
consumed complimentary ledger row; it is not proof that the current HTTP
invocation performed the transition. In particular,
`plan_used = "pro_complimentary"` with `credit_consumed = false` means the
client must release its local complimentary assumption, such as when paid access
won before final settlement.

After cutover, all public requests to `/identify`, `/identify-describe`,
`/identify-multimodal`, and `/audio-spec` must send:

```http
X-Merian-Entitlement-Protocol: 3
```

Missing or obsolete public protocol receives HTTP `426` with
`code = "client_update_required"` before provider dispatch. Authenticated
internal replay bypasses the public version check, but not ownership,
entitlement, quota, analysis-linkage, or settlement checks.

## iOS state and offline behavior

`EntitlementManager` combines an online, current-session server snapshot with
RevenueCat's paid state:

- Begin every authenticated session in unverified/free complimentary state.
- Verify `get_my_entitlement()` online once per launch for the active Supabase
  user before enabling complimentary-only modes.
- Validate account ownership, field relationships, known plan values, and a
  monotonic version before applying a snapshot.
- Buffer entitlement metadata from scan responses until the launch baseline is
  verified. A stored idempotent replay can contain an old but internally valid
  snapshot and must never establish current-launch proof by itself.
- After baseline verification, ignore any snapshot older than the installed
  `entitlement_version`. A late response cannot restore a stale balance.
- Keep Capture free of countdown UI. Show balance/exhaustion in Results and
  Settings only. Exhaustion must not redact the third stored Pro result.
- Use `canStartProFundedScan` semantics for reanalysis and new Pro-only scans;
  use functional Pro access only for eligible non-scan features.
- Preserve RevenueCat's existing paid-offline behavior. A failed online
  complimentary verification stays locked, while ordinary offline Flash queuing
  continues under the existing local meter and reconciliation flow.
- Claim a stable, account-scoped funding reservation synchronously before file
  writes or foreground inference. Subtract unresolved local complimentary
  claims from the verified server availability—even after a state-only read
  reports a hold—so one stale snapshot cannot admit the same credit twice.
- Persist funding as `funding_reservation` beside `inference_generation` in the
  scan-ingestion job metadata object. Each helper removes only its own property,
  and relaunch restores every nonterminal reservation. Active legacy jobs
  without funding metadata remain conservative blockers until their server
  state is known.
- A proven pre-dispatch local failure must first durably remove
  `funding_reservation` and set `funding_reservation_released: true`, preserving
  unrelated metadata. Only after that save succeeds may the in-memory
  reservation and advisory Flash token be released. The marker prevents a
  released legacy job from becoming an unknown blocker again after relaunch. A
  fresh funding claim removes the marker; an explicit retry of released work
  must make that claim synchronously from the persisted capture timeline before
  returning the job to automatic work.
- Mirror Flash eligibility exactly: one image, standalone audio clip, or
  description, with no video. Later eligible work blocked by an earlier local
  complimentary claim is deferred without foreground inference until one bulk
  status read proves every blocker `held` or `consumed`.
- Dispatch local complimentary reservations before paid and immediate/deferred
  Flash work so the server establishes earlier holds first. One owner-scoped
  bulk status lookup per scheduler pass supplies blocker state; no per-scan read
  loop is allowed.
- A terminal `consumed` status proves settlement but does not prove that an
  already-installed entitlement snapshot includes it. Keep the local blocker
  until a subsequent successful `get_my_entitlement()` refresh. Treat
  `released`, or a missing state after terminalization, as a reason to refresh
  and reclassify.
- After authoritative state is installed, all-`held`/`consumed` blockers select
  immediate Flash. Released capacity may promote the deferred scan to a new
  complimentary reservation; current paid proof promotes it to paid Pro. The
  new funding class must be persisted before dispatch, and paid/complimentary
  promotion refunds any optimistic advisory Flash token.
- Ambiguous outcomes retain reservations. Only proven pre-dispatch local
  failures follow the durable release sequence. HTTP 402 invalidates local
  complimentary proof until an authoritative entitlement refresh.
- On successful completion, reconcile the local reservation from both
  `plan_used` and `credit_consumed`, not the plan string alone.
- Use paid status for Profile and Explore Pro badges.

The client local daily meter remains advisory. Flash fallback is reconciled
against the authoritative server response; local clock or `UserDefaults` changes
cannot create complimentary capacity.

## Ghost-account merge

A Ghost-to-permanent merge combines history, not grants. The merge orchestrator
locks both user rows in UUID order, then
`internal.merge_ghost_complimentary_scan_usage(...)`:

1. Deduplicates identical `client_scan_id` rows, preferring `consumed`, then
   `held`, then `released` evidence.
2. Reparents distinct rows and preserves all historical consumption.
3. Derives the destination balance against one grant of three; it never adds a
   Ghost grant to a permanent-account grant.
4. Keeps only the oldest holds that fit after historical consumption and
   releases deterministic excess holds with `ghost_merge_grant_cap`.
5. Advances the destination entitlement version.

Distinct consumed history can exceed three after a merge. The derived balance
clamps at zero; historical rows are not deleted to manufacture a balance. Ledger
rows remain until account deletion.

## Authorization and security

- `internal` is not a Data API exposed schema. The rollout and usage tables have
  RLS enabled and no direct privileges for `PUBLIC`, `anon`, `authenticated`, or
  `service_role`.
- Clients cannot mutate `complimentary_entitlement_epoch`, tier, expiry, or
  version fields.
- `get_my_entitlement()` is `SECURITY DEFINER`, uses an empty search path,
  derives the caller from `auth.uid()`, and is executable only by
  `authenticated`.
- Service RPCs use an empty search path, schema-qualified objects, explicit
  `service_role` grants, and an in-body `internal.require_service_role()` check.
- Admin summary access uses the existing admin authorization boundary: Google
  identity, TOTP AAL2, active internal session, role check, and audit event.
- Function grants and RLS are independent controls. Every privileged signature
  remains registered in `internal.privileged_routine_grants` and covered by the
  catalog tests.

## Admin telemetry and incident response

The private admin route `/complimentary-entitlements` exposes only aggregates:

- accounts, active complimentary accounts, exhaustion, and
  paid-after-exhaustion;
- available-balance histogram and ledger state totals;
- total in-flight holds, holds older than 15 minutes and one hour, and oldest
  hold time;
- settlement-reason totals; and
- Flash-fallback reservation count.

AI Usage retains `pro_complimentary` and historical `pro_trial` filters. The
Overview plan split uses current user-aware entitlement; paid conversion after
exhaustion must use `is_paid`, not raw functional Pro state.

Investigate a growing stale-hold tail, completion/terminal orchestrator errors,
provider dispatch without quota commitment, unexpected direct completion-fence
rejections, elevated `426` rates after the intended client adoption window, or a
mismatch between settlement reasons and terminal ingestion outcomes. An old hold
is a recovery signal, not automatic refund authority. Prove the exact generation
durable or terminal before settling it.

## Rollout, rollback, and change procedure

The ordered release is schema in legacy mode → protocol-3-compatible dual-mode
Edge backend → verified protocol-3 TestFlight build → atomic mode/protocol-3
cutover. Expiring an older
TestFlight build is distribution cleanup only; server protocol enforcement is
the compatibility boundary.

Historical migrations are immutable. Fixes require a new forward migration.
Before cutover, leave the singleton in legacy mode and repair forward. After
cutover, prefer a forward/fail-closed remediation; reverting the singleton would
deliberately reactivate calendar-trial semantics and obsolete-client access, so
it requires explicit product, security, and incident authority in one owner
transaction.

Any change to grant size, fallback classification, state transitions, lock
order, protocol, merge behavior, paid-vs-functional gates, or settlement
classification must update this document and add corresponding migration
contract, disposable PostgreSQL, Edge route, DTO, iOS, admin, and rollout tests.

## Verification map

| Concern                                                                       | Executable source                                                                                               |
| ----------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------- |
| Migration shape, lock order, fences, merge cap, admin projection              | `services/supabase/functions/_tests/complimentaryProScansMigrationContract.test.ts`                             |
| Real overlapping hold acquisition and fourth-scan Flash fallback              | `services/supabase/functions/_tests/complimentaryScansConcurrencyDb.test.ts`                                    |
| ACLs, three holds, separate Flash quota, settlement, paid preservation, merge | `services/supabase/tests/complimentary_pro_scans_security.sql`                                                  |
| Shared reservation/linkage/metadata behavior                                  | `services/supabase/functions/_shared/complimentaryScans_test.ts`, `aiQuota_test.ts`, and ingestion helper tests |
| Four public routes and protocol translation                                   | Route-local `index.test.ts` suites plus quota-coverage inventory                                                |
| Snapshot validation, cold-launch buffering, stale response rejection          | `apps/ios/MerianTests/Core/Security/EntitlementManagerTests.swift`                                              |
| Counters, third-result persistence, paywalls, offline and badges              | Relevant AI, Analytics, Capture, Insights, Profile, and Explore iOS suites                                      |
| Admin route and public-environment security                                   | `apps/admin` test suite and database catalog contracts                                                          |

Run every gate listed in the deployment runbook against the exact source SHA. A
skipped local database test, source-only migration contract, semantic
type-check, or inability to run a simulator is not fresh-catalog, simulator,
archive, advisor, staging, or production evidence.
