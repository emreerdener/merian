import { assert, assertEquals, assertRejects, assertThrows } from "@std/assert";
import type { AIAttemptSnapshot, MultimodalAIRequest } from "./contracts.ts";
import {
  assignmentMatchesModel,
  isIdentificationProviderAssignment,
} from "./admission.ts";
import { createAIExecution } from "./execution.ts";
import { prepareMultimodalResultPolicy } from "./multimodalResultPolicy.ts";
import {
  createOpenAIPhotoModelEvaluationAdapter,
  OPENAI_RESPONSES_URL,
} from "./openai.ts";
import {
  buildOpenAIPhotoRequestParameters,
  OPENAI_PHOTO_MODERATION_MODEL,
  openAIPhotoSnapshot,
} from "./openaiPhoto.ts";
import {
  buildOpenAIPhotoModelRequestParameters,
  OPENAI_PHOTO_MODEL_PROFILES,
  openAIPhotoModelSnapshot,
} from "./openaiPhotoModels.ts";
import {
  OPENAI_LUNA_EVIDENCE_LIMITS_PROFILE,
  OPENAI_LUNA_EVIDENCE_LIMITS_PROMPT,
  OPENAI_LUNA_EVIDENCE_LIMITS_PROMPT_DIGEST,
  openAILunaEvidenceLimitsInstructions,
} from "./openaiLunaEvidenceLimits.ts";
import {
  buildOpenAIRequestParameters,
  isOpenAIProfile,
  openAIEvaluationSnapshot,
} from "./openaiRequest.ts";
import {
  openAIPhotoModerationFixture,
  openAIPhotoRequestFixture,
  openAIResponseFixture,
  openAITextFixture,
} from "./testing/openaiFixtures.ts";

Deno.test("photo model evaluation preserves the historical request independently of the current production prompt", () => {
  const base = openAIPhotoRequestFixture();
  const photo = base.evidence[0];
  if (photo.kind !== "image") throw new Error("photo_fixture_required");
  const requests: MultimodalAIRequest[] = [base, {
    ...base,
    evidence: [photo],
  }, {
    ...base,
    evidence: [photo, {
      ...photo,
      order: 1,
      inputIndex: 1,
      lineage: { kind: "image", sourceIndex: 1 },
    }, { ...base.evidence[1], order: 2 }],
  }];
  for (const request of requests) {
    const baseline = {
      ...buildOpenAIRequestParameters(
        request,
        openAIEvaluationSnapshot(request),
      ),
      moderation: { model: OPENAI_PHOTO_MODERATION_MODEL },
    };
    assert(
      baseline.instructions !==
        buildOpenAIPhotoRequestParameters(
          request,
          openAIPhotoSnapshot(request, 1),
        ).instructions,
    );
    for (const profile of OPENAI_PHOTO_MODEL_PROFILES) {
      const snapshot = openAIPhotoModelSnapshot(request, profile);
      assertEquals(buildOpenAIPhotoModelRequestParameters(request, snapshot), {
        ...baseline,
        model: snapshot.model,
      });
      assertEquals(snapshot.contextKind, "evaluation");
      assertEquals(snapshot.prompt, "openai_identify_vision_v1");
      assertEquals(isOpenAIProfile(profile), false);
      assertThrows(() =>
        prepareMultimodalResultPolicy(snapshot as unknown as AIAttemptSnapshot)
      );
      assertThrows(() =>
        buildOpenAIPhotoRequestParameters(
          request,
          snapshot as unknown as ReturnType<typeof openAIPhotoSnapshot>,
        )
      );
    }
  }
  const assignment = {
    provider: "openai",
    binding: "openai_photo_v1",
    inputProfile: "multimodal_photo_v1",
    permission: "openai",
  } as const;
  assertEquals(assignmentMatchesModel(assignment, "gpt-6-luna"), false);
  assertEquals(assignmentMatchesModel(assignment, "gpt-6-sol"), true);
  assertEquals(
    isIdentificationProviderAssignment({
      ...assignment,
      binding: "openai_photo_models_evaluation_v1",
    }),
    false,
  );
});

