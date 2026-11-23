import { assert, assertEquals } from "@std/assert";
import { COMPOSITION_SOURCE_READER_VERSION } from "../_shared/analysisHistory/compositionSourceReservation.ts";
const source = await Deno.readTextFile(
  new URL(
    "../../migrations/20261114212929_prepare_composition_source_ownership.sql",
    import.meta.url,
  ),
);
Deno.test("composition ownership remains closed and independent of deployed source readers", () => {
  assertEquals(COMPOSITION_SOURCE_READER_VERSION, 14);
  assert(source.includes("p_reader IS DISTINCT FROM 14"));
  for (
    const gate of [
      "composition_source_reservation_enabled",
      "composition_source_recovery_enabled",
      "composition_runtime_enabled",
    ]
  ) {
    assert(source.includes(`${gate} BOOLEAN NOT NULL DEFAULT FALSE`));
  }
  assert(!/UPDATE\s+internal\.observation_history_rollout\s+SET/i.test(source));
  // This migration may reserve metadata, but cannot create any upload, quota,
  // dispatch, provider execution or release entry point.
  assert(
    !/CREATE (?:OR REPLACE )?FUNCTION (?:public|internal)\.(?:advance|claim|complete|release|retire|reserve_owned_observation_composition_evidence)/i
      .test(source),
  );
  assertEquals(
    (source.match(/GRANT EXECUTE ON FUNCTION public\./g) ?? []).length,
    2,
  );
  assert(
    source.includes(
      "Reader14 schema3 exact V5 metadata reservation, default closed",
    ),
  );
});
