import { assertEquals, assertThrows } from "@std/assert";
import type {
  AIRequest,
  MultimodalAIRequest,
  UserRequestAuthority,
} from "./contracts.ts";
import { identificationInputProfile } from "./identificationInput.ts";
import { resolveAIClaim } from "./registry.ts";
import { buildDescribeAIRequest } from "../../identify-describe/provider.ts";
import { buildVisionAIRequest } from "../../identify/provider.ts";
import { buildAudioAIRequest } from "../../audio-spec/provider.ts";

const telemetry = { safeGpsLat: null, safeGpsLon: null };
const text = {
  kind: "text",
  order: 0,
  source: "observation_context",
  text: "Synthetic observation",
} as const;
const image = {
  kind: "image",
  order: 0,
  inputIndex: 0,
  data: "AQ==",
  mimeType: "image/jpeg",
  lineage: null,
} as const;
const audio = {
  kind: "audio",
  order: 0,
  inputIndex: 0,
  data: "Ag==",
  mimeType: "audio/wav",
  lineage: null,
} as const;
const capture = {
  hasVideo: false,
  videoClipCount: 0,
  declaredVideoFrameCount: 0,
  videoInferenceFrameCount: 0,
};

Deno.test("app assignment resolves only the exact photo OpenAI tuple and never ignores another medium", () => {
  const request = main([image, text]);
  const authority: UserRequestAuthority = {
    kind: "user_request",
    userId: "synthetic-owner",
    permission: "openai",
    operation: "scan_identification",
    reservation: {
      id: "synthetic-reservation",
      requestId: "synthetic-request",
      attemptCount: 1,
      policyVersion: 1,
      model: "gpt-6-sol",
      tier: { effective_tier: "pro" },
      assignment: {
        provider: "openai",
        binding: "openai_photo_v1",
        permission: "openai",
        inputProfile: "multimodal_photo_v1",
      },
    },
  };
  assertEquals(resolveAIClaim(request, authority).provider, "openai");
  for (
    const input of [
      main([text]),
      main([audio]),
      main([image, audio]),
      main([image], true),
      main([image, audio], true),
    ]
  ) {
    assertThrows(() => resolveAIClaim(input, authority));
  }
  for (
    const change of [
      { model: "gemini-2.5-pro" },
      {
        assignment: {
          ...authority.reservation.assignment!,
          binding: "gemini_baseline_v1",
        },
      },
      {
        assignment: {
          ...authority.reservation.assignment!,
          permission: "google_gemini",
        },
      },
      {
        assignment: {
          ...authority.reservation.assignment!,
          inputProfile: "multimodal_video_frames_v1",
        },
      },
    ]
  ) {
    assertThrows(() =>
      resolveAIClaim(
        request,
        {
          ...authority,
          reservation: { ...authority.reservation, ...change },
        } as UserRequestAuthority,
      )
    );
  }
});
function main(
  evidence: MultimodalAIRequest["evidence"],
  video = false,
): MultimodalAIRequest {
  return {
    task: "identify",
    variant: "multimodal",
    evidence: evidence.map((item, order) => ({ ...item, order })),
    capture: { ...capture, hasVideo: video },
  };
}
Deno.test("complete-input routing keeps compatibility, audio and sampled video distinct", () => {
  const cases = [
    [
      buildDescribeAIRequest("Synthetic observation", telemetry),
      "description_compat_v1",
    ],
    [
      buildVisionAIRequest({ imageBase64s: ["AQ=="], telemetry }),
      "vision_compat_v1",
    ],
    [buildAudioAIRequest("Ag==", telemetry), "audio_compat_v1"],
    [main([text]), "multimodal_text_v1"],
    [main([image, text]), "multimodal_photo_v1"],
    [main([audio, text]), "multimodal_audio_v1"],
    [main([image, audio, text]), "multimodal_photo_audio_v1"],
    [main([image], true), "multimodal_video_frames_v1"],
    [main([image, audio], true), "multimodal_video_audio_v1"],
    [
      main([{ ...image, lineage: { kind: "video_frame" } }]),
      "multimodal_video_frames_v1",
    ],
    [
      main([{ ...audio, lineage: { kind: "video_audio" } }]),
      "multimodal_video_audio_v1",
    ],
    [
      {
        ...main([image]),
        capture: { ...capture, videoInferenceFrameCount: 1 },
      },
      "multimodal_video_frames_v1",
    ],
    [
      { ...main([image]), capture: { ...capture, declaredVideoFrameCount: 5 } },
      "multimodal_video_frames_v1",
    ],
    [
      { ...main([audio]), capture: { ...capture, videoClipCount: 1 } },
      "multimodal_video_audio_v1",
    ],
  ] as const;
  for (const [request, expected] of cases) {
    assertEquals(identificationInputProfile(request), expected);
  }
});
Deno.test("input classifier rejects missing evidence, native video and malformed capture", () => {
  for (
    const request of [
      main([]),
      {
        ...main([image]),
        evidence: [{ ...image, kind: "video", mimeType: "video/mp4" }],
      },
      { ...main([image]), capture: { ...capture, videoClipCount: -1 } },
      { ...main([image]), capture: { ...capture, hasVideo: "false" } },
      {
        task: "species_overview",
        variant: "species_content",
        scientificName: "Synthetic",
      },
    ]
  ) {
    assertThrows(
      () => identificationInputProfile(request as AIRequest),
      Error,
      "ai_unsupported_input",
    );
  }
});
Deno.test("app assignment ignores selector-shaped extras and rejects changed evidence before dispatch", () => {
  const request = main([image]);
  const authority: UserRequestAuthority = {
    kind: "user_request",
    userId: "synthetic-owner",
    permission: "google_gemini",
    operation: "scan_identification",
    reservation: {
      id: "synthetic-reservation",
      requestId: "synthetic-request",
      attemptCount: 1,
      policyVersion: 1,
      model: "gemini-2.5-flash",
      tier: { effective_tier: "free" },
      assignment: {
        provider: "gemini",
        binding: "gemini_baseline_v1",
        permission: "google_gemini",
        inputProfile: "multimodal_photo_v1",
      },
    },
  };
  const spoofed = {
    ...request,
    provider: "openai",
    model: "unqualified",
    input_profile: "multimodal_text_v1",
  };
  assertEquals(identificationInputProfile(spoofed), "multimodal_photo_v1");
  assertEquals(resolveAIClaim(spoofed, authority).provider, "gemini");
  for (
    const changed of [main([image, audio]), main([image], true), main([text])]
  ) {
    assertThrows(
      () => resolveAIClaim(changed, authority),
      Error,
      "ai_authority_mismatch",
    );
  }
});
