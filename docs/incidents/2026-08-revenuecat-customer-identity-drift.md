# RevenueCat Customer Identity Drift and Beta Access Rollout

**Status (2026-08-09):** The P1 source corrections, durable Ghost purchase
handoff, explicit Ghost-capable beta grant, and exact empty-shell cleanup tool
are implemented. Focused TypeScript and iOS tests pass. No provider mutation has
run from this workspace: the current RevenueCat export, full Supabase Auth
audit, frozen beta/protected cohort, exact dry-run digest/count, project ID, and
server credential are still required as operation evidence.

That focused-test statement records the 2026-08-09 correction set. It predates
the account UX change below and is not evidence for its live sign-out,
RevenueCat, Apple, or Google paths.

**Account UX update (2026-08-11):** The presentation-only **Continue as Ghost**
flow is retired. User-facing **Sign out** prepares and device-persists a
server-issued StoreKit handoff before closing the linked session, binds exactly
one fresh anonymous identity, synchronizes the receipt, and succeeds only after
authoritative destination verification and server entitlement refresh. The
anonymous Profile offers **Continue with Apple** and **Continue with Google**.
Receipt-backed access follows sign-out; account-issued beta/promotional access
stays on the linked source and is not cloned. That explicit action is an
authorized rotation and does not weaken the generic-`401`
identity-preservation rule. The migration, Edge route, and iOS code are source
changes only until candidate validation, deployment, Restore-behavior review,
and live provider smokes are recorded.

## Summary

An active RevenueCat Pro entitlement and `public.users.subscription_tier =
free`
can describe the same person when RevenueCat and Supabase are looking up
different, case-sensitive App User IDs. iOS historically represented a UUID in
uppercase while PostgreSQL `uuid::text` produced lowercase. RevenueCat treats
those strings as different identifiers, and its subscriber GET creates a new
customer when the requested ID does not exist. A scheduled lookup of the empty
lowercase customer can therefore authoritatively project `free` even while the
uppercase customer remains Pro.

The mismatch and a separate iOS identity-rotation defect explain why RevenueCat
can contain far more customers than the real beta population. RevenueCat rows
can include case variants, aliases, historical test identities, `$RCAnonymousID`
values, deleted Merian users, and customer shells created by get-or-create
reads. Earlier iOS code also treated any unclassified guest `401` as a dead Auth
session, replaced the Supabase Ghost UUID, and immediately linked the
replacement UUID to RevenueCat. Repeated route failures could therefore
manufacture a chain of empty customers. Customer-count parity is not a
correctness invariant.

The long-term correction is one durable, case-exact customer identity per active
Supabase user; provider-owned Pro entitlement state; identity rotation only
after explicit user sign-out or authoritative session loss; an explicit beta
cohort; and exact cleanup of only provider shells proven empty after accidental
identity creation has stopped.

## User-visible impact

- A RevenueCat customer may show an active Pro entitlement while the matching
  Supabase profile shows `free`.
- Server-authorized Pro features, including Insight and Explore Field Chat, may
  fail closed because those routes read the durable Supabase entitlement
  projection rather than the iOS screen or RevenueCat dashboard directly.
- Editing `subscription_tier` to `pro` in Supabase appears to work briefly, but
  the next authoritative webhook or scheduled CustomerInfo reconciliation
  correctly overwrites that manual value.
- RevenueCat customer totals can continue to exceed Supabase profile totals
  without proving that a live account is duplicated or entitled incorrectly.

The beta operator has explicitly authorized cleanup of the historical shell
population. That authorization is not permission for an unfiltered bulk delete.
Purchased, promoted, aliased, active, current, or ambiguous customers remain
protected; only an exact reviewed plan that is revalidated against live
RevenueCat state may delete a proven-empty inactive shell.

## Authority model

| State                                                          | Authority                                           | Meaning                                                                                                              |
| -------------------------------------------------------------- | --------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------- |
| RevenueCat account is on the Pro developer plan                | RevenueCat project billing                          | Enables project capabilities such as integrations. It grants no Merian customer access.                              |
| App Store introductory free trial                              | Store receipt interpreted by RevenueCat             | Starts when the customer completes the store purchase flow. RevenueCat does not manually approve each trialing user. |
| RevenueCat promotional `pro` grant                             | Reviewed server-side RevenueCat mutation            | Grants immediate, finite provider entitlement without creating or modifying a store subscription.                    |
| Active RevenueCat `pro` CustomerInfo                           | RevenueCat                                          | Paid-feature source of truth for the customer identity.                                                              |
| `public.users.subscription_tier` and `subscription_expires_at` | Supabase projection of authoritative provider state | Server authorization input. These columns are not an operator-owned entitlement switch.                              |
| iOS `CustomerInfo` / `RevenueCatManager.isSubscribed`          | RevenueCat SDK cache and refresh                    | Client paid/offline presentation state. It is not the server authority for Field Chat or AI quota.                   |
| Three introductory Pro scans                                   | Private Supabase entitlement ledger                 | Separate from a RevenueCat subscription, trial, or promotional grant.                                                |

