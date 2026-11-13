import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import {
  HERO_IMAGE_GRACE_MS,
  heroFallbackImages,
  watchHeroImages,
} from "./heroImages.ts";

test("a stalled feed gets fallback without discarding late Explore results", async (t) => {
  t.mock.timers.enable({ apis: ["setTimeout"] });
  let resolve!: (images: string[]) => void;
  const pending = new Promise<string[]>((done) => {
    resolve = done;
  });
  let fallback = false;
  let received: string[] = [];
  const stop = watchHeroImages(pending, (images) => {
    received = images;
  }, () => {
    fallback = true;
  });
  t.mock.timers.tick(HERO_IMAGE_GRACE_MS - 1);
  assert.equal(fallback, false);
  t.mock.timers.tick(1);
  assert.equal(fallback, true);
  resolve(["/live.webp"]);
  await pending;
  assert.deepEqual(received, ["/live.webp"]);
  stop();
});

test("a fast feed gets the head start but slow image downloads still get fallback", async (t) => {
  t.mock.timers.enable({ apis: ["setTimeout"] });
  let fallback = false;
  let received: string[] = [];
  const stop = watchHeroImages(["/live.webp"], (images) => {
    received = images;
  }, () => {
    fallback = true;
  });
  await Promise.resolve();
  assert.deepEqual(received, ["/live.webp"]);
  assert.equal(fallback, false);
  t.mock.timers.tick(HERO_IMAGE_GRACE_MS);
  assert.equal(fallback, true);
  stop();
});

test("empty and rejected feeds select fallback immediately", async () => {
  for (const source of [[], Promise.reject(new Error("feed unavailable"))]) {
    let fallback = false;
    const stop = watchHeroImages(source, () => {}, () => {
      fallback = true;
    });
    await Promise.resolve();
    assert.equal(fallback, true);
    stop();
  }
});

test("teardown ignores late feeds and cancels the fallback timer", async (t) => {
  t.mock.timers.enable({ apis: ["setTimeout"] });
  let resolve!: (images: string[]) => void;
  const pending = new Promise<string[]>((done) => {
    resolve = done;
  });
  let calls = 0;
  const stop = watchHeroImages(pending, () => calls++, () => calls++);
  stop();
  resolve(["/live.webp"]);
  await pending;
  t.mock.timers.tick(HERO_IMAGE_GRACE_MS);
  assert.equal(calls, 0);
});

test("hero image inputs exclude blanks and duplicates and stay bounded", async () => {
  let received: string[] = [];
  const stop = watchHeroImages([
    "",
    " ",
    "/first.webp",
    "/first.webp",
    ...Array.from({ length: 30 }, (_, i) => `/${i}.webp`),
  ], (images) => {
    received = images;
  }, () => {});
  await Promise.resolve();
  assert.equal(received.length, 24);
  assert.equal(received[0], "/first.webp");
  stop();
});

test("every fallback is a bundled WebP and the set stays under 600 KiB", async () => {
  let total = 0;
  for (const path of heroFallbackImages) {
    assert.ok(path.startsWith("/assets/hero-nature/"));
    const bytes = await readFile(new URL(`../public${path}`, import.meta.url));
    assert.equal(bytes.toString("ascii", 0, 4), "RIFF");
    assert.equal(bytes.toString("ascii", 8, 12), "WEBP");
    total += bytes.length;
  }
  assert.ok(total < 600 * 1024);
});
