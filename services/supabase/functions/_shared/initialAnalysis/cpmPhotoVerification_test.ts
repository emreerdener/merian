import { assertEquals, assertThrows } from "@std/assert";
import { inspectHeifContainer } from "../analysisHistory/heifContainer.ts";
import {
  heifBox,
  heifFixture,
  heifText,
  heifUint,
} from "../analysisHistory/testing/heifFixtures.ts";
import { inspectJpegContainer } from "../analysisHistory/jpegContainer.ts";
import { inspectWebpContainer } from "../analysisHistory/webpContainer.ts";
import { inspectPngContainer } from "../analysisHistory/pngContainer.ts";
import { validatePublicPhotoContainer } from "../analysisHistory/publicPhotoContainer.ts";
import {
  joined,
  jpegSegment,
  pngChunk,
  pngParts,
  safeJpeg,
  safePng,
} from "../analysisHistory/testing/publicPhotoFixtures.ts";
import { fixture, hash } from "./cpmPhotoAdmissionTestFixtures.ts";
import { initialCanonicalText } from "./canonical.ts";
import { initialCpmPhotoContentDigest } from "./cpmPhotoContent.ts";
import { initialCpmPhotoCandidateDigest } from "./cpmPhotoCandidate.ts";
import { initialMediaHash } from "./mediaBinding.ts";
import {
  type CpmPhotoVerificationDependencies,
  verifyAndAdmitInitialCpmPhotoMedia,
} from "./cpmPhotoVerification.ts";

async function mediaFixture(
  bytes = safeJpeg(),
  count = 1,
  sourceType = "image/jpeg",
  sourceBytes = bytes,
) {
  const f = await fixture(async (candidate, assignment) => {
    const content = JSON.parse(candidate.content_canonical);
    for (let n = 1; n < count; n++) {
      content.photos.push(structuredClone(content.photos[0]));
    }
    assignment.preparation.role_mapping = [];
    for (const [ordinal, photo] of content.photos.entries()) {
      photo.ordinal = ordinal;
      for (const [index, role] of ["source", "ai", "display"].entries()) {
        const input = role === "source" ? sourceBytes : bytes;
        photo[role].byte_count = input.length;
        photo[role].sha256 = await initialMediaHash(input.slice());
        photo[role].declared_content_type = role === "source"
          ? sourceType
          : "image/jpeg";
        photo[role].reference_id = `00000000-0000-4000-8000-00000000070${
          ordinal * 3 + index
        }`;
        assignment.preparation.role_mapping.push({
          photo_ordinal: ordinal,
          role,
          object_id: `00000000-0000-4000-8000-00000000020${
            ordinal * 3 + index
          }`,
          declaration: photo[role],
        });
      }
    }
    candidate.content_canonical = initialCanonicalText(content);
    assignment.content_digest = await initialCpmPhotoContentDigest(content);
    assignment.candidate_digest = await initialCpmPhotoCandidateDigest(
      candidate,
    );
  });
  const config = {
    generation: f.snapshot.backend_generation,
    provider: "r2",
    direct_endpoint:
      "https://00000000000000000000000000000000.r2.cloudflarestorage.com",
    private_bucket: "synthetic-private",
    namespace: "initial-preparation/v2",
    credential_profile: "synthetic_only",
    storage_protocol: "conditional_create_permanent_same_key_marker_v1",
  };
  const configuration_digest = await hash(
    "merian.initial-analysis.media.backend.v1",
    initialCanonicalText(config),
  );
  f.snapshot.backend_configuration_digest = configuration_digest;
  f.snapshot.members.forEach((m) =>
    m.attempt.backend_configuration_digest = configuration_digest
  );
  f.begun.snapshot_canonical = initialCanonicalText(f.snapshot);
  f.begun.snapshot_digest = await hash(
    "merian.initial-analysis.cpm-verification-start.v1",
    f.begun.snapshot_canonical,
  );
  f.verified.snapshot_digest = f.begun.snapshot_digest;
  const dimensions = () => ({
    maximumWidth: 16384,
    maximumHeight: 16384,
    maximumPixels: 100_000_000,
  });
  const policy = {
    profile_digest: f.snapshot.profile_digest,
    verifier_build_digest: f.snapshot.verifier_build_digest,
    dimensions: {
      source: dimensions(),
      ai: dimensions(),
      display: dimensions(),
    },
    backend: { ...config, configuration_digest },
  };
  const requests: string[] = [];
  const controller = new AbortController();
  const headers = {
    "content-length": String(bytes.length),
    "content-type": "image/jpeg",
    "cache-control": "private, no-store",
  };
  let cohortChecks = 0;
  const deps: CpmPhotoVerificationDependencies = {
    load: () => Promise.resolve(policy),
    requireCurrent: (start) => {
      assertEquals(start, {
        ...f.identity,
        attempt_id: f.begun.attempt_id,
        snapshot_canonical: f.begun.snapshot_canonical,
        snapshot_digest: f.begun.snapshot_digest,
      });
      cohortChecks++;
      return Promise.resolve();
    },
    storage: {
      requireCurrent: () => Promise.resolve(),
      sign: (_profile, request) => Promise.resolve(request),
      fetch: (input) => {
        const isSource = requests.length % 3 === 0;
        const body = isSource ? sourceBytes : bytes;
        requests.push((input as Request).url);
        return Promise.resolve(
          new Response(body.slice(), {
            headers: {
              ...headers,
              "content-length": String(body.length),
              "content-type": isSource ? sourceType : "image/jpeg",
            },
          }),
        );
      },
    },
  };
  return {
    ...f,
    bytes,
    policy,
    requests,
    controller,
    headers,
    deps,
    checks: () => cohortChecks,
    run: () =>
      verifyAndAdmitInitialCpmPhotoMedia(
        f.bridge,
        deps,
        f.identity,
        controller.signal,
      ),
  };
}