Deno.test("photo model evaluation rejects profile and representation substitutions before transport", () => {
  const base = openAIPhotoRequestFixture();
  const invalid: MultimodalAIRequest[] = [openAITextFixture(), {
    ...base,
    capture: { ...base.capture, hasVideo: true },
  }, {
    ...base,
    evidence: [...base.evidence, {
      kind: "audio",
      order: 2,
      inputIndex: 0,
      lineage: null,
      data: "AQID",
      mimeType: "audio/wav",
    }],
  }, {
    ...base,
    evidence: [{
      kind: "image",
      order: 0,
      inputIndex: 0,
      lineage: { kind: "video_frame", clipIndex: 0, frameIndex: 0 },
      data: "AQID",
      mimeType: "image/png",
    }],
  }];
  for (const request of invalid) {
    assertThrows(() =>
      openAIPhotoModelSnapshot(request, OPENAI_PHOTO_MODEL_PROFILES[0])
    );
  }
  const snapshot = openAIPhotoModelSnapshot(
    base,
    OPENAI_PHOTO_MODEL_PROFILES[0],
  );
  let calls = 0;
  const adapter = createOpenAIPhotoModelEvaluationAdapter(
    "synthetic-key",
    () => {
      calls++;
      throw new Error("unexpected transport");
    },
  );
  for (
    const change of [
      { model: "gpt-6-sol" },
      { profile: "openai_photo_luna_medium_v1" },
      { moderationModel: "omni-moderation-latest" },
      { safety: undefined },
      { contextKind: "user_request" },
      { binding: "openai_photo_v1" },
      { generation: { ...snapshot.generation, reasoningEffort: "medium" } },
      { generation: { ...snapshot.generation, imageDetail: "low" } },
      { generation: { ...snapshot.generation, maxOutputTokens: 16384 } },
      { permission: "openai" },
      { timeoutMs: 180000 },
    ]
  ) {
    assertThrows(() =>
      adapter.prepare(base, { ...snapshot, ...change } as typeof snapshot)
    );
  }
  assertEquals(calls, 0);
});

Deno.test("all photo model profiles require exact returned identity and complete native moderation", async () => {
  for (
    const profile of [
      ...OPENAI_PHOTO_MODEL_PROFILES,
      OPENAI_LUNA_EVIDENCE_LIMITS_PROFILE,
    ]
  ) {
    for (
      const failure of [
        null,
        "wrong_model",
        "version_suffix",
        "missing_input",
        "missing_output",
        "flagged",
        "incomplete",
        "tool_output",
        "http_401",
        "http_500",
      ] as const
    ) {
      const request = openAIPhotoRequestFixture();
      const snapshot = openAIPhotoModelSnapshot(request, profile);
      const response = {
        ...openAIResponseFixture(),
        model: snapshot.model as string,
        service_tier: "default",
        moderation: openAIPhotoModerationFixture(),
      };
      if (failure === "wrong_model") {
        response.model = snapshot.model === "gpt-6-luna"
          ? "gpt-6-sol"
          : "gpt-6-luna";
      }
      if (failure === "version_suffix") response.model += "-unknown-snapshot";
      if (failure === "missing_input") {
        Reflect.deleteProperty(response.moderation, "input");
      }
      if (failure === "missing_output") {
        Reflect.deleteProperty(response.moderation, "output");
      }
      if (failure === "flagged") {
        response.moderation.input.flagged = true;
        response.moderation.input.categories.sexual = true;
      }
      if (failure === "incomplete") response.status = "incomplete";
      if (failure === "tool_output") response.output[0].type = "function_call";
      let calls = 0;
      const prepared = createAIExecution(
        createOpenAIPhotoModelEvaluationAdapter(
          "synthetic-key",
          (url, init) => {
            calls++;
            assertEquals(url, OPENAI_RESPONSES_URL);
            const body = JSON.parse(String(init?.body));
            assertEquals(body.model, snapshot.model);
            assertEquals(body.moderation.model, snapshot.moderationModel);
            assertEquals(body.reasoning, { effort: "low" });
            assertEquals(body.tools, []);
            if (failure === "http_401") {
              return Promise.resolve(new Response(null, { status: 401 }));
            }
            if (failure === "http_500") {
              return Promise.resolve(new Response(null, { status: 500 }));
            }
            return Promise.resolve(Response.json(response));
          },
        ),
        request,
        snapshot,
      );
      assertEquals(calls, 0);
      const result = await prepared.invoke();
      assertEquals(
        result.kind,
        failure === null
          ? "draft"
          : failure === "flagged"
          ? "refusal"
          : failure === "http_401"
          ? "operational_failure"
          : failure === "http_500"
          ? "unknown_execution"
          : "invalid_output",
      );
      if (failure === null) {
        assertEquals(result.returnedModel, snapshot.model);
        assertEquals(result.serviceTier, "default");
        assertEquals(result.usage?.outputTokens, 40);
        assertEquals(result.usage?.candidateTokens, 30);
        assertEquals(result.usage?.thinkingTokens, 10);
        assertEquals(result.mediaSafety?.disposition, "allowed");
      }
      if (failure !== null) assertEquals("draft" in result, false);
      await assertRejects(
        () => prepared.invoke(),
        Error,
        "ai_attempt_already_invoked",
      );
      assertEquals(calls, 1);
    }
  }
});

