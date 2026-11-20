import assert from "node:assert/strict";
import test from "node:test";
import { isHeroPointVisible } from "./heroMask.ts";

test("hover follows mask opacity instead of its rectangular bounds", () => {
  const mask = {
    width: 2,
    height: 2,
    data: new Uint8ClampedArray([
      255,
      255,
      255,
      0,
      255,
      255,
      255,
      255,
      255,
      255,
      255,
      180,
      255,
      255,
      255,
      40,
    ]),
  };
  assert.equal(isHeroPointVisible(mask, "desktop", 0.25, 0.25), false);
  assert.equal(isHeroPointVisible(mask, "desktop", 0.75, 0.25), true);
  assert.equal(isHeroPointVisible(mask, "desktop", 0.25, 0.75), true);
  assert.equal(isHeroPointVisible(mask, "desktop", 0.75, 0.75), false);
  assert.equal(isHeroPointVisible(mask, "centered", 0.25, 0.25), false);
  assert.equal(isHeroPointVisible(mask, "centered", 0.75, 0.25), true);
});

test("outer feathers exclude faded seams in both responsive layouts", () => {
  const mask = {
    width: 1,
    height: 1,
    data: new Uint8ClampedArray([255, 255, 255, 255]),
  };
  assert.equal(isHeroPointVisible(mask, "desktop", 0.005, 0.5), false);
  assert.equal(isHeroPointVisible(mask, "centered", 0.005, 0.5), true);
  assert.equal(isHeroPointVisible(mask, "stacked", 0.005, 0.5), true);
  assert.equal(isHeroPointVisible(mask, "desktop", 0.5, 0.005), true);
  assert.equal(isHeroPointVisible(mask, "stacked", 0.5, 0.005), false);
  for (const layout of ["desktop", "stacked", "centered", "radial"] as const) {
    assert.equal(isHeroPointVisible(mask, layout, 0.5, 0.995), false);
    assert.equal(isHeroPointVisible(mask, layout, 0.5, 0.5), true);
    for (const x of [-0.1, 1, NaN, Infinity]) {
      assert.equal(isHeroPointVisible(mask, layout, x, 0.5), false);
      assert.equal(isHeroPointVisible(mask, layout, 0.5, x), false);
    }
  }
  assert.equal(isHeroPointVisible(undefined, "desktop", 0.5, 0.5), false);
});
