/** Tooling-only records. These are not HTTP DTOs, provider inputs or consent. */
export const CORPUS_VERSION = "identification_corpus_v1" as const;
export const REPORT_VERSION = "identification_scores_v1" as const;
export const SCORER_VERSION = "identification_decisions_v1" as const;

export const INPUT_GROUPS = [
  "photos",
  "description",
  "audio",
  "frames",
  "frames_audio",
  "photos_audio",
] as const;
export type InputGroup = typeof INPUT_GROUPS[number];
export type Split = "development" | "held_out";
export const RANKS = [
  "kingdom",
  "phylum",
  "class",
  "order",
  "family",
  "genus",
  "species",
] as const;
export type Rank = typeof RANKS[number];
export type Subject =
  | "biological"
  | "non_biological"
  | "indeterminate"
  | "human";
export type Resolution = "named" | "unresolved";
export interface Taxon {
  readonly id: string;
  readonly rank: Rank;
}

interface AssetFile {
  readonly id: string;
  readonly path: string;
  readonly sha256: string;
  readonly byteLength: number;
}
export type Asset =
  & AssetFile
  & (
    | {
      readonly kind: "image";
      readonly mimeType: "image/jpeg" | "image/png" | "image/webp";
      readonly sourceIndex: number;
    }
    | {
      readonly kind: "video_frame";
      readonly mimeType: "image/jpeg" | "image/png" | "image/webp";
      readonly clipIndex: number;
      readonly frameIndex: number;
    }
    | {
      readonly kind: "audio";
      readonly mimeType: "audio/wav";
      readonly sourceIndex: number;
    }
    | {
      readonly kind: "video_audio";
      readonly mimeType: "audio/wav";
      readonly clipIndex: number;
    }
  );
export interface EvaluationInput {
  readonly caseId: string;
  readonly groupId: string;
  readonly split: Split;
  readonly inputGroup: InputGroup;
  readonly observationTexts: readonly string[];
  // Deliberately excludes precise location, device identity and arbitrary metadata.
  readonly context: {
    readonly deviceRegion: string | null;
    readonly currentMonth: number | null;
  };
  readonly clips: readonly {
    readonly clipIndex: number;
    readonly declaredFrameCount: number;
    readonly includesAudio: boolean;
  }[];
  readonly assets: readonly Asset[];
}
export interface ReferenceLabel {
  readonly subject: Subject;
  readonly resolution: Resolution;
  readonly supportedRank: Rank | null;
  readonly acceptableTaxa: readonly Taxon[];
}
export type Curation = { readonly kind: "synthetic" } | {
  readonly kind: "reviewed";
  readonly source: "purpose_collected" | "licensed";
  readonly sourceRecordRef: string;
  readonly referenceRecordRef: string;
  readonly permission: "gemini_evaluation";
  readonly rightsApproved: true;
  readonly personalDataExcluded: true;
  readonly nearDuplicatesReviewed: true;
  readonly referenceVerified: true;
  readonly reviewerRefs: readonly [string, string];
  readonly adjudication: "agreed" | "resolved";
};
export interface EvaluationCase {
  readonly input: EvaluationInput;
  readonly reference: ReferenceLabel;
  readonly curation: Curation;
}
export interface EvaluationCorpus {
  readonly version: typeof CORPUS_VERSION;
  readonly id: string;
  readonly kind: "synthetic" | "reference";
  readonly taxonomyVersion: string;
  readonly preparationVersion: string;
  readonly splitSeed: number;
  readonly approval: null | {
    readonly recordRef: string;
    readonly ownerRole: string;
    readonly retainUntil: string;
  };
  readonly cases: readonly EvaluationCase[];
}

export const OUTCOMES = [
  "normalized",
  "refusal",
  "invalid_output",
  "operational_failure",
  "unknown_execution",
  "local_validation_failure",
  "unattempted",
] as const;
export type Outcome = typeof OUTCOMES[number];
export type Prediction =
  & { readonly caseId: string }
  & (
    | { readonly outcome: Exclude<Outcome, "normalized"> }
    | {
      readonly outcome: "normalized";
      readonly subject: Subject;
      readonly resolution: Resolution;
      // A named result with null taxon means mapping failed, not abstention.
      readonly taxon: Taxon | null;
      readonly confidence: number;
    }
  );
export type Profile = "gemini_flash_free" | "gemini_pro";
export interface Rate {
  readonly numerator: number;
  readonly denominator: number;
  readonly value: number | null;
  readonly status: "measured" | "not_estimable";
}
export interface ReliabilityBin {
  readonly correctness: Rate;
  readonly meanScore: number | null;
}
export interface ScoreReport {
  readonly version: typeof REPORT_VERSION;
  readonly scorerVersion: typeof SCORER_VERSION;
  readonly evidenceKind: EvaluationCorpus["kind"];
  readonly corpusId: string;
  readonly corpusDigest: string;
  readonly taxonomyVersion: string;
  readonly preparationVersion: string;
  readonly profile: Profile;
  readonly split: Split;
  readonly inputGroup: InputGroup | "all_cases";
  readonly verdict: "measurement_only";
  readonly completeness: "complete" | "incomplete";
  readonly counts: {
    readonly scheduled: number;
    readonly biological: number;
    readonly speciesAnswerable: number;
    readonly named: number;
    readonly unsupportedSpecificity: number;
    readonly unresolvedMapping: number;
  };
  readonly outcomes: Readonly<Record<Outcome, number>>;
  readonly metrics: {
    readonly exactSpecies: Rate;
    readonly offeredPrecision: Rate;
    readonly answerCoverage: Rate;
    readonly correctAnswerYield: Rate;
    readonly subjectAccuracy: Rate;
    readonly appropriateUnresolved: Rate;
    readonly falseBiologicalAssertions: Rate;
    readonly unsupportedBiologicalAssertions: Rate;
    readonly strongErrorRate: Rate;
    readonly strongErrorAmongNamed: Rate;
    readonly diagnosticErrorRate: Rate;
    readonly diagnosticErrorAmongNamed: Rate;
  };
  readonly reliability: Readonly<
    Record<
      "below_possible" | "possible" | "strong" | "diagnostic_subset",
      ReliabilityBin
    >
  >;
  readonly subjectMatrix: Readonly<
    Record<Subject, Readonly<Record<Subject | "no_result", number>>>
  >;
  readonly resolutionMatrix: Readonly<
    Record<Resolution, Readonly<Record<Resolution | "no_result", number>>>
  >;
  readonly performance: "not_measured";
  readonly intervals: "not_computed";
}
