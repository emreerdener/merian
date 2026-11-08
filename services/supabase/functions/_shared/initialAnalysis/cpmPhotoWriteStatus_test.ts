import { assertEquals, assertThrows } from "@std/assert";
import {
  type CpmPhotoStatusIdentity,
  decodeCpmPhotoWriteStatus,
} from "./cpmPhotoWriteStatus.ts";

// The same independent golden is consumed by InitialPhotoUploadStatusTests.
const golden =
  `{"version":1,"authority":"none","scan_id":"00000000-0000-4000-8000-000000000001","assignment_digest":"eb616665a5a98638d564ef78f6aa08899551c0f09b4284fe36bf4c1afa0f7886","object_id":"00000000-0000-4000-8000-000000000200","attempt":{"attempt_id":"00000000-0000-4000-8000-000000000300","state":"bound","created_at_ms":1793140001000,"capability_expires_at_ms":1793140601000,"write_closed":false}}`;
const fixture = () => JSON.parse(golden);
const identity = (): CpmPhotoStatusIdentity => ({
  owner: "00000000-0000-4000-8000-000000000999",
  scan: fixture().scan_id,
  assignment_digest: fixture().assignment_digest,
  object: fixture().object_id,
  allocation_created_at_ms: 1793140000000,
  allocation_expires_at_ms: 1793141800000,
});
Deno.test("CPM status golden preserves historical clocks and monotonic observations", () => {
  const i = identity(), row = fixture();
  const bound = decodeCpmPhotoWriteStatus(row, i);
  assertEquals(bound, row);
  row.attempt.state = "may_have_issued";
  const issued = decodeCpmPhotoWriteStatus(row, i, bound);
  row.attempt.write_closed = true;
  const closed = decodeCpmPhotoWriteStatus(row, i, issued);
  assertEquals(decodeCpmPhotoWriteStatus(row, i, closed), closed);
  row.attempt = null;
  const absent = decodeCpmPhotoWriteStatus(row, i);
  assertEquals(absent.attempt, null);
  assertEquals(decodeCpmPhotoWriteStatus(fixture(), i, absent), bound);
  assertThrows(() => decodeCpmPhotoWriteStatus(row, i, closed));
  assertThrows(() => decodeCpmPhotoWriteStatus(fixture(), i, issued));
  row.attempt = { ...closed.attempt, write_closed: false };
  assertThrows(() => decodeCpmPhotoWriteStatus(row, i, closed));
  assertEquals(Object.isFrozen(bound), true);
  assertEquals(Object.isFrozen(bound.attempt), true);
});
for (
  const fault of [
    "version",
    "authority",
    "scan",
    "digest",
    "object",
    "extra",
    "missing",
    "attemptExtra",
    "attemptMissing",
    "id",
    "uppercase",
    "state",
    "boolean",
    "numericBoolean",
    "fraction",
    "before",
    "expiry",
    "after",
    "boundClosed",
    "array",
  ]
) {
  Deno.test(`CPM status rejects ${fault}`, () => {
    const row = fixture();
    switch (fault) {
      case "version":
        row.version = 2;
        break;
      case "authority":
        row.authority = "upload";
        break;
      case "scan":
        row.scan_id = row.object_id;
        break;
      case "digest":
        row.assignment_digest = "a".repeat(64);
        break;
      case "object":
        row.object_id = row.scan_id;
        break;
      case "extra":
        row.url = "forbidden";
        break;
      case "missing":
        delete row.attempt;
        break;
      case "attemptExtra":
        row.attempt.url = "forbidden";
        break;
      case "attemptMissing":
        delete row.attempt.write_closed;
        break;
      case "id":
        row.attempt.attempt_id = "invalid";
        break;
      case "uppercase":
        row.attempt.attempt_id = "AAAAAAAA-0000-4000-8000-000000000001";
        break;
      case "state":
        row.attempt.state = "fresh";
        break;
      case "boolean":
        row.attempt.created_at_ms = true;
        break;
      case "numericBoolean":
        row.attempt.write_closed = 0;
        break;
      case "fraction":
        row.attempt.created_at_ms += 0.5;
        break;
      case "before":
        row.attempt.created_at_ms = identity().allocation_created_at_ms - 1;
        break;
      case "expiry":
        row.attempt.capability_expires_at_ms++;
        break;
      case "after":
        row.attempt.created_at_ms = identity().allocation_expires_at_ms;
        break;
      case "boundClosed":
        row.attempt.write_closed = true;
        break;
      case "array":
        row.attempt = [];
        break;
    }
    assertThrows(() => decodeCpmPhotoWriteStatus(row, identity()));
  });
}
Deno.test("CPM status cannot replace saved attempt, clocks or association", () => {
  const saved = decodeCpmPhotoWriteStatus(fixture(), identity());
  for (
    const field of ["attempt_id", "created_at_ms", "capability_expires_at_ms"]
  ) {
    const row = fixture();
    if (field === "attempt_id") row.attempt[field] = row.scan_id;
    else {
      row.attempt.created_at_ms++;
      row.attempt.capability_expires_at_ms++;
    }
    assertThrows(() => decodeCpmPhotoWriteStatus(row, identity(), saved));
  }
  const row = fixture();
  row.object_id = row.scan_id;
  assertThrows(() =>
    decodeCpmPhotoWriteStatus(
      row,
      { ...identity(), object: row.object_id },
      saved,
    )
  );
});
Deno.test("CPM status clips to admission and accepts maximum original clocks", () => {
  for (const created of [1793140000000, 8_639_999_998_200_000]) {
    const i = {
      ...identity(),
      allocation_created_at_ms: created,
      allocation_expires_at_ms: created + 1_800_000,
    };
    const row = fixture();
    row.attempt.created_at_ms = created + 1_799_999;
    row.attempt.capability_expires_at_ms = i.allocation_expires_at_ms;
    assertEquals(
      decodeCpmPhotoWriteStatus(row, i).attempt?.capability_expires_at_ms,
      i.allocation_expires_at_ms,
    );
  }
  for (
    const i of [{ ...identity(), allocation_expires_at_ms: 1 }, {
      ...identity(),
      allocation_created_at_ms: true,
    }, { ...identity(), owner: "invalid" }]
  ) {
    assertThrows(() =>
      decodeCpmPhotoWriteStatus(fixture(), i as CpmPhotoStatusIdentity)
    );
  }
});
