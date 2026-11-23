import { assertEquals } from "@std/assert";
import type { SupabaseClient, User } from "@supabase/supabase-js";
import { handleIdentifyMultimodalRequest } from "./index.ts";

Deno.test("inactive initial evidence cannot silently enter legacy Identify or replay", async () => {
  for (const replay of [undefined, 1]) {
    for (const key of ["initialEvidence", "initial_evidence"]) {
      for (const evidence of [null, {}, { schema_version: 1 }]) {
        const calls: string[] = [];
        const database = {
          rpc(name: string) {
            calls.push(name);
            assertEquals(name, "get_entitlement_rollout_service");
            return {
              abortSignal: () =>
                Promise.resolve({
                  data: {
                    entitlement_mode: "complimentary",
                    required_client_protocol: 3,
                    mode_version: 1,
                  },
                  error: null,
                }),
            };
          },
          from() {
            throw new Error("No persistence or storage lookup is permitted");
          },
        } as unknown as SupabaseClient;
        const response = await handleIdentifyMultimodalRequest(
          new Request("https://example.invalid/identify-multimodal", {
            method: "POST",
            headers: {
              "Content-Type": "application/json",
              "X-Merian-Entitlement-Protocol": "3",
            },
            body: JSON.stringify({
              user_id: "00000000-0000-4000-8000-000000000001",
              client_scan_id: "00000000-0000-4000-8000-000000000002",
              [key]: evidence,
              imageBase64s: ["synthetic-unread-media"],
            }),
          }),
          { id: "00000000-0000-4000-8000-000000000001" } as User,
          database,
          0,
          replay,
          () => {
            throw new Error("No provider preparation is permitted");
          },
        );
        assertEquals(response.status, 503);
        assertEquals(
          (await response.json()).code,
          "analysis_history_unavailable",
        );
        assertEquals(
          calls,
          replay === undefined ? ["get_entitlement_rollout_service"] : [],
        );
      }
    }
  }
});