A store free trial and a promotional beta grant both yield an active RevenueCat
entitlement, but they enter the system differently. The store creates the trial
through its receipt. A promotional beta grant requires an explicit operator or
server action using a RevenueCat secret API key. Neither path is a manual
per-user approval performed by RevenueCat staff.

Once an active `pro` entitlement is projected to Supabase, it resolves as
`pro_paid` and receives the same server feature gates as a store-paid customer
for its active period. That includes Field Chat. Webhook delivery is the fast
path; the scheduled reconciler repairs missed delivery, so a short projection
delay is possible and must be observed rather than bypassed with a database
edit.

Separately, an exactly verified `pro_complimentary` functional tier also passes
the Field Chat `effective_tier = pro` gate while an available credit or active
hold remains. It does not create a RevenueCat entitlement, paid status, or beta
membership.

## Canonical customer identity

Merian's only database-generated RevenueCat App User ID is the uppercase RFC
4122 form of the current Supabase Auth UUID:

```text
123E4567-E89B-12D3-A456-426614174000
```

The invariant applies to signed-in and Supabase-anonymous Ghost sessions. A
Ghost UUID is still a custom RevenueCat ID; it is not a RevenueCat-generated
anonymous ID.

Login is optional credential linkage. User-facing **Sign out** performs a local
Supabase sign-out only after its one-use purchase proof is durably prepared.
One fresh anonymous UUID binds the proof; RevenueCat is linked to that custom
UUID, `syncPurchases()` reposts the StoreKit receipt, and the server verifies
the prepared horizon before the client clears the proof. A finite horizon that
expires while pending is revalidated against current source and destination
StoreKit state, so natural expiry can finish without masking a renewal.
Temporary failures survive relaunch and disable purchase mutations until completion. The anonymous
Profile offers **Continue with Apple** and **Continue with Google**. First-time
linkage retains the active anonymous UUID. When the provider already belongs to
another account, the provider-bound conflict flow merges the signed-out
activity into that account and restores its identity. Generic `401` responses
still cannot rotate identity.

- iOS configures RevenueCat only after a Supabase UUID exists and passes the
  uppercase UUID to `Purchases.configure` or `Purchases.logIn`.
- iOS never calls RevenueCat `logOut`, because that would manufacture a new
  `$RCAnonymousID` customer.
- PostgreSQL uses `internal.canonical_revenuecat_app_user_id(uuid)` for every
  database-generated lookup.
- Provider-supplied App User IDs and aliases remain byte-for-byte unchanged.
  They are evidence, not inputs to normalize destructively.
- `GET /v1/subscribers/{app_user_id}` is get-or-create. HTTP `200` means the
  customer existed and HTTP `201` means it was created; both are successful
  CustomerInfo responses. The promotional grant POST succeeds with HTTP `201`.

Migration `20260809055035_canonicalize_revenuecat_app_user_ids.sql` changes only
queue lookups that are provably the same UUID as their Merian user, clears any
outstanding lease on those rows, and makes them immediately due. It deliberately
preserves emails, unknown UUIDs, aliases, `$RCAnonymousID` values, and other
nonmatching identifiers.

## Root cause and contributing gaps

### Case-sensitive duplicate identity

The primary defect was a cross-system formatting mismatch: uppercase UUIDs in
iOS and lowercase UUID text generated by PostgreSQL. A get-or-create read made
the lowercase variant a real RevenueCat customer shell, after which the
reconciler could observe no active entitlement and project `free`.

### Mutable projection was used as beta membership

The original grant tool derived its candidate cohort from rows already holding
`subscription_tier = pro`, optionally excluding timed rows. That was not a safe
definition of “all current beta users” because it excluded users who had already
reverted to `free`, which are the exact accounts the repair must recover.

