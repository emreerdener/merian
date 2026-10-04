import { assert, assertEquals, assertRejects } from "@std/assert";
import type { SupabaseClient } from "@supabase/supabase-js";
import { publicationCopyWorkerRepository } from "./db.ts";
import { PublicHistoryPhotoStorage } from "../_shared/analysisHistory/publicPhotoStorage.ts";
import type { R2Config } from "../_shared/aws.ts";
const id = (n: number) =>
  `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
const hint = () => ({
  owner_id: id(1),
  observation_id: id(2),
  operation_id: id(3),
});
const member = () => ({
  attempt_id: id(5),
  source: {
    media_id: id(6),
    object_id: id(7),
    content_type: "image/jpeg",
    byte_count: 4,
    sha256: "a".repeat(64),
  },
});
const claim = () => ({
  claimed: true,
  ...hint(),
  work_token: id(4),
  work_expires_at: new Date(Date.now() + 120_000).toISOString(),
  cohort: [member()],
});
const signal = () => new AbortController().signal;
function client(
  run: (
    name: string,
    args: Record<string, unknown>,
    signal: AbortSignal,
  ) => unknown,
) {
  return {
    rpc: (name: string, args: Record<string, unknown>) => ({
      abortSignal: async (s: AbortSignal) => ({
        data: await run(name, args, s),
        error: null,
      }),
    }),
  } as unknown as SupabaseClient;
}
Deno.test("copy claim freezes scope original expiry and ordered source cohort", async () => {
  const input = hint(), data = claim();
  const repo = publicationCopyWorkerRepository(client((name, args, s) => {
    assert(!s.aborted);
    assertEquals(name, "claim_publication_copy_work");
    assertEquals(args, {
      p_owner: id(1),
      p_observation: id(2),
      p_operation: id(3),
    });
    input.owner_id = id(99);
    return data;
  }));
  const work = await repo.claim(input, signal());
  assert(work);
  assertEquals(work.scope.owner_id, id(1));
  assertEquals(work.work_expires_at, data.work_expires_at);
  data.cohort[0].source.sha256 = "b".repeat(64);
  assertEquals(work.cohort[0].source.sha256, "a".repeat(64));
  assert(Object.isFrozen(work) && Object.isFrozen(work.cohort));
});
Deno.test("copy worker rejects malformed private claims and unbounded hints", async () => {
  for (
    const bad of [
      { claimed: false, cohort: [] },
      { ...claim(), owner_id: id(99) },
      { ...claim(), work_expires_at: "expired" },
      { ...claim(), work_expires_at: new Date(0).toISOString() },
      { ...claim(), cohort: [] },
      { ...claim(), cohort: [member(), member()] },
      {
        ...claim(),
        cohort: [{
          ...member(),
          source: { ...member().source, content_type: "image/heic" },
        }],
      },
      { ...claim(), note: "private" },
      {
        ...claim(),
        cohort: Array.from(
          { length: 3 },
          (_, n) => ({
            attempt_id: id(20 + n),
            source: {
              ...member().source,
              media_id: id(30 + n),
              object_id: id(40 + n),
              byte_count: 12 * 1024 * 1024,
            },
          }),
        ),
      },
    ]
  ) {
    await assertRejects(() =>
      publicationCopyWorkerRepository(client(() => bad)).claim(hint(), signal())
    );
  }
  for (
    const bad of [Array(11).fill(hint()), [{ ...hint(), ip_hash: "private" }]]
  ) {
    await assertRejects(() =>
      publicationCopyWorkerRepository(client(() => bad)).list(signal())
    );
  }
  assertEquals(
    await publicationCopyWorkerRepository(client(() => ({ claimed: false })))
      .claim(hint(), signal()),
    null,
  );
});
Deno.test("copy finalizer accepts only exact bounded SQL terminal receipts", async () => {
  for (
    const value of [{ finalized: false }, {
      finalized: true,
      status: "admitted",
      reason: null,
      object_ids: [],
    }, {
      finalized: true,
      status: "needs_action",
      reason: "note_requires_text_moderation",
      object_ids: [],
    }, {
      finalized: true,
      status: "needs_action",
      reason: "staging_expired",
      object_ids: [id(8)],
    }]
  ) {
    const repo = publicationCopyWorkerRepository(
      client((name) =>
        name === "claim_publication_copy_work" ? claim() : value
      ),
    );
    const work = await repo.claim(hint(), signal());
    assert(work);
    const result = await repo.finalize(work, signal());
    assertEquals(result.status, value.finalized ? (value.status) : "pending");
  }
  for (
    const bad of [{ finalized: false, reason: null }, {
      finalized: true,
      status: "admitted",
      reason: null,
      object_ids: [id(8)],
    }, {
      finalized: true,
      status: "needs_action",
      reason: "note_requires_text_moderation",
      object_ids: [id(8)],
    }, {
      finalized: true,
      status: "needs_action",
      reason: "staging_expired",
      object_ids: [],
    }, {
      finalized: true,
      status: "needs_action",
      reason: "staging_expired",
      object_ids: [id(8), id(8)],
    }]
  ) {
    const repo = publicationCopyWorkerRepository(
      client((name) => name === "claim_publication_copy_work" ? claim() : bad),
    );
    const work = await repo.claim(hint(), signal());
    assert(work);
    await assertRejects(() => repo.finalize(work, signal()));
  }
});
Deno.test("copy cleanup never writes without an exact targeted registry claim", async () => {
  let writes = 0;
  const config = {
    endpoint: "https://r2.example.invalid",
    bucketName: "synthetic-public",
    s3Client: {} as R2Config["s3Client"],
  };
  const storage = new PublicHistoryPhotoStorage(
    () => config,
    () => config,
    () => {
      writes++;
      return Promise.resolve(new Response(null, { status: 200 }));
    },
  );
  const calls: string[] = [];
  for (const result of [null, { object_id: id(9) }]) {
    const repo = publicationCopyWorkerRepository(
      client((name, args) => {
        calls.push(name);
        assertEquals(args, { p_object: id(8) });
        return result;
      }),
      storage,
    );
    await repo.cleanup([id(8)], signal());
  }
  assertEquals(writes, 0);
  assertEquals(calls, [
    "claim_publication_photo_erasure",
    "claim_publication_photo_erasure",
  ]);
});
Deno.test("copy worker RPC aborts a noncooperative transport with caller deadline", async () => {
  const abort = new AbortController();
  const repo = publicationCopyWorkerRepository(client((_n, _a, s) => {
    assert(!s.aborted);
    abort.abort();
    return new Promise(() => {});
  }));
  await assertRejects(() => repo.list(abort.signal));
});

Deno.test("copy worker connects historical controller recovery without storage or cleanup", async () => {
  const calls: string[] = [];
  const repo = publicationCopyWorkerRepository(
    client((name) => {
      calls.push(name);
      if (name === "claim_publication_copy_work") return claim();
      assertEquals(name, "read_publication_copy_cohort");
      return {
        reservation: null,
        publication: {
          schema_version: 1,
          ...{ operation_id: id(3), observation_id: id(2) },
          analysis_id: id(10),
          request_id: id(11),
          post_id: id(12),
          status: "admitted",
        },
      };
    }),
    new PublicHistoryPhotoStorage(() => {
      throw new Error("must not resolve storage");
    }),
  );
  const work = await repo.claim(hint(), signal());
  assert(work);
  assertEquals(await repo.execute(work, signal()), "published");
  assertEquals(calls, [
    "claim_publication_copy_work",
    "read_publication_copy_cohort",
  ]);
});
Deno.test("copy cleanup marks only the granted target and acknowledges that same claim", async () => {
  const calls: string[] = [];
  const config = {
    endpoint: "https://r2.example.invalid",
    bucketName: "synthetic-public",
    s3Client: {} as R2Config["s3Client"],
  };
  const storage = new PublicHistoryPhotoStorage(
    () => config,
    () => config,
    (request) => {
      assert(!request.signal.aborted);
      calls.push(request.method);
      return Promise.resolve(
        new Response(null, {
          status: 200,
          headers: {
            "Content-Length": "0",
            "Content-Type": "application/octet-stream",
            "Cache-Control": "no-store, max-age=0",
            "x-amz-meta-erased": "true",
          },
        }),
      );
    },
  );
  const repo = publicationCopyWorkerRepository(
    client((name, args, s) => {
      assert(!s.aborted);
      calls.push(name);
      if (name === "claim_publication_photo_erasure") {
        assertEquals(args, { p_object: id(8) });
        return {
          object_id: id(8),
          claim_token: id(9),
          available_at: new Date().toISOString(),
          claim_expires_at: new Date(Date.now() + 30_000).toISOString(),
          erased_at: null,
          bound_at: null,
          revoked_at: null,
        };
      }
      assertEquals(args, { p_object: id(8), p_claim: id(9), p_success: true });
      return true;
    }),
    storage,
  );
  await repo.cleanup([id(8)], signal());
  assertEquals(calls, [
    "claim_publication_photo_erasure",
    "PUT",
    "HEAD",
    "finish_publication_photo_erasure",
  ]);
});