Deno.test("CPM actual JPEG reads verify complete ordered one/two-photo cohorts before admission", async (t) => {
  for (const count of [1, 2]) {
    await t.step(String(count), async () => {
      const f = await mediaFixture(safeJpeg(), count);
      assertEquals((await f.run()).outcome, "admitted");
      assertEquals(f.requests.length, 3 * count);
      assertEquals(new Set(f.requests).size, 3 * count);
      assertEquals(f.calls, ["recover", "begin", "admit", "recover"]);
      assertEquals(f.checks() > f.requests.length * 3, true);
    });
  }
});

Deno.test("CPM 32 MiB original does not inherit the public JPEG 12 MiB ceiling", async () => {
  const jpeg = safeJpeg(), source = new Uint8Array(33_554_432).fill(0x3f);
  source.set(jpeg.subarray(0, -3));
  source.set([255, 217], source.length - 2);
  const f = await mediaFixture(jpeg, 1, "image/jpeg", source);
  assertThrows(() => inspectJpegContainer(source, () => {}));
  assertEquals((await f.run()).outcome, "admitted");
  assertEquals(f.requests.length, 3);
});

Deno.test("CPM byte-equal malformed JPEG cannot become structural evidence", async (t) => {
  for (
    const bytes of [
      new Uint8Array([255, 216, 255, 217]),
      safeJpeg().slice(0, -1),
      joined(safeJpeg(), new Uint8Array([0])),
    ]
  ) {
    await t.step(String(bytes.length), async () => {
      const f = await mediaFixture(bytes);
      assertEquals((await f.run()).outcome, "held");
      assertEquals(f.requests.length, 1);
      assertEquals(f.calls.includes("admit"), false);
    });
  }
});

Deno.test("CPM HEIF declarations over JPEG bytes fail actual structure inspection", async (t) => {
  for (const type of ["image/heic", "image/heif"]) {
    await t.step(type, async () => {
      const f = await mediaFixture(safeJpeg(), 2, type);
      assertEquals((await f.run()).outcome, "held");
      assertEquals(f.requests.length, 1);
      assertEquals(f.calls.includes("admit"), false);
    });
  }
});

Deno.test("CPM saved verifier build and explicit dimension bounds fail closed", async (t) => {
  for (
    const change of ["build", "profile", "width", "pixels", "invalid"] as const
  ) {
    await t.step(change, async () => {
      const f = await mediaFixture();
      if (change === "build") f.policy.verifier_build_digest = "0".repeat(64);
      if (change === "profile") f.policy.profile_digest = "0".repeat(64);
      if (change === "width") f.policy.dimensions.source.maximumWidth = 7;
      if (change === "pixels") f.policy.dimensions.source.maximumPixels = 63;
      if (change === "invalid") f.policy.dimensions.source.maximumWidth = 65536;
      assertEquals((await f.run()).outcome, "held");
      assertEquals(
        f.requests.length,
        ["width", "pixels"].includes(change) ? 1 : 0,
      );
      assertEquals(f.calls.includes("admit"), false);
    });
  }
});

Deno.test("CPM JPEG uses its explicit dimensions and preserves private metadata", async () => {
  const bytes = safeJpeg();
  // SOF width > legacy public 8192, within the explicitly selected test policy.
  const sof = bytes.findIndex((v, i) => v === 255 && bytes[i + 1] === 0xc0);
  bytes[sof + 7] = 0x23;
  bytes[sof + 8] = 0x28; // 9000
  assertThrows(() => inspectJpegContainer(bytes, () => {}));
  const f = await mediaFixture(
    joined(bytes.slice(0, 2), jpegSegment(0xfe, [1, 2, 3]), bytes.slice(2)),
  );
  assertEquals((await f.run()).outcome, "admitted");
});

