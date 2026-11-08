import { assert, assertEquals, assertRejects, assertThrows } from "@std/assert";
import { encodeBase64 } from "../encoding.ts";
import { initialCanonicalText, initialDigest } from "./canonical.ts";
import {
  completionDescriptionPage,
  createCompletionDescriptionCollector,
  snapshotCompletionDescriptions,
} from "./completionDescriptions.ts";

const bytes = new TextEncoder();
function cpm(texts: string[]): string {
  return initialCanonicalText(texts.map((text) => ({
    text_utf8_base64: encodeBase64(bytes.encode(text)),
  })));
}
async function collect(version: 1 | 2, canonical: string) {
  const snapshot = await snapshotCompletionDescriptions(version, canonical);
  const collector = createCompletionDescriptionCollector(snapshot.reference);
  let pages = 0;
  for (
    let index = 0;
    index < snapshot.reference.ordered_description_count;
    index++
  ) {
    let offset: number | null = 0;
    do {
      const wire = await completionDescriptionPage(
        snapshot.reference,
        canonical,
        index,
        offset,
      );
      assert(bytes.encode(wire).length <= 65_536);
      collector.append(wire);
      offset = JSON.parse(wire).next_byte_offset;
      pages++;
    } while (offset !== null);
  }
  return { result: await collector.finish(), pages };
}
Deno.test("completion descriptions retain CPM BOM, NUL, normalization, whitespace and explicit empty items", async () => {
  const texts = ["\uFEFFx\u0000\r\n", " e\u0301 ", "é", ""];
  const canonical = cpm(texts);
  const { result, pages } = await collect(2, canonical);
  assertEquals(result.canonical, canonical);
  assertEquals(result.descriptions, texts);
  assertEquals(pages, 4);
  assert(Object.isFrozen(result) && Object.isFrozen(result.descriptions));
});
Deno.test("completion description pages split UTF-8 bytes safely and reconstruct whole original digest", async () => {
  const texts = ["a" + "🦋".repeat(8191)];
  const canonical = cpm(texts);
  const { result, pages } = await collect(2, canonical);
  assertEquals(result.descriptions, texts);
  assertEquals(pages, 2);
  assertEquals(result.canonical, canonical);
});
Deno.test("near-limit legacy descriptions do not expand the durable representation into base64", async () => {
  const texts = Array(16).fill("a".repeat(65_530));
  const canonical = initialCanonicalText(texts);
  const { result, pages } = await collect(1, canonical);
  assertEquals(result.canonical, canonical);
  assertEquals(
    result.reference.ordered_description_digest,
    await initialDigest("descriptions", canonical),
  );
  assertEquals(pages, 48);
});
Deno.test("proven empty sets preserve their original domain and have no addressable pages", async () => {
  const legacy = await collect(1, "[]"), current = await collect(2, "[]");
  assertEquals(legacy.result.descriptions, []);
  assertEquals(current.result.descriptions, []);
  assert(
    legacy.result.reference.ordered_description_digest !==
      current.result.reference.ordered_description_digest,
  );
  await assertRejects(() =>
    completionDescriptionPage(current.result.reference, "[]", 0, 0)
  );
});
Deno.test("invalid original representations fail without normalizing or replacing bytes", async (t) => {
  for (
    const [label, version, canonical] of [
      ["bad UTF8", 2, '[{"text_utf8_base64":"/w=="}]'],
      ["alternate base64 spelling", 2, '[{"text_utf8_base64":"YR=="}]'],
      ["extra context key", 2, '[{"extra":1,"text_utf8_base64":"YQ=="}]'],
      ["too many scalars", 2, cpm(["a".repeat(8193)])],
      [
        "aggregate UTF16 bound",
        2,
        cpm([
          "a".repeat(8001),
          "a".repeat(8001),
          "a".repeat(8001),
          "a".repeat(8001),
        ]),
      ],
      ["too many items", 2, cpm(Array(65).fill(""))],
      ["legacy blank", 1, '[" "]'],
      ["legacy item bound", 1, initialCanonicalText(["a".repeat(65_531)])],
    ] as const
  ) {
    await t.step(label, async () => {
      await assertRejects(() =>
        snapshotCompletionDescriptions(version, canonical)
      );
    });
  }
});
Deno.test("page producer rejects changed original digest and invalid offsets", async () => {
  const original = cpm(["x"]), changed = cpm(["y"]);
  const { reference } = await snapshotCompletionDescriptions(2, original);
  await assertRejects(() =>
    completionDescriptionPage(reference, changed, 0, 0)
  );
  for (const offset of [-1, -0, 1, 1.5, Infinity]) {
    await assertRejects(() =>
      completionDescriptionPage(reference, original, 0, offset)
    );
  }
});
Deno.test("collector rejects malformed, replayed, reordered and nonprogressing pages and remains poisoned", async (t) => {
  const canonical = cpm(["a" + "🦋".repeat(8191)]);
  const { reference } = await snapshotCompletionDescriptions(2, canonical);
  const first = await completionDescriptionPage(reference, canonical, 0, 0);
  const original = JSON.parse(first);
  const mutations: Record<string, unknown>[] = [
    { item_index: 1 },
    { byte_offset: 1 },
    { next_byte_offset: 0 },
    { next_byte_offset: null },
    { total_byte_count: 1 },
    { total_byte_count: 32_769 },
    { bytes_utf8_base64: "" },
    { ordered_description_digest: "a".repeat(64) },
    { extra: true },
  ];
  for (const [index, mutation] of mutations.entries()) {
    await t.step(String(index), async () => {
      const collector = createCompletionDescriptionCollector(reference);
      assertThrows(() =>
        collector.append(initialCanonicalText({ ...original, ...mutation }))
      );
      assertThrows(() => collector.append(first));
      await assertRejects(() => collector.finish());
    });
  }
  const collector = createCompletionDescriptionCollector(reference);
  collector.append(first);
  assertThrows(() => collector.append(first));
  await assertRejects(() => collector.finish());
});
Deno.test("valid-looking changed bytes cannot become reusable evidence and incomplete finish is terminal", async () => {
  const canonical = cpm(["a"]);
  const { reference } = await snapshotCompletionDescriptions(2, canonical);
  const wire = await completionDescriptionPage(reference, canonical, 0, 0);
  const changed = { ...JSON.parse(wire), bytes_utf8_base64: "Yg==" };
  const collector = createCompletionDescriptionCollector(reference);
  collector.append(initialCanonicalText(changed));
  await assertRejects(() => collector.finish());
  assertThrows(() => collector.append(wire));
  const incomplete = createCompletionDescriptionCollector(reference);
  await assertRejects(() => incomplete.finish());
  assertThrows(() => incomplete.append(wire));
});
