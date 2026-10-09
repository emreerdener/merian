import { invalidHistory } from "./contract.ts";
import {
  inspectRetainedVideoEnvelope,
  type RetainedVideoBox,
} from "./retainedVideoEnvelope.ts";

type Box = RetainedVideoBox;
const requireValue = (ok: boolean): void => {
  if (!ok) invalidHistory();
};
const one = (boxes: readonly Box[], type: string): Box => {
  const found = boxes.filter((box) => box.type === type);
  requireValue(found.length === 1);
  return found[0];
};

/** Closed structural profile, not a decoder, derivation proof or admission.
 * Byte/sample extents and declared configuration are checked. Compressed payloads
 * and SPS bit-level semantics are not decoded. No live caller installs this.
 */
export function inspectRetainedVideoStructure(bytes: Uint8Array) {
  try {
    return inspect(bytes);
  } catch (error) {
    if (error instanceof RangeError) return invalidHistory();
    throw error;
  }
}
function inspect(bytes: Uint8Array) {
  const envelope = inspectRetainedVideoEnvelope(bytes);
  let budget = 128;
  const data = (box: Box) =>
    new DataView(
      bytes.buffer,
      bytes.byteOffset + box.payloadStart,
      box.end - box.payloadStart,
    );
  const raw = (box: Box) => bytes.subarray(box.payloadStart, box.end);
  const exact = (box: Box, expected: readonly number[]) =>
    requireValue(
      raw(box).length === expected.length &&
        expected.every((v, i) => raw(box)[i] === v),
    );
  const hex = (value: string) =>
    Array.from(value.match(/../g) ?? [], (v) => parseInt(v, 16));
  const full = (box: Box, length: number, flags = 0) => {
    const view = data(box);
    requireValue(view.byteLength === length && view.getUint32(0) === flags);
    return view;
  };
  function children(box: Box, allowed: readonly string[], skip = 0): Box[] {
    let at = box.payloadStart + skip;
    requireValue(at <= box.end);
    const found: Box[] = [];
    while (at < box.end) {
      requireValue(--budget >= 0 && box.end - at >= 8);
      const view = new DataView(
        bytes.buffer,
        bytes.byteOffset + at,
        box.end - at,
      );
      const size = view.getUint32(0);
      // Nested extended/zero-size boxes are outside the observed closed profile.
      requireValue(size >= 8 && size <= box.end - at);
      const type = String.fromCharCode(...bytes.subarray(at + 4, at + 8));
      requireValue(allowed.includes(type));
      found.push({ type, start: at, payloadStart: at + 8, end: at + size });
      at += size;
    }
    for (const type of allowed) {
      if (type !== "trak") {
        requireValue(found.filter((v) => v.type === type).length <= 1);
      }
    }
    return found;
  }
  // The private profile is fixture-backed; no arbitrary brands/padding payloads.
  exact(one(envelope, "ftyp"), hex("6d7034320000000169736f6d6d7034316d703432"));
  for (const box of envelope.filter((v) => ["free", "wide"].includes(v.type))) {
    requireValue(raw(box).every((v) => v === 0));
  }
  const mdat = one(envelope, "mdat");
  const movie = children(one(envelope, "moov"), ["mvhd", "trak"]);
  const header = full(one(movie, "mvhd"), 100);
  const duration = header.getUint32(16);
  requireValue(
    header.getUint32(12) === 600 && duration >= 60 && duration <= 3000,
  );
  requireValue(header.getUint32(20) === 65536 && header.getUint16(24) === 256);
  const identity = [65536, 0, 0, 0, 65536, 0, 0, 0, 1073741824];
  for (let i = 0; i < 9; i++) {
    requireValue(header.getInt32(36 + i * 4) === identity[i]);
  }
  requireValue(
    new Uint8Array(header.buffer, header.byteOffset + 26, 10).every((v) =>
      v === 0
    ),
  );
  requireValue(
    new Uint8Array(header.buffer, header.byteOffset + 72, 24).every((v) =>
      v === 0
    ),
  );
  const tracks = movie.filter((v) => v.type === "trak");
  requireValue(tracks.length >= 1 && tracks.length <= 2);
  const ids = new Set<number>();
  const spans: { start: number; end: number }[] = [];
  let width = 0, height = 0, videoCount = 0, audioCount = 0;

  for (const track of tracks) {
    const nodes = children(track, ["tkhd", "edts", "mdia"]);
    const th = full(one(nodes, "tkhd"), 84, 1);
    const id = th.getUint32(12), trackDuration = th.getUint32(20);
    requireValue(id > 0 && !ids.has(id));
    ids.add(id);
    requireValue(
      th.getUint32(16) === 0 && th.getUint32(24) === 0 &&
        th.getUint32(28) === 0,
    );
    requireValue(
      th.getUint16(32) === 0 && th.getUint16(34) === 0 &&
        th.getUint16(38) === 0,
    );
    const matrix = Array.from({ length: 9 }, (_, i) => th.getInt32(40 + i * 4));
    const [a, b, u, c, d, v, x, y, w] = matrix;
    requireValue(
      [a, b, c, d].every((n) => [-65536, 0, 65536].includes(n)) && u === 0 &&
        v === 0 && w === 1073741824,
    );
    requireValue(
      a * a + b * b === 65536 ** 2 && c * c + d * d === 65536 ** 2 &&
        Math.abs(a * d - b * c) === 65536 ** 2,
    );
    requireValue(Math.abs(x) <= 2048 * 65536 && Math.abs(y) <= 2048 * 65536);
    const media = children(one(nodes, "mdia"), ["mdhd", "hdlr", "minf"]);
    const mh = full(one(media, "mdhd"), 24);
    const scale = mh.getUint32(12), mediaDuration = mh.getUint32(16);
    requireValue(
      scale > 0 && scale <= 1_000_000 && mediaDuration > 0 &&
        mediaDuration <= scale * 6,
    );
    requireValue(mh.getUint32(20) === 0x55c40000);
    const handler = one(media, "hdlr"), hv = data(handler);
    requireValue(
      hv.byteLength === 41 && hv.getUint32(0) === 0 && hv.getUint32(4) === 0,
    );
    const video = hv.getUint32(8) === 0x76696465;
    requireValue(video || hv.getUint32(8) === 0x736f756e);
    exact(handler, [
      ...new Uint8Array(8),
      ...new TextEncoder().encode(video ? "vide" : "soun"),
      ...new Uint8Array(12),
      ...new TextEncoder().encode(
        video ? "Core Media Video\0" : "Core Media Audio\0",
      ),
    ]);
    if (video) videoCount++;
    else audioCount++;
    requireValue(
      trackDuration > 0 && duration - trackDuration >= 0 &&
        duration - trackDuration <= (video ? 0 : 1),
    );
    const edit = full(one(children(one(nodes, "edts"), ["elst"]), "elst"), 20);
    const mediaTime = edit.getInt32(12);
    requireValue(
      edit.getUint32(4) === 1 && edit.getUint32(8) === trackDuration &&
        edit.getUint32(16) === 65536,
    );
    requireValue(mediaTime >= 0 && mediaTime <= (video ? 0 : 4096));
    requireValue(
      mediaTime + trackDuration * scale / 600 <= mediaDuration + scale / 600,
    );
    const minf = children(one(media, "minf"), [
      video ? "vmhd" : "smhd",
      "dinf",
      "stbl",
    ]);
    exact(
      one(minf, video ? "vmhd" : "smhd"),
      video ? hex("000000010000000000000000") : hex("0000000000000000"),
    );
    const dref = one(children(one(minf, "dinf"), ["dref"]), "dref");
    const dv = data(dref);
    requireValue(dv.getUint32(0) === 0 && dv.getUint32(4) === 1);
    const urls = children(dref, ["url "], 8);
    exact(one(urls, "url "), [0, 0, 0, 1]);
    const table = children(one(minf, "stbl"), [
      "stsd",
      "stts",
      "stsc",
      "stsz",
      "stco",
      ...(video ? ["stss", "sdtp"] : ["sgpd", "sbgp"]),
    ]);
    const stsd = one(table, "stsd"), sv = data(stsd);
    requireValue(sv.getUint32(0) === 0 && sv.getUint32(4) === 1);
    const entry = one(
      children(stsd, [video ? "avc1" : "mp4a"], 8),
      video ? "avc1" : "mp4a",
    );
    const ev = data(entry);
    requireValue(
      ev.getUint32(0) === 0 && ev.getUint16(4) === 0 && ev.getUint16(6) === 1,
    );
    if (video) {
      width = ev.getUint16(24);
      height = ev.getUint16(26);
      requireValue(
        [width, height].every((n) => n >= 2 && n <= 2048 && n % 2 === 0),
      );
      requireValue(
        th.getUint32(76) === width * 65536 &&
          th.getUint32(80) === height * 65536 && th.getUint16(36) === 0,
      );
      requireValue(raw(entry).subarray(8, 24).every((n) => n === 0));
      requireValue(
        ev.getUint32(28) === 0x480000 && ev.getUint32(32) === 0x480000 &&
          ev.getUint32(36) === 0 && ev.getUint16(40) === 1,
      );
      requireValue(
        raw(entry).subarray(42, 74).every((n) => n === 0) &&
          ev.getUint16(74) === 24 && ev.getUint16(76) === 65535,
      );
      const extensions = children(entry, ["avcC", "colr", "pasp"], 78);
      avc(raw(one(extensions, "avcC")));
      exact(one(extensions, "colr"), hex("6e636c7800060001000600"));
      exact(one(extensions, "pasp"), [0, 0, 0, 1, 0, 0, 0, 1]);
    } else {
      requireValue(
        scale === 44100 && th.getUint16(36) === 256 && th.getUint32(76) === 0 &&
          th.getUint32(80) === 0,
      );
      requireValue(matrix.every((n, i) => n === identity[i]));
      // AVFoundation's mp4a template declares 2 here; ASC is authoritative for mono.
      requireValue(
        ev.getUint32(8) === 0 && ev.getUint32(12) === 0 &&
          ev.getUint16(16) === 2 && ev.getUint16(18) === 16 &&
          ev.getUint32(20) === 0 && ev.getUint32(24) === 44100 * 65536,
      );
      const ext = children(entry, ["esds"], 28);
      esds(raw(one(ext, "esds")));
    }
    samples(table, video, mediaDuration, mdat, data, raw, spans);
  }
  requireValue(
    videoCount === 1 && audioCount <= 1 &&
      header.getUint32(96) > Math.max(...ids),
  );
  spans.sort((a, b) => a.start - b.start);
  let end = mdat.payloadStart;
  for (const span of spans) {
    requireValue(span.start === end);
    end = span.end;
  }
  requireValue(end === mdat.end);
  return Object.freeze({
    width,
    height,
    durationTicks: duration,
    hasAudio: audioCount === 1,
  });
}

