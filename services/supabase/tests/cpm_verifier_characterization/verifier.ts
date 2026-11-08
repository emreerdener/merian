import { createHash } from "node:crypto";
import { type Clock, type FixtureID, FIXTURES, LIMITS } from "./policy.ts";
import { type MemorySummary, Samples } from "./telemetry.ts";
export interface VerifyDeps {
  clock: Clock;
  samples?: Samples;
  watch?: boolean;
  deadlineAt?: number;
  memory(): unknown;
  /** Must settle acquisition/read on abort. Unknown settlement keeps worker held. */
  get(fixture: FixtureID, signal: AbortSignal): Promise<Response>;
}
export interface Verification {
  ok: boolean;
  closed: boolean;
  bytes: number;
  sha256: string | null;
  reason: string;
  quiescent: number | null;
  memory: MemorySummary;
  elapsedMs: number;
}
/** Never races an unowned read promise to start replacement I/O. No background work. */
export async function verify(
  fixture: FixtureID,
  caller: AbortSignal,
  deps: VerifyDeps,
): Promise<Verification> {
  const spec = FIXTURES[fixture],
    samples = deps.samples ?? new Samples(),
    start = deps.clock.now();
  const deadlineAt = deps.deadlineAt ?? start + LIMITS.requestMs;
  const abort = new AbortController();
  let reason = "ok",
    bytes = 0,
    digest: string | null = null,
    complete = false,
    closed = false;
  let reader: ReadableStreamDefaultReader<Uint8Array> | undefined;
  let hash: ReturnType<typeof createHash> | undefined;
  let cancelSampling = () => {}, cancelDeadline = () => {};
  const stop = (why: string) => {
    if (reason === "ok") reason = why;
    abort.abort();
    cancelSampling();
  };
  const expired = () => {
    if (deps.clock.now() >= deadlineAt) stop("deadline");
    return abort.signal.aborted;
  };
  const cancelled = () => stop("caller_abort");
  const sample = () => {
    try {
      return samples.take(deps.memory());
    } catch {
      stop("telemetry_stop");
      return null;
    }
  };
  caller.addEventListener("abort", cancelled, { once: true });
  try {
    if (caller.aborted) stop("caller_abort");
    if (sample() === null || expired()) throw Error("stop");
    cancelDeadline = deps.clock.timeout(
      () => stop("deadline"),
      Math.max(0, deadlineAt - deps.clock.now()),
    );
    if (deps.watch !== false) {
      cancelSampling = deps.clock.interval(() => {
        sample();
      }, LIMITS.sampleMs);
    }
    hash = createHash("sha256");
    // Await acquisition even after cancellation; dispose a late body before responding.
    const response = await deps.get(fixture, abort.signal);
    if (response.body) {
      reader = response.body.getReader();
      // Attach a rejection handler immediately; cleanup still awaits terminal state.
      reader.closed.catch(() => {});
    }
    if (expired()) throw Error("stop");
    if (
      response.status !== 200 || response.redirected || !reader ||
      response.headers.get("content-length") !== String(spec.bytes) ||
      response.headers.has("content-encoding")
    ) throw Error("response");
    let chunks = 0;
    for (;;) {
      if (expired()) throw Error("stop");
      const next = await reader.read();
      if (expired()) throw Error("stop");
      if (next.done) break;
      if (
        ++chunks > LIMITS.maxChunks ||
        next.value.byteLength > LIMITS.maxChunkBytes ||
        next.value.byteLength > spec.bytes - bytes
      ) throw Error("length");
      hash.update(next.value);
      bytes += next.value.byteLength;
      if (sample() === null) throw Error("stop");
    }
    if (expired()) throw Error("stop");
    digest = hash.digest("hex");
    if (expired()) throw Error("stop");
    if (bytes !== spec.bytes || digest !== spec.sha256) {
      throw Error("integrity");
    }
    complete = true;
  } catch (error) {
    if (reason === "ok") {
      reason = error instanceof Error &&
          ["response", "length", "integrity"].includes(error.message)
        ? error.message
        : "read_failed";
    }
    abort.abort();
  } finally {
    cancelSampling();
    cancelDeadline();
    caller.removeEventListener("abort", cancelled);
    try {
      if (reader) {
        if (!complete) await reader.cancel();
        await reader.closed;
        reader.releaseLock();
        reader = undefined;
      }
      // No acquired body or all owned body work settled. This is not socket/GC proof.
      closed = true;
    } catch {
      reason = "cleanup_unknown";
      // Never claim positive closure or release the worker for new reads.
      try {
        reader?.releaseLock();
      } catch { /* still held; no replacement */ }
    }
    hash?.destroy();
    hash = undefined;
  }
  expired();
  const quiescent = sample();
  return {
    ok: complete && reason === "ok" && closed,
    closed,
    bytes,
    sha256: digest,
    reason,
    quiescent,
    memory: samples.summary,
    elapsedMs: Math.max(0, deps.clock.now() - start),
  };
}
