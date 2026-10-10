import { assert, assertEquals, assertRejects, assertThrows } from "@std/assert";
import { HistoryError } from "./contract.ts";
import {
  buildSourceRetirementRequest,
  decodeSourceReservationReceipt,
  decodeSourceReservationRequest,
  decodeSourceRetirementReceipt,
  decodeSourceRetirementRequest,
  parseSourceReservationRequest,
  parseSourceRetirementRequest,
  SOURCE_RESERVATION_MAX_RECEIPT_BYTES,
  SOURCE_RESERVATION_MAX_REQUEST_BYTES,
  SOURCE_RESERVATION_READER,
  sourceReservationIdentity,
} from "./sourceReservation.ts";
import vectors from "./fixtures/source-fingerprint-v1.json" with {
  type: "json",
};
const owner = "00000000-0000-4000-8000-000000000090";
const other = "00000000-0000-4000-8000-000000000091";
const operation = "00000000-0000-4000-8000-000000000092";
const bytes = (value: unknown) =>
  new TextEncoder().encode(JSON.stringify(value));
const request = (index = 0) => ({
  schema_version: 1,
  input: structuredClone(vectors[index].input),
  fingerprint_version: 1,
  fingerprint: vectors[index].sha256,
});
const target = await sourceReservationIdentity(request());
const reserved = { ...target, owner_id: owner, state: "reserved" };
const scope = {
  schema_version: 1,
  owner_id: owner,
  observation_id: target.observation_id,
  source_analysis_id: target.source_analysis_id,
};
const retire = { ...target, operation_id: operation };
const retired = { ...retire, owner_id: owner, state: "retired_unfunded" };