function avc(bytes: Uint8Array) {
  requireValue(
    bytes.length >= 7 && bytes.length <= 4096 && bytes[0] === 1 &&
      bytes[1] === 77 && (bytes[2] & 3) === 0 && bytes[4] === 255 &&
      (bytes[5] & 224) === 224,
  );
  requireValue(
    [10, 11, 12, 13, 20, 21, 22, 30, 31, 32, 40, 41, 42, 50, 51, 52, 60, 61, 62]
      .includes(bytes[3]),
  );
  let at = 6;
  function units(count: number, type: number) {
    requireValue(count >= 1 && count <= 31);
    for (let i = 0; i < count; i++) {
      requireValue(at + 2 <= bytes.length);
      const size = bytes[at] * 256 + bytes[at + 1];
      at += 2;
      requireValue(
        size > 0 && size <= bytes.length - at && (bytes[at] & 31) === type &&
          (bytes[at] & 128) === 0,
      );
      if (type === 7) {
        requireValue(
          size >= 4 && bytes[at + 1] === bytes[1] &&
            bytes[at + 2] === bytes[2] && bytes[at + 3] === bytes[3],
        );
      }
      at += size;
    }
  }
  units(bytes[5] & 31, 7);
  requireValue(at < bytes.length);
  const count = bytes[at++];
  units(count, 8);
  requireValue(at === bytes.length);
}
function esds(bytes: Uint8Array) {
  // Closed AAC-LC/44.1kHz/mono descriptor shape emitted by this producer.
  const expected =
    "000000000380808022000000048080801440140018000000fa000000fa0005808080021208068080800102";
  requireValue(
    bytes.length * 2 === expected.length &&
      bytes.every((n, i) =>
        n === parseInt(expected.slice(i * 2, i * 2 + 2), 16)
      ),
  );
}

