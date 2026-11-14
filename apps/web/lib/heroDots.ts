export const HERO_DOT_SPACING = 32;
const HOVER_RADIUS = 180;

/** Smooth local expansion with no discontinuity at the edge of the hover field. */
export function heroDotTarget(dx: number, dy: number, active: boolean) {
  const distance = Math.hypot(dx, dy) / HOVER_RADIUS;
  const glow = active ? Math.max(0, 1 - distance * distance) ** 3 : 0;
  return { x: dx * 0.08 * glow, y: dy * 0.08 * glow, glow };
}

/** Exact damped spring step: independent of display refresh rate. */
export function stepDotSpring(
  value: number,
  velocity: number,
  target: number,
  dt: number,
  frequency = 12,
) {
  const damping = 0.78;
  const decay = frequency * damping;
  const oscillation = frequency * Math.sqrt(1 - damping * damping);
  const offset = value - target;
  const coefficient = (velocity + decay * offset) / oscillation;
  const time = Math.max(0, Math.min(dt, 0.05));
  const envelope = Math.exp(-decay * time);
  const sine = Math.sin(oscillation * time);
  const cosine = Math.cos(oscillation * time);
  const next = envelope * (offset * cosine + coefficient * sine);
  return {
    value: target + next,
    velocity: envelope * oscillation * (-offset * sine + coefficient * cosine) -
      decay * next,
  };
}
