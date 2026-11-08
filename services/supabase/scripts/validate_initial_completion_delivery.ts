/** Disposable SQL-to-transport bridge. No network permission, body logs or
 * credentials; all response and original-request facts remain in memory. */
import { assertEquals } from "@std/assert";
import { initialCanonicalText } from "../functions/_shared/initialAnalysis/canonical.ts";
import { createInitialResultStore } from "../functions/_shared/initialAnalysis/resultStore.ts";
import { transformInitialResult } from "../functions/_shared/initialAnalysis/resultEncoding.ts";
import { provenanceContractV1 } from "../functions/_shared/initialAnalysis/resultSchemaV1.ts";

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
  const store = createInitialResultStore({
    reference: packet.reference,
    completionBinding: packet.binding,
    originalProvenanceCanonical: initialCanonicalText(
      transformInitialResult(provenanceContractV1, packet.provenance, "encode"),
    ),
    origin: "http://127.0.0.1",
    serverApiKey: ["sb", "secret", "fixture", "a".repeat(20)].join("_"),
    fetcher: (url, init) => {
      calls++;
      assertEquals(
        String(url),
        "http://127.0.0.1/rest/v1/rpc/read_initial_completion_v1",
      );
      assertEquals(JSON.parse(String(init?.body)), {
        p_owner: packet.reference.owner_id,
        p_scan: packet.reference.scan_id,
        p_submission: packet.reference.submission_digest,
        p_result: packet.reference.result_evidence_id,
        p_result_digest: packet.digest,
      });
      return Promise.resolve(Response.json(packet.reply));
    },
  });
  const delivered = await store.readCompletion(
    { ...packet.reference, result_digest: packet.digest },
    new AbortController().signal,
  );
  assertEquals(calls, 1);
  if (Deno.args[0] === "absent") assertEquals(delivered, null);
  else {
    assertEquals(Deno.args[0], "found");
    assertEquals(delivered, {
      ...packet.reply.completion,
      result: packet.reply.result,
    });
  }
  console.log(JSON.stringify({ passed: true }));
} catch {
  console.log(JSON.stringify({ passed: false }));
  Deno.exit(1);
}
