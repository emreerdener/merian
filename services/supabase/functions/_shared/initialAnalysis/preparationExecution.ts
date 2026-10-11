/** Inactive synthetic-composition boundary. No provider, URL, key, artifact
 * loader or live storage dependency is available to its runtime interface. */
import { initialCanonicalText, invalidInitialInput } from "./canonical.ts";
import {
  executionDigest,
  type PreparationContext,
  preparationContext,
  type PreparationFacts,
  type PreparationGrant,
  type PreparationOutcome,
  type PreparationOutputReceipt,
  preparationReference,
  type PreparationResolvedManifest,
  type PreparationSourceReceipt,
  type PreparationTuple,
  preparationWallMs,
  sameExecutionValue,
  validateGrant,
  validateOutputReceipt,
  validatePreparationOutcome,
  validatePreparationReply,
  validateResolvedManifest,
  validateSourceReceipt,
} from "./preparationExecutionContract.ts";
import { checkInitialDeadline, initialDeadline } from "./transport.ts";
import type { InitialMediaPreparationProfile } from "./mediaPreparationProfile.ts";

export type PreparationOperation =
  | "get_initial_preparation_execution_status"
  | "settle_initial_preparation_sources"
  | "issue_initial_preparation_execution"
  | "register_initial_preparation_output"
  | "settle_initial_preparation_outcome";
export interface PreparationExecutionDependencies {
  /** Fixed service calls, one attempt, no retry/renewal/SDK policy. */
  call(
    operation: PreparationOperation,
    args: Record<string, unknown>,
    signal: AbortSignal,
  ): Promise<unknown>;
  /** Trusted synthetic owner of original fixed objects. No URL/key accepted. */
  readSource(
    ordinal: number,
    objectId: string,
    signal: AbortSignal,
  ): Promise<Uint8Array>;
  inspectSource(
    ordinal: number,
    privateBytes: Uint8Array,
    signal: AbortSignal,
  ): Promise<PreparationFacts>;
  /** Reads return defensive copies of the exact verified snapshot. */
  runtime(
    input: {
      read(ordinal: number): Uint8Array;
      profile: InitialMediaPreparationProfile;
    },
    signal: AbortSignal,
  ): Promise<(Uint8Array | null)[]>;
  /** Read-only verification of an immutable original. No write capability. */
  verifyExistingIdentityOutput(
    ordinal: number,
    objectId: string,
    signal: AbortSignal,
  ): Promise<Uint8Array>;
  /** Conditional create only (no overwrite), followed by exact read-back.
   * An existing key is accepted only with identical bytes. Synthetic adapters
   * cannot establish real durable storage qualification. */
  createFreshOutputAndReadBack(
    ordinal: number,
    objectId: string,
    bytes: Uint8Array,
    signal: AbortSignal,
  ): Promise<Uint8Array>;
}
interface Scope {
  owner: string;
  ctx: PreparationContext;
}
interface KnownOutput {
  scope: Scope;
  source: PreparationSourceReceipt;
  grant: PreparationGrant;
  deadlines: { registration: number; outcome: number };
  request: PreparationOutputReceipt;
  bytes: (Uint8Array<ArrayBuffer> | null)[];
  resolved: PreparationResolvedManifest | null;
  outcome: PreparationOutcome | null;
}
const reconciliations = new WeakMap<object, KnownOutput>();
export interface PreparationReconciliation {
  readonly kind: "known_original_output";
}
export type PreparationRunResult =
  | { kind: "outcome_ready"; outcome: PreparationOutcome }
  | {
    kind: "recovery_needed";
    reason: string;
    known?: PreparationReconciliation;
  }
  | { kind: "held"; reason: string };
