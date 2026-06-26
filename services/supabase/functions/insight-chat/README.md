# insight-chat

Private Pro follow-up chat for completed biological Insight sheets.

## Contract

The function accepts authenticated POST requests with:

- `action: "load" | "send" | "delete"`
- `scan_id`: owned `public.scans.id`
- `message_text`: required for `send`, capped at 600 characters
- `client_message_id`: optional UUID for idempotent sends

Responses return `data.conversation_id`, ordered `data.messages`, and
`data.limits`.

## Privacy

Chat context is assembled server-side from stored text evidence only: species
names, taxonomy, hazard type, confidence, candidates/lookalikes, habitat,
Wikipedia overview, `ai_reasoning`, field notes, capture date/month, location
label, weather, elevation, and image-quality metadata.

Do not add raw image bytes, R2 object keys, cloud image URLs, Explore comments,
public post metadata, or Darwin Core export payloads to the prompt.

## Rollout and Limits

- Requires `INSIGHT_CHAT_ENABLED=true`.
- Requires effective Pro tier from `_shared/tierCache.ts`; active trials count
  as Pro.
- Uses `gemini-2.5-flash`, `maxOutputTokens: 700`, no streaming, no Google
  Search grounding, and thinking disabled.
- Caps v1 at 30 messages per scan conversation and 20 sends per Pro user per
  day.

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