Deno.test("CPM third-role hash mismatch discards entire cohort", async () => {
  const f = await mediaFixture(), fetch = f.deps.storage.fetch;
  f.deps.storage.fetch = (input, init) => {
    if (f.requests.length < 2) return fetch(input, init);
    f.requests.push((input as Request).url);
    const changed = f.bytes.slice();
    changed[changed.length - 3] ^= 1;
    return Promise.resolve(new Response(changed, { headers: f.headers }));
  };
  assertEquals((await f.run()).outcome, "held");
  assertEquals(f.requests.length, 3);
  assertEquals(f.calls.includes("admit"), false);
});

Deno.test("CPM late account retirement after reads forbids admission", async () => {
  const f = await mediaFixture(), current = f.deps.requireCurrent;
  f.deps.requireCurrent = (start, signal) => {
    if (f.requests.length === 3) return Promise.reject(new Error("retired"));
    return current(start, signal);
  };
  assertEquals((await f.run()).outcome, "held");
  assertEquals(f.requests.length, 3);
  assertEquals(f.calls.includes("admit"), false);
});

Deno.test("CPM unknown admission acknowledgement recovers without rereading JPEG cohort", async () => {
  const f = await mediaFixture(), admit = f.bridge.admit;
  f.bridge.admit = async (e, signal) => {
    await admit(e, signal);
    throw new Error("lost_ack");
  };
  assertEquals((await f.run()).outcome, "admitted");
  assertEquals((await f.run()).outcome, "admitted");
  assertEquals(f.requests.length, 3);
  assertEquals(f.calls.filter((v) => v === "begin").length, 1);
});

Deno.test("CPM cancellation during JPEG read prevents later role reads and admission", async () => {
  const f = await mediaFixture();
  let entered!: () => void, cancellations = 0;
  const ready = new Promise<void>((resolve) => {
    entered = resolve;
  });
  const body = new ReadableStream<Uint8Array>({
    pull() {
      entered();
      return new Promise(() => {});
    },
    cancel() {
      cancellations++;
    },
  }, { highWaterMark: 0 });
  f.deps.storage.fetch = (input) => {
    f.requests.push((input as Request).url);
    return Promise.resolve(new Response(body, { headers: f.headers }));
  };
  const run = f.run();
  await ready;
  f.controller.abort();
  await run.catch(() => undefined);
  await new Promise((resolve) => setTimeout(resolve, 0));
  assertEquals(f.requests.length, 1);
  assertEquals(cancellations, 1);
  assertEquals(body.locked, false);
  assertEquals(f.calls.includes("admit"), false);
});

Deno.test("CPM JPEG inspection copies reused transport views before the next pull", async () => {
  const f = await mediaFixture();
  f.deps.storage.fetch = (input) => {
    f.requests.push((input as Request).url);
    let offset = 0;
    const reused = new Uint8Array(1);
    const body = new ReadableStream<Uint8Array>({
      pull(c) {
        if (offset === f.bytes.length) {
          reused.fill(0);
          c.close();
          return;
        }
        reused[0] = f.bytes[offset++];
        c.enqueue(reused);
      },
    }, { highWaterMark: 0 });
    return Promise.resolve(new Response(body, { headers: f.headers }));
  };
  assertEquals((await f.run()).outcome, "admitted");
  assertEquals(f.requests.length, 3);
});

Deno.test("CPM PNG originals share complete-cohort verification with JPEG derivatives", async (t) => {
  for (const count of [1, 2]) {
    await t.step(String(count), async () => {
      const f = await mediaFixture(safeJpeg(), count, "image/png", safePng());
      assertEquals((await f.run()).outcome, "admitted");
      assertEquals(f.requests.length, 3 * count);
      assertEquals(f.calls, ["recover", "begin", "admit", "recover"]);
    });
  }
});

Deno.test("CPM PNG opaque ancillary metadata is retained without public sanitization", async () => {
  const [signature, header, data, end] = pngParts();
  const source = joined(
    signature,
    header,
    pngChunk("vpAg", [1, 2, 3]),
    data,
    pngChunk("vpAg", [4, 5]),
    end,
  );
  const f = await mediaFixture(safeJpeg(), 1, "image/png", source);
  assertEquals((await f.run()).outcome, "admitted");
  assertEquals(f.requests.length, 3);
});

Deno.test("CPM PNG framing failures cannot supply structural evidence despite exact hashes", async (t) => {
  const [signature, header, data, end] = pngParts();
  const corrupt = safePng();
  corrupt[corrupt.length - 1] ^= 1;
  const cases: Record<string, Uint8Array> = {
    crc: corrupt,
    header: joined(signature, data, header, end),
    duplicate: joined(signature, header, header, data, end),
    critical: joined(signature, header, pngChunk("ABCD"), data, end),
    reserved: joined(signature, header, pngChunk("abcd"), data, end),
    split: joined(signature, header, data, pngChunk("vpAg"), data, end),
    trailing: joined(safePng(), new Uint8Array([0])),
    truncated: safePng().slice(0, -1),
    missingData: joined(signature, header, end),
    zlib: joined(signature, header, pngChunk("IDAT", [0, 0, 0, 0, 0, 0]), end),
    animation: joined(
      signature,
      header,
      pngChunk("acTL", [0, 0, 0, 1, 0, 0, 0, 0]),
      data,
      end,
    ),
    wrongType: safeJpeg(),
  };
  for (const [name, source] of Object.entries(cases)) {
    await t.step(name, async () => {
      const f = await mediaFixture(safeJpeg(), 1, "image/png", source);
      assertEquals((await f.run()).outcome, "held");
      assertEquals(f.requests.length, 1);
      assertEquals(f.calls.includes("admit"), false);
    });
  }
});

