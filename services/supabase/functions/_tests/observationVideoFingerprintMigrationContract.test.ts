import { assert, assertEquals } from "@std/assert";
const source = await Deno.readTextFile(
  new URL(
    "../../migrations/20261010005747_prepare_video_source_fingerprint_parity.sql",
    import.meta.url,
  ),
);
Deno.test("held video fingerprint SQL remains pure private stable encoding with no grants or writes", () => {
  assertEquals(
    (source.match(/STABLE SECURITY INVOKER SET search_path=''/g) ?? [])
      .length,
    4,
  );
  assertEquals(
    (source.match(
      /REVOKE ALL ON FUNCTION internal\.observation_video_source_fingerprint(?:_bytes)?\(JSONB\) FROM PUBLIC,anon,authenticated,service_role/g,
    ) ?? []).length,
    2,
  );
  assert(
    !/\b(?:INSERT|UPDATE|DELETE|GRANT|SECURITY DEFINER|CREATE TABLE)\b/.test(
      source,
    ),
  );
  assert(source.includes("octet_length(framed)>262144"));
  assert(source.includes("convert_to(field,'UTF8')"));
  assert(source.includes("merian.analysis-video-source-binding"));
  assert(source.includes("multimodal_video_frames_v1"));
  assert(source.includes("multimodal_video_audio_v1"));
});
