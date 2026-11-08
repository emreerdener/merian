/** Qualification-only constants. No production profile or runtime registration. */
export const MiB = 1_048_576;
export const LIMITS = Object.freeze({
  proxyBytes: 96 * MiB,
  growthBytes: 8 * MiB,
  sampleMs: 100,
  requestMs: 30_000,
  runMs: 30 * 60_000,
  cleanupMs: 15 * 60_000,
  calls: 256,
  ordinaryCalls: 192,
  cleanupCalls: 64,
  transferBytes: 2 * 1024 * MiB,
  requestBytes: 4096,
  responseBytes: 8192,
  maxChunkBytes: MiB,
  maxChunks: 65_536,
  cohortSpanMs: 320_000,
});
export const FIXTURES = Object.freeze({
  a: Object.freeze({
    key: "a.bin",
    bytes: 32 * MiB,
    seed: 17,
    sha256: "3deaf993b517a82fc1cebc0b6e9862d52c3b26e68f5856bd16d462c5dc7f577c",
  }),
  b: Object.freeze({
    key: "b.bin",
    bytes: 32 * MiB,
    seed: 41,
    sha256: "6492ef4827bc7650753bc14ca9a8c8e4a8267a25f04915d33077adb26232a5c9",
  }),
  control: Object.freeze({
    key: "control.bin",
    bytes: 65_536,
    seed: 73,
    sha256: "9ce267663a0fed025ba2eb83802c945c939a7d30e2bac57437cee708196d0307",
  }),
});
export type FixtureID = keyof typeof FIXTURES;
export interface Case {
  id: number;
  fixture: FixtureID;
  mode: "read" | "deny";
  group: number;
  atMs: number;
}
export function schedule(): readonly Case[] {
  const cases: Case[] = [
    { id: 1, fixture: "control", mode: "read", group: 1, atMs: 0 },
    { id: 2, fixture: "control", mode: "read", group: 2, atMs: 1000 },
  ];
  for (let cohort = 0; cohort < 2; cohort++) {
    for (let i = 0; i < 9; i++) {
      const id = 3 + cohort * 9 + i;
      cases.push({
        id,
        fixture: cohort === 0 ? "a" : "b",
        mode: "read",
        group: id,
        atMs: 2000 + cohort * 360_000 + i * LIMITS.cohortSpanMs / 8,
      });
    }
  }
  for (let pair = 0; pair < 3; pair++) {
    for (let member = 0; member < 2; member++) {
      cases.push({
        id: 21 + pair * 2 + member,
        fixture: member ? "b" : "a",
        mode: pair === 2 && member === 1 ? "deny" : "read",
        group: 21 + pair,
        atMs: 722_000 + pair * 40_000,
      });
    }
  }
  return Object.freeze(cases.map((item) => Object.freeze(item)));
}
export const CASES = schedule();
export interface Clock {
  now(): number;
  wall(): number;
  timeout(callback: () => void, ms: number): () => void;
  interval(callback: () => void, ms: number): () => void;
  sleep(ms: number): Promise<void>;
}
export const systemClock: Clock = {
  now: () => performance.now(),
  wall: () => Date.now(),
  timeout(fn, ms) {
    const id = setTimeout(fn, ms);
    return () => clearTimeout(id);
  },
  interval(fn, ms) {
    const id = setInterval(fn, ms);
    return () => clearInterval(id);
  },
  sleep: (ms) => new Promise((resolve) => setTimeout(resolve, ms)),
};
export function validAlias(value: unknown): value is string {
  return typeof value === "string" && /^[a-z][a-z0-9-]{0,47}$/.test(value);
}
