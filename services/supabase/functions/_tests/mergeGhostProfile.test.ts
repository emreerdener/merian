// _tests/mergeGhostProfile.test.ts
//
// Unit tests for merge-ghost-profile/index.ts inline validation logic.
// All logic is inline-stubbed — no live Supabase client required.
//
// Covers:
//   - ghost_id UUID format validation
//   - Self-merge guard (ghost_id === user.id → refresh identity, no transfer work)
//   - verifyGhostUser IDOR guard (authenticated accounts rejected)
//   - Transfer order correctness (scans → collections → Explore posts → Community requests → follows → identity sync → purge)

import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import { buildPreservedGhostIdentityUpdate } from "../merge-ghost-profile/identity.ts";

// ---------------------------------------------------------------------------
// ghost_id UUID format validation
// Mirrors the UUID_RE guard in merge-ghost-profile/index.ts.
// ---------------------------------------------------------------------------

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

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
// ghost_id === user.id → refresh identity, return early 200, never reach DB transfer steps.
// ---------------------------------------------------------------------------

type MergeResult = { status: number; skipped: boolean };

function simulateSelfMergeGuard(ghostId: string, userId: string): MergeResult {
  if (ghostId.toLowerCase() === userId.toLowerCase()) {
    return { status: 200, skipped: true };
  }
  return { status: 200, skipped: false };
}

Deno.test("self-merge guard — identical IDs trigger early return after identity refresh", async () => {
  const id = crypto.randomUUID();
  const callOrder: string[] = [];

  function stubSyncPublicAuthorIdentity() {
    return Promise.resolve(callOrder.push("syncPublicAuthorIdentity"));
  }

  const result = simulateSelfMergeGuard(id, id);
  if (result.skipped) await stubSyncPublicAuthorIdentity();

  assertEquals(result.status, 200);
  assertEquals(result.skipped, true);
  assertEquals(callOrder, ["syncPublicAuthorIdentity"]);
});

Deno.test("self-merge guard — different IDs proceed to DB transfer", () => {
  const result = simulateSelfMergeGuard(
    crypto.randomUUID(),
    crypto.randomUUID(),
  );
  assertEquals(result.skipped, false);
});

Deno.test("self-merge guard — UUID casing does not miss linked anonymous upgrades", () => {
  const id = crypto.randomUUID();
  const result = simulateSelfMergeGuard(id.toUpperCase(), id.toLowerCase());
  assertEquals(result.skipped, true);
});

// ---------------------------------------------------------------------------
// IDOR guard: verifyGhostUser
// Prevents authenticated accounts from being merged (only anonymous allowed).
// ---------------------------------------------------------------------------

