import type { SupabaseClient } from "@supabase/supabase-js";
import { assertEquals, assertRejects } from "@std/assert";
import { countAllFieldChatSendsToday } from "./fieldChatDailyUsage.ts";
import { PublicHttpError } from "./http.ts";

const USER_ID = "019fb780-46ec-77f8-aede-a0ca604072b6";

function mockRpcClient(
  response: { data: unknown; error: { message: string } | null },
  observed: { name?: string; arguments?: Record<string, unknown> } = {},
): SupabaseClient {
  return {
    rpc(name: string, arguments_: Record<string, unknown>) {
      observed.name = name;
      observed.arguments = arguments_;
      return {
        abortSignal() {
          return Promise.resolve(response);
        },
      };
    },
  } as unknown as SupabaseClient;
}

Deno.test("Field Chat usage reads the durable service-only aggregate", async () => {
  const observed: { name?: string; arguments?: Record<string, unknown> } = {};
  const count = await countAllFieldChatSendsToday(
    USER_ID,
    mockRpcClient({ data: 7, error: null }, observed),
  );

  assertEquals(count, 7);
  assertEquals(observed, {
    name: "get_field_chat_daily_usage",
    arguments: { p_user_id: USER_ID },
  });
});

Deno.test("Field Chat usage fails closed without durable accounting", async () => {
  for (
    const response of [
      { data: null, error: null },
      { data: "7", error: null },
      { data: -1, error: null },
      { data: 1.5, error: null },
      { data: null, error: { message: "database unavailable" } },
    ]
  ) {
    const error = await assertRejects(
      () => countAllFieldChatSendsToday(USER_ID, mockRpcClient(response)),
      PublicHttpError,
    );
    assertEquals(error.status, 503);
    assertEquals(error.code, "field_chat_admission_unavailable");
    assertEquals(error.retryAfterSeconds, 2);
  }
});