A Supabase profile export can contain permanent accounts and historical Ghost
profiles; its row count is not the beta population. Earlier projection
aggregates also changed as reconciliation ran. Those counts are diagnosis
evidence only and do not authorize granting every exported profile or excluding
a reviewed beta member. The repaired tool uses a separate, one-column reviewed
cohort and treats the tier snapshot only as an aggregate projection
classification.

### Generic unauthorized response rotated Ghost identity

The iOS request fallback historically treated every unclassified guest HTTP
`401` as a “zombie session.” It performed local sign-out, created a new Supabase
anonymous user, and retried. The Auth listener then configured RevenueCat with
that replacement UUID. An endpoint policy, route deployment, or configuration
error could repeat this cycle even though the original Auth user still existed.

The repaired policy preserves the active identity for every generic `401`. Ghost
replacement is permitted only when the response uses the stable
`auth_session_missing` or `invalid_session_token` contract and a Supabase SDK
refresh also fails. Anonymous-session bootstrap remains single-flight. This
keeps one install on one Ghost UUID during ordinary failures while still
recovering when Auth authoritatively no longer recognizes the session.

### New-customer success was rejected by the grant tool

> **Superseded 2026-08-13:** the RevenueCat promotional apply path described in
> this historical section is permanently retired. The script remains a
> dry-run-only cohort audit and rejects `--apply`; new beta/promotion/support
> access uses the private Supabase account-grant ledger and an immutable
> identity-free operation receipt.

The original grant tool accepted only HTTP `200` from its preliminary
CustomerInfo GET. RevenueCat documents HTTP `201` as success when that GET
creates the canonical customer. The repaired client accepts both statuses, still
requires promotional POST `201`, and validates that the bounded response
contains an active entitlement.

### Guest-to-existing-account provider continuity

The normal OAuth link preserves the Ghost Supabase UUID, so the RevenueCat
custom ID does not change. The existing-account conflict fallback is different:
it merges the Ghost profile into a different permanent Supabase UUID and then
switches RevenueCat from one non-anonymous custom ID to another.

RevenueCat documents non-anonymous custom-ID-to-custom-ID `logIn` as an account
switch with no merge or purchase transfer. The Supabase database merge therefore
cannot treat `logIn` or its destination reconciliation row as provider handoff
evidence.

Ghost purchasing is an intentional product requirement. Purchase, restore, and
offer-code redemption therefore require an exactly linked stable Supabase UUID
and a matching recognized `account_kind`, accepting both `anonymous` and
`authenticated`. The normal OAuth link upgrades the existing Ghost in place, so
the UUID and RevenueCat customer do not change.

The conflict fallback now provides both parts of the handoff:

1. After the database transaction commits, the Edge function reads authoritative
   source and destination CustomerInfo. If the source has active functional Pro,
   it mirrors the exact finite horizon—or lifetime state—to the destination and
   verifies that the destination covers it. Missing secrets, provider failures,
   malformed state, or failed verification return retryable
   `purchase_handoff_pending` and leave the source Auth user intact.
2. After the durable server completion, iOS calls `syncPurchases()` while linked
   to the destination. Under the required RevenueCat **Transfer to new App User
   ID** behavior, that transfers the real store receipt. The device-only handoff
   queue remains until provider synchronization, local evidence rebinding, and
   verified queue removal all succeed.
3. If the client disappears after the database commit, the service worker
   repeats the same provider access preservation before deleting the obsolete
   source Auth shell. It never deletes the source RevenueCat customer.

The promotional mirror closes the receipt-independent gap, while receipt sync
preserves later store renewals. Beta grants therefore accept both active
Supabase-anonymous Ghost users and linked users. Store transfer behavior still
depends on the RevenueCat project setting and must be exercised in staging.

## Containment rules

Until every exit criterion is complete:

1. Do not restore or bypass the retired `grant-beta-pro` provider mutation.
   Account-owned access must use the reviewed `grant-account-access` dry-run and
   exact-plan database operation.
2. Do not call the canonical-ID/beta rollout production-ready.
3. Preserve the exact iOS identity/account-kind fence and the grant tool's
   reviewed-cohort/Auth-evidence gate. Ghost store purchases remain allowed;
   generic authorization failures must never rotate their UUID.
4. Do not edit `public.users.subscription_tier`, expiry, or entitlement version
   as entitlement repair.
5. Do not use the dashboard to bulk-delete customers. Use only the exact
   `cleanup-revenuecat-shells` dry-run/apply contract below; preserve every row
   with purchase, promotion, alias, active-user, recent-use, or ambiguous
   evidence.
