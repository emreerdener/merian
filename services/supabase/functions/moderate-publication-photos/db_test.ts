import { assert, assertEquals, assertRejects } from "@std/assert";
import type { SupabaseClient } from "@supabase/supabase-js";
import { publicationModerationWorkerRepository } from "./db.ts";
const id = (n: number) =>
  `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
const hint = { owner_id: id(1), observation_id: id(2), operation_id: id(3) };
const source = {
  media_id: id(5),
  object_id: id(6),
  content_type: "image/jpeg",
  byte_count: 3,
  sha256: "a".repeat(64),
};
const claim = () => ({
  claimed: true,
  ...hint,
  work_token: id(4),
  work_expires_at: "2026-10-04T15:00:00Z",
  ip_hash: "b".repeat(64),
  sources: [source],
  request: {
    schema_version: 1,
    operation_id: id(3),
    observation_id: id(2),
    analysis_id: id(7),
    expected_observation_revision: 1,
    expected_review_revision: 0,
    taxonomy_version_id: id(8),
    initial_taxon_id: null,
    note: null,
    media_ids: [id(5)],
  },
});
function client(
  handler: (
    name: string,
    args: Record<string, unknown>,
    signal: AbortSignal,
  ) => unknown,
) {
  return {
    rpc: (name: string, args: Record<string, unknown>) => ({
      abortSignal: (signal: AbortSignal) =>
        Promise.resolve({ data: handler(name, args, signal), error: null }),
    }),
  } as unknown as SupabaseClient;
}
Deno.test("moderation worker validates durable scope and drops saved private request and IP", async () => {
  const calls: Record<string, unknown>[] = [];
  const db = publicationModerationWorkerRepository(
    client((name, args, signal) => {
      assert(signal instanceof AbortSignal);
      calls.push(args);
      return name === "list_observation_publication_work"
        ? [hint]
        : name === "claim_observation_publication_work"
        ? claim()
        : null;
    }),
  );
  const signal = new AbortController().signal;
  assertEquals(await db.list(signal), [hint]);
  const work = await db.claim(hint, signal);
  assert(work);
  assertEquals(work, {
    scope: { ...hint, work_token: id(4) },
    sources: [source],
  });
  assert(Object.isFrozen(work.sources[0]));
  await db.release(work, signal);
  assertEquals(calls[2], {
    p_owner: id(1),
    p_observation: id(2),
    p_operation: id(3),
    p_work: id(4),
  });
});
Deno.test("moderation worker denies malformed scope, order and private recovery fields", async () => {
  for (
    const change of [
      { owner_id: id(99) },
      { operation_id: id(99) },
      { work_token: "bad" },
      { ip_hash: "raw ip" },
      { work_expires_at: "bad" },
      { sources: [{ ...source, media_id: id(99) }] },
      { claimed: false, work_token: id(4) },
    ]
  ) {
    const db = publicationModerationWorkerRepository(
      client(() => ({ ...claim(), ...change })),
    );
    await assertRejects(() => db.claim(hint, new AbortController().signal));
  }
  for (
    const rows of [Array(11).fill(hint), [{ ...hint, work_token: id(4) }], null]
  ) {
    await assertRejects(() =>
      publicationModerationWorkerRepository(client(() => rows)).list(
        new AbortController().signal,
      )
    );
  }
});
Deno.test("moderation worker expired caller cannot begin database work", async () => {
  let calls = 0;
  const db = publicationModerationWorkerRepository(client(() => {
    calls++;
    return [hint];
  }));
  const controller = new AbortController();
  controller.abort();
  await assertRejects(() => db.list(controller.signal));
  assertEquals(calls, 0);
});