Deno.test("CPM PNG uses explicit source dimensions and rejects the wrong HTTP MIME", async (t) => {
  const [signature, , data, end] = pngParts();
  const source = joined(
    signature,
    pngChunk("IHDR", [0, 0, 35, 40, 0, 0, 0, 1, 8, 0, 0, 0, 0]),
    data,
    end,
  );
  assertThrows(() => validatePublicPhotoContainer(source, "image/png"));
  for (const mode of ["valid", "dimensions", "mime"]) {
    await t.step(mode, async () => {
      const f = await mediaFixture(safeJpeg(), 1, "image/png", source);
      if (mode === "dimensions") {
        f.policy.dimensions.source.maximumWidth = 8999;
      }
      if (mode === "mime") {
        f.deps.storage.fetch = (input) => {
          f.requests.push((input as Request).url);
          return Promise.resolve(
            new Response(source.slice(), {
              headers: {
                ...f.headers,
                "content-length": String(source.length),
              },
            }),
          );
        };
      }
      assertEquals(
        (await f.run()).outcome,
        mode === "valid" ? "admitted" : "held",
      );
      assertEquals(f.requests.length, mode === "valid" ? 3 : 1);
    });
  }
});

Deno.test("PNG inspection enforces byte and dimension policy independently of valid framing", () => {
  const png = safePng();
  const limits = {
    maximumBytes: png.length,
    maximumWidth: 1,
    maximumHeight: 1,
    maximumPixels: 1,
  };
  assertEquals(inspectPngContainer(png, limits), { width: 1, height: 1 });
  for (
    const invalid of [{ maximumBytes: png.length - 1 }, { maximumWidth: 0 }, {
      maximumHeight: NaN,
    }, { maximumPixels: 0 }]
  ) {
    assertThrows(() => inspectPngContainer(png, { ...limits, ...invalid }));
  }
});

// Structural vectors only: these synthetic entropy payloads are not pixel fixtures.
function webpChunk(kind: string, payload: Uint8Array) {
  const result = new Uint8Array(8 + payload.length + payload.length % 2);
  result.set(new TextEncoder().encode(kind));
  new DataView(result.buffer).setUint32(4, payload.length, true);
  result.set(payload, 8);
  return result;
}
function webpRiff(...chunks: Uint8Array[]) {
  const result = joined(new TextEncoder().encode("RIFF0000WEBP"), ...chunks);
  new DataView(result.buffer).setUint32(4, result.length - 8, true);
  return result;
}
function webpImage(lossless = false, width = 8, height = 6, alphaHint = false) {
  const payload = new Uint8Array(lossless ? 8 : 14);
  const view = new DataView(payload.buffer);
  if (lossless) {
    payload[0] = 0x2f;
    view.setUint32(
      1,
      (width - 1) | ((height - 1) << 14) | (alphaHint ? 1 << 28 : 0),
      true,
    );
  } else {
    payload.set([0x30, 0, 0, 0x9d, 1, 0x2a]);
    view.setUint16(6, width, true);
    view.setUint16(8, height, true);
  }
  return webpChunk(lossless ? "VP8L" : "VP8 ", payload);
}
function webpExtended(flags = 0, width = 8, height = 6) {
  const payload = new Uint8Array(10);
  payload[0] = flags;
  for (const [offset, value] of [[4, width - 1], [7, height - 1]]) {
    payload[offset] = value & 255;
    payload[offset + 1] = (value >>> 8) & 255;
    payload[offset + 2] = value >>> 16;
  }
  return webpChunk("VP8X", payload);
}
const webpLimits = {
  maximumBytes: 33_554_432,
  maximumWidth: 16384,
  maximumHeight: 16384,
  maximumPixels: 100_000_000,
};

