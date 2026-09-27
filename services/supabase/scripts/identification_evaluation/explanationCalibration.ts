import {
  type Calibration,
  CRITERIA,
  parseCalibration,
  parseRatings,
  type Ratings,
  RUBRIC,
} from "./explanationContracts.ts";
import { fingerprintJson } from "./evidence.ts";
import { requireCondition as check } from "./validation.ts";
const pass = () =>
  parseRatings(
    Object.fromEntries(
      CRITERIA.map((k) => [k, { status: "pass", reason: "supported" }]),
    ),
  );
const example = (
  observation: string,
  explanation: string,
  changes: Partial<Ratings> = {},
) => ({ observation, explanation, expected: { ...pass(), ...changes } });
/** Invented text only. No real corpus or provider output belongs in calibration. */
export const CALIBRATION_EXAMPLES = [
  example(
    "A smooth gray mineral pebble; no living structures are visible.",
    "The mineral surface supports a non-biological classification.",
  ),
  example(
    "A pebble confirmed to be mineral; no gills or spore print are visible.",
    "A non-biological pebble is suggested by the mineral surface. A spore print is also visible.",
    { grounding: { status: "fail", reason: "invented_evidence" } },
  ),
  example(
    "A mushroom with a spotted cap; underside and base are not visible. The facts support only a broad mushroom identification.",
    "The cap supports a mushroom identification; the missing underside and base prevent a reliable species choice.",
  ),
  example(
    "A spotted mushroom with no underside or base visible; these facts cannot resolve species.",
    "The spotted cap supports a mushroom identification. It is definitely a specific species and no further detail is needed.",
    { uncertainty: { status: "fail", reason: "unsupported_specificity" } },
  ),
  example(
    "A smooth mineral pebble. The explanation should connect its material or surface to a non-biological decision.",
    "It is a pebble because it is a pebble.",
    {
      requiredInformation: { status: "fail", reason: "generic_justification" },
    },
  ),
  example(
    "A blurry distant organism with no diagnostic detail visible; identification should abstain.",
    "The image does not show enough detail to identify the organism reliably.",
  ),
  example(
    "A mushroom with a visible spotted cap. The reference does not establish whether cap patterns distinguish species.",
    "The spotted cap supports a mushroom identification. This pattern is usually a useful species discriminator, although a species cannot be selected here.",
    {
      grounding: { status: "not_assessable", reason: "insufficient_reference" },
    },
  ),
  example(
    "Evidence and reference facts are unavailable.",
    "No explanation is available.",
    Object.fromEntries(
      CRITERIA.map((
        k,
      ) => [k, { status: "not_assessable", reason: "review_unavailable" }]),
    ) as Ratings,
  ),
] as const;
export async function calibrationRecord(
  reviewerRef: string,
  ratings: Ratings[],
  method: Calibration["method"] = "owner_local_v1",
): Promise<Calibration> {
  const passed = await fingerprintJson(ratings) ===
    await fingerprintJson(CALIBRATION_EXAMPLES.map((c) => c.expected));
  return parseCalibration({
    version: "explanation_calibration_v1",
    method,
    reviewerRef,
    rubricDigest: await fingerprintJson(RUBRIC),
    examplesDigest: await fingerprintJson(CALIBRATION_EXAMPLES),
    completedAt: new Date().toISOString(),
    ratings,
    passed,
  });
}
export async function validateCalibration(
  value: unknown,
  reviewerRef: string,
  live: boolean,
) {
  const v = parseCalibration(value);
  check(
    v.reviewerRef === reviewerRef &&
      v.method === (live ? "owner_local_v1" : "synthetic_fixture_v1"),
  );
  check(
    v.rubricDigest === await fingerprintJson(RUBRIC) &&
      v.examplesDigest === await fingerprintJson(CALIBRATION_EXAMPLES),
  );
  check(
    v.passed &&
      await fingerprintJson(v.ratings) ===
        await fingerprintJson(CALIBRATION_EXAMPLES.map((c) => c.expected)),
  );
  return v;
}
