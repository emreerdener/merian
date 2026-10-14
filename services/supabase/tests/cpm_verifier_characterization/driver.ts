import { readByteStreamWithinLimit } from "../../functions/_shared/http.ts";
import { type Ack, requestFor } from "./handler.ts";
import {
  type Case,
  CASES,
  type Clock,
  FIXTURES,
  LIMITS,
  validAlias,
} from "./policy.ts";
import { memory } from "./telemetry.ts";
export interface Journal {
  /** Must durably refuse any existing run journal, including incomplete files. */
  begin(): Promise<void>;
  save(snapshot: DriverSnapshot): Promise<void>;
}
export interface DriverSnapshot {
  phase: "new" | "running" | "stopped" | "complete";
  attempted: number[];
  ordinaryCallsReserved: number;
  cleanupCalls: number;
  transferReserved: number;
  obligations: number[];
  reason: string;
}
export interface DriverDeps {
  clock: Clock;
  journal: Journal;
  send(request: Request, signal: AbortSignal): Promise<Response>;
}
async function acknowledgement(
  response: Response,
  item: Case,
  run: string,
): Promise<Ack> {
  if (
    response.status !== 200 || response.redirected ||
    !response.headers.get("content-type")?.startsWith("application/json")
  ) {
    await response.body?.cancel();
    throw Error("response");
  }
  const data = await readByteStreamWithinLimit(
    response.body,
    LIMITS.responseBytes,
  );
  if (!data.bytes || data.exceeded) throw Error("response");
  const ack = JSON.parse(
    new TextDecoder("utf-8", { fatal: true }).decode(data.bytes),
  ) as Ack;
  if (
    !ack ||
    Object.keys(ack).sort().join(",") !==
      "bytes,case,cleanup,closed,elapsedMs,fixture,memory,opened,outcome,quiescent,run,sha256,version,worker" ||
    ack.version !== 1 || ack.run !== run || ack.case !== item.id ||
    ack.fixture !== item.fixture || !validAlias(ack.worker) ||
    ack.closed !== true || ack.cleanup !== true ||
    !Number.isFinite(ack.elapsedMs) || ack.elapsedMs < 0 ||
    ack.elapsedMs >= LIMITS.requestMs
  ) throw Error("acknowledgement");
  memory(ack.memory);
  if (
    ack.memory.domain !== "partial_v8" || ack.memory.rss !== "unavailable" ||
    !Number.isSafeInteger(ack.memory.samples) || ack.memory.samples < 1 ||
    ack.memory.samples > 70_000 || !Number.isSafeInteger(ack.memory.proxy) ||
    ack.memory.proxy < Math.max(ack.memory.heapTotal, ack.memory.external) ||
    ack.memory.proxy >= LIMITS.proxyBytes
  ) throw Error("telemetry");
  if (item.mode === "deny") {
    if (
      ack.outcome !== "denied" || ack.opened !== false || ack.bytes !== 0 ||
      ack.sha256 !== null || ack.quiescent !== null
    ) throw Error("denial");
  } else if (ack.outcome === "busy") {
    if (
      item.id < 21 || item.id > 24 || ack.opened !== false || ack.bytes !== 0 ||
      ack.sha256 !== null || ack.quiescent !== null
    ) throw Error("busy");
  } else if (
    ack.outcome !== "verified" || ack.opened !== true ||
    ack.bytes !== FIXTURES[item.fixture].bytes ||
    ack.sha256 !== FIXTURES[item.fixture].sha256 ||
    !Number.isSafeInteger(ack.quiescent) || ack.quiescent! < 0 ||
    ack.quiescent! >= LIMITS.proxyBytes || ack.quiescent! > ack.memory.proxy
  ) throw Error("verification");
  return ack;
}
/** Single-use, fixed schedule only. No URL/config discovery, networking default or CLI. */
export function createDriver(
  run: string,
  capability: string,
  deps: DriverDeps,
) {
  if (!validAlias(run) || !/^[a-zA-Z0-9_-]{32,128}$/.test(capability)) {
    throw Error("driver_config");
  }
  let state: DriverSnapshot = {
    phase: "new",
    attempted: [],
    ordinaryCallsReserved: 48,
    cleanupCalls: 0,
    transferReserved: Object.values(FIXTURES).reduce((n, f) => n + f.bytes, 0),
    obligations: [],
    reason: "",
  };
  let running = false;
  let terminalAt: number | undefined;
  const pending = new Map<number, Promise<void>>(),
    controllers = new Set<AbortController>();
  const results: Ack[] = [];
  const snapshot = () => structuredClone(state);
  const stop = (reason: string) => {
    terminalAt ??= deps.clock.now();
    state.phase = "stopped";
    state.reason ||= reason;
    for (const c of controllers) c.abort();
  };
  const stopped = () => state.phase === "stopped";
  async function invoke(item: Case): Promise<void> {
    const deadlineAt = deps.clock.now() + LIMITS.requestMs;
    const abort = new AbortController();
    controllers.add(abort);
    let cancelTimer = () => {};
    const timeout = new Promise<never>((_, reject) => {
      cancelTimer = deps.clock.timeout(() => {
        stop("delivery_unknown");
        reject(Error("deadline"));
      }, LIMITS.requestMs);
    });
    const work = (async () => {
      const response = await deps.send(
        requestFor(run, item.id, capability),
        abort.signal,
      );
      if (abort.signal.aborted || stopped() || deps.clock.now() >= deadlineAt) {
        // Cleanup only; never parse a late success into permission for another read.
        await response.body?.cancel();
        throw Error("late_response");
      }
      const ack = await acknowledgement(response, item, run);
      if (abort.signal.aborted || stopped() || deps.clock.now() >= deadlineAt) {
        throw Error("late_acknowledgement");
      }
      results.push(ack);
      state.obligations = state.obligations.filter((id) => id !== item.id);
    })();
    // Retain ownership of outstanding cleanup even if driver deadline wins.
    const settled = work.then(() => {}, () => {}).finally(() => {
      pending.delete(item.id);
    });
    pending.set(item.id, settled);
    try {
      await Promise.race([work, timeout]);
    } catch {
      stop("delivery_or_verification_failed");
    } finally {
      cancelTimer();
      controllers.delete(abort);
    }
  }
  return {
    snapshot,
    results: () => structuredClone(results),
    pending: () => [...pending.values()],
    async run(): Promise<DriverSnapshot> {
      if (running || state.phase !== "new") throw Error("restart_forbidden");
      running = true;
      try {
        await deps.journal.begin();
      } catch {
        stop("journal_exists_or_unavailable");
        return snapshot();
      }
      state.phase = "running";
      const start = deps.clock.now();
      try {
        for (const group of [...new Set(CASES.map((c) => c.group))]) {
          if (state.phase !== "running") break;
          const items = CASES.filter((c) => c.group === group);
          await deps.clock.sleep(
            Math.max(0, items[0].atMs - (deps.clock.now() - start)),
          );
          if (
            state.phase !== "running" ||
            deps.clock.now() - start >= LIMITS.runMs ||
            state.obligations.length || items.length > 2
          ) throw Error("run_bound");
          const fixtureIDs = items.filter((c) => c.mode === "read").map((c) =>
            c.fixture
          );
          if (new Set(fixtureIDs).size !== fixtureIDs.length) {
            throw Error("fixture_overlap");
          }
          const bytes = items.reduce(
            (n, c) => n + (c.mode === "read" ? FIXTURES[c.fixture].bytes : 0),
            0,
          );
          if (
            items.some((c) => state.attempted.includes(c.id)) ||
            state.ordinaryCallsReserved + items.length * 5 >
              LIMITS.ordinaryCalls ||
            state.transferReserved + bytes > LIMITS.transferBytes
          ) throw Error("budget");
          state.ordinaryCallsReserved += items.length * 5; // driver + four handler outbound attempts, conservatively reserved.
          state.transferReserved += bytes;
          state.attempted.push(...items.map((c) => c.id));
          state.obligations.push(...items.map((c) => c.id));
          await deps.journal.save(snapshot()); // Entire pair persisted before either send.
          await Promise.all(items.map(invoke));
          await deps.journal.save(snapshot());
        }
        if (
          state.phase === "running" && state.attempted.length === 26 &&
          state.obligations.length === 0
        ) {
          state.phase = "complete";
          terminalAt = deps.clock.now();
        }
      } catch {
        stop("local_state_or_budget_failed");
      }
      try {
        await deps.journal.save(snapshot());
      } catch {
        stop("journal_unavailable");
      }
      return snapshot();
    },
    /** Records operator-owned cleanup only; does not execute any external action. */
    async reserveCleanup(calls: number): Promise<void> {
      if (
        !["stopped", "complete"].includes(state.phase) ||
        terminalAt === undefined ||
        deps.clock.now() - terminalAt >= LIMITS.cleanupMs ||
        !Number.isInteger(calls) || calls < 1 ||
        state.cleanupCalls + calls > LIMITS.cleanupCalls ||
        state.ordinaryCallsReserved + state.cleanupCalls + calls > LIMITS.calls
      ) throw Error("cleanup_bound");
      state = { ...state, cleanupCalls: state.cleanupCalls + calls };
      await deps.journal.save(snapshot());
    },
  };
}
