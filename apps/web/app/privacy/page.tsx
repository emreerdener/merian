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
  description:
    "How Naturebook collects, uses, shares, and protects information.",
};

export default function PrivacyPolicyPage() {
  return (
    <LegalPage
      eyebrow="Naturebook legal"
      title="Privacy Policy"
      description="This policy explains what Naturebook collects, how it is used, and the controls available to you."
      lastUpdated="August 5, 2026"
    >
      <LegalSection title="Overview">
        <Text>
          Naturebook helps people identify and document plants, animals, fungi,
          insects, and other ecological observations. To provide the app,
          Naturebook may process observation media, account information,
          location context, device diagnostics, payments status, and community
          activity.
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
              <strong>Adult confirmation:</strong>{" "}
              the exact 18-or-older statement you confirm, its policy version,
              confirmation time and method, platform, and app version. We do
              not collect your birth date or exact age for this confirmation.
            </Text>
          </li>
          <li>
            <Text>
              <strong>Observation content:</strong>{" "}
              photos you capture, select, or explicitly share to Naturebook,
              audio clips, descriptions, AI-generated species results, taxonomy,
              field notes, and scan metadata. Sharing one photo from iOS Photos
              gives Naturebook access to that delivered file, not broad access
              to your Photo Library.
            </Text>
          </li>
          <li>
            <Text>
              <strong>Location and environmental context:</strong>{" "}
              exact and privacy-projected GPS coordinates, coordinate
              uncertainty, approximate place names, elevation, weather, time of
              day, month, and device capture context when permissions allow.
            </Text>
          </li>
          <li>
            <Text>
              <strong>Explore activity:</strong>{" "}
              posts you share publicly, comments, likes, reactions, follows,
              reports, blocks, Field trip enrollment and checklist status, Field
              trip publications and Event activity, public author name, and
              public avatar.
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
              if you turn on the optional Analytics &amp; diagnostics control,
              PostHog receives app events, a pseudonymous account identifier,
              app and device state, coarse locale or region, performance and
              reliability signals, feature usage, and event properties about
              how a feature performed. Session replay, automatic screen views,
              element capture, surveys, SDK swizzling, and push-notification
              capture are disabled. Support communications are handled
              separately when you contact us.
            </Text>
          </li>
          <li>
            <Text>
              <strong>Web and beta signup information:</strong>{" "}
              an email address you submit to the beta waitlist, bounded browser
              metadata, and security-challenge signals used to prevent automated
              abuse. Naturebook converts the trusted network address into a
              daily rotating one-way code for rate limiting and does not retain
              the raw address or challenge token in its database.
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
            Maintain the Naturebook scientific observation database, including
            exact location and time needed to study range, migration, phenology,
            biodiversity, and conservation patterns.
          </li>
          <li>
            Save and sync your personal scan library, collections, and field
            notes.
          </li>
          <li>
            Provide offline upload/retry, exports, notifications, and support.
          </li>
          <li>
            Operate Explore posts, comments, likes, follows, reports, blocks,
            Field trip Outings, and Events.
          </li>
          <li>
            Enforce geoprivacy, moderation, anti-abuse, and account-safety
            rules. Audio selected for public Explore sharing may be sent to
            Google Gemini for transient speech and non-speech classification;
            Naturebook does not persist the transcript or model description.
          </li>
          <li>
            When you separately allow optional analytics, understand app
            reliability, usage, subscription status, and feature health.
          </li>
        </LegalList>
      </LegalSection>

      <LegalSection title="Public Explore and Field Trip Status">
        <Text>
          Your personal scans are private unless you choose to share them to
          Explore. When you share a scan, Naturebook may display the public
          image, species labels, public author identity, privacy-filtered
          location label, coarse environmental context, engagement counts,
          comments, and any field notes you choose to publish. Private notes are
          not shown on public Explore pages. An open geoprivacy choice can show
          a precise or near-precise location; obscured and private choices
          reduce or suppress the public location.
        </Text>
        <Text>
          Separately, Naturebook automatically enrolls every account in Backyard
          Safari Level 1. While that outing is active, your public author
          profile may show your author identity, outing title, current level,
          checklist counts, and status, including before you complete a goal.
          Enrollment does not display the underlying scan IDs, media, field
          notes, coordinates, or location labels. Stopping or resetting an
          unfinished outing hides its active profile status; completed status
          and any Field trip publication follow their separate product
          lifecycle.
        </Text>
      </LegalSection>

      <LegalSection title="Location and Geoprivacy">
        <Text>
          Location improves identification and helps build your personal
          ecological journal. You can control location permission in iOS and
          configure Naturebook geoprivacy as open, obscured, or private. Public
          Explore surfaces use Naturebook&apos;s filtered location projection,
          and sensitive species handling may further reduce location precision.
          A photo selected or shared from Photos may include its embedded
          capture date and GPS coordinates. You can exclude Location in
          Photos&apos; share Options; Naturebook does not invent missing
          coordinates or dates. Geoprivacy controls public presentation and
          distribution. It does not remove exact coordinates from the required
          backend scientific observation record created when you submit a scan.
        </Text>
      </LegalSection>

      <LegalSection title="Service Providers">
        <Text>
          Naturebook uses trusted infrastructure and product providers to
          operate the app, including Supabase, Cloudflare R2 and Turnstile,
          Google Gemini, Apple platform services, Google sign-in, RevenueCat,
          PostHog, and Resend. These providers process information only as
          needed to provide, secure, analyze, or support Naturebook.
        </Text>
        <Text>
          Naturebook sends scan data to Google Gemini, a third-party AI
          service, for identification and related AI features. Depending on the
          feature, this may include photos, sampled video frames and video
          audio, audio clips, written descriptions and questions, prior result
          context, exact coordinates, elevation, approximate place information,
          weather and temperature, capture time and month, locale, time zone,
          region, and camera or observation context. The app requires your
          affirmative permission before this sharing.
        </Text>
        <Text>
          PostHog receives the optional analytics and diagnostics categories
          described above only after an account-wide grant. Absence of a grant
          means PostHog analytics are off.
        </Text>
      </LegalSection>

      <LegalSection title="Tracking and Advertising">
        <Text>
          Under Naturebook&apos;s current design, we do not use data to track you
          across apps or websites owned by other companies, and we do not use
          optional PostHog analytics for third-party targeted advertising. The
          Analytics &amp; diagnostics choice controls product analytics for
          Naturebook. Because current analytics behavior is not used for
          tracking, Naturebook does not request Apple&apos;s App Tracking
          Transparency permission for that choice.
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
          <li>
            Choose whether to accept required Google Gemini processing before
            using identification. Naturebook has no non-AI identification mode
            or separate Gemini switch in Settings; if you no longer want this
            processing, do not submit scans or use AI features.
          </li>
          <li>
            Turn optional PostHog analytics on or off using Analytics &amp;
            diagnostics in Naturebook Settings. Withdrawal applies immediately
            on the current device, synchronizes across devices for your account,
            and does not affect core functionality.
          </li>
          <li>Unshare Explore posts or delete scans in the app.</li>
          <li>
            Stop or reset an unfinished Field trip to hide its active status
            from your author profile. This does not delete its underlying scans
            or retained Scientific Data.
          </li>
          <li>
            Request a Darwin Core Archive export when that feature is available.
          </li>
          <li>Delete your account from the app or contact support for help.</li>
        </LegalList>
        <Text>
          Submitting a scan necessarily contributes its Scientific Data,
          including exact coordinates when present, to Naturebook&apos;s
          scientific observation database. This contribution and retention are
          conditions of the Service and do not have a separate opt-in or opt-out
          control. You can prevent future scans from including device location
          by disabling location permission or removing location metadata before
          submission, but account deletion does not delete Scientific Data
          already contributed. Applicable statutory rights remain available.
        </Text>
      </LegalSection>

      <LegalSection title="Retention">
        <Text>
          Naturebook keeps account, waitlist, subscription, media, and Explore
          data for as long as needed to provide and secure the Service, meet the
          periods disclosed for a feature, comply with legal obligations, and
          complete valid deletion requests. Scientific Data from every submitted
          scan is retained for the life of the Naturebook scientific observation
          database. After account deletion, the retained observation is made
          ownerless and keeps exact coordinates, elevation, observation time,
          taxonomy, identification, environmental, quality, and provenance
          facts; account linkage, private media, private free-form notes, and
          device or semantic-location context are removed. Some free-tier cloud
          media may be subject to lifecycle limits, while local copies may
          remain on your device until you delete them or remove the app.
        </Text>
      </LegalSection>

      <LegalSection title="Children">
        <Text>
          Naturebook is not directed to people under 18. If you believe a child
          has provided personal information without appropriate consent, contact
          us so we can review and delete it where required. Before scanning, the
          app requires users to self-attest that they are 18 or older; it does
          not collect a birth date or exact age for that confirmation.
        </Text>
      </LegalSection>

      <LegalSection title="Changes and Contact">
        <Text>
          We may update this policy as Naturebook changes. For privacy
          questions, account requests, or support, contact <LegalEmailLink />.
        </Text>
      </LegalSection>
    </LegalPage>
  );
}
