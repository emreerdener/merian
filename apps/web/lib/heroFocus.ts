export const HERO_DRIFT_LIMIT = 24;
export const HERO_POINTER_LIMIT = 6;

type Rect = { x: number; y: number; width: number; height: number };

// One complete, non-repeating composition: staggered T-junctions interrupt
// long seams, while smaller squares fill the pockets between larger anchors.
// Equal insets give every shared edge the same gutter. Slots never reshuffle.
const TILE_GUTTER = 0.16 * 7 / 6;
export const HERO_TILES = [
  [0, 0, 2],
  [2, 0, 4],
  [6, 0, 3],
  [9, 0, 3],
  [12, 0, 2],
  [0, 2, 2],
  [12, 2, 2],
  [6, 3, 2],
  [8, 3, 2],
  [10, 3, 2],
  [0, 4, 3],
  [3, 4, 3],
  [12, 4, 2],
  [6, 5, 3],
  [9, 5, 3],
  [12, 6, 2],
  [0, 7, 3],
  [3, 7, 3],
  [6, 8, 2],
  [8, 8, 3],
  [11, 8, 3],
  [0, 10, 4],
  [4, 10, 4],
  [8, 11, 3],
  [11, 11, 3],
].map(([x, y, span]) => ({
  x: x + TILE_GUTTER / 2,
  y: y + TILE_GUTTER / 2,
  side: span - TILE_GUTTER,
}));

const restingSquares: Rect[] = HERO_TILES.map(({ x, y, side }) => ({
  x,
  y,
  width: side,
  height: side,
}));
const packingBounds = {
  left: Math.min(...restingSquares.map((t) => t.x)),
  right: Math.max(...restingSquares.map((t) => t.x + t.width)),
  top: Math.min(...restingSquares.map((t) => t.y)),
  bottom: Math.max(...restingSquares.map((t) => t.y + t.height)),
};

// Solve the fixed neighbour relationships once, rather than independently
// scaling photos or repacking them every frame. Each shared edge constrains
// both centres and sizes, keeping its original gutter throughout a pulse.
const SIZE_WEIGHT = 2;
const dot = (a: number[], b: number[]) =>
  a.reduce((sum, value, i) => sum + value * b[i], 0);

function meshResponses() {
  const dimensions = HERO_TILES.length * 3;
  const basis: number[][] = [];
  function constrain(row: number[]) {
    // Re-orthogonalization also handles redundant constraints at junctions.
    for (let pass = 0; pass < 2; pass++) {
      for (const vector of basis) {
        const projection = dot(row, vector);
        row = row.map((value, i) => value - projection * vector[i]);
      }
    }
    const norm = Math.sqrt(dot(row, row));
    if (norm > 1e-10) basis.push(row.map((value) => value / norm));
  }
  HERO_TILES.forEach((a, i) => {
    HERO_TILES.forEach((b, j) => {
      if (i === j) return;
      const dx = b.x + b.side / 2 - a.x - a.side / 2;
      const dy = b.y + b.side / 2 - a.y - a.side / 2;
      const cornerDistance = (a.side + b.side) / 2 + TILE_GUTTER;
      if (
        i < j && Math.abs(Math.abs(dx) - cornerDistance) < 1e-8 &&
        Math.abs(Math.abs(dy) - cornerDistance) < 1e-8
      ) {
        // At diagonal junctions preserve the combined clearance, allowing a
        // little tangential movement without pinching the corner shut.
        const row = Array<number>(dimensions).fill(0);
        row[i * 3] = -Math.sign(dx);
        row[j * 3] = Math.sign(dx);
        row[i * 3 + 1] = -Math.sign(dy);
        row[j * 3 + 1] = Math.sign(dy);
        row[i * 3 + 2] = row[j * 3 + 2] = -1 / SIZE_WEIGHT;
        constrain(row);
      }
      for (const axis of [0, 1]) {
        const start = axis === 0 ? "x" : "y";
        const cross = axis === 0 ? "y" : "x";
        const touching =
          Math.abs(b[start] - a[start] - a.side - TILE_GUTTER) < 1e-8;
        const overlap = Math.min(a[cross] + a.side, b[cross] + b.side) -
          Math.max(a[cross], b[cross]);
        if (!touching || overlap <= 0) continue;
        const row = Array<number>(dimensions).fill(0);
        row[i * 3 + axis] = -1;
        row[j * 3 + axis] = 1;
        row[i * 3 + 2] = row[j * 3 + 2] = -0.5 / SIZE_WEIGHT;
        constrain(row);
      }
    });
  });
  return HERO_TILES.map((selected, index) => {
    let response = Array<number>(dimensions).fill(0);
    response[index * 3 + 2] = selected.side * 0.018 * SIZE_WEIGHT;
    for (const vector of basis) {
      const projection = dot(response, vector);
      response = response.map((value, i) => value - projection * vector[i]);
    }
    // Some junctions must grow together; cap the strongest relative change
    // instead of amplifying a smaller tile beyond the intended microinteraction.
    const peakGrowth = Math.max(
      ...HERO_TILES.map((tile, i) =>
        response[i * 3 + 2] / SIZE_WEIGHT / tile.side
      ),
    );
    const normalization = 0.018 / peakGrowth;
    return HERO_TILES.map((_, i) => ({
      x: response[i * 3] * normalization,
      y: response[i * 3 + 1] * normalization,
      side: response[i * 3 + 2] * normalization / SIZE_WEIGHT,
    }));
  });
}

