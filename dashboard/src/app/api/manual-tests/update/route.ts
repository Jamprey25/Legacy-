import { NextResponse } from "next/server";
import { authorizeDashboardWrite } from "@/lib/dashboardWriteGuard";
import { readTasksFile, updateManualTest, writeTasksFile } from "@/lib/tasksFile";
import type { ManualTestStatus } from "@/app/types";

export const dynamic = "force-dynamic";

interface UpdateBody {
  testId: string;
  status: ManualTestStatus;
  secret?: string;
}

const VALID: ManualTestStatus[] = ["pending", "passed", "failed"];

export async function POST(request: Request) {
  let body: UpdateBody;
  try {
    body = (await request.json()) as UpdateBody;
  } catch {
    return NextResponse.json({ error: "Invalid JSON body" }, { status: 400 });
  }

  if (!body.testId || !body.status) {
    return NextResponse.json({ error: "testId and status are required" }, { status: 400 });
  }
  if (!VALID.includes(body.status)) {
    return NextResponse.json({ error: "status must be pending, passed, or failed" }, { status: 400 });
  }

  const auth = authorizeDashboardWrite(request as import("next/server").NextRequest, body.secret);
  if (!auth.ok) {
    return NextResponse.json(
      { error: auth.error, retry_after_s: auth.retryAfterS },
      { status: auth.status },
    );
  }

  try {
    const { data: current, sha } = await readTasksFile();
    const { data, test } = updateManualTest(current, body.testId, body.status);
    await writeTasksFile(data, `dashboard: QA ${body.testId} → ${body.status}`, sha);
    return NextResponse.json({ ok: true, test, meta: data.meta });
  } catch (err) {
    const message = err instanceof Error ? err.message : "Failed to update manual test";
    const status = message.includes("not found") ? 404 : 500;
    return NextResponse.json({ error: message }, { status });
  }
}
