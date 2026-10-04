import { assert, assertEquals, assertRejects, assertThrows } from "@std/assert";
import type { SupabaseClient } from "@supabase/supabase-js";
import {
  isActivePhotoWork,
  publicationModerationRepository,
} from "./publicationModerationRepository.ts";
import { HistoryError } from "./contract.ts";
const id = (n: number) =>
  `00000000-0000-4000-8000-${n.toString().padStart(12, "0")}`;
const source = () => ({
  media_id: id(5),
  object_id: id(6),
  byte_count: 3,
  content_type: "image/jpeg",
  sha256: "a".repeat(64),
});
const identity = () => ({
  owner_id: id(1),
  observation_id: id(2),
  operation_id: id(3),
  work_token: id(4),
});
function receipt(state = "reserved") {
  return {
    schema_version: 1,
    attempt_id: id(7),
    operation_id: id(3),
    media_id: id(5),
    state,
    quota: {},
    lease_token: state === "reserved" || state === "dispatched" ? id(8) : null,
    dispatch_expires_at: state === "reserved" ? null : "2026-10-04T13:00:00Z",
    source: source(),
    policy_version: "photo_publication_v1",
    provider: "gemini",
    model: "gemini-2.5-flash",
    processor_permission: "google_gemini",
  };
}
function client(
  handler: (name: string, args: Record<string, unknown>) => unknown,
) {
  return {
    rpc: (name: string, args: Record<string, unknown>) => ({
      abortSignal: (signal: AbortSignal) => {
        assert(signal instanceof AbortSignal);
        return Promise.resolve({ data: handler(name, args), error: null });
      },
    }),
  } as unknown as SupabaseClient;
}
Deno.test("moderation repository freezes operation scope and recovers ordered source-bound attempts", async () => {
  const input = identity(), photo = source();
  const calls: Record<string, unknown>[] = [];
  const repo = publicationModerationRepository(
    client((name, args) => {
      calls.push(args);
      assertEquals(name, "read_publication_moderation_work");
      return [{ media_id: id(5), attempt: receipt() }];
    }),
    input,
    [photo],
  );
  input.owner_id = id(99);
  photo.sha256 = "b".repeat(64);
  const [work] = await repo.read();
  assert(work);
  assertEquals(work.source, source());
  assert(Object.isFrozen(work.source));
  assertEquals(calls, [{
    p_owner: id(1),
    p_observation: id(2),
    p_operation: id(3),
    p_work: id(4),
  }]);
  assertEquals("quota" in work, false);
});
Deno.test("moderation recovery refuses reordered, foreign or malformed receipts", async () => {
  for (
    const data of [
      [{ media_id: id(9), attempt: null }],
      [{ media_id: id(5), attempt: { ...receipt(), operation_id: id(9) } }],
      [{
        media_id: id(5),
        attempt: {
          ...receipt(),
          source: { ...source(), sha256: "b".repeat(64) },
        },
      }],
      [{ media_id: id(5), attempt: { ...receipt(), lease_token: null } }],
      [],
    ]
  ) {
    const repo = publicationModerationRepository(
      client(() => data),
      identity(),
      [source()],
    );
    await assertRejects(
      () => repo.read(),
      HistoryError,
      "analysis_history_unavailable",
    );
  }
});
Deno.test("moderation admission supplies no replacement identity or new IP and refuses outside cohort", async () => {
  let calls = 0;
  const repo = publicationModerationRepository(
    client((name, args) => {
      calls++;
      assertEquals(name, "admit_publication_moderation_work");
      assertEquals(args, {
        p_owner: id(1),
        p_observation: id(2),
        p_operation: id(3),
        p_work: id(4),
        p_media: id(5),
      });
      return receipt();
    }),
    identity(),
    [source()],
  );
  await assertRejects(() => repo.admit(id(9)));
  assertEquals(calls, 0);
  assertEquals((await repo.admit(id(5))).attempt_id, id(7));
  assertEquals(calls, 1);
});
Deno.test("moderation execution uses original attempt identity and requires exact dispatch acknowledgement", async () => {
  let bad = false;
  const calls: Record<string, unknown>[] = [];
  const repo = publicationModerationRepository(
    client((name, args) => {
      if (name === "admit_publication_moderation_work") return receipt();
      calls.push(args);
      return {
        dispatch_allowed: true,
        receipt: bad
          ? { ...receipt("dispatched"), lease_token: id(99) }
          : receipt("dispatched"),
      };
    }),
    identity(),
    [source()],
  );
  const work = await repo.admit(id(5));
  assert(isActivePhotoWork(work));
  const deps = repo.execution(work);
  const scope = {
    owner_id: id(1),
    observation_id: id(2),
    attempt_id: id(7),
    lease_token: id(8),
  };
  await assertRejects(() => deps.dispatch({ ...scope, owner_id: id(99) }));
  assertEquals(calls.length, 0);
  assertEquals(await deps.dispatch(scope), true);
  bad = true;
  await assertRejects(
    () => deps.dispatch(scope),
    HistoryError,
    "analysis_history_unavailable",
  );
  assertEquals(calls[0], {
    p_owner: id(1),
    p_observation: id(2),
    p_operation: id(3),
    p_work: id(4),
    p_attempt: id(7),
    p_token: id(8),
    p_action: "dispatch",
    p_payload: {},
  });
});
Deno.test("moderation transport errors are sanitized and never automatically retried", async () => {
  let calls = 0;
  const repo = publicationModerationRepository(
    client(() => {
      calls++;
      throw new Error("private diagnostic");
    }),
    identity(),
    [source()],
  );
  await assertRejects(
    () => repo.read(),
    HistoryError,
    "analysis_history_unavailable",
  );
  assertEquals(calls, 1);
});
Deno.test("moderation repository rejects duplicate and oversized source cohorts before transport", () => {
  const c = client(() => {
    throw new Error("must not execute");
  });
  assertThrows(() =>
    publicationModerationRepository(c, identity(), [source(), source()])
  );
  assertThrows(() =>
    publicationModerationRepository(c, identity(), [{
      ...source(),
      byte_count: 13 * 1024 * 1024,
    }])
  );
  assertThrows(() =>
    publicationModerationRepository(c, identity(), [{
      ...source(),
      object_id: id(5),
    }])
  );
});

Deno.test("terminal recovery is consumed without constructing a provider-token executor", async () => {
  for (
    const state of ["approved", "rejected", "cancelled", "unknown_execution"]
  ) {
    const repo = publicationModerationRepository(
      client(() => [{ media_id: id(5), attempt: receipt(state) }]),
      identity(),
      [source()],
    );
    const [work] = await repo.read();
    assert(work);
    assertEquals(isActivePhotoWork(work), false);
    assertEquals(work.lease_token, null);
    assertEquals(work.state, state);
  }
});
