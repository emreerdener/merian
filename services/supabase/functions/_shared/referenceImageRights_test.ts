import { assertEquals } from "@std/assert";
import {
  commonsImageIdentity,
  imageCreditText,
  reusableImageLicense,
} from "./referenceImageRights.ts";

Deno.test("reference rights accepts explicit reusable licenses, never restricted or unknown terms", () => {
  for (
    const license of [
      "CC BY-SA 4.0",
      "http://creativecommons.org/licenses/by-sa/4.0/legalcode",
      "https://creativecommons.org/licenses/by-sa/4.0/deed.en",
    ]
  ) {
    assertEquals(
      reusableImageLicense(license),
      "https://creativecommons.org/licenses/by-sa/4.0/",
    );
  }
  assertEquals(
    reusableImageLicense("CC0 1.0"),
    "https://creativecommons.org/publicdomain/zero/1.0/",
  );
  for (
    const license of [
      "CC BY-NC 4.0",
      "CC BY-ND 4.0",
      "All rights reserved",
      "fair use",
      "GFDL",
      "https://creativecommons.org.evil.test/licenses/by/4.0/",
      "https://user@creativecommons.org/licenses/by/4.0/",
      "https://creativecommons.org/licenses/by/4.0/?other=terms",
      "https://creativecommons.org/licenses/by/99.0/",
      null,
    ]
  ) {
    assertEquals(reusableImageLicense(license), null);
  }
});

Deno.test("reference rights preserves the Australia jurisdiction instead of relabeling it unported", () => {
  for (
    const value of [
      "CC BY 3.0 au",
      "https://creativecommons.org/licenses/by/3.0/au/deed.en",
    ]
  ) {
    assertEquals(
      reusableImageLicense(value),
      "https://creativecommons.org/licenses/by/3.0/au/",
    );
  }
  assertEquals(reusableImageLicense("CC BY 4.0 au"), null);
  assertEquals(
    reusableImageLicense("https://creativecommons.org/licenses/by/4.0/au/"),
    null,
  );
});

Deno.test("reference rights converts provider HTML credit to bounded plain text", () => {
  assertEquals(
    imageCreditText(
      '<a href="https://example.org">Example &amp; Co</a><br> &#169; 2026',
    ),
    "Example & Co © 2026",
  );
  assertEquals(
    imageCreditText("Example &#x2014; Photographer"),
    "Example — Photographer",
  );
  for (
    const value of [
      "<span></span>",
      "Example &unsupported;",
      "&#99999999;",
      "a".repeat(8193),
      "a".repeat(2049),
      null,
    ]
  ) {
    assertEquals(imageCreditText(value), null);
  }
});

Deno.test("Commons identity only accepts exact Commons original or thumbnail paths", () => {
  const original =
    "https://upload.wikimedia.org/wikipedia/commons/a/ab/Example_flower.jpg";
  const thumbnail =
    "https://upload.wikimedia.org/wikipedia/commons/thumb/a/ab/Example_flower.jpg/640px-Example_flower.jpg";
  assertEquals(commonsImageIdentity(original), commonsImageIdentity(thumbnail));
  assertEquals(
    commonsImageIdentity(original),
    commonsImageIdentity(`${original}?utm_source=fixture#image`),
  );
  assertEquals(
    commonsImageIdentity(original)?.title,
    "File:Example_flower.jpg",
  );
  for (
    const url of [
      "https://evil.test/Example.jpg",
      "http://upload.wikimedia.org/wikipedia/commons/a/ab/Example.jpg",
      "https://upload.wikimedia.org/wikipedia/en/a/ab/Example.jpg",
      "https://upload.wikimedia.org/wikipedia/commons/a/ab/Bad%7CFile.jpg",
      "https://upload.wikimedia.org/wikipedia/commons/a/ab/Bad%2FFile.jpg",
    ]
  ) {
    assertEquals(commonsImageIdentity(url), null);
  }
});
