import assert from "node:assert/strict";
import test from "node:test";
import { heroDotTarget, stepDotSpring } from "./heroDots.ts";

test("dot expansion stays local and does not fold or reverse the dot spacing", () => {
  assert.deepEqual(heroDotTarget(0, 0, true), { x: 0, y: 0, glow: 1 });
  assert.equal(heroDotTarget(180, 0, true).glow, 0);
  assert.equal(heroDotTarget(400, 200, true).glow, 0);
  assert.equal(heroDotTarget(50, 0, false).glow, 0);
  let previous = -Infinity;
  for (let x = -250; x <= 250; x++) {
    const target = heroDotTarget(x, 0, true);
    assert.ok(x + target.x > previous);
    assert.ok(Math.abs(target.x) < 4);
    assert.ok(target.glow >= 0 && target.glow <= 1);
    previous = x + target.x;
  }
  assert.ok(heroDotTarget(32, 0, true).x > 2);
  assert.ok(heroDotTarget(32, 0, true).x < 3);
});

test("scroll release preserves the visible effect and fades it gradually", () => {
  for (const rate of [30, 60, 120]) {
    let state = { value: 1, velocity: 0 };
    state = stepDotSpring(state.value, state.velocity, 0, 1 / rate, 6);
    assert.ok(
      state.value > 0.98,
      "first scroll frame must not erase the effect",
    );
    for (let frame = 1; frame < rate / 2; frame++) {
      state = stepDotSpring(state.value, state.velocity, 0, 1 / rate, 6);
    }
    assert.ok(state.value > 0.05 && state.value < 0.2);
    for (let frame = 0; frame < rate * 2; frame++) {
      state = stepDotSpring(state.value, state.velocity, 0, 1 / rate, 6);
    }
    assert.ok(Math.abs(state.value) < 0.0001);
  }
});

test("dot springs gently overshoot, settle, and release at different refresh rates", () => {
  for (const rate of [30, 60, 120]) {
    let state = { value: 0, velocity: 0 };
    let peak = 0;
    for (let frame = 0; frame < rate * 2; frame++) {
      state = stepDotSpring(state.value, state.velocity, 1, 1 / rate);
      peak = Math.max(peak, state.value);
    }
    assert.ok(peak > 1 && peak < 1.025);
    assert.ok(Math.abs(state.value - 1) < 0.0001);
    for (let frame = 0; frame < rate * 2; frame++) {
      state = stepDotSpring(state.value, state.velocity, 0, 1 / rate);
    }
    assert.ok(Math.abs(state.value) < 0.0001);
    assert.ok(Math.abs(state.velocity) < 0.0001);
  }
});
