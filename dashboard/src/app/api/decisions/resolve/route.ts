import { NextResponse } from "next/server";
import { authorizeDashboardWrite } from "@/lib/dashboardWriteGuard";
import { readTasksFile, resolveDecision, writeTasksFile } from "@/lib/tasksFile";

export const dynamic = "force-dynamic";

interface ResolveBody {
  decisionId: string;
  optionId: string;
  secret?: string;
}

export async function POST(request: Request) {
  let body: ResolveBody;
  try {
    body = (await request.json()) as ResolveBody;
  } catch {
    return NextResponse.json({ error: "Invalid JSON body" }, { status: 400 });
  }

  if (!body.decisionId || !body.optionId) {
    return NextResponse.json({ error: "decisionId and optionId are required" }, { status: 400 });
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
    const { data, decision } = resolveDecision(current, body.decisionId, body.optionId);
    await writeTasksFile(data, `dashboard: decide ${body.decisionId} → ${body.optionId}`, sha);
    return NextResponse.json({ ok: true, decision, meta: data.meta });
  } catch (err) {
    const message = err instanceof Error ? err.message : "Failed to resolve decision";
    const status = message.includes("not found") || message.includes("Invalid option") ? 400 : 500;
    return NextResponse.json({ error: message }, { status });
  }
}