6. Never mutate Supabase users, Auth users, the reconciliation queue, webhook
   ledger, or app data as part of RevenueCat shell cleanup.

If customer access must be restored before the automated rollout is repaired,
use a separately reviewed, exact-customer RevenueCat promotional grant with a
finite expiration and retained operator evidence. This is a production provider
mutation and requires explicit target and cohort authorization. Do not
substitute a database edit.

## Explicit beta cohort contract

Beta membership must be represented by a frozen, reviewed list of canonical
Supabase UUIDs. It must not be inferred from current entitlement state.

Before any apply-capable tool can be used, it must:

- accept an explicit cohort artifact whose only authority-bearing field is the
  intended Supabase user UUID;
- canonicalize UUIDs to uppercase and reject malformed or duplicate rows;
- report the cohort artifact checksum, exact candidate/authenticated counts, and
  exact verified Ghost/linked counts, and aggregate projection counts without
  printing identities;
- classify permanent, timed, and free Supabase projections without using them to
  silently remove an approved member, and reject a missing projection;
- require `auth_exists=true` for every cohort identity and accept both strict
  `auth_is_anonymous=true` Ghosts and `auth_is_anonymous=false` linked users;
- prove that no ID outside the reviewed cohort can receive a RevenueCat request;
- use a finite, uniformly reviewed expiration; and
- retain an identity-bearing results ledger only in restricted operator storage.

Changing the cohort or expiration after a partial attempt creates a new
operation. Preserve and reconcile the first results ledger before authorizing
another apply.

## Code, test, and release evidence

The historical source-level P1 corrections below were implemented before the
provider apply path was retired. They remain evidence about the incident, not a
supported mutation contract:

1. CustomerInfo GET `200` and `201` are accepted, promotional POST still
   requires `201`, and the grant response must contain an active entitlement.
2. Tests cover new-customer GET `201` followed by exactly one POST,
   already-active skip, rejected POST `200`, bounded retry, and secret-free
   failure output.
3. Candidate selection consumes an exact one-column cohort, includes reviewed
   free/timed/permanent projections, and rejects malformed, duplicate, missing,
   or nonexistent Auth identities while reporting Ghost and linked counts
   separately.
4. Tests prove dry-run performs zero requests and an ID outside the explicit
   cohort never reaches the RevenueCat request boundary.
5. iOS purchase, restore, and offer-code redemption accept the exact linked
   stable Ghost or permanent Supabase identity, reject unknown or stale
   account-kind linkage, and ignore results if identity changes while an SDK
   operation is suspended.
6. A generic guest `401` preserves the current UUID. Focused recovery policy
   tests allow replacement only for a stable missing-session response, a failed
   SDK refresh, and a current anonymous session.
7. Ghost conflict merge tests prove source/target CustomerInfo reads, exact
   finite and lifetime access mirroring, already-covered/free idempotency,
   verification failure, and fail-closed Auth cleanup. iOS tests prove
   `syncPurchases()` occurs before the durable handoff can be removed.
8. Empty-shell cleanup tests prove zero-request dry-run, duplicate-input
   rejection, protected current/Auth/cohort/history/alias identities, live
   last-seen revalidation, exact plan digest/count confirmation, and
   deletion-only results with no Supabase mutation.

The production hold still requires evidence that source-only checks cannot
provide:

9. A disposable PostgreSQL replay must apply the complete migration fleet and
   all catalog tests under the pinned Supabase CLI. Static SQL tests alone are
   not migration evidence.
10. Staging must exercise a brand-new canonical customer, an existing active
    customer, a reverted beta customer, a duplicate invocation, a webhook delay,
    a Ghost purchase, generic-`401` identity preservation, and both normal Ghost
    upgrade and existing-account conflict restore behavior. The exact cleanup
    batch additionally requires fresh production exports and live provider
    revalidation; staging fixtures do not authorize production customer IDs.

## Supervised rollout after the hold closes

This sequence requires explicit authorization for the resolved production
Supabase project, RevenueCat project, exact cohort, expiration, and maintenance
window.

1. Retain a fresh Supabase user export and RevenueCat customer export in
   restricted operator storage. Run the offline audit and retain its aggregate
   summary plus identity-bearing review artifact separately.
2. Freeze the explicit beta cohort, expiration, source checksum, candidate
   count, and exact candidate revision. Run the repaired grant tool in dry-run
   mode and require zero external requests.
