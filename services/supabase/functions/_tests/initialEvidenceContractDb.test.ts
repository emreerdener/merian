import { assert, assertEquals, assertRejects } from "@std/assert";
import { Client } from "https://deno.land/x/postgres@v0.19.3/mod.ts";
import {
  initialEvidenceArtifacts,
  initialEvidenceDigest,
  parseInitialEvidenceManifest,
} from "../_shared/analysisHistory/initialEvidenceManifest.ts";

const url = Deno.env.get("SUPABASE_DB_TEST_URL");
const id = (n: number) =>
  `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
const scan = id(1), generation = id(2);
const artifact = (n: number, content_type = "image/jpeg") => ({
  media_id: id(n),
  content_type,
  byte_count: 100,
  sha256: "a".repeat(64),
});
const photo = () => ({
  kind: "image",
  source: artifact(3),
  prepared: artifact(4),
  coordinate_basis: "prepared_image_top_left_v1",
  focus_region: {
    x: 0.1,
    y: 0.2,
    width: 0.3,
    height: 0.4,
    source: "user_selection",
  },
});
const video = () => ({
  kind: "video",
  source: artifact(20, "video/mp4"),
  playback: artifact(5, "video/mp4"),
  frames: [artifact(6), artifact(7)],
  audio: {
    source: artifact(8, "audio/wav"),
    prepared: artifact(9, "audio/wav"),
  },
});
function mutations(value: unknown): unknown[] {
  if (Array.isArray(value)) {
    return value.flatMap((v, i) =>
      mutations(v).map((next) => value.map((old, j) => i === j ? next : old))
    );
  }
  if (value && typeof value === "object") {
    return [
      { ...value, unknown: true },
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
    "ordinary initial evidence SQL and Edge agree on roles, typed digest and rejection boundaries",
  ignore: !url,
  async fn() {
    assert(
      url &&
        ["localhost", "127.0.0.1", "[::1]"].includes(new URL(url).hostname),
    );
    const db = new Client(url);
    await db.connect();
    const read = async (value: unknown, scanID = scan, gen = generation) =>
      (await db.queryObject<{ contract: unknown }>(
        "SELECT internal.initial_evidence_contract($1::jsonb,$2,$3) contract",
        [JSON.stringify(value), scanID, gen],
      )).rows[0].contract;
    const parity = async (value: unknown, scanID = scan, gen = generation) => {
      let expected;
      try {
        expected = {
          evidence_digest: await initialEvidenceDigest(value, scanID, gen),
          items: initialEvidenceArtifacts(
            parseInitialEvidenceManifest(value, scanID, gen),
          ),
        };
      } catch {
        await assertRejects(() => read(value, scanID, gen));
        return;
      }
      assertEquals(await read(value, scanID, gen), expected);
    };
    const manifest = {
      schema_version: 7,
      items: [photo(), {
        kind: "description",
        text: "  Synthetic 🦋 e\u0301 context  ",
      }, video()],
    };
    try {
      await parity(manifest);
      const original = {
        ...photo(),
        source: { ...artifact(3), byte_count: 33_554_432 },
      };
      for (const version of [7, 8]) {
        const full = { schema_version: version, items: [original] };
        await parity(full);
        for (const changed of mutations(full)) await parity(changed);
        for (const count of [5_242_880, 5_242_881, 33_554_432, 33_554_433]) {
          await parity({
            schema_version: version,
            items: [{
              ...photo(),
              source: { ...artifact(3), byte_count: count },
            }],
          });
        }
      }
      const geometry = {
        schema_version: 1,
        coordinate_basis: "upright_source_top_left_v1",
        format: "nativeSelectedStillImageV2",
        crop_display_size: 390,
        quarter_turns: 1,
        scale: 1.5,
        offset_x: -30,
        offset_y: 25,
        camera_vertical_center: null,
        source_selection: {
          x: 0.2,
          y: 0.3,
          width: 0.1,
          height: 0.2,
          source: "user_selection",
        },
      };
      const geometric = {
        schema_version: 9,
        items: [{ ...original, preparation: geometry }],
      };
      await parity(geometric);
      for (const changed of mutations(geometric)) await parity(changed);
      for (const offset_x of [-0, 0, 5e-324, 1e-8, -1e8]) {
        await parity({
          ...geometric,
          items: [{ ...original, preparation: { ...geometry, offset_x } }],
        });
      }
      for (
        const preparation of [
          {
            ...geometry,
            crop_display_size: null,
            quarter_turns: 0,
            scale: 1,
            offset_x: 0,
            offset_y: 0,
          },
          { ...geometry, format: "nativeStillImageV1", source_selection: null },
          {
            ...geometry,
            format: "nativeStillImageV1",
            source_selection: null,
            crop_display_size: null,
            quarter_turns: 0,
            scale: 1,
            offset_x: 0,
            offset_y: 0,
          },
          {
            ...geometry,
            format: "nativeCameraStillV1",
            source_selection: null,
            crop_display_size: null,
            quarter_turns: 0,
            scale: 1,
            offset_x: 0,
            offset_y: 0,
            camera_vertical_center: 0.7,
          },
        ]
      ) await parity({ ...geometric, items: [{ ...original, preparation }] });
      for (const count of [22_369_621, 22_369_622]) {
        await parity({
          schema_version: 8,
          items: [0, 1, 2].map((n) => ({
            ...photo(),
            source: { ...artifact(30 + n), byte_count: count },
            prepared: artifact(40 + n),
          })),
        });
      }
      // Volatility classification must not alter the canonical digest or typed
      // inventory across session rendering settings.
      const canonical = await read(manifest);
      for (const zone of ["UTC", "America/Chicago", "Asia/Tokyo"]) {
        await db.queryArray("SELECT set_config('TimeZone',$1,false)", [zone]);
        for (const style of ["ISO, MDY", "SQL, DMY", "German, DMY"]) {
          await db.queryArray("SELECT set_config('DateStyle',$1,false)", [
            style,
          ]);
          assertEquals(await read(manifest), canonical);
        }
      }
      for (const changed of mutations(manifest)) await parity(changed);
      await parity(manifest, scan, scan);
      await parity(manifest, scan.toUpperCase(), generation);
      for (
        const focus of [
          null,
          { ...photo().focus_region, x: -0 },
          { ...photo().focus_region, x: 5e-324 },
          { ...photo().focus_region, x: 0.8 },
          { ...photo().focus_region, source: "vision_objectness" },
        ]
      ) {
        await parity({
          schema_version: 7,
          items: [{ ...photo(), focus_region: focus }],
        });
      }
      for (
        const text of [
          "",
          "\ufeff",
          "\u200b",
          "\u0085",
          "a\0b",
          "a\ud800",
          "🦋".repeat(8192),
          "x".repeat(8193),
        ]
      ) {
        await parity({
          schema_version: 7,
          items: [photo(), { kind: "description", text }],
        });
      }
      for (const n of [5242880 - 100, 5242880 - 99, 5242881]) {
        await parity({
          schema_version: 7,
          items: [{ ...photo(), source: { ...artifact(3), byte_count: n } }],
        });
      }
      await parity({
        schema_version: 7,
        items: [{
          kind: "audio",
          source: artifact(10, "audio/wav"),
          prepared: artifact(11, "audio/wav"),
        }, { ...video(), audio: null }],
      });
      await parity({ schema_version: 7, items: [video(), video()] });
      await parity({
        schema_version: 7,
        items: Array(64).fill({ kind: "description", text: "x" }),
      });
      for (const role of ["anon", "authenticated", "service_role"]) {
        await db.queryArray(`SET ROLE ${role}`);
        await assertRejects(() => read(manifest));
        await db.queryArray("RESET ROLE");
      }
    } finally {
      await db.end();
    }
  },
});