const unknown = (): PreparationRunResult => ({
  kind: "recovery_needed",
  reason: "original_status_required",
});
function clone<T>(v: T): T {
  return JSON.parse(initialCanonicalText(v));
}
function object(v: unknown, keys: string[]): Record<string, unknown> {
  if (
    !v || typeof v !== "object" || Array.isArray(v) ||
    Object.keys(v).sort().join() !== [...keys].sort().join()
  ) invalidInitialInput();
  return v as Record<string, unknown>;
}
function checkedBytes(v: Uint8Array, max: number): Uint8Array<ArrayBuffer> {
  if (
    !(v instanceof Uint8Array) || !(v.buffer instanceof ArrayBuffer) ||
    v.length < 1 || v.length > max
  ) invalidInitialInput();
  return new Uint8Array(v);
}
async function hash(bytes: Uint8Array<ArrayBuffer>): Promise<string> {
  return [...new Uint8Array(await crypto.subtle.digest("SHA-256", bytes))].map(
    (b) => b.toString(16).padStart(2, "0"),
  ).join("");
}
function equalBytes(a: Uint8Array, b: Uint8Array): boolean {
  return a.length === b.length && a.every((v, i) => v === b[i]);
}
function identity(ctx: PreparationContext) {
  return {
    version: 1 as const,
    scan_id: ctx.scan_id,
    assignment_digest: ctx.assignment_digest,
  };
}
function args(s: Scope) {
  return {
    p_owner: s.owner,
    p_scan: s.ctx.scan_id,
    p_assignment_digest: s.ctx.assignment_digest,
  };
}
function stopped(signal: AbortSignal, deadline = Infinity): boolean {
  return signal.aborted || performance.now() >= deadline;
}
/** Local cancellation is passed to the dependency, but an already-started
 * bounded phase can still return a known answer. Timeout remains uncertainty.
 * No continuation is attached to an answer arriving after the phase cap. */
async function knownPhase<T>(
  caller: AbortSignal,
  ms: number,
  run: (signal: AbortSignal) => Promise<T>,
): Promise<T> {
  if (!Number.isFinite(ms) || ms <= 0 || caller.aborted) {
    throw new Error("initial_preparation_stopped");
  }
  const at = performance.now() + ms;
  return await initialDeadline(caller, ms, async (signal) => {
    let timer: ReturnType<typeof setTimeout> | undefined;
    try {
      checkInitialDeadline(signal);
      const result = await Promise.race([
        run(signal),
        new Promise<never>((_, reject) => {
          timer = setTimeout(
            () => reject(new Error("initial_preparation_unknown")),
            ms,
          );
        }),
      ]);
      // Ignore caller cancellation only for an on-time known answer. Timers can
      // be starved by synchronous work or a chain of ready microtasks.
      if (performance.now() >= at) {
        throw new Error("initial_preparation_unknown");
      }
      return result;
    } finally {
      if (timer !== undefined) clearTimeout(timer);
    }
  });
}
function held(value: Record<string, unknown>): PreparationRunResult | null {
  if (value.outcome !== "held") return null;
  object(value, ["version", "outcome", "reason"]);
  if (
    value.version !== 1 ||
    ![
      "missing",
      "expired",
      "incoherent",
      "preparation_issued",
      "budget",
      "phase_expired",
    ].includes(String(value.reason))
  ) invalidInitialInput();
  return {
    kind: value.reason === "preparation_issued" || value.reason === "incoherent"
      ? "recovery_needed"
      : "held",
    reason: String(value.reason),
  };
}
async function rpc(
  deps: PreparationExecutionDependencies,
  op: PreparationOperation,
  parameters: Record<string, unknown>,
  signal: AbortSignal,
  deadline = Infinity,
): Promise<Record<string, unknown>> {
  const answer = await knownPhase(
    signal,
    Math.min(5000, deadline - performance.now()),
    (s) => deps.call(op, parameters, s),
  );
  return validatePreparationReply(answer);
}
function times(v: Record<string, unknown>): { now: number; expiry: number } {
  const now = v.server_now_ms, expiry = v.expires_at_ms;
  if (
    typeof now !== "number" || typeof expiry !== "number" ||
    !Number.isSafeInteger(now) || !Number.isSafeInteger(expiry) || now < 0 ||
    expiry <= now || expiry - now > 300000
  ) invalidInitialInput();
  return { now, expiry };
}
function ticket(known: KnownOutput): PreparationRunResult {
  const value = Object.freeze({ kind: "known_original_output" as const });
  reconciliations.set(value, known);
  return {
    kind: "recovery_needed",
    reason: "known_output_settlement_only",
    known: value,
  };
}
async function verifySources(
  deps: PreparationExecutionDependencies,
  s: Scope,
  signal: AbortSignal,
): Promise<
  { receipt: PreparationSourceReceipt; bytes: Uint8Array<ArrayBuffer>[] }
