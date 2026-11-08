import type { R2Config } from "../aws.ts";
import { PrivateHistoryEvidenceStorage } from "./evidenceStorage.ts";
import { assertEquals, assertRejects } from "@std/assert";
import { evidenceDigest } from "./evidence.ts";
import { videoByteFixture } from "./videoByteTestFixtures.ts";
import {
  uploadVideoEvidenceItem,
  type VideoUploadDependencies,
} from "./videoUpload.ts";
const owner = "00000000-0000-4000-8000-000000000900";
const signal = () => new AbortController().signal;
const now = () => Date.parse("2025-12-31T23:59:00.000Z");
async function fixture(audio = true, target = 0) {
  const f = await videoByteFixture(audio);
  const allocation = {
    ...f.receipt,
    state: "allocated",
    items: f.receipt.items.map((item) => ({ ...item, ready_at: null })),
  };
  const completed = {
    ...allocation,
    items: allocation.items.map((item, i) =>
      i === target ? f.receipt.items[i] : item
    ),
  };
  const calls: string[] = [];
  const deps: VideoUploadDependencies = {
    reserve(_owner, candidate) {
      calls.push("reserve");
      assertEquals(_owner, owner);
      assertEquals(candidate, f.input);
      return Promise.resolve(allocation);
    },
    async write(receipt, bytes, parent) {
      calls.push("write");
      assertEquals(parent.aborted, false);
      assertEquals(receipt.object_id, allocation.items[target].object_id);
      assertEquals(bytes, f.bytes[target]);
      assertEquals(await evidenceDigest(bytes), receipt.sha256);
    },
    complete(_owner, candidate, prior, media) {
      calls.push("complete");
      assertEquals(_owner, owner);
      assertEquals(candidate, f.input);
      assertEquals(JSON.parse(new TextDecoder().decode(prior)), allocation);
      assertEquals(media, allocation.items[target].media_id);
      return Promise.resolve(completed);
    },
  };
  return {
    ...f,
    allocation,
    completed,
    calls,
    deps,
    media: allocation.items[target].media_id,
  };
}
Deno.test("video upload verifies source frame audio before ordered allocation write completion", async () => {
  for (const audio of [true, false]) {
    for (const index of (audio ? [0, 1, 6] : [0, 1])) {
      const f = await fixture(audio, index);
      assertEquals<unknown>(
        await uploadVideoEvidenceItem(
          f.input,
          owner,
          f.media,
          f.bytes[index],
          f.deps,
          signal(),
          now,
        ),
        f.completed,
      );
      assertEquals(f.calls, ["reserve", "write", "complete"]);
    }
  }
});
Deno.test("video upload rejects wrong body and target before allocation", async () => {
  const f = await fixture();
  for (
    const body of [
      new Uint8Array(),
      f.bytes[0].slice(1),
      new Uint8Array(f.bytes[0].length),
    ]
  ) {
    await assertRejects(() =>
      uploadVideoEvidenceItem(
        f.input,
        owner,
        f.media,
        body,
        f.deps,
        signal(),
        now,
      )
    );
  }
  await assertRejects(() =>
    uploadVideoEvidenceItem(
      f.input,
      owner,
      owner,
      f.bytes[0],
      f.deps,
      signal(),
      now,
    )
  );
  assertEquals(f.calls, []);
});
Deno.test("video upload ready replay skips writes even after fixed expiry", async () => {
  const f = await fixture();
  f.deps.reserve = () => {
    f.calls.push("reserve");
    return Promise.resolve(f.receipt);
  };
  assertEquals<unknown>(
    await uploadVideoEvidenceItem(
      f.input,
      owner,
      f.media,
      f.bytes[0],
      f.deps,
      signal(),
      () => Date.parse("2099-01-01T00:00:00.000Z"),
    ),
    f.receipt,
  );
  assertEquals(f.calls, ["reserve"]);
});
Deno.test("video upload expired pending allocation never writes or acknowledges", async () => {
  for (const time of [Date.parse("2026-01-01T00:00:00.000Z"), NaN]) {
    const f = await fixture();
    await assertRejects(() =>
      uploadVideoEvidenceItem(
        f.input,
        owner,
        f.media,
        f.bytes[0],
        f.deps,
        signal(),
        () => time,
      )
    );
    assertEquals(f.calls, ["reserve"]);
  }
});
Deno.test("video upload freezes caller body and manifest across hashing and RPC awaits", async () => {
  const f = await fixture(),
    original = structuredClone(f.input),
    body = f.bytes[0].slice();
  f.deps.reserve = (_owner, candidate) => {
    f.calls.push("reserve");
    assertEquals(candidate, original);
    return Promise.resolve(f.allocation);
  };
  f.deps.complete = () => Promise.resolve(f.completed);
  const pending = uploadVideoEvidenceItem(
    f.input,
    owner,
    f.media,
    body,
    f.deps,
    signal(),
    now,
  );
  body.fill(0);
  f.input.input.request_digest = "0".repeat(64);
  assertEquals<unknown>(await pending, f.completed);
});
Deno.test("video upload rejects changed allocation or completion without replacement", async () => {
  for (const phase of ["reserve", "complete"] as const) {
    const f = await fixture();
    f.deps[phase] = () => {
      f.calls.push(phase);
      return Promise.resolve({ ...f.completed, owner_id: f.media });
    };
    await assertRejects(() =>
      uploadVideoEvidenceItem(
        f.input,
        owner,
        f.media,
        f.bytes[0],
        f.deps,
        signal(),
        now,
      )
    );
    assertEquals(
      f.calls,
      phase === "reserve" ? ["reserve"] : ["reserve", "write", "complete"],
    );
  }
  const f = await fixture();
  f.deps.complete = () => Promise.resolve(f.allocation);
  await assertRejects(() =>
    uploadVideoEvidenceItem(
      f.input,
      owner,
      f.media,
      f.bytes[0],
      f.deps,
      signal(),
      now,
    )
  );
});
Deno.test("video upload write or completion loss never retries or refunds", async () => {
  for (const phase of ["write", "complete"] as const) {
    const f = await fixture();
    f.deps[phase] = () => {
      f.calls.push(phase);
      return Promise.reject<never>(new Error("lost"));
    };
    await assertRejects(() =>
      uploadVideoEvidenceItem(
        f.input,
        owner,
        f.media,
        f.bytes[0],
        f.deps,
        signal(),
        now,
      )
    );
    assertEquals(
      f.calls,
      phase === "write"
        ? ["reserve", "write"]
        : ["reserve", "write", "complete"],
    );
  }
});
Deno.test("video upload cancellation regains control while stalled write cannot acknowledge", async () => {
  const f = await fixture(), controller = new AbortController();
  let entered!: () => void;
  const started = new Promise<void>((resolve) => entered = resolve);
  let finish!: () => void;
  f.deps.write = () => {
    f.calls.push("write");
    entered();
    return new Promise<void>((resolve) => finish = resolve);
  };
  const pending = uploadVideoEvidenceItem(
    f.input,
    owner,
    f.media,
    f.bytes[0],
    f.deps,
    controller.signal,
    now,
  );
  await started;
  controller.abort();
  await assertRejects(() => pending);
  finish();
  await Promise.resolve();
  assertEquals(f.calls, ["reserve", "write"]);
  const before = await fixture();
  await assertRejects(() =>
    uploadVideoEvidenceItem(
      before.input,
      owner,
      before.media,
      before.bytes[0],
      before.deps,
      controller.signal,
      now,
    )
  );
  assertEquals(before.calls, []);
});

