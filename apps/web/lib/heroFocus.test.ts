import assert from "node:assert/strict";
import test from "node:test";
import {
  HERO_DRIFT_LIMIT,
  HERO_TILES,
  heroGridLayout,
  heroIdleEmphasis,
  heroIdleOffset,
  stepHeroSpring,
} from "./heroFocus.ts";

function assertSharedGutters(
  base: ReturnType<typeof heroGridLayout>,
  layout: ReturnType<typeof heroGridLayout>,
) {
  base.tiles.forEach((a, i) => {
    base.tiles.forEach((b, j) => {
      for (const [axis, cross] of [["x", "y"], ["y", "x"]] as const) {
        const overlap = Math.min(a[cross] + a.width, b[cross] + b.width) -
          Math.max(a[cross], b[cross]);
        if (
          overlap <= 0 ||
          Math.abs(b[axis] - a[axis] - a.width - base.restingGap) > 1e-6
        ) continue;
        const nextA = layout.tiles[i], nextB = layout.tiles[j];
        assert.ok(
          Math.abs(nextB[axis] - nextA[axis] - nextA.width - base.restingGap) <
            1e-6,
          "every shared edge retains its resting gutter",
        );
        assert.ok(
          Math.min(nextA[cross] + nextA.width, nextB[cross] + nextB.width) >
            Math.max(nextA[cross], nextB[cross]),
          "original neighbours remain adjacent",
        );
      }
    });
  });
}

test("mosaic keeps minimum gutters and extends beyond every viewport edge", () => {
  for (
    const [width, height] of [[900, 700], [390, 340], [700, 560], [448, 600]]
  ) {
    const { tiles, restingGap } = heroGridLayout(width, height);
    for (let i = 0; i < tiles.length; i++) {
      for (let j = i + 1; j < tiles.length; j++) {
        const a = tiles[i], b = tiles[j];
        const dx = Math.max(b.x - a.x - a.width, a.x - b.x - b.width);
        const dy = Math.max(b.y - a.y - a.height, a.y - b.y - b.height);
        assert.ok(
          Math.max(dx, dy) >= restingGap - 1e-8,
          "consistent resting gutter",
        );
      }
    }
    assert.ok(Math.min(...tiles.map((t) => t.x)) < -HERO_DRIFT_LIMIT);
    assert.ok(Math.min(...tiles.map((t) => t.y)) < -HERO_DRIFT_LIMIT);
    assert.ok(
      Math.max(...tiles.map((t) => t.x + t.width)) > width + HERO_DRIFT_LIMIT,
    );
    assert.ok(
      Math.max(...tiles.map((t) => t.y + t.height)) > height + HERO_DRIFT_LIMIT,
    );
  }
});

test("idle movement stays inside overscan and moves slowly", () => {
  for (let seconds = 0; seconds < 180; seconds += 0.1) {
    const point = heroIdleOffset(seconds);
    const next = heroIdleOffset(seconds + 0.1);
    assert.ok(Math.abs(point.x) <= HERO_DRIFT_LIMIT);
    assert.ok(Math.abs(point.y) <= HERO_DRIFT_LIMIT);
    assert.ok(Math.hypot(next.x - point.x, next.y - point.y) < 0.5);
  }
});

test("overlapping idle pulses reshape the mesh while preserving square gaps", () => {
  for (const [width, height] of [[900, 700], [390, 340], [448, 600]]) {
    const base = heroGridLayout(width, height);
    let largestGrowth = 0;
    for (let seconds = 0; seconds < 600; seconds += 0.5) {
      const emphasis = heroIdleEmphasis(seconds);
      const next = heroIdleEmphasis(seconds + 1 / 60);
      emphasis.forEach((value, i) => {
        assert.ok(value >= 0 && value <= 1.6);
        assert.ok(Math.abs(value - next[i]) < 0.011);
      });
      const layout = heroGridLayout(width, height, emphasis);
      assertSharedGutters(base, layout);
      assert.ok(
        emphasis.filter((value) => value > 0).length <= 2,
        "only the outgoing and incoming idle focus overlap",
      );
      assert.ok(
        Math.abs(emphasis.reduce((sum, value) => sum + value, 0) - 1.6) < 1e-10,
        "combined strength remains constant without a resting pause",
      );
      if (seconds % 12 > 0) {
        assert.equal(emphasis.filter((value) => value > 0).length, 2);
      }
      layout.tiles.forEach((tile, i) => {
        assert.equal(tile.width, tile.height);
        largestGrowth = Math.max(
          largestGrowth,
          tile.width / base.tiles[i].width - 1,
        );
        assert.ok(Math.abs(tile.width / base.tiles[i].width - 1) < 0.03);
        const nearest = Math.min(
          ...layout.tiles.filter((_, j) => i !== j).map((other) => {
            const dx = Math.max(
              other.x - tile.x - tile.width,
              tile.x - other.x - other.width,
              0,
            );
            const dy = Math.max(
              other.y - tile.y - tile.height,
              tile.y - other.y - other.height,
              0,
            );
            return Math.hypot(dx, dy);
          }),
        );
        assert.ok(
          Math.abs(nearest - base.restingGap) < 1e-6,
          "idle reshaping holds neighbouring gaps constant",
        );
        for (const other of layout.tiles.slice(i + 1)) {
          const dx = Math.max(
            other.x - tile.x - tile.width,
            tile.x - other.x - other.width,
          );
          const dy = Math.max(
            other.y - tile.y - tile.height,
            tile.y - other.y - other.height,
          );
          assert.ok(
            Math.max(dx, dy) >= base.restingGap - 1e-6,
            "no pinching at diagonal junctions",
          );
        }
      });
    }
    assert.ok(
      largestGrowth > 0.025,
      "idle growth is noticeable rather than sub-percent",
    );
  }
});

