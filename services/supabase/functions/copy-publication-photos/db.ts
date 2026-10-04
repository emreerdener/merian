import type { SupabaseClient } from "@supabase/supabase-js";
import {
  exactObject,
  HistoryError,
  historyUUID,
  invalidHistory,
} from "../_shared/analysisHistory/contract.ts";
import { validatePublicationCopySource } from "../_shared/analysisHistory/photoCopyExecution.ts";
import { erasePublicationPhoto } from "../_shared/analysisHistory/photoErasure.ts";
import { executePublicationCopyOperation } from "../_shared/analysisHistory/publicationCopyOperation.ts";
import { publicationAbortable } from "../_shared/analysisHistory/publicationDeadline.ts";
import { PublicHistoryPhotoStorage } from "../_shared/analysisHistory/publicPhotoStorage.ts";
import type { CopyClaim, CopyHint, CopyWorkerDependencies } from "./handler.ts";

export function publicationCopyWorkerRepository(
  client: SupabaseClient,
  storage = new PublicHistoryPhotoStorage(),
): CopyWorkerDependencies {
  async function rpc(
    name: string,
    args: Record<string, unknown>,
    caller: AbortSignal,
  ): Promise<unknown> {
    const signal = AbortSignal.any([caller, AbortSignal.timeout(12_000)]);
    try {
      const { data, error } = await publicationAbortable(
        signal,
        () => client.rpc(name, args).abortSignal(signal),
      );
      if (error) throw error;
      return data;
    } catch {
      throw new HistoryError("analysis_history_unavailable");
    }
  }
  function hint(value: unknown): Readonly<CopyHint> {
    const row = exactObject(value, [
      "owner_id",
      "observation_id",
      "operation_id",
    ]);
    return Object.freeze({
      owner_id: historyUUID(row.owner_id),
      observation_id: historyUUID(row.observation_id),
      operation_id: historyUUID(row.operation_id),
    });
  }
  const args = (h: CopyHint) => ({
    p_owner: h.owner_id,
    p_observation: h.observation_id,
    p_operation: h.operation_id,
  });
  const workArgs = (w: CopyClaim) => ({
    ...args(w.scope),
    p_work: w.scope.work_token,
  });
  const erasure = {
    claim: (id: string | null, signal: AbortSignal) => {
      if (id === null) return invalidHistory(); // This owner never claims unrelated cleanup.
      return rpc("claim_publication_photo_erasure", {
        p_object: historyUUID(id),
      }, signal);
    },
    erase: (id: string, signal: AbortSignal) =>
      publicationAbortable(signal, () => storage.erase(id, signal)),
    finish: async (
      id: string,
      token: string,
      success: boolean,
      signal: AbortSignal,
    ) => {
      const data = await rpc("finish_publication_photo_erasure", {
        p_object: historyUUID(id),
        p_claim: historyUUID(token),
        p_success: success,
      }, signal);
      if (typeof data !== "boolean") return invalidHistory();
      return data;
    },
  };
  return {
    async list(signal) {
      const rows = await rpc("list_publication_copy_work", {}, signal);
      if (!Array.isArray(rows) || rows.length > 10) return invalidHistory();
      return Object.freeze(rows.map(hint));
    },
    async claim(input, signal) {
      const h = hint(input); // Snapshot before suspension/account changes.
      const data = await rpc("claim_publication_copy_work", args(h), signal);
      if (
        data && typeof data === "object" && "claimed" in data &&
        data.claimed === false
      ) {
        exactObject(data, ["claimed"]);
        return null;
      }
      const row = exactObject(data, [
        "claimed",
        "owner_id",
        "observation_id",
        "operation_id",
        "work_token",
        "work_expires_at",
        "cohort",
      ]);
      if (
        row.claimed !== true || row.owner_id !== h.owner_id ||
        row.observation_id !== h.observation_id ||
        row.operation_id !== h.operation_id ||
        typeof row.work_expires_at !== "string" ||
        row.work_expires_at.length > 40 ||
        !Number.isFinite(Date.parse(row.work_expires_at)) ||
        Date.parse(row.work_expires_at) <= Date.now() ||
        !Array.isArray(row.cohort) || row.cohort.length < 1 ||
        row.cohort.length > 6
      ) return invalidHistory();
      const cohort = Object.freeze(row.cohort.map((value) => {
        const m = exactObject(value, ["attempt_id", "source"]);
        return Object.freeze({
          attempt_id: historyUUID(m.attempt_id),
          source: validatePublicationCopySource(m.source),
        });
      }));
      for (
        const ids of [
          cohort.map((m) => m.attempt_id),
          cohort.map((m) => m.source.media_id),
          cohort.map((m) => m.source.object_id),
        ]
      ) if (new Set(ids).size !== ids.length) invalidHistory();
      if (
        cohort.reduce((sum, m) => sum + m.source.byte_count, 0) >
          32 * 1024 * 1024
      ) invalidHistory();
      return Object.freeze({
        scope: Object.freeze({ ...h, work_token: historyUUID(row.work_token) }),
        cohort,
        work_expires_at: row.work_expires_at,
      });
    },
    async finalize(work, signal) {
      const data = await rpc(
        "finalize_publication_copy_work",
        workArgs(work),
        signal,
      );
      if (
        data && typeof data === "object" && "finalized" in data &&
        data.finalized === false
      ) {
        exactObject(data, ["finalized"]);
        return { status: "pending" };
      }
      const row = exactObject(data, [
        "finalized",
        "status",
        "reason",
        "object_ids",
      ]);
      if (
        row.finalized !== true || !Array.isArray(row.object_ids) ||
        row.object_ids.length > 6
      ) return invalidHistory();
      const targets = Object.freeze(row.object_ids.map(historyUUID));
      if (new Set(targets).size !== targets.length) invalidHistory();
      if (row.status === "admitted" && row.reason === null && !targets.length) {
        return { status: "admitted" };
      }
      if (
        row.status !== "needs_action" ||
        !((row.reason === "note_requires_text_moderation" && !targets.length) ||
          (row.reason === "staging_expired" && targets.length >= 1))
      ) return invalidHistory();
      return { status: "needs_action", targets };
    },
    execute: (work, signal) =>
      executePublicationCopyOperation(
        client,
        work.scope,
        work.cohort,
        work.work_expires_at,
        { erasure, storage, signal },
      ),
    async cleanup(targets, signal) {
      // Only finalizer-returned original targets reach this dedicated coordinator.
      for (const id of targets) {
        signal.throwIfAborted();
        try {
          await erasePublicationPhoto({
            claim: (target) => erasure.claim(target, signal),
            erase: (target) => erasure.erase(target, signal),
            finish: (target, token, success) =>
              erasure.finish(target, token, success, signal),
          }, id);
        } catch {
          /* Permanent registry retains unfinished cleanup obligations. */
        }
      }
    },
    async release(work, signal) {
      await rpc("release_publication_copy_work", workArgs(work), signal);
    },
  };
}
