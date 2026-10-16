// This operator launcher is constructed locally; execution requires hosted approval.
import { requirePublicApiKeyFromEnvironment } from "../../../functions/_shared/publishableKey.ts";
import { createDriver } from "../driver.ts";
import { fileJournal } from "../journal.ts";
import { FIXTURES, LIMITS, systemClock, validAlias } from "../policy.ts";
import { AUTH_MODE } from "./config.ts";
import { driverTransport, type TransportDiagnostic } from "./transport.ts";

/** Readiness is an operator attestation, not independent object immutability proof. */
export function validateReadiness(value: unknown, run: string): boolean {
  if (!value || typeof value !== "object" || Array.isArray(value)) return false;
  const v = value as Record<string, unknown>;
  return Object.keys(v).sort().join(",") === "fixtures,run,writersClosed" &&
    v.run === run && v.writersClosed === true &&
    JSON.stringify(v.fixtures) ===
      JSON.stringify(
        Object.entries(FIXTURES).map(([id, f]) => ({
          id,
          bytes: f.bytes,
          sha256: f.sha256,
        })),
      );
}
async function main() {
  if (Deno.args.length !== 1 || Deno.args[0] !== "--approved-hosted-run") {
    throw Error("approval_argument_required");
  }
  const run = Deno.env.get("CPM_Q_RUN") ?? "";
  const capability = Deno.env.get("CPM_Q_CAPABILITY") ?? "";
  const expiresAt = Number(Deno.env.get("CPM_Q_EXPIRES_AT"));
  if (
    !validAlias(run) || !Number.isSafeInteger(expiresAt) ||
    expiresAt <= Date.now() || expiresAt - Date.now() > LIMITS.runMs
  ) throw Error("run_config");
  const directory = `.artifacts/client-prepared-media/hosted-${run}`;
  await Deno.mkdir(directory, { recursive: true });
  const runtimes: { deno: string; v8: string; authMode: typeof AUTH_MODE }[] =
    [];
  const diagnostics: TransportDiagnostic[] = [];
  const failures: { case: number; stage: string }[] = [];
  const driver = createDriver(run, capability, {
    clock: systemClock,
    journal: fileJournal(`${directory}/journal.jsonl`),
    rejectedCaller: true,
    expiresAt,
    recordFailure: (failure) => {
      if (failures.length >= 26) throw Error("diagnostic_bound");
      failures.push(failure);
    },
    send: driverTransport({
      operatorKey: Deno.env.get("CPM_Q_OPERATOR_KEY") ?? "",
      publicKey: requirePublicApiKeyFromEnvironment(),
      beforeSend: () => {
        if (Date.now() >= expiresAt) throw Error("expired");
      },
      recordDiagnostic: (diagnostic) => {
        if (diagnostics.length >= 26) throw Error("diagnostic_bound");
        diagnostics.push(diagnostic);
      },
      recordRuntime: (versions) => {
        if (runtimes.length >= 26) throw Error("runtime_bound");
        runtimes.push(versions);
      },
      fetchOnce: (request) => fetch(request),
    }),
    beforeBulk: async (controls) => {
      await Deno.writeTextFile(
        `${directory}/preflight.json`,
        JSON.stringify({ controls, runtimes }),
        { createNew: true, mode: 0o600 },
      );
      console.log(
        "Preflight complete. Operator must review it, close bulk uploads, then write bulk-ready.json. No automatic upload.",
      );
      for (;;) {
        if (Date.now() >= expiresAt) throw Error("expired");
        try {
          const file = await Deno.open(`${directory}/bulk-ready.json`, {
            read: true,
          });
          let value: unknown;
          try {
            const data = new Uint8Array(4097);
            let used = 0;
            while (used < data.length) {
              const n = await file.read(data.subarray(used));
              if (n === null) break;
              used += n;
            }
            if (used > 4096) throw Error("readiness_bound");
            value = JSON.parse(
              new TextDecoder("utf-8", { fatal: true }).decode(
                data.subarray(0, used),
              ),
            );
          } finally {
            file.close();
          }
          if (!validateReadiness(value, run)) throw Error("readiness_invalid");
          break;
        } catch (error) {
          if (!(error instanceof Deno.errors.NotFound)) {
            throw Error("readiness_invalid");
          }
        }
        await systemClock.sleep(250);
      }
    },
  });
  const state = await driver.run();
  await Deno.writeTextFile(
    `${directory}/result.json`,
    JSON.stringify({
      state,
      runtimes,
      diagnostics,
      failures,
      acknowledgements: driver.results(),
      denials: driver.denials(),
    }),
    { createNew: true, mode: 0o600 },
  );
  console.log(
    JSON.stringify({
      phase: state.phase,
      attempted: state.attempted.length,
      unresolved: state.obligations.length,
    }),
  );
  if (state.phase !== "complete") Deno.exitCode = 1;
}
if (import.meta.main) {
  try {
    await main();
  } catch {
    console.error("qualification_driver_failed");
    Deno.exitCode = 1;
  }
}
