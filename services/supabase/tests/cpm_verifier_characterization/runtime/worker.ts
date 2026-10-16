import { createHandler } from "../handler.ts";
import { type Clock, systemClock } from "../policy.ts";
import { privateGetAdapter } from "../private_get.ts";
import { memory } from "../telemetry.ts";
import { authAdapter } from "./auth.ts";
import {
  AUTH_MODE,
  BUCKET,
  OPERATOR_ALIAS,
  readConfig,
  validRuntimeVersion,
} from "./config.ts";

export interface RuntimePorts {
  env(name: string): string | undefined;
  fetchOnce(request: Request): Promise<Response>;
  memoryUsage(): unknown;
  uuid(): string;
  versions: { deno: string; v8: string };
  clock?: Clock;
}
/** Called exactly once by entrypoint.ts; ports permit network-denied tests. */
export function createWorker(ports: RuntimePorts, growthContract?: "GAC-1") {
  const clock = ports.clock ?? systemClock;
  const config = readConfig(ports.env, clock.wall());
  const worker = `w-${ports.uuid()}`;
  if (
    ![ports.versions.deno, ports.versions.v8].every(validRuntimeVersion)
  ) throw Error("runtime_version");
  const measure = () => {
    const sample = memory(ports.memoryUsage());
    if (sample.heapTotal === 0 || sample.heapUsed === 0) {
      throw Error("telemetry_unavailable");
    }
    return sample;
  };
  const handler = createHandler({
    run: config.run,
    worker,
    operator: OPERATOR_ALIAS,
    capability: config.capability,
    expiresAt: config.expiresAt,
    growthContract,
  }, {
    clock,
    memory: measure,
    authenticate: authAdapter(config.operatorKey),
    get: privateGetAdapter({
      endpoint: config.endpoint,
      bucket: BUCKET,
      run: config.run,
      accessKeyId: config.accessKeyId,
      secretAccessKey: config.secretAccessKey,
      fetchOnce: ports.fetchOnce,
    }),
  });
  return {
    state: handler.state,
    async handle(request: Request) {
      const response = await handler.handle(request);
      response.headers.set("x-cpm-auth-mode", AUTH_MODE);
      response.headers.set("x-cpm-runtime-deno", ports.versions.deno);
      response.headers.set("x-cpm-runtime-v8", ports.versions.v8);
      return response;
    },
  };
}
