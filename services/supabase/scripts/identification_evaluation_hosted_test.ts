import { assert, assertEquals, assertRejects, assertThrows } from "@std/assert";
import {
  bundleUrl,
  claimKey,
  makeHostedClaim,
  parseHostedSpec,
} from "./identification_evaluation/hosted.ts";
import {
  downloadHostedBundle,
  HostedR2,
  r2Endpoint,
} from "./identification_evaluation/hostedStorage.ts";
import { hostedSpecFixture } from "./identification_evaluation/testing/hostedFixture.ts";

Deno.test("hosted review rejects widened providers, mutable source, expiry and missing public permission", async () => {
  const spec = await hostedSpecFixture();
  assertEquals(parseHostedSpec(spec), spec);
  const changes = [
    { ...spec, source: { ...spec.source, dirty: true } },
    { ...spec, publicRelease: { ...spec.publicRelease, approved: false } },
    { ...spec, budgetUsd: 30 },
    { ...spec, runs: spec.runs.toReversed() },
    { ...spec, experimentId: "../other" },
    {
      ...spec,
      window: {
        ...spec.window,
        expiresAt: new Date(Date.parse(spec.window.startsAt) + 86400000)
          .toISOString(),
      },
    },
    {
      ...spec,
      runs: spec.runs.map((r) => ({
        ...r,
        review: { ...r.review, inputPermissionApproved: false },
      })),
    },
    { ...spec, credential: "invented-extra-field" },
  ];
  for (const changed of changes) assertThrows(() => parseHostedSpec(changed));
  assertThrows(() => bundleUrl("../private"));
  assertThrows(() => claimKey("../avatars"));
  assertThrows(() => r2Endpoint("other.example/path"));
});

Deno.test("hosted R2 claim uses one exclusive write and authenticated readback; racing rerun cannot win", async () => {
  const claim = makeHostedClaim(
    await hostedSpecFixture(),
    "4".repeat(64),
    "123",
    "1",
  );
  let stored: string | null = null;
  const calls: string[] = [];
  const transport = async (r: Request) => {
    assert(
      r.url.startsWith(
        `https://${
          "a".repeat(32)
        }.r2.cloudflarestorage.com/merian/benchmarks/identification/`,
      ),
    );
    assertEquals(r.redirect, "error");
    assert(r.headers.has("authorization"));
    calls.push(r.method);
    if (r.method === "PUT") {
      assertEquals(r.headers.get("if-none-match"), "*");
      if (stored !== null) return new Response(null, { status: 412 });
      // Reserve before awaiting body, like an atomic object-store conditional put.
      stored = "pending";
      stored = await r.text();
      return new Response(null, { status: 200 });
    }
    return new Response(stored, { status: 200 });
  };
  const store = new HostedR2(
    "a".repeat(32),
    "synthetic-access",
    "synthetic-signing-material",
    transport,
  );
  const results = await Promise.allSettled([
    store.claim(claim),
    store.claim(claim),
  ]);
  assertEquals(results.filter((r) => r.status === "fulfilled").length, 1);
  assertEquals(calls.filter((v) => v === "PUT").length, 2);
  assertEquals(calls.filter((v) => v === "GET").length, 1);
  assertEquals(JSON.parse(stored!), claim);
  await assertRejects(() => store.claim({ ...claim, githubRunId: "124" }));
});

Deno.test("ambiguous R2 write, 429 and failed readback never retry or yield a claim", async () => {
  const claim = makeHostedClaim(
    await hostedSpecFixture(),
    "4".repeat(64),
    "123",
    "1",
  );
  for (const failure of ["throw", "rate", "readback"] as const) {
    let count = 0;
    const store = new HostedR2(
      "a".repeat(32),
      "synthetic-access",
      "synthetic-signing-material",
      () => {
        count++;
        if (failure === "throw") throw new Error("invented transport failure");
        return Promise.resolve(
          new Response(null, {
            status: failure === "rate" ? 429 : count === 1 ? 200 : 404,
          }),
        );
      },
    );
    await assertRejects(() => store.claim(claim));
    assertEquals(count, failure === "readback" ? 2 : 1);
  }
});

