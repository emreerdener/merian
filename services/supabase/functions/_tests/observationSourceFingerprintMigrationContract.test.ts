import { assert, assertEquals } from "@std/assert";
const source = await Deno.readTextFile(
  new URL(
    "../../migrations/20261008164349_prepare_source_fingerprint_parity.sql",
    import.meta.url,
  ),
);
Deno.test("source fingerprint SQL remains pure private stable encoding with no grants or writes", () => {
  assertEquals(
    (source.match(/STABLE SECURITY INVOKER SET search_path=''/g) ?? [])
      .length,
    2,
  );
  assertEquals(
    (source.match(
      /REVOKE ALL ON FUNCTION internal\.observation_source_fingerprint(?:_bytes)?\(JSONB\) FROM PUBLIC,anon,authenticated,service_role/g,
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
  assert(source.includes("merian.analysis-source-reservation"));
  assert(source.includes("multimodal_photo_v1"));
  assert(source.includes("multimodal_audio_v1"));
});
