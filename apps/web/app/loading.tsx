import { ExploreSkeleton } from "@/components/ExploreSkeleton";

export default function Loading() {
  return (
    <section
      className="explore-experience explore-experience--canvas"
      role="status"
      aria-label="Loading discoveries"
    >
      <ExploreSkeleton />
      <p className="explore-sr-only">Loading discoveries…</p>
    </section>
  );
}
