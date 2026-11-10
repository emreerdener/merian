/** Local disposable-database qualification bridge. Never import from an Edge
 * entry point. It has no hosted URL, environment installer, credential, role,
 * arbitrary SQL input or caller-selectable connection/container. */
import type { HandoffBridge } from "../functions/_shared/initialAnalysis/mediaHandoffExecution.ts";
import {
  type HandoffIdentity,
  handoffIdentity,
} from "../functions/_shared/initialAnalysis/mediaHandoffRows.ts";
import {
  mediaDigest,
  mediaUUID,
} from "../functions/_shared/initialAnalysis/mediaBinding.ts";
import {
  initialAbortable,
  initialDeadline,
  readInitialStream,
} from "../functions/_shared/initialAnalysis/transport.ts";

const manifestURL = new URL(
  "../../../.artifacts/initial-media-handoff-v2/runtime-implementation/committed-disposable-state.json",
  import.meta.url,
);
const ACK = "merian_local_handoff_transaction_committed_v1";
const MAX_ROW_BYTES = 6 * 1024 * 1024;
const PHASES = [
  "connection_ready",
  "transaction_ready",
  "statement_complete",
  "commit_acknowledged",
] as const;
type LocalPhase = typeof PHASES[number];
export type LocalHandoffTrace = {
  elapsed_ms: number;
  diagnostic: string;
  phases_ms: Partial<Record<LocalPhase, number>>;
};
const marker = (phase: LocalPhase) => "merian_local_handoff_phase_" + phase;
/** Observe fixed psql markers as bytes arrive, including before a timeout.
 * Retain at most 96 bytes of any line; never retain row/error text in evidence.
 * Times are local arrival observations, not server execution measurements. */
export function localHandoffPhaseProbe(
  trace: LocalHandoffTrace,
  elapsed: () => number,
): TransformStream<Uint8Array, Uint8Array> {
  let line = "", oversized = false, next = 0;
  return new TransformStream({
    transform(chunk, controller) {
      let offset = 0;
      while (offset < chunk.length) {
        const newline = chunk.indexOf(10, offset);
        const end = newline < 0 ? chunk.length : newline;
        if (!oversized) {
          if (line.length + end - offset > 96) oversized = true;
          else {
            for (let i = offset; i < end; i++) {
              line += String.fromCharCode(chunk[i]);
            }
          }
        }
        if (newline >= 0) {
          if (
            !oversized && next < PHASES.length &&
            line === marker(PHASES[next])
          ) {
            trace.phases_ms[PHASES[next++]] = Math.ceil(elapsed());
          }
          line = "";
          oversized = false;
        }
        offset = end + 1;
      }
      controller.enqueue(chunk);
    },
  });
}
class LocalHandoffUnknown extends Error {
  constructor(readonly diagnostic: string) {
    super("initial_media_handoff_local_outcome_unknown");
  }
}
const unknown = (diagnostic = "unknown") => new LocalHandoffUnknown(diagnostic);
export function localHandoffDiagnostic(error: unknown): string {
  return error instanceof LocalHandoffUnknown ? error.diagnostic : "unknown";
}
/** Never expose command text, stderr, private rows, or raw transport diagnostics
 * in thrown errors. Only fixed diagnostic categories escape; all ambiguous
 * outcomes remain unknown to the coordinator. */
