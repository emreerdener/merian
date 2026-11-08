import { LIMITS } from "./policy.ts";
export interface Memory {
  heapUsed: number;
  heapTotal: number;
  external: number;
  rss?: number;
}
export interface MemorySummary {
  domain: "partial_v8";
  samples: number;
  heapUsed: number;
  heapTotal: number;
  external: number;
  proxy: number;
  rss: "unavailable";
}
export function memory(value: unknown): Memory {
  if (!value || typeof value !== "object") throw Error("telemetry");
  const m = value as Memory;
  for (const key of ["heapUsed", "heapTotal", "external"] as const) {
    if (!Number.isSafeInteger(m[key]) || m[key] < 0) throw Error("telemetry");
  }
  if (
    m.heapUsed > m.heapTotal || !Number.isSafeInteger(m.heapTotal + m.external)
  ) throw Error("telemetry");
  return { heapUsed: m.heapUsed, heapTotal: m.heapTotal, external: m.external };
}
export class Samples {
  readonly summary: MemorySummary = {
    domain: "partial_v8",
    samples: 0,
    heapUsed: 0,
    heapTotal: 0,
    external: 0,
    proxy: 0,
    rss: "unavailable",
  };
  take(input: unknown): number {
    const m = memory(input), p = m.heapTotal + m.external;
    this.summary.samples++;
    if (this.summary.samples > 70_000) throw Error("sample_bound");
    for (const key of ["heapUsed", "heapTotal", "external"] as const) {
      this.summary[key] = Math.max(this.summary[key], m[key]);
    }
    this.summary.proxy = Math.max(this.summary.proxy, p);
    if (p >= LIMITS.proxyBytes) throw Error("proxy_stop");
    return p;
  }
}
/** Four ordered quiescent points make three increments. No cross-worker mixing. */
export class Growth {
  private points: number[] = [];
  add(proxy: number): boolean {
    this.points.push(proxy);
    if (this.points.length > 4) this.points.shift();
    return this.points.length === 4 &&
      this.points.slice(1).every((p, i) => p > this.points[i]) &&
      this.points[3] - this.points[0] >= LIMITS.growthBytes;
  }
}
