import { assert, assertEquals, assertThrows } from "@std/assert";
import { HistoryError } from "./contract.ts";
import {
  decodeSourceDiscovery,
  parseSourceDiscovery,
  parseSourceDiscoveryRequest,
  SOURCE_DISCOVERY_MAX_BYTES,
} from "./sourceDiscovery.ts";

const owner = "10000000-0000-4000-8000-000000000001";
const request = {
  schema_version: 1 as const,
  observation_id: "20000000-0000-4000-8000-000000000001",
  source_analysis_id: "30000000-0000-4000-8000-000000000001",
};
const scope = { ...request, owner_id: owner };
const existing = {
  ...scope,
  state: "existing",
  analysis_id: "40000000-0000-4000-8000-000000000001",
  request_digest: "a".repeat(64),
  phase: "admitted",
} as const;
const encode = (value: unknown) =>
  new TextEncoder().encode(JSON.stringify(value));
const reject = (value: unknown) =>
  assertThrows(
    () => parseSourceDiscovery(value, request, owner),
    HistoryError,
    "invalid_analysis_history",
  );

Deno.test("source discovery requires an exact immutable source request", () => {
  assertEquals(parseSourceDiscoveryRequest(request), request);
  assert(Object.isFrozen(parseSourceDiscoveryRequest(request)));
  for (
    const value of [
      null,
      [],
      { ...request, schema_version: 2 },
      { ...request, owner_id: owner },
      { ...request, source_analysis_id: null },
      { ...request, source_analysis_id: request.observation_id },
      { ...request, source_analysis_id: "invalid" },
      { schema_version: 1, observation_id: request.observation_id },
    ]
  ) assertThrows(() => parseSourceDiscoveryRequest(value), HistoryError);
});

Deno.test("source discovery accepts every closed informational variant", () => {
  const variants = [
    ...["advisory_absence", "history_only", "unavailable"].map((state) => ({
      ...scope,
      state,
    })),
    ...["reserved", "admitted", "dispatched", "draft"].map((phase) => ({
      ...existing,
      phase,
    })),
    ...[
      "ambiguous_occupancy",
      "malformed_linkage",
      "coverage_incomplete",
      "terminal_unproven",
    ].map((reason) => ({ ...scope, state: "held", reason })),
  ];
  for (const value of variants) {
    const result = decodeSourceDiscovery(encode(value), request, owner);
    assertEquals(result, value);
    assert(Object.isFrozen(result));
    assert(!("can_dispatch" in result));
    assert(!("can_reserve" in result));
  }
});

Deno.test("source discovery rejects owner, parent and source substitution in every state", () => {
  for (
    const value of [
      existing,
      { ...scope, state: "advisory_absence" },
      { ...scope, state: "history_only" },
      { ...scope, state: "held", reason: "coverage_incomplete" },
      { ...scope, state: "unavailable" },
    ]
  ) {
    for (const field of ["owner_id", "observation_id", "source_analysis_id"]) {
      reject({ ...value, [field]: "50000000-0000-4000-8000-000000000001" });
    }
    reject({ ...value, schema_version: 2 });
  }
  assertThrows(
    () => parseSourceDiscovery(existing, request, "invalid"),
    HistoryError,
  );
});

Deno.test("source discovery cannot leak private context or accept execution permissions", () => {
  for (
    const key of [
      "input",
      "media_path",
      "quota",
      "work_token",
      "receipt",
      "provider_response",
      "can_dispatch",
      "can_reserve",
      "expires_at",
      "next_attempt_id",
    ]
  ) reject({ ...existing, [key]: "unexpected" });
  reject({
    ...scope,
    state: "history_only",
    analysis_id: existing.analysis_id,
  });
  reject({
    ...scope,
    state: "advisory_absence",
    reason: "coverage_incomplete",
  });
  reject({
    ...scope,
    state: "held",
    reason: "ambiguous_occupancy",
    operations: [existing],
  });
});

Deno.test("source discovery rejects incomplete, ambiguous and unknown envelopes", () => {
  for (const value of [null, undefined, [], [existing], {}, "absent"]) {
    reject(value);
  }
  for (const key of Object.keys(existing)) {
    const value: Record<string, unknown> = { ...existing };
    delete value[key];
    reject(value);
  }
  for (
    const state of ["absent", "complete", "retired", "ready", "retry", null]
  ) {
    reject({ ...scope, state });
  }
  reject({ ...scope, state: "held", reason: "retry_limit" });
  reject({ ...scope, state: "unavailable", reason: "private_detail" });
});

Deno.test("source discovery existing operation requires exact child, digest and phase", () => {
  for (
    const analysis_id of [
      null,
      "invalid",
      request.observation_id,
      request.source_analysis_id,
    ]
  ) {
    reject({ ...existing, analysis_id });
  }
  for (
    const request_digest of [
      null,
      "a".repeat(63),
      "a".repeat(65),
      "A".repeat(64),
      "z".repeat(64),
    ]
  ) {
    reject({ ...existing, request_digest });
  }
  for (
    const phase of [
      null,
      "complete",
      "failed_terminal",
      "expired",
      "ready_to_retry",
    ]
  ) {
    reject({ ...existing, phase });
  }
});

Deno.test("source discovery bounds actual bytes before JSON decoding", () => {
  const text = JSON.stringify(existing);
  const atLimit = new TextEncoder().encode(
    text.padEnd(SOURCE_DISCOVERY_MAX_BYTES, " "),
  );
  assertEquals(decodeSourceDiscovery(atLimit, request, owner), existing);
  assertThrows(
    () =>
      decodeSourceDiscovery(
        new Uint8Array(SOURCE_DISCOVERY_MAX_BYTES + 1),
        request,
        owner,
      ),
    HistoryError,
  );
  // Whitespace does not avoid the actual transport-body budget.
  assertThrows(
    () =>
      decodeSourceDiscovery(
        new TextEncoder().encode(text.padEnd(SOURCE_DISCOVERY_MAX_BYTES + 1)),
        request,
        owner,
      ),
    HistoryError,
  );
});

Deno.test("source discovery invalid bytes and failed reads never become advisory absence", () => {
  for (
    const bytes of [
      new Uint8Array(),
      new Uint8Array([0xff]),
      new TextEncoder().encode("{"),
      encode(null),
      encode({ error: "unavailable" }),
    ]
  ) {
    assertThrows(
      () => decodeSourceDiscovery(bytes, request, owner),
      HistoryError,
    );
  }
});