Deno.test("public bundle download is fixed-host, bounded and never follows redirects", async () => {
  const digest = "5".repeat(64);
  const bytes = await downloadHostedBundle(digest, (r) => {
    assertEquals(r.url, bundleUrl(digest));
    assertEquals(r.redirect, "error");
    assertEquals(r.headers.has("authorization"), false);
    return Promise.resolve(new Response("{}"));
  });
  assertEquals(new TextDecoder().decode(bytes), "{}");
  await assertRejects(() =>
    downloadHostedBundle(
      digest,
      () =>
        Promise.resolve(
          new Response(null, {
            status: 302,
            headers: { location: "https://other.example" },
          }),
        ),
    )
  );
});

Deno.test("summary publication requires the owning remote claim and never overwrites", async () => {
  const claim = makeHostedClaim(
    await hostedSpecFixture(),
    "4".repeat(64),
    "123",
    "1",
  );
  let calls = 0;
  const store = new HostedR2(
    "a".repeat(32),
    "synthetic-access",
    "synthetic-signing-material",
    () => {
      calls++;
      return Promise.resolve(
        new Response(JSON.stringify({ ...claim, githubRunId: "999" })),
      );
    },
  );
  await assertRejects(() => store.publish(claim, {}));
  assertEquals(calls, 1);
});

Deno.test("hosted workflow keeps manual exact-source, environment, durable claim and credential isolation", async () => {
  const workflow = await Deno.readTextFile(
    new URL(
      "../../../.github/workflows/identification-provider-comparison.yml",
      import.meta.url,
    ),
  );
  const shell = await Deno.readTextFile(
    new URL("./run_hosted_identification.sh", import.meta.url),
  );
  for (
    const part of [
      "workflow_dispatch:",
      "environment: Production",
      "persist-credentials: false",
      "cancel-in-progress: false",
      "refs/heads/main",
      "refs/remotes/origin/main",
      "supabase-candidate-validation.yml",
      "secrets.NATUREBOOK_OPENAI_API_KEY",
      "secrets.GEMINI_PAID_API_KEY",
      "identification-public/summary.json",
    ]
  ) assert(workflow.includes(part), part);
  assert(
    workflow.indexOf("run_hosted_identification.sh claim") <
      workflow.indexOf("run_hosted_identification.sh run-gemini"),
  );
  assert(
    workflow.indexOf("run_hosted_identification.sh run-gemini") <
      workflow.indexOf("run_hosted_identification.sh run-openai"),
  );
  const steps = workflow.split("\n      - name:");
  for (const step of steps) {
    const keys = [
      "secrets.NATUREBOOK_OPENAI_API_KEY",
      "secrets.GEMINI_PAID_API_KEY",
      "secrets.R2_SECRET_ACCESS_KEY",
    ].filter((k) => step.includes(k));
    assert(keys.length <= 1, "One recipient credential per step");
    if (keys.some((k) => k.includes("OPENAI") || k.includes("GEMINI"))) {
      assert(
        step.includes("if: inputs.operation == 'compare'"),
        "Public preflight must never bind a Production provider credential",
      );
    }
  }
  assert(!workflow.includes("secrets.OPENAI_API_KEY"));
  assert(!workflow.includes("SUPABASE_ACCESS_TOKEN"));
  for (
    const part of [
      "--cached-only",
      "--allow-net=api.openai.com:443",
      "--allow-net=generativelanguage.googleapis.com:443",
      "--deny-env='SUPABASE_*,R2_*,GOOGLE_*,GEMINI_*,WS_*,OPENAI_API_KEY'",
      "assert-complete",
      "hosted-claim.json",
    ]
  ) assert(shell.includes(part), part);
});
