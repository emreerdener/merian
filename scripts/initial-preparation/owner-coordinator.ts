/** Executed only by the fixed local qualification harness; no network or storage. */
import { ownerFixture } from "./owner-fixture.ts";
import { createOwnerRuntime } from "./owner-exchange.ts";
import { initialCanonicalText } from "../../services/supabase/functions/_shared/initialAnalysis/canonical.ts";
import { executionDigest } from "../../services/supabase/functions/_shared/initialAnalysis/preparationExecutionContract.ts";
import { runInitialPreparation } from "../../services/supabase/functions/_shared/initialAnalysis/preparationExecution.ts";

const encoder = new TextEncoder();
async function write(text: string) {
  const bytes = encoder.encode(text);
  let offset = 0;
  while (offset < bytes.length) {
    offset += await Deno.stdout.write(bytes.subarray(offset));
  }
}
async function exchange(frame: string, signal: AbortSignal): Promise<string> {
  if (signal.aborted) throw new Error("local_fixture_stopped");
  const abort = () => {
    try {
      Deno.stdin.close();
    } catch { /* Already closed. */ }
  };
  signal.addEventListener("abort", abort, { once: true });
  try {
    await write(frame);
    const chunks: Uint8Array[] = [], buffer = new Uint8Array(4096);
    let total = 0;
    while (!signal.aborted) {
      const n = await Deno.stdin.read(buffer);
      if (n === null) throw new Error("local_fixture_eof");
      if (n === 0) throw new Error("local_fixture_empty_read");
      total += n;
      if (total > 300000) throw new Error("local_fixture_response_cap");
      const chunk = buffer.slice(0, n);
      chunks.push(chunk);
      const newline = chunk.indexOf(10);
      if (newline >= 0) {
        if (newline !== chunk.length - 1) {
          throw new Error("local_fixture_extra_frame");
        }
        const bytes = new Uint8Array(total);
        let offset = 0;
        for (const c of chunks) {
          bytes.set(c, offset);
          offset += c.length;
        }
        return new TextDecoder("utf-8", { fatal: true }).decode(bytes);
      }
    }
    throw new Error("local_fixture_stopped");
  } finally {
    signal.removeEventListener("abort", abort);
  }
}
export async function main() {
  const fixture = await ownerFixture(createOwnerRuntime(exchange));
  const first = await runInitialPreparation(
    fixture.deps,
    fixture.input,
    new AbortController().signal,
  );
  const replay = await runInitialPreparation(
    fixture.deps,
    fixture.input,
    new AbortController().signal,
  );
  await write(
    JSON.stringify({
      version: 1,
      kind: "summary",
      outcome: first.kind,
      replay: replay.kind,
      runtime: fixture.counts.runtime,
      issues: fixture.counts.issues,
      reads: fixture.counts.reads,
      retains: fixture.counts.retains,
      outcome_digest: first.kind === "outcome_ready"
        ? await executionDigest("outcome", initialCanonicalText(first.outcome))
        : null,
    }) + "\n",
  );
}
if (import.meta.main) {
  try {
    await main();
  } catch {
    Deno.exit(1);
  }
}
