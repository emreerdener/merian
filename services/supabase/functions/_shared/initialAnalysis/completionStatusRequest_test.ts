import { assert, assertEquals, assertRejects } from "@std/assert";
import {
  decodeInitialStatusAdmission,
  decodeInitialStatusRecoveryRequest,
} from "./completionStatusRequest.ts";
import { cpmCompletionAdmissionFixture } from "./fixtures/cpmCompletionAdmission.ts";

async function fixture() {
  const f = await cpmCompletionAdmissionFixture();
  const assignment = JSON.parse(f.binding.assignment_canonical);
  const { assignment_canonical: _assignment, ...saved } = f.binding;
  return {
    admission: f.admission,
    binding: {
      ...saved,
      candidate_digest: assignment.candidate_digest as string,
      content_digest: assignment.content_digest as string,
    },
  };
}
import { createInitialSavedAdmissionAcquisition } from "./resultStore.ts";
const foreign = "00000000-0000-4000-8000-000000000999";
function request(_scanID: string, phase: string, original: unknown) {
  return { initial_recovery: { version: 1, phase, original } };
}

Deno.test("status recovery snapshots only the exact saved original for each phase", async () => {
  const f = await fixture();
  for (const phase of ["admission", "completion"] as const) {
    const original = phase === "admission" ? f.binding : f.admission;
    const body = request(f.binding.scan_id, phase, { ...original });
    const pending = decodeInitialStatusRecoveryRequest(
      body,
      f.binding.owner_id,
    );
    body.initial_recovery.phase = "legacy";
    body.initial_recovery.original = null;
    const decoded = await pending;
    assertEquals(decoded, { phase, scan_id: f.binding.scan_id, original });
    assert(Object.isFrozen(decoded));
    assert(Object.isFrozen(decoded.original));
  }
});

Deno.test("status recovery never accepts foreign ownership, mixed legacy fields or phase drift", async (t) => {
  const f = await fixture();
  for (const phase of ["admission", "completion"] as const) {
    const original = phase === "admission" ? f.binding : f.admission;
    const valid = request(f.binding.scan_id, phase, original);
    await t.step(phase, async () => {
      await assertRejects(() =>
        decodeInitialStatusRecoveryRequest(valid, foreign)
      );
      for (
        const body of [
          { ...valid, scan_id: foreign },
          { ...valid, scan_id: f.binding.scan_id },
          { ...valid, scans: [] },
          { ...valid, recovery_scan: {} },
          request(f.binding.scan_id, phase, { ...original, owner_id: foreign }),
          request(f.binding.scan_id, phase, {
            ...original,
            scan_id: "invalid",
          }),
          request(f.binding.scan_id, phase, { ...original, retry: true }),
          request(f.binding.scan_id, phase, {
            ...original,
            result_id: foreign,
          }),
          { ...valid, operation_id: foreign },
          { ...valid, retry: false },
          {
            ...valid,
            initial_recovery: { ...valid.initial_recovery, version: 2 },
          },
          {
            ...valid,
            initial_recovery: { ...valid.initial_recovery, extra: null },
          },
          request(f.binding.scan_id, "unknown", original),
          request(
            f.binding.scan_id,
            phase === "admission" ? "completion" : "admission",
            original,
          ),
          { scan_id: f.binding.scan_id },
          null,
        ]
      ) {
        await assertRejects(() =>
          decodeInitialStatusRecoveryRequest(body, f.binding.owner_id)
        );
      }
    });
  }
});

Deno.test("status recovery rejects accessors, symbols, prototypes and coercion without invoking them", async () => {
  const f = await fixture();
  let invoked = 0;
  const getter = () => {
    invoked++;
    return f.binding;
  };
  const body = request(f.binding.scan_id, "admission", f.binding);
  const accessor = { ...body };
  Object.defineProperty(accessor, "initial_recovery", {
    enumerable: true,
    get: getter,
  });
  const nested = { ...body.initial_recovery };
  Object.defineProperty(nested, "original", { enumerable: true, get: getter });
  const original = { ...f.binding };
  Object.defineProperty(original, "candidate_canonical", {
    enumerable: true,
    get: getter,
  });
  const hidden = { ...body };
  Object.defineProperty(hidden, "scan_id", { enumerable: false });
  for (
    const value of [
      accessor,
      { ...body, initial_recovery: nested },
      request(f.binding.scan_id, "admission", original),
      { ...body, [Symbol("extra")]: true },
      Object.assign(Object.create({ inherited: true }), body),
      hidden,
      {
        ...body,
        initial_recovery: {
          ...body.initial_recovery,
          phase: {
            toString() {
              invoked++;
              return "admission";
            },
          },
        },
      },
    ]
  ) {
    await assertRejects(() =>
      decodeInitialStatusRecoveryRequest(value, f.binding.owner_id)
    );
  }
  assertEquals(invoked, 0);
});

