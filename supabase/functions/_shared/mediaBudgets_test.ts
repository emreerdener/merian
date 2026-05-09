import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.224.0/testing/asserts.ts";
import mediaStagingContract from "../../../docs/contracts/media-staging-upload-manifest.json" with {
  type: "json",
};

import {
  decodeInlineAudioBase64,
  MEDIA_BUDGET_ERRORS,
  MEDIA_BUDGETS,
  readResponseArrayBufferWithinBudget,
  STAGING_ALLOWED_CONTENT_TYPES,
  validateAudioClipCount,
  validateRequestContentLength,
  validateStagingObjectKey,
} from "./mediaBudgets.ts";

interface MediaStagingUploadManifestContract {
  maxFilesPerRequest: number;
  maxImageBytes: number;
  maxAudioBytes: number;
  maxAudioFiles: number;
  imageContentTypes: string[];
  audioContentTypes: string[];
}

Deno.test("media budgets match the documented staging upload contract", () => {
  const contract = mediaStagingContract as MediaStagingUploadManifestContract;

  assertEquals(MEDIA_BUDGETS.maxStagingFiles, contract.maxFilesPerRequest);
  assertEquals(MEDIA_BUDGETS.maxImageRawBytes, contract.maxImageBytes);
  assertEquals(MEDIA_BUDGETS.maxAudioRawBytes, contract.maxAudioBytes);
  assertEquals(MEDIA_BUDGETS.maxStagedAudioFiles, contract.maxAudioFiles);
  assertEquals(STAGING_ALLOWED_CONTENT_TYPES.image, contract.imageContentTypes);
  assertEquals(STAGING_ALLOWED_CONTENT_TYPES.audio, contract.audioContentTypes);
});

Deno.test("validateAudioClipCount rejects mixed clip sets above the cap", () => {
  assertEquals(validateAudioClipCount(1, 1), null);
  assertEquals(validateAudioClipCount(2, 1), {
    status: 413,
    message: MEDIA_BUDGET_ERRORS.tooManyAudioClips,
  });
});

Deno.test("decodeInlineAudioBase64 rejects oversize before decode and malformed data", () => {
  assertEquals(
    decodeInlineAudioBase64("A".repeat(MEDIA_BUDGETS.maxAudioBase64Chars + 1))
      .error,
    { status: 413, message: MEDIA_BUDGET_ERRORS.audioTooLarge },
  );
  assertEquals(decodeInlineAudioBase64("not-valid-base64%%%").error, {
    status: 400,
    message: MEDIA_BUDGET_ERRORS.invalidAudioBase64,
  });
});

Deno.test("decodeInlineAudioBase64 returns exact buffers for valid audio data", () => {
  const decoded = decodeInlineAudioBase64("AQIDBA==");
  assert(decoded.buffer);
  assertEquals(decoded.buffer.byteLength, 4);
});

Deno.test("readResponseArrayBufferWithinBudget rejects Content-Length before allocation", async () => {
  const response = new Response("small body", {
    headers: {
      "content-length": String(MEDIA_BUDGETS.maxAudioRawBytes + 1),
    },
  });

  const result = await readResponseArrayBufferWithinBudget(
    response,
    MEDIA_BUDGETS.maxAudioRawBytes,
    MEDIA_BUDGET_ERRORS.audioTooLarge,
  );

  assertEquals(result.error, {
    status: 413,
    message: MEDIA_BUDGET_ERRORS.audioTooLarge,
  });
});

Deno.test("validateRequestContentLength rejects media JSON before body parsing", () => {
  const request = new Request("https://example.test/identify", {
    method: "POST",
    headers: {
      "content-length": String(MEDIA_BUDGETS.maxIdentifyJsonBodyBytes + 1),
    },
  });

  assertEquals(
    validateRequestContentLength(
      request,
      MEDIA_BUDGETS.maxIdentifyJsonBodyBytes,
    ),
    {
      status: 413,
      message: MEDIA_BUDGET_ERRORS.requestBodyTooLarge,
    },
  );
});

Deno.test("validateStagingObjectKey catches traversal and user-boundary drift", () => {
  assertEquals(
    validateStagingObjectKey("staging/user-1/audio.wav", "user-1"),
    null,
  );
  assertEquals(
    validateStagingObjectKey("staging/user-1/../audio.wav", "user-1"),
    "path_traversal",
  );
  assertEquals(
    validateStagingObjectKey("staging/other-user/audio.wav", "user-1"),
    "wrong_user",
  );
});
