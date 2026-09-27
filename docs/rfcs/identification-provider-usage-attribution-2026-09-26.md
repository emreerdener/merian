# Identification provider usage attribution

Status: implemented and verified locally. Production stays Gemini.

## Problem and behavior

The durable scan trigger inferred model from the plan tier. A future provider's
result could therefore receive Gemini attribution and pricing. Admin dashboards
also displayed a sum of known costs without showing how many events had no
price.

New primary scan ledger entries take the actual model and bounded provider,
binding, policy, prompt, schema and operation references from immutable saved
provenance. SQL-null legacy results retain tier inference with an explicit
label. The canonical primary ledger operation remains `scan_identification`; the
saved execution operation is separate metadata. Existing rows, idempotent source
keys, prices, append-only rules and account anonymization remain intact.

The service writer prices only Gemini-compatible token usage with a known
modality, present prompt and candidate counts, and cached counts at most prompt
counts. An explicit unknown provider or usage contract cannot borrow a tariff by
matching a Gemini model name. Absent optional cached/thinking/tool counts retain
the existing estimate assumptions. Other native units, missing prices and
incomplete counts remain unpriced; no OpenAI tariff is introduced.

Overview and AI Usage expose priced and unpriced event counts for totals and
daily rows (also the prior period in Overview). AI Usage adds up to 50 aggregate
provider/model/attribution groups and a truncation flag. Total sums include all
filtered groups. The UI labels partial sums and shows unavailable when no price
is known; missing coverage from an older backend also shows unavailable. Cache
keys are versioned and authorization still runs before each cache read.

## Rollout and limits

Apply the migration and deploy the updated admin pages together before comparing
alternative production costs. The updated UI tolerates old backend payloads but
old pages cannot explain new partial sums. This slice adds no public API,
provider chooser, model assignment, table column or privileged grant. No
historical cost is recomputed and no observation content is added to accounting.

A future adapter still needs reviewed native-unit mapping, effective-dated
prices, cache compatibility, confidence qualification and a matched held-out
comparison. Existing failed/uncertain-call accounting gaps remain. Total token
counts across providers are not a calibrated measure of equal work. Disclosures,
supported clients and an explicitly authorized release remain activation gates.

## Verification

- Real scan-trigger tests passed for saved and legacy attribution,
  provider/model collisions, idempotent source updates and account
  anonymization. Eight SQL assertions exercise actual service writes and
  authorized admin RPCs, including unknown-price coverage, bounded groups,
  cached authorization and delimiter/null cache-key collisions.
- Fresh full migration replay passed all 62 database catalogs and 405
  assertions. Database lint was clean. Security/performance advisor error gates
  passed with the existing 103/80 warning reports.
- Complete Edge tests passed: 2,127 tests and 265 steps. All 101 deploy entry
  points passed recursive checks; whole-tree formatting/lint, isolated
  dependency graphs, generated DTOs and migration contracts passed.
- Complete tooling passed: 438 standard tests/32 steps, 58 isolated evaluation
  tests/29 steps, 19 DTO tests, 21 wire-contract tests and ten shell suites.
- Admin used Node 24.19.0 and npm 11.6.2 with a frozen install. All 27 tests,
  dependency audit (zero vulnerabilities), type check and production build
  passed. Synthetic public configuration was used; no provider or production
  credential was needed. No native or public-web runtime changed.
- Independent read-only review found a filter-cache collision, corrected with
  structural JSON encoding and real cached-RPC regression tests. The reviewer
  confirmed the fix with no remaining finding. No paid inference or hosted
  mutation ran; benchmark results and production assignments are unchanged.