const responses = meshResponses();

/** Stable composition with a continuous, local response shared by neighbours. */
export function heroGridLayout(
  width: number,
  height: number,
  emphasis: readonly number[] = [],
) {
  const size = Math.max(width / 5, height / 5);
  const packedWidth = packingBounds.right - packingBounds.left;
  const packedHeight = packingBounds.bottom - packingBounds.top;
  const unit = 0.97 * Math.max(
    (width + 2 * (HERO_DRIFT_LIMIT + HERO_POINTER_LIMIT) + size) / packedWidth,
    (height + 2 * (HERO_DRIFT_LIMIT + HERO_POINTER_LIMIT) + size) /
      packedHeight,
  );
  const restingGap = TILE_GUTTER * unit;
  const gap = restingGap;
  const tiles = restingSquares.map((tile) => ({
    x: width / 2 +
      (tile.x - (packingBounds.left + packingBounds.right) / 2) * unit,
    y: height / 2 +
      (tile.y - (packingBounds.top + packingBounds.bottom) / 2) * unit,
    width: tile.width * unit,
    height: tile.height * unit,
  }));
  // Responses are linear: hover handoffs preserve the same edge constraints.
  const anchors = tiles.map((tile) => ({
    x: tile.x + tile.width / 2,
    y: tile.y + tile.height / 2,
  }));
  const deformed = tiles.map((tile, index) => {
    let side = tile.width, shiftX = 0, shiftY = 0;
    emphasis.forEach((amount, selected) => {
      if (!amount || !responses[selected]) return;
      const response = responses[selected][index];
      side += response.side * amount * unit;
      shiftX += response.x * amount * unit;
      shiftY += response.y * amount * unit;
    });
    return {
      x: anchors[index].x + shiftX - side / 2,
      y: anchors[index].y + shiftY - side / 2,
      width: side,
      height: side,
    };
  });
  // No collision/repacking pass: restrained motion uses the clearance already
  // in the composition, so crossing a contact never switches a separation axis.
  return { size, gap, restingGap, tiles: deformed };
}

/** Slow, bounded motion leaves enough overscan at every viewport edge. */
export function heroIdleOffset(seconds: number) {
  return {
    x: Math.sin(seconds * Math.PI / 42) * HERO_DRIFT_LIMIT,
    y: Math.sin(seconds * Math.PI / 52) * HERO_DRIFT_LIMIT * 0.65,
  };
}

/** Transfer one bounded pulse between neighbours in the focus sequence. */
export function heroIdleEmphasis(seconds: number) {
  const emphasis = HERO_TILES.map(() => 0);
  const sequence = [14, 17, 19, 7, 24, 10, 20, 3, 22];
  const step = Math.floor(seconds / 12);
  const phase = (seconds % 12) / 12;
  // Complementary easing overlaps the outgoing and incoming focus without
  // stacking their strength. Shared edge constraints remain linear throughout.
  const blend = (1 - Math.cos(phase * Math.PI)) / 2;
  emphasis[sequence[step % sequence.length]] = 1.6 * (1 - blend);
  emphasis[sequence[(step + 1) % sequence.length]] = 1.6 * blend;
  return emphasis;
}

/** Exact damped spring step: a soft overshoot, stable across frame rates. */
export function stepHeroSpring(
  value: number,
  velocity: number,
  target: number,
  seconds: number,
) {
  const frequency = 6;
  const damping = 0.82;
  const decayRate = frequency * damping;
  const dampedFrequency = frequency * Math.sqrt(1 - damping * damping);
  const offset = value - target;
  const decay = Math.exp(-decayRate * seconds);
  const cosine = Math.cos(dampedFrequency * seconds);
  const sine = Math.sin(dampedFrequency * seconds);
  const nextValue = target +
    decay *
      (offset * cosine +
        (velocity + decayRate * offset) / dampedFrequency * sine);
  const nextVelocity = decay *
    (velocity * cosine -
      (decayRate * velocity + frequency * frequency * offset) /
        dampedFrequency * sine);
  if (Math.abs(nextValue - target) < 0.0001 && Math.abs(nextVelocity) < 0.001) {
    return { value: target, velocity: 0 };
  }
  return { value: nextValue, velocity: nextVelocity };
}
