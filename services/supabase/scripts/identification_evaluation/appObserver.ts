import {
  boundedLogLines,
  isProofLogRow,
  measurementLogSha256,
  projectAppLog,
} from "./appObservation.ts";

// Simulator `log stream --timeout` can close on a later polling interval. A
// two-minute synthetic run closed successfully at 128 seconds; five seconds of
// grace killed a healthy collector. A forced stop still fails the observation.
export const OBSERVER_SHUTDOWN_GRACE_SECONDS = 30;
export const OBSERVER_MAX_EVENTS = 100;

export interface LogProcess {
  stdout: ReadableStream<Uint8Array>;
  status: Promise<{ success: boolean; code: number; signal: string | null }>;
  kill(signal: "SIGKILL"): void;
}

export type ProjectedAppLog = NonNullable<ReturnType<typeof projectAppLog>>;

/** Own only the spawned reader. No raw log, subprocess stderr, or PID is
 * retained. Injectable streams/deadlines allow lifecycle tests without simctl. */
export async function collectAppLogs(
  child: LogProcess,
  deadline: AbortSignal,
  onReady: () => Promise<void>,
  onMeasurement: (
    value: ProjectedAppLog,
    measurementSha256: string | null,
  ) => Promise<void>,
) {
  let ready = false, events = 0, unprojectedRows = 0, oversizedRows = 0;
  let rejectedProofRows = 0;
  let stoppedBy: "watchdog" | "event_limit" | null = null;
  const kill = () => {
    try {
      child.kill("SIGKILL");
    } catch { /* Already stopped. */ }
  };
  const abort = () => {
    stoppedBy ??= "watchdog";
    kill();
  };
  const markReady = async () => {
    if (ready) return;
    ready = true;
    await onReady();
  };
  deadline.addEventListener("abort", abort, { once: true });
  if (deadline.aborted) abort();
  try {
    for await (
      const line of boundedLogLines(child.stdout, {
        signal: deadline,
        onOversize: () => oversizedRows++,
      })
    ) {
      if (line.startsWith("Filtering the log data using ")) {
        await markReady();
        continue;
      }
      const projected = projectAppLog(line);
      if (!projected) {
        unprojectedRows++;
        if (isProofLogRow(line)) rejectedProofRows++;
        continue;
      }
      await markReady();
      await onMeasurement(projected, await measurementLogSha256(line));
      events++;
      if (events === OBSERVER_MAX_EVENTS) {
        stoppedBy = "event_limit";
        kill();
        break;
      }
    }
    const result = await child.status;
    return {
      status: stoppedBy === "event_limit"
        ? "event_limit"
        : stoppedBy === null && ready && result.success
        ? "window_completed"
        : "observer_stopped_or_unavailable",
      events,
      ready,
      stopReason: stoppedBy ?? "collector_exit",
      collectorExitCode: result.code,
      collectorSignal: result.signal,
      unprojectedRows,
      oversizedRows,
      rejectedProofRows,
    };
  } finally {
    deadline.removeEventListener("abort", abort);
    kill();
    await child.status;
  }
}
