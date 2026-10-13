/** Disposable fixture driver. Input/output is piped by the Python owner; private
 * rows/identities remain in memory. This does not qualify physical storage. */
import {
  createDisposableHandoffBridge,
  localHandoffDiagnostic,
} from "./initial_media_handoff_bridge.ts";
import {
  decodeHandoffIO,
  decodeHandoffState,
  handoffIdentity,
} from "../functions/_shared/initialAnalysis/mediaHandoffRows.ts";
import {
  initialDeadline,
  readInitialStream,
} from "../functions/_shared/initialAnalysis/transport.ts";
import { initialCanonicalText } from "../functions/_shared/initialAnalysis/canonical.ts";
let stage = "input";
let lastWriterMs = 0;
async function main(signal: AbortSignal) {
  const input = JSON.parse(
    new TextDecoder().decode(
      await readInitialStream(Deno.stdin.readable, 4096, signal),
    ),
  );
  const id = handoffIdentity(input.identity);
  stage = "bridge_setup";
  const bridge = await createDisposableHandoffBridge(signal);
  let checks = 0, maxWriterMs = 0;
  const require = (condition: boolean) => {
    if (!condition) throw new Error("local_bridge_check_failed");
    checks++;
  };
  stage = "initial_state";
  const initial = await bridge.readState(id, signal);
  stage = "initial_decode";
  let rows = await decodeHandoffState(initial, id);
  require(rows.progress === null);
  if (input.mode === "timeout") {
    const began = performance.now();
    let unknown = false;
    try {
      await bridge.beginCopy(id, signal);
    } catch {
      unknown = true;
    }
    require(unknown);
    require(performance.now() - began < 8000);
    console.log(JSON.stringify({ passed: true, checks, mode: "timeout" }));
    return;
  }
  require(input.mode === "lifecycle");
  const write = async (
    run: () => Promise<unknown>,
    field: "progress" | "claim" | "verification" | "transfer",
  ) => {
    stage = "writer_" + field;
    const start = performance.now();
    let ack: unknown;
    try {
      ack = await run();
    } finally {
      lastWriterMs = Math.ceil(performance.now() - start);
    }
    maxWriterMs = Math.max(maxWriterMs, performance.now() - start);
    require(maxWriterMs < 5000);
    stage = "refresh_" + field;
    rows = await decodeHandoffState(await bridge.readState(id, signal), id);
    const record = ack as Record<string, unknown>;
    const value = field === "progress" ? rows.progress : (() => {
      const doc = rows[field];
      require(doc !== null);
      return {
        owner_id: id.owner_id,
        scan_id: id.scan_id,
        [field === "claim" ? "claim" : "receipt"]: doc!.canonical,
        [field === "claim" ? "claim_digest" : "receipt_digest"]: doc!.digest,
      };
    })();
    require(
      initialCanonicalText(record[field]) === initialCanonicalText(value),
    );
  };
  await write(() => bridge.beginCopy(id, signal), "progress");
  stage = "copy_loader";
  const copy = await decodeHandoffIO(
    await bridge.loadCopy(id, signal),
    id,
    "copy",
    null,
  );
  require(copy.rows.original.manifest === rows.original.manifest);
  for (const object of rows.mapping.objects) {
    await write(
      () => bridge.recordObject(id, object.object_id, signal),
      "progress",
    );
  }
  await write(() => bridge.completeCopy(id, signal), "progress");
  await write(() => bridge.claimVerification(id, signal), "claim");
  const token = rows.claim!.value.claim_token;
  stage = "verification_loader";
  const verification = await decodeHandoffIO(
    await bridge.loadVerification(id, token, signal),
    id,
    "verification",
    token,
  );
  require(verification.rows.claim?.digest === rows.claim!.digest);
  await write(
    () => bridge.settleVerification(id, token, signal),
    "verification",
  );
  await write(
    () => bridge.transfer(id, rows.verification!.digest, signal),
    "transfer",
  );
  require(rows.transfer !== null);
  console.log(
    JSON.stringify({
      passed: true,
      checks,
      mode: "lifecycle",
      max_writer_ms: Math.ceil(maxWriterMs),
    }),
  );
}
if (import.meta.main) {
  try {
    await initialDeadline(new AbortController().signal, 60000, main);
  } catch (error) {
    console.log(
      JSON.stringify({
        passed: false,
        error: "local_bridge_qualification_failed",
        stage,
        last_writer_ms: lastWriterMs,
        diagnostic: localHandoffDiagnostic(error),
      }),
    );
    Deno.exitCode = 1;
  }
}
