import { assertEquals, assertRejects } from "@std/assert";
import { createPreparationExecutionTransport } from "./preparationExecutionTransport.ts";

Deno.test("preparation transport pins trusted origin and never accepts caller destinations", async () => {
  const names = ["SUPABASE_URL", "SUPABASE_SERVER_API_KEY"];
  const saved = names.map((name) => Deno.env.get(name));
  try {
    Deno.env.set("SUPABASE_URL", "https://trusted.invalid");
    Deno.env.set("SUPABASE_SERVER_API_KEY", "sb_secret_" + "x".repeat(40));
    const destinations: string[] = [];
    const transport = createPreparationExecutionTransport((_input, init) => {
      destinations.push(String(_input));
      assertEquals(init?.redirect, "error");
      return Promise.resolve(
        new Response(
          JSON.stringify({ version: 1, outcome: "held", reason: "missing" }),
        ),
      );
    });
    // A later config or caller change cannot rebind the captured destination.
    Deno.env.set("SUPABASE_URL", "https://hostile.invalid");
    const args = {
      p_owner: "synthetic-owner",
      p_scan: "synthetic-operation",
      p_assignment_digest: "a".repeat(64),
    };
    await assertRejects(() =>
      transport.call("get_initial_preparation_execution_status", {
        ...args,
        origin: "https://hostile.invalid",
      }, new AbortController().signal)
    );
    assertEquals(destinations.length, 0);
    await transport.call(
      "get_initial_preparation_execution_status",
      args,
      new AbortController().signal,
    );
    assertEquals(destinations, [
      "https://trusted.invalid/rest/v1/rpc/get_initial_preparation_execution_status",
    ]);
  } finally {
    names.forEach((name, i) =>
      saved[i] === undefined
        ? Deno.env.delete(name)
        : Deno.env.set(name, saved[i]!)
    );
  }
});
Deno.test("preparation streamed reply deadline survives timer starvation", async () => {
  const names = ["SUPABASE_URL", "SUPABASE_SERVER_API_KEY"];
  const saved = names.map((name) => Deno.env.get(name));
  const descriptor = Object.getOwnPropertyDescriptor(performance, "now");
  const now = performance.now.bind(performance);
  let elapsed = 0;
  Object.defineProperty(performance, "now", {
    configurable: true,
    value: () => now() + elapsed,
  });
  try {
    Deno.env.set("SUPABASE_URL", "https://trusted.invalid");
    Deno.env.set("SUPABASE_SERVER_API_KEY", "sb_secret_" + "x".repeat(40));
    let reads = 0;
    const transport = createPreparationExecutionTransport(() =>
      Promise.resolve(
        new Response(
          new ReadableStream({
            pull(controller) {
              ++reads;
              elapsed += 3000;
              controller.enqueue(new TextEncoder().encode(" "));
            },
          }, { highWaterMark: 0 }),
        ),
      )
    );
    await assertRejects(() =>
      transport.call("get_initial_preparation_execution_status", {
        p_owner: "synthetic-owner",
        p_scan: "synthetic-operation",
        p_assignment_digest: "a".repeat(64),
      }, new AbortController().signal)
    );
    assertEquals(reads, 2);
  } finally {
    if (descriptor) Object.defineProperty(performance, "now", descriptor);
    else Reflect.deleteProperty(performance, "now");
    names.forEach((name, i) =>
      saved[i] === undefined
        ? Deno.env.delete(name)
        : Deno.env.set(name, saved[i]!)
    );
  }
});