test("idle handoffs and sequence wrap have continuous values and velocity", () => {
  const interval = 0.001;
  for (let seconds = 12; seconds <= 216; seconds += 12) {
    const before = heroIdleEmphasis(seconds - interval);
    const current = heroIdleEmphasis(seconds);
    const after = heroIdleEmphasis(seconds + interval);
    current.forEach((value, i) => {
      assert.ok(Math.abs(value - before[i]) < 1e-7);
      assert.ok(Math.abs(after[i] - value) < 1e-7);
      const incomingVelocity = (value - before[i]) / interval;
      const outgoingVelocity = (after[i] - value) / interval;
      assert.ok(Math.abs(incomingVelocity - outgoingVelocity) < 0.0001);
    });
  }
});

test("spring handoff from a coupled idle pulse to hover keeps clearance and continuity", () => {
  let values = HERO_TILES.map(() => 0);
  let velocities = HERO_TILES.map(() => 0);
  let seconds = 0;
  let previous = heroGridLayout(900, 700);
  const base = previous;
  for (let frame = 0; frame < 5400; frame++) {
    const selected = frame % 180 < 90
      ? null
      : Math.floor(frame / 180) % HERO_TILES.length;
    if (selected === null) seconds += 1 / 30;
    const idle = heroIdleEmphasis(seconds);
    values = values.map((value, i) => {
      const target = selected === null
        ? idle[i]
        : selected === i
        ? 1 + idle[i]
        : 0;
      const next = stepHeroSpring(value, velocities[i], target, 1 / 30);
      velocities[i] = next.velocity;
      return next.value;
    });
    const layout = heroGridLayout(900, 700, values);
    assertSharedGutters(base, layout);
    layout.tiles.forEach((tile, i) => {
      assert.ok(Math.abs(tile.width - previous.tiles[i].width) < 2);
      assert.ok(
        Math.hypot(tile.x - previous.tiles[i].x, tile.y - previous.tiles[i].y) <
          2,
      );
      for (const other of layout.tiles.slice(i + 1)) {
        const dx = Math.max(
          other.x - tile.x - tile.width,
          tile.x - other.x - other.width,
        );
        const dy = Math.max(
          other.y - tile.y - tile.height,
          tile.y - other.y - other.height,
        );
        assert.ok(Math.max(dx, dy) >= layout.gap - 1e-6);
      }
    });
    previous = layout;
  }
});

test("hover grows the frame and moves the mesh in both axes without overlaps", () => {
  for (const [width, height] of [[900, 700], [390, 340], [448, 600]]) {
    const base = heroGridLayout(width, height);
    for (let selected = 0; selected < HERO_TILES.length; selected++) {
      for (const progress of [0.2, 0.6, 1, 1.05]) {
        const emphasis = HERO_TILES.map((_, i) =>
          i === selected ? progress : 0
        );
        const layout = heroGridLayout(width, height, emphasis);
        assertSharedGutters(base, layout);
        assert.ok(
          layout.tiles.some((tile, i) =>
            tile.width < base.tiles[i].width - 1e-8
          ),
          "neighbours yield as the focus grows",
        );
        assert.equal(layout.gap, base.gap);
        layout.tiles.forEach((tile, i) => {
          const original = base.tiles[i];
          assert.ok(
            Math.abs(
              tile.width / tile.height - original.width / original.height,
            ) < 1e-8,
          );
          assert.ok(tile.width <= original.width * 1.019);
          const shiftX = tile.x + tile.width / 2 - original.x -
            original.width / 2;
          const shiftY = tile.y + tile.height / 2 - original.y -
            original.height / 2;
          if (i !== selected) assert.ok(Math.hypot(shiftX, shiftY) > 1e-9);
          if (i === selected) {
            assert.ok(
              tile.width > original.width && tile.height > original.height,
            );
          }
          for (const other of layout.tiles.slice(i + 1)) {
            const dx = Math.max(
              other.x - tile.x - tile.width,
              tile.x - other.x - other.width,
            );
            const dy = Math.max(
              other.y - tile.y - tile.height,
              tile.y - other.y - other.height,
            );
            assert.ok(Math.max(dx, dy) >= layout.gap - 1e-6);
          }
        });
      }
    }
  }
});

