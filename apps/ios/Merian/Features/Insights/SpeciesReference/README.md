# Insight Species Reference

The `SpeciesReference` directory handles fetching and displaying external authoritative data.

## Purpose
This area is responsible for presenting external links and summaries, such as in-app Safari links to Wikipedia, GBIF occurrences, or other external taxonomic databases, enriching the core AI-generated insight with established literature.

## External Reference Image Policy

`SimilarSpeciesImageFetcher` is the fallback image resolver for lookalikes that
do not already have a usable `referenceImageUrl`. Candidate Wikipedia/GBIF URLs
must pass `ExternalReferenceImagePolicy` before download. Concurrent downloads
return their source index and are reordered before display, so network timing
cannot change the preferred thumbnail.

The exact denied media path
`inaturalist-open-data.s3.amazonaws.com/photos/605615444/` is treated as absent.
This covers the original and resized variants for GBIF occurrence `5938154750`
without suppressing the European wildcat card or other imagery for the species.
If the first result is denied or fails, the next successful permitted result is
shown. If every result is denied or fails, the existing leaf placeholder is
shown.

Historical `SimilarSpeciesEntry` blobs are sanitized while decoding, so a
previously cached denied URL becomes `nil` and automatically enters this
fallback path. Do not clear all cached lookalikes to repair one media outlier.