Deno.test("Luna evidence-limit candidate changes only two instruction lines and never admits production", () => {
  const request = openAIPhotoRequestFixture();
  const original = openAIPhotoModelSnapshot(
    request,
    "openai_photo_luna_low_v1",
  );
  const baseline = buildOpenAIPhotoModelRequestParameters(request, original);
  const snapshot = openAIPhotoModelSnapshot(
    request,
    OPENAI_LUNA_EVIDENCE_LIMITS_PROFILE,
  );
  const candidate = buildOpenAIPhotoModelRequestParameters(request, snapshot);
  assertEquals(snapshot, {
    ...original,
    profile: OPENAI_LUNA_EVIDENCE_LIMITS_PROFILE,
    prompt: OPENAI_LUNA_EVIDENCE_LIMITS_PROMPT,
  });
  assertEquals(candidate, {
    ...baseline,
    instructions: openAILunaEvidenceLimitsInstructions(baseline.instructions),
  });
  const before = baseline.instructions.split("\n"),
    after = candidate.instructions.split("\n");
  assertEquals(after.length, before.length);
  const changed = before.filter((line, i) => line !== after[i]);
  assertEquals(changed.length, 2);
  assert(changed[0].startsWith("- **Geological Exceptions:**"));
  assert(changed[1].startsWith("1. **Nomenclature:**"));
  assertEquals(isOpenAIProfile(snapshot.profile), false);
  assertThrows(() =>
    prepareMultimodalResultPolicy(snapshot as unknown as AIAttemptSnapshot)
  );
  assertThrows(() =>
    buildOpenAIPhotoRequestParameters(
      request,
      snapshot as unknown as ReturnType<typeof openAIPhotoSnapshot>,
    )
  );
  for (
    const delta of [{ prompt: original.prompt }, { model: "gpt-6-sol" }, {
      profile: original.profile,
    }]
  ) {
    assertThrows(() =>
      buildOpenAIPhotoModelRequestParameters(
        request,
        { ...snapshot, ...delta } as typeof snapshot,
      )
    );
  }
  assertThrows(() =>
    openAIPhotoModelSnapshot(
      openAITextFixture(),
      OPENAI_LUNA_EVIDENCE_LIMITS_PROFILE,
    )
  );
});

Deno.test("Luna evidence-limit projection rejects changed or duplicated anchors without modifying the shared prompt", () => {
  const request = openAIPhotoRequestFixture();
  const baseline =
    buildOpenAIRequestParameters(request, openAIEvaluationSnapshot(request))
      .instructions;
  for (
    const changed of [
      baseline.replace("if identifiable.", "if certain."),
      baseline.replace(
        "maximally specific in Title Case.",
        "specific in Title Case.",
      ),
      baseline + "\n" + baseline,
      openAILunaEvidenceLimitsInstructions(baseline),
    ]
  ) {
    assertThrows(
      () => openAILunaEvidenceLimitsInstructions(changed),
      Error,
      "openai_prompt_revision_mismatch",
    );
  }
  assertEquals(
    buildOpenAIRequestParameters(request, openAIEvaluationSnapshot(request))
      .instructions,
    baseline,
  );
});

Deno.test("Luna evidence-limit prompt identity is pinned independently of the unchanged schema", async () => {
  const request = openAIPhotoRequestFixture();
  const candidate = buildOpenAIPhotoModelRequestParameters(
    request,
    openAIPhotoModelSnapshot(request, OPENAI_LUNA_EVIDENCE_LIMITS_PROFILE),
  );
  const digest = Array.from(
    new Uint8Array(
      await crypto.subtle.digest(
        "SHA-256",
        new TextEncoder().encode(candidate.instructions),
      ),
    ),
  )
    .map((n) => n.toString(16).padStart(2, "0")).join("");
  assertEquals(digest, OPENAI_LUNA_EVIDENCE_LIMITS_PROMPT_DIGEST);
  assertEquals(
    candidate.text.format.schema,
    buildOpenAIRequestParameters(request, openAIEvaluationSnapshot(request))
      .text.format.schema,
  );
});
