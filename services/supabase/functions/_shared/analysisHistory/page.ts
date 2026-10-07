import {
  exactObject,
  HISTORY_PAGE_SIZE,
  type HistoryPageRequest,
  historyRevision,
  historyUUID,
  invalidHistory,
  parseHistoryPageRequest,
} from "./contract.ts";
import { decodeAnalysisResultSnapshot } from "./result.ts";

export const HISTORY_MAX_PAGE_BYTES = 4_194_304;

/** The owner is supplied by verified server auth, never by a request body. */
export function parseHistoryPage(
  value: unknown,
  request: HistoryPageRequest,
  ownerID: string,
  reader: 7 | 8 | 9 | 10 = 7,
) {
  if (reader !== 7 && reader !== 8 && reader !== 9 && reader !== 10) {
    return invalidHistory();
  }
  const expected = parseHistoryPageRequest(request);
  historyUUID(ownerID);
  if (
    new TextEncoder().encode(JSON.stringify(value)).length >
      HISTORY_MAX_PAGE_BYTES
  ) return invalidHistory();
  const page = exactObject(value, [
    "schema_version",
    "owner_id",
    "observation_id",
    "state_revision",
    "items",
    "next_before_ordinal",
  ]);
  if (
    page.schema_version !== 1 || page.owner_id !== ownerID ||
    page.observation_id !== expected.observation_id ||
    !Array.isArray(page.items) ||
    page.items.length > Math.min(expected.limit, HISTORY_PAGE_SIZE)
  ) return invalidHistory();
  const seen = new Set<string>();
  let previous = expected.before_ordinal ?? 2_147_483_647;
  const items = page.items.map((value) => {
    const item = exactObject(value, ["ordinal", "snapshot"]);
    const ordinal = historyRevision(item.ordinal);
    const snapshot = decodeAnalysisResultSnapshot(item.snapshot, reader);
    if (
      ordinal !== snapshot.ordinal || ordinal < 1 || ordinal >= previous ||
      snapshot.observation_id !== expected.observation_id ||
      seen.has(snapshot.analysis_id)
    ) return invalidHistory();
    seen.add(snapshot.analysis_id);
    previous = ordinal;
    return { ordinal, snapshot: item.snapshot as string };
  });
  const next = page.next_before_ordinal === null
    ? null
    : historyRevision(page.next_before_ordinal);
  if (next !== null && (items.length === 0 || next !== previous || next <= 1)) {
    return invalidHistory();
  }
  return Object.freeze({
    schema_version: 1,
    owner_id: ownerID,
    observation_id: expected.observation_id,
    state_revision: historyRevision(page.state_revision),
    items,
    next_before_ordinal: next,
  });
}
