# App-controlled identification input routing — 26 September 2026

Status: implemented and verified locally. No deployment or provider activation
is included.

## Decision

Naturebook's backend chooses the provider/model assignment. End users cannot
select a provider. Their permission controls whether the app may send data to
the selected recipient; declining it blocks the request, without automatic
fallback. Every current assignment remains Gemini. OpenAI collection and
production dispatch remain disabled.

## Implementation

The four HTTP producers build the same canonical requests before reservation. A
shared classifier validates all included evidence and derives a structural input
profile. It preserves separate description, image and audio compatibility
variants, plus primary descriptions, photos, audio, photo/audio, sampled video
frames and video with audio. Capture context and lineage conservatively prevent
video-derived evidence from qualifying as photo-only. This is classification of
accepted representation, not verification of capture origin or biological truth.
No native video enters the model request. No evidence is dropped or split into
extra provider calls.

The nine-argument service-only `reserve_identification_quota` overload accepts
that derived profile, then matches a private route against the admitted
operation, plan, model and policy version. All rows are Gemini. The profile is
saved with the per-attempt assignment; historical rows remain null. Edge checks
returned equality, then the registry recomputes it before provider preparation.
Caller-supplied provider/model/profile extras do not choose the assignment.

Migration `20260926174645_add_identification_input_routing.sql` extracts both
existing quota algorithms into private invoker routines with no API-role grants.
They retain the existing quota, locking and entitlement logic. Legacy public
quota ABIs retain their Gemini consent check. The new identification RPC checks
the selected recipient in the same transaction as its quota effects: missing
policy or denied consent rolls back counters and complimentary holds.

A duplicate live/committed request keeps its original replay semantics even if
its new input differs. A new metered retry must keep any previously recorded
input profile. Failed/unknown attempts do not authorize fallback, and completed
results replay without inference. Older workers retain their eight-argument ABI
and `legacy_v1` policy lane.

## Activation boundary

Apply migrations before the matching Edge bundle through the existing exact-SHA
release procedure. A missing new RPC does not fall back to the old one. This
slice changes no public Identify DTO, Swift model, model prompt, confidence
threshold, pricing policy or active provider.

Before assigning OpenAI, implement recipient-specific client consent recovery
and compatible-client gating, qualify the exact input/model/configuration and
confidence interpretation, and extend model admission and versioned result
provenance together. The existing evaluation adapter accepts primary photo/text;
it is not qualified for compatibility endpoints or sampled video. A catalog row
alone cannot enable it. See
[Adding a provider](../../services/supabase/functions/_shared/ai/ADDING_PROVIDERS.md).

## Validation

The final local candidate passed:

| Gate                                                | Evidence                                                                                                                             |
| --------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| Clean disposable migration replay                   | All migrations, including the new routing migration                                                                                  |
| Complete database catalogs                          | 57 files, 393 assertions                                                                                                             |
| Complete Edge suite with local database concurrency | 2,105 tests and 250 steps                                                                                                            |
| Migration contracts                                 | 350 tests across 62 discovered files                                                                                                 |
| Supabase tooling                                    | 438 standard tests, 58 isolated evaluation tests, 19 and 20 DTO tests, 10 shell suites                                               |
| Runtime type/dependency checks                      | All 101 entrypoints, 101 isolated graphs and generated Deno configs                                                                  |
| Routine privilege audit                             | 261 public definer routines, zero violations; internal cores denied to all API roles                                                 |
| Database lint                                       | No warnings or errors                                                                                                                |
| Advisors                                            | Zero errors; 105 security and 80 performance warnings unchanged from the prior slice                                                 |
| Source format/lint and generators                   | Recursive functions/scripts gates, changed Markdown formatting, regenerated identification and Field Chat identities, DTO validation |

The reviewed replay regression is fixed and covered for reserved and committed
duplicates with changed input. Handler tests prove that provider/model/profile
extras cannot select an assignment, including legacy descriptor-less video
snapshots. Tests also cover missing policy, denied/revoked recipient permission,
atomic rollback of complimentary holds and counters, new-attempt profile
fencing, and legacy API compatibility.

The task-owned `merian-routing-check` database was removed after verification;
unrelated local databases were preserved. The reviewed checked-in Supabase
skills were used. The pre-existing user-level skill-link check still reports
drift and those global links were not changed.

No iOS build was needed or run: this slice changes no Swift source or public
Identify DTO. No paid evaluation, live model request, hosted mutation, push or
deployment was performed. These local gates establish behavior and integration
contracts; they do not establish alternative-provider quality or product
latency.
