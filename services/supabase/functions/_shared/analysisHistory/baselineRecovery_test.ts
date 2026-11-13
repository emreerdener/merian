import { assertEquals, assertRejects, assertThrows } from "@std/assert";
import { HistoryError } from "./contract.ts";
import {
  enrollmentBaselineDigest,
  parseBaselineRecovery,
  parseBaselineRecoveryRequest,
} from "./baselineRecovery.ts";

const page = JSON.parse(
  await Deno.readTextFile(
    new URL("./fixtures/page-v3.json", import.meta.url),
  ),
);
const enrollment = JSON.parse(
  await Deno.readTextFile(
    new URL("./fixtures/enrollment-v1.json", import.meta.url),
  ),
);
const snapshot = page.items[0].snapshot as string;
const request = parseBaselineRecoveryRequest({
  schema_version: 1,
  observation_id: enrollment.observation_id,
});
const response = {
  ...enrollment,
  snapshot,
  snapshot_sha256: await enrollmentBaselineDigest(snapshot),
};
const sharedFixture = JSON.parse(
  await Deno.readTextFile(
    new URL("./fixtures/baseline-recovery-v1.json", import.meta.url),
  ),
);

Deno.test("baseline recovery preserves exact bytes without selected state or original intent", async () => {
  assertEquals(response, sharedFixture);
  assertEquals(
    await parseBaselineRecovery(response, request, enrollment.owner_id),
    response,
  );
  const whitespace = snapshot + "\n";
  const changed = {
    ...response,
    snapshot: whitespace,
    snapshot_sha256: await enrollmentBaselineDigest(whitespace),
  };
  assertEquals(
    await parseBaselineRecovery(changed, request, enrollment.owner_id),
    changed,
  );
  await assertRejects(
    () =>
      parseBaselineRecovery(
        { ...response, snapshot: whitespace },
        request,
        enrollment.owner_id,
      ),
    HistoryError,
  );
});

Deno.test("baseline recovery denies forged or ambiguous association and non-baseline snapshots", async () => {
  for (
    const patch of [
      { schema_version: 2 },
      { owner_id: enrollment.observation_id },
      { observation_id: enrollment.owner_id },
      { baseline_analysis_id: enrollment.owner_id },
      { baseline_analysis_id: "00000000-0000-4000-8000-000000000099" },
      { snapshot_sha256: "A".repeat(64) },
      { snapshot_sha256: "0".repeat(64) },
      { snapshot: " ".repeat(1048577) },
      { snapshot: null },
      { selected_analysis_id: enrollment.baseline_analysis_id },
      { intent_id: enrollment.owner_id },
    ]
  ) {
    await assertRejects(
      () =>
        parseBaselineRecovery(
          { ...response, ...patch },
          request,
          enrollment.owner_id,
        ),
      HistoryError,
    );
  }
  for (
    const patch of [
      { ordinal: 2 },
      { observation_id: enrollment.owner_id },
      { schema_version: 1 },
      { request_digest: "a".repeat(64) },
      {
        evidence_manifest: {
          schema_version: 3,
          origin: "provider",
          availability: "unavailable",
          imported_at_ms: 1,
        },
      },
    ]
  ) {
    const changed = JSON.stringify({ ...JSON.parse(snapshot), ...patch });
    const digest = await enrollmentBaselineDigest(changed);
    await assertRejects(
      () =>
        parseBaselineRecovery(
          { ...response, snapshot: changed, snapshot_sha256: digest },
          request,
          enrollment.owner_id,
        ),
      HistoryError,
    );
  }
  for (
    const patch of [{ schema_version: 2 }, { observation_id: null }, {
      owner_id: enrollment.owner_id,
    }]
  ) {
    assertThrows(
      () => parseBaselineRecoveryRequest({ ...request, ...patch }),
      HistoryError,
    );
  }
});
