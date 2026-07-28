import {
  assert,
  assertStringIncludes,
} from "https://deno.land/std@0.224.0/testing/asserts.ts";

const routes = [
  {
    path: "../identify/index.ts",
    providerParser: "parseMerianIdentification",
    finalizationBoundary: "await compatibilityLedger.mark(",
  },
  {
    path: "../identify-multimodal/index.ts",
    providerParser: "parseMerianIdentification",
    finalizationBoundary: "const requireDurableVideo",
  },
  {
    path: "../identify-describe/index.ts",
    providerParser: "parseDescribeIdentification",
    finalizationBoundary: "await compatibilityLedger.mark(",
  },
] as const;

const scanProducerRoutes = [
  "../identify/index.ts",
  "../identify-multimodal/index.ts",
  "../identify-describe/index.ts",
  "../audio-spec/index.ts",
] as const;

Deno.test("every Identify route validates provider and final wire values before persistence", async () => {
  for (const route of routes) {
    const source = await Deno.readTextFile(
      new URL(route.path, import.meta.url),
    );
    const providerParse = source.indexOf(
      `${route.providerParser}(`,
    );
    const syntaxExtraction = source.indexOf(
      "extractJson<unknown>(responseText)",
      providerParse,
    );
    const payloadAssembly = source.indexOf(
      "payloadReadyForClient",
      syntaxExtraction,
    );
    const finalParse = source.indexOf(
      "parseIdentifySuccessEnvelope({",
      payloadAssembly,
    );
    const finalizationBoundary = source.indexOf(
      route.finalizationBoundary,
      finalParse,
    );

    assert(providerParse >= 0, `${route.path} bypasses its provider parser`);
    assert(
      syntaxExtraction > providerParse,
      `${route.path} must validate the unknown JSON value returned by extraction`,
    );
    assert(
      payloadAssembly > syntaxExtraction,
      `${route.path} assembles a payload before validating provider output`,
    );
    assert(
      finalParse > payloadAssembly,
      `${route.path} bypasses complete final-envelope validation`,
    );
    assert(
      finalizationBoundary > finalParse,
      `${route.path} persists/finalizes before the final wire parse`,
    );

    const finalValidationTail = source.slice(finalParse);
    assertStringIncludes(
      finalValidationTail,
      "await quotaLease.fail();",
      `${route.path} must settle a charged invalid response as failed`,
    );
    assertStringIncludes(
      finalValidationTail,
      'code: "identify_response_invalid"',
      `${route.path} must expose only the stable final-contract error code`,
    );
    assert(
      /jsonResponse\s*\(\s*responseEnvelope/.test(finalValidationTail),
      `${route.path} must return the parsed envelope rather than the source object`,
    );
    assert(
      !finalValidationTail.includes(
        "jsonResponse({ success: true, data: payloadReadyForClient",
      ),
      `${route.path} still returns an unparsed source payload`,
    );
  }
});

Deno.test("malformed provider output remains retryable across every scan producer", async () => {
  for (const path of scanProducerRoutes) {
    const source = (await Deno.readTextFile(new URL(path, import.meta.url)))
      .replaceAll(/\s+/g, " ");
    assert(
      /error: "Processing Error: Malformed AI response[.]",? }?,? 503/.test(
        source,
      ),
      `${path} must return HTTP 503 for malformed paid-provider output`,
    );
    assert(
      !/error: "Processing Error: Malformed AI response[.]",? }?,? 422/.test(
        source,
      ),
      `${path} must not strand the offline queue with HTTP 422`,
    );
  }
});

Deno.test("every scan producer preserves quota and media while DB persistence is ambiguous", async () => {
  for (const path of scanProducerRoutes) {
    const source = await Deno.readTextFile(new URL(path, import.meta.url));
    const ambiguityFence = source.lastIndexOf(
      "const persistenceOutcomeUnknown",
    );
    assert(
      ambiguityFence >= 0,
      `${path} does not classify ambiguous scan persistence`,
    );

    const failureTail = source.slice(ambiguityFence);
    const quotaFailure = failureTail.indexOf("quotaLease.fail()");
    const quotaGuard = failureTail.lastIndexOf(
      "if (!persistenceOutcomeUnknown)",
      quotaFailure,
    );
    assert(
      quotaFailure >= 0 && quotaGuard >= 0 && quotaGuard < quotaFailure,
      `${path} may release committed quota while the scan write is ambiguous`,
    );

    let destructiveDelete = failureTail.indexOf("deleteR2ObjectIfPresent(");
    while (destructiveDelete >= 0) {
      const guardWindow = failureTail.slice(
        Math.max(0, destructiveDelete - 5_000),
        destructiveDelete,
      );
      assert(
        guardWindow.includes("!persistenceOutcomeUnknown"),
        `${path} may delete media while the scan write is ambiguous`,
      );
      destructiveDelete = failureTail.indexOf(
        "deleteR2ObjectIfPresent(",
        destructiveDelete + 1,
      );
    }

    const stagedAssetFailure = failureTail.indexOf(
      "markUploadAssetsFailedBestEffort(",
    );
    if (stagedAssetFailure >= 0) {
      const guardWindow = failureTail.slice(
        Math.max(0, stagedAssetFailure - 2_000),
        stagedAssetFailure,
      );
      assert(
        guardWindow.includes("if (!persistenceOutcomeUnknown)"),
        `${path} may retire staged assets while the scan write is ambiguous`,
      );
    }
  }
});

Deno.test("every scan-row adapter uses the exact-owner persistence boundary", async () => {
  const databaseAdapters = [
    "../_shared/identify/db.ts",
    "../identify-describe/db.ts",
    "../audio-spec/db.ts",
  ] as const;

  for (const path of databaseAdapters) {
    const source = await Deno.readTextFile(new URL(path, import.meta.url));
    assertStringIncludes(
      source,
      "await persistOwnedScanRow({",
      `${path} bypasses ambiguous-write reconciliation`,
    );
    assertStringIncludes(
      source,
      "scanId: row.id",
      `${path} does not verify the exact scan ID`,
    );
    assertStringIncludes(
      source,
      "userId: row.user_id",
      `${path} does not verify the exact scan owner`,
    );
  }
});
