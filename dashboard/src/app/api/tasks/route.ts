import { NextResponse } from "next/server";
import { authorizeDashboardRead } from "@/lib/dashboardAuth";
import { readTasksFile } from "@/lib/tasksFile";

export const dynamic = "force-dynamic";

/** Authoritative tasks.json — same source as write APIs (GitHub API or local disk). */
export async function GET(request: Request) {
  const auth = authorizeDashboardRead(request as import("next/server").NextRequest);
  if (!auth.ok) {
    return NextResponse.json({ error: auth.error }, { status: auth.status });
  }

  try {
    const { data } = await readTasksFile();
    return NextResponse.json(data);
  } catch (err) {
    const message = err instanceof Error ? err.message : "Failed to read tasks.json";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
