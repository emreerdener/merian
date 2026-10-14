import { withPublicEdgeHandler } from "../../functions/_shared/edgeHandler.ts";
import { bearerTokenFromAuthorizationHeader } from "../../functions/_shared/auth.ts";
import {
  jsonResponse,
  publicErrorResponse,
  readBoundedJsonBody,
  timingSafeCompare,
} from "../../functions/_shared/http.ts";
import {
  CASES,
  type Clock,
  type FixtureID,
  FIXTURES,
  LIMITS,
  validAlias,
} from "./policy.ts";
import { Growth, Samples } from "./telemetry.ts";
import { verify, type VerifyDeps } from "./verifier.ts";
export interface RunConfig {
  run: string;
  worker: string;
  operator: string;
  capability: string;
  expiresAt: number;
}
export interface HandlerDeps extends VerifyDeps {
  /** Trusted verification seam: never accepts an unverified caller-supplied subject. */
  authenticate(bearer: string, signal: AbortSignal): Promise<string | null>;
}
export interface Ack {
  version: 1;
  run: string;
  case: number;
  fixture: FixtureID;
  worker: string;
  outcome: "verified" | "busy" | "denied" | "stopped";
  opened: boolean;
  closed: boolean;
  bytes: number;
  sha256: string | null;
  cleanup: boolean;
  memory: Samples["summary"];
  quiescent: number | null;
  elapsedMs: number;
}
/** No default fetch/auth/env adapters and no Deno.serve registration. */
export function createHandler(config: RunConfig, deps: HandlerDeps) {
  if (
    !validAlias(config.run) || !validAlias(config.worker) ||
    !validAlias(config.operator) ||
    !/^[a-zA-Z0-9_-]{32,128}$/.test(config.capability) ||
    !Number.isSafeInteger(config.expiresAt)
  ) throw Error("config");
  const frozen = Object.freeze({ ...config }),
    seen = new Set<number>(),
    growth = new Growth();
  let busy = false, halted = false;
  const live = new Map<AbortController, () => void>();
  const stop = () => {
    halted = true;
    for (const [controller, cancelTimers] of live) {
      controller.abort();
      cancelTimers();
    }
  };
  return {
    state: () => ({ busy, halted, seen: seen.size }),
    async handle(req: Request): Promise<Response> {
      const start = deps.clock.now(),
        sample = new Samples(),
        abort = new AbortController();
      let timer = () => {}, deadline = () => {};
      const capture = () => {
        try {
          sample.take(deps.memory());
        } catch {
          stop();
        }
      };
      const onAbort = () => {
        abort.abort();
        timer();
        deadline();
      };
      const expired = () =>
        halted || abort.signal.aborted ||
        deps.clock.now() - start >= LIMITS.requestMs ||
        deps.clock.wall() >= frozen.expiresAt;
      live.set(abort, () => {
        timer();
        deadline();
      });
      req.signal.addEventListener("abort", onAbort, { once: true });
      if (req.signal.aborted) onAbort();
      capture();
      if (!abort.signal.aborted) {
        timer = deps.clock.interval(capture, LIMITS.sampleMs);
        deadline = deps.clock.timeout(stop, LIMITS.requestMs);
      }
      try {
        return await withPublicEdgeHandler(req, async () => {
          const reject = (status: number, code: string) =>
            publicErrorResponse(
              req,
              status,
              code,
              "Qualification request rejected.",
            );
          if (req.method !== "POST") return reject(405, "method_not_allowed");
          const bearer = bearerTokenFromAuthorizationHeader(
            req.headers.get("authorization"),
          );
          if (
            !bearer ||
            !timingSafeCompare(
              req.headers.get("x-qualification-capability") ?? "",
              frozen.capability,
            )
          ) return reject(403, "forbidden");
          if (
            halted || abort.signal.aborted ||
            deps.clock.wall() >= frozen.expiresAt
          ) {
            stop();
            return reject(409, "qualification_stopped");
          }
          let operator: string | null;
          try {
            operator = await deps.authenticate(bearer, abort.signal);
          } catch {
            stop();
            return reject(503, "auth_unavailable");
          }
          if (expired()) {
            stop();
            return reject(409, "qualification_stopped");
          }
          capture();
          if (expired()) {
            stop();
            return reject(409, "qualification_stopped");
          }
          if (operator !== frozen.operator) return reject(403, "forbidden");
          const parsed = await readBoundedJsonBody<Record<string, unknown>>(
            req,
            { limit: "small", maxBytes: LIMITS.requestBytes },
          );
          if (expired()) {
            stop();
            return reject(409, "qualification_stopped");
          }
          capture();
          if (parsed.error || !parsed.value) {
            return reject(
              parsed.error?.status ?? 400,
              parsed.error?.code ?? "invalid_request",
            );
          }
          const input = parsed.value;
          if (
            Object.keys(input).sort().join(",") !== "case,fixture,run" ||
            input.run !== frozen.run || !Number.isSafeInteger(input.case)
          ) return reject(400, "invalid_request");
          const item = CASES.find((c) => c.id === input.case);
          if (!item || item.fixture !== input.fixture) {
            return reject(400, "invalid_request");
          }
          if (
            halted || abort.signal.aborted ||
            deps.clock.now() - start >= LIMITS.requestMs ||
            deps.clock.wall() >= frozen.expiresAt
          ) {
            stop();
            return reject(409, "qualification_stopped");
          }
          if (seen.has(item.id)) {
            stop();
            return reject(409, "duplicate_case");
          }
          seen.add(item.id);
          const ack: Ack = {
            version: 1,
            run: frozen.run,
            case: item.id,
            fixture: item.fixture,
            worker: frozen.worker,
            outcome: "denied",
            opened: false,
            closed: true,
            cleanup: true,
            bytes: 0,
            sha256: null,
            memory: sample.summary,
            quiescent: null,
            elapsedMs: 0,
          };
          if (item.mode !== "deny" && !busy) {
            busy = true;
            ack.opened = true; // Conservative read obligation even if GET later fails to open a body.
            const result = await verify(item.fixture, abort.signal, {
              ...deps,
              samples: sample,
              watch: false,
              deadlineAt: start + LIMITS.requestMs,
            });
            ack.outcome = result.ok ? "verified" : "stopped";
            ack.closed = result.closed;
            ack.cleanup = result.closed;
            ack.bytes = result.bytes;
            ack.sha256 = result.sha256;
            ack.quiescent = result.quiescent;
            if (result.closed) busy = false;
            if (
              !result.ok || result.quiescent === null ||
              growth.add(result.quiescent)
            ) {
              stop();
              ack.outcome = "stopped";
            }
          } else if (item.mode !== "deny") ack.outcome = "busy";
          capture();
          if (expired()) {
            stop();
            ack.outcome = "stopped";
          }
          ack.elapsedMs = Math.max(0, deps.clock.now() - start);
          timer();
          deadline(); // Must precede a terminal acknowledgement.
          const body = JSON.stringify(ack);
          if (new TextEncoder().encode(body).length > LIMITS.responseBytes) {
            stop();
            return reject(503, "response_bound");
          }
          return jsonResponse(ack, 200, { "Cache-Control": "no-store" });
        });
      } finally {
        timer();
        deadline();
        req.signal.removeEventListener("abort", onAbort);
        live.delete(abort);
      }
    },
  };
}
export function requestFor(
  run: string,
  id: number,
  capability: string,
  bearer = "synthetic-test",
) {
  const c = CASES.find((item) => item.id === id);
  if (!c) throw Error("case");
  return new Request("https://qualification.invalid/", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      authorization: `Bearer ${bearer}`,
      "x-qualification-capability": capability,
    },
    body: JSON.stringify({ run, case: id, fixture: c.fixture }),
  });
}
export type { Clock };
export { FIXTURES };
