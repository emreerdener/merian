import {
  type IdentificationInputProfile,
  isIdentificationInputProfile,
} from "./identificationInput.ts";

/** Database-owned identification recipient. No client/runtime provider selector. */
export type IdentificationProviderAssignment = {
  readonly inputProfile: IdentificationInputProfile;
  readonly provider: "gemini";
  readonly binding: "gemini_baseline_v1";
  readonly permission: "google_gemini";
} | {
  readonly inputProfile: "multimodal_photo_v1";
  readonly provider: "openai";
  readonly binding: "openai_photo_v1";
  readonly permission: "openai";
};

export function isIdentificationProviderAssignment(
  value: unknown,
): value is IdentificationProviderAssignment {
  if (!value || typeof value !== "object" || Array.isArray(value)) return false;
  const assignment = value as Record<string, unknown>;
  return (isIdentificationInputProfile(assignment.inputProfile) &&
    assignment.provider === "gemini" &&
    assignment.binding === "gemini_baseline_v1" &&
    assignment.permission === "google_gemini") ||
    (assignment.inputProfile === "multimodal_photo_v1" &&
      assignment.provider === "openai" &&
      assignment.binding === "openai_photo_v1" &&
      assignment.permission === "openai");
}

export function assignmentMatchesModel(
  assignment: IdentificationProviderAssignment,
  model: string,
): boolean {
  return assignment.provider === "openai"
    ? model === "gpt-6-sol"
    : model === "gemini-2.5-flash" || model === "gemini-2.5-pro";
}
