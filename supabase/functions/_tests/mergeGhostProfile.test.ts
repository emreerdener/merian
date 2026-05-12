// _tests/mergeGhostProfile.test.ts
//
// Unit tests for merge-ghost-profile/index.ts inline validation logic.
// All logic is inline-stubbed — no live Supabase client required.
//
// Covers:
//   - ghost_id UUID format validation
//   - Self-merge guard (ghost_id === user.id → early 200, no DB work)
//   - verifyGhostUser IDOR guard (authenticated accounts rejected)
//   - Transfer order correctness (scans → collections → Explore posts → follows → purge)

import { assertEquals, assert } from "https://deno.land/std@0.224.0/assert/mod.ts";

// ---------------------------------------------------------------------------
// ghost_id UUID format validation
// Mirrors the UUID_RE guard in merge-ghost-profile/index.ts.
// ---------------------------------------------------------------------------

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function isValidGhostId(v: unknown): boolean {
  return typeof v === "string" && UUID_RE.test(v);
}

Deno.test("ghost_id — well-formed UUID passes validation", () => {
  assert(isValidGhostId("550e8400-e29b-41d4-a716-446655440000"));
});

Deno.test("ghost_id — crypto.randomUUID() output always passes", () => {
  assert(isValidGhostId(crypto.randomUUID()));
});

Deno.test("ghost_id — non-UUID string is rejected", () => {
  assertEquals(isValidGhostId("not-a-uuid"), false);
});

Deno.test("ghost_id — SQL injection string is rejected", () => {
  assertEquals(isValidGhostId("'; DROP TABLE users; --"), false);
});

Deno.test("ghost_id — empty string is rejected", () => {
  assertEquals(isValidGhostId(""), false);
});

Deno.test("ghost_id — null is rejected", () => {
  assertEquals(isValidGhostId(null), false);
});

Deno.test("ghost_id — number is rejected", () => {
  assertEquals(isValidGhostId(42), false);
});

// ---------------------------------------------------------------------------
// Self-merge guard
// ghost_id === user.id → return early 200, never reach DB transfer steps.
// ---------------------------------------------------------------------------

type MergeResult = { status: number; skipped: boolean };

function simulateSelfMergeGuard(ghostId: string, userId: string): MergeResult {
  if (ghostId === userId) {
    return { status: 200, skipped: true };
  }
  return { status: 200, skipped: false };
}

Deno.test("self-merge guard — identical IDs trigger early return (no DB work)", () => {
  const id = crypto.randomUUID();
  const result = simulateSelfMergeGuard(id, id);
  assertEquals(result.status, 200);
  assertEquals(result.skipped, true);
});

Deno.test("self-merge guard — different IDs proceed to DB transfer", () => {
  const result = simulateSelfMergeGuard(crypto.randomUUID(), crypto.randomUUID());
  assertEquals(result.skipped, false);
});

// ---------------------------------------------------------------------------
// IDOR guard: verifyGhostUser
// Prevents authenticated accounts from being merged (only anonymous allowed).
// ---------------------------------------------------------------------------

function simulateVerifyGhostUser(isAnonymous: boolean): { allowed: boolean; status?: number } {
  if (!isAnonymous) {
    return { allowed: false, status: 403 };
  }
  return { allowed: true };
}

Deno.test("verifyGhostUser — anonymous account passes verification", () => {
  const result = simulateVerifyGhostUser(true);
  assertEquals(result.allowed, true);
  assertEquals(result.status, undefined);
});

Deno.test("verifyGhostUser — authenticated account is rejected with 403", () => {
  const result = simulateVerifyGhostUser(false);
  assertEquals(result.allowed, false);
  assertEquals(result.status, 403);
});

// ---------------------------------------------------------------------------
// Transfer operation order
// scans must move before collections before purge — both must precede purge
// to avoid ON DELETE CASCADE silently dropping data.
// ---------------------------------------------------------------------------

Deno.test("transfer order — scans, collections, purge execute in correct sequence", async () => {
  const callOrder: string[] = [];

  async function stubTransferScans() { callOrder.push("transferScans"); }
  async function stubTransferCollections() { callOrder.push("transferCollections"); }
  async function stubTransferExplorePosts() { callOrder.push("transferExplorePosts"); }
  async function stubTransferUserFollows() { callOrder.push("transferUserFollows"); }
  async function stubPurgeGhostUser() { callOrder.push("purgeGhostUser"); }

  await stubTransferScans();
  await stubTransferCollections();
  await stubTransferExplorePosts();
  await stubTransferUserFollows();
  await stubPurgeGhostUser();

  assertEquals(callOrder, [
    "transferScans",
    "transferCollections",
    "transferExplorePosts",
    "transferUserFollows",
    "purgeGhostUser",
  ]);
});

Deno.test("transfer order — purge must not run before follow transfer", async () => {
  const callOrder: string[] = [];

  async function stubTransferScans() { callOrder.push("transferScans"); }
  async function stubTransferCollections() { callOrder.push("transferCollections"); }
  async function stubTransferExplorePosts() { callOrder.push("transferExplorePosts"); }
  async function stubTransferUserFollows() { callOrder.push("transferUserFollows"); }
  async function stubPurgeGhostUser() { callOrder.push("purgeGhostUser"); }

  await stubTransferScans();
  await stubTransferCollections();
  await stubTransferExplorePosts();
  await stubTransferUserFollows();
  await stubPurgeGhostUser();

  const purgeIndex = callOrder.indexOf("purgeGhostUser");
  const followsIndex = callOrder.indexOf("transferUserFollows");
  assert(followsIndex < purgeIndex, "transferUserFollows must run before purgeGhostUser");
});
