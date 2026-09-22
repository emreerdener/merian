import assert from "node:assert/strict";
import test from "node:test";
import {
  attributionParts,
  referenceImageCaption,
  speciesReferenceCredit,
} from "./speciesReferenceCredit.ts";
import { webSafeReferenceImages } from "./species.ts";
import { fetchExternalEnrichment } from "../../../services/supabase/functions/_shared/external.ts";
import { referenceImagesFromRows } from "../../../services/supabase/functions/_shared/publicSpeciesProjection.ts";

test("embedded attribution URLs use readable links without losing credit or destinations", () => {
  const website = "http://www.example.org/flowers/yellow.htm";
  const license = "https://creativecommons.org/licenses/by-sa/3.0/";
  const attribution = `Émile Example · ${website} · ${license}`;
  const parts = attributionParts(attribution);
  assert.equal(
    parts.map((part) => part.label).join(""),
    "Émile Example · Website · CC BY-SA 3.0",
  );
  assert.deepEqual(parts.flatMap((part) => part.url ?? []), [website, license]);
  assert.equal(
    referenceImageCaption({
      url: "https://images.example.org/flower.jpg",
      source: "gbif",
      license: "CC BY-SA 3.0",
      attribution,
    }),
    "Émile Example · Website · CC BY-SA 3.0 — CC BY-SA 3.0 · GBIF",
  );
});

test("credit formatting handles URL-only credits, punctuation and plain names", () => {
  for (
    const [input, expected] of [
      ["https://creativecommons.org/licenses/by/3.0/au/", "CC BY 3.0 AU"],
      ["https://creativecommons.org/publicdomain/zero/1.0/", "CC0 1.0"],
      ["https://creativecommons.org/publicdomain/mark/1.0/", "Public domain"],
      ["https://creativecommons.org/unknown", "License"],
      ["https://creativecommons.org.example.org/licenses/by/4.0/", "Website"],
      ["www.example.org/credit", "Website"],
      ["example.org/credit", "Website"],
      ["first.last@example.org", "first.last@example.org"],
      ["ftp://example.org/credit", "Website"],
      ["mailto:creator@example.org", "Contact"],
      [
        "Photo (https://example.org/credit), https://example.org/credit.",
        "Photo (Website), Website.",
      ],
      ["Example Photographer · CC BY 4.0", "Example Photographer · CC BY 4.0"],
    ]
  ) {
    assert.equal(
      attributionParts(input).map((part) => part.label).join(""),
      expected,
    );
  }
  assert.deepEqual(attributionParts(undefined), []);
});

test("credit links preserve balanced URL parentheses and query strings", () => {
  const url = "https://example.org/credit_(photo)?author=example#credit";
  const parts = attributionParts(`Photo (${url}).`);
  assert.equal(parts.map((part) => part.label).join(""), "Photo (Website).");
  assert.deepEqual(parts.flatMap((part) => part.url ?? []), [url]);
  assert.deepEqual(attributionParts("https://example.org/credit_(photo)"), [
    { label: "Website", url: "https://example.org/credit_(photo)" },
  ]);
  assert.deepEqual(attributionParts("www.example.org?author=example"), [
    { label: "Website", url: "https://www.example.org/?author=example" },
  ]);
});

test("species credits link canonical licenses and the exact Commons file", () => {
  const image = {
    url: "https://upload.wikimedia.org/wikipedia/commons/a/ab/Flower.jpg",
    source: "wikipedia" as const,
    license: "https://creativecommons.org/licenses/by-sa/4.0/",
    attribution: "Example Photographer",
  };
  assert.deepEqual(speciesReferenceCredit(image), {
    licenseURL: "https://creativecommons.org/licenses/by-sa/4.0/",
    licenseLabel: "CC BY-SA 4.0",
    sourceLabel: "Wikipedia",
    sourceURL: "https://commons.wikimedia.org/wiki/File%3AFlower.jpg",
  });
  assert.equal(
    referenceImageCaption(image),
    "Example Photographer — CC BY-SA 4.0 · Wikipedia",
  );
});

test("provider rights survive the public projection and web attribution gate", async () => {
  const url = "https://upload.wikimedia.org/wikipedia/commons/a/ab/Flower.jpg";
  const fetcher: typeof fetch = async (input) => {
    const target = new URL(String(input));
    const data = target.hostname === "commons.wikimedia.org"
      ? {
        query: {
          pages: [{
            imageinfo: [{
              url,
              extmetadata: {
                LicenseShortName: { value: "CC BY-SA 4.0" },
                Artist: { value: "Example Photographer" },
              },
            }],
          }],
        },
      }
      : target.hostname === "en.wikipedia.org"
      ? { type: "standard", originalimage: { source: url } }
      : { matchType: "NONE" };
    return new Response(JSON.stringify(data));
  };
  const enriched = await fetchExternalEnrichment("Example species", fetcher, {
    includeImageRights: true,
  });
  const projected = referenceImagesFromRows(enriched.referenceImages, null);
  const images = webSafeReferenceImages(projected);
  assert.equal(images.length, 1);
  assert.equal(images[0].url, url);
  assert.equal(
    referenceImageCaption(images[0]),
    "Example Photographer — CC BY-SA 4.0 · Wikipedia",
  );
  assert.deepEqual(webSafeReferenceImages([{ url, source: "wikipedia" }]), []);
});

test("GBIF credits link the original supplied material without inventing a source page", () => {
  const credit = speciesReferenceCredit({
    url: "https://images.example.org/flower.jpg",
    source: "gbif",
    license: "CC BY 4.0",
    attribution: "Example Photographer",
  });
  assert.equal(credit.sourceURL, "https://images.example.org/flower.jpg");
  assert.equal(
    credit.licenseURL,
    "https://creativecommons.org/licenses/by/4.0/",
  );
});

test("Australian license captions retain their jurisdiction", () => {
  const credit = speciesReferenceCredit({
    url: "https://images.example.org/flower.jpg",
    source: "gbif",
    license: "https://creativecommons.org/licenses/by/3.0/au/",
    attribution: "Example Photographer",
  });
  assert.equal(credit.licenseLabel, "CC BY 3.0 AU");
  assert.equal(
    credit.licenseURL,
    "https://creativecommons.org/licenses/by/3.0/au/",
  );
});
