import { publicHttpError } from "../_shared/http.ts";

export const GROUPS = [
  "plants",
  "birds",
  "insects",
  "fungi",
  "mammals",
  "reptiles_amphibians",
] as const;
export const MEDIA = ["image", "video", "audio"] as const;
export type SearchGroup = typeof GROUPS[number];
export type SearchMedia = typeof MEDIA[number];
export type ResultKind = "species" | "sightings";
export interface SearchContext {
  query: string;
  group: SearchGroup | null;
  media: SearchMedia | null;
  mode: "name" | "description";
}
export interface SearchCursor {
  id: string;
  rank: number | null;
  shared_at: string | null;
}
export interface SearchRequest {
  request_id: string;
  question: string | null;
  context: SearchContext | null;
  result_kind: ResultKind;
  cursor: SearchCursor | null;
}
export interface Interpretation {
  status: "results" | "clarification" | "unsupported";
  context: SearchContext;
  message: string;
}
export const UUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export function object(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw publicHttpError(400, "Invalid search request.");
  }
  return value as Record<string, unknown>;
}
function text(value: unknown, max: number, empty = false): string {
  if (
    typeof value !== "string" || value.length > max ||
    (!empty && !value.trim()) ||
    Array.from(value).some((character) => {
      const code = character.codePointAt(0)!;
      return code < 32 && code !== 9 && code !== 10 && code !== 13;
    })
  ) throw publicHttpError(400, "Invalid search text.");
  return value.trim();
}
function nullableEnum<T extends string>(
  value: unknown,
  allowed: readonly T[],
): T | null {
  if (value == null) return null;
  if (typeof value !== "string" || !allowed.includes(value as T)) {
    throw publicHttpError(400, "Unsupported search filter.");
  }
  return value as T;
}
export function parseContext(value: unknown): SearchContext {
  const row = object(value);
  if (row.mode !== "name" && row.mode !== "description") {
    throw publicHttpError(400, "Invalid search mode.");
  }
  const query = text(row.query, 240, true);
  const group = nullableEnum(row.group, GROUPS);
  const media = nullableEnum(row.media, MEDIA);
  if (!query && !group) {
    throw publicHttpError(400, "Describe a species or choose a group.");
  }
  return { query, group, media, mode: row.mode };
}
export function parseSearchRequest(value: unknown): SearchRequest {
  const row = object(value);
  const request_id = text(row.request_id, 36).toLowerCase();
  if (!UUID.test(request_id)) {
    throw publicHttpError(400, "Invalid search identity.");
  }
  const question = row.question == null ? null : text(row.question, 600);
  const context = row.context == null ? null : parseContext(row.context);
  if (!question && !context) throw publicHttpError(400, "Enter a search.");
  const result_kind = row.result_kind;
  if (result_kind !== "species" && result_kind !== "sightings") {
    throw publicHttpError(400, "Invalid result type.");
  }
  let cursor: SearchCursor | null = null;
  if (row.cursor != null) {
    const raw = object(row.cursor);
    if (question || typeof raw.id !== "string" || !UUID.test(raw.id)) {
      throw publicHttpError(400, "Invalid search cursor.");
    }
    if (result_kind === "species") {
      if (
        typeof raw.rank !== "number" || !Number.isFinite(raw.rank) ||
        raw.rank < 0 || raw.rank > 10 || raw.shared_at != null
      ) throw publicHttpError(400, "Invalid species cursor.");
      cursor = { id: raw.id, rank: raw.rank, shared_at: null };
    } else {
      if (
        typeof raw.shared_at !== "string" || raw.shared_at.length > 40 ||
        !Number.isFinite(Date.parse(raw.shared_at)) || raw.rank != null
      ) throw publicHttpError(400, "Invalid sightings cursor.");
      cursor = { id: raw.id, rank: null, shared_at: raw.shared_at };
    }
  }
  return { request_id, question, context, result_kind, cursor };
}
export function parseInterpretation(value: unknown): Interpretation {
  const row = object(value);
  if (
    !["results", "clarification", "unsupported"].includes(String(row.status))
  ) throw new Error("Invalid search interpretation");
  return {
    status: row.status as Interpretation["status"],
    context: parseContext(row.context),
    message: text(row.message, 300),
  };
}
