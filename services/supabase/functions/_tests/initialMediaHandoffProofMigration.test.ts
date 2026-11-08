import { assert, assertEquals } from "@std/assert";
import schema from "../_shared/initialAnalysis/media-handoff-proof-schema-v1.json" with {
  type: "json",
};
import vectors from "../_shared/initialAnalysis/fixtures/media-handoff-proof-v1.json" with {
  type: "json",
};
import originals from "../_shared/initialAnalysis/fixtures/admitted-proof-v1.json" with {
  type: "json",
};
import { MEDIA_HANDOFF_PROOF_LIMITS } from "../_shared/initialAnalysis/mediaHandoffProof.ts";
const sql = await Deno.readTextFile(
  new URL(
    "../../migrations/20261013082827_prepare_initial_media_handoff_proof.sql",
    import.meta.url,
  ),
);
const tests = await Deno.readTextFile(
  new URL("../../tests/initial_media_handoff_proof.sql", import.meta.url),
);
Deno.test("media handoff SQL embeds exact accepted schemas, proof chains and originals", () => {
  assertEquals(JSON.parse(sql.match(/\$json\$(.*?)\$json\$/s)![1]), schema);
  assertEquals(
    JSON.parse(tests.match(/\$vectors\$(.*?)\$vectors\$/s)![1]),
    vectors,
  );
  assertEquals(
    JSON.parse(tests.match(/\$originals\$(.*?)\$originals\$/s)![1]),
    originals,
  );
});
Deno.test("media handoff SQL is private invoker-only pure validation, never a runtime owner", () => {
  assertEquals([...sql.matchAll(/CREATE FUNCTION /g)].length, 4);
  assertEquals(
    [...sql.matchAll(/SECURITY INVOKER SET search_path=''/g)].length,
    4,
  );
  assert(
    !/SECURITY DEFINER|GRANT EXECUTE|CREATE OR REPLACE|CREATE TABLE|CREATE TRIGGER|INSERT INTO |UPDATE internal\.|DELETE FROM |FOR UPDATE|pg_advisory|clock_timestamp/
      .test(sql),
  );
  assert(sql.includes("FROM PUBLIC,anon,authenticated,service_role"));
  assert(sql.includes("internal.validate_initial_admitted_proof("));
  assert(sql.includes("'authority','none'"));
  const signature = sql.match(
    /CREATE FUNCTION internal.validate_initial_media_handoff_proof\(([\s\S]*?)\) RETURNS JSONB/,
  )![1];
  assertEquals([...signature.matchAll(/\bTEXT\b/g)].length, 16);
  for (const [kind, cap] of Object.entries(MEDIA_HANDOFF_PROOF_LIMITS)) {
    assert(sql.includes(`WHEN '${kind}' THEN ${cap}`));
  }
  assert(
    sql.indexOf("octet_length(p_text)>cap") < sql.indexOf("p_text::JSONB"),
  );
  assert(sql.includes("jsonb_array_length(v->'objects')=0"));
});
Deno.test("media handoff SQL retains canonical domains and staged NULL semantics", () => {
  for (
    const domain of [
      "verification-claim.v2",
      "verification-receipt.v2",
      "transfer-receipt.v1",
    ]
  ) assert(sql.includes(`'${domain}'`));
  assert(
    sql.includes(
      "'merian.initial-analysis.handoff.'||domain_name||pg_catalog.chr(10)||p_text",
    ),
  );
  assert(
    sql.includes(
      "p_verification_receipt IS NOT NULL OR p_transfer_receipt IS NOT NULL",
    ),
  );
  assert(
    sql.includes(
      "p_kind='verification_receipt' AND p_transfer_receipt IS NOT NULL",
    ),
  );
});