3. Confirm the RevenueCat webhook, HMAC, server API key, reconciliation monitor,
   and pre-cutover queue health are normal.
4. Pause only `reconcile_revenuecat_subscribers_every_fifteen_minutes` for the
   bounded maintenance window. Record its exact prior schedule. This prevents
   the migration's immediately due canonical rows from reconciling before grants
   exist.
5. Deploy the canonical-ID migration through the normal exact-SHA production
   workflow. Do not edit the migration or queue rows interactively.
6. Apply the approved promotional cohort. Require GET `200|201`, POST `201` for
   each missing grant, zero unexplained failures, and the exact reviewed
   expiration.
7. Verify a sample and aggregate projection: authoritative CustomerInfo is
   active, webhook or targeted reconciliation advances Supabase to Pro, and
   Field Chat admits an eligible completed scan/post. Do not print identities
   into release artifacts.
8. Restore the exact reconciliation schedule and require the due backlog and
   oldest-due age to recover below monitor thresholds.
9. Release the custom-ID-only iOS build containing the exact stable-identity
   purchase fence and generic-`401` preservation only after staging proves them
   and the backend state is healthy.
10. After new identity rotation has stopped, generate a fresh shell-cleanup plan
    from the four independent artifacts below. Review its identity-bearing CSV,
    freeze its candidate SHA-256 and exact count, then apply that exact batch.
    Require every result to be `deleted`, `queued`, `already_absent`, or
    `protected_live_evidence`; investigate any `failed` row before a new plan.

If grant apply partially fails, keep the maintenance decision explicit. Correct
and retry only the failed identities using the retained ledger. If the window
cannot be completed safely, restore the reconciler so ordinary subscription
correctness resumes, retain all evidence, and leave the beta rollout incomplete.
Never keep an unrecorded cron pause or clear queue state to make health green.
Grant and cleanup results are separate identity-bearing ledgers and must never
be silently combined or inferred from one another.

## Exact empty-shell cleanup contract

Create the cleanup plan only from four fresh, independently retained inputs:

1. the complete `public.users` CSV export;
2. the complete `audit-ghost-users --snapshot-csv` Auth/public evidence;
3. RevenueCat **Customers → All customers → Export all**; and
4. a nonempty, reviewed one-column `id` CSV containing every beta or otherwise
   protected customer, including Ghost users.

Dry-run is network-free and hashes all four source artifacts, the inactivity
threshold, the current-Supabase-shell flag, and the stable candidate identity
and evidence fields. The display-only `inactive_days` value is excluded so the
authorization digest cannot drift merely because wall time advances. By default
it excludes canonical current Supabase customers and protects every active Auth
UUID, reviewed cohort member, linked alias, row with purchase/promotion or
customer-attribute evidence, recently seen row, and row with missing recency.
`--include-current-supabase-shells` is an exceptional separate operation for an
inactive `public.users` row whose full Auth audit proves `auth_exists=false`; an
active Auth UUID remains protected even with the flag. It is not part of the
initial historical-duplicate cleanup.

Apply requires `--apply --confirm-delete-empty-revenuecat-shells`, the exact
dry-run `--approved-plan-sha256`, exact `--confirm-count`, an identity-bearing
`--results-csv`, the exact RevenueCat project ID, and an `sk_` server key.
Before each delete it uses the dedicated local-only
`REVENUECAT_CLEANUP_V2_API_KEY` and revalidates the exact project/customer,
requires that live `last_seen_at` is no newer than the reviewed export and
remains outside the inactivity window, requires no active entitlement or
customer attribute, requires a complete self-only alias list, and requires
complete empty V2 subscription, purchase, and customer-event lists. It never
calls the V1 get-or-create subscriber endpoint. A changed or ambiguous response
protects the row; the tool never writes Supabase.

RevenueCat dashboard exports currently truncate `last_seen_at` to a whole second
even though they encode it as epoch milliseconds; the live V2 customer response
can restore the original millisecond remainder. Revalidation accepts only that
remainder of the same exported second. Any later second, or any live timestamp
inside the inactivity window, remains protected. The result ledger uses separate
stable codes for identity, recency, active-entitlement, attribute, alias, and
history evidence.

### 2026-08-10 prelaunch cleanup execution note

