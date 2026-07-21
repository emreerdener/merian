import { NextResponse } from "next/server";
import { appleAppSiteAssociation } from "@/lib/appleAppSiteAssociation";

export async function GET() {
  return NextResponse.json(appleAppSiteAssociation);
}
