import { assertEquals, assertThrows } from "@std/assert";
import {
  evaluateEvidenceErasureHealth,
  parseEvidenceErasureHealth,
} from "./monitor_observation_evidence_erasure.ts";

function healthy() {
  return {
    schema_version: 1 as const,
    generated_at: new Date().toISOString(),
    queue: {
      pending: 0,
      claimable: 0,
      deferred: 0,
      live_claims: 0,
      expired_claims: 0,
      unknown_age: 0,
      oldest_pending_age_seconds: 0,
      oldest_due_age_seconds: 0,
    },
    retirement: {
      photo: 0,
      audio: 0,
      video: 0,
      orphan: 0,
      objects: 0,
      oldest_age_seconds: 0,
      expired_unretirable_objects: 0,
      expired_bound_objects: 0,
    },
    worker: {
      enabled: true,
      cron_active: true,
      credentials_ready: true,
      admission_enabled: true,
      request_pending: false,
      request_age_seconds: null as number | null,
      last_result: "success",
      consecutive_failures: 0,
      success_age_seconds: 30 as number | null,
      marker_success_age_seconds: null as number | null,
    },
  };
}
Deno.test("empty aggregate needs a real recent successful heartbeat", () => {
  assertEquals(
    evaluateEvidenceErasureHealth(parseEvidenceErasureHealth(healthy())).status,
    "ok",
  );
  const h = healthy();
  h.worker.success_age_seconds = null;
  assertEquals(evaluateEvidenceErasureHealth(h).status, "critical");
});
Deno.test("backoff and live claims remain pending even with zero claimable work", () => {
  const h = healthy();
  Object.assign(h.queue, {
    pending: 2,
    deferred: 1,
    live_claims: 1,
    oldest_pending_age_seconds: 1800,
  });
  assertEquals(
    evaluateEvidenceErasureHealth(parseEvidenceErasureHealth(h)).status,
    "critical",
  );
});
Deno.test("unknown historical age is not a zero-age success", () => {
  const h = healthy();
  Object.assign(h.queue, { pending: 1, claimable: 1, unknown_age: 1 });
  assertEquals(
    evaluateEvidenceErasureHealth(parseEvidenceErasureHealth(h)).status,
    "critical",
  );
});
Deno.test("candidate cohort count is distinct from object drain capacity", () => {
  const h = healthy();
  Object.assign(h.retirement, { video: 9, objects: 63 });
  assertEquals(evaluateEvidenceErasureHealth(h).status, "warning");
  h.retirement.objects = 182;
  h.retirement.video = 26;
  assertEquals(evaluateEvidenceErasureHealth(h).status, "critical");
});
Deno.test("mixed health requires a V3 receipt even without pending cohorts", () => {
  for (const version of [null, 2, 3] as const) {
    const h = healthy();
    Object.assign(h.retirement, { composition: 0 });
    Object.assign(h.worker, { last_receipt_schema_version: version });
    const result = evaluateEvidenceErasureHealth(parseEvidenceErasureHealth(h));
    assertEquals(result.status, version === 3 ? "ok" : "critical");
    assertEquals(
      result.critical,
      version === 3 ? [] : ["composition_receipt_unverified"],
    );
  }
});
Deno.test("mixed cohorts use the existing aggregate object and age budgets", () => {
  const h = healthy();
  Object.assign(h.retirement, { composition: 8, objects: 64 });
  Object.assign(h.worker, { last_receipt_schema_version: 3 });
  assertEquals(
    evaluateEvidenceErasureHealth(parseEvidenceErasureHealth(h)).status,
    "warning",
  );
  h.retirement.oldest_age_seconds = 1800;
  assertEquals(
    evaluateEvidenceErasureHealth(parseEvidenceErasureHealth(h)).status,
    "critical",
  );
});
Deno.test("partial mixed health, invalid receipt generations and extra fields reject", () => {
  const candidates: unknown[] = [];
  for (const version of [undefined, 0, 1, 5, 2.5, "3", NaN]) {
    const h = healthy();
    Object.assign(h.retirement, { composition: 0 });
    if (version !== undefined) {
      Object.assign(h.worker, { last_receipt_schema_version: version });
    }
    candidates.push(h);
  }
  const partial = healthy();
  Object.assign(partial.worker, { last_receipt_schema_version: 3 });
  candidates.push(partial);
  for (const count of [-1, 0.5, NaN, "0"]) {
    const h = healthy();
    Object.assign(h.retirement, { composition: count });
    Object.assign(h.worker, { last_receipt_schema_version: 3 });
    candidates.push(h);
  }
  const extra = healthy();
  Object.assign(extra.retirement, {
    composition: 0,
    object_key: "synthetic-private-value",
  });
  Object.assign(extra.worker, { last_receipt_schema_version: 3 });
  candidates.push(extra);
  for (const candidate of candidates) {
    assertEquals(
      assertThrows(() => parseEvidenceErasureHealth(candidate), Error).message,
      "Invalid private evidence health aggregate",
    );
  }
});
function stageHealthy() {
  const h = healthy();
  return {
    ...h,
    schema_version: 2 as const,
    retirement: { ...h.retirement, composition: 0 },
    worker: { ...h.worker, last_receipt_schema_version: 4 as 2 | 3 | 4 | null },
    capture_stage: { ...h.queue, marker_failures: 0 },
  };
}
Deno.test("capture stage health requires observed V4 even with empty queues", () => {
  for (const version of [null, 2, 3, 4] as const) {
    const h = stageHealthy();
    h.worker.last_receipt_schema_version = version;
    const result = evaluateEvidenceErasureHealth(parseEvidenceErasureHealth(h));
    assertEquals(result.status, version === 4 ? "ok" : "critical");
    assertEquals(
      result.critical.includes("capture_stage_receipt_unverified"),
      version !== 4,
    );
  }
});
Deno.test("capture stage marker failures and unknown outcomes remain visible", () => {
  for (
    const [field, diagnostic] of [
      ["marker_failures", "capture_stage_marker_failure"],
      ["expired_claims", "capture_stage_claim_outcome_unknown"],
      ["unknown_age", "historical_backlog_age_unknown"],
    ] as const
  ) {
    const h = stageHealthy();
    Object.assign(h.capture_stage, { pending: 1, claimable: 1, [field]: 1 });
    const result = evaluateEvidenceErasureHealth(parseEvidenceErasureHealth(h));
    assertEquals(result.status, "critical");
    assertEquals(result.critical.includes(diagnostic), true);
  }
});
Deno.test("stage backlog shares the existing drain budget and oldest age", () => {
  const h = stageHealthy();
  Object.assign(h.queue, { pending: 30, claimable: 30 });
  Object.assign(h.capture_stage, { pending: 30, deferred: 30 });
  assertEquals(
    evaluateEvidenceErasureHealth(parseEvidenceErasureHealth(h)).status,
    "warning",
  );
  h.capture_stage.oldest_pending_age_seconds = 1800;
  assertEquals(
    evaluateEvidenceErasureHealth(parseEvidenceErasureHealth(h)).status,
    "critical",
  );
});
Deno.test("partial or identity-bearing stage health fails closed", () => {
  const h = stageHealthy();
  const { capture_stage: stage, ...missingStage } = h;
  const { composition: _composition, ...oldRetirement } = h.retirement;
  const { last_receipt_schema_version: _receipt, ...oldWorker } = h.worker;
  for (
    const candidate of [
      missingStage,
      { ...h, schema_version: 1 },
      { ...h, retirement: oldRetirement, worker: oldWorker },
      { ...h, capture_stage: { ...stage, marker_failures: 1 } },
      { ...h, capture_stage: { ...stage, pending: 1 } },
      { ...h, capture_stage: { ...stage, object_id: "synthetic" } },
    ]
  ) assertThrows(() => parseEvidenceErasureHealth(candidate), Error);
});
Deno.test("intent-bound expired evidence is retained while unbound holds are visible", () => {
  const h = healthy();
  h.retirement.expired_bound_objects = 200;
  assertEquals(evaluateEvidenceErasureHealth(h).status, "ok");
  h.retirement.expired_unretirable_objects = 1;
  assertEquals(evaluateEvidenceErasureHealth(h).status, "warning");
});
for (
  const flag of [
    "enabled",
    "cron_active",
    "credentials_ready",
    "admission_enabled",
  ] as const
) {
  Deno.test(`closed or misconfigured ${flag} is not healthy`, () => {
    const h = healthy();
    h.worker[flag] = false;
    assertEquals(evaluateEvidenceErasureHealth(h).status, "critical");
  });
}
Deno.test("missing, failed and stalled acknowledgements cannot reuse old success", () => {
  for (const result of ["unknown", "failure", "configuration_unavailable"]) {
    const h = healthy();
    h.worker.last_result = result;
    assertEquals(evaluateEvidenceErasureHealth(h).status, "critical");
  }
  const h = healthy();
  h.worker.request_pending = true;
  h.worker.request_age_seconds = 180;
  assertEquals(
    evaluateEvidenceErasureHealth(parseEvidenceErasureHealth(h)).status,
    "critical",
  );
});
Deno.test("malformed, extra, stale and identity-bearing responses are rejected", () => {
  for (
    const mutate of [
      (h: ReturnType<typeof healthy>) =>
        Object.assign(h, { object_id: "synthetic-private-value" }),
      (h: ReturnType<typeof healthy>) =>
        Object.assign(h.worker, { headers: "synthetic-private-value" }),
      (h: ReturnType<typeof healthy>) => h.queue.pending = NaN,
      (h: ReturnType<typeof healthy>) => h.queue.pending = 0.5,
      (h: ReturnType<typeof healthy>) => h.queue.pending = -1,
      (h: ReturnType<typeof healthy>) => h.queue.pending = 1,
      (h: ReturnType<typeof healthy>) => h.worker.request_pending = true,
      (h: ReturnType<typeof healthy>) =>
        h.generated_at = new Date(Date.now() - 31_000).toISOString(),
      (h: ReturnType<typeof healthy>) =>
        h.generated_at = new Date(Date.now() + 6_000).toISOString(),
      (h: ReturnType<typeof healthy>) => h.worker.last_result = "provider-body",
    ]
  ) {
    const h = healthy();
    mutate(h);
    const error = assertThrows(() => parseEvidenceErasureHealth(h), Error);
    assertEquals(error.message, "Invalid private evidence health aggregate");
  }
});
