import { assert, assertEquals, assertRejects, assertThrows } from "@std/assert";
import vectors from "./fixtures/admission-v1.json" with { type: "json" };
import catalog from "./configuration-assets-v1.json" with { type: "json" };
import schema from "./input-schema-v1.json" with { type: "json" };
import {
  initialCanonicalText,
  initialDecimal,
  initialDigest,
  parseInitialCanonicalText,
} from "./canonical.ts";
import { validateInitialInput } from "./schema.ts";
import { assertInitialSemantics, initialInputProfile } from "./semantics.ts";
import { prepareInitialAdmission } from "./preparation.ts";
import { verifyInitialConfigurationAssets } from "./configuration.ts";
import { InitialAnalysisLifecycleRepository } from "./repository.ts";

for (const vector of vectors.valid) {
  Deno.test(`IC-1 codec - ${vector.name}`, async () => {
    assertEquals(validateInitialInput(vector.input), vector.canonical);
    assertEquals(await initialDigest("input", vector.canonical), vector.digest);
    assertInitialSemantics(vector.input);
    assertEquals(initialInputProfile(vector.input), vector.profile);
  });
}
for (const vector of vectors.invalid) {
  Deno.test(`IC-1 rejects - ${vector.name}`, () => {
    assertThrows(() =>
      "canonical" in vector
        ? validateInitialInput(parseInitialCanonicalText(vector.canonical!))
        : validateInitialInput(vector.input)
    );
  });
}
Deno.test("IC-1 codec rejects coercion, getters, unsafe numbers and duplicate keys", () => {
  for (
    const value of [
      NaN,
      Infinity,
      -0,
      1.5,
      9007199254740992,
      undefined,
      () => 1,
      new Date(),
      [undefined],
      Array(1),
      Object.create(null),
      { toJSON: () => ({}) },
      Object.defineProperty({}, "field", {
        enumerable: true,
        get() {
          throw new Error("getter invoked");
        },
      }),
      Object.defineProperty([], "0", {
        enumerable: true,
        get() {
          throw new Error("getter invoked");
        },
      }),
    ]
  ) assertThrows(() => initialCanonicalText(value));
  assertEquals(initialCanonicalText({ z: "é", a: "é" }), '{"a":"é","z":"é"}');
  assertEquals(initialDecimal(1e-7), "0.0000001");
  assertEquals(initialDecimal(1e21), "1000000000000000000000");
  assertEquals(initialDecimal(-0), "0");
});
Deno.test("IC-1 fixture schema/catalog exactly match reviewed migration literals", async () => {
  const sql = await Deno.readTextFile(
    new URL(
      "../../../migrations/20261011070945_prepare_initial_analysis_admission.sql",
      import.meta.url,
    ),
  );
  const schemaLiteral =
    sql.split("AS $schema$\n SELECT '")[1].split("'::JSONB;")[0];
  assertEquals(JSON.parse(schemaLiteral), schema);
  const assetLiteral = sql.split(
    "INSERT INTO internal.initial_analysis_configuration_assets(digest,manifest) VALUES('",
  )[1].split("'::JSONB);")[0];
  assertEquals(assetLiteral.split("','")[0], catalog.digest);
  assertEquals(
    JSON.parse(assetLiteral.slice(assetLiteral.indexOf("','") + 3)),
    catalog.manifest,
  );
  assertEquals(
    await initialDigest("assets", initialCanonicalText(catalog.manifest)),
    catalog.digest,
  );
});
const repoRoot = new URL("../../../../../", import.meta.url);
const readAsset = async (path: string) =>
  await Deno.readFile(new URL(path, repoRoot));
