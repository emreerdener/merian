import assert from "node:assert/strict";
import test from "node:test";
import {
  cardAtPoint,
  cellAt,
  indexAtCell,
  lensPoint,
  mergeCards,
} from "./exploreCanvas.ts";
import { decodeExploreCursor, encodeExploreCursor } from "./exploreCursor.ts";
import { approvedExplorePoster, readBoundedPoster } from "./explorePoster.ts";

test("expanding pages have unique stable adjacent cells", () => {
  const cells = Array.from({ length: 1000 }, (_, i) => cellAt(i));
  assert.equal(new Set(cells.map(({ x, y }) => `${x},${y}`)).size, 1000);
  for (let i = 1; i < cells.length; i++) {
    assert.equal(
      Math.abs(cells[i].x - cells[i - 1].x) +
        Math.abs(cells[i].y - cells[i - 1].y),
      1,
    );
  }
  assert.deepEqual(cellAt(0), { x: 0, y: 0 });
  assert.deepEqual(cellAt(48), { x: 3, y: -3 });
});

test("clicks follow the shader mapping and exclude gutters and rounded corners", () => {
  assert.deepEqual(lensPoint({ x: 500, y: 300 }, 1000, 600, .075), {
    x: 0,
    y: 0,
  });
  assert.deepEqual(lensPoint({ x: 1000, y: 300 }, 1000, 600, .075), {
    x: 537.5,
    y: 0,
  });
  assert.equal(cardAtPoint({ x: 0, y: 0 }, { x: 0, y: 0 }, 1, 252, 240, 48), 0);
  assert.equal(
    cardAtPoint({ x: 126, y: 0 }, { x: 0, y: 0 }, 1, 252, 240, 48),
    -1,
  );
  assert.equal(
    cardAtPoint({ x: 119, y: 119 }, { x: 0, y: 0 }, 1, 252, 240, 48),
    -1,
  );
  assert.equal(
    cardAtPoint(
      { x: 252 * .94 + 30, y: 20 },
      { x: 30, y: 20 },
      .94,
      252,
      240,
      48,
    ),
    1,
  );
});

test("page append deduplicates without moving existing cards", () => {
  const a = { id: "a", label: "A", poster: null },
    b = { id: "b", label: "B", poster: null };
  assert.deepEqual(mergeCards([a], [a, b, b]), [a, b]);
});

test("cursor round trips preserve database microseconds", () => {
  const cursor = {
    sharedAt: "2026-11-08T12:00:00.123456+00:00",
    postId: "00000000-0000-4000-8000-000000000001",
  };
  assert.deepEqual(decodeExploreCursor(encodeExploreCursor(cursor)), cursor);
  assert.equal(decodeExploreCursor(null), null);
  for (
    const value of [
      "",
      "!",
      "a".repeat(257),
      Buffer.from('[1,"infinity","bad"]').toString("base64url"),
      Buffer.from("{}").toString("base64url"),
    ]
  ) assert.throws(() => decodeExploreCursor(value));
});

test("poster allowlist rejects arbitrary origins, redirects inputs and private media", () => {
  assert.ok(
    approvedExplorePoster(
      "https://media.merian.app/public_uploads/free/photo.webp",
    ),
  );
  assert.ok(
    approvedExplorePoster(
      "https://upload.wikimedia.org/wikipedia/commons/a/ab/Bird.jpg",
    ),
  );
  for (
    const value of [
      "https://evil.test/photo.webp",
      "https://media.merian.app/private/photo.webp",
      "https://media.merian.app/public_uploads/free/x.svg",
      "https://media.merian.app/public_uploads/free/../../private/x.png",
      "https://user@media.merian.app/public_uploads/free/x.png",
      "https://media.merian.app/public_uploads/free/x.png?url=secret",
      "http://media.merian.app/public_uploads/free/x.png",
      "https://media.merian.app/public_uploads/free/%2fprivate.png",
    ]
  ) assert.equal(approvedExplorePoster(value), null, value);
});

test("poster stream enforces actual size, not just declared content-length", async () => {
  const stream = new ReadableStream({
    start(controller) {
      controller.enqueue(new Uint8Array(4));
      controller.enqueue(new Uint8Array(4));
      controller.close();
    },
  });
  await assert.rejects(
    readBoundedPoster(
      new Response(stream, { headers: { "content-length": "1" } }),
      6,
    ),
  );
  assert.equal(
    (await readBoundedPoster(new Response(new Uint8Array(4)), 6)).length,
    4,
  );
});

test("spiral address inversion remains exact across large feeds", () => {
  for (let i = 0; i < 100000; i++) {
    const cell = cellAt(i);
    assert.equal(indexAtCell(cell.x, cell.y), i);
  }
});

test("lens-aware coverage stays filled within the GPU budget while panning and zooming", async () => {
  const { exploreViewportLayout, visibleCanvasCells } = await import(
    "./exploreCanvas.ts"
  );
  for (
    const [width, height] of [
      [320, 844],
      [390, 844],
      [1280, 720],
      [2048, 1240],
      [3840, 2160],
      [7680, 4320],
    ]
  ) {
    const layout = exploreViewportLayout(width, height);
    for (const zoom of [1, .94]) {
      for (const pan of [{ x: 0, y: 0 }, { x: 3517.3, y: -8791.1 }]) {
        const cells = visibleCanvasCells(
          width,
          height,
          pan,
          layout.pitch,
          zoom,
          layout.bend,
        );
        assert.ok(
          cells.length <= 96,
          `${width}×${height}: ${cells.length} tiles`,
        );
        const indices = new Set(cells.map((cell) => cell.index));
        for (let x = 0; x <= width; x += width / 20) {
          for (let y = 0; y <= height; y += height / 20) {
            const point = lensPoint({ x, y }, width, height, layout.bend);
            const index = cardAtPoint(
              point,
              pan,
              zoom,
              layout.pitch,
              layout.size,
              Infinity,
              layout.radius,
            );
            if (index >= 0) {
              assert.ok(
                indices.has(index),
                "every visible photo has a rendered cell",
              );
            }
          }
        }
      }
    }
  }
});

test("skeleton projection and image shader use the same lens geometry", async () => {
  const { projectLensPoint } = await import("./exploreCanvas.ts");
  for (const bend of [.035, .075]) {
    for (
      const point of [{ x: 0, y: 0 }, { x: -780, y: 470 }, { x: 560, y: -350 }]
    ) {
      const screen = projectLensPoint(point, 1280, 720, bend);
      const result = lensPoint(screen, 1280, 720, bend);
      assert.ok(Math.hypot(result.x - point.x, result.y - point.y) < .00001);
    }
  }
});
