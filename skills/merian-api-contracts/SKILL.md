---
name: merian-api-contracts
description: "Coordinate and verify Merian API payload changes across Deno Edge Functions, executable schemas, generated Swift Codable DTOs, iOS domain mappings, public web, internal admin, tests, documentation, and CI. Use when adding, removing, renaming, retyping, or changing optionality or semantics of a request, response, event, webhook, or shared JSON field."
---

# Merian API contracts

Treat the executable Deno schema as the source for generated boundaries, then
regenerate, inspect the diff, and validate every consumer in that order.

## Start safely

1. Read `AGENTS.md`, inspect `git status`, and identify the contract owner,
   every producer, and every consumer before editing.
2. Read [contract-workflow.md](references/contract-workflow.md) completely.
3. For Supabase-backed payloads, load `$merian-supabase` and its applicable Edge
   reference first. For iOS or web implementation details, also load
   `$merian-ios` or `$merian-web-admin`.
4. Separate an intentional compatibility change from accidental drift. Preserve
   backward compatibility or document the explicit coordinated cutover.

## Required order

1. Change the canonical executable schema and owning implementation.
2. Run `make generate-edge-dto-contract` when the Identify Swift block is in
   scope.
3. Review the complete generated diff; do not assume generation means it is
   semantically correct.
4. Update hand-written mappings and non-generated consumers.
5. Run `make validate-edge-dto-contract`, recursive Deno checks/tests, iOS
   compile/tests, and affected web/admin tests, type checks, and builds.
6. Update API documentation and examples without copying stale production data.

Never hand-edit the generated Identify block in `InferenceEdgeDTOs.swift`.
Validation evidence does not authorize deployment.
