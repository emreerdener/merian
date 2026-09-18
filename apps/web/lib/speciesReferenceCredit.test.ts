import assert from "node:assert/strict";
import test from "node:test";
import {
  referenceImageCaption,
  speciesReferenceCredit,
} from "./speciesReferenceCredit.ts";
import { webSafeReferenceImages } from "./species.ts";
import { fetchExternalEnrichment } from "../../../services/supabase/functions/_shared/external.ts";
import { referenceImagesFromRows } from "../../../services/supabase/functions/_shared/publicSpeciesProjection.ts";

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
