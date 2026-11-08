import { assertEquals, assertRejects } from "@std/assert";
import {
  readInitialRecovery,
  readInitialRecoveryHttp,
} from "./initialRecovery.ts";
import { cpmCompletionAdmissionFixture } from "../_shared/initialAnalysis/fixtures/cpmCompletionAdmission.ts";
import { completionAcquisitionFixture } from "../_shared/initialAnalysis/fixtures/completionAcquisition.ts";
import { snapshotInitialCompletionAdmission } from "../_shared/initialAnalysis/completionAcquisition.ts";
import { initialCanonicalText } from "../_shared/initialAnalysis/canonical.ts";

const options = {
  origin: "https://trusted.invalid",
  serverApiKey: "sb_secret_" + "x".repeat(40),
};
Deno.test("prepared status branch returns only exact acknowledgement or original completion, never legacy repair", async (t) => {
  const f = await cpmCompletionAdmissionFixture();
  const assignment = JSON.parse(f.binding.assignment_canonical);
  const original = {
    owner_id: f.binding.owner_id,
    scan_id: f.binding.scan_id,
    candidate_canonical: f.binding.candidate_canonical,
    candidate_digest: assignment.candidate_digest,
    content_digest: assignment.content_digest,
    assignment_digest: f.binding.assignment_digest,
    backend_generation: f.binding.backend_generation,
    backend_configuration_digest: f.binding.backend_configuration_digest,
  };
  const admission = snapshotInitialCompletionAdmission(f.admission);
  const found = await completionAcquisitionFixture(
    true,
    admission,
    "\ufeffe\u0301/🦋",
  );
  for (const mode of ["admission", "pending", "found"] as const) {
    await t.step(mode, async () => {
      const calls: string[] = [];
      const body = {
        scan_id: original.scan_id,
        initial_recovery: {
          version: 1,
          phase: mode === "admission" ? "admission" : "completion",
          original: mode === "admission" ? original : admission,
        },
      };
      const response = await readInitialRecovery(
        body,
        original.owner_id,
        new AbortController().signal,
        {
          ...options,
          fetcher: (url, init) => {
            const operation = new URL(String(url)).pathname.split("/").at(-1)!;
            calls.push(operation);
            const args = JSON.parse(String(init?.body));
            assertEquals(args.p_owner, original.owner_id);
            assertEquals(args.p_scan, original.scan_id);
            if (mode === "admission") {
              assertEquals(operation, "read_initial_cpm_saved_admission_v1");
              return Promise.resolve(
                Response.json({
                  version: 1,
                  assignment_canonical: f.binding.assignment_canonical,
                  acknowledgement: f.reply,
                }),
              );
            }
            assertEquals(operation, "discover_initial_completion_v1");
            assertEquals(args.p_admission, initialCanonicalText(admission));
            return Promise.resolve(
              Response.json(
                mode === "found" ? found.reply : {
                  version: 1,
                  outcome: "pending",
                  admission_canonical: initialCanonicalText(admission),
                  reference: null,
                  result_digest: null,
                  original_provenance: null,
                  delivery: null,
                },
              ),
            );
          },
        },
      );
      const text = new TextDecoder().decode(response), value = JSON.parse(text);
      assertEquals(text, initialCanonicalText(value));
      if (mode === "admission") {
        assertEquals(text, initialCanonicalText(f.reply));
      } else {
        assertEquals(value.outcome, mode);
        assertEquals(
          value.admission_canonical,
          initialCanonicalText(admission),
        );
      }
      assertEquals(calls.length, 1);
    });
  }
});

Deno.test("prepared status branch denies foreign, mixed and cancelled requests before reads", async () => {
  const f = await cpmCompletionAdmissionFixture();
  let calls = 0;
  const transport = {
    ...options,
    fetcher: () => {
      calls++;
      return Promise.resolve(Response.json(null));
    },
  };
  const body = {
    scan_id: f.binding.scan_id,
    initial_recovery: {
      version: 1,
      phase: "completion",
      original: f.admission,
    },
  };
  await assertRejects(() =>
    readInitialRecovery(
      body,
      "00000000-0000-4000-8000-000000000999",
      new AbortController().signal,
      transport,
    )
  );
  await assertRejects(() =>
    readInitialRecovery(
      { ...body, recovery_scan: {} },
      f.binding.owner_id,
      new AbortController().signal,
      transport,
    )
  );
  const cancelled = new AbortController();
  cancelled.abort();
  await assertRejects(() =>
    readInitialRecovery(body, f.binding.owner_id, cancelled.signal, transport)
  );
  assertEquals(calls, 0);
});

