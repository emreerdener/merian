import {
  projectedMeasurementCost,
} from "./identification_evaluation/appObservation.ts";
import {
  collectAppLogs,
  OBSERVER_MAX_EVENTS,
  OBSERVER_SHUTDOWN_GRACE_SECONDS,
} from "./identification_evaluation/appObserver.ts";
import {
  parsePricing,
  type Pricing,
} from "./identification_evaluation/runContracts.ts";

/** Passive simulator log observer. Never sends an identification or uses a key. */
export async function observeIdentificationApp(args: string[]): Promise<void> {
  const options = new Map<string, string>();
  for (let i = 0; i < args.length; i += 2) {
    if (
      !["--device", "--seconds", "--output", "--pricing"].includes(args[i]) ||
      !args[i + 1] || options.has(args[i])
    ) throw new Error("invalid_observer_options");
    options.set(args[i], args[i + 1]);
  }
  const device = options.get("--device") ?? "";
  const secondsText = options.get("--seconds") ?? "120";
  const seconds = Number(secondsText);
  const output = options.get("--output");
  if (
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(
      device,
    ) || device.trim() !== device || !/^[0-9]{1,3}$/.test(secondsText) ||
    !Number.isInteger(seconds) || seconds < 1 || seconds > 300 || !output
  ) throw new Error("bounded_device_duration_output_required");
  let pricing: Pricing | null = null;
  const pricePath = options.get("--pricing");
  if (pricePath) {
    const info = await Deno.stat(pricePath);
    if (!info.isFile || info.size > 16384) {
      throw new Error("invalid_pricing_file");
    }
    pricing = parsePricing(JSON.parse(await Deno.readTextFile(pricePath)));
  }
  // Exclusive creation refuses existing files and symlinks. Caller chooses a
  // private evidence directory outside source; no raw logs ever reach this file.
  const file = await Deno.open(output, {
    createNew: true,
    write: true,
    mode: 0o600,
  });
  const write = async (value: unknown) => {
    const bytes = new TextEncoder().encode(JSON.stringify(value) + "\n");
    let offset = 0;
    while (offset < bytes.length) {
      offset += await file.write(bytes.subarray(offset));
    }
    await file.sync();
  };
  const started = performance.now();
  let events = 0;
  let child: Deno.ChildProcess | undefined;
  let timer: ReturnType<typeof setTimeout> | undefined;
  let status = "observer_unavailable";
  let completion: Awaited<ReturnType<typeof collectAppLogs>> | undefined;
  try {
    await write({
      version: "identification_app_observation_v1",
      startedAt: new Date().toISOString(),
      maxSeconds: seconds,
      shutdownGraceSeconds: OBSERVER_SHUTDOWN_GRACE_SECONDS,
      maxEvents: OBSERVER_MAX_EVENTS,
      automaticSubmissions: 0,
      pricing,
      caseAssociation: "requires_observed_sequential_ui_actions",
      costScope: "observed_primary_attempts_only",
    });
    child = new Deno.Command("xcrun", {
      args: [
        "simctl",
        "spawn",
        device,
        "log",
        "stream",
        "--style",
        "ndjson",
        "--level",
        "debug",
        "--timeout",
        String(seconds),
        "--predicate",
        'subsystem == "com.merian.app" AND eventMessage BEGINSWITH "[⏱ BENCH]"',
      ],
      stdout: "piped",
      stderr: "null",
    }).spawn();
    const deadline = new AbortController();
    timer = setTimeout(
      () => deadline.abort(),
      (seconds + OBSERVER_SHUTDOWN_GRACE_SECONDS) * 1000,
    );
    completion = await collectAppLogs(child, deadline.signal, async () => {
      await write({
        readyAt: new Date().toISOString(),
        status: "observer_ready",
      });
      console.log(
        JSON.stringify({ status: "observer_ready", automaticSubmissions: 0 }),
      );
    }, async (projected) => {
      const now = Date.now();
      const cost = projectedMeasurementCost(projected, pricing, now);
      await write({
        observedAt: new Date(now).toISOString(),
        observedAfterSeconds: Math.round(performance.now() - started) / 1000,
        measurement: projected,
        cost,
      });
      events++;
    });
    status = completion.status;
  } finally {
    if (timer !== undefined) clearTimeout(timer);
    try {
      child?.kill("SIGKILL");
    } catch { /* Already stopped. */ }
    if (child) await child.status;
    try {
      await write({
        finishedAt: new Date().toISOString(),
        ...completion,
        status,
        events,
      });
    } finally {
      file.close();
    }
  }
  console.log(JSON.stringify({ status, events, automaticSubmissions: 0 }));
  if (status === "observer_stopped_or_unavailable") {
    throw new Error("identification_app_observer_unavailable");
  }
}

if (import.meta.main) {
  try {
    await observeIdentificationApp(Deno.args);
  } catch {
    console.error("identification_app_observer_failed");
    Deno.exitCode = 1;
  }
}
