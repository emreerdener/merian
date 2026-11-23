import { assertEquals, assertNotEquals, assertRejects } from "@std/assert";
import { initialEvidenceDigest } from "./initialEvidenceManifest.ts";
import { initialEvidenceStagingPlan } from "./initialEvidenceStaging.ts";

const id = (n: number) =>
  `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
const owner = id(1), scan = id(2), generation = id(3);
const artifact = (
  n: number,
  content_type = "image/jpeg",
  byte_count = 100,
) => ({
  media_id: id(n),
  content_type,
  byte_count,
  sha256: "a".repeat(64),
});
const photo = (n = 10) => ({
  kind: "image",
  source: artifact(n, "image/heic", 32 * 1024 * 1024),
  prepared: artifact(n + 1),
  coordinate_basis: "prepared_image_top_left_v1",
  focus_region: null,
  preparation: {
    schema_version: 1,
    coordinate_basis: "upright_source_top_left_v1",
    format: "nativeStillImageV1",
    crop_display_size: null,
    quarter_turns: 0,
    scale: 1,
    offset_x: 0,
    offset_y: 0,
    camera_vertical_center: null,
    source_selection: null,
  },
});
const audio = (n = 20) => ({
  kind: "audio",
  source: artifact(n, "audio/mp4"),
  prepared: artifact(n + 1, "audio/wav"),
});
const video = () => ({
  kind: "video",
  source: artifact(30, "video/mp4"),
  playback: artifact(31, "video/mp4"),
  frames: [artifact(32), artifact(33)],
  audio: {
    source: artifact(34, "audio/mp4"),
    prepared: artifact(35, "audio/wav"),
  },
});
async function request(items: unknown[], gen = generation) {
  const evidence_manifest = { schema_version: 9, items };
  return {
    schema_version: 1,
    scan_id: scan,
    generation: gen,
    evidence_manifest,
    evidence_digest: await initialEvidenceDigest(evidence_manifest, scan, gen),
  };
}

Deno.test("initial staging separates private originals from exact ordered provider inputs", async () => {
  for (
    const items of [
      [photo(), audio()],
      [audio(), photo()],
      [photo(), photo(12)],
      [audio(), audio(22)],
      [photo(), video()],
    ]
  ) {
    const plan = await initialEvidenceStagingPlan(owner, await request(items));
    const sources = plan.files.filter((file) =>
      file.role.startsWith("source_")
    );
    const provider = [
      ...plan.provider.image,
      ...plan.provider.audio,
      ...plan.provider.video,
    ];
    assertEquals(
      sources.every((file) => !provider.includes(file.sourceKey)),
      true,
    );
    assertEquals(
      plan.files.every((file) =>
        file.sourceKey === `staging/${owner}/${file.fileName}`
      ),
      true,
    );
    assertEquals(
      new Set(plan.files.map((file) => file.sourceKey)).size,
      plan.files.length,
    );
    assertEquals(
      plan.provider.image,
      plan.files.filter((file) =>
        ["prepared_image", "inference_frame"].includes(file.role)
      ).map((file) => file.sourceKey),
    );
    assertEquals(
      plan.provider.audio,
      plan.files.filter((file) =>
        ["prepared_audio", "prepared_companion_audio"].includes(file.role)
      ).map((file) => file.sourceKey),
    );
    assertEquals(
      plan.files.filter((file) =>
        file.mediaKind === "image" && file.role.startsWith("source_")
      ).every((file) => file.byte_count === 32 * 1024 * 1024),
      true,
    );
  }
  const plan = await initialEvidenceStagingPlan(
    owner,
    await request([photo(), {
      kind: "description",
      text: "Synthetic field notes",
    }, video()]),
  );
  assertEquals(plan.files.map((file) => file.item_index), [
    0,
    0,
    2,
    2,
    2,
    2,
    2,
    2,
  ]);
  assertEquals(
    plan.files.filter((file) => file.role === "inference_frame").map((file) =>
      file.role_index
    ),
    [0, 1],
  );
});

Deno.test("staging replay preserves key identity and binds geometry and source metadata", async () => {
  const input = await request([photo()]);
  const first = await initialEvidenceStagingPlan(owner, input);
  assertEquals(
    await initialEvidenceStagingPlan(owner, structuredClone(input)),
    first,
  );
  const changed = await initialEvidenceStagingPlan(
    owner,
    await request([photo()], id(4)),
  );
  assertNotEquals(
    changed.files.map((file) => file.sourceKey),
    first.files.map((file) => file.sourceKey),
  );
  for (
    const mutate of [
      (v: typeof input) => {
        v.evidence_digest = "b".repeat(64);
      },
      (v: typeof input) => {
        v.generation = id(5);
      },
    ]
  ) {
    const copy = structuredClone(input);
    mutate(copy);
    await assertRejects(() => initialEvidenceStagingPlan(owner, copy));
  }
  await assertRejects(() => initialEvidenceStagingPlan(scan, input));
  await assertRejects(() => initialEvidenceStagingPlan(id(10), input));
  await assertRejects(() =>
    initialEvidenceStagingPlan(owner, { ...input, sourceKey: "foreign" })
  );
  // An input mutation after the first await cannot replace parsed artifacts.
  const pending = initialEvidenceStagingPlan(owner, input);
  input.evidence_manifest.items.length = 0;
  assertEquals(await pending, first);
});

Deno.test("initial staging preserves five-image provider cap independently from artifact count", async () => {
  const photos = [10, 12, 14, 16, 18].map((n) => ({
    ...photo(n),
    source: artifact(n),
  }));
  const plan = await initialEvidenceStagingPlan(owner, await request(photos));
  assertEquals(plan.files.length, 10);
  assertEquals(plan.provider.image.length, 5);
  const movie = video();
  movie.frames = [32, 33, 36, 37, 38].map((n) => artifact(n));
  // Persisted evidence may describe these roles; current provider count does
  // not admit six image inputs. Never enlarge that budget with source storage.
  await assertRejects(async () =>
    initialEvidenceStagingPlan(owner, await request([photo(), movie]))
  );
});