Deno.test("prepared recovery HTTP preserves acknowledgement and completion bytes within fixed phase limits", async (t) => {
  const f = await cpmCompletionAdmissionFixture();
  const assignment = JSON.parse(f.binding.assignment_canonical);
  const original = {
    owner_id: f.binding.owner_id,
    scan_id: f.binding.scan_id,
    candidate_canonical: f.binding.candidate_canonical,
    candidate_digest: assignment.candidate_digest,
    content_digest: assignment.content_digest,
    assignment_digest: f.binding.assignment_digest,
    backend_generation: f.binding.backend_generation,
    backend_configuration_digest: f.binding.backend_configuration_digest,
  };
  const admission = snapshotInitialCompletionAdmission(f.admission);
  const found = await completionAcquisitionFixture(
    true,
    admission,
    "\ufeffe\u0301/🦋",
  );
  for (const mode of ["admission", "pending", "found"] as const) {
    await t.step(mode, async () => {
      let calls = 0;
      const phase = mode === "admission" ? "admission" : "completion";
      const body = JSON.stringify({
        scan_id: original.scan_id,
        initial_recovery: {
          version: 1,
          phase,
          original: mode === "admission" ? original : admission,
        },
      });
      // Admission gets its own ceiling; completion's exact byte boundary also
      // accepts legal whitespace without reserializing before measuring it.
      const padded = body +
        " ".repeat(
          (mode === "admission" ? 9000 : 8192) -
            new TextEncoder().encode(body).length,
        );
      const response = await readInitialRecoveryHttp(
        new Request("https://status.invalid", {
          method: "POST",
          headers: {
            "content-type": "application/json",
            "x-merian-initial-recovery": phase + "-v1",
          },
          body: padded,
        }),
        original.owner_id,
        {
          ...options,
          fetcher: () => {
            calls++;
            return Promise.resolve(Response.json(
              mode === "admission"
                ? {
                  version: 1,
                  assignment_canonical: f.binding.assignment_canonical,
                  acknowledgement: f.reply,
                }
                : mode === "found"
                ? found.reply
                : {
                  version: 1,
                  outcome: "pending",
                  admission_canonical: initialCanonicalText(admission),
                  reference: null,
                  result_digest: null,
                  original_provenance: null,
                  delivery: null,
                },
            ));
          },
        },
      );
      assertEquals(response.status, 200);
      assertEquals(response.headers.get("cache-control"), "no-store");
      const text = await response.text();
      if (mode === "admission") {
        assertEquals(text, initialCanonicalText(f.reply));
      } else {
        const decoded = JSON.parse(text);
        assertEquals(decoded.outcome, mode);
        assertEquals(
          decoded.admission_canonical,
          initialCanonicalText(admission),
        );
        if (mode === "found") {
          assertEquals(
            decoded.result_canonical,
            found.reply.delivery.result.result_canonical,
          );
        }
      }
      assertEquals(calls, 1);
    });
  }
});

Deno.test("prepared recovery HTTP rejects bad framing and bindings before private reads", async (t) => {
  const f = await cpmCompletionAdmissionFixture();
  const body = JSON.stringify({
    scan_id: f.binding.scan_id,
    initial_recovery: {
      version: 1,
      phase: "completion",
      original: f.admission,
    },
  });
  const defaults = {
    "content-type": "application/json",
    "x-merian-initial-recovery": "completion-v1",
  };
  const cases: {
    name: string;
    headers?: Record<string, string>;
    body?: BodyInit;
    owner?: string;
  }[] = [
    {
      name: "actual overflow",
      body: body + " ".repeat(8193 - new TextEncoder().encode(body).length),
    },
    { name: "declared overflow", headers: { "content-length": "8193" } },
    { name: "declared mismatch", headers: { "content-length": "0" } },
    { name: "invalid length", headers: { "content-length": "-1" } },
    { name: "wrong media type", headers: { "content-type": "text/plain" } },
    { name: "encoded body", headers: { "content-encoding": "gzip" } },
    {
      name: "unknown phase",
      headers: { "x-merian-initial-recovery": "future-v1" },
    },
    {
      name: "mismatched phase",
      headers: { "x-merian-initial-recovery": "admission-v1" },
    },
    { name: "mixed legacy", body: body.slice(0, -1) + ',"recovery_scan":{}}' },
    { name: "foreign owner", owner: "00000000-0000-4000-8000-000000000999" },
    { name: "malformed UTF8", body: new Uint8Array([0xc3, 0x28]) },
  ];
  for (const c of cases) {
    await t.step(c.name, async () => {
      let calls = 0;
      const response = await readInitialRecoveryHttp(
        new Request("https://status.invalid", {
          method: "POST",
          headers: { ...defaults, ...c.headers },
          body: c.body ?? body,
        }),
        c.owner ?? f.binding.owner_id,
        {
          ...options,
          fetcher: () => {
            calls++;
            return Promise.resolve(Response.json(null));
          },
        },
      );
      assertEquals(response.status, 503);
      assertEquals(
        await response.text(),
        '{"error":"initial_recovery_unavailable"}',
      );
      assertEquals(calls, 0);
    });
  }
});

Deno.test("prepared recovery HTTP cancels a stalled body without awaiting cancellation acknowledgement", async () => {
  const abort = new AbortController();
  let cancelled = false, reads = 0;
  const stream = new ReadableStream<Uint8Array>({
    pull() {
      return new Promise<void>(() => {});
    },
    cancel() {
      cancelled = true;
      return new Promise<void>(() => {});
    },
  });
  const request = new Request("https://status.invalid", {
    method: "POST",
    signal: abort.signal,
    headers: {
      "content-type": "application/json",
      "x-merian-initial-recovery": "completion-v1",
    },
    body: stream,
  });
  const pending = readInitialRecoveryHttp(
    request,
    "00000000-0000-4000-8000-000000000001",
    {
      ...options,
      fetcher: () => {
        reads++;
        return Promise.resolve(Response.json(null));
      },
    },
  );
  await Promise.resolve();
  assertEquals(request.body?.locked, true);
  abort.abort();
  const response = await pending;
  assertEquals(response.status, 503);
  assertEquals(cancelled, true);
  assertEquals(request.body?.locked, false);
  assertEquals(reads, 0);
});
