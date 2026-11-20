import type { Metadata } from "next";
import { ExploreExperience } from "@/components/ExploreExperience";

export const dynamic = "force-dynamic";
export const metadata: Metadata = {
  title: "Explore nature together",
  description:
    "Explore public nature discoveries from the Naturebook community.",
  alternates: { canonical: "/" },
};

export default function HomePage() {
  return <ExploreExperience initialPage={null} />;
}
