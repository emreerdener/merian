import { assertEquals, assertThrows } from "@std/assert";

import {
  canonicalizeCompatibleCapturedMediaWireV1,
  CAPTURED_MEDIA_MAX_ITEMS,
  CAPTURED_MEDIA_WIRE_VERSION,
  CapturedMediaContractError,
  capturedMediaSwiftDTOContract,
  parseCapturedMediaWireV1,
  parseCompatibleCapturedMediaWireV1,
  type StoredMediaReferenceDTO,
} from "./capturedMediaContract.ts";

const reference = (
  path: string,
  sourceIndex?: number,
): StoredMediaReferenceDTO => ({
  storage: "remoteURL",
  path,
  ...(sourceIndex == null ? {} : { sourceIndex }),
});

Deno.test("captured-media V1 validates every canonical variant without changing wrappers", () => {
  const value = [
    { image: { _0: reference("https://cdn.example.com/photo.webp") } },
    {
      audio: {
        _0: reference("https://cdn.example.com/call.wav", 0),
      },
    },
    {
      video: {
        _0: {
          video: reference("https://cdn.example.com/clip.mp4"),
          thumbnail: reference("https://cdn.example.com/poster.webp"),
        },
      },
    },
    { description: { _0: { freeText: "  Near the creek  " } } },
  ];

  assertEquals(parseCapturedMediaWireV1(value), [
    { image: { _0: reference("https://cdn.example.com/photo.webp") } },
    {
      audio: {
        _0: reference("https://cdn.example.com/call.wav", 0),
      },
    },
    {
      video: {
        _0: {
          video: reference("https://cdn.example.com/clip.mp4"),
          thumbnail: reference("https://cdn.example.com/poster.webp"),
        },
      },
    },
    { description: { _0: { freeText: "Near the creek" } } },
  ]);
});

Deno.test("captured-media compatibility reader discards every legacy addedAt representation", () => {
  const values = [
    { freeText: "Numeric", addedAt: 807_000_000 },
    { freeText: "ISO", added_at: "2026-08-22T12:00:00.000Z" },
    { free_text: "Missing" },
    { freeText: "Malformed but retired", addedAt: { unexpected: true } },
  ].map((context) => ({ description: { _0: context } }));

  assertEquals(parseCompatibleCapturedMediaWireV1(values), [
    { description: { _0: { freeText: "Numeric" } } },
    { description: { _0: { freeText: "ISO" } } },
    { description: { _0: { freeText: "Missing" } } },
    { description: { _0: { freeText: "Malformed but retired" } } },
  ]);
  assertThrows(
    () => parseCapturedMediaWireV1(values),
    CapturedMediaContractError,
    "unexpected key",
  );
});

Deno.test("captured-media compatibility reader retains legacy video audio and canonicalizes source aliases", () => {
  assertEquals(
    parseCompatibleCapturedMediaWireV1([{
      video: {
        _0: {
          video: {
            storage: "remoteURL",
            path: "https://cdn.example.com/clip.mp4",
            source_index: 0,
          },
          audio: reference("https://cdn.example.com/companion.wav"),
        },
      },
    }]),
    [{
      video: {
        _0: {
          video: reference("https://cdn.example.com/clip.mp4", 0),
          audio: reference("https://cdn.example.com/companion.wav"),
        },
      },
    }],
  );
});

Deno.test("captured-media compatibility accepts empty and legacy localFile manifests", () => {
  assertEquals(parseCompatibleCapturedMediaWireV1([]), []);
  assertEquals(
    parseCompatibleCapturedMediaWireV1([{
      audio: {
        _0: { storage: "localFile", path: "legacy/call.wav", sourceIndex: 1 },
      },
    }]),
    [{
      audio: {
        _0: { storage: "localFile", path: "legacy/call.wav", sourceIndex: 1 },
      },
    }],
  );
});

Deno.test("captured-media canonical writer drops local references and retired fields", () => {
  assertEquals(
    canonicalizeCompatibleCapturedMediaWireV1([
      {
        audio: {
          _0: { storage: "localFile", path: "legacy.wav", sourceIndex: 0 },
        },
      },
      {
        image: {
          _0: {
            storage: "remoteURL",
            path: "https://cdn.example.com/photo.webp",
            source_index: 1,
          },
        },
      },
      {
        video: {
          _0: {
            video: reference("https://cdn.example.com/clip.mp4"),
            thumbnail: { storage: "localFile", path: "poster.webp" },
            audio: reference("https://cdn.example.com/companion.wav"),
          },
        },
      },
      {
        description: {
          _0: { free_text: "  Canonical note  ", addedAt: 807_000_000 },
        },
      },
    ]),
    [
      {
        image: {
          _0: reference("https://cdn.example.com/photo.webp", 1),
        },
      },
      {
        video: {
          _0: {
            video: reference("https://cdn.example.com/clip.mp4"),
          },
        },
      },
      { description: { _0: { freeText: "Canonical note" } } },
    ],
  );
});

Deno.test("captured-media V1 rejects ambiguous variants, unknown keys, and unsafe URLs", () => {
  for (
    const value of [
      [{
        image: { _0: reference("https://cdn.example.com/a.webp") },
        audio: {},
      }],
      [{ unknown: { _0: {} } }],
      [{
        image: {
          _0: { ...reference("https://cdn.example.com/a.webp"), extra: true },
        },
      }],
      [{ image: { _0: reference("http://cdn.example.com/a.webp") } }],
      [{ audio: { _0: { storage: "localFile", path: "legacy.wav" } } }],
      [{
        image: { _0: reference("https://user:secret@cdn.example.com/a.webp") },
      }],
    ]
  ) {
    assertThrows(
      () => parseCapturedMediaWireV1(value),
      CapturedMediaContractError,
    );
  }
});

Deno.test("captured-media V1 enforces bounded nonempty manifests", () => {
  assertThrows(
    () => parseCapturedMediaWireV1([]),
    CapturedMediaContractError,
  );
  assertThrows(
    () =>
      parseCapturedMediaWireV1(
        Array.from(
          { length: CAPTURED_MEDIA_MAX_ITEMS + 1 },
          () => ({
            description: { _0: { freeText: "bounded" } },
          }),
        ),
      ),
    CapturedMediaContractError,
  );
});

Deno.test("captured-media Swift metadata is version-locked to the executable parser", () => {
  assertEquals(
    capturedMediaSwiftDTOContract.version,
    CAPTURED_MEDIA_WIRE_VERSION,
  );
  assertEquals(
    capturedMediaSwiftDTOContract.maxItems,
    CAPTURED_MEDIA_MAX_ITEMS,
  );
});
