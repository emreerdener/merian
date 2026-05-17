---
description: Verify the boundary between TypeScript Edge schema and Swift Codables.
---

# 🚀 Merian API Contract Validation

Before deploying your Supabase Edge functions, it is essential to ensure that the Gemini Deno extraction schema exactly matches the JSON payloads expected by iOS `InferenceEdgeDTOs.swift`. This automated AST validation script checks for sync drifts.

## Step 1: Execute The Validation Script

// turbo-all
```bash
cd services/supabase/scripts
deno run --allow-read validate_edge_dtos.ts
```

## Step 2: Handle Mismatches
If the script outputs `❌ Validation Failed`, it means you either added a property to `index.ts` without mapping it into Swift as `let [property]: Type?`, or you removed one.

1. Open `apps/ios/Merian/Core/AI/InferenceEdgeDTOs.swift` and patch the struct boundaries immediately.
2. Re-run the validation script to verify the fix.
3. You can safely deploy using `/deploy_edge_functions` runbook once validations pass green.
