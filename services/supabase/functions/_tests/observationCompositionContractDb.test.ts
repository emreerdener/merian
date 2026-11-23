import { assert, assertEquals, assertRejects } from "@std/assert";
import { Client } from "https://deno.land/x/postgres@v0.19.3/mod.ts";
import vectors from "../_shared/analysisHistory/fixtures/composition-request-v5.json" with {
  type: "json",
};
import { compositionFingerprint } from "../_shared/analysisHistory/compositionFingerprint.ts";
import { compositionCohortItems } from "../_shared/analysisHistory/compositionCohort.ts";

const databaseUrl = Deno.env.get("SUPABASE_DB_TEST_URL");

// Change every leaf, omit every object field, and add unknown fields at every
// object level. Valid semantic changes must agree, not merely both be rejected.
function mutations(value: unknown): unknown[] {
  if (Array.isArray(value)) {
    return value.flatMap((child, index) =>
      mutations(child).map((next) =>
        value.map((item, position) => position === index ? next : item)
      )
    );
  }
  if (value !== null && typeof value === "object") {
    return [
      { ...value, unexpected: true },
      ...Object.entries(value).flatMap(([key, child]) => {
        const omitted = { ...value } as Record<string, unknown>;
        delete omitted[key];
        return [
          omitted,
          ...mutations(child).map((next) => ({ ...value, [key]: next })),
        ];
      }),
    ];
  }
  return [null, true, "invalid", typeof value === "number" ? value + 1 : 0];
}

Deno.test({
  name:
    "composition SQL fingerprint and complete inventory agree with Edge; API roles remain denied",
  ignore: !databaseUrl,
  async fn() {
    assert(
      databaseUrl &&
        ["localhost", "127.0.0.1", "[::1]"].includes(
          new URL(databaseUrl).hostname,
        ),
    );
    const db = new Client(databaseUrl);
    await db.connect();
    const readRaw = async (value: string) =>
      (await db.queryObject<{ contract: unknown }>(
        "SELECT internal.observation_composition_source_contract($1::jsonb) contract",
        [value],
      )).rows[0].contract;
    const read = (value: unknown) => readRaw(JSON.stringify(value));
    const parity = async (value: unknown) => {
      let expected;
      try {
        expected = {
          fingerprint: await compositionFingerprint(value),
          items: compositionCohortItems(value),
        };
      } catch {
        await assertRejects(() => read(value));
        return;
      }
      assertEquals(await read(value), expected);
    };
    try {
      for (const vector of vectors) {
        await parity(vector.input);
        if (vector.valid) {
          assertEquals(
            (await read(vector.input) as { fingerprint: string }).fingerprint,
            vector.fingerprint,
          );
        }
      }
      const mixed = vectors.find((vector) => vector.name === "photo-video");
      assert(mixed?.valid);
      for (const changed of mutations(mixed.input)) await parity(changed);
      for (
        const text of [
          "",
          " \n",
          "\ufeff",
          "\u200b",
          "\u0085",
          "🦋 e\u0301",
          "a\0b",
          "a\ud800b",
          "a\udfffb",
          "x".repeat(8193),
        ]
      ) {
        const base = structuredClone(vectors[0].input);
        await parity({
          ...base,
          evidence_manifest: {
            schema_version: 5,
            items: [
              ...base.evidence_manifest.items,
              { kind: "description", text },
            ],
          },
        });
      }
      const raw = JSON.stringify(vectors[0].input);
      const withItems = (items: unknown[]) => ({
        ...vectors[0].input,
        evidence_manifest: { schema_version: 5, items },
      });
      const photo = vectors[0].input.evidence_manifest.items[0];
      for (
        const descriptions of [
          Array(63).fill("x"),
          Array(64).fill("x"),
          ["🦋".repeat(8192)],
          ["🦋".repeat(8193)],
          Array(4).fill("x".repeat(8000)),
          [...Array(4).fill("x".repeat(8000)), "x"],
        ]
      ) {
        await parity(
          withItems([
            photo,
            ...descriptions.map((text) => ({ kind: "description", text })),
          ]),
        );
      }
      const five = vectors.find((vector) => vector.name === "five-photos");
      assert(five?.valid);
      const boundedImages = five.input.evidence_manifest.items.map((node) => ({
        ...node,
        artifact: { ...node.artifact, byte_count: 1_048_576 },
      }));
      await parity(withItems(boundedImages));
      boundedImages[0].artifact.byte_count++;
      await parity(withItems(boundedImages));
      const videoPhoto = structuredClone(mixed.input);
      const still = videoPhoto.evidence_manifest.items.find((node) =>
        node.kind === "image"
      );
      const clip = videoPhoto.evidence_manifest.items.find((node) =>
        node.kind === "video"
      );
      assert(
        still?.artifact && clip && "provenance" in clip && clip.provenance,
      );
      clip.provenance.frames.forEach((frame) => {
        frame.artifact.byte_count = 100;
      });
      still.artifact.byte_count = 5_242_880 - 500;
      await parity(videoPhoto);
      still.artifact.byte_count++;
      await parity(videoPhoto);
      const twoAudio = vectors.find((vector) => vector.name === "two-audio");
      assert(twoAudio?.valid);
      const boundedAudio = twoAudio.input.evidence_manifest.items.map((
        node,
      ) => ({
        ...node,
        artifact: { ...node.artifact, byte_count: 2_700_000 },
      }));
      await parity(withItems(boundedAudio));
      boundedAudio[0].artifact.byte_count++;
      await parity(withItems(boundedAudio));
      assertEquals(
        await readRaw(raw.replace('"byte_count":100', '"byte_count":1e2')),
        await read(vectors[0].input),
      );
      for (
        const invalid of [null, {}, [], {
          ...vectors[0].input,
          schema_version: 4,
        }]
      ) await parity(invalid);
      for (const role of ["anon", "authenticated", "service_role"]) {
        await db.queryArray(`SET ROLE ${role}`);
        try {
          await assertRejects(() => read(vectors[0].input));
        } finally {
          await db.queryArray("RESET ROLE");
        }
      }
    } finally {
      await db.end();
    }
  },
});