async function process(
  args: string[],
  input: string,
  signal: AbortSignal,
  maxBytes: number,
  probe?: TransformStream<Uint8Array, Uint8Array>,
): Promise<string> {
  const child = new Deno.Command("docker", {
    args,
    stdin: "piped",
    stdout: "piped",
    stderr: "piped",
  }).spawn();
  const terminate = () => {
    try {
      child.kill("SIGKILL");
    } catch { /* Already exited. */ }
  };
  signal.addEventListener("abort", terminate, { once: true });
  const writer = child.stdin.getWriter();
  try {
    // Drain both channels concurrently with input/status. Per-channel byte caps
    // apply before aggregation; no process output is printed or persisted.
    const output = await Promise.all([
      readInitialStream(
        probe ? child.stdout.pipeThrough(probe) : child.stdout,
        maxBytes,
        signal,
      ),
      readInitialStream(child.stderr, 65536, signal),
      initialAbortable(signal, () => child.status),
      initialAbortable(signal, async () => {
        await writer.write(new TextEncoder().encode(input));
        await writer.close();
      }),
    ]);
    if (!output[2].success) {
      const diagnostic = new TextDecoder().decode(output[1]);
      const code = /(?:ERROR|FATAL):\s+([A-Z0-9]{5})/.exec(diagnostic)?.[1];
      const allowed = [
        "22023",
        "23514",
        "25000",
        "55000",
        "57014",
        "55P03",
        "P0002",
      ];
      throw unknown(
        code && allowed.includes(code) ? "sql_" + code : "process_exit",
      );
    }
    return new TextDecoder("utf-8", { fatal: true }).decode(output[0]);
  } catch (error) {
    terminate();
    throw error instanceof LocalHandoffUnknown
      ? error
      : unknown("process_wait");
  } finally {
    signal.removeEventListener("abort", terminate);
    writer.releaseLock();
  }
}
/** Test harness setup only. The exact current-checkout ownership receipt is
 * fixed here, not supplied by a media request. Docker is pinned to the verified
 * local UNIX endpoint even if the ambient context subsequently changes. */
