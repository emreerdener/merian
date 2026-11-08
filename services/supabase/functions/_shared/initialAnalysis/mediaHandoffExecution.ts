/** Local qualification algorithm only. No installed signer, SQL transport,
 * grant, environment composition, provider or funding operation. */
import { initialCanonicalText } from "./canonical.ts";
import { validateInitialAdmissionRecoveryResponse } from "./admissionRecoveryResponse.ts";
import { type HandoffPhase } from "./handoffProfile.ts";
import { initialMediaUnavailable, mediaRecord } from "./mediaBinding.ts";
import {
  decodeHandoffIO,
  decodeHandoffState,
  type HandoffIdentity,
  handoffIdentity,
  type HandoffRows,
} from "./mediaHandoffRows.ts";
import {
  discardHandoffSource,
  type HandoffStorageDependencies,
  type HandoffVerifiedObject,
  readHandoffSource,
  retainHandoffDestination,
  verifyHandoffDestination,
} from "./mediaHandoffStorage.ts";
import {
  checkInitialDeadline,
  initialAbortable,
  initialDeadline,
} from "./transport.ts";

export const HANDOFF_SQL_MS = 5_000;
/** Each method is a separate, acknowledged READ COMMITTED transaction. The
 * local bridge also enforces server 5s statement/1s lock and process limits.
 * No method accepts caller-selected SQL, connection, routine or document. */
export interface HandoffBridge {
  readState(id: HandoffIdentity, signal: AbortSignal): Promise<unknown>;
  loadCopy(id: HandoffIdentity, signal: AbortSignal): Promise<unknown>;
  loadVerification(
    id: HandoffIdentity,
    claim: string,
    signal: AbortSignal,
  ): Promise<unknown>;
  beginCopy(id: HandoffIdentity, signal: AbortSignal): Promise<unknown>;
  recordObject(
    id: HandoffIdentity,
    object: string,
    signal: AbortSignal,
  ): Promise<unknown>;
  completeCopy(id: HandoffIdentity, signal: AbortSignal): Promise<unknown>;
  claimVerification(id: HandoffIdentity, signal: AbortSignal): Promise<unknown>;
  settleVerification(
    id: HandoffIdentity,
    claim: string,
    signal: AbortSignal,
  ): Promise<unknown>;
  transfer(
    id: HandoffIdentity,
    verification: string,
    signal: AbortSignal,
  ): Promise<unknown>;
}
export interface HandoffExecutionDependencies {
  bridge: HandoffBridge;
  storage: Omit<HandoffStorageDependencies, "beforeIO">;
  /** Trusted host attestation of resolved saved artifacts AND the executing
   * adapter. Digest echoing is not an implementation of this contract. Local
   * tests inject synthetic attestation; installed use remains unimplemented. */
  attest(rows: HandoffRows, signal: AbortSignal): Promise<{
    copy_adapter_digest: string;
    verification_adapter_digest: string;
    protocol_artifact_digest: string;
  }>;
}
export type HandoffExecutionResult =
  | { outcome: "transferred"; transferDigest: string }
  | { outcome: "unresolved"; recovered: HandoffRows | null };
type Deadlines = Readonly<Record<HandoffPhase, number>>;
const unavailable = initialMediaUnavailable;
function same(a: unknown, b: unknown): boolean {
  return initialCanonicalText(a) === initialCanonicalText(b);
}
function context(original: HandoffRows, next: HandoffRows): void {
  if (
    !same(original.original, next.original) ||
    !same(original.identity, next.identity) ||
    next.observedAtMs < original.observedAtMs
  ) throw unavailable();
}
async function bounded<T>(
  caller: AbortSignal,
  at: number,
  run: (signal: AbortSignal) => Promise<T>,
  limit = Infinity,
): Promise<T> {
  checkInitialDeadline(caller);
  const remaining = Math.min(at - performance.now(), limit);
  if (!(remaining > 0)) throw unavailable();
  return await initialDeadline(caller, remaining, async (signal) => {
    const value = await initialAbortable(signal, () => run(signal));
    checkInitialDeadline(signal);
    return value;
  });
}
async function state(
  bridge: HandoffBridge,
  id: HandoffIdentity,
  signal: AbortSignal,
): Promise<HandoffRows> {
  const raw = await initialAbortable(
    signal,
    () => bridge.readState(id, signal),
  );
  const result = await initialAbortable(
    signal,
    () => decodeHandoffState(raw, id),
  );
  checkInitialDeadline(signal);
  return result;
}
/** Historical status gets its own bounded read, never a fresh processing budget. */
export async function readOriginalHandoffStatus(
  bridge: HandoffBridge,
  requested: HandoffIdentity,
  caller: AbortSignal,
): Promise<HandoffRows | null> {
  try {
    const id = handoffIdentity(requested);
    return await bounded(
      caller,
      Infinity,
      (s) => state(bridge, id, s),
      HANDOFF_SQL_MS,
    );
  } catch {
    return null;
  }
}
class UnknownWrite extends Error {}

