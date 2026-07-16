import type { Metadata } from "next";
import { Text } from "@mantine/core";
import { LegalEmailLink, LegalList, LegalPage, LegalSection } from "@/components/LegalPage";

export const metadata: Metadata = {
  title: "Privacy Choices",
  description: "How to manage privacy choices, exports, and deletion requests in Merian."
};

export default function PrivacyChoicesPage() {
  return (
    <LegalPage
      eyebrow="Merian privacy"
      title="Privacy Choices"
      description="Manage permissions, public sharing, exports, and deletion requests."
    >
      <LegalSection title="In-App Controls">
        <LegalList>
          <li>Use iOS Settings to manage camera, microphone, speech, photo library, and location permissions.</li>
          <li>Exclude Location in Photos&apos; share Options before sending a photo to Merian.</li>
          <li>Use Merian geoprivacy settings to choose open, obscured, or private location sharing behavior.</li>
          <li>Unshare Explore posts to remove them from public Explore surfaces.</li>
          <li>Delete individual scans from your library when you no longer want them stored.</li>
          <li>Use account deletion in Merian settings to request removal of your account and associated cloud data.</li>
        </LegalList>
      </LegalSection>

      <LegalSection title="Data Export">
        <Text>
          Merian can generate a Darwin Core Archive export for research-friendly access to
          your scan data. Exports are queued from the app and delivered asynchronously when
          processing is complete.
        </Text>
      </LegalSection>

      <LegalSection title="Deletion Help">
        <Text>
          If you cannot access the app or need help with a privacy request, contact{" "}
          <LegalEmailLink /> from the email associated with your account when possible.
          We may need enough information to verify the account and locate the relevant
          records.
        </Text>
      </LegalSection>

      <LegalSection title="Public Content">
        <Text>
          Removing or unsharing a post can remove it from public Explore pages, but copies
          already shared outside Merian may remain wherever recipients saved, cached, or
          reposted them.
        </Text>
      </LegalSection>
    </LegalPage>
  );
}
