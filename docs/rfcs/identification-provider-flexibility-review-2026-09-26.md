# Provider-flexibility implementation review

Date: 26 September 2026\
Reviewed runtime source: `14dfe9029`\
Branch: `codex/openai-identification-adapter`\
Disposition: Source review complete; no runtime blockers identified. Production
OpenAI assignment remains unimplemented and unqualified.

The branch is ready for source review as an evaluation-only OpenAI adapter plus
controlled evaluation infrastructure. Its runtime review covered the changes
from `480593d6d` through `14dfe9029`; the follow-up change corrects
documentation only. The optional concise-prompt experiment is closed as
inconclusive and is not a prerequisite for reviewing this implementation. No new
provider request, production change, deployment or external publication occurred
during this review.

## Findings and corrections

Two independent read-only reviews covered production/CI contracts and evaluator
execution/accounting. The primary review covered the adapter's request schema,
transport, output decoding and shared execution changes. No concrete runtime
regression or control bypass was identified.

Three documentation issues were corrected in this change:

1. The [foundation PRD](../product/03-identification-foundation-prd.md) still
   described another provider as unintegrated without dating that statement to
   the completed Gemini-only release. A dated scope note now links the separate
   evaluator and preserves the original phase's acceptance conditions.
2. The [foundation SRD](./identification-foundation-srd.md) similarly presented
   all OpenAI integration as future work. It now distinguishes local evaluation
   from future production integration while preserving historical slice facts.
3. [Adding a provider](../../services/supabase/functions/_shared/ai/ADDING_PROVIDERS.md)
   described all current model/configuration unions as Gemini-only. The
   statement now refers explicitly to production contracts and the registry; the
   separate evaluator snapshot does not grant production authority.

The earlier audit's stale paid-run status and dedicated-project prerequisite
findings are already resolved in the evaluator README and `preflight.ts`.

## Verified boundaries

| Area                             | Source owner and verified behavior                                                                                                                                                                                                                                                    |
| -------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Production assignment            | [`production.ts`](../../services/supabase/functions/_shared/ai/production.ts) composes the Gemini adapter. Production handlers use this composition, and [`registry.ts`](../../services/supabase/functions/_shared/ai/registry.ts) preserves Gemini permission/model admission.       |
| Alternative-provider composition | [`providers.ts`](../../services/supabase/scripts/identification_evaluation/providers.ts) selects OpenAI only within the local evaluator. No client field or deployment setting enables it.                                                                                            |
| Accepted evidence                | [`openaiRequest.ts`](../../services/supabase/functions/_shared/ai/openaiRequest.ts) accepts bounded prepared still photos and text. Audio, video-frame lineage and video capture metadata reject the complete observation before dispatch; evidence is not silently dropped.          |
| Transport and result contract    | [`openai.ts`](../../services/supabase/functions/_shared/ai/openai.ts) uses one fixed-origin request, redirects disabled, a deadline and a response-size bound. Strict provider output maps through the common Identify parser. Prose and diagnostics stay out of durable results.     |
| Confidence                       | The OpenAI evaluator retains an explicitly unqualified score. Its normalization does not apply Gemini candidate thresholds; production clients and persisted results retain their existing interpretation.                                                                            |
| Invocation and recovery          | [`execution.ts`](../../services/supabase/functions/_shared/ai/execution.ts) allows one invocation per prepared attempt. The evaluator controller keeps durable reservation, claim, result and settlement ordering, exclusive execution, global stops and no replay of uncertain work. |
| Spending and credentials         | The controller checks exact plan/profile/source bindings, readiness, per-run and aggregate limits before dispatch. The launcher admits only OpenAI for its single-key session and keeps the key in memory; unrelated credentials and network destinations are not admitted.           |
| Explanation evidence             | Versioned AI assessments cannot be substituted for owner or synthetic evidence. Reports disclose AI review, no independent human validation and no production qualification.                                                                                                          |
| CI                               | The candidate workflow tests the adapter with network/environment denied, and discovers evaluator, launcher and contract tests through the complete Supabase tooling gate.                                                                                                            |

## Verification evidence

- This review reran the exact network- and environment-denied adapter suite: **6
  tests passed**, with no paid calls.
- The preceding unchanged runtime revision passed the complete tooling gate:
  **438 standard tests plus 32 steps**, **58 isolated evaluator tests plus 29
  steps**, DTO/media checks and all 10 shell suites. That gate also verified the
  generated identification runtime fingerprint against the source graph.
- Earlier implementation verification retained **2,084 Edge tests plus 233
  steps**, six ignored tests, function-entrypoint type checks and **101** Deno
  configuration checks. These broader suites were not repeated for this
  documentation-only follow-up.
- The follow-up Markdown files were formatted; changed-Markdown validation,
  local-link checks, the exact functions/scripts formatter gate and diff
  whitespace checks passed.
- `skills/user/install.sh --check` reports existing drift in the two user-level
  Supabase skill links. The checked-in skills were used; personal skill links
  were not modified by this review.

This is local source evidence. It does not claim fresh hosted candidate CI,
production deployment or a qualified alternative-provider rollout. The runtime
and documentation reviews cannot establish identification quality beyond the
separate recorded experiments.

## Next implementation milestone

Prepare a provider-aware production path for still photos and descriptions,
using the existing OpenAI prompt as the candidate. Keep the optional brevity
optimization deferred. This milestone has three dependent slices:

1. **Admission and recipient permission:** extend the authoritative model/task
   assignment and quota admission together; introduce OpenAI-specific user
   permission with deny/revoke/account-switch/replay behavior. Server code owns
   provider selection, and one admitted observation has one primary call.
2. **Result and accounting compatibility:** qualify confidence interpretation,
   saved results, older clients and usage accounting; extend executable schemas
   and migrations only where required. Preserve historical Gemini results and
   duplicate-result replay without another inference call.
3. **Qualification and controlled activation:** use the existing provider
   onboarding and release procedure to establish quality, reliability, latency,
   cost, consent and rollback evidence for the accepted input set before any
   production assignment is enabled.

Audio and video-origin observations stay on their qualified Gemini path until
support for their complete evidence is implemented and qualified. A five-second
video supplies ordered image snapshots and any included companion audio; no
native-video capability is assumed and no included audio may be discarded.

The
[alternative-provider guide](../development-guides/22-alternative-identification-provider.md)
and
[provider-onboarding procedure](../../services/supabase/functions/_shared/ai/ADDING_PROVIDERS.md)
remain the implementation and qualification authorities. This review records
readiness and the proposed next work; it does not authorize deployment or more
paid comparisons.
