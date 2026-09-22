import {
  type Asset,
  CORPUS_VERSION,
  type EvaluationCorpus,
  INPUT_GROUPS,
  type Prediction,
  type ReferenceLabel,
} from "./contracts.ts";

/** Invented labels and asset descriptors, never biological or live-run evidence. */
export function syntheticCorpus(): EvaluationCorpus {
  const observations = [
    "Synthetic broad leaf without flowers.",
    "Synthetic small insect with incomplete markings.",
    "Synthetic repeated animal call.",
    "Synthetic moving organism across ordered frames.",
    "Synthetic movement with a companion call.",
    "Synthetic manufactured object with background noise.",
    "Synthetic distant organism in a still image.",
    "Synthetic description too vague for a named answer.",
    "Synthetic sound with insufficient evidence for a name.",
    "Synthetic non-biological object across frames.",
    "Synthetic second frame and sound observation.",
    "Synthetic second still and sound observation.",
  ];
  return {
    version: CORPUS_VERSION,
    id: "synthetic-contract-cases-v1",
    kind: "synthetic",
    taxonomyVersion: "synthetic-taxonomy-v1",
    preparationVersion: "synthetic-descriptors-v1",
    splitSeed: 42,
    approval: null,
    cases: observations.map((text, index) => {
      const n = index + 1;
      const inputGroup = INPUT_GROUPS[index % INPUT_GROUPS.length];
      const video = inputGroup === "frames" || inputGroup === "frames_audio";
      const audio = inputGroup === "audio" || inputGroup.endsWith("_audio");
      const assets: Asset[] = [];
      const file = (offset: number, wav = false) => {
        const number = n * 10 + offset;
        const id = `a${String(number).padStart(4, "0")}`;
        return {
          id,
          path: `assets/${id}.${wav ? "wav" : "webp"}`,
          sha256: number.toString(16).padStart(64, "0"),
          byteLength: 128,
        };
      };
      if (video) {
        for (let frameIndex = 0; frameIndex < 5; frameIndex++) {
          assets.push({
            ...file(frameIndex),
            kind: "video_frame",
            mimeType: "image/webp",
            clipIndex: 0,
            frameIndex,
          });
        }
      } else if (inputGroup === "photos" || inputGroup === "photos_audio") {
        assets.push({
          ...file(0),
          kind: "image",
          mimeType: "image/webp",
          sourceIndex: 0,
        });
      }
      if (audio) {
        assets.push(
          video
            ? {
              ...file(5, true),
              kind: "video_audio",
              mimeType: "audio/wav",
              clipIndex: 0,
            }
            : {
              ...file(5, true),
              kind: "audio",
              mimeType: "audio/wav",
              sourceIndex: 0,
            },
        );
      }
      const reference: ReferenceLabel = n === 6 || n === 10
        ? {
          subject: "non_biological",
          resolution: "unresolved",
          supportedRank: null,
          acceptableTaxa: [],
        }
        : n === 8 || n === 9
        ? {
          subject: "biological",
          resolution: "unresolved",
          supportedRank: null,
          acceptableTaxa: [],
        }
        : {
          subject: "biological",
          resolution: "named",
          supportedRank: n === 2 ? "genus" : "species",
          acceptableTaxa: [{
            id: `synthetic:${n}`,
            rank: n === 2 ? "genus" : "species",
          }],
        };
      return {
        input: {
          caseId: `c${String(n).padStart(4, "0")}`,
          groupId: `g${String(n).padStart(4, "0")}`,
          split: "development",
          inputGroup,
          observationTexts: [text],
          context: { deviceRegion: null, currentMonth: null },
          clips: video
            ? [{ clipIndex: 0, declaredFrameCount: 5, includesAudio: audio }]
            : [],
          assets,
        },
        reference,
        curation: { kind: "synthetic" },
      };
    }),
  };
}

export function syntheticPredictions(): Prediction[] {
  const named = (n: number, confidence: number): Prediction => ({
    caseId: `c${String(n).padStart(4, "0")}`,
    outcome: "normalized",
    subject: "biological",
    resolution: "named",
    taxon: { id: `synthetic:${n}`, rank: "species" },
    confidence,
  });
  return [
    named(1, 0.99),
    named(2, 0.99), // Genus evidence cannot justify this species claim.
    { caseId: "c0003", outcome: "refusal" },
    named(4, 0.90),
    { caseId: "c0005", outcome: "invalid_output" },
    named(6, 0.99), // A non-biological negative, included in confident errors.
    { caseId: "c0007", outcome: "operational_failure" },
    named(8, 0.97), // Unresolved reference, not a license to guess.
    {
      caseId: "c0009",
      outcome: "normalized",
      subject: "biological",
      resolution: "unresolved",
      taxon: null,
      confidence: 0,
    },
    {
      caseId: "c0010",
      outcome: "normalized",
      subject: "non_biological",
      resolution: "unresolved",
      taxon: null,
      confidence: 1,
    },
    { caseId: "c0011", outcome: "unknown_execution" },
    { caseId: "c0012", outcome: "unattempted" },
  ];
}
