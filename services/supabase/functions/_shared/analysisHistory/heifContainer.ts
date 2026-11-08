/** Private HEVC still-item increment. Bounds item/property/extents and NAL
 * framing, not HEVC parameter-set semantics, pixels or metadata interpretation.
 * Nested grids/non-alpha auxiliary/sequence/other-codec forms remain unqualified. */
export class HeifContainerRejected extends Error {}
const requireValue = (ok: boolean): void => {
  if (!ok) throw new HeifContainerRejected();
};
type Box = { type: string; start: number; end: number };
export interface HeifContainerLimits {
  maximumBytes: number;
  maximumWidth: number;
  maximumHeight: number;
  maximumPixels: number;
}
class Reader {
  at: number;
  constructor(readonly bytes: Uint8Array, readonly end: number, start: number) {
    this.at = start;
  }
  uint(n: number): number {
    requireValue(n >= 0 && n <= 8 && n <= this.end - this.at);
    let result = 0n;
    for (let i = 0; i < n; i++) {
      result = result * 256n + BigInt(this.bytes[this.at++]);
    }
    requireValue(result <= BigInt(Number.MAX_SAFE_INTEGER));
    return Number(result);
  }
  tag(): string {
    return String.fromCharCode(
      ...Array.from({ length: 4 }, () => this.uint(1)),
    );
  }
  zeroString(): string {
    const start = this.at;
    while (
      this.at < this.end && this.bytes[this.at] !== 0 && this.at - start <= 4096
    ) this.at++;
    requireValue(this.at < this.end && this.at - start <= 4096);
    const result = new TextDecoder("utf-8", { fatal: true }).decode(
      this.bytes.subarray(start, this.at),
    );
    this.at++;
    return result;
  }
  done() {
    requireValue(this.at === this.end);
  }
}
export function inspectHeifContainer(
  bytes: Uint8Array,
  mime: "image/heic" | "image/heif",
  limits: HeifContainerLimits,
  checkpoint: () => void = () => {},
): { width: number; height: number; primaryItem: number } {
  for (
    const [key, max] of [
      ["maximumBytes", 33_554_432],
      ["maximumWidth", 65535],
      ["maximumHeight", 65535],
      ["maximumPixels", 65535 ** 2],
    ] as const
  ) {
    requireValue(
      Number.isSafeInteger(limits[key]) && limits[key] > 0 &&
        limits[key] <= max,
    );
  }
  requireValue(
    bytes.length >= 32 && bytes.length <= limits.maximumBytes &&
      (mime === "image/heic" || mime === "image/heif"),
  );
  let budget = 2048;
  const read = (b: Box) => new Reader(bytes, b.end, b.start);
  const full = (b: Box, versions: number[], allowedFlags = 0) => {
    const r = read(b), version = r.uint(1), flags = r.uint(3);
    requireValue(versions.includes(version) && (flags & ~allowedFlags) === 0);
    return { r, version, flags };
  };
  function boxes(start: number, end: number): Box[] {
    const result: Box[] = [];
    const r = new Reader(bytes, end, start);
    while (r.at < end) {
      checkpoint();
      requireValue(--budget >= 0 && end - r.at >= 8);
      const at = r.at;
      let size = r.uint(4);
      const type = r.tag();
      if (size === 1) size = r.uint(8);
      requireValue(size >= r.at - at && size <= end - at);
      result.push({ type, start: r.at, end: at + size });
      r.at = at + size;
    }
    return result;
  }
  const one = (all: Box[], type: string): Box => {
    const found = all.filter((b) => b.type === type);
    requireValue(found.length === 1);
    return found[0];
  };
  const only = (all: Box[], allowed: string[]) =>
    requireValue(all.every((b) => allowed.includes(b.type)));
  const top = boxes(0, bytes.length);
  requireValue(top.length <= 32 && top[0]?.type === "ftyp");
  only(top, ["ftyp", "meta", "mdat", "free", "skip"]);
  const ftyp = read(one(top, "ftyp"));
  const major = ftyp.tag();
  ftyp.uint(4);
  const brands = new Set([major]);
  requireValue((ftyp.end - ftyp.at) % 4 === 0 && ftyp.end - ftyp.at <= 128);
  while (ftyp.at < ftyp.end) brands.add(ftyp.tag());
  // A generic HEIF declaration is accepted only with a supported HEVC still
  // brand too. Sequence/AVIF brands cannot masquerade as this closed profile.
  requireValue(
    ["heic", "heix", "mif1"].includes(major) &&
      [...brands].every((b) =>
        ["heic", "heix", "mif1", "miaf", "MiPr", "MiHB", "MiHE"].includes(b)
      ) &&
      (brands.has("heic") || brands.has("heix")) && brands.has("mif1"),
  );
  const meta = full(one(top, "meta"), [0]);
  const children = boxes(meta.r.at, meta.r.end);
  only(children, [
    "hdlr",
    "pitm",
    "iinf",
    "iloc",
    "iprp",
    "iref",
    "idat",
    "dinf",
  ]);
  requireValue(new Set(children.map((b) => b.type)).size === children.length);
  const dinf = children.find((b) => b.type === "dinf");
  if (dinf) {
    const entries = boxes(dinf.start, dinf.end);
    requireValue(entries.length === 1);
    const dref = full(one(entries, "dref"), [0]).r;
    requireValue(dref.uint(4) === 1);
    const locations = boxes(dref.at, dref.end);
    requireValue(locations.length === 1);
    const url = full(one(locations, "url "), [0], 1);
    requireValue(url.flags === 1);
    url.r.done(); // Self-contained only; no URL payload.
  }
  const handler = full(one(children, "hdlr"), [0]).r;
  requireValue(handler.uint(4) === 0 && handler.tag() === "pict");
  requireValue(
    handler.uint(4) === 0 && handler.uint(4) === 0 && handler.uint(4) === 0,
  );
  if (handler.at < handler.end) handler.zeroString();
  handler.done();
  const primary = full(one(children, "pitm"), [0, 1]);
  const primaryItem = primary.r.uint(primary.version ? 4 : 2);
  primary.r.done();
  requireValue(primaryItem > 0);
  const info = full(one(children, "iinf"), [0, 1]);
  const count = info.r.uint(info.version ? 4 : 2);
  requireValue(count > 0 && count <= 256);
  const entries = boxes(info.r.at, info.r.end);
  requireValue(entries.length === count);
  const items = new Map<number, string>();
  const hidden = new Set<number>();
  for (const entry of entries) {
    requireValue(entry.type === "infe");
    const { r, version, flags } = full(entry, [2, 3], 1);
    const id = r.uint(version === 2 ? 2 : 4);
    requireValue(id > 0 && !items.has(id) && r.uint(2) === 0);
    const type = r.tag();
    requireValue(["hvc1", "grid", "Exif", "mime"].includes(type));
    requireValue(id !== primaryItem || flags === 0);
    r.zeroString();
    if (type === "mime") {
      requireValue(r.zeroString() === "application/rdf+xml");
      if (r.at < r.end) requireValue(r.zeroString() === "");
    }
    r.done();
    items.set(id, type);
    if (flags & 1) hidden.add(id);
  }
  const isImage = (id: number) =>
    ["hvc1", "grid"].includes(items.get(id) ?? "");
  requireValue(isImage(primaryItem));
  const gridTargets = new Map<number, number[]>();
  let alphaItem: number | undefined;
  // Single-level coded-image grids only: no recursive derived-item traversal.
  const refs = children.find((b) => b.type === "iref");
  if (refs) {
    const { r, version } = full(refs, [0, 1]);
    const seen = new Set<string>();
    let referenceBudget = 1024;
    for (const ref of boxes(r.at, r.end)) {
      requireValue(["thmb", "cdsc", "dimg", "auxl"].includes(ref.type));
      const rr = read(ref), from = rr.uint(version ? 4 : 2), n = rr.uint(2);
      requireValue(
        items.has(from) && n > 0 && n <= 256 && (referenceBudget -= n) >= 0,
      );
      requireValue(
        ref.type === "dimg"
          ? items.get(from) === "grid"
          : (ref.type === "thmb" || ref.type === "auxl")
          ? isImage(from)
          : ["Exif", "mime"].includes(items.get(from) ?? ""),
      );
      if (ref.type === "auxl") {
        requireValue(
          alphaItem === undefined && n === 1 && hidden.has(from) &&
            from !== primaryItem,
        );
        alphaItem = from;
      }
      const targets: number[] = [];
      if (ref.type === "dimg") requireValue(!gridTargets.has(from));
      for (let i = 0; i < n; i++) {
        const to = rr.uint(version ? 4 : 2), key = `${ref.type}:${from}:${to}`;
        requireValue(
          isImage(to) && to !== from && !seen.has(key) &&
            (!["thmb", "auxl"].includes(ref.type) || to === primaryItem) &&
            (ref.type !== "dimg" || items.get(to) === "hvc1"),
        );
        seen.add(key);
        targets.push(to);
      }
      if (ref.type === "dimg") gridTargets.set(from, targets);
      rr.done();
    }
  }
  const locations = full(one(children, "iloc"), [0, 1, 2]);
  const lr = locations.r, widths = lr.uint(1), widths2 = lr.uint(1);
  const offsetSize = widths >>> 4,
    lengthSize = widths & 15,
    baseSize = widths2 >>> 4,
    indexSize = widths2 & 15;
  requireValue(
    [0, 4, 8].includes(offsetSize) && [4, 8].includes(lengthSize) &&
      [0, 4, 8].includes(baseSize) && indexSize === 0,
  );
  requireValue(lr.uint(locations.version === 2 ? 4 : 2) === items.size);
  const extents = new Map<number, { start: number; end: number }[]>();
  const allSpans: { start: number; end: number }[] = [];
  let extentBudget = 1024;
  const media = top.filter((b) => b.type === "mdat");
  const idat = children.find((b) => b.type === "idat");
  for (let i = 0; i < items.size; i++) {
    checkpoint();
    const id = lr.uint(locations.version === 2 ? 4 : 2);
    requireValue(items.has(id) && !extents.has(id));
    const method = locations.version ? lr.uint(2) : 0;
    requireValue((method === 0 || method === 1) && lr.uint(2) === 0);
    const base = lr.uint(baseSize), n = lr.uint(2);
    requireValue(n > 0 && n <= 256 && (extentBudget -= n) >= 0);
    const spans = [];
    for (let j = 0; j < n; j++) {
      const offset = lr.uint(offsetSize), length = lr.uint(lengthSize);
      const origin = method === 1 ? idat?.start : 0;
      requireValue(
        origin !== undefined && base <= bytes.length &&
          offset <= bytes.length && length > 0,
      );
      const start = (origin ?? 0) + base + offset, end = start + length;
      const containers = method === 1 && idat ? [idat] : media;
      requireValue(
        Number.isSafeInteger(end) &&
          containers.some((b) => start >= b.start && end <= b.end),
      );
      spans.push({ start, end });
      allSpans.push({ start, end });
    }
    extents.set(id, spans);
  }
  lr.done();
  allSpans.sort((a, b) => a.start - b.start);
  requireValue(allSpans.every((s, i) => !i || allSpans[i - 1].end <= s.start));
  const properties = boxes(
    one(children, "iprp").start,
    one(children, "iprp").end,
  );
  only(properties, ["ipco", "ipma"]);
  const container = one(properties, "ipco"),
    props = boxes(container.start, container.end);
  requireValue(props.length > 0 && props.length <= 256);
  only(props, ["ispe", "hvcC", "pixi", "colr", "irot", "imir", "clli", "auxC"]);
  const associations = full(one(properties, "ipma"), [0, 1], 1);
  const ar = associations.r, associationCount = ar.uint(4);
  requireValue(associationCount > 0 && associationCount <= items.size);
  const attached = new Map<number, { box: Box; essential: boolean }[]>();
  for (let i = 0; i < associationCount; i++) {
    const id = ar.uint(associations.version ? 4 : 2), n = ar.uint(1);
    requireValue(items.has(id) && !attached.has(id) && n <= 32);
    const chosen = [], indices = new Set<number>();
    for (let j = 0; j < n; j++) {
      const wide = Boolean(associations.flags & 1), raw = ar.uint(wide ? 2 : 1);
      const index = raw & (wide ? 0x7fff : 0x7f);
      requireValue(index > 0 && index <= props.length && !indices.has(index));
      indices.add(index);
      chosen.push({
        box: props[index - 1],
        essential: Boolean(raw & (wide ? 0x8000 : 0x80)),
      });
    }
    attached.set(id, chosen);
  }
  ar.done();
  requireValue(
    new Set([...attached.values()].flatMap((v) => v.map((p) => p.box))).size ===
      props.length,
  );
  let dimensions: { width: number; height: number } | undefined;
  let pixels = 0;
  const imageSizes = new Map<number, { width: number; height: number }>();
  const imageConfigs = new Map<number, Box>();
  const chromaFormats = new Map<number, number>();
  const channels = new Map<number, number>();
  const orientations = new Map<number, string>();
  const alphaProperties = new Set<number>();
  const transformed = new Set<number>();
  const grids: {
    id: number;
    rows: number;
    columns: number;
    width: number;
    height: number;
  }[] = [];
  for (const [id, type] of items) {
    checkpoint();
    if (!isImage(id)) {
      requireValue(!attached.get(id)?.length);
      continue; // Opaque bounded metadata extents, not metadata semantics.
    }
    const chosen = attached.get(id) ?? [];
    requireValue(new Set(chosen.map((p) => p.box.type)).size === chosen.length);
    const imageProps = chosen.map((p) => p.box);
    orientations.set(
      id,
      imageProps.filter((p) => p.type === "irot" || p.type === "imir")
        .map((p) => `${p.type}:${bytes[p.start]}`).join(","),
    );
    if (
      imageProps.some((p) =>
        p.type === "imir" || (p.type === "irot" && bytes[p.start] !== 0)
      )
    ) transformed.add(id);
    const size = full(one(imageProps, "ispe"), [0]).r;
    const width = size.uint(4), height = size.uint(4);
    size.done();
    if (type === "hvc1") pixels += width * height;
    imageSizes.set(id, { width, height });
    requireValue(
      width > 0 && height > 0 && width <= limits.maximumWidth &&
        height <= limits.maximumHeight &&
        width * height <= limits.maximumPixels &&
        pixels <= limits.maximumPixels,
    );
    if (id === primaryItem) dimensions = { width, height };
    if (type === "grid") {
      requireValue(!imageProps.some((p) => p.type === "hvcC"));
      const spans = extents.get(id)!;
      requireValue(spans.length === 1);
      const gr = new Reader(bytes, spans[0].end, spans[0].start);
      requireValue(gr.uint(1) === 0);
      const flags = gr.uint(1);
      requireValue(flags === 0 || flags === 1);
      const rows = gr.uint(1) + 1, columns = gr.uint(1) + 1;
      requireValue(
        rows * columns <= 256 && gr.uint(flags ? 4 : 2) === width &&
          gr.uint(flags ? 4 : 2) === height,
      );
      gr.done();
      grids.push({ id, rows, columns, width, height });
    } else {
      const config = one(imageProps, "hvcC");
      imageConfigs.set(id, config);
      requireValue(chosen.find((p) => p.box === config)?.essential === true);
      const cr = read(config);
      requireValue(cr.end - cr.at >= 23 && cr.uint(1) === 1);
      cr.uint(1);
      cr.uint(4);
      cr.uint(6);
      cr.uint(1);
      requireValue(
        (cr.uint(2) & 0xf000) === 0xf000 && (cr.uint(1) & 0xfc) === 0xfc,
      );
      const chroma = cr.uint(1);
      requireValue((chroma & 0xfc) === 0xfc);
      chromaFormats.set(id, chroma & 3);
      requireValue(
        (cr.uint(1) & 0xf8) === 0xf8 && (cr.uint(1) & 0xf8) === 0xf8,
      );
      cr.uint(2);
      const nalWidth = (cr.uint(1) & 3) + 1,
        arrays = cr.uint(1),
        parameterTypes = new Set<number>();
      requireValue(nalWidth !== 3 && arrays > 0 && arrays <= 64);
      let nals = 0;
      const nal = (r: Reader, length: number, expected?: number) => {
        requireValue(length >= 3 && length <= r.end - r.at && ++nals <= 4096);
        const first = r.uint(1),
          second = r.uint(1),
          actual = (first >>> 1) & 63;
        requireValue(
          !(first & 0x81) && (second & 0xf8) === 0 && (second & 7) > 0,
        );
        if (expected !== undefined) requireValue(actual === expected);
        r.at += length - 2;
        return actual;
      };
      for (let j = 0; j < arrays; j++) {
        checkpoint();
        const header = cr.uint(1), kind = header & 63, n = cr.uint(2);
        requireValue(
          !(header & 0x40) && [32, 33, 34, 39, 40].includes(kind) && n > 0 &&
            !parameterTypes.has(kind),
        );
        parameterTypes.add(kind);
        for (let k = 0; k < n; k++) nal(cr, cr.uint(2), kind);
      }
      cr.done();
      requireValue([32, 33, 34].every((t) => parameterTypes.has(t)));
      // This increment supports one extent per coded image. Do not concatenate
      // attacker-selected extents or claim split-item bitstream coverage yet.
      const spans = extents.get(id)!;
      requireValue(spans.length === 1);
      const image = new Reader(bytes, spans[0].end, spans[0].start);
      let vcl = false;
      while (image.at < image.end) {
        checkpoint();
        const kind = nal(image, image.uint(nalWidth));
        requireValue(kind <= 40);
        if (kind <= 31) vcl = true;
      }
      requireValue(vcl);
    }
    for (const p of imageProps) {
      const r = read(p);
      if (p.type === "irot" || p.type === "imir") {
        requireValue((r.uint(1) & (p.type === "irot" ? 0xfc : 0xfe)) === 0);
        r.done();
      } else if (p.type === "auxC") {
        requireValue(
          id === alphaItem &&
            chosen.find((a) => a.box === p)?.essential === true,
        );
        const ar = full(p, [0]).r;
        requireValue(
          ar.zeroString() === "urn:mpeg:hevc:2015:auxid:1" &&
            ar.end - ar.at <= 4096,
        );
        // Codec-specific auxiliary subtype bytes remain opaque, not alpha/pixel proof.
        alphaProperties.add(id);
      } else if (p.type === "clli") {
        r.uint(2);
        r.uint(2);
        r.done(); // Content-light declarations, not HDR proof.
      } else if (p.type === "pixi") {
        const pr = full(p, [0]).r, count = pr.uint(1);
        channels.set(id, count);
        requireValue(count === 1 || count === 3);
        for (let k = 0; k < count; k++) {
          requireValue([8, 10, 12].includes(pr.uint(1)));
        }
        pr.done();
      } else if (p.type === "colr") {
        const kind = r.tag();
        if (kind === "nclx") {
          r.uint(2);
          r.uint(2);
          r.uint(2);
          requireValue(!(r.uint(1) & 0x7f));
          r.done();
        } else requireValue(["rICC", "prof"].includes(kind) && r.at < r.end);
      }
    }
  }
  for (const grid of grids) {
    checkpoint();
    const targets = gridTargets.get(grid.id) ?? [];
    requireValue(targets.length === grid.rows * grid.columns);
    const tile = imageSizes.get(targets[0])!;
    // Observed native grid subset: a single shared configuration and untransformed
    // coded tiles. Broader per-tile configuration/transform semantics stay held.
    requireValue(
      targets.every((id) =>
        !transformed.has(id) &&
        imageConfigs.get(id) === imageConfigs.get(targets[0])
      ),
    );
    requireValue(
      targets.every((id) =>
        imageSizes.get(id)?.width === tile.width &&
        imageSizes.get(id)?.height === tile.height
      ),
    );
    requireValue(
      grid.width > tile.width * (grid.columns - 1) &&
        grid.width <= tile.width * grid.columns &&
        grid.height > tile.height * (grid.rows - 1) &&
        grid.height <= tile.height * grid.rows,
    );
  }
  if (alphaItem !== undefined) {
    const alphaSize = imageSizes.get(alphaItem)!;
    requireValue(
      alphaProperties.has(alphaItem) && channels.get(alphaItem) === 1 &&
        alphaSize.width === dimensions?.width &&
        alphaSize.height === dimensions?.height &&
        orientations.get(alphaItem) === orientations.get(primaryItem),
    );
    const alphaTiles = gridTargets.get(alphaItem) ?? [alphaItem];
    const primaryTiles = new Set(gridTargets.get(primaryItem) ?? [primaryItem]);
    requireValue(
      alphaTiles.every((id) =>
        !primaryTiles.has(id) && chromaFormats.get(id) === 0
      ),
    );
  }
  requireValue(dimensions !== undefined);
  checkpoint();
  return { ...dimensions!, primaryItem };
}
