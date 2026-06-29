import { NextResponse } from "next/server";
import { readTasksFile } from "@/lib/tasksFile";

export const dynamic = "force-dynamic";

/** Authoritative tasks.json — same source as write APIs (GitHub API or local disk). */
export async function GET() {
  try {
    const { data } = await readTasksFile();
    return NextResponse.json(data);
  } catch (err) {
    const message = err instanceof Error ? err.message : "Failed to read tasks.json";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
