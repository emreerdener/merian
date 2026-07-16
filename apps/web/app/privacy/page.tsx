import type { Metadata } from "next";
import { Text } from "@mantine/core";
import {
  LegalEmailLink,
  LegalList,
  LegalPage,
  LegalSection,
} from "@/components/LegalPage";

export const metadata: Metadata = {
  title: "Privacy Policy",
  description: "How Naturebook collects, uses, shares, and protects information.",
};

export default function PrivacyPolicyPage() {
  return (
    <LegalPage
      eyebrow="Naturebook legal"
      title="Privacy Policy"
      description="This policy explains what Naturebook collects, how it is used, and the controls available to you."
    >
      <LegalSection title="Overview">
        <Text>
          Naturebook helps people identify and document plants, animals, fungi,
          insects, and other ecological observations. To provide the app, Naturebook
          may process observation media, account information, location context,
          device diagnostics, payments status, and community activity.
        </Text>
      </LegalSection>

      <LegalSection title="Information We Collect">
        <LegalList>
          <li>
            <Text>
              <strong>Account information:</strong>{" "}
              anonymous device identity, Supabase user id, and, if you sign in,
              account details such as email, name, and avatar from Apple or
              Google.
            </Text>
          </li>
          <li>
            <Text>
              <strong>Observation content:</strong>{" "}
              photos you capture, select, or explicitly share to Naturebook, audio
              clips, descriptions, AI-generated species results, taxonomy,
              field notes, and scan metadata. Sharing one photo from iOS Photos
              gives Naturebook access to that delivered file, not broad access to
              your Photo Library.
            </Text>
          </li>
          <li>
            <Text>
              <strong>Location and environmental context:</strong>{" "}
              GPS coordinates, approximate place names, elevation, weather, time
              of day, month, and device capture context when permissions allow.
            </Text>
          </li>
          <li>
            <Text>
              <strong>Explore activity:</strong>{" "}
              posts you share publicly, comments, likes, reactions, follows,
              reports, blocks, public author name, and public avatar.
            </Text>
          </li>
          <li>
            <Text>
              <strong>Payments and entitlement status:</strong>{" "}
              subscription status and purchase events from RevenueCat and Apple,
              but not full payment card details.
            </Text>
          </li>
          <li>
            <Text>
              <strong>Analytics and diagnostics:</strong>{" "}
              app events, device state, crashes, performance signals, feature
              usage, and support communications.
            </Text>
          </li>
        </LegalList>
      </LegalSection>

      <LegalSection title="How We Use Information">
        <LegalList>
          <li>
            Identify observations and generate structured ecological results.
          </li>
          <li>
            Save and sync your personal scan library, collections, and field
            notes.
          </li>
          <li>
            Provide offline upload/retry, exports, notifications, and support.
          </li>
          <li>
            Operate Explore posts, comments, likes, follows, reports, and
            blocks.
          </li>
          <li>
            Enforce geoprivacy, moderation, anti-abuse, and account-safety
            rules. Audio selected for public Explore sharing may be sent to
            Google Gemini for transient speech and non-speech classification;
            Naturebook does not persist the transcript or model description.
          </li>
          <li>
            Understand app reliability, usage, subscription status, and feature
            health.
          </li>
        </LegalList>
      </LegalSection>

      <LegalSection title="Public Explore Sharing">
        <Text>
          Your personal scans are private unless you choose to share them to
          Explore. When you share a scan, Naturebook may display the public image,
          species labels, public author identity, privacy-filtered location
          label, coarse environmental context, engagement counts, comments, and
          any field notes you choose to publish. Exact coordinates and private
          notes are not shown on public Explore pages.
        </Text>
      </LegalSection>

      <LegalSection title="Location and Geoprivacy">
        <Text>
          Location improves identification and helps build your personal
          ecological journal. You can control location permission in iOS and
          configure Naturebook geoprivacy as open, obscured, or private. Public
          Explore surfaces use Naturebook&apos;s filtered location projection, and
          sensitive species handling may further reduce location precision. A
          photo selected or shared from Photos may include its embedded capture
          date and GPS coordinates. You can exclude Location in Photos&apos; share
          Options; Naturebook does not invent missing coordinates or dates.
        </Text>
      </LegalSection>

      <LegalSection title="Service Providers">
        <Text>
          Naturebook uses trusted infrastructure and product providers to operate
          the app, including Supabase, Cloudflare R2, Google Gemini, Apple
          platform services, Google sign-in, RevenueCat, PostHog, and Resend.
          These providers process information only as needed to provide, secure,
          analyze, or support Naturebook.
        </Text>
      </LegalSection>

      <LegalSection title="Your Choices">
        <LegalList>
          <li>
            Disable camera, microphone, photo library, speech, or location
            permissions in iOS.
          </li>
          <li>
            Exclude Location in the iOS Photos share Options before sending a
            photo to Naturebook.
          </li>
          <li>Change geoprivacy settings in Naturebook.</li>
          <li>Unshare Explore posts or delete scans in the app.</li>
          <li>
            Request a Darwin Core Archive export from the profile settings.
          </li>
          <li>Delete your account from the app or contact support for help.</li>
        </LegalList>
      </LegalSection>

      <LegalSection title="Retention">
        <Text>
          Naturebook keeps account, scan, subscription, and Explore data for as long
          as needed to provide the service, maintain records, prevent abuse,
          comply with legal obligations, and honor deletion requests. Some
          free-tier cloud media may be subject to lifecycle limits, while local
          copies may remain on your device until you delete them or remove the
          app.
        </Text>
      </LegalSection>

      <LegalSection title="Children">
        <Text>
          Naturebook is not directed to children under 13. If you believe a child
          has provided personal information without appropriate consent, contact
          us so we can review and delete it where required.
        </Text>
      </LegalSection>

      <LegalSection title="Changes and Contact">
        <Text>
          We may update this policy as Naturebook changes. For privacy questions,
          account requests, or support, contact <LegalEmailLink />.
        </Text>
      </LegalSection>
    </LegalPage>
  );
}
