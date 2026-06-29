import { NextResponse } from "next/server";
import { isDashboardPinRequired } from "@/lib/dashboardAuth";

export const dynamic = "force-dynamic";

export async function GET() {
  return NextResponse.json({
    pinRequired: isDashboardPinRequired(),
    githubWrites: Boolean(process.env.GITHUB_TOKEN),
  });
}