test("handoff between two hovered tiles keeps gutters while both frames are changing", () => {
  for (let from = 0; from < HERO_TILES.length; from++) {
    for (let to = 0; to < HERO_TILES.length; to++) {
      if (from === to) continue;
      for (const progress of [-0.05, 0, 0.25, 0.5, 0.75, 1, 1.05]) {
        const layout = heroGridLayout(
          800,
          700,
          HERO_TILES.map((_, i) =>
            i === from ? 1 - progress : i === to ? progress : 0
          ),
        );
        layout.tiles.forEach((tile, i) => {
          assert.ok(tile.width > 0 && tile.height > 0);
          assert.equal(tile.width, tile.height);
          for (const other of layout.tiles.slice(i + 1)) {
            const dx = Math.max(
              other.x - tile.x - tile.width,
              tile.x - other.x - other.width,
            );
            const dy = Math.max(
              other.y - tile.y - tile.height,
              tile.y - other.y - other.height,
            );
            assert.ok(Math.max(dx, dy) >= layout.gap - 1e-6);
          }
        });
      }
    }
  }
});

test("hover spring has a small overshoot and settles at different frame rates", () => {
  for (const fps of [30, 60, 120]) {
    let state = { value: 0, velocity: 0 };
    let peak = 0;
    for (let i = 0; i < fps * 3; i++) {
      state = stepHeroSpring(state.value, state.velocity, 1, 1 / fps);
      peak = Math.max(peak, state.value);
    }
    assert.ok(peak > 1.005 && peak < 1.015);
    assert.deepEqual(state, { value: 1, velocity: 0 });
    for (let i = 0; i < fps * 3; i++) {
      state = stepHeroSpring(state.value, state.velocity, 0, 1 / fps);
    }
    assert.deepEqual(state, { value: 0, velocity: 0 });
  }
});

test("spring retargeting preserves momentum and stays bounded during quick hover changes", () => {
  let state = { value: 0, velocity: 0 };
  for (let i = 0; i < 600; i++) {
    const target = Math.floor(i / 9) % 2;
    const before = state;
    state = stepHeroSpring(state.value, state.velocity, target, 1 / 60);
    assert.ok(Math.abs(state.value - before.value) < 0.12);
    assert.ok(state.value > -0.1 && state.value < 1.1);
  }
  const unchanged = stepHeroSpring(state.value, state.velocity, 1, 0);
  assert.ok(Math.abs(unchanged.value - state.value) < 1e-10);
  assert.ok(Math.abs(unchanged.velocity - state.velocity) < 1e-10);
});

test("resting mosaic preserves square-source framing with varied sizes", () => {
  for (const [width, height] of [[900, 700], [390, 340]]) {
    const layout = heroGridLayout(width, height);
    const feature = layout.tiles.reduce((largest, tile) =>
      tile.width * tile.height > largest.width * largest.height ? tile : largest
    );
    const oldSize = Math.max(width / 4.4, height / 4.4);
    const oldFeatureSide = 2 * oldSize +
      Math.max(10, Math.min(16, oldSize * 0.075));
    assert.ok(feature.width * feature.height < oldFeatureSide ** 2 * 0.75);
    const areas = layout.tiles.map((t) => Math.round(t.width * t.height));
    assert.ok(new Set(areas).size === 3);
    for (const tile of layout.tiles) {
      assert.equal(tile.width, tile.height);
    }
  }
});

test("mosaic mixes sizes and offsets seams instead of repeating full rows", () => {
  const { tiles, gap } = heroGridLayout(800, 700);
  const areas = tiles.map((t) => t.width * t.height);
  assert.ok(Math.max(...areas) / Math.min(...areas) > 1.7);
  // Larger squares sit beside multiple smaller squares with naturally varied gaps.
  const junctions = tiles.filter((a) =>
    tiles.filter((b) =>
      b.x - (a.x + a.width) >= gap - 1e-8 &&
      b.x - (a.x + a.width) <= gap + Math.min(a.width, b.width) * 0.25 &&
      Math.min(a.y + a.height, b.y + b.height) - Math.max(a.y, b.y) > 1
    ).length >= 2
  );
  assert.ok(junctions.length >= 2);
});

