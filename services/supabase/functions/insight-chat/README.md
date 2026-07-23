# insight-chat

Private Pro follow-up chat for completed biological Insight sheets.

## Contract

The function accepts authenticated POST requests with:

- `action: "load" | "send" | "delete"`
- `action: "feedback" | "feature_feedback" | "summarize_notes" |
  "suggest_prompts"`
  for answer feedback, sheet-level feature feedback, field-note drafts, and
  AI-generated quick prompts
- `scan_id`: owned `public.scans.id`
- `message_text`: required for `send`, capped at 600 characters
- `client_message_id`: optional UUID for idempotent sends

Responses return `data.conversation_id`, ordered `data.messages`, and
`data.limits`. Each scan has at most one saved chat conversation per user.
`suggest_prompts` returns `data.prompts`, three non-persisted prompt chip
suggestions with allowlisted telemetry categories. Prompt generation is
best-effort and independent from `load` / `send`; iOS falls back to local
deterministic chips if this action fails.

## Privacy

Chat context is assembled server-side from stored text evidence only: species
names, taxonomy, hazard type, confidence, candidates/lookalikes, habitat,
Wikipedia overview, invasive flag, review/provenance state, observed traits,
ecological annotations, species group tags, `ai_reasoning`, field notes, capture
date/month, location label, weather, elevation, and image/capture-quality
metadata.

Do not add raw image bytes, R2 object keys, cloud image URLs, Explore comments,
public post metadata, or Darwin Core export payloads to the prompt.

## Rollout and Limits

- Requires durable effective Pro entitlement. Model replies, prompt suggestions,
  and field-note summaries reserve separate database quota operations before
  provider dispatch; active trials use the `pro_trial` policy.
- `client_message_id` is the idempotency key for sends. Suggestions and
  summaries accept the `Idempotency-Key` header. Local safety refusals do not
  invoke the provider and therefore do not consume AI quota.
- Uses `gemini-2.5-flash`, `maxOutputTokens: 700`, no streaming, no Google
  Search grounding, and thinking disabled.
- Each scan has one saved conversation per user, capped at 30 messages. All
  Insight chat sends share the 20 sends per Pro user per day limit.
- Quick prompt suggestions are generated asynchronously from saved text context
  and recent chat history, then regenerated after successful chat turns. Prompt
  generation does not consume the user send limit and falls back to local iOS
  suggestions if unavailable. Generated prompt text should stay short enough for
  chips and must avoid edible certainty, medical/veterinary treatment, illegal
  collection, pesticide/poison instructions, exact-location requests, and
  human-subject identification.

## Safety

The system prompt states the assistant has no raw image access and answers only
from saved scan evidence. Local deterministic guards refuse or redirect
edible/foraging certainty, medical or veterinary treatment, dangerous handling,
illegal collection, pesticide/poison instructions, and human-subject
identification.

## Verification

```bash
deno test --config services/supabase/functions/deno.json \
  services/supabase/functions/insight-chat/guards_test.ts \
  services/supabase/functions/insight-chat/prompt_test.ts

deno check --config services/supabase/functions/deno.json \
  services/supabase/functions/insight-chat/index.ts
```