Deno.test("CPM still WebP sources share complete cohort verification with JPEG derivatives", async (t) => {
  const metadata = webpRiff(
    webpExtended(0x2c),
    webpChunk("EXIF", new Uint8Array([1, 2, 3])),
    webpChunk("ICCP", new Uint8Array([4])),
    webpImage(),
    webpChunk("XMP ", new Uint8Array([5])),
    webpChunk("test", new Uint8Array([6])),
    webpChunk("test", new Uint8Array([7])),
  );
  const rawAlpha = webpRiff(
    webpExtended(0x10),
    webpChunk("ALPH", new Uint8Array(49)),
    webpImage(),
  );
  const compressedAlpha = webpRiff(
    webpExtended(0x10),
    webpChunk("ALPH", new Uint8Array([0x1d, 0])),
    webpImage(),
  );
  for (
    const [name, bytes] of [
      ["lossy", webpRiff(webpImage())],
      ["lossless", webpRiff(webpImage(true))],
      ["simple alpha hint", webpRiff(webpImage(true, 8, 6, true))],
      [
        "extended alpha hint",
        webpRiff(webpExtended(0x10), webpImage(true, 8, 6, true)),
      ],
      ["opaque metadata", metadata],
      ["raw alpha", rawAlpha],
      ["compressed alpha header", compressedAlpha],
    ] as const
  ) {
    await t.step(name, async () => {
      const f = await mediaFixture(safeJpeg(), 2, "image/webp", bytes);
      inspectWebpContainer(bytes, webpLimits, "private_still");
      assertEquals((await f.run()).outcome, "admitted");
      assertEquals(f.requests.length, 6);
      assertEquals(f.calls, ["recover", "begin", "admit", "recover"]);
      assertEquals(inspectWebpContainer(bytes, webpLimits, "private_still"), {
        width: 8,
        height: 6,
      });
    });
  }
});

Deno.test("CPM hash-matching malformed WebP never admits partial evidence", async (t) => {
  const original = webpRiff(webpImage());
  const wrongSize = original.slice();
  wrongSize[4]--;
  const badPadding = webpChunk("EXIF", new Uint8Array([1]));
  badPadding[badPadding.length - 1] = 1;
  const badVersion = webpImage(true);
  badVersion[12] |= 0x20;
  const badSignature = webpImage();
  badSignature[11] = 0;
  const scaled = webpImage();
  scaled[15] |= 0x40;
  const reserved = webpExtended();
  reserved[9] = 1;
  const tooMany = webpRiff(
    webpExtended(),
    ...Array.from({ length: 4095 }, () => webpChunk("test", new Uint8Array())),
    webpImage(),
  );
  for (
    const [name, bytes] of [
      ["RIFF size", wrongSize],
      ["truncated", original.slice(0, -1)],
      ["trailing", joined(original, new Uint8Array([0]))],
      ["duplicate image", webpRiff(webpImage(), webpImage(true))],
      ["missing image", webpRiff(webpExtended())],
      ["canvas mismatch", webpRiff(webpExtended(0, 7), webpImage())],
      ["reserved header", webpRiff(reserved, webpImage())],
      ["reserved flag", webpRiff(webpExtended(0x40), webpImage())],
      ["animation flag", webpRiff(webpExtended(2), webpImage())],
      [
        "animation chunk",
        webpRiff(
          webpExtended(),
          webpChunk("ANMF", new Uint8Array()),
          webpImage(),
        ),
      ],
      ["missing metadata", webpRiff(webpExtended(8), webpImage())],
      [
        "undeclared metadata",
        webpRiff(
          webpExtended(),
          webpImage(),
          webpChunk("EXIF", new Uint8Array()),
        ),
      ],
      [
        "duplicate metadata",
        webpRiff(
          webpExtended(8),
          webpImage(),
          webpChunk("EXIF", new Uint8Array()),
          webpChunk("EXIF", new Uint8Array()),
        ),
      ],
      [
        "late color profile",
        webpRiff(
          webpExtended(0x20),
          webpImage(),
          webpChunk("ICCP", new Uint8Array([1])),
        ),
      ],
      ["padding", webpRiff(webpExtended(8), webpImage(), badPadding)],
      ["lossless version", webpRiff(badVersion)],
      ["VP8 signature", webpRiff(badSignature)],
      ["scaled VP8", webpRiff(scaled)],
      ["missing alpha", webpRiff(webpExtended(0x10), webpImage())],
      [
        "short raw alpha",
        webpRiff(
          webpExtended(0x10),
          webpChunk("ALPH", new Uint8Array(48)),
          webpImage(),
        ),
      ],
      [
        "invalid alpha header",
        webpRiff(
          webpExtended(0x10),
          webpChunk("ALPH", new Uint8Array([2, 0])),
          webpImage(),
        ),
      ],
      [
        "alpha with lossless",
        webpRiff(
          webpExtended(0x10),
          webpChunk("ALPH", new Uint8Array(49)),
          webpImage(true),
        ),
      ],
      [
        "metadata without VP8X",
        webpRiff(webpImage(), webpChunk("EXIF", new Uint8Array())),
      ],
      ["chunk count", tooMany],
      ["wrong actual format", safeJpeg()],
    ] as const
  ) {
    await t.step(name, async () => {
      const f = await mediaFixture(safeJpeg(), 1, "image/webp", bytes);
      assertEquals((await f.run()).outcome, "held");
      assertEquals(f.requests.length, 1);
      assertEquals(f.calls.includes("admit"), false);
    });
  }
});

