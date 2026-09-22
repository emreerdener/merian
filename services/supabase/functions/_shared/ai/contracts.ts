/** Internal contracts. No SDK types, credentials, HTTP admission or settlement. */
import type {
  AudioMediaDescriptor,
  VisualMediaDescriptor,
} from "../../identify-multimodal/capturedMedia.ts";

export type AITask =
  | "identify"
  | "species_overview"
  | "lookalikes"
  | "group_tags";

export interface UserRequestAuthority {
  readonly kind: "user_request";
  readonly userId: string;
  readonly permission: "google_gemini";
  readonly operation: string;
  readonly reservation: {
    readonly id: string;
    readonly requestId: string;
    readonly attemptCount: number;
    readonly policyVersion: number;
    readonly model: string;
    readonly tier?: { readonly effective_tier: "free" | "pro" };
  };
}

/** Supplied only after service authentication and a durable public-fact claim. */
export interface ServiceJobAuthority {
  readonly kind: "service_job";
  readonly task: Exclude<AITask, "identify">;
  readonly purpose: "public_species_facts";
  readonly jobId: string;
  readonly attemptCount: number;
  readonly maxAttempts: number;
  readonly model: string;
}

// Authority is supplied by trusted orchestrators after existing admission; these
// types do not authenticate a caller or replace a quota lease / durable claim.
export type AIExecutionAuthority = UserRequestAuthority | ServiceJobAuthority;

export interface DescribeAIRequest {
  readonly task: "identify";
  readonly variant: "description_compat";
  readonly evidence: readonly [{
    readonly kind: "text";
    readonly source: "description";
    readonly order: 0;
    readonly text: string;
  }];
}

export type IdentifyEvidence =
  | {
    readonly kind: "text";
    readonly order: number;
    readonly text: string;
    readonly source:
      | "observation_context"
      | "visual_context"
      | "capture_context";
  }
  | {
    readonly kind: "image";
    readonly order: number;
    readonly data: string;
    readonly mimeType: string;
    readonly inputIndex: number;
    readonly lineage: VisualMediaDescriptor | null;
  }
  | {
    readonly kind: "audio";
    readonly order: number;
    readonly data: string;
    readonly mimeType: "audio/wav";
    readonly inputIndex: number;
    readonly lineage: AudioMediaDescriptor | null;
  };

export interface MultimodalAIRequest {
  readonly task: "identify";
  readonly variant: "multimodal";
  readonly evidence: readonly IdentifyEvidence[];
  // Capture provenance is separate from inference capability. No playback key,
  // storage URL or native video file enters the provider request.
  readonly capture: {
    readonly hasVideo: boolean;
    readonly videoClipCount: number;
    readonly declaredVideoFrameCount: number;
    readonly videoInferenceFrameCount: number;
  };
}

export interface CompatibilityMediaAIRequest {
  readonly task: "identify";
  readonly variant: "vision_compat" | "audio_compat";
  readonly evidence: readonly IdentifyEvidence[];
}

export type AIRequest =
  | DescribeAIRequest
  | MultimodalAIRequest
  | CompatibilityMediaAIRequest
  | SpeciesContentAIRequest;

export type SpeciesContentAIRequest =
  & {
    readonly variant: "species_content";
    readonly scientificName: string;
  }
  & (
    | { readonly task: "species_overview"; readonly locale: string }
    | {
      readonly task: "lookalikes";
      readonly taxonomy:
        | {
          readonly kingdom?: string | null;
          readonly class?: string | null;
          readonly order?: string | null;
          readonly family?: string | null;
        }
        | null
        | undefined;
    }
    | { readonly task: "group_tags" }
  );

export interface AIAttemptSnapshot {
  readonly provider: "gemini";
  readonly binding: "gemini_baseline_v1";
  readonly task: AITask;
  readonly variant: AIRequest["variant"];
  readonly model: "gemini-2.5-flash" | "gemini-2.5-pro";
  readonly contextKind: "user_request" | "service_job";
  readonly operation:
    | "scan_identification"
    | "scan_audio_identification"
    | "scan_overview_enrichment"
    | "scan_lookalike_enrichment"
    | "scan_group_tag_enrichment";
  readonly policyVersion: number | null;
  readonly permission: "google_gemini" | null;
  readonly prompt:
    | "identify_describe_v1"
    | "identify_vision_v1"
    | "identify_audio_v1"
    | "identify_audio_compat_v1"
    | "identify_text_v1"
    | "identify_blended_v1"
    | "species_overview_v1"
    | "lookalikes_v1"
    | "group_tags_v1";
  readonly schema:
    | "merian_describe_v1"
    | "merian_identify_v1"
    | "merian_audio_v1"
    | "species_overview_v1"
    | "lookalikes_v1"
    | "group_tags_v1";
  readonly confidence:
    | "gemini_describe_v1"
    | "gemini_identify_v1"
    | "gemini_vision_compat_v1"
    | "gemini_audio_compat_v1"
    | null;
  readonly diagnosticTrigger?: number;
  // Legacy vision binds its prompt to the model and schema to the admitted tier.
  readonly promptDiagnosticTrigger?: number;
  readonly safety?: "biological_vision_v1";
  readonly timeoutMs: 90000;
  readonly generation: {
    readonly temperature: 0.15 | 0.1;
    readonly seed?: 42;
    readonly topK?: 40;
    readonly maxOutputTokens: 100 | 300 | 1500 | 2048 | 4096 | 8192;
    readonly thinkingBudget?: 0 | 1024 | 2048 | 3000 | 5000;
  };
}

export interface AIUsage {
  readonly promptTokens: number | null;
  readonly candidateTokens: number | null;
  readonly totalTokens: number | null;
  readonly thinkingTokens: number | null;
  readonly cachedTokens: number | null;
  readonly toolTokens?: number | null;
  readonly modalityBreakdown: Record<string, unknown>;
}

export interface AIResponseFacts {
  /** Native invocation only, excluding response normalization/JSON parsing. */
  readonly providerDurationMs: number;
  readonly providerCompletedAt: number;
  readonly returnedModel: string | null;
  readonly usage: AIUsage | null;
  readonly finishReason: string | null;
  readonly responseCharacters: number;
  // Only the probability consumed by the existing moderation boundary. Other
  // providers must translate their safety signals before using this contract.
  readonly safetyRatings?: readonly { readonly probability?: string }[];
}

export type AIProviderOutcome =
  & AIResponseFacts
  & (
    | { readonly kind: "draft"; readonly draft: unknown }
    | { readonly kind: "refusal" }
    | { readonly kind: "invalid_output"; readonly reason: "json" | "finish" }
    | { readonly kind: "operational_failure" | "unknown_execution" }
  );

export type AIExecutionOutcome = AIProviderOutcome & {
  readonly execution: AIAttemptSnapshot & { readonly durationMs: number };
};

export interface AIAdapter {
  readonly provider: string;
  // Prepare must not dispatch. Local configuration failure precedes commitment.
  prepare(
    request: AIRequest,
    snapshot: AIAttemptSnapshot,
  ): () => Promise<AIProviderOutcome>;
}

export interface PreparedAIExecution {
  readonly snapshot: AIAttemptSnapshot;
  invoke(): Promise<AIExecutionOutcome>;
}
