import { readInitialRecoveryHttp } from "../functions/check-scan-status/initialRecovery.ts";
import { encodeInitialCompletionStatus } from "../functions/_shared/initialAnalysis/completionStatusResponse.ts";
/** Synthetic local SQL bridge; no network permission, bodies or credentials in logs. */
import { assertEquals } from "@std/assert";
import { initialCanonicalText } from "../functions/_shared/initialAnalysis/canonical.ts";
import { createInitialCompletionAcquisition } from "../functions/_shared/initialAnalysis/resultStore.ts";
try {
  const chunks: Uint8Array[] = [];
  let total = 0;
  for await (const chunk of Deno.stdin.readable) {
    total += chunk.length;
    if (total > 3 * 1048576) throw new Error("bound");
    chunks.push(chunk);
  }
  const bytes = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.length;
  }
  const packet = JSON.parse(
    new TextDecoder("utf-8", { fatal: true }).decode(bytes),
  );
  let calls = 0;
  const store = createInitialCompletionAcquisition({
    admission: packet.admission,
    origin: "http://127.0.0.1",
    serverApiKey: ["sb", "secret", "fixture", "a".repeat(20)].join("_"),
    fetcher: (url, init) => {
      calls++;
      assertEquals(
        String(url),
        "http://127.0.0.1/rest/v1/rpc/discover_initial_completion_v1",
      );
      assertEquals(JSON.parse(String(init?.body)), {
        p_owner: packet.admission.owner_id,
        p_scan: packet.admission.scan_id,
        p_admission: initialCanonicalText(packet.admission),
      });
      return Promise.resolve(Response.json(packet.reply));
    },
  });
  const result = await store.read(new AbortController().signal);
  assertEquals(calls, 1);
  if (Deno.args[0] === "pending") assertEquals(result, null);
  else {
    assertEquals(Deno.args[0], "found");
    assertEquals(
      result?.reference.result_evidence_id,
      packet.expected_result_id,
    );
    assertEquals(
      result?.reference.invocation_id,
      packet.expected_invocation_id,
    );
    assertEquals(result?.admission, packet.admission);
  }
  let httpCalls = 0;
  const response = await readInitialRecoveryHttp(
    new Request("http://127.0.0.1/check-scan-status", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-merian-initial-recovery": "completion-v1",
      },
      body: JSON.stringify({
        initial_recovery: {
          version: 1,
          phase: "completion",
          original: packet.admission,
        },
      }),
    }),
    packet.admission.owner_id,
    {
      origin: "http://127.0.0.1",
      serverApiKey: ["sb", "secret", "fixture", "a".repeat(20)].join("_"),
      fetcher: (url, init) => {
        httpCalls++;
        assertEquals(
          String(url),
          "http://127.0.0.1/rest/v1/rpc/discover_initial_completion_v1",
        );
        assertEquals(JSON.parse(String(init?.body)), {
          p_owner: packet.admission.owner_id,
          p_scan: packet.admission.scan_id,
          p_admission: initialCanonicalText(packet.admission),
        });
        return Promise.resolve(Response.json(packet.reply));
      },
    },
  );
  assertEquals(response.status, 200);
  assertEquals(response.headers.get("cache-control"), "no-store");
  assertEquals(
    await response.text(),
    new TextDecoder().decode(
      encodeInitialCompletionStatus(packet.admission, result),
    ),
  );
  assertEquals(httpCalls, 1);
  console.log(JSON.stringify({ passed: true }));
} catch {
  console.log(JSON.stringify({ passed: false }));
  Deno.exit(1);
}
