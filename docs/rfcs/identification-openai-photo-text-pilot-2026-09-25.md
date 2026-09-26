# OpenAI photo/text identification pilot

Date: 25 September 2026 (America/Chicago) Status: Pilot accounted for; seven
normalized results, one preserved unknown outcome; production remains Gemini

The first live `gpt-6-sol` comparison exercised the local OpenAI adapter against
the six existing photo examples and two descriptions. The initial run produced
three normalized results and one uncertain bison attempt. A separately approved
continuation completed only the four untouched cases in their original relative
order. All eight unique cases have a durable claim; none was replayed. The
server-issue explanation is owner-reported, without an independently captured
endpoint or HTTP status.

The
[machine-readable evidence](./identification-evaluation-evidence/2026-09-25-openai-photo-text-pilot/results.json)
preserves counts, source/packet/ledger hashes and bounded decisions. The
[provider guide](../development-guides/22-alternative-identification-provider.md)
owns the adapter and onboarding contract. Existing Gemini
[photo](./identification-source-photo-app-benchmark-2026-09-22.md) and
[description](./identification-description-app-benchmark-2026-09-22.md) results
remain historical evidence.

## Observed results

| Example              | Historical Gemini result                                            | OpenAI result                                                       |
| -------------------- | ------------------------------------------------------------------- | ------------------------------------------------------------------- |
| Bison photo          | Bison bison                                                         | Unknown; first attempt preserved                                    |
| Bald eagle photo     | Haliaeetus leucocephalus                                            | Haliaeetus leucocephalus                                            |
| Monarch photo        | Danaus plexippus                                                    | Danaus plexippus                                                    |
| Sunflower photo      | Helianthus annuus                                                   | Helianthus annuus                                                   |
| Saguaro photo        | Carnegiea gigantea                                                  | Carnegiea gigantea                                                  |
| Mineral photo        | Non-biological                                                      | Non-biological                                                      |
| Mushroom description | Amanita muscaria; provisional reference supports genus only         | Named biological answer; name absent from retained taxonomy mapping |
| Basalt description   | Daldinia concentrica; biological assertion on non-biological source | Non-biological                                                      |

Four species results and both non-biological results agree with their
provisional references. The mushroom result is a benchmark limitation: only
exact names in the small frozen taxonomy are retained as identities. Its
unmatched name cannot be reconstructed from the saved record. Do not count it as
a verified model error, infer the missing name, or reclassify it after seeing
the result. The basalt description is ambiguous; its OpenAI subject
classification agrees with the source reference where the earlier Gemini answer
did not, but this single observation does not establish general superiority.

## Timing, cost and evidence limits

The seven normalized requests took **6.509–7.477 seconds** at the provider
boundary, with a **6.914-second median**. Their combined conservative usage
estimate is **USD 0.17579**. The interrupted request's usage and billed cost
remain unknown, so the complete actual cost is unknown. The owner approved a USD
15 combined guard for the continuation, retaining the full USD 5.37288
reservation for that uncertain attempt; a reservation is not a charge.

Capture, upload, hydration, persistence and rendering are outside these timings.
Earlier Gemini runs used the app with different crop/context and execution
boundaries; this is not a paired speed or price comparison. References are
provisional, confidence is unqualified, and seven normalized results do not
establish formal accuracy or production readiness.

Both execution segments used source commit
`480593d6d3b15e2c1c60514737feab414411a334` with dirty graph
`701c94dba3ae0cccb6f8160dc0225267563260bb988ff294a98ebfcb992d5bc2`. Each
segment's source, manifest, immutable claims/results and frozen inputs were
checked. The continuation retained exact request fingerprints and
input/reference records for its four-case subset. The pre-request launcher
failure sent no provider requests; its explicit environment-denial fix passed
the real Deno admission regression and complete Supabase tooling gate before
this run.

## Decision and next milestone

Close this initial provider-path pilot with its unknown and unscorable entries
retained. It establishes working OpenAI credentials, live photo/text inference
and durable evaluation through the shared abstraction. Prepare the adapter and
evidence for source review and commit. Resolve taxonomy identity matching before
another scored comparison, and complete provider consent,
confidence/persistence, admission and rollout controls before assigning
production requests to OpenAI. Gemini remains the production default. This
record authorizes no further model requests or deployment.
