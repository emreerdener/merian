/** Local qualification bridge: input and identities remain in memory.
 * Emits only a boolean; never retain completion bodies in evidence logs.
 */
import { snapshotInitialCompletionDocuments } from "../functions/_shared/initialAnalysis/completionContract.ts";

try {
  const chunks: Uint8Array[] = [];
  let total = 0;
  for await (const chunk of Deno.stdin.readable) {
    total += chunk.length;
    if (total > 131072) throw new Error("bound");
    chunks.push(chunk);
  }
  const bytes = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.length;
  }
  const value: unknown = JSON.parse(
    new TextDecoder("utf-8", { fatal: true }).decode(bytes),
  );
  if (!Array.isArray(value) || value.length !== 2) throw new Error("shape");
  await snapshotInitialCompletionDocuments(value[0], value[1]);
  console.log(JSON.stringify({ passed: true }));
} catch {
  console.log(JSON.stringify({ passed: false }));
  Deno.exit(1);
}
