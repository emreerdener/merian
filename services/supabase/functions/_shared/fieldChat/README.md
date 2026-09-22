# Field Chat shared helpers

This directory owns the shared prompt/request, admission, and response/replay
contracts for `explore-post-chat`, `insight-chat`, and
`species-dictionary-chat`:

- `speciesKnowledge.ts`: `FIELD_CHAT_SPECIES_KNOWLEDGE_RULES` distinguishes
  general species knowledge from recorded observation evidence. Prompt builders
  append these rules after the route's context block.
- `reply.ts`: `buildFieldChatReplyRequest` constructs the existing native Gemini
  reply request; `extractFieldChatReplyJson` preserves structured-output
  decoding. The SDK dependency is type-only; the helpers perform no I/O.
- `dailyUsage.ts`: fail-closed read of the durable daily admission aggregate.
- `reservation.ts`: validated atomic admission and stale-quota recovery RPC
  adapters, plus deployment contract headers using the generated bundle
  identity.
- `response.ts`: subject-bound envelopes, canonical request pairing,
  deterministic assistant IDs, and bounded waits for completed replays.
- Colocated `*_test.ts` files preserve helper, payload, and RPC assertions.

Routes retain dispatch, admission orchestration, persistence, and their separate
summary or prompt-suggestion paths. PostgreSQL owns atomic reservation, shared
caps, and concurrency; `dailyUsage.ts` is read-side accounting, not admission.
`response.ts` still imports the existing limits and types from
`insight-chat/types.ts`. Shared AI quota and the generated
`fieldChatDeploymentIdentity.ts` remain at the parent shared root. The
[shared-owner reference](../README.md) and
[API contract](../../../../../docs/backend-and-data/05-api-contracts.md) own
those boundaries. This directory does not move Field Chat into the
identification provider abstraction.

The synthetic answer tooling imports this same request/parser. Its evaluator
still requires explicit `--live` and a paid test key; ordinary refactoring tests
use synthetic fixtures without provider calls.

Path changes affect all three generated Field Chat bundle identities, even if
helper bytes do not change. Regenerate them with
[`generate_field_chat_deployment_identity.ts`](../../../scripts/generate_field_chat_deployment_identity.ts)
and follow the
[organization verification plan](../../../../../docs/rfcs/supabase-functions-organization.md).
The existing deploy planner can select the full fleet for removed shared paths;
actual imports alone do not define deployment scope.
