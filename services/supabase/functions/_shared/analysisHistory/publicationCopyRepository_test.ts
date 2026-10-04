import { assert, assertEquals, assertRejects, assertThrows } from "@std/assert";
import type { SupabaseClient } from "@supabase/supabase-js";
import { publicationCopyRepository } from "./publicationCopyRepository.ts";
import { HistoryError } from "./contract.ts";
import { executePublicationCopyMember } from "./publicationCopyExecution.ts";
const id = (n: number) =>
  `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
const identity = () => ({
  owner_id: id(1),
  observation_id: id(2),
  operation_id: id(3),
  work_token: id(4),
});
const member = (i = 0) => ({
  attempt_id: id(10 + i),
  source: {
    media_id: id(20 + i),
    object_id: id(30 + i),
    content_type: "image/jpeg",
    byte_count: 3,
    sha256: "a".repeat(64),
  },
});
const row = (i = 0) => ({
  owner_id: id(1),
  observation_id: id(2),
  attempt_id: id(10 + i),
  object_id: id(40 + i),
  lease_token: id(50 + i),
  source: member(i).source,
  expires_at: "2099-01-01T00:10:00+00:00",
  ready_at: null as string | null,
});
const reservation = () => ({
  expires_at: row().expires_at,
  copies: [row(0), row(1)],
});
const published = () => ({
  schema_version: 1,
  operation_id: id(3),
  observation_id: id(2),
  analysis_id: id(60),
  request_id: id(61),
  post_id: id(62),
  status: "admitted",
});
function client(
  handler: (
    name: string,
    args: Record<string, unknown>,
    signal: AbortSignal,
  ) => unknown | Promise<unknown>,
) {
  return {
    rpc: (name: string, args: Record<string, unknown>) => ({
      abortSignal: async (signal: AbortSignal) => ({
        data: await handler(name, args, signal),
        error: null,
      }),
    }),
  } as unknown as SupabaseClient;
}
function make(
  handler: Parameters<typeof client>[0],
  signal = new AbortController().signal,
) {
  return publicationCopyRepository(client(handler), identity(), [
    member(0),
    member(1),
  ], signal);
}
const scope = () => ({
  owner_id: id(1),
  observation_id: id(2),
  attempt_id: id(10),
});
const lease = () => ({ ...scope(), object_id: id(40), lease_token: id(50) });
Deno.test("copy repository freezes exact cohort and distinguishes recovery from reserve authorization", async () => {
  const input = identity(),
    members = [member(0), member(1)],
    calls: Record<string, unknown>[] = [];
  const repo = publicationCopyRepository(
    client((name, args) => {
      calls.push(args);
      assertEquals(name, "read_publication_copy_cohort");
      return { reservation: reservation(), publication: null };
    }),
    input,
    members,
    new AbortController().signal,
  );
  input.owner_id = id(99);
  members[0].source.sha256 = "b".repeat(64);
  const recovered = await repo.read();
  assertEquals(recovered.reservation, reservation());
  assert(Object.isFrozen(recovered.reservation!.copies[0].source));
  assertEquals(calls, [{
    p_owner: id(1),
    p_observation: id(2),
    p_operation: id(3),
  }]);
  await assertRejects(() =>
    repo.forPhoto(id(10)).complete(lease(), new AbortController().signal)
  );
});
Deno.test("copy repository denies oversized, repeated or unsupported approved cohort before RPC", () => {
  for (
    const members of [
      [member(0), member(0)],
      [{
        ...member(),
        source: { ...member().source, content_type: "image/heic" },
      }],
      Array.from({ length: 7 }, (_, i) => member(i)),
      Array.from(
        { length: 3 },
        (_, i) => ({
          ...member(i),
          source: { ...member(i).source, byte_count: 12 * 1024 * 1024 },
        }),
      ),
    ]
  ) {
    assertThrows(() =>
      publicationCopyRepository(
        client(() => {
          throw new Error("unexpected RPC");
        }),
        identity(),
        members,
        new AbortController().signal,
      )
    );
  }
});
Deno.test("copy recovery rejects reordered, foreign, partial and inconsistent-expiry reservations", async () => {
  for (
    const data of [
      { ...reservation(), copies: [row(1), row(0)] },
      { ...reservation(), copies: [row(0)] },
      { ...reservation(), copies: [{ ...row(0), owner_id: id(99) }, row(1)] },
      {
        ...reservation(),
        copies: [{ ...row(0), expires_at: "2099-01-01T00:11:00Z" }, row(1)],
      },
      {
        ...reservation(),
        copies: [{ ...row(0), object_id: member(1).source.object_id }, row(1)],
      },
      {
        ...reservation(),
        copies: [row(0), { ...row(1), object_id: row(0).object_id }],
      },
    ]
  ) {
    await assertRejects(
      () => make(() => ({ reservation: data, publication: null })).read(),
      HistoryError,
      "analysis_history_unavailable",
    );
  }
});
Deno.test("copy member callbacks refresh full cohort and keep exact private execution identities", async () => {
  const calls: { name: string; args: Record<string, unknown> }[] = [];
  const repo = make((name, args) => {
    calls.push({ name, args });
    return name === "reserve_publication_copy_cohort"
      ? reservation()
      : { ...row(), ready_at: "2099-01-01T00:00:01Z" };
  });
  const photo = repo.forPhoto(id(10));
  assertEquals(await photo.reserve(scope()), row());
  await assertRejects(() =>
    photo.complete(
      { ...lease(), owner_id: id(99) },
      new AbortController().signal,
    )
  );
  assertEquals(
    await photo.complete(lease(), new AbortController().signal),
    { ...row(), ready_at: "2099-01-01T00:00:01Z" },
  );
  assertEquals(calls.map((c) => c.name), [
    "reserve_publication_copy_cohort",
    "complete_publication_copy_cohort_photo",
  ]);
  assertEquals(calls[1].args, {
    p_owner: id(1),
    p_observation: id(2),
    p_operation: id(3),
    p_work: id(4),
    p_attempt: id(10),
    p_object: id(40),
    p_lease: id(50),
  });
  assertThrows(() => repo.forPhoto(id(99)));
});
Deno.test("copy repository rejects changed reservation identity and changed completion lease", async () => {
  let count = 0;
  const repo = make(() =>
    ++count === 1
      ? reservation()
      : { ...reservation(), copies: [{ ...row(), object_id: id(99) }, row(1)] }
  );
  await repo.reserve();
  await assertRejects(
    () => repo.reserve(),
    HistoryError,
    "analysis_history_unavailable",
  );
  const changed = make((name) =>
    name === "reserve_publication_copy_cohort"
      ? reservation()
      : { ...row(), lease_token: id(99), ready_at: "2099-01-01T00:00:01Z" }
  );
  await changed.reserve();
  await assertRejects(
    () =>
      changed.forPhoto(id(10)).complete(lease(), new AbortController().signal),
    HistoryError,
    "analysis_history_unavailable",
  );
});
Deno.test("copy cleanup recovers committed publication without calling abandonment", async () => {
  const names: string[] = [];
  const repo = make((name) => {
    names.push(name);
    return { reservation: reservation(), publication: published() };
  });
  assertEquals(await repo.abandon(), null);
  assertEquals(names, ["read_publication_copy_cohort"]);
  await assertRejects(
    () =>
      make(() => ({
        reservation: reservation(),
        publication: { ...published(), operation_id: id(99) },
      })).abandon(),
    HistoryError,
    "analysis_history_unavailable",
  );
});
Deno.test("copy cleanup accepts only the exact complete registry cohort and publication race refusal", async () => {
  for (
    const result of [{ abandoned: true, object_ids: [id(41), id(40)] }, {
      abandoned: false,
    }]
  ) {
    const names: string[] = [];
    const repo = make((name) => {
      names.push(name);
      return name === "read_publication_copy_cohort"
        ? { reservation: reservation(), publication: null }
        : result;
    });
    assertEquals(
      await repo.abandon(),
      result.abandoned ? [id(40), id(41)] : null,
    );
    assertEquals(names, [
      "read_publication_copy_cohort",
      "abandon_publication_copy_cohort",
    ]);
  }
  for (const ids of [[id(40)], [id(40), id(99)], [id(40), id(40)]]) {
    await assertRejects(
      () =>
        make((name) =>
          name === "read_publication_copy_cohort"
            ? { reservation: reservation(), publication: null }
            : { abandoned: true, object_ids: ids }
        ).abandon(),
      HistoryError,
      "analysis_history_unavailable",
    );
  }
});
Deno.test("copy cleanup never invents objects after failed recovery", async () => {
  const names: string[] = [];
  const repo = make((name) => {
    names.push(name);
    throw new Error("private SQL detail");
  });
  await assertRejects(
    () => repo.abandon(),
    HistoryError,
    "analysis_history_unavailable",
  );
  assertEquals(names, ["read_publication_copy_cohort"]);
});
Deno.test("copy repository aborts noncooperative RPC without retry or private diagnostics", async () => {
  const controller = new AbortController();
  let calls = 0;
  const repo = make(() => {
    calls++;
    controller.abort();
    return new Promise(() => {});
  }, controller.signal);
  await assertRejects(
    () => repo.reserve(),
    HistoryError,
    "analysis_history_unavailable",
  );
  assertEquals(calls, 1);
  await assertRejects(
    () => repo.reserve(),
    HistoryError,
    "analysis_history_unavailable",
  );
  assertEquals(calls, 1);
});
Deno.test("copy completion honors caller deadline before invoking RPC", async () => {
  let calls = 0;
  const repo = make(() => {
    calls++;
    return reservation();
  });
  await repo.reserve();
  const controller = new AbortController();
  controller.abort();
  await assertRejects(
    () => repo.forPhoto(id(10)).complete(lease(), controller.signal),
    HistoryError,
    "analysis_history_unavailable",
  );
  assertEquals(calls, 1);
});

Deno.test("copy recovery pins original objects without granting execution and rejects rebound cleanup", async () => {
  let count = 0;
  const repo = make(() => ({
    reservation: ++count === 1
      ? reservation()
      : { ...reservation(), copies: [{ ...row(), object_id: id(99) }, row(1)] },
    publication: null,
  }));
  await repo.read();
  await assertRejects(
    () => repo.abandon(),
    HistoryError,
    "analysis_history_unavailable",
  );
  assertEquals(count, 2);
});

Deno.test("failed member targets every original sibling and never a foreign cleanup hint", async () => {
  for (const mode of ["normal", "deleted", "foreign", "published"]) {
    const targets: string[] = [];
    const repo = make((name) => {
      if (name === "reserve_publication_copy_cohort") return reservation();
      if (name === "read_publication_copy_cohort") {
        if (mode === "deleted") throw new Error("removed");
        return {
          reservation: reservation(),
          publication: mode === "published" ? published() : null,
        };
      }
      assertEquals(name, "abandon_publication_copy_cohort");
      return {
        abandoned: true,
        object_ids: mode === "foreign" ? [id(40), id(99)] : [id(40), id(41)],
      };
    });
    const result = await executePublicationCopyMember(repo, id(10), {
      readSource: () =>
        Promise.reject(new Error("synthetic write prerequisite failure")),
      erasure: {
        claim: (target) => {
          assert(target);
          targets.push(target);
          return Promise.resolve(null);
        },
        erase: () => {
          throw new Error("claim required");
        },
        finish: () => {
          throw new Error("claim required");
        },
      },
    });
    assertEquals(result, "reconcile");
    assertEquals(targets, mode === "published" ? [id(40)] : [id(41), id(40)]);
  }
});
