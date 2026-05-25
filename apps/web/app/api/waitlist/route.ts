import { headers } from "next/headers";
import { NextResponse } from "next/server";
import { createServerSupabaseClient } from "@/lib/supabase";

const emailPattern = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

export async function POST(request: Request) {
  let payload: unknown;

  try {
    payload = await request.json();
  } catch {
    return NextResponse.json(
      { message: "Send a valid email address to join the beta list." },
      { status: 400 }
    );
  }

  const email =
    typeof payload === "object" &&
    payload !== null &&
    "email" in payload &&
    typeof payload.email === "string"
      ? payload.email.trim().toLowerCase()
      : "";

  if (!email || !emailPattern.test(email)) {
    return NextResponse.json(
      { message: "Enter a valid email address to join the beta list." },
      { status: 400 }
    );
  }

  const supabase = createServerSupabaseClient();

  if (!supabase) {
    return NextResponse.json(
      { message: "The beta list is not configured yet. Please try again later." },
      { status: 503 }
    );
  }

  const headerStore = await headers();
  const userAgent = headerStore.get("user-agent");

  const { error } = await supabase
    .from("beta_waitlist_signups")
    .upsert(
      {
        email,
        source: "web_waitlist",
        user_agent: userAgent
      },
      {
        onConflict: "email_normalized",
        ignoreDuplicates: true
      }
    );

  if (error) {
    console.error("Failed to add beta waitlist signup", error);

    return NextResponse.json(
      { message: "Could not join the beta list. Please try again." },
      { status: 500 }
    );
  }

  return NextResponse.json({
    message: "You are on the Merian beta list. We will be in touch soon."
  });
}