Deno.test("status recovery rejects corrupt or oversized saved documents before fixed reads", async () => {
  const f = await fixture();
  for (
    const original of [
      { ...f.binding, candidate_digest: "0".repeat(64) },
      {
        ...f.binding,
        candidate_canonical: f.binding.candidate_canonical + " ",
      },
      { ...f.binding, candidate_canonical: "x".repeat(1048577) },
      { ...f.binding, content_digest: "0".repeat(64) },
      { ...f.binding, backend_generation: "invalid" },
      { ...f.binding, backend_configuration_digest: "not-a-digest" },
      { ...f.binding, candidate_canonical: {} },
    ]
  ) {
    await assertRejects(() =>
      decodeInitialStatusRecoveryRequest(
        request(f.binding.scan_id, "admission", original),
        f.binding.owner_id,
      )
    );
  }
  for (
    const original of [
      { ...f.admission, route: "x".repeat(8193) },
      { ...f.admission, funding_binding_version: 0 },
      { ...f.admission, ordered_description_count: -1 },
      { ...f.admission, submission_digest: "unknown" },
    ]
  ) {
    await assertRejects(() =>
      decodeInitialStatusRecoveryRequest(
        request(f.binding.scan_id, "completion", original),
        f.binding.owner_id,
      )
    );
  }
});

Deno.test("saved admission reader uses one fixed original read and returns only the acknowledgement", async () => {
  const f = await cpmCompletionAdmissionFixture(), native = await fixture();
  const reply = {
    version: 1,
    assignment_canonical: f.binding.assignment_canonical,
    acknowledgement: f.reply,
  };
  let calls = 0;
  const reader = await createInitialSavedAdmissionAcquisition({
    original: native.binding,
    authenticatedOwnerID: native.binding.owner_id,
    origin: "https://trusted.invalid",
    serverApiKey: "sb_secret_" + "x".repeat(40),
    fetcher: (url, init) => {
      calls++;
      assertEquals(
        String(url),
        "https://trusted.invalid/rest/v1/rpc/read_initial_cpm_saved_admission_v1",
      );
      assertEquals(JSON.parse(String(init?.body)), {
        p_owner: f.binding.owner_id,
        p_scan: f.binding.scan_id,
        p_candidate: f.binding.candidate_canonical,
        p_candidate_digest: native.binding.candidate_digest,
        p_content_digest: native.binding.content_digest,
        p_assignment_digest: f.binding.assignment_digest,
        p_backend_generation: f.binding.backend_generation,
        p_backend_configuration_digest: f.binding.backend_configuration_digest,
      });
      assertEquals(init?.redirect, "error");
      assertEquals(init?.cache, "no-store");
      return Promise.resolve(Response.json(reply));
    },
  });
  const value = await reader.read(new AbortController().signal);
  assertEquals(value.admission, f.admission);
  assertEquals(calls, 1);
  assertEquals(Object.hasOwn(value, "assignment_canonical"), false);
  for (
    const bad of [
      { ...reply, version: 2 },
      { ...reply, extra: true },
      { ...reply, assignment_canonical: f.binding.assignment_canonical + " " },
      { ...reply, assignment_canonical: "x".repeat(65537) },
      { ...reply, acknowledgement: { ...f.reply, owner_id: foreign } },
    ]
  ) {
    await assertRejects(() =>
      decodeInitialStatusAdmission(bad, native.binding)
    );
  }
});

Deno.test("saved admission reader rejects absence, oversize, cancellation and late replies without retry", async (t) => {
  const f = await cpmCompletionAdmissionFixture(), native = await fixture();
  for (const mode of ["absent", "oversize", "cancelled", "late"] as const) {
    await t.step(mode, async () => {
      const controller = new AbortController();
      let calls = 0;
      let release: ((response: Response) => void) | undefined;
      let entered: (() => void) | undefined;
      const began = new Promise<void>((resolve) => {
        entered = resolve;
      });
      const reader = await createInitialSavedAdmissionAcquisition({
        original: native.binding,
        authenticatedOwnerID: native.binding.owner_id,
        origin: "https://trusted.invalid",
        serverApiKey: "sb_secret_" + "x".repeat(40),
        fetcher: () => {
          calls++;
          entered?.();
          if (mode === "late") {
            return new Promise<Response>((resolve) => {
              release = resolve;
            });
          }
          return Promise.resolve(
            mode === "oversize"
              ? new Response("x".repeat(151553))
              : Response.json(null),
          );
        },
      });
      if (mode === "cancelled") controller.abort();
      const rejected = assertRejects(() => reader.read(controller.signal));
      if (mode === "late") {
        await began;
        controller.abort();
        release?.(
          Response.json({
            version: 1,
            assignment_canonical: f.binding.assignment_canonical,
            acknowledgement: f.reply,
          }),
        );
      }
      await rejected;
      assertEquals(calls, mode === "cancelled" ? 0 : 1);
    });
  }
});

Deno.test("nested original recovery cannot satisfy pre-marker legacy repair requirements", async () => {
  const { requireParams } = await import("../http.ts");
  const f = await fixture();
  for (const phase of ["admission", "completion"] as const) {
    const body = request(
      f.binding.scan_id,
      phase,
      phase === "admission" ? f.binding : f.admission,
    );
    assertEquals(Object.keys(body), ["initial_recovery"]);
    assertEquals(requireParams(body, ["scan_id"])?.status, 400);
    const decoded = await decodeInitialStatusRecoveryRequest(
      body,
      f.binding.owner_id,
    );
    assertEquals(decoded.scan_id, f.binding.scan_id);
  }
});
