import {
  CORPUS_VERSION,
  type EvaluationCorpus,
  type EvaluationInput,
  INPUT_GROUPS,
  OUTCOMES,
  type Prediction,
  RANKS,
} from "./contracts.ts";

export type ContractErrorCode =
  | "invalid_shape"
  | "unsupported_version"
  | "invalid_media"
  | "unapproved_evidence"
  | "invalid_reference"
  | "duplicate_case"
  | "duplicate_group"
  | "split_leakage"
  | "duplicate_evidence"
  | "invalid_prediction"
  | "unknown_case"
  | "duplicate_prediction";

/** Fixed codes only: malformed records must not leak input through errors. */
export class EvaluationContractError extends Error {
  constructor(readonly code: ContractErrorCode) {
    super(code);
    this.name = "EvaluationContractError";
  }
}
export function requireCondition(
  condition: unknown,
  code: ContractErrorCode = "invalid_shape",
): asserts condition {
  if (!condition) throw new EvaluationContractError(code);
}
function record(value: unknown): Record<string, unknown> {
  requireCondition(
    value !== null && typeof value === "object" && !Array.isArray(value),
  );
  requireCondition(
    Object.getPrototypeOf(value) === Object.prototype ||
      Object.getPrototypeOf(value) === null,
  );
  return value as Record<string, unknown>;
}
export function fields(
  value: unknown,
  names: readonly string[],
): Record<string, unknown> {
  const object = record(value);
  requireCondition(
    Object.keys(object).length === names.length &&
      names.every((name) => Object.hasOwn(object, name)),
  );
  return object;
}
export function array(value: unknown, min: number, max: number): unknown[] {
  requireCondition(
    Array.isArray(value) && value.length >= min && value.length <= max,
  );
  requireCondition(Object.keys(value).length === value.length);
  for (let i = 0; i < value.length; i++) {
    requireCondition(Object.hasOwn(value, i));
  }
  return value;
}
export function text(value: unknown, max = 2000): asserts value is string {
  requireCondition(
    typeof value === "string" && value.length > 0 && value.length <= max &&
      value.trim() === value,
  );
  for (const character of value) {
    const code = character.charCodeAt(0);
    requireCondition(
      (code >= 32 && code !== 127) || code === 9 || code === 10 || code === 13,
    );
  }
}
export function token(value: unknown): asserts value is string {
  text(value, 80);
  requireCondition(/^[a-z0-9][a-z0-9_.:-]*$/.test(value));
}
export function id(value: unknown, prefix: string): asserts value is string {
  requireCondition(
    typeof value === "string" &&
      new RegExp(`^${prefix}[0-9]{4,12}$`).test(value),
  );
}
export function integer(
  value: unknown,
  min: number,
  max: number,
): asserts value is number {
  requireCondition(
    typeof value === "number" && Number.isSafeInteger(value) && value >= min &&
      value <= max,
  );
}
export function member<T>(
  value: unknown,
  allowed: readonly T[],
): asserts value is T {
  requireCondition(allowed.includes(value as T));
}
export function taxon(
  value: unknown,
): { id: string; rank: typeof RANKS[number] } {
  const item = fields(value, ["id", "rank"]);
  token(item.id);
  member(item.rank, RANKS);
  return { id: item.id, rank: item.rank };
}
export function validateReference(value: unknown, synthetic: boolean): void {
  const label = fields(value, [
    "subject",
    "resolution",
    "supportedRank",
    "acceptableTaxa",
  ]);
  member(label.subject, [
    "biological",
    "non_biological",
    "indeterminate",
    ...(synthetic ? ["human"] : []),
  ]);
  member(label.resolution, ["named", "unresolved"]);
  const taxa = array(label.acceptableTaxa, 0, 16).map(taxon);
  requireCondition(
    new Set(taxa.map((item) => item.id)).size === taxa.length,
    "invalid_reference",
  );
  if (label.resolution === "named") {
    member(label.supportedRank, RANKS);
    const rank = RANKS.indexOf(label.supportedRank);
    requireCondition(
      label.subject === "biological" && taxa.length > 0 && taxa.some((item) =>
        item.rank === label.supportedRank
      ) && taxa.every((item) => RANKS.indexOf(item.rank) <= rank),
      "invalid_reference",
    );
  } else {
    requireCondition(
      label.supportedRank === null && taxa.length === 0,
      "invalid_reference",
    );
  }
}
function validateCuration(value: unknown, synthetic: boolean): void {
  if (synthetic) {
    requireCondition(
      fields(value, ["kind"]).kind === "synthetic",
      "unapproved_evidence",
    );
    return;
  }
  const item = fields(value, [
    "kind",
    "source",
    "sourceRecordRef",
    "referenceRecordRef",
    "permission",
    "rightsApproved",
    "personalDataExcluded",
    "nearDuplicatesReviewed",
    "referenceVerified",
    "reviewerRefs",
    "adjudication",
  ]);
  requireCondition(
    item.kind === "reviewed" && item.permission === "gemini_evaluation" &&
      item.rightsApproved === true && item.personalDataExcluded === true &&
      item.nearDuplicatesReviewed === true && item.referenceVerified === true,
    "unapproved_evidence",
  );
  member(item.source, ["purpose_collected", "licensed"]);
  token(item.sourceRecordRef);
  token(item.referenceRecordRef);
  const reviewers = array(item.reviewerRefs, 2, 2);
  reviewers.forEach((reviewer) => id(reviewer, "r"));
  requireCondition(reviewers[0] !== reviewers[1], "unapproved_evidence");
  member(item.adjudication, ["agreed", "resolved"]);
}

