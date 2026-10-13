import { assert, assertEquals, assertRejects } from "@std/assert";
import {
  createDisposableHandoffBridge,
  localHandoffDiagnostic,
} from "./initial_media_handoff_bridge.ts";
const ACK = "merian_local_handoff_transaction_committed_v1";
const project = "merian-handoff-runtime-abcdefgh";
const id = {
  owner_id: "00000000-0000-4000-8000-000000000001",
  scan_id: "00000000-0000-4000-8000-000000000002",
  admission_receipt_digest: "a".repeat(64),
};
const token = "00000000-0000-4000-8000-000000000003";
type Result = { out: string; err?: string; code?: number };
function fixture() {
  const commands: { args: string[]; input: string }[] = [];
  let killed = 0;
  const config = {
    manifest: {
      state: "ready",
      start_exit: 0,
      project,
      container: "supabase_db_" + project,
      workdir: (Deno.build.os === "darwin" ? "/private/tmp/" : "/tmp/") +
        project,
      docker_host: "unix:///private/tmp/synthetic-docker.sock",
    },
    host: "unix:///private/tmp/synthetic-docker.sock",
    label: project,
    result: (_input: string): Promise<Result> =>
      Promise.resolve({ out: '{"synthetic":true}\n' + ACK + "\n" }),
  };
  const readFile = Deno.readFile, Command = Deno.Command;
  Object.defineProperty(Deno, "readFile", {
    configurable: true,
    value: (path: URL) => {
      assert(
        path.pathname.endsWith(
          "/.artifacts/initial-media-handoff-v2/runtime-implementation/committed-disposable-state.json",
        ),
      );
      return Promise.resolve(
        new TextEncoder().encode(JSON.stringify(config.manifest)),
      );
    },
  });
  class FakeCommand {
    constructor(public command: string, public options: Deno.CommandOptions) {
      assertEquals(command, "docker");
    }
    spawn() {
      let resolve!: (value: Result) => void;
      const result = new Promise<Result>((r) => resolve = r);
      const chunks: Uint8Array[] = [];
      const args = this.options.args!;
      const stdin = new WritableStream<Uint8Array>({
        write(chunk) {
          chunks.push(chunk.slice());
        },
        async close() {
          const input = chunks.map((c) => new TextDecoder().decode(c)).join("");
          commands.push({ args, input });
          if (args[0] === "context") {
            resolve({
              out: JSON.stringify([{
                Endpoints: { docker: { Host: config.host } },
              }]),
            });
          } else if (args.includes("inspect")) {
            resolve({
              out: JSON.stringify([{
                Name: "/supabase_db_" + project,
                State: { Running: true },
                Config: {
                  Labels: { "com.supabase.cli.project": config.label },
                },
              }]),
            });
          } else resolve(await config.result(input));
        },
      });
      const stream = (field: "out" | "err") =>
        new ReadableStream<Uint8Array>({
          async start(c) {
            const value = await result;
            try {
              c.enqueue(new TextEncoder().encode(value[field] ?? ""));
              c.close();
            } catch { /* cancelled */ }
          },
        });
      return {
        stdin,
        stdout: stream("out"),
        stderr: stream("err"),
        status: result.then((r) => ({
          success: !r.code,
          code: r.code ?? 0,
          signal: null,
        })),
        kill() {
          killed++;
          resolve({ out: "", code: 137 });
        },
      };
    }
  }
  Object.defineProperty(Deno, "Command", {
    configurable: true,
    value: FakeCommand,
  });
  return {
    config,
    commands,
    killed: () => killed,
    [Symbol.dispose]() {
      Object.defineProperty(Deno, "readFile", {
        configurable: true,
        value: readFile,
      });
      Object.defineProperty(Deno, "Command", {
        configurable: true,
        value: Command,
      });
    },
  };
}
Deno.test("local handoff bridge has nine fixed methods and independent bounded transactions", async () => {
  using f = fixture();
  const signal = new AbortController().signal;
  const bridge = await createDisposableHandoffBridge(signal);
  assert(Object.isFrozen(bridge));
  await bridge.readState(id, signal);
  await bridge.loadCopy(id, signal);
  await bridge.loadVerification(id, token, signal);
  await bridge.beginCopy(id, signal);
  await bridge.recordObject(id, token, signal);
  await bridge.completeCopy(id, signal);
  await bridge.claimVerification(id, signal);
  await bridge.settleVerification(id, token, signal);
  await bridge.transfer(id, "b".repeat(64), signal);
  const calls = f.commands.filter((c) => c.args.includes("exec"));
  assertEquals(calls.length, 9);
  const names = [
    "read_initial_media_handoff_state",
    "load_initial_media_copy_io",
    "load_initial_media_verification_io",
    "begin_initial_media_copy_v2",
    "record_initial_media_copy_object_v2",
    "complete_initial_media_copy_v2",
    "claim_initial_media_verification_v2",
    "settle_initial_media_verification_v2",
    "transfer_initial_preparation_v2",
  ];
  for (const [i, c] of calls.entries()) {
    assertEquals(c.args.slice(0, 5), [
      "--host",
      f.config.host,
      "exec",
      "-i",
      "supabase_db_" + project,
    ]);
    assert(
      c.input.startsWith(
        "BEGIN ISOLATION LEVEL READ COMMITTED;\nSET LOCAL statement_timeout='5s';\nSET LOCAL lock_timeout='1s';\n",
      ),
    );
    assert(c.input.includes("FROM internal." + names[i] + "("));
    assert(c.input.endsWith("\nCOMMIT;\nSELECT '" + ACK + "';\n"));
  }
});
for (
  const kind of ["manifest", "remote", "label", "endpoint_drift", "reserving"]
) {
  Deno.test(
    "local handoff bridge rejects unowned " + kind + " before SQL",
    async () => {
      using f = fixture();
      if (kind === "manifest") {
        f.config.manifest.container = "supabase_db_unrelated";
      }
      if (kind === "remote") f.config.host = "tcp://remote.invalid:2376";
      if (kind === "label") f.config.label = "unrelated";
      if (kind === "endpoint_drift") f.config.host = "unix:///tmp/other.sock";
      if (kind === "reserving") f.config.manifest.state = "reserving";
      await assertRejects(() =>
        createDisposableHandoffBridge(new AbortController().signal)
      );
      assertEquals(f.commands.filter((c) => c.args.includes("exec")).length, 0);
    },
  );
}
for (const os of ["darwin", "linux", "windows"] as const) {
  Deno.test(
    "local handoff bridge binds fixed platform root: " + os,
    async () => {
      const build = Deno.build;
      Object.defineProperty(Deno, "build", {
        configurable: true,
        value: { ...build, os },
      });
      try {
        using f = fixture();
        if (os === "windows") {
          await assertRejects(() =>
            createDisposableHandoffBridge(new AbortController().signal)
          );
          assertEquals(f.commands.length, 0);
        } else {
          await createDisposableHandoffBridge(new AbortController().signal);
          f.config.manifest.workdir =
            (os === "darwin" ? "/tmp/" : "/private/tmp/") + project;
          await assertRejects(() =>
            createDisposableHandoffBridge(new AbortController().signal)
          );
        }
      } finally {
        Object.defineProperty(Deno, "build", {
          configurable: true,
          value: build,
        });
      }
    },
  );
}
for (
  const kind of [
    "missing_commit",
    "exit_failure",
    "malformed",
    "extra_rows",
    "oversize",
    "stderr_oversize",
  ]
) {
  Deno.test(
    "local handoff bridge " + kind + " is unknown without private diagnostics",
    async () => {
      using f = fixture();
      const signal = new AbortController().signal;
      const bridge = await createDisposableHandoffBridge(signal);
      f.config.result = () =>
        Promise.resolve(
          kind === "missing_commit"
            ? { out: '{"private":"fixture"}\n' }
            : kind === "exit_failure"
            ? {
              out: '{"private":"fixture"}\n' + ACK + "\n",
              err: "sensitive diagnostic",
              code: 1,
            }
            : kind === "malformed"
            ? { out: "{not-json}\n" + ACK + "\n" }
            : kind === "extra_rows"
            ? { out: "{}\n{}\n" + ACK + "\n" }
            : kind === "oversize"
            ? { out: " ".repeat(6 * 1024 * 1024 + 1) }
            : { out: "{}\n" + ACK + "\n", err: " ".repeat(65537) },
        );
      const error = await assertRejects(() => bridge.beginCopy(id, signal));
      assertEquals(
        (error as Error).message,
        "initial_media_handoff_local_outcome_unknown",
      );
      assertEquals(f.commands.filter((c) => c.args.includes("exec")).length, 1);
    },
  );
}
for (
  const [code, category] of [["55000", "sql_55000"], ["XX001", "process_exit"]]
) {
  Deno.test(
    "local handoff bridge sanitizes verbose SQLSTATE " + code,
    async () => {
      using f = fixture();
      const signal = new AbortController().signal;
      const bridge = await createDisposableHandoffBridge(signal);
      f.config.result = () =>
        Promise.resolve({
          out: "",
          err: "ERROR:  " + code +
            ": private synthetic diagnostic\nCONTEXT: private synthetic SQL\n",
          code: 1,
        });
      const error = await assertRejects(() => bridge.beginCopy(id, signal));
      assertEquals(
        (error as Error).message,
        "initial_media_handoff_local_outcome_unknown",
      );
      assertEquals(localHandoffDiagnostic(error), category);
      assert(!JSON.stringify(error).includes("private"));
      assertEquals(f.commands.filter((c) => c.args.includes("exec")).length, 1);
    },
  );
}
Deno.test("local handoff bridge rejects SQL-like identity before subprocess", async () => {
  using f = fixture();
  const s = new AbortController().signal;
  const bridge = await createDisposableHandoffBridge(s);
  await assertRejects(async () => {
    await bridge.recordObject(id, "' ; SELECT 1; --", s);
  });
  await assertRejects(async () => {
    await bridge.beginCopy({ ...id, owner_id: "'bad" }, s);
  });
  assertEquals(f.commands.filter((c) => c.args.includes("exec")).length, 0);
});
Deno.test("local handoff bridge cancellation kills only its subprocess and remains unknown", async () => {
  using f = fixture();
  const controller = new AbortController();
  const bridge = await createDisposableHandoffBridge(controller.signal);
  f.config.result = () => {
    controller.abort();
    return new Promise(() => {});
  };
  await assertRejects(() => bridge.beginCopy(id, controller.signal));
  assert(f.killed() > 0);
  assertEquals(f.commands.filter((c) => c.args.includes("exec")).length, 1);
});
