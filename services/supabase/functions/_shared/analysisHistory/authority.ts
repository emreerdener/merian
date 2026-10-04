import {
  type EffectiveIdentification,
  effectiveIdentification,
  type SavedIdentificationFields,
} from "../identify/effectiveIdentity.ts";
import { HistoryError } from "./contract.ts";

export interface BoundAnalysisEvidence {
  observation_id: string;
  analysis_id: string;
  fields: Pick<
    SavedIdentificationFields,
    | "primary_identification"
    | "identification_provenance"
    | "species_id"
    | "is_biological_subject"
    | "candidates"
    | "pet_identification"
  >;
}

export interface BoundAnalysisReview {
  observation_id: string;
  analysis_id: string;
  review_revision: number;
  fields: Pick<
    SavedIdentificationFields,
    | "ai_identification_review"
    | "confirmed_species_identity"
    | "confirmed_species_identity_revision"
    | "confirmed_species_id"
    | "user_identification_override"
    | "user_confirmed_identification"
    | "user_review_state"
  >;
}

/** Only trusted stored fields enter this function; selection is not review. */
export function analysisIdentification(
  evidence: BoundAnalysisEvidence,
  authority: BoundAnalysisReview,
): EffectiveIdentification {
  if (
    evidence.observation_id !== authority.observation_id ||
    evidence.analysis_id !== authority.analysis_id
  ) throw new HistoryError("analysis_history_not_found");
  // Select fields explicitly so a malformed/mixed evidence snapshot cannot
  // smuggle another result's confirmation into the active projection.
  const identity = effectiveIdentification({
    primary_identification: evidence.fields.primary_identification,
    identification_provenance: evidence.fields.identification_provenance,
    species_id: evidence.fields.species_id,
    is_biological_subject: evidence.fields.is_biological_subject,
    candidates: evidence.fields.candidates,
    pet_identification: evidence.fields.pet_identification,
    ai_identification_review: authority.fields.ai_identification_review,
    confirmed_species_identity: authority.fields.confirmed_species_identity,
    confirmed_species_identity_revision:
      authority.fields.confirmed_species_identity_revision,
    confirmed_species_id: authority.fields.confirmed_species_id,
    user_identification_override: authority.fields.user_identification_override,
    user_confirmed_identification:
      authority.fields.user_confirmed_identification,
    user_review_state: authority.fields.user_review_state,
  });
  // Legacy rows can contain stale species links after classification changes.
  if (evidence.fields.is_biological_subject === false) {
    return {
      ...identity,
      rank: "non_biological",
      species_id: null,
      verified: false,
    };
  }
  return identity;
}

export interface PublicationAuthority {
  status: "current" | "unresolved" | "hidden";
  identification: EffectiveIdentification | null;
}

/** Published analysis is explicit: private selection is intentionally absent. */
export function publicationAuthority(
  publishedEvidence: BoundAnalysisEvidence,
  currentPublishedReview: BoundAnalysisReview,
  visibility: { privacyPermits: boolean; moderationPermits: boolean },
): PublicationAuthority {
  if (!visibility.privacyPermits || !visibility.moderationPermits) {
    return { status: "hidden", identification: null };
  }
  const identification = analysisIdentification(
    publishedEvidence,
    currentPublishedReview,
  );
  if (
    identification.source === "invalid" ||
    identification.rank === "non_biological"
  ) return { status: "hidden", identification: null };
  if (identification.pending_review) {
    return {
      status: "unresolved",
      identification: { ...identification, species_id: null, verified: false },
    };
  }
  return { status: "current", identification };
}
