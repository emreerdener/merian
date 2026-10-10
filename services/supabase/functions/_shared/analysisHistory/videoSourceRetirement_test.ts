import { assert, assertEquals, assertRejects, assertThrows } from "@std/assert";
import {
  buildVideoSourceRetirementRequest,
  decodeVideoSourceRetirementReceipt,
  decodeVideoSourceRetirementRequest,
  parseVideoSourceRetirementRequest,
  VIDEO_SOURCE_RETIREMENT_MAX_BYTES,
  VIDEO_SOURCE_RETIREMENT_READER,
} from "./videoSourceRetirement.ts";
import {
  decodeVideoSourceRecoveryReceipt,
  decodeVideoSourceReservationReceipt,
} from "./videoSourceReservation.ts";
import { parseSourceRetirementRequest } from "./sourceReservation.ts";
import inputs from "./fixtures/video-source-fingerprint-v1.json" with {
  type: "json",
};
import fixtures from "./fixtures/video-source-retirement-v2.json" with {
  type: "json",
};
const bytes = (value: unknown) =>
  new TextEncoder().encode(JSON.stringify(value));
const owner = fixtures[0].receipt.owner_id;
const operation = fixtures[0].request.operation_id;
const other = "00000000-0000-4000-8000-000000000091";
const candidate = (i = 0) => ({
  schema_version: 2,
  input: structuredClone(inputs[i].input),
  fingerprint_version: 1,
  fingerprint: inputs[i].sha256,
});
Deno.test("video retirement fixed audio silent Unicode request and permanent receipt parity", async () => {
  assertEquals(VIDEO_SOURCE_RETIREMENT_READER, 12);
  for (const [i, f] of fixtures.entries()) {
    const request = await buildVideoSourceRetirementRequest(
      candidate(i),
      operation,
    );
    assertEquals<unknown>(request, f.request);
    assertEquals<unknown>(
      decodeVideoSourceRetirementRequest(bytes(f.request)),
      f.request,
    );
    const receipt = await decodeVideoSourceRetirementReceipt(
      bytes(f.receipt),
      candidate(i),
      request,
      owner,
    );
    assertEquals<unknown>(receipt, f.receipt);
    assert(Object.isFrozen(request));
    assert(Object.isFrozen(receipt));
    assertEquals(
      await decodeVideoSourceRetirementReceipt(
        bytes(f.receipt),
        candidate(i),
        request,
        owner,
      ),
      receipt,
    );
  }
});
Deno.test("video retirement snapshots candidate expected request and receipt before awaits", async () => {
  const input = candidate();
  const building = buildVideoSourceRetirementRequest(input, operation);
  input.input.evidence_manifest.provenance.frames.reverse();
  input.input.request_digest = "0".repeat(64);
  assertEquals<unknown>(await building, fixtures[0].request);
  const source = candidate();
  const expected = {
    ...fixtures[0].request,
    schema_version: 2 as const,
    fingerprint_version: 1 as const,
  };
  const data = bytes(fixtures[0].receipt);
  const decoding = decodeVideoSourceRetirementReceipt(
    data,
    source,
    expected,
    owner,
  );
  data.fill(0);
  expected.operation_id = other;
  expected.fingerprint = "0".repeat(64);
  source.input.source_analysis_id = other;
  assertEquals<unknown>(await decoding, fixtures[0].receipt);
});
Deno.test("video retirement requires every closed identity field and distinct operation", () => {
  const request = fixtures[0].request;
  for (const field of Object.keys(request)) {
    const missing: Record<string, unknown> = { ...request };
    delete missing[field];
    assertThrows(() => parseVideoSourceRetirementRequest(missing));
    assertThrows(() =>
      parseVideoSourceRetirementRequest({ ...request, [field]: null })
    );
  }
  for (
    const patch of [
      { schema_version: 1 },
      { fingerprint_version: 2 },
      { owner_id: owner },
      { fingerprint: "A".repeat(64) },
      { request_digest: "f".repeat(64) + "\n" },
      { operation_id: "bad" },
      { operation_id: request.analysis_id },
      { operation_id: request.observation_id },
      { operation_id: request.source_analysis_id },
      { analysis_id: request.observation_id },
    ]
  ) {
    assertThrows(() =>
      parseVideoSourceRetirementRequest({ ...request, ...patch })
    );
  }
});
Deno.test("video retirement reply binds owner operation every identity field and exact candidate", async () => {
  const request = await buildVideoSourceRetirementRequest(
    candidate(),
    operation,
  );
  const receipt = fixtures[0].receipt;
  for (const field of Object.keys(receipt)) {
    const missing: Record<string, unknown> = { ...receipt };
    delete missing[field];
    await assertRejects(() =>
      decodeVideoSourceRetirementReceipt(
        bytes(missing),
        candidate(),
        request,
        owner,
      )
    );
    await assertRejects(() =>
      decodeVideoSourceRetirementReceipt(
        bytes({ ...receipt, [field]: other }),
        candidate(),
        request,
        owner,
      )
    );
  }
  for (
    const state of [
      "reserved",
      "unavailable",
      "held",
      "retired_before_dispatch",
      "retired_unfunded",
      "complete",
      "not_found",
    ]
  ) {
    await assertRejects(() =>
      decodeVideoSourceRetirementReceipt(
        bytes({ ...receipt, state }),
        candidate(),
        request,
        owner,
      )
    );
  }
  await assertRejects(() =>
    decodeVideoSourceRetirementReceipt(
      bytes({ ...receipt, reason: "terminal_unproven" }),
      candidate(),
      request,
      owner,
    )
  );
  await assertRejects(() =>
    decodeVideoSourceRetirementReceipt(
      bytes(receipt),
      candidate(),
      request,
      other,
    )
  );
  const forged = { ...request, request_digest: "0".repeat(64) };
  await assertRejects(() =>
    decodeVideoSourceRetirementReceipt(
      bytes({ ...receipt, ...forged }),
      candidate(),
      forged,
      owner,
    )
  );
  const changed = candidate();
  changed.input.evidence_manifest.provenance.frames.reverse();
  await assertRejects(() =>
    decodeVideoSourceRetirementReceipt(bytes(receipt), changed, request, owner)
  );
});
Deno.test("video retirement never broadens reservation lookup or legacy retirement decoders", async () => {
  const request = fixtures[0].request, receipt = fixtures[0].receipt;
  assertThrows(() => parseSourceRetirementRequest(request));
  await assertRejects(() =>
    decodeVideoSourceReservationReceipt(bytes(receipt), candidate(), owner)
  );
  await assertRejects(() =>
    decodeVideoSourceRecoveryReceipt(bytes(receipt), candidate(), owner)
  );
  await assertRejects(() =>
    buildVideoSourceRetirementRequest(
      { ...candidate(), schema_version: 1 },
      operation,
    )
  );
});
Deno.test("video retirement enforces strict UTF8 and 2KiB request and reply bounds", async () => {
  const request = await buildVideoSourceRetirementRequest(
    candidate(),
    operation,
  );
  for (
    const data of [
      new Uint8Array([0xff]),
      bytes(null),
      bytes([]),
      new TextEncoder().encode("{"),
      new Uint8Array(VIDEO_SOURCE_RETIREMENT_MAX_BYTES + 1),
    ]
  ) {
    assertThrows(() => decodeVideoSourceRetirementRequest(data));
    await assertRejects(() =>
      decodeVideoSourceRetirementReceipt(data, candidate(), request, owner)
    );
  }
  const padded = (value: unknown, size: number) => {
    const data = bytes(value), result = new Uint8Array(size).fill(32);
    result.set(data);
    return result;
  };
  assertEquals(
    decodeVideoSourceRetirementRequest(padded(request, 2048)),
    request,
  );
  assertThrows(() => decodeVideoSourceRetirementRequest(padded(request, 2049)));
  assertEquals<unknown>(
    await decodeVideoSourceRetirementReceipt(
      padded(fixtures[0].receipt, 2048),
      candidate(),
      request,
      owner,
    ),
    fixtures[0].receipt,
  );
  await assertRejects(() =>
    decodeVideoSourceRetirementReceipt(
      padded(fixtures[0].receipt, 2049),
      candidate(),
      request,
      owner,
    )
  );
});
