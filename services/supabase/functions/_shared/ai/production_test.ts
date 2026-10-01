import { assert, assertEquals, assertRejects, assertThrows } from "@std/assert";
import type { AIRequest, UserRequestAuthority } from "./contracts.ts";
import { prepareAIExecution } from "./production.ts";
import { OPENAI_RESPONSES_URL } from "./openai.ts";
import {
  buildOpenAIPhotoRequestParameters,
  OPENAI_PHOTO_MODERATION_MODEL,
  openAIPhotoSnapshot,
} from "./openaiPhoto.ts";
import {
  openAIPhotoModerationFixture,
  openAIPhotoRequestFixture,
  openAIResponseFixture,
  openAITextFixture,
} from "./testing/openaiFixtures.ts";

function photoAuthority(): UserRequestAuthority {
  return {
    kind: "user_request",
    userId: "synthetic-owner",
    permission: "openai",
    operation: "scan_identification",
    reservation: {
      assignment: {
        inputProfile: "multimodal_photo_v1",
        provider: "openai",
        binding: "openai_photo_v1",
        permission: "openai",
      },
      id: "synthetic-reservation",
      requestId: "synthetic-request",
      attemptCount: 1,
      policyVersion: 1,
      model: "gpt-6-sol",
      tier: { effective_tier: "pro" },
    },
  };
}

Deno.test({
  name:
    "production dispatches one admitted OpenAI photo request and keeps safety failures closed",
  permissions: { env: ["NATUREBOOK_OPENAI_API_KEY"], net: false },
  async fn() {
    const key = Deno.env.get("NATUREBOOK_OPENAI_API_KEY");
    const originalFetch = globalThis.fetch;
    let calls = 0;
    let response: Record<string, unknown> = {};
    let body: Record<string, unknown> | undefined;
    try {
      Deno.env.delete("NATUREBOOK_OPENAI_API_KEY");
      assertThrows(
        () => prepareAIExecution(openAIPhotoRequestFixture(), photoAuthority()),
        Error,
        "openai_credential_invalid",
      );
      Deno.env.set("NATUREBOOK_OPENAI_API_KEY", "synthetic-photo-key");
      globalThis.fetch = (input, init) => {
        calls++;
        assertEquals(String(input), OPENAI_RESPONSES_URL);
        assertEquals(init?.method, "POST");
        assertEquals(init?.redirect, "error");
        assert(init?.signal instanceof AbortSignal);
        body = JSON.parse(String(init?.body));
        return Promise.resolve(Response.json(response));
      };
      const request = openAIPhotoRequestFixture();
      const prepared = prepareAIExecution(request, photoAuthority());
      assertEquals(calls, 0);
      assertEquals(prepared.snapshot.provider, "openai");
      assertEquals(prepared.snapshot.binding, "openai_photo_v1");
      assertEquals(
        prepared.snapshot.prompt,
        "openai_identify_vision_confidence_v1",
      );
      assertEquals(prepared.snapshot.schema, "merian_openai_identify_v1");
      const freeAuthority = photoAuthority();
      assertEquals(
        prepareAIExecution(request, {
          ...freeAuthority,
          reservation: {
            ...freeAuthority.reservation,
            tier: { effective_tier: "free" },
          },
        }).snapshot,
        prepared.snapshot,
      );
      response = {
        ...openAIResponseFixture(),
        moderation: openAIPhotoModerationFixture(),
      };
      const allowed = await prepared.invoke();
      assertEquals(allowed.kind, "draft");
      assertEquals(allowed.mediaSafety?.disposition, "allowed");
      assertEquals(allowed.execution.model, "gpt-6-sol");
      assertEquals(body?.moderation, { model: OPENAI_PHOTO_MODERATION_MODEL });
      assertEquals(
        body,
        JSON.parse(
          JSON.stringify(
            buildOpenAIPhotoRequestParameters(
              request,
              openAIPhotoSnapshot(request, 1),
            ),
          ),
        ),
      );
      assert(JSON.stringify(body).includes("An invented observation note."));
      assert(JSON.stringify(body).includes("data:image/png;base64,AQID"));
      await assertRejects(
        () => prepared.invoke(),
        Error,
        "ai_attempt_already_invoked",
      );
      assertEquals(calls, 1);

      response = openAIResponseFixture();
      const unavailable = await prepareAIExecution(request, photoAuthority())
        .invoke();
      assertEquals(unavailable.kind, "invalid_output");
      assertEquals(unavailable.mediaSafety?.disposition, "unavailable");
      assert(!("draft" in unavailable));

      const moderation = openAIPhotoModerationFixture();
      moderation.input.flagged = true;
      moderation.input.categories.violence = true;
      response = { ...openAIResponseFixture(), moderation };
      const refused = await prepareAIExecution(request, photoAuthority())
        .invoke();
      assertEquals(refused.kind, "refusal");
      assert(!("draft" in refused));
      assertEquals(calls, 3);

      for (
        const unsupported of [
          openAITextFixture(),
          { ...request, capture: { ...request.capture, hasVideo: true } },
          {
            ...request,
            evidence: [{
              kind: "audio",
              order: 0,
              mimeType: "audio/wav",
              data: "AQID",
            }],
          },
        ] as AIRequest[]
      ) {
        assertThrows(
          () => prepareAIExecution(unsupported, photoAuthority()),
          Error,
        );
      }
      assertThrows(
        () =>
          prepareAIExecution(request, {
            ...photoAuthority(),
            permission: "google_gemini",
          }),
        Error,
        "ai_authority_mismatch",
      );
      assertEquals(calls, 3);
    } finally {
      globalThis.fetch = originalFetch;
      if (key === undefined) Deno.env.delete("NATUREBOOK_OPENAI_API_KEY");
      else Deno.env.set("NATUREBOOK_OPENAI_API_KEY", key);
    }
  },
});
