import { type Clock, type FixtureID, FIXTURES, MiB } from "./policy.ts";
import type { DriverSnapshot, Journal } from "./driver.ts";

export class ManualClock implements Clock {
  time = 0;
  private next = 0;
  private tasks = new Map<
    number,
    { at: number; repeat: number; callback: () => void }
  >();
  now = () => this.time;
  wall = () => 2_000_000_000_000 + this.time;
  get active() {
    return this.tasks.size;
  }
  timeout(callback: () => void, ms: number) {
    return this.add(callback, ms, 0);
  }
  interval(callback: () => void, ms: number) {
    return this.add(callback, ms, ms);
  }
  private add(callback: () => void, ms: number, repeat: number) {
    const id = ++this.next;
    this.tasks.set(id, { at: this.time + ms, repeat, callback });
    return () => {
      this.tasks.delete(id);
    };
  }
  advance(ms: number) {
    const end = this.time + ms;
    for (;;) {
      const next = [...this.tasks].sort((a, b) => a[1].at - b[1].at)[0];
      if (!next || next[1].at > end) break;
      const [id, task] = next;
      this.time = task.at;
      if (task.repeat) task.at += task.repeat;
      else this.tasks.delete(id);
      task.callback();
    }
    this.time = end;
  }
  sleep(ms: number) {
    this.advance(ms);
    return Promise.resolve();
  }
}
export function deferred<T>() {
  let resolve!: (value: T) => void;
  let reject!: (reason: unknown) => void;
  const promise = new Promise<T>((a, b) => {
    resolve = a;
    reject = b;
  });
  return { promise, resolve, reject };
}
export const CAPABILITY = "synthetic_capability_not_a_secret_0001";
export const MEMORY = {
  heapUsed: MiB,
  heapTotal: 2 * MiB,
  external: MiB,
  rss: 0,
};
export const config = (clock: Clock, worker = "worker-a") => ({
  run: "local-check",
  worker,
  operator: "synthetic-operator",
  capability: CAPABILITY,
  expiresAt: clock.wall() + 1_800_000,
});
/** Generated on pull, never allocates or retains a whole fixture. */
export function fixtureResponse(
  id: FixtureID,
  fault?: "corrupt" | "truncated" | "overrun",
) {
  const fixture = FIXTURES[id];
  let offset = 0;
  const length = fixture.bytes +
    (fault === "truncated" ? -1 : fault === "overrun" ? 1 : 0);
  const stream = new ReadableStream<Uint8Array>({
    pull(controller) {
      if (offset === length) {
        controller.close();
        return;
      }
      const chunk = new Uint8Array(Math.min(65_536, length - offset));
      chunk.fill((fixture.seed + Math.floor(offset / 65_536)) % 251);
      if (fault === "corrupt" && offset === 0) chunk[0] ^= 1;
      offset += chunk.length;
      controller.enqueue(chunk);
    },
  }, { highWaterMark: 0 });
  return new Response(stream, {
    headers: { "content-length": String(fixture.bytes) },
  });
}
export class MemoryJournal implements Journal {
  started = false;
  records: DriverSnapshot[] = [];
  begin() {
    if (this.started) return Promise.reject(Error("exists"));
    this.started = true;
    return Promise.resolve();
  }
  save(value: DriverSnapshot) {
    this.records.push(structuredClone(value));
    return Promise.resolve();
  }
}
export async function until(check: () => boolean) {
  for (let i = 0; i < 1000; i++) {
    if (check()) return;
    await Promise.resolve();
  }
  throw Error("local condition did not settle");
}