export function parseEvaluationInput(value: unknown): EvaluationInput {
  const input = fields(value, [
    "caseId",
    "groupId",
    "split",
    "inputGroup",
    "observationTexts",
    "context",
    "clips",
    "assets",
  ]);
  id(input.caseId, "c");
  id(input.groupId, "g");
  member(input.split, ["development", "held_out"]);
  member(input.inputGroup, INPUT_GROUPS);
  array(input.observationTexts, 0, 8).forEach((value) => text(value));
  const context = fields(input.context, ["deviceRegion", "currentMonth"]);
  requireCondition(
    context.deviceRegion === null ||
      (typeof context.deviceRegion === "string" &&
        /^[A-Z]{2}$/.test(context.deviceRegion)),
  );
  if (context.currentMonth !== null) integer(context.currentMonth, 1, 12);
  const clips = array(input.clips, 0, 4).map((value, index) => {
    const clip = fields(value, [
      "clipIndex",
      "declaredFrameCount",
      "includesAudio",
    ]);
    requireCondition(clip.clipIndex === index, "invalid_media");
    integer(clip.declaredFrameCount, 1, 20);
    requireCondition(typeof clip.includesAudio === "boolean");
    return clip;
  });
  const seenIds = new Set<string>();
  const frames = clips.map(() => [] as number[]);
  const videoAudio = clips.map(() => 0);
  let stills = 0, audios = 0, audioStarted = false, previousClip = -1;
  let visualMime: string | null = null;
  const assets = array(input.assets, 0, 24);
  for (const raw of assets) {
    const item = record(raw);
    member(item.kind, ["image", "video_frame", "audio", "video_audio"]);
    const extra = item.kind === "video_frame"
      ? ["clipIndex", "frameIndex"]
      : item.kind === "video_audio"
      ? ["clipIndex"]
      : ["sourceIndex"];
    fields(item, [
      "id",
      "path",
      "sha256",
      "byteLength",
      "kind",
      "mimeType",
      ...extra,
    ]);
    id(item.id, "a");
    requireCondition(!seenIds.has(item.id), "invalid_media");
    seenIds.add(item.id);
    requireCondition(
      typeof item.sha256 === "string" && /^[a-f0-9]{64}$/.test(item.sha256),
    );
    integer(item.byteLength, 1, 16 * 1024 * 1024);
    const audio = item.kind === "audio" || item.kind === "video_audio";
    member(
      item.mimeType,
      audio ? ["audio/wav"] : ["image/jpeg", "image/png", "image/webp"],
    );
    if (!audio) {
      requireCondition(
        visualMime === null || visualMime === item.mimeType,
        "invalid_media",
      );
      visualMime = item.mimeType;
    }
    const ext = item.mimeType === "audio/wav"
      ? "wav"
      : item.mimeType === "image/png"
      ? "png"
      : item.mimeType === "image/webp"
      ? "webp"
      : "jpg";
    requireCondition(item.path === `assets/${item.id}.${ext}`, "invalid_media");
    requireCondition(audio || !audioStarted, "invalid_media");
    audioStarted ||= audio;
    if (item.kind === "image") {
      requireCondition(item.sourceIndex === stills++, "invalid_media");
    } else if (item.kind === "audio") {
      requireCondition(item.sourceIndex === audios++, "invalid_media");
    } else {
      integer(item.clipIndex, 0, clips.length - 1);
      if (item.kind === "video_audio") {
        videoAudio[item.clipIndex]++;
      } else {
        integer(
          item.frameIndex,
          0,
          (clips[item.clipIndex].declaredFrameCount as number) - 1,
        );
        const indexes = frames[item.clipIndex];
        requireCondition(
          item.clipIndex >= previousClip &&
            (indexes.length === 0 ||
              item.frameIndex > indexes[indexes.length - 1]),
          "invalid_media",
        );
        indexes.push(item.frameIndex);
        previousClip = item.clipIndex;
      }
    }
  }
  clips.forEach((clip, i) =>
    requireCondition(
      frames[i].length > 0 && videoAudio[i] === (clip.includesAudio ? 1 : 0),
      "invalid_media",
    )
  );
  const frameCount = frames.reduce((sum, indexes) => sum + indexes.length, 0);
  const videoAudioCount = videoAudio.reduce((sum, count) => sum + count, 0);
  const expected = stills > 0 && frameCount === 0 && videoAudioCount === 0
    ? (audios > 0 ? "photos_audio" : "photos")
    : frameCount > 0 && stills === 0 && audios === 0
    ? (videoAudioCount > 0 ? "frames_audio" : "frames")
    : audios > 0 && stills === 0 && frameCount === 0
    ? "audio"
    : assets.length === 0 && (input.observationTexts as unknown[]).length > 0
    ? "description"
    : null;
  requireCondition(input.inputGroup === expected, "invalid_media");
  return structuredClone(input) as unknown as EvaluationInput;
}

