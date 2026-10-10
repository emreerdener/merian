import { assert } from "@std/assert";
Deno.test("video allocation keeps execution and erasure boundaries closed", async () => {
  const sql = await Deno.readTextFile(
    new URL(
      "../../migrations/20261010054046_prepare_video_evidence_allocation.sql",
      import.meta.url,
    ),
  );
  for (
    const required of [
      "video_evidence_enabled BOOLEAN NOT NULL DEFAULT FALSE",
      "ENABLE ROW LEVEL SECURITY",
      "observation_video_source_preexecution_clear",
      "observation_video_evidence_execution_clear",
      "expire_unbound_observation_evidence(uuid)",
      "expire_observation_evidence(uuid)",
      "merian-history-object:",
      "p_media UUID,p_object UUID",
      "item->'ready_at'<>'null'::JSONB",
      "internal.video_evidence_receipt(binding)",
      "private_evidence_erasure_enabled",
      "date_trunc('milliseconds',clock_timestamp())",
      "ON DELETE CASCADE",
    ]
  ) assert(sql.includes(required), required);
  assert(!/GRANT EXECUTE[^;]+TO (?:anon|authenticated)/.test(sql));
  assert(
    !/CREATE (?:OR REPLACE )?FUNCTION (?:public|internal)\.(?:dispatch|execute|refund|admit)_/
      .test(sql),
  );
});