Deno.test("video upload shares conditional object writes and rejects retained erasure markers", async () => {
  for (const erased of [false, true]) {
    const f = await fixture(true, 1), requests: string[] = [];
    const config = {
      endpoint: "https://storage.example.invalid",
      bucketName: "private-history",
    } as R2Config;
    const storage = new PrivateHistoryEvidenceStorage(
      () => config,
      () => config,
      async (request) => {
        requests.push(request.method);
        assertEquals(
          new URL(request.url).pathname,
          `/private-history/evidence/v1/${f.allocation.items[1].object_id}`,
        );
        if (request.method === "PUT") {
          assertEquals(request.headers.get("if-none-match"), "*");
          assertEquals(new Uint8Array(await request.arrayBuffer()), f.bytes[1]);
          return new Response(null, { status: erased ? 412 : 200 });
        }
        assertEquals(request.method, "HEAD");
        return new Response(null, {
          headers: erased
            ? {
              "content-type": "application/octet-stream",
              "content-length": "0",
              "x-amz-meta-erased": "true",
            }
            : {
              "content-type": f.allocation.items[1].content_type,
              "content-length": String(f.bytes[1].length),
              "x-amz-meta-sha256": f.allocation.items[1].sha256,
            },
        });
      },
    );
    f.deps.write = (receipt, bytes, signal) => {
      f.calls.push("write");
      return storage.writeOnce(receipt, bytes, signal);
    };
    const run = () =>
      uploadVideoEvidenceItem(
        f.input,
        owner,
        f.media,
        f.bytes[1],
        f.deps,
        signal(),
        now,
      );
    if (erased) {
      await assertRejects(run);
      assertEquals(f.calls, ["reserve", "write"]);
    } else {
      assertEquals<unknown>(await run(), f.completed);
      assertEquals(f.calls, ["reserve", "write", "complete"]);
    }
    assertEquals(requests, ["PUT", "HEAD"]);
  }
});

Deno.test("video upload partial allocation skips an already acknowledged target after expiry", async () => {
  const f = await fixture();
  f.deps.reserve = () => {
    f.calls.push("reserve");
    return Promise.resolve(f.completed);
  };
  assertEquals<unknown>(
    await uploadVideoEvidenceItem(
      f.input,
      owner,
      f.media,
      f.bytes[0],
      f.deps,
      signal(),
      () => Date.parse("2099-01-01T00:00:00.000Z"),
    ),
    f.completed,
  );
  assertEquals(f.calls, ["reserve"]);
});

Deno.test("video upload cancellation bounds stalled reserve and completion without accepting late answers", async () => {
  for (const phase of ["reserve", "complete"] as const) {
    const f = await fixture(), controller = new AbortController();
    let entered!: () => void;
    const started = new Promise<void>((resolve) => entered = resolve);
    let finish!: (value: unknown) => void;
    f.deps[phase] = () => {
      f.calls.push(phase);
      entered();
      return new Promise<unknown>((resolve) => finish = resolve);
    };
    const pending = uploadVideoEvidenceItem(
      f.input,
      owner,
      f.media,
      f.bytes[0],
      f.deps,
      controller.signal,
      now,
    );
    await started;
    controller.abort();
    await assertRejects(() => pending);
    finish(phase === "reserve" ? f.allocation : f.completed);
    await Promise.resolve();
    assertEquals(
      f.calls,
      phase === "reserve" ? ["reserve"] : ["reserve", "write", "complete"],
    );
  }
});