Deno.test("WebP preserves strict frame policy and enforces trusted resource limits", async () => {
  const bytes = webpRiff(webpImage());
  assertEquals(inspectWebpContainer(bytes, webpLimits, "opaque_frame"), {
    width: 8,
    height: 6,
  });
  for (
    const forbidden of [
      webpRiff(webpImage(true, 8, 6, true)),
      webpRiff(
        webpExtended(8),
        webpImage(),
        webpChunk("EXIF", new Uint8Array()),
      ),
      webpRiff(
        webpExtended(0x10),
        webpChunk("ALPH", new Uint8Array(49)),
        webpImage(),
      ),
    ]
  ) {
    assertThrows(() =>
      inspectWebpContainer(forbidden, webpLimits, "opaque_frame")
    );
  }
  for (
    const override of [
      { maximumBytes: bytes.length - 1 },
      { maximumWidth: 7 },
      { maximumHeight: 5 },
      { maximumPixels: 47 },
      { maximumBytes: 33_554_433 },
      { maximumWidth: 0 },
      { maximumHeight: NaN },
      { maximumPixels: 0x100000000 },
    ]
  ) {
    assertThrows(() =>
      inspectWebpContainer(
        bytes,
        { ...webpLimits, ...override },
        "private_still",
      )
    );
  }
  const f = await mediaFixture(safeJpeg(), 1, "image/webp", bytes);
  f.policy.dimensions.source.maximumWidth = 7;
  assertEquals((await f.run()).outcome, "held");
  assertEquals(f.calls.includes("admit"), false);
});

Deno.test("CPM WebP consumer accepts existing native frame corpus as original bytes", async () => {
  const vectors = JSON.parse(
    await Deno.readTextFile(
      new URL(
        "../analysisHistory/fixtures/video-frame-containers.json",
        import.meta.url,
      ),
    ),
  );
  let count = 0;
  for (const vector of vectors) {
    if (vector.content_type !== "image/webp") continue;
    const bytes = Uint8Array.from(atob(vector.base64), (c) => c.charCodeAt(0));
    const f = await mediaFixture(safeJpeg(), 1, "image/webp", bytes);
    assertEquals((await f.run()).outcome, "admitted");
    assertEquals(f.requests.length, 3);
    count++;
  }
  assertEquals(count > 0, true);
});

Deno.test("CPM HEVC still-item sources bind primary properties and exact contained extents", async (t) => {
  for (const idat of [false, true]) {
    for (const wide of [false, true]) {
      for (const metadata of [false, true]) {
        await t.step(JSON.stringify({ idat, wide, metadata }), async () => {
          const bytes = heifFixture({ idat, wide, metadata });
          assertEquals(inspectHeifContainer(bytes, "image/heic", webpLimits), {
            width: 8,
            height: 6,
            primaryItem: 1,
          });
          for (const mime of ["image/heic", "image/heif"]) {
            const f = await mediaFixture(safeJpeg(), 2, mime, bytes);
            assertEquals((await f.run()).outcome, "admitted");
            assertEquals(f.requests.length, 6);
            assertEquals(f.calls, ["recover", "begin", "admit", "recover"]);
          }
        });
      }
    }
  }
});

