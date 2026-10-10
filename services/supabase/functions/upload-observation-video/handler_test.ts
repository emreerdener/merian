import { frame } from "./testFixtures.ts";
import { assertEquals } from "@std/assert";
import { videoByteFixture } from "../_shared/analysisHistory/videoByteTestFixtures.ts";
import type { VideoUploadDependencies } from "../_shared/analysisHistory/videoUpload.ts";
import { HistoryError } from "../_shared/analysisHistory/contract.ts";
import {
  uploadObservationVideo,
  VIDEO_UPLOAD_METADATA_MAX_BYTES,
} from "./handler.ts";
const owner = "00000000-0000-4000-8000-000000000900";
const req = () => new Request("https://example.invalid", { method: "POST" });
Deno.test("video binary handler returns exact ready cohort for source frame and audio", async () => {
  for (const audio of [true, false]) {
    const f = await videoByteFixture(audio);
    for (const index of audio ? [0, 1, 6] : [0, 1]) {
      const deps: VideoUploadDependencies = {
        reserve: (id, candidate) => {
          assertEquals(id, owner);
          assertEquals(candidate, f.input);
          return Promise.resolve(f.receipt);
        },
        write: () => {
          throw new Error("unexpected");
        },
        complete: () => {
          throw new Error("unexpected");
        },
      };
      const body = frame({
        schema_version: 1,
        reader_version: 12,
        candidate: f.input,
        media_id: f.receipt.items[index].media_id,
      }, f.bytes[index]);
      const response = await uploadObservationVideo(
        req(),
        body,
        owner,
        deps,
        new AbortController().signal,
      );
      assertEquals(response.status, 200);
      assertEquals(await response.json(), f.receipt);
      assertEquals(response.headers.get("cache-control"), "private, no-store");
    }
  }
});
Deno.test("video binary handler rejects open fields versions framing UTF8 and foreign target before IO", async () => {
  const f = await videoByteFixture(true);
  let calls = 0;
  const deps: VideoUploadDependencies = {
    reserve: () => {
      calls++;
      throw new Error("unexpected");
    },
    write: () => {
      throw new Error("unexpected");
    },
    complete: () => {
      throw new Error("unexpected");
    },
  };
  const metadata = {
    schema_version: 1,
    reader_version: 12,
    candidate: f.input,
    media_id: f.receipt.items[0].media_id,
  };
  const cases = [
    new Uint8Array(),
    frame({ ...metadata, owner_id: owner }, f.bytes[0]),
    frame({ ...metadata, object_id: owner }, f.bytes[0]),
    frame({ ...metadata, reader_version: 11 }, f.bytes[0]),
    frame({ ...metadata, schema_version: 2 }, f.bytes[0]),
    frame({ ...metadata, media_id: owner }, f.bytes[0]),
    frame(metadata, f.bytes[0].slice(1)),
    new Uint8Array([0, 0, 0, 1, 255, 1]),
  ];
  const bad = frame(metadata, f.bytes[0]);
  new DataView(bad.buffer).setUint32(0, VIDEO_UPLOAD_METADATA_MAX_BYTES + 1);
  cases.push(bad);
  for (const body of cases) {
    const response = await uploadObservationVideo(
      req(),
      body,
      owner,
      deps,
      new AbortController().signal,
    );
    assertEquals(response.status, 400);
    await response.body?.cancel();
  }
  assertEquals(calls, 0);
});
Deno.test("video handler keeps conflict distinct and conceals unexpected diagnostics", async () => {
  const f = await videoByteFixture(false);
  const body = frame({
    schema_version: 1,
    reader_version: 12,
    candidate: f.input,
    media_id: f.receipt.items[0].media_id,
  }, f.bytes[0]);
  for (const conflict of [true, false]) {
    const deps: VideoUploadDependencies = {
      reserve: () =>
        Promise.reject(
          conflict
            ? new HistoryError("analysis_history_operation_conflict")
            : new Error("private diagnostic"),
        ),
      write: () => {
        throw new Error("unexpected");
      },
      complete: () => {
        throw new Error("unexpected");
      },
    };
    const response = await uploadObservationVideo(
      req(),
      body,
      owner,
      deps,
      new AbortController().signal,
    );
    assertEquals(response.status, conflict ? 409 : 503);
    assertEquals((await response.text()).includes("private diagnostic"), false);
  }
});