Deno.test("source reservation accepts exact photo/audio vectors and preserves original replay digest", async () => {
  assertEquals<unknown>(SOURCE_RESERVATION_READER, 11);
  for (let i = 0; i < vectors.length; i++) {
    const original = request(i);
    assertEquals<unknown>(
      await decodeSourceReservationRequest(bytes(original)),
      original,
    );
    assertEquals<unknown>(
      (await sourceReservationIdentity(original)).request_digest,
      original.input.request_digest,
    );
  }
});
Deno.test("source reservation snapshots and deeply freezes input before hashing", async () => {
  const original = request();
  const before = structuredClone(original);
  const pending = parseSourceReservationRequest(original);
  original.input.request_digest = "a".repeat(64);
  original.input.evidence_manifest.items.reverse();
  original.fingerprint = "c".repeat(64);
  const saved = await pending;
  assertEquals<unknown>(saved, before);
  function check(value: unknown): void {
    if (value !== null && typeof value === "object") {
      assert(Object.isFrozen(value));
      Object.values(value).forEach(check);
    }
  }
  check(saved);
});
Deno.test("source reservation rejects forged digests, versions, owner fields and source substitutions", async () => {
  for (
    const change of [
      { fingerprint: "a".repeat(64) },
      { fingerprint_version: 2 },
      { schema_version: 2 },
      { owner_id: owner },
      { fingerprint: null },
      { fingerprint: "A".repeat(64) },
      { input: { ...request().input, source_analysis_id: other } },
      { input: { ...request().input, source_analysis_id: null } },
      { input: { ...request().input, analysis_id: target.source_analysis_id } },
      { input: { ...request().input, request_digest: "a".repeat(64) } },
      { input: { ...request().input, schema_version: 1 } },
    ]
  ) {
    await assertRejects(
      () => parseSourceReservationRequest({ ...request(), ...change }),
      HistoryError,
    );
  }
});
Deno.test("source reservation byte boundary rejects overflow, malformed JSON and invalid UTF8", async () => {
  for (
    const input of [
      new Uint8Array(SOURCE_RESERVATION_MAX_REQUEST_BYTES + 1),
      new Uint8Array([0xc3, 0x28]),
      bytes(null),
      bytes([]),
      new TextEncoder().encode("{"),
    ]
  ) {
    await assertRejects(
      async () => await decodeSourceReservationRequest(input),
      HistoryError,
    );
  }
});
Deno.test("source reservation receipt binds every original identity and permits exact replay only", async () => {
  const first = await decodeSourceReservationReceipt(
    bytes(reserved),
    request(),
    owner,
  );
  assertEquals<unknown>(
    await decodeSourceReservationReceipt(bytes(reserved), request(), owner),
    first,
  );
  assert(Object.isFrozen(first));
  for (const key of Object.keys(target)) {
    const bad = {
      ...reserved,
      [key]: key.endsWith("version")
        ? 2
        : key.includes("digest") || key === "fingerprint"
        ? "f".repeat(64)
        : other,
    };
    await assertRejects(
      () => decodeSourceReservationReceipt(bytes(bad), request(), owner),
      HistoryError,
    );
  }
  await assertRejects(
    () => decodeSourceReservationReceipt(bytes(reserved), request(), other),
    HistoryError,
  );
});
Deno.test("source reservation held and unavailable expose scope only and never a competitor", async () => {
  for (
    const reason of [
      "source_occupied",
      "ambiguous_occupancy",
      "coverage_incomplete",
      "malformed_linkage",
      "terminal_unproven",
    ]
  ) {
    const held = { ...scope, state: "held", reason };
    assertEquals<unknown>(
      await decodeSourceReservationReceipt(bytes(held), request(), owner),
      held,
    );
    for (
      const extra of [
        { analysis_id: other },
        { fingerprint: "a".repeat(64) },
        { request_digest: "a".repeat(64) },
        { may_dispatch: true },
        { input: request().input },
      ]
    ) {
      await assertRejects(
        () =>
          decodeSourceReservationReceipt(
            bytes({ ...held, ...extra }),
            request(),
            owner,
          ),
        HistoryError,
      );
    }
    await assertRejects(
      () => decodeSourceReservationReceipt(bytes(held), request(), other),
      HistoryError,
    );
  }
  const unavailable = { ...scope, state: "unavailable" };
  assertEquals<unknown>(
    await decodeSourceReservationReceipt(bytes(unavailable), request(), owner),
    unavailable,
  );
});
Deno.test("source reservation never accepts discovery absence, unknown states or capability fields", async () => {
  for (
    const value of [
      { ...scope, state: "advisory_absence" },
      { ...scope, state: "history_only" },
      { ...scope, state: "held", reason: ["source_occupied"] },
      { ...scope, state: "held", reason: "retry" },
      { ...reserved, quota: {} },
      { ...reserved, grant: other },
      { ...reserved, may_dispatch: false },
      { ...reserved, proof: {} },
      { ...scope, state: "unavailable", reason: "disabled" },
    ]
  ) {
    await assertRejects(
      () => decodeSourceReservationReceipt(bytes(value), request(), owner),
      HistoryError,
    );
  }
});
Deno.test("source unfunded retirement builds a distinct immutable action only from the full candidate", async () => {
  assertEquals<unknown>(
    await buildSourceRetirementRequest(request(), operation),
    retire,
  );
  assertEquals<unknown>(decodeSourceRetirementRequest(bytes(retire)), retire);
  assert(Object.isFrozen(parseSourceRetirementRequest(retire)));
  for (
    const id of [
      target.observation_id,
      target.source_analysis_id,
      target.analysis_id,
    ]
  ) {
    await assertRejects(
      () => buildSourceRetirementRequest(request(), id),
      HistoryError,
    );
  }
  for (
    const extra of [{ owner_id: owner }, { input: request().input }, {
      schema_version: 2,
    }, { operation_id: null }]
  ) {
    assertThrows(
      () => parseSourceRetirementRequest({ ...retire, ...extra }),
      HistoryError,
    );
  }
});
Deno.test("source unfunded retirement receipt never accepts funded retirement or changed action", async () => {
  assertEquals<unknown>(
    await decodeSourceRetirementReceipt(
      bytes(retired),
      request(),
      retire,
      owner,
    ),
    retired,
  );
  assertEquals<unknown>(
    await decodeSourceRetirementReceipt(
      bytes(retired),
      request(),
      retire,
      owner,
    ),
    retired,
  );
  for (
    const extra of [
      { state: "retired_before_dispatch" },
      { state: "held" },
      { operation_id: other },
      { owner_id: other },
      { analysis_id: other },
      { fingerprint: "a".repeat(64) },
      { request_digest: "a".repeat(64) },
      { source_analysis_id: other },
      { observation_id: other },
      { refund: false },
    ]
  ) {
    await assertRejects(
      () =>
        decodeSourceRetirementReceipt(
          bytes({ ...retired, ...extra }),
          request(),
          retire,
          owner,
        ),
      HistoryError,
    );
  }
});
Deno.test("source receipt and retirement byte limits reject unknown or oversized responses", async () => {
  for (
    const malformed of [
      new Uint8Array(SOURCE_RESERVATION_MAX_RECEIPT_BYTES + 1),
      new Uint8Array([0xff]),
      bytes(null),
      bytes([]),
    ]
  ) {
    await assertRejects(
      () => decodeSourceReservationReceipt(malformed, request(), owner),
      HistoryError,
    );
    await assertRejects(
      () => decodeSourceRetirementReceipt(malformed, request(), retire, owner),
      HistoryError,
    );
    assertThrows(() => decodeSourceRetirementRequest(malformed), HistoryError);
  }
});
Deno.test("source receipt rejects well-formed forged expected fingerprints and identity-only candidates", async () => {
  const fake = { ...request(), fingerprint: "d".repeat(64) };
  const fakeIdentity = { ...target, fingerprint: fake.fingerprint };
  const fakeRetire = { ...retire, fingerprint: fake.fingerprint };
  for (const candidate of [fake, fakeIdentity]) {
    await assertRejects(
      () =>
        decodeSourceReservationReceipt(
          bytes({ ...fakeIdentity, owner_id: owner, state: "reserved" }),
          candidate,
          owner,
        ),
      HistoryError,
    );
    await assertRejects(
      () => buildSourceRetirementRequest(candidate, operation),
      HistoryError,
    );
    await assertRejects(
      () =>
        decodeSourceRetirementReceipt(
          bytes({ ...fakeRetire, owner_id: owner, state: "retired_unfunded" }),
          candidate,
          fakeRetire,
          owner,
        ),
      HistoryError,
    );
  }
  await assertRejects(
    () =>
      decodeSourceRetirementReceipt(
        bytes({ ...fakeRetire, owner_id: owner, state: "retired_unfunded" }),
        request(),
        fakeRetire,
        owner,
      ),
    HistoryError,
  );
});
Deno.test("source receipt freezes expected candidate, action and response before hash await", async () => {
  const candidate = request();
  const action = { ...retire };
  const reply = bytes(retired);
  const pending = decodeSourceRetirementReceipt(
    reply,
    candidate,
    action,
    owner,
  );
  candidate.input.request_digest = "a".repeat(64);
  action.operation_id = other;
  reply.fill(0);
  assertEquals<unknown>(await pending, retired);
  const reserveReply = bytes(reserved);
  const reserveCandidate = request();
  const reservePending = decodeSourceReservationReceipt(
    reserveReply,
    reserveCandidate,
    owner,
  );
  reserveReply.fill(0);
  reserveCandidate.fingerprint = "a".repeat(64);
  assertEquals<unknown>(await reservePending, reserved);
});