export async function createDisposableHandoffBridge(
  caller: AbortSignal,
  diagnostics?: LocalHandoffTrace[],
): Promise<HandoffBridge> {
  const { container, host } = await initialDeadline(
    caller,
    5000,
    async (signal) => {
      const bytes = await initialAbortable(
        signal,
        () => Deno.readFile(manifestURL),
      );
      if (bytes.length > 131072) throw unknown();
      const manifest = JSON.parse(
        new TextDecoder("utf-8", { fatal: true }).decode(bytes),
      );
      const temporaryRoot = Deno.build.os === "darwin"
        ? "/private/tmp/"
        : Deno.build.os === "linux"
        ? "/tmp/"
        : null;
      if (
        temporaryRoot === null ||
        manifest.state !== "ready" || manifest.start_exit !== 0 ||
        typeof manifest.project !== "string" ||
        !/^merian-handoff-runtime-[a-z0-9_]{8}$/.test(manifest.project) ||
        manifest.container !== "supabase_db_" + manifest.project ||
        manifest.workdir !== temporaryRoot + manifest.project ||
        typeof manifest.docker_host !== "string" ||
        !/^unix:\/\/\/[A-Za-z0-9_./-]+$/.test(manifest.docker_host)
      ) throw unknown();
      const context = JSON.parse(
        await process(["context", "inspect"], "", signal, 65536),
      );
      const host = context?.[0]?.Endpoints?.docker?.Host;
      if (
        typeof host !== "string" || host !== manifest.docker_host
      ) throw unknown();
      const inspection = JSON.parse(
        await process(
          ["--host", host, "container", "inspect", manifest.container],
          "",
          signal,
          65536,
        ),
      );
      if (
        !Array.isArray(inspection) || inspection.length !== 1 ||
        inspection[0].Name !== "/" + manifest.container ||
        inspection[0].State?.Running !== true ||
        inspection[0].Config?.Labels?.["com.supabase.cli.project"] !==
          manifest.project
      ) throw unknown();
      return { container: manifest.container as string, host };
    },
  );
  const invoke = async (sql: string, caller: AbortSignal): Promise<unknown> => {
    const began = performance.now();
    const trace: LocalHandoffTrace = {
      elapsed_ms: 0,
      diagnostic: "unknown",
      phases_ms: {},
    };
    const phase = (name: LocalPhase) =>
      diagnostics ? "\\echo " + marker(name) + "\n" : "";
    try {
      return await initialDeadline(caller, 5000, async (signal) => {
        const text = await process(
          [
            "--host",
            host,
            "exec",
            "-i",
            container,
            "psql",
            "-X",
            "-qAt",
            "-v",
            "ON_ERROR_STOP=1",
            "-v",
            "VERBOSITY=verbose",
            "-U",
            "postgres",
            "-d",
            "postgres",
          ],
          phase("connection_ready") +
            "BEGIN ISOLATION LEVEL READ COMMITTED;\n" +
            "SET LOCAL statement_timeout='5s';\nSET LOCAL lock_timeout='1s';\n" +
            phase("transaction_ready") + sql + "\n" +
            phase("statement_complete") + "COMMIT;\n" +
            phase("commit_acknowledged") + "SELECT '" + ACK + "';\n",
          signal,
          MAX_ROW_BYTES,
          diagnostics
            ? localHandoffPhaseProbe(trace, () => performance.now() - began)
            : undefined,
        );
        let lines = text.trimEnd().split("\n");
        if (diagnostics) {
          if (
            lines.length !== 6 || lines[0] !== marker(PHASES[0]) ||
            lines[1] !== marker(PHASES[1]) ||
            lines[3] !== marker(PHASES[2]) ||
            lines[4] !== marker(PHASES[3])
          ) throw unknown("phase_framing");
          lines = [lines[2], lines[5]];
        }
        if (lines.length !== 2 || lines[1] !== ACK) throw unknown();
        const row = JSON.parse(lines[0]);
        if (!row || typeof row !== "object" || Array.isArray(row)) {
          throw unknown();
        }
        trace.diagnostic = "acknowledged";
        return row;
      });
    } catch (error) {
      trace.diagnostic = error instanceof LocalHandoffUnknown
        ? error.diagnostic
        : "acknowledgement";
      throw error instanceof LocalHandoffUnknown
        ? error
        : unknown("acknowledgement");
    } finally {
      trace.elapsed_ms = Math.ceil(performance.now() - began);
      // This fixture has a finite cohort; cap observations independently of it.
      if (diagnostics && diagnostics.length < 128) diagnostics.push(trace);
    }
  };
  const args = (id: HandoffIdentity) => {
    const x = handoffIdentity(id);
    return `'${x.owner_id}'::uuid,'${x.scan_id}'::uuid,'${x.admission_receipt_digest}'::text`;
  };
  // Routine identifiers are literals. Every interpolation is a validated UUID
  // or lowercase SHA256, never caller-provided SQL or a private document.
  return Object.freeze({
    readState: (id: HandoffIdentity, s: AbortSignal) =>
      invoke(
        `SELECT row_to_json(x)::text FROM internal.read_initial_media_handoff_state(${
          args(id)
        }) x;`,
        s,
      ),
    loadCopy: (id: HandoffIdentity, s: AbortSignal) =>
      invoke(
        `SELECT row_to_json(x)::text FROM internal.load_initial_media_copy_io(${
          args(id)
        }) x;`,
        s,
      ),
    loadVerification: (id: HandoffIdentity, claim: string, s: AbortSignal) =>
      invoke(
        `SELECT row_to_json(x)::text FROM internal.load_initial_media_verification_io(${
          args(id)
        },'${mediaUUID(claim)}'::uuid) x;`,
        s,
      ),
    beginCopy: (id: HandoffIdentity, s: AbortSignal) =>
      invoke(
        `SELECT row_to_json(x)::text FROM internal.begin_initial_media_copy_v2(${
          args(id)
        }) x;`,
        s,
      ),
    recordObject: (id: HandoffIdentity, object: string, s: AbortSignal) =>
      invoke(
        `SELECT row_to_json(x)::text FROM internal.record_initial_media_copy_object_v2(${
          args(id)
        },'${mediaUUID(object)}'::uuid) x;`,
        s,
      ),
    completeCopy: (id: HandoffIdentity, s: AbortSignal) =>
      invoke(
        `SELECT row_to_json(x)::text FROM internal.complete_initial_media_copy_v2(${
          args(id)
        }) x;`,
        s,
      ),
    claimVerification: (id: HandoffIdentity, s: AbortSignal) =>
      invoke(
        `SELECT row_to_json(x)::text FROM internal.claim_initial_media_verification_v2(${
          args(id)
        }) x;`,
        s,
      ),
    settleVerification: (id: HandoffIdentity, claim: string, s: AbortSignal) =>
      invoke(
        `SELECT row_to_json(x)::text FROM internal.settle_initial_media_verification_v2(${
          args(id)
        },'${mediaUUID(claim)}'::uuid) x;`,
        s,
      ),
    transfer: (id: HandoffIdentity, verification: string, s: AbortSignal) =>
      invoke(
        `SELECT row_to_json(x)::text FROM internal.transfer_initial_preparation_v2(${
          args(id)
        },'${mediaDigest(verification)}'::text) x;`,
        s,
      ),
  });
}
