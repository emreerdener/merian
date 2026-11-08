import { assert, assertEquals, assertRejects, assertThrows } from "@std/assert";
import {
  buildVideoSourceRecoveryRequest,
  decodeVideoSourceRecoveryReceipt,
  decodeVideoSourceRecoveryRequest,
  decodeVideoSourceReservationReceipt,
  decodeVideoSourceReservationRequest,
  parseVideoSourceReservationRequest,
  VIDEO_SOURCE_MAX_RECEIPT_BYTES,
  VIDEO_SOURCE_MAX_REQUEST_BYTES,
  VIDEO_SOURCE_READER,
  videoSourceIdentity,
} from "./videoSourceReservation.ts";
import { parseSourceReservationRequest } from "./sourceReservation.ts";
import { parseExecutableAnalysisInput } from "./analysisInput.ts";
import inputs from "./fixtures/video-source-fingerprint-v1.json" with {
  type: "json",
};
import fixtures from "./fixtures/video-source-reservation-v2.json" with {
  type: "json",
};
const bytes = (value: unknown) =>
  new TextEncoder().encode(JSON.stringify(value));
const owner = "00000000-0000-4000-8000-000000000090";
const other = "00000000-0000-4000-8000-000000000091";
const candidate = (i = 0) => ({
  schema_version: 2,
  input: structuredClone(inputs[i].input),
  fingerprint_version: 1,
  fingerprint: inputs[i].sha256,
});
Deno.test("prepared video source contract accepts fixed audio silent and Unicode vectors", async () => {
  assertEquals(VIDEO_SOURCE_READER, 12);
  for (const [i, f] of fixtures.entries()) {
    const request = candidate(i);
    assertEquals<unknown>(
      await decodeVideoSourceReservationRequest(bytes(request)),
      request,
    );
    assertEquals(await videoSourceIdentity(request), f.identity);
    assertEquals(await buildVideoSourceRecoveryRequest(request), f.identity);
    assertEquals(
      decodeVideoSourceRecoveryRequest(bytes(f.identity)),
      f.identity,
    );
    for (const reply of f.replies) {
      assertEquals<unknown>(
        await decodeVideoSourceReservationReceipt(bytes(reply), request, owner),
        reply,
      );
      assertEquals<unknown>(
        await decodeVideoSourceRecoveryReceipt(bytes(reply), request, owner),
        reply,
      );
    }
  }
});
Deno.test("prepared video source request snapshots the complete graph before await", async () => {
  const value = candidate(), before = structuredClone(value);
  const pending = parseVideoSourceReservationRequest(value);
  value.input.request_digest = "f".repeat(64);
  value.input.evidence_manifest.provenance.frames.reverse();
  value.input.evidence_manifest.descriptions.push("Changed after final tap");
  value.fingerprint = "0".repeat(64);
  const result = await pending;
  assertEquals<unknown>(result, before);
  function frozen(v: unknown) {
    if (v !== null && typeof v === "object") {
      assert(Object.isFrozen(v));
      Object.values(v).forEach(frozen);
    }
  }
  frozen(result);
  const original = candidate(), identity = fixtures[0].identity;
  const response = { ...identity, owner_id: owner, state: "reserved" };
  const data = bytes(response);
  const decoding = decodeVideoSourceReservationReceipt(data, original, owner);
  data.fill(0);
  original.input.source_analysis_id = other;
  assertEquals<unknown>(await decoding, response);
});
Deno.test("prepared video source rejects old envelopes and forged provenance without widening legacy parsers", async () => {
  for (
    const patch of [
      { schema_version: 1 },
      { schema_version: 4 },
      { fingerprint_version: 2 },
      { fingerprint: "0".repeat(64) },
      { fingerprint: "A".repeat(64) },
      { fingerprint: candidate().fingerprint + "\n" },
      { owner_id: owner },
      { input: { ...candidate().input, source_analysis_id: other } },
      { input: { ...candidate().input, schema_version: 3 } },
      { input: { ...candidate().input, request_digest: "0".repeat(64) } },
    ]
  ) {
    await assertRejects(() =>
      parseVideoSourceReservationRequest({ ...candidate(), ...patch })
    );
  }
  await assertRejects(() => parseSourceReservationRequest(candidate()));
  await assertRejects(() =>
    parseSourceReservationRequest({ ...candidate(), schema_version: 1 })
  );
  assertThrows(() => parseExecutableAnalysisInput(candidate().input));
});
Deno.test("prepared video source every reply binds owner and full candidate identity", async () => {
  for (const good of fixtures[0].replies) {
    for (const field of Object.keys(fixtures[0].identity)) {
      await assertRejects(() =>
        decodeVideoSourceReservationReceipt(
          bytes({ ...good, [field]: field.endsWith("_id") ? other : 0 }),
          candidate(),
          owner,
        )
      );
      const missing: Record<string, unknown> = { ...good };
      delete missing[field];
      await assertRejects(() =>
        decodeVideoSourceReservationReceipt(bytes(missing), candidate(), owner)
      );
    }
    for (
      const patch of [
        { owner_id: other },
        { owner_id: null },
        { extra: true },
        { state: "not_found" },
        { state: "retired_unfunded" },
        { state: "complete" },
        { state: "dispatched" },
      ]
    ) {
      await assertRejects(() =>
        decodeVideoSourceRecoveryReceipt(
          bytes({ ...good, ...patch }),
          candidate(),
          owner,
        )
      );
    }
  }
  const id = fixtures[0].identity;
  for (
    const patch of [
      { state: "held", reason: "unknown" },
      { state: "held" },
      { state: "reserved", reason: "source_occupied" },
      { state: "unavailable", operation_id: other },
      { state: "retired_unfunded", operation_id: other },
    ]
  ) {
    await assertRejects(() =>
      decodeVideoSourceRecoveryReceipt(
        bytes({ ...id, owner_id: owner, ...patch }),
        candidate(),
        owner,
      )
    );
  }
});
Deno.test("prepared video recovery requests reject incomplete or ambiguous identity", () => {
  const id = fixtures[0].identity;
  for (
    const bad of [
      null,
      [],
      {},
      { ...id, schema_version: 1 },
      { ...id, owner_id: owner },
      { ...id, operation_id: other },
      { ...id, analysis_id: id.source_analysis_id },
      { ...id, fingerprint_version: true },
      { ...id, fingerprint: id.fingerprint + "\n" },
    ]
  ) {
    assertThrows(() => decodeVideoSourceRecoveryRequest(bytes(bad)));
  }
});
Deno.test("prepared video source bounded UTF8 decoding fails closed", async () => {
  for (
    const bad of [
      new Uint8Array(VIDEO_SOURCE_MAX_REQUEST_BYTES + 1),
      new Uint8Array([0xc3, 0x28]),
      bytes(null),
      bytes([]),
      new TextEncoder().encode("{"),
    ]
  ) {
    await assertRejects(async () =>
      await decodeVideoSourceReservationRequest(bad)
    );
  }
  for (
    const bad of [
      new Uint8Array(VIDEO_SOURCE_MAX_RECEIPT_BYTES + 1),
      new Uint8Array([0xc3, 0x28]),
      bytes(null),
      bytes([]),
      new TextEncoder().encode("{"),
    ]
  ) {
    assertThrows(() => decodeVideoSourceRecoveryRequest(bad));
    await assertRejects(() =>
      decodeVideoSourceRecoveryReceipt(bad, candidate(), owner)
    );
  }
});
