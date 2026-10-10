import { assertEquals, assertRejects } from "@std/assert";
import { materializeVideoCohort } from "./videoMaterialization.ts";
import { evidenceDigest } from "./evidence.ts";
import { videoByteFixture as fixture } from "./videoByteTestFixtures.ts";
const id = (n: number) =>
  `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
const json = (value: unknown) =>
  new TextEncoder().encode(JSON.stringify(value));
Deno.test("video materialization preserves complete audio/silent saved cohort and independent bytes", async () => {
  for (const audio of [true, false]) {
    const f = await fixture(audio), signal = new AbortController().signal;
    let reads = 0;
    const result = await materializeVideoCohort(
      f.input,
      id(900),
      json(f.receipt),
      {
        read(item, options) {
          assertEquals(item, f.receipt.items[reads]);
          assertEquals(options, {
            maximumBytes: f.bytes[reads].length,
            signal,
          });
          return Promise.resolve(f.bytes[reads++]);
        },
      },
      signal,
    );
    assertEquals(reads, audio ? 7 : 6);
    assertEquals(result.items.map((row) => row.bytes), f.bytes);
    result.items[0].bytes.fill(0);
    assertEquals(f.bytes[0][0], 0); // MP4 starts with a big-endian box size.
    assertEquals(await evidenceDigest(f.bytes[0]), f.receipt.items[0].sha256);
  }
});

Deno.test("video materialization denies mismatched or partial receipts before storage", async () => {
  const f = await fixture(true);
  let reads = 0;
  for (
    const change of [{ owner_id: id(901) }, { state: "allocated" }, {
      items: f.receipt.items.slice(1),
    }, { analysis_id: id(902) }]
  ) {
    await assertRejects(() =>
      materializeVideoCohort(
        f.input,
        id(900),
        json({ ...f.receipt, ...change }),
        {
          read() {
            reads++;
            return Promise.resolve(f.bytes[0]);
          },
        },
        new AbortController().signal,
      )
    );
  }
  assertEquals(reads, 0);
});

Deno.test("video materialization stops at every corrupt or missing item without repair", async () => {
  const f = await fixture(true);
  for (let failure = 0; failure < 7; failure++) {
    for (const mode of ["digest", "length", "missing"]) {
      let reads = 0;
      await assertRejects(() =>
        materializeVideoCohort(f.input, id(900), json(f.receipt), {
          read() {
            const index = reads++, bytes = f.bytes[index].slice();
            if (index === failure) {
              if (mode === "missing") {
                return Promise.reject(new Error("unavailable"));
              }
              if (mode === "length") return Promise.resolve(bytes.subarray(1));
              bytes[bytes.length - 1] ^= 1;
            }
            return Promise.resolve(bytes);
          },
        }, new AbortController().signal)
      );
      assertEquals(reads, failure + 1);
    }
  }
});

Deno.test("video materialization snapshots caller metadata and stops after aborted reads", async () => {
  const f = await fixture(false),
    original = structuredClone(f.input),
    receipt = json(f.receipt);
  let reads = 0;
  const pending = materializeVideoCohort(f.input, id(900), receipt, {
    read() {
      return Promise.resolve(f.bytes[reads++]);
    },
  }, new AbortController().signal);
  f.input.input.evidence_manifest.provenance.source.sha256 = "0".repeat(64);
  receipt.fill(0);
  assertEquals(
    (await pending).receipt.items[0].sha256,
    original.input.evidence_manifest.provenance.source.sha256,
  );
  for (const during of [false, true]) {
    const controller = new AbortController();
    reads = 0;
    if (!during) controller.abort();
    await assertRejects(() =>
      materializeVideoCohort(original, id(900), json(f.receipt), {
        read() {
          reads++;
          controller.abort();
          return Promise.resolve(f.bytes[0]);
        },
      }, controller.signal)
    );
    assertEquals(reads, during ? 1 : 0);
  }
});
