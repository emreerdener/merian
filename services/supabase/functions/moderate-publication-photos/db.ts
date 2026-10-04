import type { SupabaseClient } from "@supabase/supabase-js";
import {
  exactObject,
  HistoryError,
  historyUUID,
  invalidHistory,
} from "../_shared/analysisHistory/contract.ts";
import { publicationAbortable } from "../_shared/analysisHistory/publicationDeadline.ts";
import { parsePublicationOperationRequest } from "../_shared/analysisHistory/publicationOperation.ts";
import { publicationModerationRepository } from "../_shared/analysisHistory/publicationModerationRepository.ts";
import type {
  PublicationHint,
  PublicationModerationDependencies,
} from "./handler.ts";

export function publicationModerationWorkerRepository(
  client: SupabaseClient,
): PublicationModerationDependencies {
  async function rpc(
    name: string,
    args: Record<string, unknown>,
    caller: AbortSignal,
  ) {
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
  function hint(value: unknown): PublicationHint {
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
  const args = (h: PublicationHint) => ({
    p_owner: h.owner_id,
    p_observation: h.observation_id,
    p_operation: h.operation_id,
  });
  return {
    async list(signal) {
      const rows = await rpc("list_observation_publication_work", {}, signal);
      if (!Array.isArray(rows) || rows.length > 10) return invalidHistory();
      return Object.freeze(rows.map(hint));
    },
    async claim(h, signal) {
      const data = await rpc(
        "claim_observation_publication_work",
        args(h),
        signal,
      );
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
        "request",
        "sources",
        "ip_hash",
      ]);
      const request = parsePublicationOperationRequest(row.request);
      if (
        row.claimed !== true || row.owner_id !== h.owner_id ||
        row.observation_id !== h.observation_id ||
        row.operation_id !== h.operation_id ||
        request.operation_id !== h.operation_id ||
        request.observation_id !== h.observation_id ||
        typeof row.work_expires_at !== "string" ||
        row.work_expires_at.length > 40 ||
        !Number.isFinite(Date.parse(row.work_expires_at)) ||
        typeof row.ip_hash !== "string" ||
        !/^[0-9a-f]{64}$/.test(row.ip_hash) || !Array.isArray(row.sources) ||
        row.sources.length !== request.media_ids.length
      ) return invalidHistory();
      const sources = Object.freeze(row.sources.map((value, i) => {
        const s = exactObject(value, [
          "media_id",
          "object_id",
          "byte_count",
          "content_type",
          "sha256",
        ]);
        if (
          s.media_id !== request.media_ids[i] ||
          typeof s.content_type !== "string" ||
          typeof s.byte_count !== "number" || typeof s.sha256 !== "string"
        ) return invalidHistory();
        return Object.freeze({
          media_id: historyUUID(s.media_id),
          object_id: historyUUID(s.object_id),
          content_type: s.content_type,
          byte_count: s.byte_count,
          sha256: s.sha256,
        });
      }));
      // Original IP is validated then dropped. Scoped SQL admission, not this
      // worker or caller, retrieves it for provider quota.
      return Object.freeze({
        scope: Object.freeze({ ...h, work_token: historyUUID(row.work_token) }),
        sources,
      });
    },
    async release(work, signal) {
      await rpc("release_observation_publication_work", {
        ...args(work.scope),
        p_work: work.scope.work_token,
      }, signal);
    },
    repository: (work, deadlines) =>
      publicationModerationRepository(
        client,
        work.scope,
        work.sources,
        deadlines,
      ),
  };
}
