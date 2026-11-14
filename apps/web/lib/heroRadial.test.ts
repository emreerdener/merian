import assert from "node:assert/strict";
import test from "node:test";
import {
  heroRadialLayout,
  heroResponsiveLayout,
  heroScrollProgress,
} from "./heroRadial.ts";

test("radial scroll progress is bounded, including restored and overscrolled pages", () => {
  assert.equal(heroScrollProgress(76, 800), 0);
  assert.equal(heroScrollProgress(200, 800), 0);
  assert.equal(heroScrollProgress(-324, 800), 0.5);
  assert.equal(heroScrollProgress(-900, 800), 1);
  assert.equal(heroScrollProgress(0, 0), 0);
});

test("scroll keeps square frames and smoothly opens both rings at responsive sizes", () => {
  for (const [width, height] of [[1440, 900], [390, 380]]) {
    const start = heroRadialLayout(width, height, 0);
    const mid = heroRadialLayout(width, height, 0.5);
    const next = heroRadialLayout(width, height, 0.501);
    const end = heroRadialLayout(width, height, 1);
    assert.equal(start.tiles.length, 31);
    start.tiles.forEach((tile, index) => {
      const after = end.tiles[index];
      assert.equal(after.width, after.height);
      assert.ok(after.width > tile.width && after.width < tile.width * 1.1);
      assert.ok(Math.abs(after.rotation - tile.rotation) <= 8);
      assert.ok(
        Math.hypot(
          next.tiles[index].x - mid.tiles[index].x,
          next.tiles[index].y - mid.tiles[index].y,
        ) < 1,
      );
    });
    assert.deepEqual(heroRadialLayout(width, height, -1), start);
    assert.deepEqual(heroRadialLayout(width, height, 2), end);
    assert.deepEqual(heroRadialLayout(width, height, 0.5), mid);
  }
});

test("compact mosaic preserves every gap and square size throughout scrolling", () => {
  for (const width of [320, 390, 768]) {
    const start = heroResponsiveLayout(width, 380, 0).tiles;
    const end = heroResponsiveLayout(width, 380, 1).tiles;
    assert.equal(start.length, 25);
    assert.ok(new Set(start.map((tile) => Math.round(tile.width))).size >= 3);
    start.forEach((tile, index) => {
      assert.equal(tile.rotation, 0);
      assert.equal(tile.width, tile.height);
      assert.equal(end[index].width, tile.width);
      assert.equal(end[index].x, tile.x);
      assert.ok(Math.abs(end[index].y - tile.y + 24) < 1e-8);
    });
    assert.ok(Math.min(...end.map((tile) => tile.y)) < 0);
    assert.ok(Math.max(...end.map((tile) => tile.y + tile.height)) > 380);
    assert.ok(Math.min(...start.map((tile) => tile.x)) < 0);
    assert.ok(Math.max(...start.map((tile) => tile.x + tile.width)) > width);
  }
  assert.deepEqual(
    heroResponsiveLayout(769, 900, 0.5),
    heroRadialLayout(769, 900, 0.5),
  );
});

test("six radial accents are smaller than every anchor and stay clear of the central copy", () => {
  for (const [width, height] of [[769, 900], [1440, 900], [2200, 1000]]) {
    for (const progress of [0, 0.25, 0.5, 0.75, 1]) {
      const { tiles } = heroRadialLayout(width, height, progress);
      const smallestAnchor = Math.min(
        ...tiles.slice(0, 25).map((tile) => tile.width),
      );
      for (const tile of tiles.slice(25)) {
        assert.ok(tile.width < smallestAnchor * 0.7);
        const radians = tile.rotation * Math.PI / 180;
        const extent = tile.width *
          (Math.abs(Math.cos(radians)) + Math.abs(Math.sin(radians))) / 2;
        const x = tile.x + tile.width / 2;
        const y = tile.y + tile.height / 2;
        // Keep generous space around both the heading and CTA throughout scroll.
        assert.ok(
          x + extent < width * 0.22 || x - extent > width * 0.78 ||
            y + extent < height * 0.28 || y - extent > height * 0.73,
          JSON.stringify({ width, height, progress, x, y, extent }),
        );
      }
    }
  }
});

test("each radial ring mixes tilt directions without long runs of the same lean", () => {
  const tiles = heroRadialLayout(1440, 900).tiles;
  assert.equal(new Set(tiles.map((tile) => tile.rotation)).size, tiles.length);
  for (const ring of [tiles.slice(0, 15), tiles.slice(15, 25)]) {
    ring.forEach((tile, index) => {
      assert.ok(
        Number.isFinite(tile.rotation) && Math.abs(tile.rotation) <= 18,
      );
      const neighbors = [
        tile,
        ring[(index + 1) % ring.length],
        ring[(index + 2) % ring.length],
      ];
      assert.ok(neighbors.some((item) => item.rotation > 0));
      assert.ok(neighbors.some((item) => item.rotation < 0));
    });
  }
});

test("rotated radial photos keep breathing room at rest and throughout scrolling", () => {
  // Include wide, short heroes where the two rings previously crowded each other.
  for (const width of [769, 900, 1024, 1280, 1440, 1728, 1920, 2200, 2560, 3440]) {
    for (const height of [680, 820, 1004]) {
      for (let step = 0; step <= 40; step++) {
        const tiles = heroRadialLayout(width, height, step / 40).tiles;
        const frames = tiles.map((tile) => {
          const angle = tile.rotation * Math.PI / 180;
          return {
            x: tile.x + tile.width / 2,
            y: tile.y + tile.height / 2,
            half: tile.width / 2,
            axes: [[Math.cos(angle), Math.sin(angle)], [-Math.sin(angle), Math.cos(angle)]],
          };
        });
        for (let i = 0; i < frames.length; i++) {
          for (let j = i + 1; j < frames.length; j++) {
            const a = frames[i];
            const b = frames[j];
            // Separating-axis projections include the actual rotated corners.
            const separated = [...a.axes, ...b.axes].some(([x, y]) => {
              const extent = (frame: typeof a) => frame.half * frame.axes.reduce(
                (sum, [ax, ay]) => sum + Math.abs(x * ax + y * ay), 0,
              );
              return Math.abs((a.x - b.x) * x + (a.y - b.y) * y) -
                extent(a) - extent(b) >= 12;
            });
            assert.ok(separated, JSON.stringify({ width, height, step, i, j }));
          }
        }
      }
    }
  }
});
