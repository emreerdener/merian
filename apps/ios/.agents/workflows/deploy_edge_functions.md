---
description: Deploying Supabase Edge Functions to Production
---

# 🚀 Supabase Edge Functions Deployment Runbook

Merian requires strict synchronization between the TypeScript (`services/supabase/functions/`) backend and the Swift natively parsed environment. This workflow guarantees that no regressions occur during an Edge deploy.

## Step 1: Validate TypeScript Interfaces
If you modified `merianResponseSchema` or any output JSON signatures, ensure you have already updated the Swift `InferenceEdgeDTOs.swift` file! An asynchronous crash will occur if the Deno payload fails the Codable parsing block on iOS.

## Step 2: Deno Static Analysis
Before pushing, run a local type check to ensure everything resolves cleanly.

// turbo
```bash
cd services/supabase/functions
deno check _shared/*.ts
deno check identify/index.ts
deno check enrich-scan/index.ts
```

## Step 3: Run Unit Tests (Optional but Recommended)
Test the payloads against active Supabase Ghost sessions. Ensure `.env` is properly loaded for integration blocks but never hardcoded into git.

## Step 4: Deploy All Functions
Deploying replaces the live production functions immediately. Run this from the repository root. The command requires the Supabase CLI to be authenticated via `supabase login`.

```bash
supabase --workdir services functions deploy --project-ref [YOUR_PROJECT_ID]
```

## Step 5: Verify Secret Bindings
If the newly deployed function relies on a new API Key (e.g. `GEMINI_PRO_KEY` or `GBIF_API_TOKEN`), you **must** bind it to the project securely via the CLI. It does not pull from your local `.env` automatically!

```bash
supabase secrets set --project-ref [YOUR_PROJECT_ID] NEW_SECRET_NAME=value
```

> [!CAUTION]
> Never hardcode `GEMINI_API_KEY` directly inside the `.ts` files. Always extract it via `Deno.env.get("GEMINI_API_KEY")`.

## Step 6: Post-Deploy Verification
Check the Supabase Dashboard -> Edge Functions -> Logs. Trigger a test scan in the iOS application to verify that the HTTP 200 `EdgeResponseWrapper` is returning cleanly and without CORS or 500 timeout errors.
