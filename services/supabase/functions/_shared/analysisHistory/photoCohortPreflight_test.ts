import { assert, assertEquals, assertRejects } from "@std/assert";
import {
  preparePublicationPhotoCohort,
  PublicationPhotoCohortContainerRejection,
} from "./photoCohortPreflight.ts";
import { evidenceDigest } from "./evidence.ts";
import {
  joined,
  jpegSegment,
  safeJpeg,
  safePng,
} from "./testing/publicPhotoFixtures.ts";
const id = (n: number) =>
  `00000000-0000-4000-8000-${n.toString().padStart(12, "0")}`;
async function source(n: number, bytes = safeJpeg()) {
  return {
    media_id: id(n),
    object_id: id(n + 10),
    content_type: "image/jpeg",
    byte_count: bytes.length,
    sha256: await evidenceDigest(bytes),
  };
}
Deno.test("whole-cohort preflight prepares exact ordered one-shot photos without provider calls", async () => {
  const bytes = safeJpeg();
  const sources = [await source(1), await source(2)];
  const reads: string[] = [];
  let providerCalls = 0;
  const prepared = await preparePublicationPhotoCohort(sources, {
    apiKey: () => "synthetic-key",
    readSource: (s, signal) => {
      reads.push(s.media_id);
      assert(signal instanceof AbortSignal);
      return Promise.resolve(bytes);
    },
    fetcher: () => {
      providerCalls++;
      return Promise.resolve(new Response("unavailable", { status: 503 }));
    },
  });
  assertEquals(reads, sources.map((s) => s.media_id));
  assertEquals(providerCalls, 0);
  assertEquals(prepared.sources, sources);
  sources[0].sha256 = "b".repeat(64);
  bytes.fill(0);
  assert(Object.isFrozen(prepared));
  const chosen = await prepared.prepare(id(1));
  assertEquals(chosen.proof.source, prepared.sources[0]);
  await assertRejects(() => prepared.prepare(id(2)));
  await assertRejects(() => chosen.invoke());
  await assertRejects(() => chosen.invoke());
  assertEquals(providerCalls, 1);
});
Deno.test("last-source metadata rejection cannot return a partial prepared cohort or charge quota", async () => {
  const good = safeJpeg(),
    bad = joined(good.slice(0, 2), jpegSegment(0xe1, [1, 2, 3]), good.slice(2));
  let charged = 0, providerCalls = 0;
  await assertRejects(async () => {
    await preparePublicationPhotoCohort(
      [await source(1), await source(2, bad)],
      {
        apiKey: () => "synthetic-key",
        readSource: (s) => Promise.resolve(s.media_id === id(1) ? good : bad),
        fetcher: () => {
          providerCalls++;
          throw new Error("must not call");
        },
      },
    );
    charged++;
  });
  assertEquals(charged, 0);
  assertEquals(providerCalls, 0);
});
Deno.test("cohort preflight rejects aliases, HEIC and total-byte overflow before reading", async () => {
  const first = await source(1);
  let reads = 0;
  for (
    const inputs of [
      [first, first],
      [{ ...first, content_type: "image/heic" }],
      [1, 2, 3].map((n) => ({
        ...first,
        media_id: id(n),
        object_id: id(n + 10),
        byte_count: 12 * 1024 * 1024,
      })),
    ]
  ) {
    await assertRejects(() =>
      preparePublicationPhotoCohort(inputs, {
        readSource: () => {
          reads++;
          return Promise.resolve(safeJpeg());
        },
      })
    );
  }
  assertEquals(reads, 0);
});
Deno.test("cohort preflight freezes inputs before suspension and enforces cancellation after reads", async () => {
  const first = await source(1);
  const controller = new AbortController();
  let reads = 0;
  await assertRejects(() =>
    preparePublicationPhotoCohort([first], {
      signal: controller.signal,
      apiKey: () => "synthetic-key",
      readSource: (s) => {
        reads++;
        first.sha256 = "b".repeat(64);
        assertEquals(s.sha256 === first.sha256, false);
        controller.abort();
        return Promise.resolve(safeJpeg());
      },
    })
  );
  assertEquals(reads, 1);
});
Deno.test("cohort preflight refuses bytes whose digest or container differs from approved source", async () => {
  const first = await source(1);
  await assertRejects(() =>
    preparePublicationPhotoCohort([first], {
      apiKey: () => "synthetic-key",
      readSource: () => Promise.resolve(new Uint8Array(first.byte_count)),
    })
  );
});