function heifPayload(bytes: Uint8Array, kind: string) {
  const tag = heifText(kind);
  const at = bytes.findIndex((_, i) => tag.every((v, j) => bytes[i + j] === v));
  if (at < 0) throw new Error("missing synthetic box");
  return at + 4;
}
Deno.test("CPM malformed or unsupported HEIF graphs remain held after exact-byte verification", async (t) => {
  const original = heifFixture();
  const mutate = (
    kind: string,
    change: (b: Uint8Array, at: number) => void,
  ) => {
    const bytes = original.slice();
    change(bytes, heifPayload(bytes, kind));
    return bytes;
  };
  const set32 = (b: Uint8Array, at: number, value: number) =>
    new DataView(b.buffer).setUint32(at, value);
  for (
    const [name, bytes] of [
      ["truncated", original.slice(0, -1)],
      ["trailing", joined(original, new Uint8Array([0]))],
      ["zero box", mutate("meta", (b, p) => set32(b, p - 8, 0))],
      ["oversized box", mutate("meta", (b, p) => set32(b, p - 8, 0xffffffff))],
      ["sequence brand", mutate("ftyp", (b, p) => b.set(heifText("msf1"), p))],
      [
        "other codec brand",
        mutate("ftyp", (b, p) => b.set(heifText("avif"), p + 8)),
      ],
      [
        "non-picture handler",
        mutate("hdlr", (b, p) => b.set(heifText("vide"), p + 8)),
      ],
      ["missing primary", mutate("pitm", (b, p) => b[p + 5] = 2)],
      ["hidden primary", mutate("infe", (b, p) => b[p + 3] = 1)],
      ["protected item", mutate("infe", (b, p) => b[p + 7] = 1)],
      [
        "grid pending",
        mutate("infe", (b, p) => b.set(heifText("grid"), p + 8)),
      ],
      ["item count", mutate("iinf", (b, p) => b[p + 5] = 2)],
      ["external location", mutate("iloc", (b, p) => b[p + 13] = 1)],
      ["derived construction", mutate("iloc", (b, p) => b[p + 11] = 2)],
      [
        "out of file extent",
        mutate("iloc", (b, p) => set32(b, p + 16, 0xffffffff)),
      ],
      ["extent into metadata", mutate("iloc", (b, p) => set32(b, p + 16, 12))],
      [
        "oversized extent",
        mutate("iloc", (b, p) => set32(b, p + 20, 0xffffffff)),
      ],
      ["empty extent", mutate("iloc", (b, p) => set32(b, p + 20, 0))],
      [
        "unknown property",
        mutate("ispe", (b, p) => b.set(heifText("auxC"), p - 4)),
      ],
      ["missing property", mutate("ipma", (b, p) => b[p + 11] = 0x83)],
      ["duplicate association", mutate("ipma", (b, p) => b[p + 12] = 0x81)],
      ["nonessential config", mutate("ipma", (b, p) => b[p + 12] = 2)],
      ["zero dimensions", mutate("ispe", (b, p) => set32(b, p + 4, 0))],
      [
        "oversized dimensions",
        mutate("ispe", (b, p) => set32(b, p + 4, 100000)),
      ],
      ["configuration version", mutate("hvcC", (b, p) => b[p] = 2)],
      ["reserved config", mutate("hvcC", (b, p) => b[p + 13] = 0)],
      ["missing parameter array", mutate("hvcC", (b, p) => b[p + 22] = 2)],
      ["parameter NAL mismatch", mutate("hvcC", (b, p) => b[p + 28] = 66)],
      ["truncated NAL length", mutate("mdat", (b, p) => set32(b, p, 1000))],
      ["invalid NAL header", mutate("mdat", (b, p) => b[p + 4] |= 0x80)],
      ["no coded picture", mutate("mdat", (b, p) => b[p + 4] = 64)],
      ["movie sequence", joined(original, heifBox("moov", new Uint8Array()))],
    ] as const
  ) {
    await t.step(name, async () => {
      assertThrows(() => inspectHeifContainer(bytes, "image/heif", webpLimits));
      const f = await mediaFixture(safeJpeg(), 1, "image/heif", bytes);
      assertEquals((await f.run()).outcome, "held");
      assertEquals(f.calls.includes("admit"), false);
    });
  }
});
Deno.test("HEIF bounds and parser checkpoints reject without allocating decoded media", () => {
  const bytes = heifFixture();
  for (
    const override of [
      { maximumBytes: bytes.length - 1 },
      { maximumWidth: 7 },
      { maximumHeight: 5 },
      { maximumPixels: 47 },
      { maximumPixels: 0 },
      { maximumWidth: NaN },
    ]
  ) {
    assertThrows(() =>
      inspectHeifContainer(bytes, "image/heic", { ...webpLimits, ...override })
    );
  }
  let checks = 0;
  assertThrows(() =>
    inspectHeifContainer(bytes, "image/heic", webpLimits, () => {
      if (++checks === 5) throw new Error("cancelled");
    })
  );
  assertEquals(checks, 5);
});

Deno.test("HEIF uses bounded 64-bit lengths and rejects overlapping or unsafe item ranges", async () => {
  const bytes = heifFixture({ idat: true, largeOffsets: true });
  const meta = heifPayload(bytes, "meta") - 8;
  const extended = joined(
    bytes.subarray(0, meta),
    heifUint(1, 4),
    heifText("meta"),
    heifUint(bytes.length - meta + 8, 8),
    bytes.subarray(meta + 8),
  );
  for (const source of [bytes, extended]) {
    const f = await mediaFixture(safeJpeg(), 1, "image/heic", source);
    assertEquals((await f.run()).outcome, "admitted");
  }
  const unsafeBox = extended.slice();
  unsafeBox.fill(255, meta + 8, meta + 16);
  assertThrows(() => inspectHeifContainer(unsafeBox, "image/heic", webpLimits));
  const unsafeExtent = bytes.slice();
  const offset = heifPayload(unsafeExtent, "iloc") + 16;
  unsafeExtent.fill(255, offset, offset + 8);
  assertThrows(() =>
    inspectHeifContainer(unsafeExtent, "image/heic", webpLimits)
  );
  const overlap = heifFixture({ metadata: true });
  const loc = heifPayload(overlap, "iloc"), view = new DataView(overlap.buffer);
  view.setUint32(loc + 32, view.getUint32(loc + 16));
  assertThrows(() => inspectHeifContainer(overlap, "image/heic", webpLimits));
});

