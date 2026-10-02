# Photo feature collection and review workflow

Status: implemented for offline verification on 1 October 2026. No new provider
calls, charges, reservations or biological results. This follows the
[offline preparation snapshot](identification-photo-feature-preparation-2026-10-01.md);
that record's limitations describe the earlier prototype.

The objective is to test whether explicit observations of distinguishing or
missing visual evidence improve supported identification, including broader
answers and appropriate abstention. Confidence calibration follows only after
selecting a worthwhile identification configuration. Keep the released photo
configuration: this engineering work establishes no accuracy advantage.

## Frozen comparison and decision

The proposed development screen remains 18 exposed observations, with the
explicit-primary comparator and the diagnostic-feature candidate: 36 scheduled
attempts. Both reference holds remain excluded. References are
assistant-reviewed, provisional and historically outcome-aware; they are not
independent human ground truth. Original scores, source images and the two arms'
request settings remain those of the preparation record.

The collector binds image bytes, requests, snapshots, taxonomy, current source,
pricing, visible-fact cards and reviewer assignments before dispatch. Arm order
alternates deterministically. A recorded seed shuffles review order; each image
receives an opaque token. All calls finish before review, preventing reviewers'
verdicts from changing collection.

This is a prospective amendment to the
[answerability audit's](identification-answerability-audit-2026-10-01.md)
proposed review instrument, made before any collection: **conservative double
coding replaces dispute adjudication**. Two separate slots independently code
image support, visibility accuracy and diagnostic value. Neither sees the
other's judgments. Any disagreement or unsupported, contradicted, unverifiable,
irrelevant or uninformative feature prevents gain credit. There is no third
adjudicator and no post-outcome reconciliation.

A named-answer gain additionally needs a feature both slots classify as
distinguishing among plausible lookalikes. A biological abstention gain needs
consensus on shared evidence or a correctly described unshown/unclear feature.
An unshown structure is not evidence of biological absence. Saved categorical
feature kinds and visibility support this rule without retaining feature prose.

The implemented hurdle requires all 36 outputs valid and all 18 candidate
reviews present; at least three reviewed limited-evidence gains spanning two
mechanisms; at least three net gains; at least one biological abstention gain;
no paired regressions or new subject errors; and a gain beyond taxonomy mapping
alone. Missing calls and technical failures remain in the scheduled denominator.
Passing is a development signal, never automatic advancement, provider
superiority or confidence qualification.

## Collection and privacy controls

The collector reuses the evaluator's exact-model OpenAI transport, moderation,
usage and service-tier checks. A generic trusted evaluation transport in
`_shared/ai/openai.ts` accepts the feature decoder; production admission does
not register the candidate. Generated deployment identity reflects the changed
shared source. No runtime routing or public response contract is changed or
deployed.

Each attempt is durably claimed before dispatch. Conservative reservation
includes reasoning usage and a ten-percent accounting margin. Settled spend plus
the next reservation must fit the frozen cap. Unknown execution or usage retains
the reservation and stops. Failed attempts consume their slots. No automatic
retry, replacement, budget reset or interrupted-run replay is supported.

Feature observations remain in process memory until randomized review finishes.
The local browser receives the image, frozen visible-fact card and feature
claims, without predicted name, confidence, explanation, case ID or correctness
score. Historical outcome-aware limitation/rationale text is not used as a
review card. Feature claims render as text, never HTML or instructions.

The existing ephemeral loopback review transport supplies capability-token,
host/origin, bounded-body, no-store and restrictive content-security controls.
It clears the displayed content on completion/cancellation and closes on
timeout. Only categorical receipts, digests, opaque slots and bounded result
projections are written. Image, feature, card and exact attempt-result digests
bind each receipt. This is not secure memory erasure; trusted browser/automation
operators must not save screenshots or private prose.

Reviewer IDs are only `slot-01` and `slot-02`. Any person-to-slot mapping stays
outside evaluation artifacts. `local_interactive` attests browser transport, not
an authenticated person, human validation or independence. Two callbacks or
slots alone cannot establish independent scientific review. Synthetic tests use
`synthetic`, which live execution rejects.

## Execution boundary

`evaluate_photo_features.ts --check <packet> <plan>` validates a prepared packet
and writes an immutable run manifest without credentials or network access.
`--report` reconstructs the bounded report. `--live` is separate and requires
all of the following before credential access:

- An explicit new user spending authorization; prior closed budgets stay closed.
- A plan bound to the prepared source and packet, reviewed OpenAI pricing,
  budget, retention deadline, two reviewer slots and review seed.
- A separately issued approval file under the packet's private
  `.photo-feature-approvals` directory, named by the canonical JSON hash of the
  authorization reference. Its version is `photo_feature_user_approval_v1`;
  fields bind `authorizationRef`, `runDigest`, `rootDigest`, `pricingDigest`,
  `budgetNanoUsd`, `maxCalls: 36` and `expiresAt`.
- A one-use authorization ledger that refuses relocation to a different run
  under that authorization. Pricing must have been retrieved within seven days,
  and the original retention deadline must remain valid.
- The existing hidden-input OpenAI credential setup and ready local review
  transport.

The CLI never issues approval. A trusted operator may create the private
approval artifact only after the actual user grant. It is an auditable local
record, not cryptographic proof of a conversation or a defense against a
malicious operator with filesystem access.

An offline rehearsal uses `mode: offline`, `paidServiceApproved: false`, a
clearly synthetic price fixture, and network/environment denial. These fields
cannot be flipped in an existing frozen run. Rehearsal prices and source hashes
do not authorize a paid study.

Before a paid experiment, finish an isolated reviewed source freeze, verify
current provider pricing, obtain the new spending ceiling, assign actual
reviewers and arrange the credential session. This shared dirty checkout and the
earlier preparation packet are not an isolated executable release. The retained
assets expire on 22 October 2026.

## Verification

Software verification uses synthetic providers and judgments; it does not
measure identification accuracy. Tests cover full 36-slot collection, review
ordering, transient-content exclusion, disagreement and forged credit,
exact-model transport, paired advancement, interrupted attempts, unknown
accounting, lost reviews, no replay, private directories, and
image/card/feature/snapshot/pricing/ approval binding failures. Gate results and
the real-packet offline preflight are recorded below after completion.
