import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { fetchEligiblePushDevices } from "./db.ts";

class FakePushDeviceQuery {
  filters: Array<[string, unknown]> = [];

  select(_columns: string): FakePushDeviceQuery {
    return this;
  }

  eq(column: string, value: unknown): FakePushDeviceQuery {
    this.filters.push([column, value]);
    return this;
  }

  then(
    resolve: (
      value: { data: unknown[]; error: null },
    ) => void,
  ): void {
    resolve({ data: [], error: null });
  }
}

class FakeSupabaseClient {
  query = new FakePushDeviceQuery();

  from(table: string): FakePushDeviceQuery {
    assertEquals(table, "user_push_devices");
    return this.query;
  }
}

Deno.test("fetchEligiblePushDevices gates regular Explore pushes by Explore activity", async () => {
  const client = new FakeSupabaseClient();

  await fetchEligiblePushDevices("user-1", "comment", client as never);

  assertEquals(client.query.filters, [
    ["user_id", "user-1"],
    ["platform", "ios"],
    ["is_active", true],
    ["explore_enabled", true],
  ]);
});

Deno.test("fetchEligiblePushDevices gates comment mentions by mention preference", async () => {
  const client = new FakeSupabaseClient();

  await fetchEligiblePushDevices("user-1", "comment_mention", client as never);

  assertEquals(client.query.filters, [
    ["user_id", "user-1"],
    ["platform", "ios"],
    ["is_active", true],
    ["comment_mentions_enabled", true],
  ]);
});
