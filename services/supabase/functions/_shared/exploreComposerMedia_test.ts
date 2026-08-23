import { assertEquals } from "@std/assert";
import { buildComposerMediaSources } from "./exploreComposerMedia.ts";
import { sourceMediaIdForPostMedia } from "./explorePostMedia.ts";

Deno.test("buildComposerMediaSources prefers normalized scan media assets", () => {
  const media = buildComposerMediaSources({
    id: "00000000-0000-0000-0000-000000000001",
    image_storage_urls: ["https://media.merian.app/stale-frame.webp"],
    video_storage_urls: ["https://media.merian.app/stale-clip.mp4"],
    captured_media: [
      {
        image: {
          _0: {
            storage: "remoteURL",
            path: "https://media.merian.app/stale-image.webp",
          },
        },
      },
    ],
    media_assets: [
      {
        kind: "video",
        role: "playback",
        status: "ready",
        url: "https://media.merian.app/clip.mp4",
        thumbnail_url: "https://media.merian.app/poster.webp",
        order_index: 0,
        duration_seconds: null,
        has_audio: true,
      },
      {
        kind: "image",
        role: "display",
        status: "ready",
        url: "https://media.merian.app/photo.webp",
        thumbnail_url: "https://media.merian.app/photo.webp",
        order_index: 1,
        duration_seconds: null,
        has_audio: false,
      },
    ],
  });

  assertEquals(media, [
    {
      source_media_id: "scan:00000000-0000-0000-0000-000000000001:video:0",
      kind: "video",
      url: "https://media.merian.app/clip.mp4",
      thumbnail_url: "https://media.merian.app/poster.webp",
      order_index: 0,
      has_audio: true,
      is_selected: false,
      selection_order_index: null,
    },
    {
      source_media_id: "scan:00000000-0000-0000-0000-000000000001:image:0",
      kind: "image",
      url: "https://media.merian.app/photo.webp",
      thumbnail_url: "https://media.merian.app/photo.webp",
      order_index: 1,
      has_audio: false,
      is_selected: false,
      selection_order_index: null,
    },
  ]);
});

Deno.test("buildComposerMediaSources ignores unready normalized media assets", () => {
  const media = buildComposerMediaSources({
    id: "00000000-0000-0000-0000-000000000001",
    image_storage_urls: [
      "https://media.merian.app/frame-1.webp",
      "https://media.merian.app/frame-2.webp",
    ],
    video_storage_urls: ["https://media.merian.app/clip.mp4"],
    captured_media: [
      {
        video: {
          _0: {
            video: {
              storage: "remoteURL",
              path: "https://media.merian.app/clip.mp4",
            },
            thumbnail: {
              storage: "remoteURL",
              path: "https://media.merian.app/poster.webp",
            },
          },
        },
      },
    ],
    media_assets: [
      {
        kind: "video",
        role: "playback",
        status: "failed",
        url: "https://media.merian.app/failed-clip.mp4",
        thumbnail_url: "https://media.merian.app/failed-poster.webp",
        order_index: 0,
        duration_seconds: null,
        has_audio: true,
        failure_reason: "promotion_failed",
      },
      {
        kind: "image",
        role: "inference_frame",
        status: "ready",
        url: "https://media.merian.app/frame-only.webp",
        thumbnail_url: "https://media.merian.app/frame-only.webp",
        order_index: 1,
        duration_seconds: null,
        has_audio: false,
      },
    ],
  });

  assertEquals(media, [
    {
      source_media_id: "scan:00000000-0000-0000-0000-000000000001:video:0",
      kind: "video",
      url: "https://media.merian.app/clip.mp4",
      thumbnail_url: "https://media.merian.app/poster.webp",
      order_index: 0,
      has_audio: false,
      is_selected: false,
      selection_order_index: null,
    },
  ]);
});

Deno.test("buildComposerMediaSources prefers captured media manifest for video scans", () => {
  const media = buildComposerMediaSources({
    id: "00000000-0000-0000-0000-000000000001",
    image_storage_urls: [
      "https://media.merian.app/frame-1.webp",
      "https://media.merian.app/frame-2.webp",
    ],
    video_storage_urls: ["https://media.merian.app/clip.mp4"],
    captured_media: [
      {
        video: {
          _0: {
            video: {
              storage: "remoteURL",
              path: "https://media.merian.app/clip.mp4",
            },
            thumbnail: {
              storage: "remoteURL",
              path: "https://media.merian.app/poster.webp",
            },
          },
        },
      },
    ],
  });

  assertEquals(media, [
    {
      source_media_id: "scan:00000000-0000-0000-0000-000000000001:video:0",
      kind: "video",
      url: "https://media.merian.app/clip.mp4",
      thumbnail_url: "https://media.merian.app/poster.webp",
      order_index: 0,
      has_audio: false,
      is_selected: false,
      selection_order_index: null,
    },
  ]);
});

