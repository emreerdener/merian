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
