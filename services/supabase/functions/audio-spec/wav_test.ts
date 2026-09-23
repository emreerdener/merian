import { assertEquals } from "@std/assert";
import { trimSilence } from "./wav.ts";

Deno.test("trimming retains an active partial final window", () => {
  const input = new Float32Array(44_100 + 137).fill(0.25);
  assertEquals(trimSilence(input, 44_100), input);
});

Deno.test("a partial tail can be the only active window", () => {
  const input = new Float32Array(44_100 + 137);
  input.fill(0.25, 44_100);
  const output = trimSilence(input, 44_100);
  assertEquals(output, input.slice(48 * 882));
  assertEquals(output.length, 2 * 882 + 137);
});

Deno.test("silence, empty and sub-window clips retain all source samples", () => {
  for (const length of [0, 1, 127, 44_237]) {
    const input = new Float32Array(length);
    assertEquals(trimSilence(input, 44_100), input);
  }
  const shortSound = new Float32Array(137).fill(0.25);
  assertEquals(trimSilence(shortSound, 44_100), shortSound);
});

Deno.test("whole quiet windows still trim with 40 ms of context on each side", () => {
  const input = new Float32Array(100 * 882 + 137);
  input.fill(0.25, 25 * 882, 75 * 882);
  assertEquals(trimSilence(input, 44_100), input.slice(23 * 882, 77 * 882));
});
