import type { Metadata } from "next";
import { Text } from "@mantine/core";
import { LegalEmailLink, LegalList, LegalPage, LegalSection } from "@/components/LegalPage";

export const metadata: Metadata = {
  title: "Community Guidelines",
  description: "Guidelines for sharing, commenting, and participating in Naturebook Explore."
};

export default function GuidelinesPage() {
  return (
    <LegalPage
      eyebrow="Naturebook community"
      title="Community Guidelines"
      description="These guidelines keep Explore useful, respectful, and safe for people and wildlife."
    >
      <LegalSection title="Share Responsibly">
        <LegalList>
          <li>Share observations that you captured or have permission to post.</li>
          <li>Use geoprivacy when a location could expose people, private property, nests, dens, rare species, or vulnerable habitats.</li>
          <li>Do not encourage touching, eating, collecting, harming, or disturbing organisms.</li>
          <li>Do not publish private field notes or personal information you would not want public.</li>
        </LegalList>
      </LegalSection>

      <LegalSection title="Be Respectful">
        <Text>
          Treat other people as collaborators in learning about the living world. Do not
          harass, threaten, shame, impersonate, dox, spam, or target people based on
          identity, ability, experience level, location, or beliefs.
        </Text>
      </LegalSection>

      <LegalSection title="Keep Content Useful">
        <LegalList>
          <li>Post observations that are relevant to Naturebook&apos;s ecological focus.</li>
          <li>Use comments for identification help, ecological context, questions, and corrections.</li>
          <li>Do not post deceptive, unrelated, explicit, graphic, illegal, or promotional content.</li>
          <li>Do not manipulate likes, comments, follows, reports, or rankings.</li>
        </LegalList>
      </LegalSection>

      <LegalSection title="Moderation">
        <Text>
          Naturebook may remove content, hide posts, limit distribution, disable comments,
          shadow-limit abusive activity, or suspend accounts when needed to protect users,
          wildlife, and the integrity of Explore. Reports and blocks help us review
          problems faster.
        </Text>
      </LegalSection>

      <LegalSection title="Reporting Problems">
        <Text>
          Use in-app report and block controls when available. For urgent concerns or
          appeals, contact <LegalEmailLink />.
        </Text>
      </LegalSection>
    </LegalPage>
  );
}
