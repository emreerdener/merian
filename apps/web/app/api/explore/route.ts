import { NextRequest, NextResponse } from "next/server";
import { decodeExploreCursor } from "@/lib/exploreCursor";
import { fetchExplorePage } from "@/lib/exploreFeed";

export const dynamic = "force-dynamic";
export async function GET(request: NextRequest) {
  const headers = { "Cache-Control": "no-store" };
  let cursor;
  try {
    cursor = decodeExploreCursor(request.nextUrl.searchParams.get("cursor"));
  } catch {
    return NextResponse.json({ error: "Invalid cursor" }, {
      status: 400,
      headers,
    });
  }
  try {
    return NextResponse.json(await fetchExplorePage(cursor), { headers });
  } catch {
    return NextResponse.json({
      error: "Discoveries are temporarily unavailable",
    }, { status: 503, headers });
  }
}