The first reviewed provider-only batch contained 188 candidates and protected
all 269 current Auth UUIDs. Apply deleted one verified empty shell, protected
187 at the initial customer-state boundary, failed none, and made no Supabase
mutation. Aggregate inspection showed that all 187 shared the same boundary; the
frozen export stored each candidate timestamp at `.000Z`, exposing the
whole-second export versus live-millisecond precision mismatch above.

The validator was corrected and regression-tested at both edges: a live value up
to `+999 ms` within the reviewed second proceeds to the remaining evidence
checks, while `+1,000 ms` fails closed as newer activity. The plan digest was
also corrected to bind the exact four sources and selection configuration while
excluding derived age. The replacement dry-run retained the identical 188
customer IDs and stable evidence fields. Preserve the first apply ledger; any
retry uses a separately named ledger and the replacement plan digest.

The replacement apply then deleted 154 additional verified-empty shells,
confirmed the first deletion as already absent, protected 33, failed none, and
again made no Supabase mutation. Aggregate-only review classified 32 protected
rows as customers with non-self alias groups and one as a customer with
attributes. Those 33 are not empty-shell deletions: retain them until a separate
read-only alias/attribute review proves the complete customer relationship and
defines an independently approved operation. Across both passes, 155 provider
shells were deleted with zero failed requests.

A fresh dashboard export after both passes reconciled exactly: the original 435
rows minus 155 deleted IDs plus four newly materialized canonical customers
equalled 284 rows. The removed set exactly matched the two deletion ledgers, no
deleted ID repopulated, and all 33 protected IDs remained. Each of the four new
rows was the uppercase canonical RevenueCat form of a pre-existing Supabase
UUID, not a new Supabase user; this is expected output from the deployed
canonical reconciliation repair. The fresh read-only audit reported 284
RevenueCat rows, 269 Supabase users, 152 exact canonical-customer matches, five
case-variant rows, 119 unknown UUID rows, seven `$RCAnonymousID` rows, one other
unlinked alias, five duplicate identity groups, and 36 review rows.

The post-cleanup offline shell plan still selects 33 old unknown UUIDs because a
dashboard export cannot prove their live provider relationships. Do not apply
that plan: the preceding live pass already proved 32 have non-self alias groups
and one has customer attributes. Three additional review rows are inactive
case-variant members of two-row Supabase identity groups and remain protected by
the current Auth cohort. A new deletion operation requires new live evidence and
separate authorization; the fresh export alone is verification, not authority.

The coordinated Supabase cleanup was then rerun in dry-run mode with the fresh
284-row provider export, the same 269-row Auth audit, and the conservative
protected cohort containing every current Auth UUID. Five old empty Ghosts met
the database-audit age/content rules, but zero passed the independent provider
gate, so the selected count remained zero. No current Supabase/Auth deletion is
authorized by this evidence. Reducing the 269 current Auth identities to the 29
known TestFlight humans would require either an independently proven exact UUID
cohort or an explicitly approved prelaunch data reset; dashboard counts and
simulator-looking platform versions are not identity proof.

The product owner subsequently authorized the exceptional RevenueCat-only
prelaunch project reset and asserted that the app has not launched publicly and
that no provider transaction or customer is real. This authority does not extend
to Supabase/Auth deletion. The retained post-cleanup export contains 284 exact
customers in dashboard project `49ebd1c2`, has SHA-256
`99a241dac9082c23adde45ddfd94657e3ede1804739ae34547dc5b521ee0175f`, and maps to
V2 project `proj49ebd1c2`. The reset dry-run selected all 284 rows, reported
five with purchase or entitlement evidence and 191 with customer attributes, and
produced plan SHA-256
`006f141f5deca54c16970f7430254025f34e1db9a0b2748c8ade2cd1fde2a4de`. Those
evidence rows are included intentionally under the recorded synthetic-data
assertion; this is erasure, not empty-shell deduplication.

Apply completed at `2026-08-10T20:51:05.083Z`. All 284 exact planned customers
returned `deleted`; none were queued, already absent, or failed, and the ledger
contains 284 unique App User IDs with no error code. The result summary has
SHA-256 `866ebf92e88e119e3e35a5083be9be57a8caf8d28e75bbb9f2fd02f27da5f0f8`;
the identity-bearing results CSV has SHA-256
`6abba60bc8bc766e9fd533cff47c89a1a9f77467f2bd9ed1365da103ad6b3494`.
The terminal summary records `supabase_mutations=false`.