Deno.test("cohort preflight aborts a suspended source read through its shared signal", async () => {
  const input = await source(1);
  const controller = new AbortController();
  let abortSeen = false;
  const timer = setTimeout(() => controller.abort(), 20);
  try {
    await assertRejects(
      () =>
        preparePublicationPhotoCohort([input], {
          signal: controller.signal,
          readSource: (_source, signal) =>
            new Promise<Uint8Array>((_resolve, reject) => {
              const stop = () => {
                abortSeen = true;
                reject(new Error("private transport diagnostic"));
              };
              if (signal.aborted) stop();
              else signal.addEventListener("abort", stop, { once: true });
            }),
        }),
      Error,
      "analysis_history_evidence_unavailable",
    );
    assertEquals(abortSeen, true);
  } finally {
    clearTimeout(timer);
  }
});

Deno.test("container attestation contains only immutable exact verified source and policy", async () => {
  const bytes = joined(
    safeJpeg().slice(0, 2),
    jpegSegment(0xe1, [1, 2, 3]),
    safeJpeg().slice(2),
  );
  const input = await source(1, bytes);
  const error = await assertRejects(
    () =>
      preparePublicationPhotoCohort([input], {
        readSource: () => Promise.resolve(bytes),
      }),
    PublicationPhotoCohortContainerRejection,
  );
  assertEquals(error.attestation, {
    schema_version: 1,
    policy_version: "public_photo_container_v1",
    source: input,
  });
  input.sha256 = "f".repeat(64);
  assert(error.attestation.source.sha256 !== input.sha256);
  assert(
    Object.isFrozen(error) && Object.isFrozen(error.attestation) &&
      Object.isFrozen(error.attestation.source),
  );
});
Deno.test("read errors cannot spoof verified container evidence and digest mismatch stays unavailable", async () => {
  const input = await source(1);
  for (
    const failure of [
      new Error("publication_photo_not_sanitized"),
      new PublicationPhotoCohortContainerRejection(input),
    ]
  ) {
    const error = await assertRejects(
      () =>
        preparePublicationPhotoCohort([input], {
          readSource: () => Promise.reject(failure),
        }),
      Error,
      "analysis_history_evidence_unavailable",
    );
    assert(!(error instanceof PublicationPhotoCohortContainerRejection));
  }
  const error = await assertRejects(
    () =>
      preparePublicationPhotoCohort([input], {
        readSource: () => Promise.resolve(new Uint8Array(input.byte_count)),
      }),
    Error,
    "analysis_history_evidence_unavailable",
  );
  assert(!(error instanceof PublicationPhotoCohortContainerRejection));
});

Deno.test("verified PNG policy rejection is distinct from an unexpected parser failure", async () => {
  const bad = safePng();
  bad[bad.length - 1] ^= 1;
  const input = { ...await source(1, bad), content_type: "image/png" };
  await assertRejects(
    () =>
      preparePublicationPhotoCohort([input], {
        readSource: () => Promise.resolve(bad),
      }),
    PublicationPhotoCohortContainerRejection,
  );
  class UnexpectedParserBytes extends Uint8Array {
    override subarray(): never {
      throw new Error("unexpected parser fault");
    }
  }
  const unusual = new UnexpectedParserBytes(safePng());
  const ordinary = { ...await source(1, unusual), content_type: "image/png" };
  const error = await assertRejects(
    () =>
      preparePublicationPhotoCohort([ordinary], {
        readSource: () => Promise.resolve(unusual),
      }),
    Error,
    "analysis_history_evidence_unavailable",
  );
  assert(!(error instanceof PublicationPhotoCohortContainerRejection));
});