> {
  const m = s.ctx.assignment.preparation.source_mapping,
    bytes: Uint8Array<ArrayBuffer>[] = [],
    entries: PreparationSourceReceipt["entries"] = [];
  await knownPhase(signal, 30000, async (phase) => {
    for (const entry of m) {
      checkInitialDeadline(phase);
      const supplied = await deps.readSource(
        entry.ordinal,
        entry.object_id,
        phase,
      );
      checkInitialDeadline(phase);
      // Copy synchronously before hashing/structural awaits. Shared memory rejects.
      const owned = checkedBytes(supplied, entry.source.source_byte_count);
      if (
        owned.length !== entry.source.source_byte_count ||
        await hash(owned) !== entry.source.source_sha256
      ) invalidInitialInput();
      checkInitialDeadline(phase);
      const facts = clone(
        await deps.inspectSource(entry.ordinal, new Uint8Array(owned), phase),
      );
      checkInitialDeadline(phase);
      bytes.push(owned);
      entries.push({
        ordinal: entry.ordinal,
        object_id: entry.object_id,
        bytes: {
          byte_count: owned.length,
          sha256: entry.source.source_sha256,
          content_type: entry.source.source_content_type,
        },
        facts,
      });
    }
  });
  const receipt: PreparationSourceReceipt = {
    ...identity(s.ctx),
    profile_digest: s.ctx.assignment.preparation.profile_digest,
    backend_generation: s.ctx.assignment.preparation.backend_generation,
    validator_identity: s.ctx.profile.spec.identities.validator,
    entries,
  };
  validateSourceReceipt(s.ctx, receipt);
  return { receipt, bytes };
}
/** Status/replay is never reinterpreted as a fresh capability. Calling this
 * again after issuance returns recovery_needed with zero runtime calls. */