The completed reset remains snapshot-bound. It issued no Supabase request and
could not delete a RevenueCat customer created after the export. SDK
identification and the deployed reconciler may recreate empty or canonical
provider customers during or after apply, without restoring erased aliases,
attributes, promotions, or history. Preserve the separately named apply ledger,
take a fresh post-reset export, and revoke the temporary reset key. Any remaining
or newly created customers require a new reviewed snapshot and digest.

The immediate follow-up export had SHA-256
`9c53cf3568380bc2bb00df0d6a53703cc4ab042ec6f2403bfff12c86d7085d0c`
and temporarily returned eight rows: seven Test Store fixtures and one App Store
Ghost, with no purchase or entitlement evidence. All eight were exact matches
to the approved snapshot, including unchanged first/last-seen timestamps, and
all eight had terminal `deleted` entries in the apply ledger. A subsequent
RevenueCat dashboard refresh settled to zero customers without a second apply,
confirming provider/export propagation rather than new activity. No pass-two
deletion was executed.

Deletion remains permanent provider erasure. A later SDK or get-or-create read
may make a new empty shell with the same ID, but it will not recover deleted
aliases, attributes, promotions, or history. That is why the apply boundary
for normal empty-shell cleanup deletes only customers already proven to have
none of those things. The exceptional full prelaunch reset above instead relied
on the explicit synthetic-data assertion and exact project-wide snapshot.

## Coordinated empty Ghost cleanup

Cleaning Supabase identities is a different operation from deleting
RevenueCat-only shells. Preserve every real Ghost: anonymous users may purchase,
remain anonymous for their lifetime, later link an OAuth identity without
changing their UUID, and log out without rotating that identity. A high row
count never authorizes deletion, and two Ghost UUIDs are never merged merely
because they look inactive.

The current coordinated procedure is deliberately ordered:

1. Freeze identity-rotation defects and retain fresh Auth/public audit,
   RevenueCat export, and a nonempty protected beta/team cohort.
2. Run the provider-only cleanup in dry-run mode if an initial orphan inventory
   is useful, but do not apply RevenueCat deletion yet.
3. Run `cleanup-ghost-users` offline. Its Supabase candidates must be old,
   anonymous, free, identity-free, activity-free, and outside the protected
   cohort. Their canonical RevenueCat row must be absent or a single inactive
   empty customer; purchase, promotion, customer-attribute, alias, case-variant,
   multi-customer, recent, or unknown provider evidence excludes the Supabase
   account.
4. Execute only the reviewed digest/count. For each candidate, the tool calls
   `inspect_empty_ghost_cleanup_candidate`, reserves the Ghost/merge lock, and
   performs live RevenueCat **GET-only** V2 customer, alias, subscription,
   purchase, and event checks. It then calls
   `request_empty_ghost_account_deletion`; it never calls Auth Admin delete,
   directly deletes `public.users`, calls the V1 get-or-create endpoint, or
   deletes a RevenueCat customer.
5. The database reruns the complete reference guard and atomically enters the
   normal relational, R2 storage, provider, and Auth deletion state machine.
   Auth remains recoverable until delayed storage verification is complete.
6. Wait for every accepted account-deletion job to complete. Generate fresh
   exports, then run the provider-only cleanup again for newly orphaned empty
   shells.

The database guard treats every reviewed current or future user foreign key as a
blocker by default. It additionally blocks recent Auth sessions, logical
references without foreign keys, active merge/deletion state, custom profile
state, and any Field Trip state other than the exact automatically created,
untouched Backyard Safari Level 1 baseline. Schema drift or an unread audit
source fails closed. The private deletion receipt stores only the reviewed plan
hash, RevenueCat project, recent verification timestamp, checked-customer count,
and durable deletion-job ID.

`internal.entitlement_rollout_config.entitlement_mode = 'legacy_trial'` is
orthogonal to this cleanup. It means the resolver may give a newly created free
profile the legacy seven-day effective trial; it neither identifies beta members
nor creates a RevenueCat entitlement. Do not change that configuration as a
cleanup side effect. Beta access remains the explicit, finite promotional grant
for the reviewed cohort until a separately validated entitlement-policy rollout
replaces it.

## Customer deletion policy

RevenueCat customer deletion is permanent data erasure, not deduplication.
Deleting a customer clears provider data and purchase history; it does not
cancel an Apple subscription. A later subscriber GET can recreate an empty
customer shell, and an SDK/store flow may separately re-observe a live receipt.
Neither is recovery of the deleted customer or its aliases, attributes,
RevenueCat-only promotions, and historical evidence.