Deno.test("CPM native ImageIO HEIC direct and grid fixtures traverse the complete photo cohort", async (t) => {
  const vectors = JSON.parse(
    await Deno.readTextFile(
      new URL(
        "../analysisHistory/fixtures/heif-native-containers.json",
        import.meta.url,
      ),
    ),
  );
  assertEquals(vectors.length, 2);
  for (const vector of vectors) {
    await t.step(vector.name, async () => {
      const bytes = Uint8Array.from(
        atob(vector.base64),
        (c) => c.charCodeAt(0),
      );
      assertEquals(await initialMediaHash(bytes), vector.sha256);
      const actual = inspectHeifContainer(bytes, "image/heic", webpLimits);
      assertEquals([actual.width, actual.height], [
        vector.width,
        vector.height,
      ]);
      const f = await mediaFixture(safeJpeg(), 2, "image/heic", bytes);
      assertEquals((await f.run()).outcome, "admitted");
      assertEquals(f.requests.length, 6);
      assertEquals(f.calls, ["recover", "begin", "admit", "recover"]);
    });
  }
});

Deno.test("HEIF native grid and self-contained data references reject malformed alternatives", async (t) => {
  const vectors = JSON.parse(
    await Deno.readTextFile(
      new URL(
        "../analysisHistory/fixtures/heif-native-containers.json",
        import.meta.url,
      ),
    ),
  );
  const original = Uint8Array.from(
    atob(vectors[1].base64),
    (c) => c.charCodeAt(0),
  );
  const mutate = (
    kind: string,
    change: (b: Uint8Array, at: number) => void,
  ) => {
    const bytes = original.slice();
    change(bytes, heifPayload(bytes, kind));
    return bytes;
  };
  const set16 = (b: Uint8Array, p: number, n: number) =>
    new DataView(b.buffer).setUint16(p, n);
  const set32 = (b: Uint8Array, p: number, n: number) =>
    new DataView(b.buffer).setUint32(p, n);
  for (
    const [name, bytes] of [
      ["external reference", mutate("url ", (b, p) => b[p + 3] = 0)],
      ["extra reference flag", mutate("url ", (b, p) => b[p + 3] = 3)],
      ["reference count", mutate("dref", (b, p) => set32(b, p + 4, 2))],
      [
        "transformed tile",
        mutate("ipma", (b, p) => {
          b[p + 13] = 5; // First tile's clli association becomes irot.
          b[heifPayload(b, "irot")] = 1;
        }),
      ],
      [
        "surplus tile column",
        mutate("idat", (b, p) => {
          set16(b, p + 4, 512);
          const first = heifPayload(b, "ispe");
          const second = first + heifPayload(b.subarray(first), "ispe");
          set32(b, second + 4, 512);
        }),
      ],
      ["grid version", mutate("idat", (b, p) => b[p] = 1)],
      ["grid flags", mutate("idat", (b, p) => b[p + 1] = 2)],
      ["grid row count", mutate("idat", (b, p) => b[p + 2] = 2)],
      ["grid column count", mutate("idat", (b, p) => b[p + 3] = 2)],
      ["grid declared width", mutate("idat", (b, p) => set16(b, p + 4, 1023))],
      ["grid declared height", mutate("idat", (b, p) => set16(b, p + 6, 767))],
      ["duplicate tile", mutate("dimg", (b, p) => set16(b, p + 6, 1))],
      ["self tile", mutate("dimg", (b, p) => set16(b, p + 4, 5))],
      ["missing tile", mutate("dimg", (b, p) => set16(b, p + 4, 99))],
      [
        "missing grid reference",
        mutate("dimg", (b, p) => b.set(heifText("thmb"), p - 4)),
      ],
      [
        "insufficient tile width",
        mutate("ispe", (b, p) => set32(b, p + 4, 511)),
      ],
      [
        "grid extent short",
        mutate("iloc", (b, p) => {
          const end = p - 8 + new DataView(b.buffer).getUint32(p - 8);
          set32(b, end - 4, 7);
        }),
      ],
      [
        "unsupported property",
        mutate("clli", (b, p) => b.set(heifText("auxC"), p - 4)),
      ],
    ] as const
  ) {
    await t.step(name, async () => {
      assertThrows(() => inspectHeifContainer(bytes, "image/heic", webpLimits));
      const f = await mediaFixture(safeJpeg(), 1, "image/heic", bytes);
      assertEquals((await f.run()).outcome, "held");
      assertEquals(f.calls.includes("admit"), false);
    });
  }
});

Deno.test("HEIF grid resource policy counts all coded tiles, not just output pixels", async () => {
  const vectors = JSON.parse(
    await Deno.readTextFile(
      new URL(
        "../analysisHistory/fixtures/heif-native-containers.json",
        import.meta.url,
      ),
    ),
  );
  const bytes = Uint8Array.from(
    atob(vectors[1].base64),
    (c) => c.charCodeAt(0),
  );
  const f = await mediaFixture(safeJpeg(), 1, "image/heic", bytes);
  f.policy.dimensions.source.maximumPixels = 800_000; // Output fits; four 512-square tiles do not.
  assertEquals((await f.run()).outcome, "held");
  assertEquals(f.calls.includes("admit"), false);
});