Deno.test("sourceMediaIdForPostMedia matches manifest video post media", () => {
  const sourceMediaId = sourceMediaIdForPostMedia(
    {
      id: "00000000-0000-0000-0000-000000000001",
      image_storage_urls: [
        "https://media.merian.app/frame-1.webp",
        "https://media.merian.app/frame-2.webp",
      ],
      video_storage_urls: ["https://media.merian.app/clip.mp4"],
      captured_media: [
        {
          video: {
            _0: {
              video: {
                storage: "remoteURL",
                path: "https://media.merian.app/clip.mp4",
              },
              thumbnail: {
                storage: "remoteURL",
                path: "https://media.merian.app/poster.webp",
              },
            },
          },
        },
      ],
    },
    "video",
    "https://media.merian.app/clip.mp4",
  );

  assertEquals(
    sourceMediaId,
    "scan:00000000-0000-0000-0000-000000000001:video:0",
  );
});

Deno.test("buildComposerMediaSources collapses legacy video frame URLs", () => {
  const media = buildComposerMediaSources({
    id: "00000000-0000-0000-0000-000000000002",
    image_storage_urls: [
      "https://media.merian.app/frame-1.webp",
      "https://media.merian.app/frame-2.webp",
      "https://media.merian.app/frame-3.webp",
      "https://media.merian.app/frame-4.webp",
      "https://media.merian.app/frame-5.webp",
    ],
    video_storage_urls: ["https://media.merian.app/clip.mp4"],
  });

  assertEquals(media.length, 1);
  assertEquals(media[0].kind, "video");
  assertEquals(media[0].url, "https://media.merian.app/clip.mp4");
  assertEquals(media[0].thumbnail_url, "https://media.merian.app/frame-1.webp");
  assertEquals(media[0].has_audio, false);
});

Deno.test("buildComposerMediaSources exposes durable standalone audio", () => {
  const media = buildComposerMediaSources({
    id: "00000000-0000-0000-0000-000000000003",
    audio_storage_urls: ["https://media.merian.app/clip.wav"],
    captured_media: [
      {
        audio: {
          _0: {
            storage: "remoteURL",
            path: "https://media.merian.app/clip.wav",
          },
        },
      },
    ],
  });

  assertEquals(media, [{
    source_media_id: "scan:00000000-0000-0000-0000-000000000003:audio:0",
    kind: "audio",
    url: "https://media.merian.app/clip.wav",
    thumbnail_url: "",
    order_index: 0,
    has_audio: true,
    is_selected: false,
    selection_order_index: null,
  }]);
});

Deno.test("buildComposerMediaSources drops local-only manifest audio and falls back to durable URLs", () => {
  const media = buildComposerMediaSources({
    id: "00000000-0000-0000-0000-000000000004",
    audio_storage_urls: ["https://media.merian.app/durable-call.m4a"],
    captured_media: [{
      audio: {
        _0: {
          storage: "localFile",
          path: "recording-from-another-device.wav",
        },
      },
    }],
  });

  assertEquals(media.map(({ kind, url }) => ({ kind, url })), [{
    kind: "audio",
    url: "https://media.merian.app/durable-call.m4a",
  }]);
});

Deno.test("buildComposerMediaSources rejects unsafe manifests and uses legacy durable columns", () => {
  const media = buildComposerMediaSources({
    id: "00000000-0000-0000-0000-000000000005",
    image_storage_urls: ["https://media.merian.app/safe-photo.webp"],
    captured_media: [{
      image: {
        _0: {
          storage: "remoteURL",
          path: "http://media.merian.app/unsafe-photo.webp",
        },
      },
    }],
  });

  assertEquals(media.map(({ kind, url }) => ({ kind, url })), [{
    kind: "image",
    url: "https://media.merian.app/safe-photo.webp",
  }]);
});

Deno.test("buildComposerMediaSources never trusts legacy nested video audio as playback proof", () => {
  const media = buildComposerMediaSources({
    id: "00000000-0000-0000-0000-000000000006",
    captured_media: [{
      video: {
        _0: {
          video: {
            storage: "remoteURL",
            path: "https://media.merian.app/legacy-clip.mp4",
          },
          thumbnail: {
            storage: "remoteURL",
            path: "https://media.merian.app/legacy-poster.webp",
          },
          audio: {
            storage: "remoteURL",
            path: "https://media.merian.app/inference-only-track.wav",
          },
        },
      },
    }],
  });

  assertEquals(media.length, 1);
  assertEquals(media[0].kind, "video");
  assertEquals(media[0].has_audio, false);
});

Deno.test("buildComposerMediaSources filters unsafe normalized and legacy URLs", () => {
  const media = buildComposerMediaSources({
    id: "00000000-0000-0000-0000-000000000007",
    image_storage_urls: [
      "http://media.merian.app/insecure.webp",
      "https://user:secret@media.merian.app/credentialed.webp",
      "https://media.merian.app/safe.webp",
    ],
    media_assets: [{
      kind: "audio",
      role: "audio",
      status: "ready",
      url: "https://user:secret@media.merian.app/unsafe.m4a",
      order_index: 0,
    }],
  });

  assertEquals(media.map(({ kind, url }) => ({ kind, url })), [{
    kind: "image",
    url: "https://media.merian.app/safe.webp",
  }]);
});
