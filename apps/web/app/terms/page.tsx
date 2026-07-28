import type { Metadata } from "next";
import { Anchor, Text } from "@mantine/core";
import {
  LegalEmailLink,
  LegalList,
  LegalPage,
  LegalSection,
} from "@/components/LegalPage";

export const metadata: Metadata = {
  title: "Terms of Service",
  description:
    "Terms for using Naturebook, Naturebook Explore, and Naturebook public web pages.",
};

export default function TermsPage() {
  return (
    <LegalPage
      eyebrow="Naturebook legal"
      title="Terms of Service"
      description="These Terms govern the Naturebook app, Explore community, subscriptions, and Naturebook public web pages."
      lastUpdated="July 28, 2026"
    >
      <LegalSection title="1. Agreement to These Terms">
        <Text>
          These Terms of Service (&quot;Terms&quot;) are an agreement between
          you and the operator of Naturebook (&quot;Naturebook,&quot;
          &quot;we,&quot; &quot;us,&quot; or &quot;our&quot;). They apply to
          the Naturebook mobile app, Explore, public web pages, and related
          features and services (together, the &quot;Service&quot;).
        </Text>
        <Text>
          By tapping the control that accepts these Terms, creating or using a
          Naturebook account, submitting a scan, purchasing access, or otherwise
          using the Service, you agree to these Terms. If you do not agree, do
          not use the Service. The{" "}
          <Anchor href="/privacy" fw={700}>
            Privacy Policy
          </Anchor>{" "}
          explains how we handle personal information, and the{" "}
          <Anchor href="/guidelines" fw={700}>
            Community Guidelines
          </Anchor>{" "}
          are incorporated into these Terms when you use Explore.
        </Text>
        <Text>
          Some rights cannot legally be waived or limited. Nothing in these
          Terms removes any mandatory consumer, privacy, or other statutory
          right that applies to you.
        </Text>
      </LegalSection>

      <LegalSection title="2. Eligibility">
        <Text>
          You must be at least 18 years old and legally able to enter into these
          Terms to use Naturebook. The Service is not directed to, and may not
          be used by, anyone under 18. If you use the Service for an
          organization, you represent that you have authority to bind that
          organization, and &quot;you&quot; includes that organization.
        </Text>
      </LegalSection>

      <LegalSection title="3. The Naturebook Service and App License">
        <Text>
          Naturebook supports ecological discovery, education, journaling,
          scientific documentation, and community sharing. Subject to these
          Terms, Naturebook grants you a limited, personal, revocable,
          non-exclusive, non-transferable, and non-sublicensable license to
          install and use the app on devices you own or control, solely for its
          intended purpose and as permitted by applicable store usage rules.
          The app is licensed, not sold. Naturebook and its licensors retain all
          rights in the Service not expressly granted to you.
        </Text>
        <Text>
          Features, models, limits, eligibility, availability, and supported
          devices may differ by plan, region, app version, or technical
          capacity. Access described as &quot;unlimited&quot; is still subject
          to reasonable fair-use, safety, anti-abuse, rate, file-size, and
          provider limits. Naturebook is not a data-backup or emergency
          service.
        </Text>
      </LegalSection>

      <LegalSection title="4. Accounts and Account Security">
        <Text>
          Naturebook may automatically create an anonymous account so you can
          begin using the app. You may later link that account to an available
          sign-in provider. You are responsible for activity through your
          account and for protecting your device and credentials. Tell us
          promptly if you suspect unauthorized access. You may not transfer,
          sell, rent, or share an account in a way that undermines security,
          plan limits, or another person&apos;s rights.
        </Text>
      </LegalSection>

      <LegalSection title="5. Required AI Processing — Important">
        <Text>
          <strong>
            AI processing is a core and necessary part of Naturebook&apos;s
            identification service.
          </strong>{" "}
          Naturebook uses the Google Gemini API, operated by Google, to process
          identification requests and certain related AI features. Depending on
          the feature and permissions you choose, information sent to Google
          may include photos, sampled video frames and video audio, audio clips,
          written descriptions, follow-up questions, prior identification
          context, exact coordinates, elevation, approximate place information,
          weather and temperature, capture time and month, locale, time zone,
          region, and relevant camera or observation context.
        </Text>
        <Text>
          Before Naturebook sends personal information from your scan to Google
          Gemini, the app will clearly disclose this processing and ask you to
          affirmatively accept it. The AI disclosure and permission may be part
          of the same acceptance flow as these Terms; it does not need to be a
          separate contract. By tapping that acceptance control and then
          submitting a scan or using an AI feature, you specifically authorize
          Naturebook to transmit and process the applicable information through
          Google Gemini and the infrastructure providers needed to deliver,
          secure, troubleshoot, and maintain that feature.
        </Text>
        <Text>
          If you do not permit this processing, do not submit scans or use
          Naturebook&apos;s AI features. Because identification is the
          Service&apos;s central function, declining required AI processing
          means the core identification Service will not be available. You may
          withdraw permission for future AI processing by stopping submissions
          and deleting applicable content or your account, subject to the
          de-identified scientific-data provisions below. Withdrawal does not
          invalidate processing already performed lawfully.
        </Text>
        <Text>
          We will not materially expand the information sent to third-party AI
          providers, or use it for a materially different purpose such as
          training a third party&apos;s general-purpose model, without updating
          our disclosures and obtaining additional permission when required.
          Provider processing is also subject to the applicable provider terms
          and privacy commitments described in our Privacy Policy.
        </Text>
      </LegalSection>

      <LegalSection title="6. AI and Ecological Information Are Not Guaranteed">
        <Text>
          Naturebook uses probabilistic AI and ecological information from
          public and third-party sources. Identifications, confidence scores,
          descriptions, conservation information, hazard labels, location
          context, and other results may be incorrect, incomplete, duplicated,
          outdated, biased, or unsuitable for your circumstances. Similar
          outputs may be generated for other users. Naturebook does not promise
          that an organism can be identified or that any output is unique,
          accurate, safe, or fit for a particular purpose.
        </Text>
        <Text>
          Do not rely on Naturebook for medical, veterinary, poison-control,
          edibility, toxicity, allergy, emergency, legal, regulatory,
          invasive-species enforcement, harvesting, navigation, or other
          safety-critical decisions. Do not touch, eat, collect, handle,
          approach, relocate, or treat an organism based only on Naturebook.
          Consult qualified local experts and authoritative sources.
        </Text>
      </LegalSection>

      <LegalSection title="7. Product Analytics">
        <Text>
          Naturebook uses PostHog and may use comparable providers identified
          in the Privacy Policy to understand app reliability, lifecycle
          events, feature and product interactions, funnels, subscription and
          entitlement events, performance, and Service health. Analytics may
          include a pseudonymous or account identifier, app and device state,
          coarse locale or region, and event properties connected to how a
          feature performed. Naturebook currently disables PostHog session
          replay, element autocapture, automatic screen-view capture, surveys,
          and SDK swizzling.
        </Text>
        <Text>
          By accepting these Terms, you authorize the product-analytics
          processing described above, subject to the Privacy Policy and
          applicable law. Where law requires a separate choice or gives you a
          right to object or withdraw, Naturebook will honor that right.
          Declining non-essential analytics will not prevent access to the core
          identification Service. You may contact <LegalEmailLink /> to object
          to or withdraw future non-essential analytics processing. Withdrawal
          does not affect processing already performed lawfully.
        </Text>
      </LegalSection>

      <LegalSection title="8. Purchases, Passes, Subscriptions, and Trials">
        <Text>
          Naturebook may offer free access with usage limits, a non-renewing
          seven-day Pro pass, an auto-renewing annual Pro subscription,
          promotional access, or an eligibility-based trial. The product,
          duration, current storefront price, taxes, renewal terms, and trial
          eligibility shown in the App Store purchase flow control over
          descriptive copy elsewhere.
        </Text>
        <LegalList>
          <li>
            A non-renewing pass expires at the end of its stated period and does
            not renew automatically.
          </li>
          <li>
            An auto-renewing subscription renews for the period shown at
            purchase unless you cancel through Apple before renewal.
          </li>
          <li>
            Apple processes payment and controls billing, cancellation,
            renewal, storefront pricing, and refund procedures. Naturebook does
            not receive your full payment-card details.
          </li>
          <li>
            Trials may convert to paid access as disclosed in the purchase flow
            and may be limited to eligible users.
          </li>
          <li>
            Deleting the Naturebook app or your Naturebook account does not
            cancel an Apple subscription. You must cancel it separately in your
            Apple subscription settings.
          </li>
          <li>
            Paid access remains subject to technical, fair-use, safety,
            anti-abuse, and provider limits.
          </li>
        </LegalList>
      </LegalSection>

      <LegalSection title="9. Your Content and the Operational License">
        <Text>
          You retain whatever ownership rights you have in photos, videos,
          audio, descriptions, field notes, comments, profile material,
          corrections, and other content you submit
          (&quot;Your Content&quot;). You grant Naturebook a worldwide,
          non-exclusive, royalty-free, sublicensable license to host, copy,
          cache, encode, compress, transmit, process, analyze, format,
          technically modify, and create technical derivatives of Your Content
          as reasonably needed to operate, secure, improve, troubleshoot, and
          support the Service; provide AI identification and related features;
          sync your library; enforce permissions and geoprivacy; generate
          requested exports; prevent abuse; and fulfill your sharing choices.
          This operational license lasts while the content is stored or as
          reasonably needed for backups, security, legal compliance, and
          processing already initiated before deletion.
        </Text>
        <Text>
          You represent that you have all rights and permissions needed to
          submit Your Content and grant these licenses. Your Content must not
          infringe intellectual-property, privacy, publicity, confidentiality,
          contractual, or other rights. Do not submit another person&apos;s
          face, voice, private information, confidential material, or precise
          location without all legally required permission. You remain
          responsible for Your Content and the consequences of sharing it.
        </Text>
      </LegalSection>

      <LegalSection title="10. Public Contributions and Reference Photos">
        <Text>
          Personal scans are private unless you deliberately publish them to
          Explore or another public surface. When you publish content
          (&quot;Public Contributions&quot;), it may be visible in the app and
          on public web pages, search previews, social previews, feeds, maps,
          and species pages. Public Contributions may include your public
          author identity, privacy-filtered location, species labels,
          observation context you elect to publish, engagement, and comments.
        </Text>
        <Text>
          For each Public Contribution, you grant Naturebook a worldwide,
          non-exclusive, royalty-free, transferable, and sublicensable license
          to host, reproduce, format, adapt for technical or editorial display,
          translate, communicate, publicly perform or display, distribute, make
          available, index, moderate, and promote that contribution in
          connection with Naturebook and its scientific and educational
          purposes. This includes permission to select eligible shared photos
          as species reference imagery and to show them to other users as a
          reference for, comparison with, or support for other
          identifications. Naturebook may display the public attribution
          connected to the contribution while it remains available.
        </Text>
        <Text>
          Naturebook&apos;s current reference-image system considers only
          eligible, visible Explore photos that satisfy quality, confidence,
          moderation, media, and geoprivacy rules. Unsharing a post, deleting
          the underlying scan, deleting your account, or moderation may remove
          the photo from active Naturebook public and reference surfaces after
          processing and cache delays. Removal does not reverse identifications
          already delivered or require Naturebook to recall copies that others
          lawfully made while the contribution was public, except where
          applicable law requires otherwise. Naturebook will not license your
          original media as a standalone stock-media asset unless you separately
          agree.
        </Text>
      </LegalSection>

      <LegalSection title="11. Scientific Observation Data and Commercial Use">
        <Text>
          Naturebook may extract or derive scientific observation data from
          scans and Public Contributions. Examples include taxonomy,
          identification and confidence, confirmation state, observation time,
          coarse or geoprivacy-projected location, environmental conditions,
          biological traits, quality signals, and non-identifying usage or
          provenance information (&quot;Scientific Data&quot;). Scientific Data
          does not include your original private media, account credentials,
          private notes, exact private location, or information that Naturebook
          continues to treat as directly identifying, unless you have
          separately chosen to make that information public and the applicable
          license permits the use.
        </Text>
        <Text>
          To the extent you have any intellectual-property or database right in
          Scientific Data, you grant Naturebook a perpetual, irrevocable,
          worldwide, non-exclusive, royalty-free, transferable, and
          sublicensable license to collect, validate, correct, structure,
          combine, aggregate, de-identify, analyze, reproduce, publish,
          distribute, share, license, sell, and otherwise use that Scientific
          Data for scientific, conservation, educational, operational, or
          commercial purposes, subject to applicable law and our geoprivacy and
          privacy commitments.
        </Text>
        <Text>
          Naturebook may provide or license Scientific Data for free or for a
          fee to scientific organizations, researchers, conservation groups,
          educational institutions, public bodies, data platforms, and
          commercial partners. Naturebook may retain any resulting revenue, and
          you are not entitled to royalties, payment, accounting, approval, or
          ownership in resulting datasets, analyses, or products. We will not
          attempt to re-identify de-identified Scientific Data or permit a
          recipient to do so. If retained data remains personal information
          under applicable law, your applicable privacy rights continue to
          apply notwithstanding this section.
        </Text>
      </LegalSection>

      <LegalSection title="12. Location, Geoprivacy, and Embedded Metadata">
        <Text>
          Location and environmental context can improve an identification and
          your ecological journal. With applicable permission, exact location
          may be stored privately and sent as AI context. Public surfaces use
          the geoprivacy choice available for the observation or post—such as
          open, obscured, or private—and Naturebook may further obscure
          sensitive-species locations. An &quot;open&quot; choice can expose a
          precise or near-precise location. No geoprivacy method eliminates all
          inference or re-identification risk.
        </Text>
        <Text>
          A file selected from your photo library may contain embedded capture
          time, device, or GPS metadata. Review the file and iOS sharing options
          before submission. Do not publish a location that could endanger
          people, private property, nests, dens, vulnerable habitat, or a
          sensitive species. Naturebook may reduce location precision, limit
          distribution, or remove content to protect people, wildlife, and the
          Service.
        </Text>
      </LegalSection>

      <LegalSection title="13. Explore, Community Conduct, and Moderation">
        <Text>
          Explore includes public profiles, posts, comments, replies,
          reactions, likes, follows, hashtags, notifications, maps, nearby
          discovery, reports, blocks, and community identification. You must
          comply with the Community Guidelines and all applicable law.
          Naturebook does not endorse and is not responsible for user content,
          and we do not promise to monitor every contribution.
        </Text>
        <LegalList>
          <li>
            Do not harass, threaten, shame, stalk, dox, impersonate, exploit, or
            discriminate against another person.
          </li>
          <li>
            Do not upload unlawful, deceptive, hateful, sexually explicit,
            graphically harmful, confidential, infringing, or unrelated
            promotional content.
          </li>
          <li>
            Do not spam, manipulate engagement or reports, create deceptive
            accounts, or interfere with community-identification integrity.
          </li>
          <li>
            Do not use Naturebook to locate, disturb, collect, poach, harm, or
            exploit wildlife or sensitive habitat, or to trespass.
          </li>
          <li>
            Do not bypass blocks, moderation, security, geoprivacy, purchase
            controls, quotas, or rate limits.
          </li>
        </LegalList>
        <Text>
          Naturebook may review, preserve, restrict, label, deprioritize, hide,
          remove, or disclose content; disable interactions; or warn, suspend,
          or terminate accounts when reasonably needed for enforcement, safety,
          legal process, or Service integrity. We may use automated tools and
          human review. You may report content or seek review of a moderation
          decision through available in-app controls or <LegalEmailLink />.
        </Text>
      </LegalSection>

      <LegalSection title="14. Other Prohibited Uses">
        <Text>You may not:</Text>
        <LegalList>
          <li>
            copy, modify, distribute, sell, lease, reverse engineer, extract
            source code from, or create derivative works of the app or Service,
            except to the extent a restriction is prohibited by law or an
            open-source license permits it;
          </li>
          <li>
            scrape, harvest, crawl, bulk export, train a model from, or
            commercially exploit the Service or its content without written
            permission;
          </li>
          <li>
            probe, disrupt, overload, or gain unauthorized access to the
            Service, another account, or connected infrastructure;
          </li>
          <li>
            introduce malware or use automation in a way that exceeds ordinary
            personal use or published interfaces;
          </li>
          <li>
            misrepresent AI output as verified expert advice or use the Service
            in clinical practice or to provide medical advice; or
          </li>
          <li>
            use the Service in violation of applicable law, sanctions, export
            controls, provider policies, or third-party rights.
          </li>
        </LegalList>
      </LegalSection>

      <LegalSection title="15. Third-Party Services, Data, and Links">
        <Text>
          Naturebook relies on third-party services and content, which may
          include Apple, Supabase, Cloudflare, Google, RevenueCat, PostHog,
          Resend, Wikipedia, Wikimedia Commons, GBIF, and other ecological data
          sources. Their content, availability, and processing may be subject to
          separate terms, licenses, notices, and policies. You must comply with
          applicable third-party terms when using the Service.
        </Text>
        <Text>
          Naturebook does not control or guarantee third-party services, sites,
          species data, maps, media, or links. Attribution and license
          information accompanying third-party material must be preserved.
          Access to a third-party source through Naturebook does not imply that
          Naturebook or that source endorses the other.
        </Text>
      </LegalSection>

      <LegalSection title="16. Storage, Retention, and Deletion">
        <Text>
          Do not use Naturebook as the only copy of important content.
          Biological scan media is generally retained while the scan remains
          active, unless you delete it, moderation removes it, storage becomes
          unavailable, or Naturebook takes an authorized operational or legal
          action. Completed non-biological scans and their media may be purged
          after 30 days. Temporary upload, staging, quarantine, and generated
          export areas may have shorter lifecycle periods. Local copies may
          remain on your device until the app deletes them or you remove them.
        </Text>
        <Text>
          Deleting an individual scan removes its server scan record and owned
          media through Naturebook&apos;s deletion workflow. If the scan has an
          Explore post, that post and associated engagement are also removed.
          A private, content-free scan identifier may be retained to prevent a
          delayed upload or another device from recreating the deleted scan.
        </Text>
        <Text>
          <strong>Account deletion.</strong> When you delete your account,
          Naturebook deletes your account, profile, authentication record,
          public attribution, community content, avatars, exports, and stored
          scan photos, videos, and audio through a verified deletion process.
          Exact account-linked location, device and semantic-location context,
          free-form notes, and similar identifying fields are removed or
          transformed as part of that process. Deletion may take time to finish
          across active systems, security records, caches, and backups.
        </Text>
        <Text>
          Account deletion does not necessarily delete the scientific fact that
          an observation occurred. Naturebook may retain a reduced,
          ownerless observation record after taking measures designed to make it
          non-personal. That record may retain taxonomy or identification,
          confidence and quality signals, observation time, coarse or
          geoprivacy-projected location, environmental measurements, and
          non-identifying biological facts. It will not remain attributed to
          your deleted account and may continue to be used as Scientific Data
          under Section 11. If a retained record is personal information under
          applicable law, it remains subject to applicable legal rights and
          deletion requirements.
        </Text>
        <Text>
          Naturebook may retain records that applicable law requires, records
          reasonably needed to prevent fraud or abuse or establish legal claims,
          and aggregate or de-identified information that is no longer personal
          information. Account deletion does not cancel an Apple subscription;
          cancel it separately before deletion if you do not want it to renew.
        </Text>
      </LegalSection>

      <LegalSection title="17. Intellectual Property, Feedback, and Complaints">
        <Text>
          The Service, excluding Your Content and separately licensed
          third-party material, is owned by Naturebook or its licensors and is
          protected by intellectual-property laws. Naturebook names, branding,
          interface elements, software, and original content may not be used
          without permission except as these Terms allow.
        </Text>
        <Text>
          If you provide ideas or feedback, you grant Naturebook a perpetual,
          irrevocable, worldwide, royalty-free, transferable, and sublicensable
          license to use them without restriction or compensation. Do not send
          feedback you consider confidential.
        </Text>
        <Text>
          To report claimed copyright or other rights infringement, contact{" "}
          <LegalEmailLink /> with your contact information, identification of
          the protected work, identification and location of the material,
          a good-faith statement explaining the claim, and any other information
          required by applicable law. We may forward a complete complaint to
          the person who submitted the material.
        </Text>
      </LegalSection>

      <LegalSection title="18. Suspension and Termination">
        <Text>
          You may stop using the Service at any time. Naturebook may suspend,
          restrict, or terminate access, remove content, or refuse future
          service if you materially or repeatedly violate these Terms, create
          risk or possible legal exposure, harm people or wildlife, abuse the
          Service, fail to pay applicable charges, or if suspension is
          reasonably needed to protect the Service or comply with law.
        </Text>
        <Text>
          On termination, your app license ends and you must stop using the
          Service. Provisions that by their nature should survive—including
          content and Scientific Data licenses for retained material, payment
          obligations, intellectual-property provisions, disclaimers,
          limitations, indemnity, dispute provisions, and general terms—will
          survive.
        </Text>
      </LegalSection>

      <LegalSection title="19. Service Changes and Changes to These Terms">
        <Text>
          Naturebook may add, change, limit, suspend, or discontinue features,
          plans, models, public routes, pricing, integrations, or the Service.
          Where required, we will provide notice before a material adverse
          change. We may update these Terms as the Service or law changes. The
          updated date will appear above, and we will request renewed acceptance
          for material changes when required. Continued use after an effective
          update constitutes acceptance only to the extent permitted by law.
        </Text>
      </LegalSection>

      <LegalSection title="20. Disclaimers">
        <Text>
          <strong>
            To the fullest extent permitted by law, the Service and all outputs,
            user content, ecological data, and third-party services are provided
            &quot;as is&quot; and &quot;as available,&quot; without warranties
            of any kind, whether express, implied, or statutory, including
            warranties of accuracy, merchantability, fitness for a particular
            purpose, title, non-infringement, availability, security, or freedom
            from harmful code.
          </strong>
        </Text>
        <Text>
          Naturebook does not warrant uninterrupted or error-free operation,
          successful upload or sync, preservation of content, accurate AI
          output, compatibility with every device, or that defects will be
          corrected. You assume the risks of outdoor activity, wildlife
          encounters, terrain, weather, travel, property access, data loss, and
          decisions based on the Service. Some jurisdictions do not allow
          certain warranty exclusions, so some exclusions may not apply to you.
        </Text>
      </LegalSection>

      <LegalSection title="21. Limitation of Liability">
        <Text>
          <strong>
            To the fullest extent permitted by law, Naturebook and its owners,
            affiliates, licensors, service providers, officers, employees,
            contractors, and agents will not be liable for indirect, incidental,
            special, consequential, exemplary, or punitive damages, or for loss
            of data, content, profits, goodwill, use, opportunity, or life-list
            progress, arising from or related to the Service, even if advised
            that such damages were possible.
          </strong>
        </Text>
        <Text>
          To the fullest extent permitted by law, their total aggregate
          liability arising from or related to the Service or these Terms will
          not exceed the greater of US $100 or the amount you paid Naturebook
          for the Service during the 12 months before the event giving rise to
          the claim. These exclusions and cap do not apply to liability that
          cannot legally be excluded or limited, and they do not reduce
          mandatory consumer remedies.
        </Text>
      </LegalSection>

      <LegalSection title="22. Indemnity">
        <Text>
          To the extent permitted by law, you will defend, indemnify, and hold
          harmless Naturebook and its owners, affiliates, licensors, service
          providers, officers, employees, contractors, and agents from
          third-party claims, damages, losses, liabilities, judgments, costs,
          and reasonable legal fees arising from Your Content, your unlawful or
          unauthorized conduct, your material breach of these Terms, or your
          infringement of another person&apos;s rights. Naturebook may control
          the defense of a covered claim, and you will reasonably cooperate.
          This section does not apply where prohibited by mandatory consumer
          law.
        </Text>
      </LegalSection>

      <LegalSection title="23. Apple-Specific Terms">
        <Text>
          If you obtained the app through Apple, you and Naturebook acknowledge
          that these Terms are between you and Naturebook, not Apple, and
          Naturebook—not Apple—is responsible for the app and its content. The
          license is limited to a non-transferable license to use the app on
          Apple-branded products you own or control as permitted by the Apple
          Media Services Usage Rules, including access by associated accounts
          where those rules allow Family Sharing, volume purchasing, or Legacy
          Contacts.
        </Text>
        <LegalList>
          <li>
            Naturebook is responsible for maintenance and support; Apple has no
            obligation to provide either.
          </li>
          <li>
            If the app fails to conform to an applicable warranty, you may
            notify Apple, and Apple may refund the app purchase price, if any.
            To the maximum extent permitted by law, Apple has no other warranty
            obligation, and Naturebook is responsible for other warranty
            claims, losses, liabilities, damages, costs, or expenses.
          </li>
          <li>
            Naturebook, not Apple, is responsible for product-liability,
            regulatory, consumer-protection, privacy, and other claims relating
            to the app or your possession or use of it.
          </li>
          <li>
            Naturebook, not Apple, is responsible for investigating, defending,
            settling, and discharging claims that the app or your use of it
            infringes third-party intellectual-property rights.
          </li>
          <li>
            You represent that you are not located in a region subject to a
            United States government embargo or designated by that government
            as supporting terrorism, and that you are not on a United States
            government prohibited- or restricted-party list.
          </li>
          <li>
            Apple and its subsidiaries are third-party beneficiaries of these
            Terms and may enforce the Apple-specific provisions against you
            after your acceptance.
          </li>
        </LegalList>
      </LegalSection>

      <LegalSection title="24. Governing Law and Disputes">
        <Text>
          Applicable law governs these Terms. A dispute may be brought before a
          court with lawful jurisdiction. Nothing in these Terms deprives you
          of a mandatory right to bring a claim in your home jurisdiction or
          receive the protection of law that cannot be contractually excluded.
          Before filing a claim, you and Naturebook agree to make a reasonable
          good-faith effort to resolve it by contacting the other party, unless
          urgent relief or law makes informal resolution inappropriate.
        </Text>
      </LegalSection>

      <LegalSection title="25. General Terms">
        <Text>
          These Terms, the Privacy Policy, the Community Guidelines when
          applicable, and terms presented in a purchase or feature flow are the
          entire agreement between you and Naturebook regarding the Service. If
          a provision is unenforceable, it will be enforced to the maximum
          lawful extent and the rest will remain effective. A failure to enforce
          a provision is not a waiver. You may not assign these Terms without
          Naturebook&apos;s written consent. Naturebook may assign them in
          connection with a merger, financing, reorganization, sale of assets,
          or transfer of the Service, subject to applicable law.
        </Text>
        <Text>
          Section titles are for convenience only. The word
          &quot;including&quot; means &quot;including without limitation.&quot;
          If these Terms conflict with mandatory law, mandatory law controls.
        </Text>
      </LegalSection>

      <LegalSection title="26. Contact">
        <Text>
          Questions, complaints, claims, analytics objections, or legal notices
          concerning these Terms may be sent to <LegalEmailLink />.
        </Text>
      </LegalSection>
    </LegalPage>
  );
}