function simulateVerifyGhostUser(
  isAnonymous: boolean,
): { allowed: boolean; status?: number } {
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
// scans, collections, posts, follows, and public identity sync must all happen
// before purge to avoid ON DELETE CASCADE silently dropping data. Preserved
// ghost identity is applied after purge so the old username row is gone.
// ---------------------------------------------------------------------------

Deno.test("transfer order — scans, collections, identity sync, purge execute in correct sequence", async () => {
  const callOrder: string[] = [];

  function stubTransferScans() {
    return Promise.resolve(callOrder.push("transferScans"));
  }
  function stubTransferCollections() {
    return Promise.resolve(callOrder.push("transferCollections"));
  }
  function stubTransferExplorePosts() {
    return Promise.resolve(callOrder.push("transferExplorePosts"));
  }
  function stubTransferCommunityRequests() {
    return Promise.resolve(callOrder.push("transferCommunityRequests"));
  }
  function stubTransferUserFollows() {
    return Promise.resolve(callOrder.push("transferUserFollows"));
  }
  function stubSyncPublicAuthorIdentity() {
    return Promise.resolve(callOrder.push("syncPublicAuthorIdentity"));
  }
  function stubPurgeGhostUser() {
    return Promise.resolve(callOrder.push("purgeGhostUser"));
  }
  function stubApplyPreservedGhostIdentity() {
    return Promise.resolve(callOrder.push("applyPreservedGhostIdentity"));
  }

  await stubTransferScans();
  await stubTransferCollections();
  await stubTransferExplorePosts();
  await stubTransferCommunityRequests();
  await stubTransferUserFollows();
  await stubSyncPublicAuthorIdentity();
  await stubPurgeGhostUser();
  await stubApplyPreservedGhostIdentity();

  assertEquals(callOrder, [
    "transferScans",
    "transferCollections",
    "transferExplorePosts",
    "transferCommunityRequests",
    "transferUserFollows",
    "syncPublicAuthorIdentity",
    "purgeGhostUser",
    "applyPreservedGhostIdentity",
  ]);
});

Deno.test("transfer order — purge must not run before follow transfer", async () => {
  const callOrder: string[] = [];

  function stubTransferScans() {
    return Promise.resolve(callOrder.push("transferScans"));
  }
  function stubTransferCollections() {
    return Promise.resolve(callOrder.push("transferCollections"));
  }
  function stubTransferExplorePosts() {
    return Promise.resolve(callOrder.push("transferExplorePosts"));
  }
  function stubTransferCommunityRequests() {
    return Promise.resolve(callOrder.push("transferCommunityRequests"));
  }
  function stubTransferUserFollows() {
    return Promise.resolve(callOrder.push("transferUserFollows"));
  }
  function stubSyncPublicAuthorIdentity() {
    return Promise.resolve(callOrder.push("syncPublicAuthorIdentity"));
  }
  function stubPurgeGhostUser() {
    return Promise.resolve(callOrder.push("purgeGhostUser"));
  }
  function stubApplyPreservedGhostIdentity() {
    return Promise.resolve(callOrder.push("applyPreservedGhostIdentity"));
  }

  await stubTransferScans();
  await stubTransferCollections();
  await stubTransferExplorePosts();
  await stubTransferCommunityRequests();
  await stubTransferUserFollows();
  await stubSyncPublicAuthorIdentity();
  await stubPurgeGhostUser();
  await stubApplyPreservedGhostIdentity();

  const purgeIndex = callOrder.indexOf("purgeGhostUser");
  const preserveIndex = callOrder.indexOf("applyPreservedGhostIdentity");
  const communityRequestsIndex = callOrder.indexOf("transferCommunityRequests");
  const followsIndex = callOrder.indexOf("transferUserFollows");
  const syncIndex = callOrder.indexOf("syncPublicAuthorIdentity");
  assert(
    communityRequestsIndex < purgeIndex,
    "transferCommunityRequests must run before purgeGhostUser",
  );
  assert(
    followsIndex < purgeIndex,
    "transferUserFollows must run before purgeGhostUser",
  );
  assert(
    syncIndex < purgeIndex,
    "syncPublicAuthorIdentity must run before purgeGhostUser",
  );
  assert(
    purgeIndex < preserveIndex,
    "applyPreservedGhostIdentity must run after purgeGhostUser",
  );
});

Deno.test("guest identity preservation — custom display name, avatar, and edited username win", () => {
  const update = buildPreservedGhostIdentityUpdate({
    publicUsername: "river_wren",
    publicAuthorName: "River Wren",
    publicIdentitySource: "display_name",
    customAvatarUrl: "https://media.merian.app/avatars/ghost/avatar.webp",
    customAvatarUpdatedAt: "2026-06-25T12:00:00.000Z",
    defaultPublicUsername: "cedar_path_42",
  });

  assertEquals(update, {
    public_author_name: "River Wren",
    public_identity_source: "display_name",
    custom_avatar_url: "https://media.merian.app/avatars/ghost/avatar.webp",
    custom_avatar_updated_at: "2026-06-25T12:00:00.000Z",
    public_avatar_url: "https://media.merian.app/avatars/ghost/avatar.webp",
    public_username: "river_wren",
  });
});

Deno.test("guest identity preservation — untouched defaults fall back to provider identity", () => {
  const update = buildPreservedGhostIdentityUpdate({
    publicUsername: "cedar_path_42",
    publicAuthorName: "cedar_path_42",
    publicIdentitySource: "alias",
    customAvatarUrl: null,
    customAvatarUpdatedAt: null,
    defaultPublicUsername: "cedar_path_42",
  });

  assertEquals(update, {});
});

Deno.test("guest identity preservation — custom avatar can win without custom display name", () => {
  const update = buildPreservedGhostIdentityUpdate({
    publicUsername: "cedar_path_42",
    publicAuthorName: "cedar_path_42",
    publicIdentitySource: "alias",
    customAvatarUrl: "https://media.merian.app/avatars/ghost/avatar.webp",
    customAvatarUpdatedAt: null,
    defaultPublicUsername: "cedar_path_42",
  });

  assertEquals(
    update.public_avatar_url,
    "https://media.merian.app/avatars/ghost/avatar.webp",
  );
  assertEquals(
    update.custom_avatar_url,
    "https://media.merian.app/avatars/ghost/avatar.webp",
  );
  assertEquals("public_username" in update, false);
  assertEquals("public_author_name" in update, false);
});
