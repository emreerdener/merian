import type { SupabaseClient } from "@supabase/supabase-js";
import {
  exactObject,
  HistoryError,
  historyUUID,
  invalidHistory,
} from "./contract.ts";
import type { PublicationPhotoSource } from "./photoClassifier.ts";
import {
  type PhotoCopyLease,
  type PhotoCopyScope,
  validatePublicationCopyReceipt,
  validatePublicationCopySource,
} from "./photoCopyExecution.ts";
import { publicationAbortable } from "./publicationDeadline.ts";

export interface PublicationCopyWorkScope {
  owner_id: string;
  observation_id: string;
  operation_id: string;
  work_token: string;
}
export interface ApprovedCopyMember {
  attempt_id: string;
  source: Readonly<PublicationPhotoSource>;
}
export interface ReservedCopy extends PhotoCopyLease {
  readonly source: Readonly<PublicationPhotoSource>;
  readonly expires_at: string;
  readonly ready_at: string | null;
}
export interface ReservedCopyCohort {
  readonly expires_at: string;
  readonly copies: readonly ReservedCopy[];
}
/** Service-private repository. Recovery is not permission to write. The caller
 * still owns verified container preflight, bounded storage I/O and registry
 * erasure claims. No provider dispatch, binder or transport retry is supplied. */