Deno.test("IC-1 pinned configuration source hashes hold on missing, changed or other manifest", async () => {
  await verifyInitialConfigurationAssets(readAsset);
  await assertRejects(
    () =>
      verifyInitialConfigurationAssets(() => Promise.resolve(new Uint8Array())),
    Error,
    "initial_analysis_configuration_unavailable",
  );
  await assertRejects(
    () =>
      verifyInitialConfigurationAssets(() =>
        Promise.reject(new Error("missing"))
      ),
    Error,
    "initial_analysis_configuration_unavailable",
  );
  await assertRejects(
    () => verifyInitialConfigurationAssets(readAsset, "f".repeat(64)),
    Error,
    "initial_analysis_configuration_unavailable",
  );
});
Deno.test("IC-1 preparation preserves exact text and cannot accept media digests without bytes", async () => {
  const initial = await prepareInitialAdmission(vectors.valid[0].input);
  assertEquals(initial.canonicalInput, vectors.valid[0].canonical);
  await assertRejects(() => prepareInitialAdmission(vectors.valid[1].input));
  const changed = structuredClone(vectors.valid[0].input);
  changed.ordered_descriptions[0] += " changed";
  assert(
    (await prepareInitialAdmission(changed)).submissionDigest !==
      initial.submissionDigest,
  );
});
Deno.test("IC-1 unknown admission performs one write and recovery cannot allocate or dispatch", async () => {
  const initial = await prepareInitialAdmission(vectors.valid[0].input);
  const owner = "00000000-0000-4000-8000-00000000a001",
    scan = "00000000-0000-4000-8000-00000000a002";
  let calls = 0;
  const requests: Record<string, unknown>[] = [];
  const repository = new InitialAnalysisLifecycleRepository({
    rpc(name, args) {
      assertEquals(name, "admit_initial_analysis");
      calls++;
      requests.push(args);
      return Promise.reject(new Error("lost acknowledgement"));
    },
  }, readAsset);
  assertEquals(await repository.admit(owner, scan, initial, "a".repeat(64)), {
    outcome: "unknown",
    reason: "write_outcome_unknown",
  });
  assertEquals(calls, 1);
  assertEquals(
    await repository.recoverAdmission(
      owner,
      scan,
      initial.canonicalInput,
      initial.submissionDigest,
    ),
    { outcome: "unknown", reason: "write_outcome_unknown" },
  );
  assertEquals(calls, 2);
  assertEquals(requests[1].p_assets_digest, null);
  assertEquals(requests[1].p_ip_hash, null);
  assertEquals(requests[0].p_canonical_input, requests[1].p_canonical_input);
  await assertRejects(() =>
    repository.admit(owner, scan, { ...initial }, "a".repeat(64))
  );
});
Deno.test("IC-1 recovery returns only exact saved binding; malformed/cross-owner/fresh responses stay unknown", async () => {
  const v = vectors.valid[0];
  const owner = "00000000-0000-4000-8000-00000000a001",
    scan = "00000000-0000-4000-8000-00000000a002";
  const binding = {
    version: 1,
    owner_id: owner,
    scan_id: scan,
    route: v.input.route,
    submission_digest: v.digest,
    configuration_digest: "b".repeat(64),
    funding_digest: "c".repeat(64),
    descriptions_digest: "d".repeat(64),
    funding_binding_id: "00000000-0000-4000-8000-00000000a003",
    assets_digest: "e".repeat(64),
  };
  for (
    const data of [
      { outcome: "replay", binding },
      { outcome: "admitted", binding },
      { outcome: "replay", binding: { ...binding, owner_id: scan } },
      { outcome: "replay", binding, may_dispatch: true },
    ]
  ) {
    const repository = new InitialAnalysisLifecycleRepository({
      rpc() {
        return Promise.resolve({ data, error: null });
      },
    }, () => {
      throw new Error("recovery must not resolve current assets");
    });
    const result = await repository.recoverAdmission(
      owner,
      scan,
      v.canonical,
      v.digest,
    );
    assertEquals(
      result.outcome,
      data.outcome === "replay" && data.binding.owner_id === owner &&
        !("may_dispatch" in data)
        ? "replay"
        : "unknown",
    );
  }
});

Deno.test("IC-1 preparation binds copied photo bytes before asynchronous hashing", async () => {
  const input = structuredClone(
    vectors.valid.find((v) => v.profile === "vision_compat_v1")!.input,
  );
  const source = new Uint8Array([137, 80, 78, 71, 13, 10, 26, 10]);
  const hash = Array.from(
    new Uint8Array(await crypto.subtle.digest("SHA-256", source)),
    (v) => v.toString(16).padStart(2, "0"),
  ).join("");
  input.media[0].byte_count = input.media[0].source_byte_count = source.length;
  input.media[0].sha256 = input.media[0].source_sha256 = hash;
  const expected = validateInitialInput(input);
  const pending = prepareInitialAdmission(input, [source]);
  source.fill(0);
  input.media[0].sha256 = "0".repeat(64);
  assertEquals((await pending).canonicalInput, expected);
  await assertRejects(() =>
    prepareInitialAdmission(JSON.parse(expected), [source])
  );
});
Deno.test("IC-1 preparation recomputes WAV output and rejects substituted derived hash", async () => {
  const { encodeWav16 } = await import("../../audio-spec/wav.ts");
  const { processWavBuffer } = await import("../audioProcessing.ts");
  const { decodeBase64 } = await import("../encoding.ts");
  const input = structuredClone(
    vectors.valid.find((v) => v.profile === "multimodal_audio_v1")!.input,
  );
  const source = encodeWav16(new Float32Array(44100).fill(0.25), 44100);
  const output = decodeBase64(
    processWavBuffer(source.buffer as ArrayBuffer, 16000).base64Audio,
  );
  const hash = async (bytes: Uint8Array) =>
    Array.from(
      new Uint8Array(
        await crypto.subtle.digest("SHA-256", new Uint8Array(bytes)),
      ),
      (v) => v.toString(16).padStart(2, "0"),
    ).join("");
  input.media[0].source_byte_count = source.length;
  input.media[0].source_sha256 = await hash(source);
  input.media[0].byte_count = output.length;
  input.media[0].sha256 = await hash(output);
  assertEquals(
    (await prepareInitialAdmission(input, [source])).canonicalInput,
    validateInitialInput(input),
  );
  input.media[0].sha256 = input.media[0].source_sha256;
  await assertRejects(() => prepareInitialAdmission(input, [source]));
});
