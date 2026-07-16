import type { Metadata } from "next";
import { Text } from "@mantine/core";
import { LegalEmailLink, LegalList, LegalPage, LegalSection } from "@/components/LegalPage";

export const metadata: Metadata = {
  title: "Terms of Service",
  description: "Terms for using Naturebook and Naturebook public web pages."
};

export default function TermsPage() {
  return (
    <LegalPage
      eyebrow="Naturebook legal"
      title="Terms of Service"
      description="These terms describe the rules for using Naturebook, Explore, and Naturebook public web pages."
    >
      <LegalSection title="Using Naturebook">
        <Text>
          By using Naturebook, you agree to these terms. If you do not agree, do not use the
          app or public web pages. Naturebook is provided for ecological discovery, education,
          journaling, and community sharing.
        </Text>
      </LegalSection>

      <LegalSection title="Identification Results">
        <Text>
          Naturebook uses AI and public ecological data to suggest identifications. Results may
          be incomplete, incorrect, outdated, or unsuitable for a particular situation. Do
          not rely on Naturebook for medical, veterinary, legal, emergency, toxicity,
          edibility, invasive-species enforcement, or safety-critical decisions. Do not
          touch, eat, handle, or approach organisms based only on Naturebook output.
        </Text>
      </LegalSection>

      <LegalSection title="Accounts and Subscriptions">
        <Text>
          You are responsible for activity on your account and for keeping your device and
          sign-in methods secure. Paid subscriptions are processed through Apple and managed
          by the App Store. Subscription changes, cancellations, and refunds are handled
          under Apple&apos;s applicable policies.
        </Text>
      </LegalSection>

      <LegalSection title="Your Content">
        <Text>
          You keep ownership of your photos, audio, descriptions, field notes, comments,
          and other content. You grant Naturebook a limited license to host, process, transform,
          display, transmit, and analyze that content as needed to operate the service,
          provide AI identification, sync your library, generate exports, prevent abuse,
          and support Explore sharing.
        </Text>
      </LegalSection>

      <LegalSection title="Explore and Community Content">
        <Text>
          If you share content to Explore, it may be visible to other people and on public
          web pages. You are responsible for the content you publish and must have the
          rights needed to share it. Naturebook may remove, limit, or moderate content or
          accounts that violate these terms, community guidelines, privacy expectations, or
          applicable law.
        </Text>
      </LegalSection>

      <LegalSection title="Rules">
        <LegalList>
          <li>Do not upload content you do not own or have permission to share.</li>
          <li>Do not harass, threaten, impersonate, spam, scrape, or abuse others.</li>
          <li>Do not attempt to bypass security, rate limits, moderation, or geoprivacy.</li>
          <li>Do not use Naturebook to locate, harm, poach, or exploit sensitive species.</li>
          <li>Do not submit unlawful, deceptive, hateful, explicit, or harmful content.</li>
        </LegalList>
      </LegalSection>

      <LegalSection title="Third-Party Services">
        <Text>
          Naturebook depends on third-party services including Apple, Supabase, Cloudflare,
          Google, RevenueCat, PostHog, and Resend. Your use of those
          services through Naturebook may also be subject to their own terms and policies.
        </Text>
      </LegalSection>

      <LegalSection title="Service Changes">
        <Text>
          Naturebook may change, suspend, or discontinue features, limits, pricing, public
          routes, or integrations. We may also suspend or terminate access when needed to
          protect users, the service, wildlife, or legal compliance.
        </Text>
      </LegalSection>

      <LegalSection title="Disclaimers and Liability">
        <Text>
          Naturebook is provided as available and without warranties to the fullest extent
          permitted by law. To the fullest extent permitted by law, Naturebook is not liable
          for indirect, incidental, consequential, special, exemplary, or punitive damages,
          or for decisions made from identification results.
        </Text>
      </LegalSection>

      <LegalSection title="Contact">
        <Text>
          Questions about these terms can be sent to <LegalEmailLink />.
        </Text>
      </LegalSection>
    </LegalPage>
  );
}
