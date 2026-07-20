"use client";

import { useRouter } from "next/navigation";
import { useEffect } from "react";

export function AutoRefresh({ milliseconds = 30_000 }: { milliseconds?: number }) {
  const router = useRouter();
  useEffect(() => {
    const timer = window.setInterval(() => router.refresh(), milliseconds);
    return () => window.clearInterval(timer);
  }, [milliseconds, router]);
  return null;
}