function samples(
  table: Box[],
  video: boolean,
  duration: number,
  mdat: Box,
  data: (b: Box) => DataView,
  raw: (b: Box) => Uint8Array,
  spans: { start: number; end: number }[],
) {
  const cap = video ? 600 : 1024;
  function rows(type: string, stride: number, offset = 8) {
    const view = data(one(table, type)), count = view.getUint32(4);
    requireValue(
      view.getUint32(0) === 0 && count > 0 && count <= cap &&
        view.byteLength === offset + count * stride,
    );
    return { view, count };
  }
  const sizes = data(one(table, "stsz")),
    fixed = sizes.getUint32(4),
    count = sizes.getUint32(8);
  requireValue(
    sizes.getUint32(0) === 0 && count > 0 && count <= cap &&
      sizes.byteLength === (fixed ? 12 : 12 + 4 * count),
  );
  const lengths = Array.from(
    { length: count },
    (_, i) => fixed || sizes.getUint32(12 + i * 4),
  );
  requireValue(
    lengths.every((n) => n > 0 && n <= mdat.end - mdat.payloadStart),
  );
  const timing = rows("stts", 8);
  let timed = 0, ticks = 0;
  for (let i = 0; i < timing.count; i++) {
    const n = timing.view.getUint32(8 + i * 8),
      delta = timing.view.getUint32(12 + i * 8);
    requireValue(n > 0 && delta > 0 && n <= count && delta <= duration);
    if (!video) requireValue(delta === 1024);
    timed += n;
    ticks += n * delta;
  }
  requireValue(timed === count && ticks === duration);
  const chunks = rows("stco", 4), mapping = rows("stsc", 12);
  let sample = 0, map = 0;
  requireValue(
    mapping.view.getUint32(8) === 1 && mapping.count <= chunks.count,
  );
  for (let i = 0; i < mapping.count; i++) {
    const first = mapping.view.getUint32(8 + i * 12),
      n = mapping.view.getUint32(12 + i * 12);
    requireValue(
      first >= 1 && first <= chunks.count && n > 0 && n <= count &&
        mapping.view.getUint32(16 + i * 12) === 1,
    );
    if (i) requireValue(first > mapping.view.getUint32(8 + (i - 1) * 12));
  }
  for (let chunk = 1; chunk <= chunks.count; chunk++) {
    if (
      map + 1 < mapping.count &&
      mapping.view.getUint32(8 + (map + 1) * 12) === chunk
    ) map++;
    let at = chunks.view.getUint32(8 + (chunk - 1) * 4);
    const n = mapping.view.getUint32(12 + map * 12);
    requireValue(sample + n <= count);
    for (let i = 0; i < n; i++) {
      const end = at + lengths[sample++];
      requireValue(at >= mdat.payloadStart && end <= mdat.end);
      spans.push({ start: at, end });
      at = end;
    }
  }
  requireValue(sample === count);
  if (video) {
    if (table.some((b) => b.type === "stss")) {
      const sync = rows("stss", 4);
      let last = 0;
      for (let i = 0; i < sync.count; i++) {
        const n = sync.view.getUint32(8 + i * 4);
        requireValue(n > last && n <= count);
        last = n;
      }
    }
    if (table.some((b) => b.type === "sdtp")) {
      const dep = raw(one(table, "sdtp"));
      requireValue(
        dep.length === 4 + count && dep.subarray(0, 4).every((n) => n === 0),
      );
      requireValue(
        dep.subarray(4).every((n) =>
          [0, 1, 2].includes(n >> 6) && [0, 1, 2].includes((n >> 4) & 3) &&
          [0, 1, 2].includes((n >> 2) & 3) && [0, 1, 2].includes(n & 3)
        ),
      );
    }
  } else {
    const group = data(one(table, "sgpd"));
    requireValue(
      group.byteLength === 18 && group.getUint32(0) === 0x01000000 &&
        group.getUint32(4) === 0x726f6c6c && group.getUint32(8) === 2 &&
        group.getUint32(12) === 1 && group.getInt16(16) === -1,
    );
    const map = data(one(table, "sbgp"));
    requireValue(
      map.byteLength === 20 && map.getUint32(0) === 0 &&
        map.getUint32(4) === 0x726f6c6c && map.getUint32(8) === 1 &&
        map.getUint32(12) === count && map.getUint32(16) === 1,
    );
  }
}