export async function executeOriginalMediaHandoff(
  deps: HandoffExecutionDependencies,
  requested: HandoffIdentity,
  caller: AbortSignal,
): Promise<HandoffExecutionResult> {
  let rows: HandoffRows | null = null;
  let deadlines: Deadlines | null = null;
  let identity: Readonly<HandoffIdentity>;
  try {
    identity = handoffIdentity(requested);
    const started = performance.now();
    rows = await bounded(
      caller,
      Infinity,
      (s) => state(deps.bridge, identity, s),
      HANDOFF_SQL_MS,
    );
    // Anchor at request START: this subtracts the whole read/decode roundtrip.
    // No subsequent server observation can move any of these deadlines.
    deadlines = Object.freeze(Object.fromEntries(
      Object.entries(rows.binding.phase_window.cutoffs).map((
        [phase, cutoff],
      ) => [phase, started + (cutoff - rows!.observedAtMs)]),
    )) as Deadlines;
    const original = rows;
    if (rows.transfer) {
      return { outcome: "transferred", transferDigest: rows.transfer.digest };
    }
    const phaseRun = <T>(
      phase: HandoffPhase,
      run: (s: AbortSignal) => Promise<T>,
      limit = Infinity,
    ) => bounded(caller, deadlines![phase], run, limit);
    const refresh = async (signal: AbortSignal) => {
      const next = await bounded(
        signal,
        deadlines!.reconciliation,
        (s) => state(deps.bridge, identity, s),
        HANDOFF_SQL_MS,
      );
      context(rows!, next);
      return next;
    };
    // Known writes still reload the original full chain before advancing. An
    // absent, malformed, late or lost acknowledgement allows one recovery only;
    // it never turns into a mutation retry within this attempt.
    const write = async (
      phase: HandoffPhase,
      field: "progress" | "claim" | "verification" | "transfer",
      call: (signal: AbortSignal) => Promise<unknown>,
    ) => {
      checkInitialDeadline(caller);
      if (deadlines![phase] - performance.now() < HANDOFF_SQL_MS) {
        throw unavailable();
      }
      let invoked = false;
      try {
        const ack = await phaseRun(phase, async (signal) => {
          const raw = await initialAbortable(signal, () => {
            invoked = true;
            return call(signal);
          });
          const envelope = mediaRecord(raw, ["response", field]);
          const text = initialCanonicalText(envelope);
          if (new TextEncoder().encode(text).length > 262144) {
            throw unavailable();
          }
          const snapshot = JSON.parse(text);
          const response = JSON.parse(
            await initialAbortable(
              signal,
              () => validateInitialAdmissionRecoveryResponse(snapshot.response),
            ),
          );
          if (
            response.outcome === "held" ||
            response.admission_receipt_digest !==
              identity.admission_receipt_digest ||
            !same(response.binding, original.binding) ||
            snapshot[field] === null
          ) throw unavailable();
          return snapshot;
        }, HANDOFF_SQL_MS);
        const next = await phaseRun(phase, refresh, HANDOFF_SQL_MS);
        const expected = field === "progress" ? next.progress : (() => {
          const doc = next[field];
          if (!doc) return null;
          return {
            owner_id: identity.owner_id,
            scan_id: identity.scan_id,
            [field === "claim" ? "claim" : "receipt"]: doc.canonical,
            [field === "claim" ? "claim_digest" : "receipt_digest"]: doc.digest,
          };
        })();
        if (!same(ack[field], expected)) throw unavailable();
        rows = next;
      } catch {
        if (invoked) throw new UnknownWrite();
        throw unavailable();
      }
    };
    const attest = async (phase: "copy" | "verification") => {
      await phaseRun(phase, async (signal) => {
        const result = await initialAbortable(
          signal,
          () => deps.attest(original, signal),
        );
        const a = mediaRecord(result, [
          "copy_adapter_digest",
          "verification_adapter_digest",
          "protocol_artifact_digest",
        ]);
        if (
          a.copy_adapter_digest !== original.handoff.copy_adapter_digest ||
          a.verification_adapter_digest !==
            original.handoff.verification_adapter_digest ||
          a.protocol_artifact_digest !==
            original.handoff.protocol_artifact_digest
        ) throw unavailable();
      });
    };
    const load = async (
      phase: "copy" | "verification",
      signal: AbortSignal,
    ) => {
      const saved = rows!;
      const token = saved.claim?.value.claim_token ?? null;
      const raw = await bounded(
        signal,
        deadlines![phase],
        (s) =>
          phase === "copy"
            ? deps.bridge.loadCopy(identity, s)
            : deps.bridge.loadVerification(identity, token!, s),
        HANDOFF_SQL_MS,
      );
      const io = await initialAbortable(
        signal,
        () => decodeHandoffIO(raw, identity, phase, token),
      );
      checkInitialDeadline(signal);
      context(saved, io.rows);
      if (
        !same(saved.progress, io.rows.progress) ||
        !same(saved.claim, io.rows.claim)
      ) throw unavailable();
      return io;
    };
    const storage = (
      phase: "copy" | "verification",
      io: Awaited<ReturnType<typeof load>>,
    ): HandoffStorageDependencies => ({
      sign: deps.storage.sign.bind(deps.storage),
      fetch: deps.storage.fetch.bind(deps.storage),
      beforeIO: async (signal) => {
        const next = await load(phase, signal);
        if (
          !same(io.sourceBackend, next.sourceBackend) ||
          !same(io.destinationBackend, next.destinationBackend)
        ) throw unavailable();
      },
    });
    if (!rows.progress?.completed_at_ms) {
      await attest("copy");
      const afterArtifact = await phaseRun("copy", refresh, HANDOFF_SQL_MS);
      if (
        !same(rows.progress, afterArtifact.progress) ||
        !same(rows.claim, afterArtifact.claim) ||
        !same(rows.verification, afterArtifact.verification) ||
        !same(rows.transfer, afterArtifact.transfer)
      ) throw unavailable();
      rows = afterArtifact;
      if (!rows.progress) {
        await write(
          "copy",
          "progress",
          (s) => deps.bridge.beginCopy(identity, s),
        );
      }
      const settled = new Set(
        (JSON.parse(rows.progress!.completed_objects) as {
          object_id: string;
        }[]).map((o) => o.object_id),
      );
      for (
        const destination of [...original.mapping.objects].sort((a, b) =>
          a.object_id.localeCompare(b.object_id)
        )
      ) {
        if (settled.has(destination.object_id)) continue;
        await phaseRun("copy", async (signal) => {
          const io = await load("copy", signal),
            transport = storage("copy", io);
          const aliases = original.mapping.items.flatMap((
            item,
          ) => [item.source, ...(item.prepared ? [item.prepared] : [])])
            .filter((role) =>
              role.destination_object_id === destination.object_id
            );
          if (!aliases.length) throw unavailable();
          let token: HandoffVerifiedObject | null = null;
          try {
            for (const role of aliases) {
              if (token) {
                discardHandoffSource(token);
                token = null;
              }
              token = await readHandoffSource(
                transport,
                io.sourceBackend,
                identity.scan_id,
                { object_id: role.original_object_id, ...role.bytes },
                signal,
              );
              checkInitialDeadline(signal);
            }
            await retainHandoffDestination(
              transport,
              io.destinationBackend,
              identity.scan_id,
              { object_id: destination.object_id, ...destination.bytes },
              token!,
              signal,
            );
            checkInitialDeadline(signal);
          } finally {
            if (token) discardHandoffSource(token);
          }
        });
        await write(
          "copy",
          "progress",
          (s) => deps.bridge.recordObject(identity, destination.object_id, s),
        );
      }
      await write(
        "copy",
        "progress",
        (s) => deps.bridge.completeCopy(identity, s),
      );
    }
    if (!rows.claim) {
      await write(
        "verification_claim",
        "claim",
        (s) => deps.bridge.claimVerification(identity, s),
      );
    }
    if (!rows.verification) {
      await attest("verification");
      await phaseRun("verification", async (signal) => {
        const io = await load("verification", signal),
          transport = storage("verification", io);
        for (
          const destination of [...original.mapping.objects].sort((a, b) =>
            a.object_id.localeCompare(b.object_id)
          )
        ) {
          await verifyHandoffDestination(
            transport,
            io.destinationBackend,
            identity.scan_id,
            { object_id: destination.object_id, ...destination.bytes },
            signal,
          );
          checkInitialDeadline(signal);
        }
      });
      await write(
        "verification_settlement",
        "verification",
        (s) =>
          deps.bridge.settleVerification(
            identity,
            rows!.claim!.value.claim_token,
            s,
          ),
      );
    }
    await write(
      "transfer",
      "transfer",
      (s) => deps.bridge.transfer(identity, rows!.verification!.digest, s),
    );
    const transferred = (rows as HandoffRows).transfer;
    if (!transferred) throw unavailable();
    return { outcome: "transferred", transferDigest: transferred.digest };
  } catch (error) {
    if (error instanceof UnknownWrite && deadlines && rows && !caller.aborted) {
      try {
        const recovered = await bounded(
          caller,
          deadlines.reconciliation,
          (s) => state(deps.bridge, rows!.identity, s),
          HANDOFF_SQL_MS,
        );
        context(rows, recovered);
        return { outcome: "unresolved", recovered };
      } catch { /* Recovery does not authorize another mutation. */ }
    }
    return { outcome: "unresolved", recovered: null };
  }
}