export async function runInitialPreparation(
  deps: PreparationExecutionDependencies,
  input: {
    owner: string;
    scan: string;
    candidate: unknown;
    assignment: unknown;
    profile: unknown;
  },
  signal: AbortSignal,
): Promise<PreparationRunResult> {
  try {
    if (
      !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(
        input.owner,
      )
    ) invalidInitialInput();
    const s: Scope = {
      owner: input.owner,
      ctx: await preparationContext(
        input.scan,
        input.candidate,
        input.assignment,
        input.profile,
      ),
    };
    const start = performance.now(),
      status = await rpc(
        deps,
        "get_initial_preparation_execution_status",
        args(s),
        signal,
      ),
      h = held(status);
    if (h) return h;
    object(status, [
      "version",
      "outcome",
      "phase",
      "source",
      "execution_reference",
      "output",
      "result",
      "server_now_ms",
      "expires_at_ms",
    ]);
    if (status.outcome !== "status") invalidInitialInput();
    const t = times(status),
      deadline = performance.now() + t.expiry - t.now -
        (performance.now() - start);
    if (status.phase === "outcome_ready") {
      await validatePreparationOutcome(s.ctx, status.result);
      const result = status.result as PreparationOutcome;
      if (
        !sameExecutionValue(status.source, result.source_verification) ||
        !sameExecutionValue(
          status.execution_reference,
          preparationReference(result.grant),
        ) ||
        !sameExecutionValue(status.output, {
          request: result.output_manifest,
          resolved: result.resolved_manifest,
        })
      ) invalidInitialInput();
      return { kind: "outcome_ready", outcome: clone(result) };
    }
    if (status.phase !== "allocated" && status.phase !== "verified") {
      return { kind: "recovery_needed", reason: "preparation_already_issued" };
    }
    if (
      status.execution_reference !== null || status.output !== null ||
      status.result !== null ||
      (status.phase === "allocated") !== (status.source === null)
    ) invalidInitialInput();
    if (
      stopped(signal) ||
      deadline - performance.now() <= 120000 + preparationWallMs(s.ctx)
    ) return { kind: "held", reason: "budget" };
    const sources = await verifySources(deps, s, signal);
    if (
      status.source !== null &&
      !sameExecutionValue(status.source, sources.receipt)
    ) invalidInitialInput();
    if (stopped(signal, deadline)) {
      return { kind: "held", reason: "cancelled_before_issue" };
    }
    const text = validateSourceReceipt(s.ctx, sources.receipt),
      sourceDigest = await executionDigest("source_verification", text);
    const verification = await rpc(
        deps,
        "settle_initial_preparation_sources",
        {
          ...args(s),
          p_receipt: text,
        },
        signal,
        deadline,
      ),
      vh = held(verification);
    if (vh) return vh;
    object(verification, ["version", "outcome", "receipt", "digest"]);
    if (
      verification.outcome !== "verified" ||
      verification.digest !== sourceDigest ||
      !sameExecutionValue(verification.receipt, sources.receipt)
    ) invalidInitialInput();
    if (stopped(signal, deadline)) {
      return { kind: "held", reason: "cancelled_before_issue" };
    }
    const issueStart = performance.now(),
      answer = await rpc(
        deps,
        "issue_initial_preparation_execution",
        {
          ...args(s),
          p_source_digest: sourceDigest,
        },
        signal,
        deadline,
      ),
      gh = held(answer);
    if (gh) return gh;
    object(answer, [
      "version",
      "outcome",
      "grant",
      "server_now_ms",
      "expires_at_ms",
    ]);
    if (answer.outcome !== "granted") invalidInitialInput();
    validateGrant(s.ctx, sourceDigest, answer.grant);
    const grant = answer.grant as PreparationGrant,
      gt = times(answer),
      rtt = performance.now() - issueStart;
    if (
      gt.now < grant.issued_at_ms || gt.expiry !== t.expiry ||
      grant.outcome_deadline_ms + 35000 > gt.expiry
    ) invalidInitialInput();
    const executionDeadline = Math.min(
      deadline,
      performance.now() + grant.execution_deadline_ms - gt.now - rtt,
    );
    if (
      stopped(signal) ||
      executionDeadline - performance.now() <= preparationWallMs(s.ctx)
    ) return { kind: "recovery_needed", reason: "issued_without_runtime" };
    // The only runtime invocation site. No reusable grant/capability leaves scope.
    // No await occurs between final cancellation check and consuming authority.
    const runtimeDeadline = Math.min(
      executionDeadline,
      performance.now() + preparationWallMs(s.ctx),
    );
    const supplied = await knownPhase(
      signal,
      runtimeDeadline - performance.now(),
      (p) =>
        deps.runtime({
          read(i: number) {
            if (!Number.isInteger(i) || i < 0 || i >= sources.bytes.length) {
              invalidInitialInput();
            }
            return new Uint8Array(sources.bytes[i]);
          },
          profile: clone(s.ctx.profile),
        }, p),
    );
    if (performance.now() >= runtimeDeadline) {
      return { kind: "recovery_needed", reason: "late_runtime_output" };
    }
    if (!Array.isArray(supplied) || supplied.length !== sources.bytes.length) {
      invalidInitialInput();
    }
    // Snapshot the complete output synchronously before any asynchronous hash.
    const owned = supplied.map((v, i) => {
      const m = s.ctx.assignment.preparation.source_mapping[i];
      if (m.role === "raw_video") {
        if (v !== null) invalidInitialInput();
        return null;
      }
      if (v === null) invalidInitialInput();
      return checkedBytes(
        v,
        s.ctx.profile.spec.rules.find((r) => r.role === m.role)!.limits
          .output_bytes,
      );
    });
    const entries: PreparationOutputReceipt["entries"] = [];
    for (const [i, bytes] of owned.entries()) {
      const source = s.ctx.assignment.preparation.source_mapping[i].source;
      const tuple: PreparationTuple | null = bytes === null ? null : {
        byte_count: bytes.length,
        sha256: await hash(bytes),
        content_type: source.kind === "audio"
          ? "audio/wav"
          : source.source_content_type,
      };
      entries.push({
        ordinal: i,
        prepared: tuple === null ? null : {
          bytes: tuple,
          transform: source.transform,
          parameters: clone(source.transform_parameters),
          source_identity: equalBytes(bytes!, sources.bytes[i]),
        },
      });
    }
    const request: PreparationOutputReceipt = {
      ...identity(s.ctx),
      grant_id: grant.grant_id,
      source_digest: sourceDigest,
      entries,
    };
    validateOutputReceipt(s.ctx, grant, request);
    const known: KnownOutput = {
      scope: s,
      source: sources.receipt,
      grant,
      deadlines: {
        registration: Math.min(
          deadline,
          issueStart + grant.registration_deadline_ms - gt.now,
        ),
        outcome: Math.min(
          deadline,
          issueStart + grant.outcome_deadline_ms - gt.now,
        ),
      },
      request,
      bytes: owned,
      resolved: null,
      outcome: null,
    };
    if (stopped(signal, deadline)) return ticket(known);
    return await settleKnownOutput(deps, known, signal, true);
  } catch {
    return unknown();
  }
}
async function settleKnownOutput(
  deps: PreparationExecutionDependencies,
  k: KnownOutput,
  signal: AbortSignal,
  fresh = false,
): Promise<PreparationRunResult> {
  try {
    if (stopped(signal)) return ticket(k);
    let registrationDeadline = k.deadlines.registration;
    let outcomeDeadline = k.deadlines.outcome;
    // Fresh registration is the one RPC reserved in this phase. Its SQL owner
    // checks live ownership, terminal state, grant and exact original output.
    // Explicit reconciliation first reads committed proof; it cannot invoke
    // runtime or extend the original local/server grant deadlines.
    if (!fresh) {
      const start = performance.now();
      const status = await rpc(
        deps,
        "get_initial_preparation_execution_status",
        args(k.scope),
        signal,
      );
      const statusHeld = held(status);
      if (statusHeld) return statusHeld;
      object(status, [
        "version",
        "outcome",
        "phase",
        "source",
        "execution_reference",
        "output",
        "result",
        "server_now_ms",
        "expires_at_ms",
      ]);
      if (
        status.outcome !== "status" ||
        !sameExecutionValue(status.source, k.source) ||
        !sameExecutionValue(
          status.execution_reference,
          preparationReference(k.grant),
        )
      ) invalidInitialInput();
      const timing = times(status), rtt = performance.now() - start;
      registrationDeadline = Math.min(
        registrationDeadline,
        performance.now() +
          Math.min(timing.expiry, k.grant.registration_deadline_ms) -
          timing.now - rtt,
      );
      outcomeDeadline = Math.min(
        outcomeDeadline,
        performance.now() +
          Math.min(timing.expiry, k.grant.outcome_deadline_ms) - timing.now -
          rtt,
      );
      if (status.result !== null) {
        await validatePreparationOutcome(k.scope.ctx, status.result);
        const result = status.result as PreparationOutcome;
        if (!sameExecutionValue(result.output_manifest, k.request)) {
          invalidInitialInput();
        }
        return { kind: "outcome_ready", outcome: clone(result) };
      }
      if (status.output !== null) {
        const registered = object(status.output, ["request", "resolved"]);
        if (!sameExecutionValue(registered.request, k.request)) {
          invalidInitialInput();
        }
        await validateResolvedManifest(
          k.scope.ctx,
          k.request,
          registered.resolved,
        );
        if (
          k.resolved !== null &&
          !sameExecutionValue(k.resolved, registered.resolved)
        ) invalidInitialInput();
        k.resolved = clone(registered.resolved as PreparationResolvedManifest);
      } else if (k.resolved !== null) {
        // A missing previously committed proof is corruption, not permission to rebuild it.
        return { kind: "recovery_needed", reason: "registered_output_missing" };
      }
    }
    const outputDeadline = outcomeDeadline - 5000;
    if (stopped(signal)) return ticket(k);
    if (k.resolved === null) {
      const answer = await rpc(
          deps,
          "register_initial_preparation_output",
          {
            ...args(k.scope),
            p_manifest: initialCanonicalText(k.request),
          },
          signal,
          registrationDeadline,
        ),
        h = held(answer);
      if (h) return h;
      object(answer, ["version", "outcome", "request", "resolved"]);
      if (
        answer.outcome !== "registered" ||
        !sameExecutionValue(answer.request, k.request)
      ) invalidInitialInput();
      await validateResolvedManifest(k.scope.ctx, k.request, answer.resolved);
      // Preserve a positively known reply even when local cancellation just won.
      k.resolved = clone(answer.resolved as PreparationResolvedManifest);
    }
    if (stopped(signal)) return ticket(k);
    if (k.outcome === null) {
      await knownPhase(
        signal,
        Math.min(30000, outputDeadline - performance.now()),
        async (phase) => {
          for (const [i, bytes] of k.bytes.entries()) {
            if (bytes === null) continue;
            if (stopped(phase, outputDeadline)) {
              throw new Error("initial_preparation_stopped");
            }
            const objectId = k.resolved!.entries[i].object_id!;
            checkInitialDeadline(phase);
            const retained = checkedBytes(
              k.request.entries[i].prepared!.source_identity
                ? await deps.verifyExistingIdentityOutput(i, objectId, phase)
                : await deps.createFreshOutputAndReadBack(
                  i,
                  objectId,
                  new Uint8Array(bytes),
                  phase,
                ),
              bytes.length,
            );
            checkInitialDeadline(phase);
            if (stopped(phase, outputDeadline)) {
              throw new Error("initial_preparation_stopped");
            }
            if (!equalBytes(bytes, retained)) invalidInitialInput();
          }
        },
      );
      const outcome: PreparationOutcome = {
        ...identity(k.scope.ctx),
        grant: k.grant,
        source_verification: k.source,
        output_manifest: k.request,
        resolved_manifest: k.resolved,
        profile: k.scope.ctx.profile,
        retained: k.request.entries.flatMap((e, i) =>
          e.prepared === null ? [] : [{
            ordinal: i,
            object_id: k.resolved!.entries[i].object_id!,
            bytes: e.prepared.bytes,
          }]
        ),
      };
      await validatePreparationOutcome(k.scope.ctx, outcome);
      k.outcome = outcome;
    }
    if (stopped(signal)) return ticket(k);
    const answer = await rpc(
        deps,
        "settle_initial_preparation_outcome",
        {
          ...args(k.scope),
          p_outcome: initialCanonicalText(k.outcome),
        },
        signal,
        outcomeDeadline,
      ),
      h = held(answer);
    if (h) return h;
    object(answer, ["version", "outcome", "result", "digest"]);
    if (
      answer.outcome !== "outcome_ready" ||
      !sameExecutionValue(answer.result, k.outcome) ||
      answer.digest !==
        await executionDigest("outcome", initialCanonicalText(k.outcome))
    ) invalidInitialInput();
    return { kind: "outcome_ready", outcome: clone(k.outcome) };
  } catch {
    return ticket(k);
  }
}
/** Explicit reconciliation of exactly retained original output, never runtime.
 * Tokens are process-local; they are not durable persistence qualification. */
export async function reconcileInitialPreparationOutput(
  deps: PreparationExecutionDependencies,
  value: PreparationReconciliation,
  signal: AbortSignal,
): Promise<PreparationRunResult> {
  const known = reconciliations.get(value);
  if (!known) return { kind: "held", reason: "original_output_missing" };
  return await settleKnownOutput(deps, known, signal);
}
