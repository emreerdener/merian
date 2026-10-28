import { assertEquals, assertNotEquals, assertThrows } from "@std/assert";
import { initialCanonicalText } from "./canonical.ts";
import { initialCpmPhotoContentDigest } from "./cpmPhotoContent.ts";
import {
  initialCpmPhotoCandidateDigest,
  parseInitialCpmPhotoCandidate,
  validateInitialCpmPhotoCandidate,
} from "./cpmPhotoCandidate.ts";
import fixture from "./fixtures/cpm-photo-candidate-v1.json" with {
  type: "json",
};
import contentFixture from "./fixtures/cpm-photo-content-v1.json" with {
  type: "json",
};

const make = () => structuredClone(fixture.candidate);
const reject = (value: unknown) =>
  assertThrows(
    () => validateInitialCpmPhotoCandidate(value),
    Error,
    "initial_analysis_input_invalid",
  );

Deno.test("CPM allocation candidate matches independent canonical/digest vector", async () => {
  assertEquals(validateInitialCpmPhotoCandidate(make()), fixture.canonical);
  assertEquals(
    parseInitialCpmPhotoCandidate(fixture.canonical),
    fixture.canonical,
  );
  assertEquals(await initialCpmPhotoCandidateDigest(make()), fixture.digest);
  assertEquals(make().content_canonical, contentFixture.canonical);
});

Deno.test("CPM candidate binds processor expectation without rewriting content", async () => {
  const candidate = make();
  candidate.admission.expected_processor_permission = "openai";
  assertNotEquals(
    await initialCpmPhotoCandidateDigest(candidate),
    fixture.digest,
  );
  assertEquals(candidate.content_canonical, contentFixture.canonical);
  assertEquals(
    await initialCpmPhotoContentDigest(JSON.parse(candidate.content_canonical)),
    contentFixture.digest,
  );
  // Content-only identity is not sufficient for allocation identity.
  assertNotEquals(fixture.digest, contentFixture.digest);
});

Deno.test("CPM candidate snapshots content and expectation before digest await", async () => {
  const candidate = make(), pending = initialCpmPhotoCandidateDigest(candidate);
  candidate.admission.expected_processor_permission = "openai";
  candidate.content_canonical = "{}";
  assertEquals(await pending, fixture.digest);
});

Deno.test("CPM candidate closes protocol, processor and private authority fields", async (t) => {
  const invalid = [
    { ...make(), version: 2 },
    { ...make(), variant: "media_sources" },
    { ...make(), variant: "no_media" },
    { ...make(), owner_id: "00000000-0000-4000-8000-000000000001" },
    { ...make(), assignment_digest: "a".repeat(64) },
    { ...make(), admission: { ...make().admission, client_protocol: 2 } },
    { ...make(), admission: { ...make().admission, client_protocol: 4 } },
    { ...make(), admission: { ...make().admission, client_protocol: true } },
    {
      ...make(),
      admission: { ...make().admission, identification_protocol: 5 },
    },
    {
      ...make(),
      admission: { ...make().admission, identification_protocol: 6.5 },
    },
    {
      ...make(),
      admission: { ...make().admission, expected_processor_permission: null },
    },
    {
      ...make(),
      admission: {
        ...make().admission,
        expected_processor_permission: "google",
      },
    },
    { ...make(), admission: { ...make().admission, model: "caller-selected" } },
    { ...make(), admission: { ...make().admission, language: "en" } },
    { ...make(), admission: { ...make().admission, location: null } },
    { ...make(), admission: null },
    { ...make(), content_canonical: contentFixture.content },
    { ...make(), content_canonical: "x".repeat(1_048_577) },
    contentFixture.content,
  ];
  for (const [index, value] of invalid.entries()) {
    await t.step(`denial ${index}`, () => {
      reject(value);
    });
  }
});

Deno.test("CPM candidate requires independently canonical valid embedded content", () => {
  for (
    const content_canonical of [
      "{}",
      contentFixture.canonical + "\n",
      '{"version":1,' + contentFixture.canonical.slice(1),
      JSON.stringify(contentFixture.content),
    ]
  ) reject({ ...make(), content_canonical });
  const invalidContent = structuredClone(contentFixture.content);
  invalidContent.photos = [];
  reject({
    ...make(),
    content_canonical: initialCanonicalText(invalidContent),
  });
  const textOnly = { ...make() };
  const inner = structuredClone(contentFixture.content);
  inner.kind = "text_only";
  textOnly.content_canonical = initialCanonicalText(inner);
  reject(textOnly);
});

Deno.test("CPM candidate wire rejects duplicate and alternate outer spellings", () => {
  for (
    const text of [
      fixture.canonical + "\n",
      '{"version":1,' + fixture.canonical.slice(1),
      fixture.canonical.replace('"version":1', '"version":1.0'),
      fixture.canonical.replace('"client_protocol":3', '"client_protocol":3e0'),
    ]
  ) {
    assertThrows(
      () => parseInitialCpmPhotoCandidate(text),
      Error,
      "initial_analysis_input_invalid",
    );
  }
});