test("square tiling has balanced size variation and close neighbours", () => {
  const { tiles, restingGap } = heroGridLayout(800, 700);
  const sides = tiles.map((t) => t.width);
  assert.ok(Math.max(...sides) / Math.min(...sides) > 2);
  assert.ok(Math.max(...sides) / Math.min(...sides) < 2.2);
  const sizes = [...new Set(sides)].sort((a, b) => a - b);
  assert.ok(
    sides.filter((side) => side === sizes[1]).length > sides.length * 0.35,
    "medium squares remain well represented",
  );
  for (const tile of tiles) {
    const nearest = Math.min(
      ...tiles.filter((t) => t !== tile).map((other) => {
        const dx = Math.max(
          other.x - tile.x - tile.width,
          tile.x - other.x - other.width,
          0,
        );
        const dy = Math.max(
          other.y - tile.y - tile.height,
          tile.y - other.y - other.height,
          0,
        );
        return Math.hypot(dx, dy);
      }),
    );
    assert.ok(
      Math.abs(nearest - restingGap) < 1e-6,
      "each square meets a neighbour at the same gutter",
    );
  }
  const width = Math.max(...tiles.map((t) => t.x + t.width)) -
    Math.min(...tiles.map((t) => t.x));
  const height = Math.max(...tiles.map((t) => t.y + t.height)) -
    Math.min(...tiles.map((t) => t.y));
  assert.ok(
    tiles.reduce((sum, t) => sum + t.width * t.height, 0) / (width * height) >
      0.72,
  );
  const filledArea = tiles.reduce(
    (sum, t) => sum + (t.width + restingGap) ** 2,
    0,
  );
  assert.ok(
    Math.abs(filledArea - (width + restingGap) * (height + restingGap)) < 1e-6,
    "squares plus their gutters completely fill the footprint without pockets",
  );
  assert.deepEqual(heroGridLayout(800, 700).tiles, tiles);
});

test("local hover response stays small and returns exactly to the resting composition", () => {
  const base = heroGridLayout(800, 700);
  const selected = 0;
  const changed = heroGridLayout(
    800,
    700,
    HERO_TILES.map((_, i) => i === selected ? 1 : 0),
  );
  const distances = base.tiles.map((t) =>
    Math.hypot(
      t.x + t.width / 2 - base.tiles[selected].x -
        base.tiles[selected].width / 2,
      t.y + t.height / 2 - base.tiles[selected].y -
        base.tiles[selected].height / 2,
    )
  );
  const shifts = changed.tiles.map((t, i) =>
    Math.hypot(
      t.x + t.width / 2 - base.tiles[i].x - base.tiles[i].width / 2,
      t.y + t.height / 2 - base.tiles[i].y - base.tiles[i].height / 2,
    )
  );
  assert.ok(Math.max(...shifts) < 3, "shared response is only a few pixels");
  const furthest = distances.indexOf(Math.max(...distances));
  assert.ok(
    shifts[furthest] < Math.max(...shifts) / 4,
    "response fades across the field",
  );
  assert.deepEqual(heroGridLayout(800, 700, HERO_TILES.map(() => 0)), base);
});

test("composition interrupts long seams instead of repeating quadrant boundaries", () => {
  const { tiles, restingGap } = heroGridLayout(800, 700);
  const sizes = [...new Set(tiles.map((t) => t.width))].sort((a, b) => a - b);
  const unit = sizes[1] - sizes[0];
  const left = Math.min(...tiles.map((t) => t.x));
  const top = Math.min(...tiles.map((t) => t.y));
  const extent = Math.round(
    (Math.max(...tiles.map((t) => t.x + t.width)) - left + restingGap) / unit,
  );
  const cells = Array.from(
    { length: extent },
    () => Array<number>(extent).fill(-1),
  );
  tiles.forEach((tile, index) => {
    const x = Math.round((tile.x - left) / unit);
    const y = Math.round((tile.y - top) / unit);
    const span = Math.round((tile.width + restingGap) / unit);
    for (let row = y; row < y + span; row++) {
      for (let column = x; column < x + span; column++) {
        cells[row][column] = index;
      }
    }
  });
  for (let seam = 1; seam < extent; seam++) {
    let vertical = 0, horizontal = 0;
    for (let step = 0; step < extent; step++) {
      vertical = cells[step][seam] !== cells[step][seam - 1] ? vertical + 1 : 0;
      horizontal = cells[seam][step] !== cells[seam - 1][step]
        ? horizontal + 1
        : 0;
      assert.ok(
        Math.max(vertical, horizontal) <= Math.floor(extent * 0.72),
        "no long row or column divider",
      );
    }
  }
});
