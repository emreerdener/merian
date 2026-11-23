import { assert, assertEquals, assertRejects, assertThrows } from "@std/assert";
import {
  COMPOSITION_SOURCE_MAX_RECEIPT_BYTES,
  COMPOSITION_SOURCE_MAX_REQUEST_BYTES,
  compositionSourceIdentity,
  decodeCompositionSourceRecoveryRequest,
  decodeCompositionSourceReservationReceipt,
  decodeCompositionSourceReservationRequest,
  parseCompositionSourceReservationRequest,
} from "./compositionSourceReservation.ts";
import { parseVideoSourceReservationRequest } from "./videoSourceReservation.ts";
import { parseSourceReservationRequest } from "./sourceReservation.ts";
import { compositionEvidenceIdentity } from "./compositionEvidence.ts";
import { parseCompositionAdmission } from "./compositionAdmission.ts";
import { compositionFingerprint } from "./compositionFingerprint.ts";
const rows: { valid: boolean; input: unknown }[] = JSON.parse(
  await Deno.readTextFile(
    new URL("./fixtures/composition-request-v5.json", import.meta.url),
  ),
);
const owner = "00000000-0000-4000-8000-000000009000";
const other = "00000000-0000-4000-8000-000000009001";
const bytes = (v: unknown) => new TextEncoder().encode(JSON.stringify(v));
async function candidate(value = rows[0].input) {
  const input = parseCompositionAdmission(value);
  return {
    schema_version: 3,
    input,
    fingerprint_version: 1,
    fingerprint: await compositionFingerprint(input),
  };
}
Deno.test("composition reservation matches the whole inventory identity for all valid shapes", async () => {
  for (const row of rows.filter((r) => r.valid)) {
    const request = await candidate(row.input);
    assertEquals<unknown>(
      await decodeCompositionSourceReservationRequest(bytes(request)),
      request,
    );
    const identity = await compositionSourceIdentity(request);
    assertEquals<unknown>(
      identity,
      await compositionEvidenceIdentity(request.input),
    );
    assertEquals<unknown>(
      decodeCompositionSourceRecoveryRequest(bytes(identity)),
      identity,
    );
    for (const state of ["reserved", "unavailable"] as const) {
      const receipt = { ...identity, owner_id: owner, state };
      assertEquals<unknown>(
        await decodeCompositionSourceReservationReceipt(
          bytes(receipt),
          request,
          owner,
        ),
        receipt,
      );
    }
    for (
      const reason of [
        "source_occupied",
        "ambiguous_occupancy",
        "coverage_incomplete",
        "malformed_linkage",
        "terminal_unproven",
      ]
    ) {
      const receipt = { ...identity, owner_id: owner, state: "held", reason };
      assertEquals<unknown>(
        await decodeCompositionSourceReservationReceipt(
          bytes(receipt),
          request,
          owner,
        ),
        receipt,
      );
    }
  }
});
Deno.test("composition reservation freezes caller content and receipt before hashing suspends", async () => {
  const original = await candidate(),
    mutable = JSON.parse(JSON.stringify(original));
  const pending = parseCompositionSourceReservationRequest(mutable);
  mutable.input.evidence_manifest.items.reverse();
  mutable.input.source_analysis_id = other;
  mutable.fingerprint = "f".repeat(64);
  const result = await pending;
  assertEquals<unknown>(result, original);
  function frozen(v: unknown) {
    if (v !== null && typeof v === "object") {
      assert(Object.isFrozen(v));
      Object.values(v).forEach(frozen);
    }
  }
  frozen(result);
  const receipt = {
    ...await compositionSourceIdentity(original),
    owner_id: owner,
    state: "reserved",
  };
  const encoded = bytes(receipt),
    request = JSON.parse(JSON.stringify(original));
  const decoding = decodeCompositionSourceReservationReceipt(
    encoded,
    request,
    owner,
  );
  encoded.fill(0);
  request.input.request_digest = "f".repeat(64);
  assertEquals<unknown>(await decoding, receipt);
});
Deno.test("composition reservation refuses cross-lane envelopes and mismatched fingerprints", async () => {
  const request = await candidate();
  for (
    const patch of [
      { schema_version: 1 },
      { schema_version: 2 },
      { fingerprint_version: 2 },
      { fingerprint: "a".repeat(64) },
      { owner_id: owner },
      { input: { ...request.input, source_analysis_id: other } },
    ]
  ) {
    await assertRejects(() =>
      parseCompositionSourceReservationRequest({ ...request, ...patch })
    );
  }
  await assertRejects(() => parseVideoSourceReservationRequest(request));
  await assertRejects(() => parseSourceReservationRequest(request));
  assertThrows(() =>
    decodeCompositionSourceReservationRequest(
      new Uint8Array(COMPOSITION_SOURCE_MAX_REQUEST_BYTES + 1),
    )
  );
  assertThrows(() =>
    decodeCompositionSourceRecoveryRequest(
      new Uint8Array(COMPOSITION_SOURCE_MAX_RECEIPT_BYTES + 1),
    )
  );
  assertThrows(() =>
    decodeCompositionSourceRecoveryRequest(new Uint8Array([0xff]))
  );
});
Deno.test("composition reservation receipts never infer ownership, absence, funding or release", async () => {
  const request = await candidate(),
    identity = await compositionSourceIdentity(request);
  const good = { ...identity, owner_id: owner, state: "reserved" };
  for (const key of Object.keys(identity)) {
    await assertRejects(() =>
      decodeCompositionSourceReservationReceipt(
        bytes({ ...good, [key]: key.endsWith("_id") ? other : 0 }),
        request,
        owner,
      )
    );
  }
  for (
    const patch of [
      { owner_id: other },
      { extra: true },
      { state: "not_found" },
      { state: "complete" },
      { state: "dispatched" },
      { state: "retired_unfunded" },
      { state: "held" },
      { state: "held", reason: "unknown" },
      { reason: "source_occupied" },
    ]
  ) {
    await assertRejects(() =>
      decodeCompositionSourceReservationReceipt(
        bytes({ ...good, ...patch }),
        request,
        owner,
      )
    );
  }
});
