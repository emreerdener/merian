import { assert, assertEquals, assertRejects, assertThrows } from "@std/assert";
import { Client } from "https://deno.land/x/postgres@v0.19.3/mod.ts";
import vectors from "../_shared/analysisHistory/fixtures/video-source-fingerprint-v1.json" with {
  type: "json",
};
import {
  videoSourceCanonicalBytes,
  videoSourceFingerprint,
} from "../_shared/analysisHistory/videoSourceFingerprint.ts";
const databaseUrl = Deno.env.get("SUPABASE_DB_TEST_URL");
Deno.test({
  name:
    "Held video fingerprint DB parity - golden bytes, semantic integers and closed metadata",
  ignore: !databaseUrl,
  async fn() {
    assert(
      databaseUrl &&
        ["127.0.0.1", "localhost", "[::1]"].includes(
          new URL(databaseUrl).hostname,
        ),
    );
    const db = new Client(databaseUrl);
    await db.connect();
    const readRaw = async (json: string) =>
      (await db.queryObject<{ bytes: string; hash: string }>(
        "SELECT encode(internal.observation_video_source_fingerprint_bytes($1::jsonb),'hex') bytes, internal.observation_video_source_fingerprint($1::jsonb) hash",
        [json],
      )).rows[0];
    const read = (value: unknown) => readRaw(JSON.stringify(value));
    const parity = async (value: unknown) => {
      let bytes: Uint8Array;
      try {
        bytes = videoSourceCanonicalBytes(value);
      } catch {
        await assertRejects(() => read(value));
        return;
      }
      assertEquals(await read(value), {
        bytes: Array.from(bytes, (x) => x.toString(16).padStart(2, "0")).join(
          "",
        ),
        hash: await videoSourceFingerprint(value),
      });
    };
    function mutations(value: unknown): unknown[] {
      if (Array.isArray(value)) {
        return value.flatMap((item, index) =>
          mutations(item).map((child) =>
            value.map((x, i) => i === index ? child : x)
          )
        );
      }
      if (value !== null && typeof value === "object") {
        return Object.entries(value).flatMap(([key, item]) =>
          mutations(item).map((child) => ({ ...value, [key]: child }))
        );
      }
      return [null, true, "invalid", typeof value === "number" ? value + 1 : 0];
    }
    try {
      for (const vector of vectors) {
        assertEquals(await read(vector.input), {
          bytes: vector.canonical_utf8_hex,
          hash: vector.sha256,
        });
        await parity(vector.input);
      }
      for (const terminator of ["\n", "\r", "\u2028", "\u2029"]) {
        for (const field of ["observation_id", "request_digest"] as const) {
          const input = structuredClone(vectors[0].input);
          input[field] += terminator;
          assertThrows(() => videoSourceCanonicalBytes(input));
          await assertRejects(() => read(input));
        }
        for (const field of ["media_id", "sha256"] as const) {
          const input = structuredClone(vectors[0].input);
          input.evidence_manifest.provenance.source[field] += terminator;
          assertThrows(() => videoSourceCanonicalBytes(input));
          await assertRejects(() => read(input));
        }
      }
      const changed = mutations(vectors[0].input);
      assert(changed.length > 320);
      for (const candidate of changed) await parity(candidate);
      for (
        const text of [
          "é",
          "e\u0301",
          "🦋",
          "\u0085",
          "\u200b",
          "x\ufeff",
          "x".repeat(8192),
          "",
          " \n",
          "\ufeff",
          "\u2028",
          "x".repeat(8193),
          "a\u0000b",
          "a\ud800b",
        ]
      ) {
        const input = structuredClone(vectors[0].input);
        input.evidence_manifest.descriptions = [text];
        await parity(input);
      }
      for (
        const descriptions of [
          Array(64).fill("x"),
          Array(65).fill("x"),
          Array(4).fill("x".repeat(8000)),
          [...Array(4).fill("x".repeat(8000)), "x"],
        ]
      ) {
        const input = structuredClone(vectors[0].input);
        input.evidence_manifest.descriptions = descriptions;
        await parity(input);
      }
      for (const count of [60, 65, 3000]) {
        const input = structuredClone(vectors[1].input);
        const g = input.evidence_manifest.provenance;
        g.parameters.duration_ticks = count;
        g.frames.forEach((frame, i) => {
          frame.requested_time_ticks = Math.min(
            Math.max(Math.floor(count * (1 + 2 * i) / 10 + 0.5), 30),
            count - 30,
          );
          frame.actual_time_ticks = frame.requested_time_ticks;
        });
        await parity(input);
      }
      const row = structuredClone(vectors[0].input);
      row.evidence_manifest.provenance.parameters.crop_center_basis_points = 0;
      const json = JSON.stringify(row);
      for (const numeric of ["-0", "-0.0", "0.0", "0e0"]) {
        assertEquals(
          await readRaw(
            json.replace(
              '"crop_center_basis_points":0',
              '"crop_center_basis_points":' + numeric,
            ),
          ),
          await read(row),
        );
      }
      assertEquals(
        await readRaw(json.replaceAll(":100,", ":1e2,")),
        await read(row),
      );
      for (
        const key of ["observation_id", "analysis_id", "source_analysis_id"]
      ) {
        const alias = structuredClone(vectors[0].input);
        alias.evidence_manifest.provenance.source.media_id =
          alias[key as keyof typeof alias] as string;
        await parity(alias);
      }
      const duplicate = structuredClone(vectors[0].input);
      duplicate.evidence_manifest.provenance.frames[1].artifact.media_id =
        duplicate.evidence_manifest.provenance.frames[0].artifact.media_id;
      await parity(duplicate);
      const extra = { ...vectors[0].input, owner_id: "unexpected" };
      await parity(extra);
      const reversed = structuredClone(vectors[0].input);
      reversed.evidence_manifest.provenance.frames.reverse();
      await parity(reversed);
      for (
        const bad of [null, {}, [], { ...vectors[0].input, schema_version: 3 }]
      ) await parity(bad);
    } finally {
      await db.end();
    }
  },
});
