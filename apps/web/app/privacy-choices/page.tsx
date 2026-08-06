import type { Metadata } from "next";
import { Text } from "@mantine/core";
import {
  LegalEmailLink,
  LegalList,
  LegalPage,
  LegalSection,
} from "@/components/LegalPage";

export const metadata: Metadata = {
  title: "Privacy Choices",
  description:
    "How to manage privacy choices and deletion requests, and understand scientific retention in Naturebook.",
};

export default function PrivacyChoicesPage() {
  return (
    <LegalPage
      eyebrow="Naturebook privacy"
      title="Privacy Choices"
      description="Manage permissions, public sharing, and deletion requests."
      lastUpdated="August 5, 2026"
    >
      <LegalSection title="In-App Controls">
        <LegalList>
          <li>
            Use iOS Settings to manage camera, microphone, speech, photo
            library, and location permissions.
          </li>
          <li>
            Exclude Location in Photos&apos; share Options before sending a
            photo to Naturebook.
          </li>
          <li>
            Use Naturebook geoprivacy settings to choose open, obscured, or
            private location sharing behavior.
          </li>
          <li>
            Turn optional Analytics &amp; diagnostics on or off in Naturebook
            Settings. Withdrawal applies immediately on the current device,
            synchronizes across devices for your account, and does not affect
            core functionality.
          </li>
          <li>
            Choose whether to accept required Google Gemini processing before
            using identification. Naturebook has no non-AI identification mode
            or separate Gemini switch in Settings; if you no longer want this
            processing, do not submit scans or use AI features.
          </li>
          <li>
            Unshare Explore posts to remove them from public Explore surfaces.
          </li>
          <li>
            Stop or reset an unfinished Field trip to hide its active status
            from your public author profile. Every account is automatically
            enrolled in Backyard Safari Level 1 under the current product
            contract.
          </li>
          <li>
            Delete individual scans from your library when you no longer want
            them stored.
          </li>
          <li>
            Use account deletion in Naturebook settings to remove your account,
            attribution, private media, and other account-owned cloud data.
          </li>
        </LegalList>
        <Text>
          Under Naturebook&apos;s current design, optional analytics is not used
          to track you across apps or websites owned by other companies or for
          third-party targeted advertising. Naturebook therefore does not
          request Apple&apos;s App Tracking Transparency permission for that
          analytics choice.
        </Text>
      </LegalSection>

      <LegalSection title="Data Export">
        <Text>
          Darwin Core Archive export is unavailable at launch while Naturebook
          completes production validation. When enabled, exports will be queued
          from the app and delivered asynchronously.
        </Text>
      </LegalSection>

      <LegalSection title="Scientific Observation Retention">
        <Text>
          Every submitted scan contributes a scientific observation to the
          Naturebook database. This mandatory record includes exact coordinates
          when present, observation time, taxonomy, identification,
          environmental, quality, and provenance facts. Account deletion removes
          account linkage and account-owned content but does not delete this
          ownerless scientific record. There is no separate opt-in or opt-out
          control for this condition of the Service. Applicable statutory rights
          remain available.
        </Text>
      </LegalSection>

      <LegalSection title="Deletion Help">
        <Text>
          If you cannot access the app or need help with a privacy request,
          contact <LegalEmailLink />{" "}
          from the email associated with your account when possible. We may need
          enough information to verify the account and locate the relevant
          records.
        </Text>
      </LegalSection>

      <LegalSection title="Public Content">
        <Text>
          Removing or unsharing a post can remove it from public Explore pages,
          but copies already shared outside Naturebook may remain wherever
          recipients saved, cached, or reposted them.
        </Text>
        <Text>
          Active Field trip status is separate from an Explore post. Automatic
          Backyard Safari enrollment may show the outing title, level, checklist
          counts, and status on your author profile, but never its scan IDs,
          media, notes, coordinates, or location labels. Stopping or resetting
          an unfinished outing hides that active status. Contact support if you
          need help with a completed status, publication, or privacy request.
        </Text>
      </LegalSection>
    </LegalPage>
  );
}