export function parseEvaluationCorpus(value: unknown): EvaluationCorpus {
  const corpus = fields(value, [
    "version",
    "id",
    "kind",
    "taxonomyVersion",
    "preparationVersion",
    "splitSeed",
    "approval",
    "cases",
  ]);
  requireCondition(corpus.version === CORPUS_VERSION, "unsupported_version");
  member(corpus.kind, ["synthetic", "reference"]);
  token(corpus.id);
  token(corpus.taxonomyVersion);
  token(corpus.preparationVersion);
  integer(corpus.splitSeed, 0, 0xffffffff);
  const synthetic = corpus.kind === "synthetic";
  if (synthetic) {
    requireCondition(corpus.approval === null, "unapproved_evidence");
  } else {
    requireCondition(corpus.approval !== null, "unapproved_evidence");
    const approval = fields(corpus.approval, [
      "recordRef",
      "ownerRole",
      "retainUntil",
    ]);
    token(approval.recordRef);
    token(approval.ownerRole);
    requireCondition(
      typeof approval.retainUntil === "string" &&
        /^\d{4}-\d{2}-\d{2}$/.test(approval.retainUntil) &&
        Number.isFinite(Date.parse(approval.retainUntil)) &&
        new Date(approval.retainUntil).toISOString().slice(0, 10) ===
          approval.retainUntil,
    );
  }
  const cases = array(corpus.cases, 1, 10000).map((raw) => {
    const item = fields(raw, ["input", "reference", "curation"]);
    validateReference(item.reference, synthetic);
    validateCuration(item.curation, synthetic);
    return parseEvaluationInput(item.input);
  });
  validateInputSeparation(cases);
  return structuredClone(corpus) as unknown as EvaluationCorpus;
}

/** Shared evidence identity rules; never supplies labels or approval. */
export function validateInputSeparation(
  inputs: readonly EvaluationInput[],
): void {
  const ids = new Set<string>();
  const groups = new Map<string, string>();
  const evidence = new Map<string, string>();
  for (const input of inputs) {
    requireCondition(!ids.has(input.caseId), "duplicate_case");
    ids.add(input.caseId);
    const split = groups.get(input.groupId);
    requireCondition(
      split === undefined || split === input.split,
      "split_leakage",
    );
    requireCondition(split === undefined, "duplicate_group");
    groups.set(input.groupId, input.split);
    const hashes = input.assets.map((asset) => `asset:${asset.sha256}`);
    if (input.observationTexts.length > 0) {
      hashes.push(
        `text:${
          input.observationTexts.join(" ").replace(/\s+/g, " ").toLowerCase()
        }`,
      );
    }
    for (const hash of hashes) {
      requireCondition(
        !evidence.has(hash) || evidence.get(hash) === input.groupId,
        "duplicate_evidence",
      );
      evidence.set(hash, input.groupId);
    }
  }
}

export function parsePrediction(value: unknown): Prediction {
  const item = record(value);
  member(item.outcome, OUTCOMES);
  fields(
    item,
    item.outcome === "normalized"
      ? ["caseId", "outcome", "subject", "resolution", "taxon", "confidence"]
      : ["caseId", "outcome"],
  );
  id(item.caseId, "c");
  if (item.outcome === "normalized") {
    member(item.subject, [
      "biological",
      "non_biological",
      "indeterminate",
      "human",
    ]);
    member(item.resolution, ["named", "unresolved"]);
    requireCondition(
      typeof item.confidence === "number" && Number.isFinite(item.confidence) &&
        item.confidence >= 0 && item.confidence <= 1,
      "invalid_prediction",
    );
    if (item.taxon !== null) taxon(item.taxon);
    requireCondition(
      item.resolution === "named"
        ? item.subject === "biological"
        : item.taxon === null,
      "invalid_prediction",
    );
  }
  return structuredClone(item) as unknown as Prediction;
}