Deletion is permitted for an exact test identity, a verified privacy-erasure
request under the separate account-deletion process, the beta-authorized
empty-shell batch produced and live-revalidated by `cleanup-revenuecat-shells`,
or an explicitly owner-authorized full prelaunch provider reset after every
provider row is asserted synthetic. A high dashboard count, UUID case
difference, old timestamp, or absent Supabase profile is never sufficient by
itself. The exact plan digest/count and retained results ledger are the deletion
authority. A full prelaunch reset is not an acceptable live production cleanup
path.

## Recovery and rollback

- Revoke or correct an erroneous beta grant in RevenueCat for the exact
  customer. Let webhook/reconciliation project the result; do not write the
  database tier directly.
- If the canonical migration exposes unexpected queue state, preserve claims and
  history, contain only the named worker if necessary, and prepare a forward
  migration. Never rewrite an applied migration.
- If the iOS identity policy is faulty, stop the affected sign-in or purchase
  path with a forward client/server control. Do not call RevenueCat logout or
  manufacture anonymous IDs.
- Preserve RevenueCat and Supabase exports, the dry-run summary, apply results
  ledger, exact SHA, migration evidence, monitor links, and schedule restoration
  evidence.
- A customer deletion has no rollback. If apply protects or fails a row, leave
  it intact, inspect the retained evidence, and generate a new reviewed plan
  only after the reason is understood.

## Exit criteria

The incident can be closed only when:

- every required code and test correction above is green on one exact SHA;
- the disposable migration/catalog gate passes under Supabase CLI `2.109.1`;
- the production migration version is recorded and the canonical queue invariant
  is verified read-only;
- every approved beta member has the intended active provider entitlement or a
  reviewed terminal explanation;
- Supabase projection and RevenueCat CustomerInfo agree for the sampled and
  aggregate cohort;
- Field Chat succeeds for an entitled completed-scan and completed-post fixture;
- Ghost purchasing works without account creation; with Supabase and RevenueCat
  reachable and RevenueCat Restore behavior set to **Transfer to new App User
  ID**, explicit sign-out of an active StoreKit subscriber completes with
  exactly one replacement anonymous identity and matching custom RevenueCat ID,
  never a `$RCAnonymousID`, and preserves the prepared entitlement horizon in
  Supabase; a promo-only source does not clone access; forced prepare,
  Keychain-persist, anonymous-bootstrap, receipt-sync, completion, and
  entitlement-refresh failures retain the correct session/proof and surface an
  incomplete transition; relaunch resumes a bound proof even after its pre-bind
  expiry timestamp; normal first-time OAuth linking retains the same UUID;
  generic `401` responses do not rotate it; and both Apple and Google
  existing-account conflict paths have a proven provider handoff in separate
  clean sign-out cycles;
- the reconciliation cron is restored and health remains normal through the
  agreed observation window; and
- every normal cleanup candidate has a retained terminal result, with no
  purchase-bearing, aliased, active, recent, or ambiguous customer deleted; any
  exceptional full prelaunch provider reset instead has its owner assertion,
  exact snapshot/digest/count, terminal ledger, and fresh post-reset export.

“Implemented in source,” “validated against a disposable catalog,” “applied to
production,” “provider grants complete,” “iOS released,” and “customer paths
verified” remain separate evidence states.

## References

- [RevenueCat API v1: get/create customer and promotional entitlements](https://www.revenuecat.com/docs/api-v1)
- [RevenueCat API v2: live customer, alias, and exact deletion boundaries](https://www.revenuecat.com/docs/api-v2)
- [RevenueCat customer identity and `logIn` behavior](https://www.revenuecat.com/docs/customers/identifying-customers)
- [RevenueCat webhook event types](https://www.revenuecat.com/docs/integrations/webhooks/event-types-and-fields)
- [RevenueCat project restore behavior](https://www.revenuecat.com/docs/projects/restore-behavior)
- [RevenueCat programmatic purchase synchronization](https://www.revenuecat.com/docs/getting-started/restoring-purchases)
- [RevenueCat customer deletion](https://www.revenuecat.com/docs/dashboard-and-metrics/customer-profile#delete-customer)
- [Supabase deployment runbook](../backend-and-data/06-supabase-deployment-runbook.md#revenuecat-webhook-release-gate)
- [Revenue and Identity Management](../features-and-hardware/02-revenue-and-identity.md)
