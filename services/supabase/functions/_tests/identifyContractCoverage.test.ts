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
