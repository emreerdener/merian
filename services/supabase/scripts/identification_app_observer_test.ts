import { assertEquals, assertRejects } from "@std/assert";
import {
  collectAppLogs,
  type LogProcess,
} from "./identification_evaluation/appObserver.ts";

function processFixture() {
  let controller: ReadableStreamDefaultController<Uint8Array>;
  let ended = false;
  const status = Promise.withResolvers<Awaited<LogProcess["status"]>>();
  const stdout = new ReadableStream<Uint8Array>({
    start(value) {
      controller = value;
    },
    cancel() {
      ended = true;
    },
  });
  const finish = (code = 0, signal: string | null = null) => {
    if (!ended) controller.close();
    ended = true;
    status.resolve({ code, signal, success: code === 0 });
  };
  return {
    child: {
      stdout,
      status: status.promise,
      kill: () => finish(137, "SIGKILL"),
    },
    finish,
    send: (line: string) =>
      controller.enqueue(new TextEncoder().encode(line + "\n")),
  };
}

const banner = 'Filtering the log data using "synthetic predicate"';
const event = JSON.stringify({
  subsystem: "com.merian.app",
  eventMessage: "[⏱ BENCH] Total pipeline: 2.123s",
  unused: "synthetic-private",
});

Deno.test("observer waits for native closure and flushes late records before successful completion", async () => {
  const process = processFixture();
  const ready = Promise.withResolvers<void>();
  const first = Promise.withResolvers<void>();
  const records: unknown[] = [];
  const result = collectAppLogs(
    process.child,
    new AbortController().signal,
    () => {
      ready.resolve();
      return Promise.resolve();
    },
    (value) => {
      records.push(value);
      first.resolve();
      return Promise.resolve();
    },
  );
  process.send(banner);
  await ready.promise;
  process.send(event);
  await first.promise;
  // The subprocess is still alive after earlier events were safely delivered.
  process.send(event);
  process.finish();
  const completed = await result;
  assertEquals(completed.status, "window_completed");
  assertEquals(completed.stopReason, "collector_exit");
  assertEquals(completed.collectorExitCode, 0);
  assertEquals(completed.events, 2);
  assertEquals(JSON.stringify(records).includes("synthetic-private"), false);
});

Deno.test("observer watchdog preserves delivered events and cannot become success", async () => {
  const process = processFixture();
  const deadline = new AbortController();
  const first = Promise.withResolvers<void>();
  const result = collectAppLogs(
    process.child,
    deadline.signal,
    async () => {},
    () => {
      first.resolve();
      return Promise.resolve();
    },
  );
  process.send(event);
  await first.promise;
  deadline.abort();
  const completed = await result;
  assertEquals(completed.status, "observer_stopped_or_unavailable");
  assertEquals(completed.events, 1);
  assertEquals(completed.stopReason, "watchdog");
  assertEquals(completed.collectorSignal, "SIGKILL");
});

Deno.test("observer fails unavailable collectors and an exit without readiness", async () => {
  for (const code of [0, 1]) {
    const process = processFixture();
    process.finish(code);
    const result = await collectAppLogs(
      process.child,
      new AbortController().signal,
      async () => {},
      async () => {},
    );
    assertEquals(result.status, "observer_stopped_or_unavailable");
    assertEquals(result.ready, false);
    assertEquals(result.collectorExitCode, code);
  }
});

Deno.test("observer event cap stops exactly at 100 despite buffered extra rows", async () => {
  const process = processFixture();
  for (let index = 0; index < 101; index++) process.send(event);
  let retained = 0;
  const result = await collectAppLogs(
    process.child,
    new AbortController().signal,
    async () => {},
    () => {
      retained++;
      return Promise.resolve();
    },
  );
  assertEquals(retained, 100);
  assertEquals(result.events, 100);
  assertEquals(result.status, "event_limit");
  assertEquals(result.stopReason, "event_limit");
});

Deno.test("observer reports discarded rows without retaining their contents", async () => {
  const process = processFixture();
  process.send(banner);
  process.send("x".repeat(65537));
  process.send("synthetic-private-unrecognized-line");
  process.finish();
  const result = await collectAppLogs(
    process.child,
    new AbortController().signal,
    async () => {},
    async () => {},
  );
  assertEquals(result.status, "window_completed");
  assertEquals(result.oversizedRows, 1);
  assertEquals(result.unprojectedRows, 1);
  assertEquals(JSON.stringify(result).includes("synthetic-private"), false);
});

Deno.test("observer stops its child when retaining an event fails", async () => {
  const process = processFixture();
  process.send(event);
  await assertRejects(
    () =>
      collectAppLogs(
        process.child,
        new AbortController().signal,
        async () => {},
        () => Promise.reject(new Error("synthetic_write_failure")),
      ),
    Error,
    "synthetic_write_failure",
  );
  assertEquals((await process.child.status).signal, "SIGKILL");
});