export function publicationCopyRepository(
  client: SupabaseClient,
  identity: PublicationCopyWorkScope,
  inputs: readonly ApprovedCopyMember[],
  deadline: AbortSignal,
) {
  const scope = Object.freeze({
    p_owner: historyUUID(identity.owner_id),
    p_observation: historyUUID(identity.observation_id),
    p_operation: historyUUID(identity.operation_id),
    p_work: historyUUID(identity.work_token),
  });
  const ownerScope = Object.freeze({
    p_owner: scope.p_owner,
    p_observation: scope.p_observation,
    p_operation: scope.p_operation,
  });
  if (inputs.length < 1 || inputs.length > 6) invalidHistory();
  const members = Object.freeze(inputs.map((input) => {
    exactObject(input, ["attempt_id", "source"]);
    return Object.freeze({
      attempt_id: historyUUID(input.attempt_id),
      source: validatePublicationCopySource(input.source),
    });
  }));
  for (
    const values of [
      members.map((m) => m.attempt_id),
      members.map((m) => m.source.media_id),
      members.map((m) => m.source.object_id),
    ]
  ) {
    if (new Set(values).size !== members.length) invalidHistory();
  }
  if (
    members.reduce((sum, m) => sum + m.source.byte_count, 0) > 32 * 1024 * 1024
  ) invalidHistory();
  const privateIDs = new Set([
    scope.p_owner,
    scope.p_observation,
    scope.p_operation,
    ...members.flatMap((
      m,
    ) => [m.attempt_id, m.source.media_id, m.source.object_id]),
  ]);
  let original: ReservedCopyCohort | null = null;
  let authorized: ReservedCopyCohort | null = null;
  async function rpc(
    name: string,
    args: Record<string, unknown>,
    caller?: AbortSignal,
  ) {
    const signal = AbortSignal.any([
      deadline,
      AbortSignal.timeout(12_000),
      ...(caller ? [caller] : []),
    ]);
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
  function checked<T>(parse: () => T): T {
    try {
      return parse();
    } catch {
      throw new HistoryError("analysis_history_unavailable");
    }
  }
  function copy(
    value: unknown,
    member: Readonly<ApprovedCopyMember>,
  ): ReservedCopy {
    const identity: PhotoCopyScope = {
      owner_id: scope.p_owner,
      observation_id: scope.p_observation,
      attempt_id: member.attempt_id,
    };
    const parsed = validatePublicationCopyReceipt(
      value,
      identity,
      member.source,
    );
    if (
      privateIDs.has(parsed.lease.object_id) || parsed.expires_at.length > 40 ||
      (parsed.ready_at !== null && parsed.ready_at.length > 40)
    ) invalidHistory();
    return Object.freeze({
      ...parsed.lease,
      source: member.source,
      expires_at: parsed.expires_at,
      ready_at: parsed.ready_at,
    });
  }
  function reservation(value: unknown): ReservedCopyCohort {
    const row = exactObject(value, ["expires_at", "copies"]);
    if (
      typeof row.expires_at !== "string" || row.expires_at.length > 40 ||
      !Number.isFinite(Date.parse(row.expires_at)) ||
      !Array.isArray(row.copies) || row.copies.length !== members.length
    ) invalidHistory();
    const copies = Object.freeze(row.copies.map((v, i) => copy(v, members[i])));
    if (
      copies.some((c) => c.expires_at !== row.expires_at) ||
      new Set(copies.map((c) => c.object_id)).size !== copies.length
    ) invalidHistory();
    return Object.freeze({ expires_at: row.expires_at, copies });
  }
  function publication(value: unknown) {
    const row = exactObject(value, [
      "schema_version",
      "operation_id",
      "observation_id",
      "analysis_id",
      "request_id",
      "post_id",
      "status",
    ]);
    if (
      row.schema_version !== 1 || row.operation_id !== scope.p_operation ||
      row.observation_id !== scope.p_observation || row.status !== "admitted"
    ) invalidHistory();
    return Object.freeze({
      schema_version: 1 as const,
      operation_id: scope.p_operation,
      observation_id: scope.p_observation,
      analysis_id: historyUUID(row.analysis_id),
      request_id: historyUUID(row.request_id),
      post_id: historyUUID(row.post_id),
      status: "admitted" as const,
    });
  }
  function pin(next: ReservedCopyCohort | null) {
    if (
      original &&
      (!next || next.expires_at !== original.expires_at ||
        next.copies.some((c, i) =>
          c.object_id !== original!.copies[i].object_id ||
          c.lease_token !== original!.copies[i].lease_token
        ))
    ) throw new HistoryError("analysis_history_unavailable");
    if (next) original = next;
    return next;
  }
  async function read() {
    const data = await rpc("read_publication_copy_cohort", ownerScope);
    return checked(() => {
      const row = exactObject(data, ["reservation", "publication"]);
      const saved = row.reservation === null
        ? null
        : reservation(row.reservation);
      const published = row.publication === null
        ? null
        : publication(row.publication);
      return Object.freeze({ reservation: pin(saved), publication: published });
    });
  }
  async function reserve() {
    const data = await rpc("reserve_publication_copy_cohort", scope);
    const next = checked(() => reservation(data));
    pin(next);
    authorized = next;
    return next;
  }
  async function abandon(): Promise<readonly string[] | null> {
    // Never turn a lost successful binding reply into erasure. SQL repeats this
    // check atomically with cleanup eligibility in case another worker binds now.
    const recovered = await read();
    if (recovered.publication || !recovered.reservation) return null;
    const data = await rpc("abandon_publication_copy_cohort", scope);
    return checked(() => {
      const row = exactObject(
        data,
        data && typeof data === "object" && "abandoned" in data &&
          data.abandoned === false
          ? ["abandoned"]
          : ["abandoned", "object_ids"],
      );
      if (row.abandoned === false) return null;
      if (row.abandoned !== true || !Array.isArray(row.object_ids)) {
        invalidHistory();
      }
      const ids = row.object_ids.map(historyUUID).sort();
      const expected = recovered.reservation!.copies.map((c) => c.object_id)
        .sort();
      if (
        ids.length !== expected.length ||
        ids.some((id, i) => id !== expected[i])
      ) invalidHistory();
      return Object.freeze(ids);
    });
  }
  async function bind(signal?: AbortSignal) {
    // SQL owns both fresh authority and historical success after work retirement.
    const result = await rpc("bind_publication_copy_cohort", scope, signal);
    return checked(() => publication(result));
  }
  async function cleanupTargets(): Promise<readonly string[]> {
    try {
      return await abandon() ?? [];
    } catch {
      // Only validated original reservation IDs survive loss of private state.
      return Object.freeze(original?.copies.map((c) => c.object_id) ?? []);
    }
  }
  function forPhoto(attempt: string) {
    const member = members.find((m) => m.attempt_id === historyUUID(attempt));
    if (!member) return invalidHistory();
    function assertScope(input: PhotoCopyScope) {
      if (
        input.owner_id !== scope.p_owner ||
        input.observation_id !== scope.p_observation ||
        input.attempt_id !== member!.attempt_id
      ) invalidHistory();
    }
    function assertLease(input: PhotoCopyLease) {
      assertScope(input);
      const saved = authorized?.copies.find((c) =>
        c.attempt_id === member!.attempt_id
      );
      if (
        !saved || input.object_id !== saved.object_id ||
        input.lease_token !== saved.lease_token
      ) return invalidHistory();
      return saved;
    }
    return Object.freeze({
      scope: Object.freeze({
        owner_id: scope.p_owner,
        observation_id: scope.p_observation,
        attempt_id: member.attempt_id,
      }),
      source: member.source,
      async reserve(input: PhotoCopyScope) {
        assertScope(input);
        // Refresh authorization for the whole cohort before each member's I/O.
        return (await reserve()).copies.find((c) =>
          c.attempt_id === member.attempt_id
        )!;
      },
      async complete(input: PhotoCopyLease, signal: AbortSignal) {
        const saved = assertLease(input);
        const data = await rpc("complete_publication_copy_cohort_photo", {
          ...scope,
          p_attempt: saved.attempt_id,
          p_object: saved.object_id,
          p_lease: saved.lease_token,
        }, signal);
        const ready = checked(() => copy(data, member));
        if (
          ready.object_id !== saved.object_id ||
          ready.lease_token !== saved.lease_token ||
          ready.expires_at !== saved.expires_at || ready.ready_at === null
        ) throw new HistoryError("analysis_history_unavailable");
        return ready;
      },
      async cleanupTargets(input: PhotoCopyLease): Promise<readonly string[]> {
        assertLease(input);
        return await cleanupTargets();
      },
    });
  }
  return Object.freeze({
    read,
    reserve,
    abandon,
    bind,
    cleanupTargets,
    forPhoto,
  });
}
