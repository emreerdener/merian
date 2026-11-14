/** Browser-safe, minimal public discovery contract. No scan or account IDs. */
export type ExploreCard = {
  id: string;
  label: string;
  poster: string | null;
};

export type ExplorePage = {
  items: ExploreCard[];
  nextCursor: string | null;
  hasMore: boolean;
};

export type Point = { x: number; y: number };

/** Stable square spiral: appended pages never relocate existing observations. */
export function cellAt(index: number): Point {
  if (index === 0) return { x: 0, y: 0 };
  const ring = Math.ceil((Math.sqrt(index + 1) - 1) / 2);
  const side = 2 * ring;
  const offset = index - (2 * ring - 1) ** 2;
  if (offset < side) return { x: ring, y: -ring + 1 + offset };
  if (offset < side * 2) return { x: ring - 1 - (offset - side), y: ring };
  if (offset < side * 3) return { x: -ring, y: ring - 1 - (offset - side * 2) };
  return { x: -ring + 1 + (offset - side * 3), y: -ring };
}

/** Inverse spiral address, keeping viewport work independent of feed length. */
export function indexAtCell(x: number, y: number): number {
  const r = Math.max(Math.abs(x), Math.abs(y));
  if (!r) return 0;
  const base = (2 * r - 1) ** 2;
  if (x === r && y > -r) return base + y + r - 1;
  if (y === r) return base + 2 * r + r - 1 - x;
  if (x === -r) return base + 4 * r + r - 1 - y;
  return base + 6 * r + x + r - 1;
}

/** Output pixel -> undistorted scene. Must match the screen-space shader. */
export function lensPoint(
  point: Point,
  width: number,
  height: number,
  bend: number,
): Point {
  const x = 2 * point.x / width - 1;
  const y = 2 * point.y / height - 1;
  const factor = 1 + bend * (x * x + y * y);
  return { x: x * factor * width / 2, y: y * factor * height / 2 };
}

export function cardAtPoint(
  point: Point,
  pan: Point,
  zoom: number,
  pitch: number,
  size: number,
  count: number,
  radius = size < 200 ? 12 : 16,
): number {
  const x = (point.x - pan.x) / zoom;
  const y = (point.y - pan.y) / zoom;
  const cellX = Math.round(x / pitch);
  const cellY = Math.round(y / pitch);
  const dx = Math.abs(x - cellX * pitch);
  const dy = Math.abs(y - cellY * pitch);
  // Rounded-corner hit testing, not just the enclosing square.
  if (
    Math.hypot(
      Math.max(dx - (size / 2 - radius), 0),
      Math.max(dy - (size / 2 - radius), 0),
    ) > radius
  ) return -1;
  const index = indexAtCell(cellX, cellY);
  return index < count ? index : -1;
}

export function mergeCards(
  current: ExploreCard[],
  incoming: ExploreCard[],
): ExploreCard[] {
  const ids = new Set(current.map((item) => item.id));
  return [
    ...current,
    ...incoming.filter((item) => {
      if (ids.has(item.id)) return false;
      ids.add(item.id);
      return true;
    }),
  ];
}

/** Viewport coverage includes the lens corners and worst-case drag zoom. */
export function exploreViewportLayout(width: number, height: number) {
  const mobile = width < 768;
  const gap = mobile ? 8 : 12;
  const bend = mobile ? .035 : .075;
  let size = mobile ? 150 : 240;
  const factor = 1 + 2 * bend;
  while (
    (Math.ceil(width * factor / ((size + gap) * .94)) + 3) *
        (Math.ceil(height * factor / ((size + gap) * .94)) + 3) > 96
  ) size += 12;
  // Increase the composed photo size after the viewport coverage calculation,
  // including on large displays where the minimum size is already adaptive.
  size = Math.round(size * 1.25);
  return { size, gap, pitch: size + gap, bend, radius: mobile ? 12 : 16 };
}

export function visibleCanvasCells(
  width: number,
  height: number,
  pan: Point,
  pitch: number,
  zoom: number,
  bend: number,
) {
  const halfWidth = width * (1 + 2 * bend) / 2;
  const halfHeight = height * (1 + 2 * bend) / 2;
  const unit = pitch * zoom;
  const cells: Array<Point & { index: number }> = [];
  for (
    let y = Math.floor((-halfHeight - pan.y) / unit);
    y <= Math.ceil((halfHeight - pan.y) / unit);
    y++
  ) {
    for (
      let x = Math.floor((-halfWidth - pan.x) / unit);
      x <= Math.ceil((halfWidth - pan.x) / unit);
      x++
    ) {
      cells.push({ x, y, index: indexAtCell(x, y) });
    }
  }
  return cells;
}

/** Scene -> screen, the inverse of the shared shader's texture sampling. */
export function projectLensPoint(
  point: Point,
  width: number,
  height: number,
  bend: number,
): Point {
  const x = point.x * 2 / width, y = point.y * 2 / height;
  const distance = Math.hypot(x, y);
  let radius = distance;
  for (let i = 0; i < 8; i++) {
    radius -= (radius * (1 + bend * radius * radius) - distance) /
      (1 + 3 * bend * radius * radius);
  }
  const ratio = distance ? radius / distance : 1;
  return { x: (x * ratio + 1) * width / 2, y: (y * ratio + 1) * height / 2 };
}

export function curvedSkeletonPath(
  x: number,
  y: number,
  width: number,
  height: number,
) {
  const { size, pitch, radius, bend } = exploreViewportLayout(width, height);
  const half = size / 2 - radius;
  const corners = [[half, -half], [half, half], [-half, half], [-half, -half]];
  const points: Point[] = [];
  for (let corner = 0; corner < 4; corner++) {
    const [cx, cy] = corners[corner], [nx, ny] = corners[(corner + 1) % 4];
    const start = (corner - 1) * Math.PI / 2;
    for (let step = 0; step <= 4; step++) {
      const angle = start + step / 4 * Math.PI / 2;
      points.push({
        x: cx + radius * Math.cos(angle),
        y: cy + radius * Math.sin(angle),
      });
    }
    const end = start + Math.PI / 2;
    for (let step = 1; step < 6; step++) {
      points.push({
        x: cx + (nx - cx) * step / 6 + radius * Math.cos(end),
        y: cy + (ny - cy) * step / 6 + radius * Math.sin(end),
      });
    }
  }
  return points.map((point, i) => {
    const projected = projectLensPoint(
      { x: point.x + x * pitch, y: point.y + y * pitch },
      width,
      height,
      bend,
    );
    return `${i ? "L" : "M"}${projected.x.toFixed(2)},${
      projected.y.toFixed(2)
    }`;
  }).join(" ") + "Z";
}
